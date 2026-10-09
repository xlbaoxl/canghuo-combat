extends Control
signal actor_selected(id:String)
var rows:Array=[]
var displayed:Dictionary={}
var target:Dictionary={}
var previous:Dictionary={}
var phase:float=1.0
var active:String=""
var paused:bool=false
var history:Array=[]
func set_view(units:Array,current:String,animate:bool=true):
	rows=units.duplicate(true);active=current
	previous=displayed.duplicate()
	for row in rows:
		target[row.id]=float(row.A)
		if not displayed.has(row.id):displayed[row.id]=0.0;previous[row.id]=0.0
	phase=0.0 if animate else 1.0
	if not animate:displayed=target.duplicate()
	history.append(target.duplicate())
	if history.size()>300:history.pop_front()
	queue_redraw()
func _process(delta:float):
	if paused:return
	phase=minf(1,phase+delta/0.16)
	for id in target:displayed[id]=lerpf(previous.get(id,0.0),target[id],phase)
	queue_redraw()
func _draw():
	var font=get_theme_font("font")
	for i in range(rows.size()):
		var row=rows[i]
		var y=18.0+i*25.0
		var selected=active==row.id
		var color=Color("9dcbb2") if row.id=="p" else Color("d5a883")
		if not selected and active!="":color=color.darkened(0.42)
		draw_string(font,Vector2(0,y+5),"己方" if row.id=="p" else "对手",HORIZONTAL_ALIGNMENT_LEFT,47,12,color)
		draw_line(Vector2(53,y),Vector2(size.x-36,y),Color("203333"),5)
		var x=53+(size.x-89)*clampf(displayed.get(row.id,0.0)/100,0,1)
		draw_line(Vector2(53,y),Vector2(x,y),color,3)
		for division in range(11):
			var dx=53+(size.x-89)*division/10.0
			draw_line(Vector2(dx,y-3),Vector2(dx,y+3),Color(0.68,0.73,0.64,0.36),1)
		draw_circle(Vector2(x,y),7,color)
		if selected:draw_arc(Vector2(x,y),11,0,TAU,32,Color("edcf83"),2,true)
		draw_string(font,Vector2(size.x-29,y+5),"出手",HORIZONTAL_ALIGNMENT_LEFT,29,11,Color("bcbda2"))
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var index=int(event.position.y/25)
		if index>=0 and index<rows.size():actor_selected.emit(str(rows[index].id))
