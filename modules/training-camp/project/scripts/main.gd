extends Control
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
const Stage=preload("res://scripts/stage.gd")
const P=preload("res://scripts/presentation.gd")
const Tile=preload("res://scripts/ui/skill_tile.gd")
const DetailPopup=preload("res://scripts/ui/detail_popup.gd")
const BattleHud=preload("res://scripts/ui/battle_hud.gd")
const SAVE="user://training_camp_v3/settings.json"
const Protocol=preload("res://scripts/combat_protocol.gd")
const Math=preload("res://scripts/effect_math.gd")
var growth_profile:String="base"
var disabled_artifacts:Array=[]
var visual_kind:String=""
var decision_epoch:int=0
var migration_notice:String=""
var catalog=Catalog.new()
var ai=AI.new()
var battle
var page:String="characters"
var char_id:String="C01"
var slots:Array=["sword_deep","ember","guard","qi"]
var artifacts:Array=["jade","blade"]
var selected_slot:int=0
var library_tab:String="techniques"
var favorites:Array=[]
var saved_presets:Array=[]
var mode:String="mirror"
var choice:String="normal"
var mirror_choice:String="normal"
var preset_choice:String="P01"
var seed:int=103
var snapshot:Dictionary={}
var preview_hash:String=""
var modal:Control
var canvas:Control
var stage
var selected_action:Dictionary={}
var controls:Dictionary={}
var log_open:bool=false
var event_cursor:int=0
var playback_wait:float=0
var speed:int=1
var paused:bool=false
var autoplay:bool=false
var last_notice:String=""
var inputs:Array=[]
var sound:AudioStreamPlayer
var native_check_root:String=""
var ai_worker:Thread
var ai_pending:Dictionary={}
var battle_generation:int=0
var hud
var details
var hover_action_data:Dictionary={}
var hover_rect:Rect2
var visual_rows:Array=[]
var visual_current:String=""
var grade_filter:int=0

func _ready()->void:
	get_viewport().gui_embed_subwindows=true
	Engine.max_fps=30
	get_window().unresizable=true
	get_window().content_scale_size=Vector2i(1280,720)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	var font=FontVariation.new()
	font.base_font=load("res://assets/fonts/NotoSansSC.ttf")
	font.variation_embolden=0.4
	theme=Theme.new()
	theme.default_font=font
	theme.default_font_size=16
	for type in ["Button","OptionButton"]:
		theme.set_stylebox("normal",type,style(Color("18383c"),Color("49615b")))
		theme.set_stylebox("hover",type,style(Color("29534e"),Color("a6b998")))
		theme.set_stylebox("pressed",type,style(Color("3a6558"),Color("dfc58b")))
		theme.set_stylebox("focus",type,style(Color(0,0,0,0),Color("e0c17d")))
		theme.set_stylebox("disabled",type,style(Color("14272d"),Color("28393a")))
		theme.set_color("font_color",type,Color("e6ead9"))
		theme.set_color("font_disabled_color",type,Color("879893"))
	theme.set_color("font_color","Label",Color("e8eadf"))
	load_settings()
	sound=AudioStreamPlayer.new()
	add_child(sound)
	sound.volume_db=-16
	show_characters()
	if not migration_notice.is_empty():label(migration_notice,Rect2(40,690,1160,24),12,Color("e7c78d"))
	print("TRAINING_READY rules="+catalog.data.rules+" content="+catalog.data.version)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--native-check="):
			native_check_root=a.trim_prefix("--native-check=")
			var tester=load("res://tests/ui_upgrade.gd").new()
			add_child(tester)
			tester.run.call_deferred(self,native_check_root)
		elif a.begins_with("--export-check="):
			var tester=load("res://tests/export_smoke.gd").new()
			add_child(tester)
			tester.run.call_deferred(self,a.trim_prefix("--export-check="))
		elif a.begins_with("--reload-check="):
			var tester=load("res://tests/reload_upgrade.gd").new()
			add_child(tester)
			tester.run.call_deferred(self,a.trim_prefix("--reload-check="))

func style(bg:Color,border:Color)->StyleBoxFlat:
	var s=StyleBoxFlat.new()
	s.bg_color=bg
	s.border_color=border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left=12
	s.content_margin_right=12
	return s

func clear()->void:
	hide_details()
	if modal!=null:modal.queue_free();modal=null
	if canvas!=null:remove_child(canvas);canvas.queue_free()
	canvas=Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	controls={};stage=null;hud=null
	if page=="battle":return
	var background=TextureRect.new()
	background.texture=load("res://assets/scenes/battle-courtyard.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate=Color(0.18,0.23,0.23)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	place(background,Rect2(0,0,1280,720))
	label("藏 火",Rect2(26,14,112,40),30,Color("e5cb91"))
	label("战斗训练营",Rect2(147,22,220,32),22)
	button("帮助",Rect2(1172,20,76,32),show_help,"help")

func place(node:Control,rect:Rect2,parent:Control=null)->Control:
	(parent if parent!=null else canvas).add_child(node)
	node.position=rect.position
	node.size=rect.size
	return node

func panel(rect:Rect2,color:Color=Color(0.035,0.10,0.12,0.94),parent:Control=null)->Panel:
	var p=Panel.new()
	p.add_theme_stylebox_override("panel",style(color,Color("36504a")))
	place(p,rect,parent)
	return p

func label(text:String,rect:Rect2,font_size:int=16,color:Color=Color("e8eadf"),parent:Control=null)->Label:
	var l=Label.new()
	l.text=text
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	place(l,rect,parent)
	return l

func button(text:String,rect:Rect2,callback:Callable,key:String="",parent:Control=null)->Button:
	var b=Button.new()
	b.text=text
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	place(b,rect,parent)
	b.pressed.connect(func():
		inputs.append({"ms":Time.get_ticks_msec(),"page":page,"button":key,"text":b.text})
		callback.call())
	if key!="":controls[key]=b
	return b

func art(rect:Rect2,id:String,parent:Control=null)->TextureRect:
	var t=TextureRect.new()
	var atlas=AtlasTexture.new()
	atlas.atlas=load("res://assets/characters/"+id+"/attack.png")
	atlas.region=Rect2(0,0,512,512) if id=="cinder_horn_ox" else Rect2(0,0,640,640)
	t.texture=atlas
	t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter=Control.MOUSE_FILTER_IGNORE
	place(t,rect,parent)
	return t

func show_characters()->void:
	page="characters"
	clear()
	label("选择本次练习的人物",Rect2(40,105,680,42),26)
	label("四种属性倾向，同一个全开放法门库。人物名称均为训练样例。",Rect2(40,152,1100,30),16,Color("b6c1b0"))
	for i in range(catalog.data.characters.size()):
		var c=catalog.data.characters[i]
		var x=36+i*310
		panel(Rect2(x,209,286,400))
		art(Rect2(x-26,215,338,285),c.art)
		label(c.name+" · "+c.label,Rect2(x+18,440,250,32),22,Color("dfc88d"))
		label("气血 %d  灵气 %d\n回气 %d  速度 %d"%[c.stats.Hmax,c.stats.M,c.stats.Q,c.stats.S],Rect2(x+18,483,250,62))
		button("选择人物",Rect2(x+18,557,250,38),func():char_id=c.id;show_loadout(),"character_"+c.id)
	label("普通回合一招，战机回合多招；思考与施展时公共时间暂停。",Rect2(40,651,920,30),17)
	if not snapshot.is_empty():button("重试上场初态",Rect2(1000,642,240,45),start_snapshot,"resume_retry")

func show_loadout()->void:
	disabled_artifacts=disabled_artifacts.filter(func(id):return artifacts.has(id))
	page="loadout";clear()
	var c=selected_character()
	panel(Rect2(24,85,310,531))
	label(c.name+" · "+c.label,Rect2(43,102,271,32),22,Color("e2c795"))
	art(Rect2(25,134,264,232),c.art)
	label("气血 %d    灵气 %d\n回气 %d    速度 %d"%[c.stats.Hmax,c.stats.M,c.stats.Q,c.stats.S],Rect2(44,330,276,45),15)
	button("切换人物",Rect2(211,136,104,29),show_characters,"back_characters").add_theme_font_size_override("font_size",13)
	label("战斗功法",Rect2(44,387,249,23),17,Color("d9c18e"))
	for i in range(4):
		var v=catalog.techniques.get(slots[i],{})
		var tile=Tile.new();tile.slot_index=i;tile.item_id=slots[i];tile.kind="techniques"
		tile.key_hint=str(i+1);tile.selected=selected_slot==i and library_tab=="techniques"
		if not v.is_empty():tile.artwork=P.icon(v.id);tile.grade=P.grade(v)
		place(tile,Rect2(45+i*66,417,56,56));controls["slot_"+str(i)]=tile
		tile.pressed.connect(func():selected_slot=i;library_tab="techniques";show_loadout())
		tile.dropped.connect(func(payload):slots[i]=payload.item;show_loadout())
		if not v.is_empty():
			tile.mouse_entered.connect(func():show_details(P.skill_model(v,c),tile.get_global_rect()))
			tile.mouse_exited.connect(hide_details)
	label("法宝",Rect2(44,499,270,25),17,Color("d9c18e"))
	for i in range(2):
		var a=catalog.artifacts.get(artifacts[i],{})
		var tile=Tile.new();tile.slot_index=i;tile.item_id=artifacts[i];tile.kind="artifacts";tile.key_hint=str(i+1)
		tile.selected=library_tab=="artifacts" and selected_slot==i
		if not a.is_empty():tile.artwork=P.icon(a.id)
		place(tile,Rect2(45+i*72,539,56,56));controls["artifact_slot_"+str(i)]=tile
		tile.pressed.connect(func():selected_slot=i;library_tab="artifacts";show_loadout())
		tile.dropped.connect(func(payload):artifacts[i]=payload.item;show_loadout())
		if not a.is_empty():
			var toggle=CheckBox.new();toggle.text="自动";toggle.button_pressed=not disabled_artifacts.has(a.id)
			place(toggle,Rect2(39+i*76,589,76,24));controls["artifact_enabled_"+str(i)]=toggle
			toggle.toggled.connect(func(enabled):
				if enabled:disabled_artifacts.erase(a.id)
				elif not disabled_artifacts.has(a.id):disabled_artifacts.append(a.id))
			tile.mouse_entered.connect(func():show_details(P.artifact_model(a,c),tile.get_global_rect()))
			tile.mouse_exited.connect(hide_details)
	var check=catalog.validate(c.stats,slots,artifacts)
	var capacity="承载 %d / %d\n灵感 %d / %d"%[check.get("load",0),c.stats.M,check.get("F",0),c.stats.Q] if check.ok else check.reason
	label(capacity,Rect2(202,533,112,67),12,Color("9fc2a7") if check.ok else Color("e5a083"))
	button("功法",Rect2(360,89,124,36),func():library_tab="techniques";selected_slot=mini(selected_slot,3);show_loadout(),"library_techniques")
	button("法宝",Rect2(497,89,124,36),func():library_tab="artifacts";selected_slot=mini(selected_slot,1);show_loadout(),"library_artifacts")
	label("选择槽位后点书本，或拖入槽位。法宝分自动功效与独立的「催」。",Rect2(363,138,882,30),15,Color("b2bda8"))
	if library_tab=="techniques":
		for i in range(4):
			var b=button(["全部","初级","中级","高级"][i],Rect2(360+i*126,177,112,32),func():grade_filter=i;show_loadout(),"grade_"+str(i))
			if grade_filter==i:b.add_theme_stylebox_override("normal",style(Color("38564b"),Color("cdb783")))
	for i in range(catalog.data.growth_profiles.size()):
		var profile=catalog.data.growth_profiles[i]
		var button_profile=button(["基础","人物＋","系列＋","本法＋"][i],Rect2(700+i*89,89,84,36),func():growth_profile=profile.id;show_loadout(),"profile_"+profile.id)
		button_profile.add_theme_font_size_override("font_size",14)
		button_profile.tooltip_text=profile.name+" · 固定测试快照"
		if profile.id==growth_profile:button_profile.add_theme_stylebox_override("normal",style(Color("38564b"),Color("cdb783")))
	label("测试快照，不消耗修炼资源",Rect2(1065,93,190,28),12,Color("a9bfab"))
	var scroll=ScrollContainer.new();place(scroll,Rect2(360,223,894,390));scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);scroll.add_child(grid)
	var dictionary=catalog.techniques if library_tab=="techniques" else catalog.artifacts
	for id in dictionary:
		var v=dictionary[id]
		if library_tab=="techniques" and grade_filter>0 and P.grade(v)!=grade_filter:continue
		var tile=Tile.new();tile.card=true;tile.item_id=id;tile.kind=library_tab;tile.drag_enabled=true;tile.title=v.name;tile.artwork=P.icon(id)
		tile.grade=P.grade(v) if library_tab=="techniques" else 1
		tile.subtitle=P.GRADE_NAMES[tile.grade]+" · CD %d"%v.CD if library_tab=="techniques" else "法宝 · 灵感 %d"%v.F
		tile.custom_minimum_size=Vector2(282,118);grid.add_child(tile);controls["equip_"+id]=tile
		tile.pressed.connect(func():
			if library_tab=="techniques":slots[selected_slot]=id
			else:artifacts[selected_slot]=id
			last_notice="已装入 "+v.name;show_loadout())
		tile.mouse_entered.connect(func():show_details(P.skill_model(v,c) if library_tab=="techniques" else P.artifact_model(v,c),tile.get_global_rect()))
		tile.mouse_exited.connect(hide_details)
		# Favorite is a compact corner control, not another full row.
		var favorite=button("★" if favorites.has(id) else "☆",Rect2(246,86,28,25),func():
			if favorites.has(id):favorites.erase(id)
			else:favorites.append(id)
			show_loadout(),"favorite_"+id,tile)
		favorite.add_theme_font_size_override("font_size",13)
	button("卸下",Rect2(24,642,86,35),func():
		if library_tab=="techniques":slots[selected_slot]=""
		else:artifacts[selected_slot]=""
		show_loadout(),"clear_slot")
	button("保存配装",Rect2(123,642,123,35),func():save_settings();notice("已保存配装"),"save")
	button("示范方案",Rect2(260,642,123,35),show_templates,"templates")
	label(last_notice,Rect2(405,641,492,38),14,Color("b5c7b6"))
	button("进入训练营  ›",Rect2(1045,637,208,48),open_selector,"enter").disabled=not check.ok

func notice(text:String)->void:
	last_notice=text
	if page=="loadout":show_loadout()

func open_modal(rect:Rect2)->Control:
	hide_details()
	if modal!=null:remove_child(modal);modal.queue_free()
	modal=Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim=ColorRect.new()
	dim.color=Color(0,0,0,0.78)
	place(dim,Rect2(0,0,1280,720),modal)
	panel(rect,Color("10272c"),modal)
	return modal

func close_modal()->void:
	hide_details()
	if modal!=null:
		remove_child(modal)
		modal.queue_free()
		modal=null

func selected_character()->Dictionary:
	var c=catalog.character(char_id)
	catalog.apply_profile(c,growth_profile)
	return c

func toggle_pause()->void:
	paused=not paused;decision_epoch+=1;ai_pending={}
	if not selected_action.is_empty():selected_action={};stage.selected_target=""
	if controls.has("pause"):controls.pause.text="▶" if paused else "Ⅱ"
	update_battle_hud()

func show_templates()->void:
	var parent=open_modal(Rect2(316,160,648,400))
	label("示范与已保存方案",Rect2(342,181,550,35),24,Color("dfc68c"),parent)
	var y=232
	for id in catalog.data.loadouts:
		var l=catalog.data.loadouts[id]
		button(l.name,Rect2(342,y,280,44),func():slots=l.slots.duplicate();artifacts=l.artifacts.duplicate();show_loadout(),"template_"+id,parent)
		label("四格成品与两法宝",Rect2(646,y,272,44),14,Color("a7b7a8"),parent)
		y+=58
	if not saved_presets.is_empty():button("载入保存的本场装配",Rect2(342,y,570,40),func():
		var p=saved_presets.back();slots=p.slots.duplicate();artifacts=p.artifacts.duplicate();show_loadout(),"saved_template",parent)
	button("返回",Rect2(795,490,136,42),close_modal,"modal_back",parent)

func open_selector()->void:
	var check=catalog.validate(catalog.character(char_id).stats,slots,artifacts)
	if not check.ok:notice(check.reason);return
	choice=mirror_choice if mode=="mirror" else preset_choice
	var parent=open_modal(Rect2(245,119,790,490))
	label("选择本次训练",Rect2(270,136,735,40),25,Color("dfc68c"),parent)
	button("镜像战斗",Rect2(270,193,353,40),func():mode="mirror";open_selector(),"mode_mirror",parent)
	button("预设战斗",Rect2(636,193,373,40),func():mode="preset";open_selector(),"mode_preset",parent)
	var options=catalog.data.difficulties if mode=="mirror" else catalog.data.enemies
	for i in range(options.size()):
		var o=options[i]
		var text=o.name if mode=="mirror" else o.type+" · "+o.name
		var b=button(text,Rect2(270+i*247,247,238,42),func():
			if mode=="mirror":mirror_choice=o.id
			else:preset_choice=o.id
			open_selector(),"choice_"+o.id,parent)
		if o.id==choice:b.add_theme_stylebox_override("normal",style(Color("49654f"),Color("d8bc7c")))
	var s=catalog.snapshot(char_id,slots,artifacts,mode,choice,seed,["p","e"],growth_profile,disabled_artifacts)
	if not s.ok:
		label(s.reason,Rect2(270,304,737,167),18,Color("ffa38c"),parent)
	else:
		preview_hash=s.value.loadout_hash
		var p=s.value.units[0]
		var e=s.value.units[1]
		label("对手："+e.name,Rect2(270,304,734,30),22,Color("dfc68c"),parent)
		label("气血 %d    灵气 %d    回气 %d    速度 %d"%[e.stats.Hmax,e.stats.M,e.stats.Q,e.stats.S],Rect2(270,346,734,28),16,Color("cad7c7"),parent)
		label("气血与速度分别为你的%d%%、%d%%"%[e.stats.Hmax*100/p.stats.Hmax,e.stats.S*100/p.stats.S] if mode=="mirror" else "固定对手配装",Rect2(270,383,734,24),14,Color("b2bda8"),parent)
		for i in range(e.slots.size()):
			var v=catalog.techniques.get(e.slots[i],{})
			var tile=Tile.new();tile.artwork=P.icon(e.slots[i]);tile.grade=P.grade(v);place(tile,Rect2(270+i*65,424,52,52),parent)
			if not v.is_empty():
				tile.mouse_entered.connect(func():show_details(P.skill_model(v,e),tile.get_global_rect()))
				tile.mouse_exited.connect(hide_details)
		label("镜像使用与你相同的功法和法宝。" if mode=="mirror" else "此对手使用独立的功法与法宝。",Rect2(552,435,453,36),14,Color("b2bda8"),parent)
	button("返回配装",Rect2(270,540,226,44),close_modal,"selector_back",parent)
	button("开始战斗",Rect2(746,540,262,44),confirm_start,"start",parent).disabled=not s.ok
	controls.start.grab_focus()

func confirm_start()->void:
	if modal==null or page!="loadout":return
	var s=catalog.snapshot(char_id,slots,artifacts,mode,choice,seed,["p","e"],growth_profile,disabled_artifacts)
	if not s.ok:notice(s.reason);return
	if s.value.loadout_hash!=preview_hash:open_selector();return
	snapshot=s.value.duplicate(true)
	save_settings()
	start_snapshot()

func start_snapshot()->void:
	var validation=catalog.validate_snapshot(snapshot)
	if not validation.ok:
		snapshot={};show_loadout();notice("旧快照不可直接续用，请重新选战："+validation.reason);return
	battle_generation+=1;decision_epoch+=1;ai_pending={}
	close_modal()
	battle=Battle.new(catalog);battle.capture_visual=true
	var result=battle.start(snapshot)
	if not result.ok:show_loadout();notice(result.reason);return
	event_cursor=0;playback_wait=0;selected_action={};paused=false;autoplay=false
	visual_kind="";show_battle()

func show_battle()->void:
	page="battle";clear()
	stage=Stage.new();place(stage,Rect2(0,0,1280,720));stage.target_clicked.connect(select_target)
	visual_rows=battle.events[0].get("visual",battle.state.units).duplicate(true) if not battle.events.is_empty() else battle.state.units.duplicate(true)
	visual_current=""
	stage.set_actors(visual_rows,visual_current)
	hud=BattleHud.new();hud.controller=self;place(hud,Rect2(0,0,1280,720));controls.merge(hud.controls)
	update_battle_hud()

func update_battle_hud(visual:Array=[],clock_event:bool=false)->void:
	if page!="battle" or hud==null:return
	if not visual.is_empty():visual_rows=visual.duplicate(true)
	if visual_rows.is_empty():visual_rows=battle.view()
	hud.set_view(visual_rows,visual_current,clock_event)
	var player=battle.unit("p").duplicate(true)
	for row in visual_rows:
		if row.id=="p":player.merge(row,true)
	var can=modal==null and not paused and not thinking() and event_cursor>=battle.events.size() and playback_wait<=0 and battle.state.current=="p" and battle.state.phase=="DECISION" and not battle.state.ended
	var kind="战机回合 · 多法连用" if visual_kind==Protocol.OPPORTUNITY else "普通回合 · 一次主动作"
	controls.state.text=("你的" if visual_current=="p" else "对手的")+kind if visual_current!="" else "行动与战机积累中"
	if paused:controls.state.text="已暂停"
	elif thinking():controls.state.text="对手正在判断" if battle.state.current!="p" else "自动判断中"
	for i in range(4):
		var entry=player.entries[i];var v=catalog.techniques.get(entry.technique,{})
		var tile=controls["skill_"+str(i)]
		tile.item_id=entry.technique;tile.artwork=P.icon(v.id) if not v.is_empty() else null
		tile.grade=P.grade(v) if not v.is_empty() else 1
		tile.spent=entry.used;tile.remaining=P.remaining(entry,player,catalog)
		tile.selected=selected_action.get("kind","")=="cast" and selected_action.get("slot",-1)==i
		var a={"kind":"cast","actor":"p","slot":i,"target":"e","window_id":battle.state.window_id}
		tile.disabled=not can or not battle.legal(a).ok;tile.refresh()
		controls["swap_"+str(i)].disabled=not can or entry.used or player.swap_used
	controls.end_window.disabled=not can
	controls.end_window.text="结束战机 ›" if visual_kind==Protocol.OPPORTUNITY else "结束 / 跳过 ›"
	controls.sword.disabled=not can or player.sword_used or not battle.legal({"kind":"sword","actor":"p","target":"e"}).ok
	for i in range(player.art_entries.size()):
		var entry=player.art_entries[i];var tile=controls["passive_"+str(i)]
		tile.spent=entry.triggered or not entry.enabled;tile.refresh()
		if controls.has("active_"+str(i)):
			var active=controls["active_"+str(i)]
			var v=catalog.artifacts[entry.artifact].active
			var target="p"
			for s in v.sentences:
				if s.target in ["enemy","all_enemies"]:target="e"
			active.disabled=not can or not battle.legal({"kind":"artifact","actor":"p","slot":i,"target":target,"window_id":battle.state.window_id}).ok
			active.text="已催" if entry.active_used else "催 %d"%[entry.active_ready_window-player.W] if entry.active_ready_window>player.W else "催"
	stage.active=visual_current
	if not hover_action_data.is_empty():hover_action(hover_action_data,hover_rect)

func show_details(model:Dictionary,anchor:Rect2)->void:
	if details==null:
		details=DetailPopup.new();details.model=model;details.z_index=100;add_child(details)
	details.set_model(model)
	var x=anchor.end.x+12
	if x+details.size.x>1272:x=anchor.position.x-details.size.x-12
	var y=anchor.position.y
	if y+details.size.y>708:y=anchor.position.y-details.size.y-12
	details.position=Vector2(clampf(x,8,1272-details.size.x),clampf(y,8,708-details.size.y))
	details.show()

func hide_details()->void:
	hover_action_data={}
	if is_instance_valid(details):details.hide()
	if is_instance_valid(hud):hud.preview(-1)

func hover_action(action:Dictionary,anchor:Rect2)->void:
	if page!="battle" or not action.get("kind","") in ["cast","artifact"]:return
	hover_action_data=action.duplicate(true);hover_rect=anchor
	var player=battle.unit("p").duplicate(true)
	for row in visual_rows:
		if row.id=="p":player.merge(row,true)
	var v=battle.variant_for(player,action)
	if v.is_empty():hide_details();return
	var model=P.catalyst_model(catalog.artifacts[player.art_entries[int(action.slot)].artifact],player,battle,action) if action.kind=="artifact" else P.skill_model(v,player,battle,action)
	# Execute only a genuinely current, settled decision snapshot, never a UI-made turn.
	if event_cursor>=battle.events.size() and playback_wait<=0 and battle.state.current=="p" and battle.state.phase=="DECISION" and not battle.state.ended:
		var preview=battle.fork()
		var candidate=action.duplicate(true);candidate.actor="p";candidate.target="p";candidate.window_id=battle.state.window_id
		for sentence in v.sentences:
			if sentence.target in ["enemy","all_enemies"]:candidate.target="e"
		var check=preview.legal(candidate)
		if check.ok:
			var receipt=preview.execute(candidate)
			model.after=int(receipt.after_effect_E);model.after_label="施展后（不含随后回气）"
		elif model.availability.is_empty():model.availability=P.reason(check.reason)
	show_details(model,anchor);hud.preview(int(model.cost),int(model.after))

func select_action(a:Dictionary)->void:
	if battle.state.current!="p" or battle.state.phase!="DECISION" or modal!=null or paused or thinking() or event_cursor<battle.events.size() or playback_wait>0:return
	hide_details()
	hud.inspector.hide();hud.inspected=""
	selected_action=a.duplicate(true)
	selected_action.window_id=battle.state.window_id
	stage.selected_target=""
	var v=battle.variant_for(battle.unit("p"),a) if a.kind!="sword" else {}
	var self_target=not v.is_empty()
	for s in v.get("sentences",[]):
		if s.target in ["enemy","all_enemies"]:self_target=false
	stage.selected_target="p" if self_target else "e"
	controls.receipt.text="%s · 点击%s确认（右键取消）"%[v.get("name","挥剑"),"自己" if self_target else "对手"]

func select_target(id:String)->void:
	inputs.append({"ms":Time.get_ticks_msec(),"page":page,"target":id})
	if selected_action.is_empty():
		hide_details();hud.inspect(id);return
	var a=selected_action.duplicate(true)
	a.target=id
	var check=battle.legal(a)
	if not check.ok:controls.receipt.text=P.reason(check.reason);return
	# Self-only abilities require self confirmation even though their executor binds self.
	if stage.selected_target!="" and id!=stage.selected_target:controls.receipt.text="请选择高亮的合法目标";return
	selected_action={}
	stage.selected_target=""
	submit(a)

func submit(a:Dictionary)->void:
	if paused or thinking() or modal!=null or event_cursor<battle.events.size() or playback_wait>0:return
	if battle.state.phase!="DECISION" or battle.state.current!="p":return
	var command=a.duplicate(true)
	if not command.has("window_id"):command.window_id=battle.state.window_id
	var r=battle.execute(command)
	if not r.ok:controls.receipt.text=P.reason(r.reason)
	else:selected_action={};stage.selected_target=""
	update_battle_hud()

func show_swap(slot:int)->void:
	hide_details()
	selected_action={};stage.selected_target=""
	var parent=open_modal(Rect2(192,100,896,530))
	label("更换功法",Rect2(218,119,780,35),24,Color("dfc68c"),parent)
	label("每窗口可准备换法一次；继承本格与同源等待，本窗口不能使用。",Rect2(218,163,790,28),16,Color("b2bda8"),parent)
	var scroll=ScrollContainer.new();place(scroll,Rect2(218,208,844,339),parent)
	var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);scroll.add_child(grid)
	for id in catalog.techniques:
		var v=catalog.techniques[id]
		var a={"kind":"swap","actor":"p","slot":slot,"technique":id,"window_id":battle.state.window_id}
		var check=battle.legal(a)
		var tile=Tile.new();tile.card=true;tile.item_id=id;tile.artwork=P.icon(id);tile.title=v.name;tile.grade=P.grade(v)
		tile.subtitle=P.GRADE_NAMES[tile.grade]+" · CD %d"%v.CD
		tile.custom_minimum_size=Vector2(271,118);tile.disabled=not check.ok;grid.add_child(tile);controls["swap_to_"+id]=tile
		tile.pressed.connect(func():hide_details();close_modal();submit(a))
		tile.mouse_entered.connect(func():
			var model=P.skill_model(v,battle.unit("p"),battle)
			model.availability="最早在自己的第%d次出手机会可用（含战机）。"%battle.swap_ready(battle.unit("p"),slot,id) if check.ok else P.reason(check.reason)
			show_details(model,tile.get_global_rect()))
		tile.mouse_exited.connect(hide_details)
	button("返回",Rect2(882,574,179,36),func():hide_details();close_modal(),"swap_back",parent)

func event_text(e:Dictionary)->String:
	var actor=battle.unit(e.get("actor","")).get("name","")
	var target=battle.unit(e.get("target","")).get("name","")
	match e.kind:
		"clock","window_end":return ""
		"window":return "%s · %s"%[actor,e.get("text","")]
		"opportunity":return "%s进入战机：可连续施展已就绪的不同功法"%actor
		"qualified":return "%s战机已满，当前窗口结束后调度"%actor
		"cast":return "%s · %s"%[actor,e.text]
		"damage":return ("%s受到%d伤害"%[target,e.actual] if e.target=="p" else "%s受到攻击"%target) if e.actual>0 else "%s的护体吸收伤害"%target if e.absorbed>0 else ""
		"apply":return "%s获得%s"%[target,e.buff]
		"heal":return "%s恢复%d气血"%[target,e.actual] if e.target=="p" else "%s恢复气血"%target
		"qi":return "%s恢复%d灵气"%[target,e.actual] if e.target=="p" else "%s恢复灵气"%target
		"public_effect":return ""
		"auto":return "%s · %s"%[actor,e.text]
		"consume","remove":return ""
		"swap":return "%s更换功法"%actor
		_:return P.reason(e.get("text",""))

func thinking()->bool:
	return ai_worker!=null or not ai_pending.is_empty()

func launch_ai(profile:String)->void:
	var isolated=battle.fork()
	var actor=str(battle.state.current)
	var generation=battle_generation
	var observation=battle.public_hash()
	var epoch=decision_epoch
	var window_id=battle.state.window_id
	ai_worker=Thread.new()
	var error=ai_worker.start(func():
		var policy=AI.new()
		var action=policy.choose(isolated,profile,actor)
		return {"action":action,"trace":policy.last_trace,"budget":isolated.state.ai_budget[actor],"actor":actor,"generation":generation,"observation":observation,"epoch":epoch,"window_id":window_id})
	if error!=OK:
		ai_worker=null
		battle.finish("aborted","无法启动AI判断线程")
	update_battle_hud()

func _exit_tree()->void:
	if ai_worker!=null:ai_worker.wait_to_finish();ai_worker=null

func _process(delta:float)->void:
	if ai_worker!=null and not ai_worker.is_alive():
		ai_pending=ai_worker.wait_to_finish()
		ai_worker=null
	if not ai_pending.is_empty():
		if page!="battle" or battle.state.ended or ai_pending.generation!=battle_generation or ai_pending.epoch!=decision_epoch or ai_pending.window_id!=battle.state.window_id or ai_pending.observation!=battle.public_hash() or (ai_pending.actor=="p" and not autoplay):ai_pending={}
	if page=="battle" and is_instance_valid(hud):
		hud.timeline.paused=paused or modal!=null
		stage.diorama.set_process(not paused and modal==null)
		stage.set_process(not paused and modal==null)
		if paused and not controls.end_window.disabled:update_battle_hud()
	if page!="battle" or modal!=null or paused:return
	playback_wait=maxf(0,playback_wait-delta)
	if playback_wait>0:return
	while event_cursor<battle.events.size():
		var e=battle.events[event_cursor]
		event_cursor+=1
		if not e.kind in ["clock","window","window_end","opportunity","qualified","cast","damage","apply","heal","qi","auto","consume","remove","skip","swap","end"]:continue
		if e.kind=="window":visual_current=e.actor;visual_kind=e.window_kind
		elif e.kind in ["window_end","end"]:visual_current="";visual_kind=""
		if e.kind=="clock":stage.set_actors(e.visual,visual_current)
		else:stage.play(e)
		controls.receipt.text=event_text(e)
		update_battle_hud(e.get("visual",[]),e.kind in ["clock","window","window_end","end"])
		if e.kind=="clock":
			playback_wait=0.17/float(speed) if speed>0 else 0
		if e.kind in ["damage","cast","apply","heal","qi","auto","consume","swap","opportunity"]:
			playback_wait=(0.7 if e.kind=="opportunity" else 0.28)/float(speed) if speed>0 else 0
			if e.kind=="damage" and speed>0:
				sound.stream=load("res://assets/sfx/hit.wav");sound.play()
		return
	if battle.state.ended:show_result();return
	update_battle_hud()
	if battle.state.current!="p" or autoplay:
		if not ai_pending.is_empty():
			var decision=ai_pending
			ai_pending={}
			battle.state.ai_budget[decision.actor]=decision.budget
			decision.trace.background=true
			battle.state.ai_traces.append(decision.trace)
			var r=battle.execute(decision.action)
			if not r.ok:push_error("AI illegal: "+r.reason);battle.finish("aborted","AI指令错误")
		elif ai_worker==null:
			launch_ai(snapshot.enemy_ai if battle.state.current!="p" else "normal")

func show_result()->void:
	page="result"
	clear()
	var outcomes={"player":"训练胜利","enemy":"训练落败","draw":"双方平局","undecided":"观察未决","aborted":"训练中止","error":"规则异常（请导出记录）"}
	label(outcomes[battle.state.result],Rect2(36,98,1030,55),34,Color("e7c98c"))
	label(snapshot.title+" · "+battle.state.reason.replace("600公共刻","战斗时长").replace("100自身窗","回合数"),Rect2(38,158,1130,38),18)
	for i in range(battle.state.units.size()):
		var u=battle.state.units[i]
		var x=32+i*619
		panel(Rect2(x,218,595,322))
		art(Rect2(x-21,230,275,272),u.art)
		var s=u.stats_log
		label(u.name,Rect2(x+218,233,358,36),23,Color("e0cb94"))
		label("气血 %d/%d · 灵气 %d/%d\n普通 %d · 战机 %d · 施法 %d\n造成直伤 %d · 承受效果伤害 %d\n灵气支出 %d · 气血支付 %d\n即时恢复 %d · 护体新增 %d\n周期伤/疗请求 %d / %d\n周期气血净变化 %+d\n回气溢出 %d · 恢复溢出 %d"%[u.H,u.Hmax,u.E,u.M,u.R,s.opportunity_windows,s.casts,s.direct,s.effect_taken,s.qi_cost,s.hp_cost,s.heal,s.shield,s.periodic_damage_requested,s.periodic_heal_requested,s.periodic_net,s.qi_overflow,s.heal_overflow],Rect2(x+218,278,358,238),15)
	label("周期伤害与恢复显示请求和共同净变化，不伪造施加者实际归属。",Rect2(39,557,1190,40),14,Color("b3c5b5"))
	button("原条件重试",Rect2(33,622,230,50),start_snapshot,"retry")
	button("重新选择战斗",Rect2(276,622,230,50),func():show_loadout();open_selector(),"reselect")
	button("返回配装",Rect2(519,622,206,50),show_loadout,"edit")
	button("保存本场装配为预设",Rect2(738,622,264,50),save_final,"save_final")
	button("事件与 AI 复盘",Rect2(1014,622,232,50),show_logs,"result_logs")
	var out="user://training_camp_v3/last_battle.json"
	var f=FileAccess.open(out,FileAccess.WRITE)
	if f:f.store_string(JSON.stringify({"snapshot":snapshot,"result":battle.state,"events":battle.events,"accounting":battle.accounting()},"\t"))

func save_final()->void:
	var u=battle.unit("p")
	saved_presets.append({"slots":u.slots.duplicate(),"artifacts":u.artifacts.duplicate()})
	save_settings()
	controls.save_final.text="已保存，可从示范方案载入"

func show_logs()->void:
	var parent=open_modal(Rect2(139,86,1002,568))
	label("事件与公开信息 AI 复盘",Rect2(163,104,930,38),23,Color("dfc68c"),parent)
	var text=RichTextLabel.new()
	text.bbcode_enabled=false
	place(text,Rect2(164,156,948,426),parent)
	for e in battle.events:text.append_text("#%d t%d R%d W%d %s  %s\n"%[e.id,e.t,e.R,e.W,e.event_type,event_text(e)])
	text.append_text("\nAI 决策（未来输入不可见）\n")
	for t in battle.state.ai_traces:
		text.append_text("t%d W%d %s %s\n节点%d / 模拟事件%d / 截断%s\n"%[t.t,t.W,t.profile,t.reason,t.nodes,t.events,str(t.truncated)])
	button("导出复盘",Rect2(164,597,205,38),func():
		var f=FileAccess.open("user://training_camp_v3/review.json",FileAccess.WRITE)
		f.store_string(JSON.stringify({"snapshot":snapshot,"events":battle.events,"AI":battle.state.ai_traces},"\t"))
		OS.shell_open(ProjectSettings.globalize_path("user://training_camp_v3")),"export_review",parent)
	button("返回",Rect2(901,597,208,38),close_modal,"logs_back",parent)

func show_abort()->void:
	var parent=open_modal(Rect2(386,236,508,229))
	label("中止本次练习？配装会保留。",Rect2(410,258,461,76),22,Color("dfc68c"),parent)
	button("继续训练",Rect2(410,376,210,46),close_modal,"keep_training",parent)
	button("中止",Rect2(637,376,230,46),func():close_modal();battle.finish("aborted","主动中止训练");event_cursor=battle.events.size();show_result(),"confirm_abort",parent)

func show_help()->void:
	var parent=open_modal(Rect2(258,117,764,490))
	label("训练营操作 · 双窗口",Rect2(283,137,704,43),25,Color("dfc68c"),parent)
	label("先选人物、配装，再选择镜像或预设对手。测试快照只改变造诣。\n行动条满：普通回合一次主动作（施法或挥剑）。\n战机条满：安全边界自动进入战机，可连用多门已就绪功法。\n普通与战机都推进自己的CD；CD1表示下次自己的出手可用。\n\n按1–4或点技能，再点高亮人物确认；右键取消。\n右键功法可换法，每个窗口一次准备；继承本格及同源等待。\n自动图标只显示效果；点「催」另施主动能力，普通回合占主动作。\n空格结束窗口；右上角可暂停、自动练习或改变播放速度。\n\n点击人物查看信息；战机不额外跳周期状态或重复普通开场法宝。\n所有消耗、派生结果、阶段和AI判断可在战后导出。",Rect2(283,194,704,335),17,Color("cbd7c6"),parent)
	button("返回",Rect2(789,549,204,39),close_modal,"help_back",parent)

func _input(event:InputEvent)->void:
	# A selected spell/Cui can be cancelled even when the stage consumes GUI input.
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and page=="battle" and not selected_action.is_empty():
		selected_action={};stage.selected_target="";controls.receipt.text="已取消选招"
		get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F12:
			var dir=ProjectSettings.globalize_path("user://training_camp_v3/screenshots")
			DirAccess.make_dir_recursive_absolute(dir)
			get_viewport().get_texture().get_image().save_png(dir+"/"+page+"-"+str(Time.get_ticks_msec())+".png")
			var f=FileAccess.open("user://training_camp_v3/physical_inputs.json",FileAccess.WRITE)
			f.store_string(JSON.stringify(inputs,"\t"))
		elif event.keycode==KEY_ESCAPE:
			if modal!=null:close_modal()
			elif page=="battle":toggle_pause()
			elif page=="loadout":show_characters()
		elif page=="battle" and modal==null:
			if event.keycode==KEY_SPACE:submit({"kind":"end","actor":"p"})
			elif event.keycode>=KEY_1 and event.keycode<=KEY_4:select_action({"kind":"cast","actor":"p","slot":event.keycode-KEY_1})
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and page=="battle":
		selected_action={};stage.selected_target="";controls.receipt.text="已取消选招"

func save_settings()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://training_camp_v3"))
	var f=FileAccess.open(SAVE,FileAccess.WRITE)
	if f:f.store_string(JSON.stringify({"save_schema":Protocol.SAVE_SCHEMA,"rules":Protocol.RULES,"version":catalog.data.version,"content_digest":catalog.digest,"character":char_id,"slots":slots,"artifacts":artifacts,"growth_profile":growth_profile,"disabled_artifacts":disabled_artifacts,"favorites":favorites,"saved_presets":saved_presets,"mode":mode,"mirror_choice":mirror_choice,"preset_choice":preset_choice,"seed":seed,"snapshot":snapshot},"\t"))

func load_settings()->void:
	var path=SAVE
	var legacy=false
	if not FileAccess.file_exists(path):
		path="user://training_camp_v2/settings.json";legacy=true
		if not FileAccess.file_exists(path):return
	var raw=FileAccess.get_file_as_string(path)
	var saved=JSON.parse_string(raw)
	if not saved is Dictionary:migration_notice="设置文件无法解析，未覆盖原文件。";return
	legacy=legacy or saved.get("save_schema",0)!=Protocol.SAVE_SCHEMA or saved.get("rules","")!=Protocol.RULES or saved.get("content_digest","")!=catalog.digest
	if legacy:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://training_camp_v3"))
		var backup=FileAccess.open("user://training_camp_v3/import-backup-"+str(Time.get_unix_time_from_system())+".json",FileAccess.WRITE)
		if backup:backup.store_string(raw)
		migration_notice="旧设置已备份；合法配装可保留，旧战斗快照不可直接续用，请重新选战。"
	if not catalog.character(str(saved.get("character",""))).is_empty():char_id=str(saved.character)
	var candidate_slots=saved.get("slots",slots)
	var candidate_arts=saved.get("artifacts",artifacts)
	if candidate_slots is Array and candidate_arts is Array and catalog.validate(catalog.character(char_id).stats,candidate_slots,candidate_arts).ok:
		slots=candidate_slots;artifacts=candidate_arts
	favorites=saved.get("favorites",[]) if saved.get("favorites",[]) is Array else []
	saved_presets=[]
	for preset in saved.get("saved_presets",[]):
		if preset is Dictionary and preset.get("slots") is Array and preset.get("artifacts") is Array and catalog.validate(catalog.character(char_id).stats,preset.slots,preset.artifacts).ok:saved_presets.append(preset)
	mode=str(saved.get("mode","mirror")) if saved.get("mode","mirror") in ["mirror","preset"] else "mirror"
	mirror_choice=str(saved.get("mirror_choice","normal")) if saved.get("mirror_choice","normal") in ["easy","normal","hard"] else "normal"
	preset_choice=str(saved.get("preset_choice","P01")) if not catalog.opponent(str(saved.get("preset_choice","P01"))).is_empty() else "P01"
	seed=int(saved.get("seed",103))
	for profile in catalog.data.growth_profiles:
		if profile.id==saved.get("growth_profile",""):growth_profile=profile.id
	disabled_artifacts=[]
	for id in saved.get("disabled_artifacts",[]):
		if artifacts.has(id):disabled_artifacts.append(id)
	snapshot={}
	if not legacy and saved.get("snapshot") is Dictionary and catalog.validate_snapshot(saved.snapshot).ok:snapshot=saved.snapshot
