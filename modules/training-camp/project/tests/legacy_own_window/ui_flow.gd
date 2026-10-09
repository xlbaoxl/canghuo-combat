extends Node
var main
var root:String
var checks:Array=[]
var failures:Array=[]

func test(ok:bool,description:String):
	checks.append(description)
	if not ok:failures.append(description);push_error("UI_FAIL "+description)

func wait_frames(n:int=3):
	for i in range(n):await get_tree().process_frame

func click_at(p:Vector2,mouse_button:int=MOUSE_BUTTON_LEFT):
	var move=InputEventMouseMotion.new()
	move.position=p
	Input.parse_input_event(move)
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p
		e.button_index=mouse_button
		e.button_mask=(MOUSE_BUTTON_MASK_LEFT if mouse_button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
		e.pressed=down
		Input.parse_input_event(e)
	await wait_frames()

func click(key:String):
	if not main.controls.has(key):test(false,"Missing control "+key);return
	var b=main.controls[key]
	test(is_instance_valid(b) and b.is_visible_in_tree(),"Visible "+key)
	await click_at(b.get_global_rect().get_center())

func capture(name:String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(root+"/"+name+".png")

func idle():
	main.speed=0
	var ticks=0
	while main.page=="battle" and (main.event_cursor<main.battle.events.size() or main.playback_wait>0) and ticks<200:
		await get_tree().process_frame
		ticks+=1
	await wait_frames()

func abort():
	await click("battle_menu")
	await click("abort")
	await click("confirm_abort")
	test(main.page=="result" and main.battle.state.result=="aborted","Abort distinct from defeat")

func run(app,output:String):
	main=app
	root=output.replace("\\","/")
	DirAccess.make_dir_recursive_absolute(root)
	await wait_frames(15)
	await capture("01-characters")
	await click("character_C01")
	await click("templates")
	await click("template_balanced")
	await library_checks()
	await capture("02-loadout")
	var before=main.slots.duplicate(true)
	await click("enter")
	test(main.page=="loadout" and main.modal!=null and main.battle==null,"Entry opens selector without battle or entry effects")
	await capture("03-mirror-selection")
	await click("selector_back")
	test(main.modal==null and before==main.slots,"Cancel preserves equipment")
	await click("slot_0")
	await click("equip_sword")
	test(main.slots[0]=="sword","Library hit test equips into selected slot")
	await click("enter")
	await click("mode_mirror")
	await click("choice_easy")
	main.speed=1
	await click("start")
	await progress_checks()
	await idle()
	test(main.battle.unit("e").slots[0]=="sword" and main.snapshot.choice=="easy","Changed loadout cloned at confirmation")
	await battle_checks()
	await capture("04-battle")
	var p=main.battle.unit("p")
	var old_E=p.E
	await click("skill_0")
	test(main.stage.diorama.cell_meshes.size()==18,"Legacy stone model: nine cells on each side")
	await click_at(main.stage.target_point("e"))
	await idle()
	test(main.battle.unit("p").E<old_E and main.battle.unit("p").entries[0].used,"Target click submits once and pays real resources")
	test(main.controls.skill_0.spent and main.controls.skill_0.disabled,"Used skill visibly dims after actual cast")
	await hover("skill_3")
	var simulated=main.battle.fork()
	var qi_action={"kind":"cast","actor":"p","slot":3,"target":"p"}
	var result=simulated.execute(qi_action)
	test(result.ok and main.details.model.after==simulated.unit("p").E,"Qi recovery hover includes actual self recovery after paying cost")
	await capture("05b-qi-recovery-hover")
	main.hide_details()
	await capture("05-action-receipt")
	var snap=main.snapshot.duplicate(true)
	await click_at(main.controls.skill_2.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT)
	await click("swap_2")
	await click("swap_to_heal")
	await idle()
	test(main.battle.unit("p").slots[2]=="heal","Battle swap uses actual controls")
	await abort()
	await capture("06-result")
	await click("retry")
	await idle()
	test(main.snapshot==snap and main.battle.unit("p").slots[2]=="guard","Retry original frozen loadout, not final swap")
	await abort()
	await click("reselect")
	await click("mode_preset")
	await capture("07-preset-selection")
	await click("choice_P01")
	await click("start")
	await idle()
	test(main.snapshot.mode=="preset" and main.snapshot.units[1].stats.Hmax==2400,"Preset doesn't inherit mirror multiplier")
	await capture("08-beast-battle")
	await abort()
	await capture("08b-beast-result")
	await click("edit")
	await buff_battle_checks()
	# Test actual GUI routing of every start combination; semantic results are in core tests.
	for char in main.catalog.data.characters:
		for mode in ["mirror","preset"]:
			var options=main.catalog.data.difficulties if mode=="mirror" else main.catalog.data.enemies
			for option in options:
				await click("back_characters")
				await click("character_"+char.id)
				await click("templates")
				await click("template_balanced")
				await click("enter")
				await click("mode_"+mode)
				await click("choice_"+option.id)
				await click("start")
				await idle()
				test(main.page=="battle" and main.snapshot.units[0].id==char.id and main.snapshot.mode==mode and main.snapshot.choice==option.id,"24-start "+char.id+mode+option.id)
				await abort()
				await click("edit")
	# Native controls activate automatic normal policy and finish a complete game.
	await click("back_characters")
	await click("character_C01")
	await click("enter")
	await click("mode_mirror")
	await click("choice_normal")
	await click("start")
	await idle()
	await click("auto")
	var frames=0
	while main.page=="battle" and frames<3000:await get_tree().process_frame;frames+=1
	test(main.page=="result" and main.battle.state.result in ["player","enemy","draw"],"Complete native game finishes with actual outcome")
	await capture("09-complete-result")
	await click("reselect")
	await click("mode_mirror")
	await click("choice_hard")
	await click("start")
	await idle()
	await click("auto")
	frames=0
	while main.page=="battle" and (main.ai_worker==null or main.battle.state.current=="p") and frames<1000:
		await get_tree().process_frame;frames+=1
	test(main.page=="battle" and main.ai_worker!=null,"Hard AI runs in background while native window remains active")
	if main.page=="battle":
		await click("pause")
		var t=main.battle.state.t
		var process_frames=Engine.get_process_frames()
		await wait_frames(8)
		test(main.paused and main.battle.state.t==t and Engine.get_process_frames()>process_frames+6,"Actual pause input works during background search and freezes real combat")
		await capture("09b-hard-paused")
		await click("pause")
	frames=0
	while main.page=="battle" and frames<5000:await get_tree().process_frame;frames+=1
	test(main.page=="result" and main.battle.state.result in ["player","enemy","draw","undecided"],"Complete threaded hard battle uses real outcome")
	var threaded=false
	for trace in main.battle.state.ai_traces:
		if trace.profile=="hard" and trace.get("background",false):threaded=true
	test(threaded,"Hard decision traces are integrated from isolated worker")
	await capture("09c-hard-result")
	await click("edit")
	await click("save")
	await capture("10-saved-loadout")
	var f=FileAccess.open(root+"/ui-checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"Native Godot mouse input events through real controls; no physical desktop input in this revision","checks":checks,"failures":failures,"count":checks.size(),"inputs":main.inputs,"saved":{"char_id":main.char_id,"slots":main.slots,"artifacts":main.artifacts}},"\t"))
	print("NATIVE_UI_RESULT checks=%d failures=%d"%[checks.size(),failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func hover(key:String):
	var e=InputEventMouseMotion.new();e.position=main.controls[key].get_global_rect().get_center();Input.parse_input_event(e)
	await wait_frames(3)

func library_checks():
	for grade in range(1,4):
		await click("grade_"+str(grade))
		var count=0
		for key in main.controls:
			if key.begins_with("equip_"):
				var tile=main.controls[key];count+=1
				test(tile.card and tile.artwork!=null and tile.grade==grade,"Book artwork and correct grade "+key)
		test(count>0,"Nonempty grade "+str(grade))
	await click("grade_0")
	await hover("equip_ember")
	test(main.details.visible and main.details.model.effect.contains("650") and main.details.model.effect.contains("侵袭"),"Immediate book hover describes actual attack and debuff")
	test(main.details.body.get_parsed_text().contains("CD") and not main.details.body.get_parsed_text().contains("句"),"Player tooltip presents CD without sentence counts")
	await capture("02b-book-hover")
	main.hide_details()
	await glossary_library_checks()

func progress_checks():
	var frames=0
	while main.hud.timeline.target.get("p",0.0)<=0 and frames<60:
		await get_tree().process_frame;frames+=1
	var before=main.hud.timeline.displayed.duplicate()
	await wait_frames(2)
	test(main.hud.timeline.displayed!=before,"Actual clock receipts visibly interpolate initiative")
	await capture("03b-initiative-moving")
	await click("pause")
	var progress=main.hud.timeline.displayed.duplicate()
	var cursor=main.event_cursor
	await wait_frames(8)
	test(main.hud.timeline.displayed==progress and main.event_cursor==cursor,"Pause freezes displayed initiative and playback")
	await click("pause")

func battle_checks():
	test(not main.hud.inspector.visible and not main.hud.menu.visible,"Battle opens with character info and menu collapsed")
	test(main.hud.enemy_health.quantized and main.hud.enemy_health.lit_segments==10,"Enemy uses ten quantized health segments")
	test(not main.hud.enemy_badge.text.contains(str(main.battle.unit("e").H)),"Default enemy name has no exact health")
	test(main.hud.player_values.text.contains(str(main.battle.unit("p").E)),"Own qi remains visible in real time")
	await hover("skill_0")
	var v=main.catalog.techniques[main.battle.unit("p").entries[0].technique]
	var cost=main.battle.costs(main.battle.unit("p"),v)
	test(main.details.visible and main.details.model.cost==cost.qi and main.details.model.after==maxi(0,main.battle.unit("p").E-cost.qi),"Hover shows executor cost and correct qi remaining after cast")
	test(main.hud.mana_preview.visible and main.hud.preview_cost==cost.qi,"Hover overlays real qi expenditure on own bar")
	var text=main.details.body.get_parsed_text()
	for forbidden in ["句","回转","公共刻","W"]:test(not text.contains(forbidden),"Tooltip omits backend wording "+forbidden)
	test(main.details.body.get_content_height()<=main.details.body.size.y+2,"Entire skill tooltip fits without hidden text")
	await capture("04b-skill-hover")
	await click_at(main.stage.target_point("e"))
	test(main.hud.inspector.visible and main.hud.inspected=="e" and main.hud.inspector_body.text.contains("灵气"),"Click opponent expands full demo information")
	await capture("04c-enemy-inspected")
	await click("inspector_close")
	test(not main.hud.inspector.visible,"Enemy details collapse after close")
	test(main.hud.own_buff_root.get_child_count()>0 and not main.controls.player_hp.text.contains("护体"),"Shield shown in Buff strip rather than base health stats")
	test(main.hud.timeline.active=="p" and not main.controls.skill_0.disabled and main.controls.skill_0.size.x<=58,"Player action state has lit compact available icon")
	var health=main.hud.enemy_health
	for sample in [[51,10,"75bc82"],[50,5,"e2c66a"],[20,2,"e2c66a"],[19,2,"d96b64"],[0,0,"d96b64"]]:
		health.set_health(sample[0],100)
		test(health.tint==Color(sample[2]) and health.lit_segments==sample[1] if sample[0]!=51 else health.tint==Color(sample[2]) and health.lit_segments==6,"Health threshold and quantization "+str(sample[0]))
	main.update_battle_hud()
	# One actor and multiple actors use the same actual-row widget, no assumed alternation.
	var timeline=preload("res://scripts/ui/initiative.gd").new();add_child(timeline)
	var row=main.visual_rows[0].duplicate(true)
	timeline.set_view([row],"p",false)
	test(timeline.rows.size()==1 and timeline.target.has("p"),"Single actor initiative row")
	timeline.set_view(main.visual_rows,"p",false)
	test(timeline.rows.size()==2 and timeline.target.has("e"),"Two actor initiative rows")
	timeline.queue_free()
	main.hide_details()

func glossary_library_checks():
	for tab in ["techniques","artifacts"]:
		await click("library_"+tab)
		var dictionary=main.catalog.techniques if tab=="techniques" else main.catalog.artifacts
		for id in dictionary:
			var tile=main.controls["equip_"+id]
			var scroll=tile.get_parent().get_parent()
			scroll.ensure_control_visible(tile)
			await wait_frames(2)
			await hover("equip_"+id)
			test(main.details.visible and main.details.model.id==id,"Actual hover on "+tab+"/"+id)
			var text=main.details.body.get_parsed_text()
			for row in main.details.model.buff_details:
				test(text.contains(row.name+"：") and text.contains(row.effect),"Named Buff definition in hover "+id+"/"+row.name)
			test(not text.contains("可以施展") and not text.contains("点图标") and not text.contains("再点目标"),"No operation guidance in tooltip "+id)
			test(main.details.body.get_content_height()<=main.details.body.size.y+2 and main.details.get_global_rect().end.y<=709,"Complete tooltip and Buff glossary fit "+id)
			if id=="pressure":await capture("02c-pressure-book-hover")
			elif id=="heal_clean":await capture("02d-cleanse-book-hover")
			elif id=="bell":await capture("02e-bell-hover")
	await click("library_techniques")
	main.hide_details()

func buff_battle_checks():
	await click("slot_3")
	var tile=main.controls.equip_pressure
	tile.get_parent().get_parent().ensure_control_visible(tile)
	await wait_frames(2)
	await click("equip_pressure")
	await click("enter")
	await click("mode_preset")
	await click("choice_P02")
	await click("start")
	await idle()
	await hover("skill_3")
	var model=main.details.model
	var text=main.details.body.get_parsed_text()
	test(model.id=="pressure" and model.effect=="给敌方附加55层逆气、35层滞气与5层蚀骨。","Pressure upper section describes only its actual applications")
	test(model.buff_details.size()==3 and text.contains("逆气：") and text.contains("滞气：") and text.contains("蚀骨："),"Pressure lower section contains all three named Buff definitions")
	test(not text.contains("可以施展") and not text.contains("点图标"),"Ready battle tooltip excludes operation hint")
	test(model.cost==300 and model.after==1300 and main.hud.preview_cost==300,"Buff glossary preserves actual payment preview")
	test(main.details.body.get_content_height()<=main.details.body.size.y+2,"Three Buff descriptions remain fully visible in battle")
	await capture("11-pressure-battle-hover")
	main.hide_details()
	await abort()
	await click("edit")
	await click("templates")
	await click("template_balanced")
