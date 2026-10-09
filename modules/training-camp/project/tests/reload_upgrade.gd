extends Node
func run(main,output:String):
	await get_tree().process_frame
	var expected=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("ui-checks.json"))).saved
	var failures=[]
	if main.char_id!=expected.char_id or main.slots!=expected.slots or main.artifacts!=expected.artifacts or main.growth_profile!=expected.growth_profile:failures.append("saved preparation differs")
	if main.snapshot.is_empty() or main.snapshot!=expected.snapshot:failures.append("frozen snapshot differs")
	else:
		var snap=main.snapshot.duplicate(true)
		main.start_snapshot()
		if main.snapshot!=snap:failures.append("retry mutated snapshot")
		if not main.battle.accounting().ok:failures.append("initial retry accounting")
	var result={"separate_process":true,"platform":OS.get_name(),"failures":failures,"settings_match":failures.is_empty()}
	FileAccess.open(output.path_join("reload-check.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("UPGRADE_RELOAD failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
