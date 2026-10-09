extends Node
## Native Godot input against the real scene (also callable in exported binaries).
var main
var root:String
var checks:Array=[]
var failures:Array=[]
func test(ok:bool,label:String,details=null):
	var item={"label":label,"pass":ok,"details":details}
	checks.append(item)
	var state=main.battle.state if main.battle!=null else {}
	var progress={"label":label,"checks":checks.size(),"failures":failures,"page":main.page,"phase":state.get("phase",""),"current":state.get("current",""),"kind":state.get("window_kind",""),"cursor":main.event_cursor,"events":main.battle.events.size() if main.battle!=null else 0,"thinking":main.thinking()}
	FileAccess.open(root.path_join("ui-progress.json"),FileAccess.WRITE).store_string(JSON.stringify(progress,"\t"))
	if not ok:failures.append(item);push_error("UI_FAIL "+label)
func frames(n:int=3):
	for i in range(n):await get_tree().process_frame
func click_at(point:Vector2,which:int=MOUSE_BUTTON_LEFT):
	var motion=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.button_index=which;e.pressed=down;e.button_mask=(MOUSE_BUTTON_MASK_LEFT if which==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
		Input.parse_input_event(e)
	await frames()
func click(key:String):
	if not main.controls.has(key):test(false,"control exists "+key);return
	var button=main.controls[key]
	test(button.is_visible_in_tree(),"visible "+key)
	await click_at(button.get_global_rect().get_center())
func key(code:int):
	for down in [true,false]:
		var e=InputEventKey.new();e.keycode=code;e.pressed=down;Input.parse_input_event(e)
	await frames()
func capture(name:String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(root.path_join(name+".png"))
func settle_player()->bool:
	for i in range(3000):
		if main.page=="result":return false
		if main.page=="battle" and main.battle.state.current=="p" and main.battle.state.phase=="DECISION" and main.event_cursor>=main.battle.events.size() and main.playback_wait<=0 and not main.thinking():return true
		await frames(1)
	test(false,"player decision reached before timeout");return false
func settle_events():
	for i in range(1500):
		if main.page!="battle" or (main.event_cursor>=main.battle.events.size() and main.playback_wait<=0):return
		await frames(1)
	test(false,"event playback reached boundary")
func abort():
	if main.page!="battle":return
	await click("battle_menu");await click("abort");await click("confirm_abort")
	test(main.page=="result" and main.battle.state.result=="aborted","user abort is not defeat")
func cast(slot:int,target:String):
	await click("skill_"+str(slot));await click_at(main.stage.target_point(target))
func hover(key_name:String):
	var tile=main.controls[key_name]
	var parent=tile.get_parent()
	while parent!=null and not parent is ScrollContainer:parent=parent.get_parent()
	if parent is ScrollContainer:parent.ensure_control_visible(tile);await frames()
	var motion=InputEventMouseMotion.new();motion.position=tile.get_global_rect().get_center();Input.parse_input_event(motion)
	await frames()
func save_report():
	var payload={"engine":Engine.get_version_info().string,"platform":OS.get_name(),"rules":main.catalog.data.rules,"content":main.catalog.digest,"native_control_events":true,"checks":checks,"failures":failures,"inputs":main.inputs,"saved":{"char_id":main.char_id,"slots":main.slots,"artifacts":main.artifacts,"growth_profile":main.growth_profile,"snapshot":main.snapshot}}
	FileAccess.open(root.path_join("ui-checks.json"),FileAccess.WRITE).store_string(JSON.stringify(payload,"\t"))
	print("UPGRADE_UI checks=",checks.size()," failures=",failures.size())

func run(app,output:String):
	main=app;root=output.replace("\\","/");DirAccess.make_dir_recursive_absolute(root)
	await frames(15);await capture("01-characters")
	await click("character_C01");await click("templates");await click("template_balanced")
	await click("profile_base");await click("grade_0")
	test(main.page=="loadout" and main.battle==null,"character then equipment, no premature battle")
	await capture("02-loadout")
	# Native fixed-profile button selects a growth input without changing the library.
	await click("profile_power")
	test(main.growth_profile=="power","growth snapshot chosen through actual widget",main.growth_profile)
	await hover("equip_sword")
	test(main.details.visible and main.details.model.effect.contains("50"),"grown effect shown from live formula",main.details.model)
	await capture("03-growth-tooltip")
	main.hide_details();await click("profile_base")
	test(main.growth_profile=="base","restore base snapshot through native widget")
	# All real book and artifact tooltips remain in the viewport.
	for id in main.catalog.techniques:
		await hover("equip_"+id)
		test(main.details.visible and main.details.model.id==id,"tooltip uses compiled "+id)
		test(main.details.position.y>=0 and main.details.position.y+main.details.size.y<=720,"tooltip height "+id)
	main.hide_details();await click("library_artifacts")
	for id in main.catalog.artifacts:
		await hover("equip_"+id)
		test(main.details.model.type=="法宝" and main.details.model.effect.contains("【自动】") and main.details.model.effect.contains("【催】"),"separate auto and active artifact tooltip "+id)
		test(main.details.body.get_content_height()<=main.details.body.size.y+1,"artifact full description not clipped "+id,{"content":main.details.body.get_content_height(),"height":main.details.body.size.y})
		if id=="talisman":await capture("04-auto-talisman")
		if id=="bell":await capture("04b-bell-auto-cui")
	main.hide_details();await click("library_techniques")
	var equipment=main.slots.duplicate(true)
	await click("enter");test(main.modal!=null and main.battle==null,"enter opens mode selection only")
	await capture("05-mode-selector");await click("selector_back")
	test(main.slots==equipment and main.modal==null,"T60 cancel retains preparation")
	await click("slot_0");await hover("equip_sword");main.hide_details();await click("equip_sword")
	await click("enter");await click("mode_mirror");await click("choice_easy");main.speed=0;await click("start")
	if not await settle_player():save_report();get_tree().quit(1);return
	test(main.snapshot.units[1].slots[0]=="sword" and main.snapshot.choice=="easy","T60 latest loadout copied by mirror")
	test(main.controls.has("passive_0") and main.controls.has("active_0"),"separate inspect-only auto and active Cui UI")
	var passive_before=main.battle.public_hash()
	await click("passive_1")
	test(main.selected_action.is_empty() and main.battle.public_hash()==passive_before,"CU20 clicking auto icon cannot cast anything")
	await hover("active_1")
	test(main.details.model.title.ends_with("·催") and main.details.model.cost==16 and main.details.model.effect.contains("29"),"CU20 active hover uses independent effect and real cost")
	await capture("06a-cui-tooltip");main.hide_details()
	await click("active_1")
	test(main.selected_action.get("kind","")=="artifact" and main.battle.public_hash()==passive_before,"CU20 active click selects without paying until target confirmation")
	await click_at(Vector2(1035,540),MOUSE_BUTTON_RIGHT)
	test(main.selected_action.is_empty() and main.battle.public_hash()==passive_before,"CU20 cancelling Cui selection does not cast auto or spend")
	test(main.stage.diorama.cell_meshes.size()==18,"existing nine-per-side stage retained")
	await capture("06-normal-battle")
	# Protect in ordinary turns until the independently accumulated opportunity occurs.
	var saw_burst=false
	for step in range(8):
		if main.page!="battle":break
		if main.battle.state.window_kind=="OPPORTUNITY":saw_burst=true;break
		var W=main.battle.unit("p").W
		await cast(2,"p")
		test(main.battle.unit("p").W>=W and not (main.battle.state.current=="p" and main.battle.unit("p").W==W),"T01 native normal main closes")
		if not await settle_player():break
	test(saw_burst,"T62 natural ordinary-to-opportunity flow without injected gauge")
	if saw_burst:
		await capture("07-opportunity")
		var W=main.battle.unit("p").W;var R=main.battle.unit("p").R
		await hover("skill_3")
		var expected=main.battle.fork().execute({"kind":"cast","actor":"p","slot":3,"target":"p"})
		test(main.details.model.after==expected.after_effect_E,"supply hover uses actual immediate post-action qi")
		main.hide_details();await cast(3,"p");await settle_events()
		await cast(0,"e");await settle_events()
		test(main.battle.unit("p").W==W and main.battle.unit("p").R==R and main.controls.skill_0.disabled,"T03 two native burst skills same window, spent entry disabled")
		var auto_count=main.battle.events.filter(func(e):return e.event_type=="AUTOMATIC_TRIGGERED" and e.owner_id=="p").size()
		var qi_before=main.battle.unit("p").E
		await click("active_0");await click_at(main.stage.target_point("p"));await settle_events()
		test(main.battle.unit("p").E==qi_before-10 and main.battle.unit("p").W==W and main.controls.active_0.disabled,"CU21 native Cui pays own cost and locks only own burst entry")
		test(main.battle.events.filter(func(e):return e.event_type=="AUTOMATIC_TRIGGERED" and e.owner_id=="p").size()==auto_count,"CU21 native Cui never replays automatic effect")
		await capture("07a-cui-after-use")
		await click("pause");var frozen=main.battle.public_hash();await frames(12)
		test(main.battle.public_hash()==frozen,"T59 pause freezes logic")
		await click("pause")
		await click_at(main.controls.skill_2.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT)
		await click("swap_2");await hover("swap_to_heal")
		test(main.details.model.availability.contains("最早"),"swap states actual earliest window")
		await click("swap_to_heal");await settle_events()
		test(main.battle.unit("p").slots[2]=="heal" and main.battle.unit("p").swap_used,"native swap works once")
		await capture("08-burst-after-actions")
	var original=main.snapshot.duplicate(true)
	await abort();await capture("09-result")
	test(main.battle.accounting().ok,"T51/T52 final result accounting",main.battle.accounting())
	await click("retry");await settle_player()
	test(main.snapshot==original and main.battle.unit("p").slots[2]=="guard","T60 retry original not final loadout")
	await abort();await click("reselect");await click("mode_preset");await click("choice_P01")
	await capture("10-preset-selection");await click("start");await settle_player()
	test(main.snapshot.mode=="preset" and main.snapshot.units[1].stats.Hmax==240,"preset own small-scale stats")
	# Native controls drive a complete non-injected opponent battle; AI can finish it.
	await click("auto");main.speed=0
	for i in range(9000):
		if main.page=="result":break
		await frames(1)
	test(main.page=="result","T62 complete battle reaches result")
	if main.page=="result":
		test(main.battle.accounting().ok,"complete automated battle reconciles")
		await capture("11-completed-battle")
		FileAccess.open(root.path_join("completed-battle.json"),FileAccess.WRITE).store_string(JSON.stringify({"snapshot":main.snapshot,"state":main.battle.state,"events":main.battle.events,"accounting":main.battle.accounting()},"\t"))
		await click("edit");test(main.page=="loadout","T62 result returns to preparation")
	# A real worker return is invalidated by pause, even when its job finishes.
	await click("enter");await click("mode_mirror");await click("choice_hard");await click("start");await settle_player()
	await click("end_window")
	var worker_seen=false
	for i in range(1500):
		if main.thinking():worker_seen=true;break
		if main.page!="battle":break
		await frames(1)
	if worker_seen:
		await click("pause");var stable=main.battle.public_hash();await frames(30)
		test(main.battle.public_hash()==stable and main.ai_pending.is_empty(),"T59 outdated worker does not commit after pause")
		await capture("12-paused-worker");await click("pause")
	else:test(false,"actual hard worker observed")
	await abort();await click("edit");main.save_settings()
	save_report()
	get_tree().quit(0 if failures.is_empty() else 1)
