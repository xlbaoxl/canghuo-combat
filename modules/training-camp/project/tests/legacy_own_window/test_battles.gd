extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
var c=Catalog.new()
var rows:Array=[]
var errors:Array=[]
var timings:Array=[]
var development:Array=[]
var retained:Array=[]

func _initialize():call_deferred("run")

func duel(snapshot:Dictionary,player_ai:String,enemy_ai:String,label:String)->Dictionary:
	var b=Battle.new(c)
	b.start(snapshot)
	var ai=AI.new()
	var steps=0
	var illegal:Array=[]
	var peak_events=0
	var peak_nodes=0
	var downgraded=0
	while not b.state.ended and steps<2000:
		var id=b.state.current
		var profile=player_ai if id=="p" else enemy_ai
		var a=ai.choose(b,profile,id)
		if profile=="hard":
			timings.append(ai.last_trace.elapsed_us)
			peak_events=maxi(peak_events,int(ai.last_trace.events))
			peak_nodes=maxi(peak_nodes,int(ai.last_trace.nodes))
			if ai.last_trace.truncated:downgraded+=1
		var result=b.execute(a)
		if not result.ok:
			illegal.append(result.reason)
			break
		steps+=1
	if steps>=2000:illegal.append("safety action ceiling")
	var units:Array=[]
	for u in b.state.units:units.append({"id":u.id,"H":u.H,"E":u.E,"W":u.W,"stats":u.stats_log,"slots":u.slots})
	var row={"label":label,"snapshot":snapshot,"player_ai":player_ai,"enemy_ai":enemy_ai,"result":b.state.result,"reason":b.state.reason,"ticks":b.state.t,"actions":steps,"units":units,"illegal":illegal,"peak_events":peak_events,"peak_nodes":peak_nodes,"truncated_decisions":downgraded}
	if not illegal.is_empty():errors.append(label+": "+str(illegal))
	if peak_events>30000 or peak_nodes>256:errors.append(label+": budget exceeded")
	return row

func run():
	var profiles=[["easy","normal"],["easy","hard"],["normal","hard"]]
	# Fixed public input corpus: no random reruns counted as independent evidence.
	for char in c.data.characters:
		for loadout_id in c.data.loadouts:
			var l=c.data.loadouts[loadout_id]
			for first in [true,false]:
				for pair in profiles:
					var order=["p","e"] if first else ["e","p"]
					var s=c.snapshot(char.id,l.slots,l.artifacts,"mirror","normal",103,order)
					if not s.ok:errors.append(char.id+loadout_id+": "+s.reason);continue
					var label="pure-ai/%s/%s/%s/%s-%s"%[char.id,loadout_id,str(first),pair[0],pair[1]]
					rows.append(duel(s.value,pair[0],pair[1],label))
					print("DUEL %d %s %s t%d"%[rows.size(),label,rows.back().result,rows.back().ticks])
	for char in c.data.characters:
		for d in c.data.difficulties:
			var l=c.data.loadouts.balanced
			var s=c.snapshot(char.id,l.slots,l.artifacts,"mirror",d.id)
			development.append(duel(s.value,"normal",d.ai,"joint-mirror/"+char.id+"/"+d.id))
		for e in c.data.enemies:
			var l=c.data.loadouts.balanced
			var s=c.snapshot(char.id,l.slots,l.artifacts,"preset",e.id)
			development.append(duel(s.value,"normal",e.ai,"preset/"+char.id+"/"+e.id))
	# A held-out legal configuration is not in the three tuning templates.
	for char in c.data.characters:
		for d in c.data.difficulties:
			var s=c.snapshot(char.id,["sword_echo","calm","guard_spring","qi_flow"],["robe","talisman"],"mirror",d.id,803)
			retained.append(duel(s.value,"normal",d.ai,"held-out/"+char.id+"/"+d.id))
	var stat_base=c.snapshot("C01",["sword_deep","guard","heal","qi"],[],"mirror","normal").value
	var stat_strong=stat_base.duplicate(true)
	stat_strong.units[0].stats.Hmax=4500
	retained.append(duel(stat_base,"normal","normal","numbers/H3000"))
	retained.append(duel(stat_strong,"normal","normal","numbers/H4500"))
	timings.sort()
	var p95=timings[int(timings.size()*0.95)] if not timings.is_empty() else 0
	var dir="user://training_camp_v2/checks"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f=FileAccess.open(dir+"/battles.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"rules":c.data.rules,"content":c.data.version,"pure_ai":rows,"joint_and_preset":development,"held_out_and_numbers":retained,"errors":errors,"hard_p95_us":p95,"hard_max_us":timings.back() if not timings.is_empty() else 0},"\t"))
	print("BATTLES_RESULT pure=%d joint=%d held=%d errors=%d hard_p95_ms=%.2f"%[rows.size(),development.size(),retained.size(),errors.size(),float(p95)/1000])
	quit(0 if errors.is_empty() else 1)
