extends Node
## Exported executable startup/resource/real-executor smoke; no graphics-quality claim.
func run(main,output:String):
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(output)
	var failures=[]
	if not main.catalog.errors.is_empty():failures.append("catalog errors")
	if main.page!="characters" or not main.controls.has("character_C01"):failures.append("startup page unavailable")
	var c=main.catalog
	var l=c.data.loadouts.balanced
	var s=c.snapshot("C01",l.slots,l.artifacts,"mirror","normal")
	if not s.ok:failures.append(s.reason)
	else:
		main.snapshot=s.value.duplicate(true)
		main.start_snapshot()
		var b=main.battle
		var before=b.unit("p").W
		var action={"kind":"artifact","actor":"p","slot":1,"target":"e"}
		var r=b.execute(action)
		if not r.ok or (b.state.current=="p" and b.unit("p").W==before):failures.append("normal Cui action did not close")
		if b.unit("p").stats_log.catalysts!=1:failures.append("independent Cui was not executed")
		if not b.accounting().ok:failures.append("resource accounting")
		main.save_settings()
		if not FileAccess.file_exists(main.SAVE):failures.append("settings write")
	var report={"platform":OS.get_name(),"engine":Engine.get_version_info().string,"rules":c.data.rules,"content":c.digest,"executable":OS.get_executable_path(),"scope":"actual executable startup, resources, scene initialization and a legal normal action; not native graphic input or human playtest","failures":failures}
	FileAccess.open(output.path_join("export-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EXPORT_SMOKE failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
