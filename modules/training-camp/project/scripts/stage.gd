extends Control
signal target_clicked(id:String)
const Diorama=preload("res://scripts/stone_stage.gd")
var actors:Array=[]
var active:String=""
var selected_target:String=""
var current_event:Dictionary={}
var elapsed:float=0.0
var viewport:SubViewport
var diorama

func _ready()->void:
	viewport=SubViewport.new();viewport.size=Vector2i(1280,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_2X
	add_child(viewport)
	diorama=Diorama.new();viewport.add_child(diorama)
	# Restore the legacy full-stage camera; HUD elements float above it.
	diorama.camera.fov=43.0
	diorama.sync_visual(actors)

func set_actors(rows:Array,acting:String="")->void:
	actors=rows.duplicate(true);active=acting
	if diorama!=null:diorama.sync_visual(actors)
	queue_redraw()

func play(event:Dictionary)->void:
	current_event=event;elapsed=0
	if event.has("visual"):actors=event.visual.duplicate(true)
	if diorama!=null:diorama.animate(event)
	queue_redraw()

func _process(delta:float)->void:
	elapsed+=delta
	if diorama!=null:diorama.highlight_cell(diorama.get_actor_cell(selected_target if selected_target!="" else active))
	queue_redraw()

func target_point(id:String)->Vector2:
	return global_position+position_for(id)

func position_for(id:String)->Vector2:
	return diorama.actor_center_screen(id)*size/Vector2(1280,720) if diorama!=null else Vector2.ZERO

func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for id in ["p","e"]:
			var center=position_for(id)
			if Rect2(center-Vector2(85,110),Vector2(170,230)).has_point(event.position):
				target_clicked.emit(id);return

func _draw()->void:
	if viewport==null or diorama==null:return
	draw_texture_rect(viewport.get_texture(),Rect2(Vector2.ZERO,size),false)
	for id in ["p","e"]:
		var feet=diorama.actor_feet_screen(id)*size/Vector2(1280,720)
		if selected_target==id:draw_arc(feet,27,0,TAU,48,Color("f3d18d"),2,true)
	if not current_event.is_empty() and elapsed<0.65:
		var kind=str(current_event.get("kind",""))
		var from=position_for(current_event.get("actor","p"))
		var to=position_for(current_event.get("target","e"))
		if kind=="opportunity":
			draw_arc(from,38+elapsed*150,0,TAU,64,Color(0.95,0.78,0.37,1-elapsed),5,true)
		elif kind=="damage" and current_event.get("actor","")!="":
			var shot=from.lerp(to,clampf(elapsed/0.35,0,1))
			draw_line(shot-Vector2(34,0),shot,Color("ffd792"),4,true)
			draw_circle(shot,8,Color("ffe4af"))
		elif kind in ["apply","heal","qi"]:draw_arc(to,25+elapsed*100,0,TAU,48,Color(0.39,0.92,0.8,1-elapsed),3,true)
