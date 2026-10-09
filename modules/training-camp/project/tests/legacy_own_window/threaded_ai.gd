extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
func _initialize():call_deferred("run")
func run():
	var c=Catalog.new()
	var results:Array=[]
	var errors:Array=[]
	for profile in ["easy","normal","hard"]:
		var b=Battle.new(c)
		b.start(c.snapshot("C01",c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"mirror","normal").value)
		var before=JSON.stringify(b.state)
		var background=b.fork()
		var direct=b.fork()
		var worker=Thread.new()
		worker.start(func():
			var policy=AI.new()
			return {"action":policy.choose(background,profile),"budget":background.state.ai_budget.p})
		var local_policy=AI.new()
		var expected=local_policy.choose(direct,profile)
		while worker.is_alive():await process_frame
		var actual=worker.wait_to_finish()
		var same=actual.action==expected and actual.budget==direct.state.ai_budget.p
		var isolated=before==JSON.stringify(b.state)
		if not same or not isolated:errors.append(profile)
		results.append({"profile":profile,"same_action_and_budget":same,"real_state_unchanged":isolated})
	var f=FileAccess.open("user://training_camp_v2/checks/threaded-ai.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"results":results,"errors":errors},"\t"))
	print("THREADED_AI_RESULT profiles=3 errors=",errors.size())
	quit(0 if errors.is_empty() else 1)
