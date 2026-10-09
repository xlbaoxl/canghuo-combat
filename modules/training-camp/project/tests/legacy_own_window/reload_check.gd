extends Node
func run(main,output:String):
	await get_tree().process_frame
	var expected=JSON.parse_string(FileAccess.get_file_as_string(output.replace("\\","/")+"/ui-checks.json"))
	var saved=expected.saved
	var errors:Array=[]
	if main.char_id!=saved.char_id or main.slots!=saved.slots or main.artifacts!=saved.artifacts:errors.append("settings did not survive separate process restart")
	if main.snapshot.is_empty():errors.append("original retry snapshot missing")
	else:
		var snapshot=main.snapshot.duplicate(true)
		main.start_snapshot()
		if main.snapshot!=snapshot:errors.append("retry changed immutable snapshot")
		for u in main.battle.state.units:
			if u.H!=u.Hmax or u.E!=u.M:errors.append("retry did not reset health/qi")
	var f=FileAccess.open(output.replace("\\","/")+"/reload-check.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"separate_process":true,"settings_match":errors.is_empty(),"errors":errors,"character":main.char_id,"slots":main.slots},"\t"))
	print("RELOAD_RESULT errors=",errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)
