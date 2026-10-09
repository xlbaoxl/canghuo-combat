extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
var c=Catalog.new()
var results:Array=[]
var failures:Array=[]
var elapsed:Array=[]
var output:String
func _initialize():call_deferred("run")
func fight(snapshot:Dictionary,player_ai:String,label:String)->void:
	var b=Battle.new(c)
	var start=b.start(snapshot)
	if not start.ok:failures.append({"label":label,"reason":start.reason});return
	var policy=AI.new();var actions=0;var illegal=0;var overbudget=0;var mismatches=0;var truncated=0;var complete=0
	var begin=Time.get_ticks_msec()
	while not b.state.ended and actions<1600:
		var actor=str(b.state.current)
		var profile=player_ai if actor=="p" else snapshot.enemy_ai
		var a=policy.choose(b,profile)
		elapsed.append(int(policy.last_trace.elapsed_us))
		if policy.last_trace.truncated:truncated+=1
		if policy.last_trace.get("coverage_complete",false):complete+=1
		if policy.last_trace.events>int(c.data.ai.window_events)+512 or policy.last_trace.nodes>int(c.data.ai.nodes):overbudget+=1
		if not b.legal(a).ok:illegal+=1;break
		var expected=b.fork();var preview=expected.execute(a)
		var actual=b.execute(a)
		if not actual.ok or not preview.ok or b.public_hash()!=expected.public_hash():mismatches+=1;break
		if not b.accounting().ok:mismatches+=1;break
		actions+=1
	var row={"label":label,"snapshot":snapshot,"player_ai":player_ai,"enemy_ai":snapshot.enemy_ai,"result":b.state.result,"reason":b.state.reason,"ticks":b.state.t,"actions":actions,"illegal":illegal,"budget_overruns":overbudget,"state_or_accounting_mismatches":mismatches,"truncated_decisions":truncated,"complete_hard_comparisons":complete,"wall_ms":Time.get_ticks_msec()-begin,"units":[],"accounting":b.accounting()}
	for u in b.state.units:row.units.append({"id":u.id,"H":u.H,"E":u.E,"R":u.R,"W":u.W,"Z":u.Z,"stats":u.stats_log})
	if illegal>0 or overbudget>0 or mismatches>0 or not b.state.ended:failures.append(row)
	results.append(row)
	if label in ["C01-mirror-hard","C01-preset-P01","C01-preset-P03"]:
		FileAccess.open(output.path_join(label+"-trace.json"),FileAccess.WRITE).store_string(JSON.stringify({"snapshot":snapshot,"state":b.state,"events":b.events},"\t"))
	FileAccess.open(output.path_join("battles-progress.json"),FileAccess.WRITE).store_string(JSON.stringify({"completed":results.size(),"results":results,"failures":failures},"\t"))
	print("MATCH ",results.size()," ",label," ",b.state.result," ticks=",b.state.t," actions=",actions," errors=",illegal+overbudget+mismatches)
func run():
	output=OS.get_environment("UPGRADE_VERIFY_DIR")
	if output.is_empty():output="user://upgrade_verification"
	DirAccess.make_dir_recursive_absolute(output)
	for char in c.data.characters:
		for difficulty in c.data.difficulties:
			fight(c.snapshot(char.id,c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"mirror",difficulty.id).value,"normal",char.id+"-mirror-"+difficulty.id)
		for enemy in c.data.enemies:
			fight(c.snapshot(char.id,c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"preset",enemy.id).value,"normal",char.id+"-preset-"+enemy.id)
	for loadout_id in c.data.loadouts:
		var loadout=c.data.loadouts[loadout_id]
		for pair in [["easy","normal"],["easy","hard"],["normal","hard"]]:
			for order in [["p","e"],["e","p"]]:
				var snapshot=c.snapshot("C01",loadout.slots,loadout.artifacts,"mirror","normal",103,order).value
				snapshot.enemy_ai=pair[1]
				fight(snapshot,pair[0],loadout_id+"-"+pair[0]+"-"+pair[1]+"-first-"+order[0])
	for profile in ["base","power","expert"]:
		for scale in [100,150]:
			var snapshot=c.snapshot("C01",c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"preset","P03",103,["p","e"],profile).value
			snapshot.units[0].stats.Hmax=snapshot.units[0].stats.Hmax*scale/100
			fight(snapshot,"normal","growth-"+profile+"-H"+str(scale))
	elapsed.sort()
	var p95=elapsed[int((elapsed.size()-1)*0.95)] if not elapsed.is_empty() else 0
	var payload={"rules":c.data.rules,"content":c.digest,"engine":Engine.get_version_info().string,"platform":OS.get_name(),"sample_design":"24 startup combinations + 18 same-panel strategy pairs + 6 explicit growth/H comparisons; deterministic scenarios, not a human win-rate estimate and no duplicate random seeds claimed independent","count":results.size(),"failures":failures,"decision_timing_us":{"p95":p95,"max":elapsed.back() if not elapsed.is_empty() else 0,"samples":elapsed.size(),"note":"local software-rendering/native UI may be concurrent, not controlled cross-machine performance"},"results":results}
	FileAccess.open(output.path_join("battles.json"),FileAccess.WRITE).store_string(JSON.stringify(payload,"\t"))
	print("UPGRADE_BATTLES count=",results.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
