extends Control
const P=preload("res://scripts/presentation.gd")
const Tile=preload("res://scripts/ui/skill_tile.gd")
const Health=preload("res://scripts/ui/health_bar.gd")
const Timeline=preload("res://scripts/ui/initiative.gd")
var controller
var controls:Dictionary={}
var timeline
var player_health
var enemy_health
var player_mana:ProgressBar
var mana_preview:ColorRect
var player_values:Label
var enemy_badge:Button
var notice:Label
var own_buff_root:Control
var enemy_buff_root:Control
var buff_signature:String=""
var menu:Panel
var inspector:Panel
var inspector_body:RichTextLabel
var inspected:String=""
var rows:Array=[]
var preview_cost:int=-1
var preview_after:int=-1
var gauge_bars:Dictionary={}
var gauge_labels:Dictionary={}

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	# The battle has no page banner or fixed character-information windows.
	timeline=Timeline.new();_place(timeline,Rect2(342,16,596,53));timeline.actor_selected.connect(controller.select_target)
	_label("行动进度",Rect2(342,1,82,17),11,Color("91a69a"))
	var state_back=_panel(Rect2(376,122,528,34));state_back.mouse_filter=Control.MOUSE_FILTER_IGNORE
	controls.state=_label("",Rect2(380,126,520,26),16,Color("e0c68c"));controls.state.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for i in range(2):
		var id="p" if i==0 else "e"
		var gauge=ProgressBar.new();gauge.max_value=100;gauge.show_percentage=false;gauge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		for part in ["background","fill"]:
			var skin=StyleBoxFlat.new();skin.bg_color=Color("c8a04e") if part=="fill" else Color("252921");skin.set_corner_radius_all(3);gauge.add_theme_stylebox_override(part,skin)
		_place(gauge,Rect2(400,84+i*21,374,10));gauge_bars[id]=gauge
		_label("己方战机" if i==0 else "对手战机",Rect2(342,77+i*21,58,20),11,Color("cfb875"))
		gauge_labels[id]=_label("",Rect2(786,77+i*21,175,20),11,Color("e2c887"))
	_button("Ⅱ",Rect2(1130,18,32,30),controller.toggle_pause,"pause")
	_button("▷",Rect2(1088,18,32,30),func():controller.autoplay=not controller.autoplay;controls.auto.text="◆" if controller.autoplay else "▷","auto")
	_button("跳过" if controller.speed==0 else str(controller.speed)+"×",Rect2(1172,18,38,30),func():controller.speed=3 if controller.speed==1 else 0 if controller.speed==3 else 1;controls.speed.text="跳过" if controller.speed==0 else str(controller.speed)+"×","speed")
	_button("☰",Rect2(1220,18,34,30),func():menu.visible=not menu.visible,"battle_menu")
	controls.pause.tooltip_text="暂停 / 继续";controls.auto.tooltip_text="自动练习 / 手动";controls.speed.tooltip_text="播放速度"
	var portrait=_button("",Rect2(24,641,48,58),func():controller.select_target("p"),"player_portrait")
	var picture=TextureRect.new();picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var atlas=AtlasTexture.new();atlas.atlas=load("res://assets/characters/"+controller.battle.unit("p").art+"/attack.png");atlas.region=Rect2(190,135,245,275)
	picture.texture=atlas;picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_place(picture,Rect2(2,1,44,56),portrait)
	_label(controller.battle.unit("p").name,Rect2(82,628,188,19),14,Color("e2d3ac"))
	player_health=Health.new();_place(player_health,Rect2(82,652,186,10))
	player_mana=ProgressBar.new();player_mana.show_percentage=false;player_mana.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for part in ["background","fill"]:
		var skin=StyleBoxFlat.new();skin.bg_color=Color("65b8c9") if part=="fill" else Color("142a32");skin.set_corner_radius_all(1)
		player_mana.add_theme_stylebox_override(part,skin)
	_place(player_mana,Rect2(82,678,186,9))
	mana_preview=ColorRect.new();mana_preview.color=Color(0.95,0.64,0.34,0.9);mana_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(mana_preview);mana_preview.hide()
	player_values=_label("",Rect2(82,690,232,19),12,Color("a6d0d0"))
	controls.player_hp=_label("",Rect2(82,663,220,15),11,Color("c4d8bc"))
	for i in range(4):
		var tile=Tile.new();tile.key_hint=str(i+1);_place(tile,Rect2(365+i*69,645,58,58))
		controls["skill_"+str(i)]=tile
		tile.pressed.connect(func():controller.select_action({"kind":"cast","actor":"p","slot":i}))
		tile.mouse_entered.connect(func():controller.hover_action({"kind":"cast","actor":"p","slot":i},tile.get_global_rect()))
		tile.mouse_exited.connect(controller.hide_details)
		tile.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
				for j in range(4):controls["swap_"+str(j)].hide()
				if not controller.thinking() and controller.battle.state.current=="p":controls["swap_"+str(i)].show()
				tile.accept_event())
		var swap=_button("换法",Rect2(361+i*69,601,66,34),func():controller.show_swap(i),"swap_"+str(i));swap.hide()
	for i in range(controller.battle.unit("p").art_entries.size()):
		var entry=controller.battle.unit("p").art_entries[i]
		var tile=Tile.new();tile.key_hint="自动";tile.artwork=P.icon(entry.artifact);_place(tile,Rect2(664+i*55,652,46,46))
		controls["passive_"+str(i)]=tile
		tile.mouse_entered.connect(func():controller.show_details(P.passive_model(controller.catalog.artifacts[entry.artifact],controller.battle.unit("p")),tile.get_global_rect()))
		tile.mouse_exited.connect(controller.hide_details)
		# Deliberately no pressed callback on the passive icon.
		if controller.catalog.artifacts[entry.artifact].has("active"):
			var active=_button("催",Rect2(664+i*55,618,46,29),func():controller.select_action({"kind":"artifact","actor":"p","slot":i}),"active_"+str(i))
			active.mouse_entered.connect(func():controller.hover_action({"kind":"artifact","actor":"p","slot":i},active.get_global_rect()))
			active.mouse_exited.connect(controller.hide_details)
	var sword=Tile.new();sword.artwork=P.icon("sword");sword.key_hint="剑";_place(sword,Rect2(791,656,40,40));controls.sword=sword
	sword.pressed.connect(func():controller.select_action({"kind":"sword","actor":"p"}))
	sword.mouse_entered.connect(func():controller.show_details({"title":"挥剑","grade":"基础攻击","effect":"造成%d点基础直接伤害，不耗灵气。普通回合占主动作；战机内最多一次。"%controller.Math.root_amount(controller.battle.unit("p").basic_attack,controller.Math.growth_inputs(controller.battle.unit("p"),{}))},sword.get_global_rect()))
	sword.mouse_exited.connect(controller.hide_details)
	_button("结束回合  ›",Rect2(1100,652,150,44),func():controller.submit({"kind":"end","actor":"p"}),"end_window")
	notice=_label("",Rect2(365,569,700,27),14,Color("e8d3a1"));controls.receipt=notice
	own_buff_root=Control.new();_place(own_buff_root,Rect2(24,600,270,26));own_buff_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	enemy_badge=_button("",Rect2(0,0,186,22),func():controller.select_target("e"),"enemy_badge")
	for part in ["normal","pressed","hover","focus"]:enemy_badge.add_theme_stylebox_override(part,StyleBoxEmpty.new())
	enemy_health=Health.new();enemy_health.quantized=true;_place(enemy_health,Rect2(0,0,186,9))
	enemy_buff_root=Control.new();_place(enemy_buff_root,Rect2(0,0,270,26));enemy_buff_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	menu=_panel(Rect2(1055,59,199,185));menu.hide()
	_button("事件 / AI记录",Rect2(12,16,175,36),func():menu.hide();controller.show_logs(),"logs",menu)
	_button("操作帮助",Rect2(12,66,175,36),func():menu.hide();controller.show_help(),"help",menu)
	_button("中止训练",Rect2(12,116,175,36),func():menu.hide();controller.show_abort(),"abort",menu)
	inspector=_panel(Rect2(966,135,290,425));inspector.hide()
	_label("人物信息 · 测试版",Rect2(16,12,235,28),16,Color("dbbe88"),inspector)
	_button("×",Rect2(252,9,28,28),func():inspected="";inspector.hide(),"inspector_close",inspector)
	inspector_body=RichTextLabel.new();inspector_body.bbcode_enabled=true;inspector_body.add_theme_font_size_override("normal_font_size",15)
	_place(inspector_body,Rect2(16,53,258,349),inspector)

func _place(node:Control,rect:Rect2,parent:Control=null):
	(parent if parent!=null else self).add_child(node);node.position=rect.position;node.size=rect.size;return node
func _label(text:String,rect:Rect2,font_size:int,color:Color,parent:Control=null)->Label:
	var label=Label.new();label.text=text;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE;return _place(label,rect,parent)
func _button(text:String,rect:Rect2,callback:Callable,key:String,parent:Control=null)->Button:
	var button=controller.button(text,rect,callback,key,self if parent==null else parent)
	controls[key]=button;return button
func _panel(rect:Rect2)->Panel:return controller.panel(rect,Color(0.035,0.065,0.07,0.96),self)

func set_view(units:Array,current:String,clock_event:bool=false):
	rows=units.duplicate(true)
	timeline.paused=controller.paused
	if clock_event or timeline.rows.is_empty():timeline.set_view(rows,current,clock_event)
	else:timeline.active=current;timeline.queue_redraw()
	for row in rows:
		if gauge_bars.has(row.id):
			gauge_bars[row.id].max_value=controller.battle.state.snapshot.opportunity.maximum;gauge_bars[row.id].value=row.Z
			gauge_labels[row.id].text="%d / %d%s"%[row.Z,controller.battle.state.snapshot.opportunity.maximum," · 已就绪" if row.opportunity_pending else " · 待普通回合解锁" if row.opportunity_locked else ""]
		if row.id=="p":
			player_health.set_health(int(row.H),int(row.Hmax));controls.player_hp.text="气血 %d / %d"%[row.H,row.Hmax]
			player_mana.max_value=row.M;player_mana.value=row.E
			player_values.text="灵气 %d / %d"%[row.E,row.M]
			if preview_cost>=0:
				player_values.text+="  → %d"%[preview_after if preview_after>=0 else maxi(0,int(row.E)-preview_cost)]
				mana_preview.position=Vector2(82+186*maxf(0,float(row.E-preview_cost))/row.M,678)
				mana_preview.size=Vector2(186*minf(row.E,preview_cost)/row.M,9);mana_preview.show()
			else:mana_preview.hide()
		else:
			enemy_health.set_health(int(row.H),int(row.Hmax));enemy_badge.text=row.name
			var head=controller.stage.diorama.actor_head_screen("e")
			enemy_badge.position=head-Vector2(93,49);enemy_health.position=head-Vector2(93,24);enemy_buff_root.position=head-Vector2(93,6)
	var signature=""
	for row in rows:signature+=str(row.buffs)
	if signature!=buff_signature:
		buff_signature=signature
		for root in [own_buff_root,enemy_buff_root]:
			for child in root.get_children():root.remove_child(child);child.queue_free()
		for row in rows:
			var root=own_buff_root if row.id=="p" else enemy_buff_root
			var i=0
			for buff in row.buffs:
				var icon=Tile.new();icon.artwork=P.icon(buff);_place(icon,Rect2(i*29,0,25,25),root)
				icon.mouse_entered.connect(func():controller.show_details({"title":buff,"grade":"Buff · %d"%int(row.buffs[buff]),"effect":P.BUFF_EFFECTS[buff]},icon.get_global_rect()))
				icon.mouse_exited.connect(controller.hide_details)
				i+=1
	if inspected!="":inspect(inspected)

func inspect(id:String):
	inspected=id;inspector.show()
	var unit=controller.battle.unit(id).duplicate(true)
	for row in rows:
		if row.id==id:unit.merge(row,true)
	var names:Array=[]
	for entry in unit.entries:
		var name=controller.catalog.techniques.get(entry.technique,{}).get("name","空槽")
		var status="本回合已用" if entry.used else "还差%d次出手"%P.remaining(entry,unit,controller.catalog) if P.remaining(entry,unit,controller.catalog)>0 else "可用"
		names.append(name+" · "+status)
	var artifact_names:Array=[]
	for entry in unit.art_entries:
		var a=controller.catalog.artifacts[entry.artifact]
		var status="自动"+("停用" if not entry.enabled else "启用")
		if a.has("active"):status+=" / 催"+("本窗已用" if entry.active_used else "还差%d次"%maxi(0,int(entry.active_ready_window)-int(unit.W)) if entry.active_ready_window>unit.W else "可用")
		artifact_names.append(a.name+" · "+status)
	var buffs:Array=[]
	for buff in unit.buffs:buffs.append("%s · %d"%[buff,int(unit.buffs[buff])])
	inspector_body.text="[color=#dfc18b][font_size=22]%s[/font_size][/color]\n\n气血 %d / %d\n灵气 %d / %d\n自然回气 %d\n速度 %d · 效能 %d\n普通 %d · 战机 %d\n\n[color=#96bda9]已装备功法[/color]\n%s\n\n[color=#96bda9]法宝[/color]\n%s\n\n[color=#96bda9]当前Buff[/color]\n%s"%[unit.name,unit.H,unit.Hmax,unit.E,unit.M,unit.Q,unit.S,unit.P,unit.R,unit.W-unit.R,"\n".join(names),"\n".join(artifact_names) if not artifact_names.is_empty() else "无","\n".join(buffs) if not buffs.is_empty() else "无"]

func preview(value:int,after:int=-1):
	preview_cost=value;preview_after=after
	if not rows.is_empty():set_view(rows,timeline.active)
