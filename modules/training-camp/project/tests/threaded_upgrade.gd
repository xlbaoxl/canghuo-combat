extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
var results=[]
var failures=[]
func _initialize():call_deferred("run")
func run():
	var c=Catalog.new()
	for profile in ["easy","normal","hard"]:
		for kind in ["NORMAL","OPPORTUNITY"]:
			var b=Battle.new(c);b.start(c.snapshot("C01",c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"mirror","normal").value)
			if kind=="OPPORTUNITY":
				b.close_window(false);b.unit("p").Z=100;b.qualify_opportunities();b.advance()
			var baseline=b.public_hash()
			var direct=b.fork();var isolated=b.fork();var ai=AI.new();var expected=ai.choose(direct,profile)
			var thread=Thread.new()
			var result=thread.start(func():
				var policy=AI.new();var chosen=policy.choose(isolated,profile)
				return {"choice":chosen,"budget":isolated.state.ai_budget.p,"trace":policy.last_trace})
			if result!=OK:failures.append("thread failed");continue
			while thread.is_alive():await process_frame
			var response=thread.wait_to_finish()
			var ok=response.choice==expected and b.public_hash()==baseline and response.budget==direct.state.ai_budget.p
			results.append({"profile":profile,"window_kind":kind,"same_decision_budget":ok,"real_state_unchanged":b.public_hash()==baseline})
			if not ok:failures.append(results.back())
	var folder=OS.get_environment("UPGRADE_VERIFY_DIR")
	if folder.is_empty():folder="user://upgrade_verification"
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("threaded-ai.json"),FileAccess.WRITE).store_string(JSON.stringify({"results":results,"failures":failures},"\t"))
	print("UPGRADE_THREADS cases=",results.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
