extends Button
signal dropped(payload:Dictionary)
var item_id:String=""
var slot_index:int=-1
var kind:String="techniques"
var card:bool=false
var grade:int=1
var selected:bool=false
var spent:bool=false
var remaining:int=0
var artwork:Texture2D
var title:String=""
var subtitle:String=""
var key_hint:String=""
var drag_enabled:bool=false

func _ready():
	text="";focus_mode=Control.FOCUS_NONE
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled","focus"]:add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw);mouse_exited.connect(queue_redraw)

func _draw():
	var colors=[Color("83baa6"),Color("73b9d0"),Color("ddad67")]
	var tint=colors[clampi(grade-1,0,2)]
	var rect=Rect2(Vector2(1,1),size-Vector2(2,2))
	draw_style_box(_frame(Color("172c2d") if card else Color("132426"),tint if selected or is_hovered() else Color("5d6756")),rect)
	var icon_rect=Rect2(7,7,size.x-14,size.y-14)
	if card:
		# Reserve the book cover area independently of the eventual raster artwork.
		icon_rect=Rect2(15,16,62,86)
		draw_rect(Rect2(12,12,68,94),Color("0d1b20"))
		draw_rect(Rect2(12,12,68,94),tint,false,1)
		draw_style_box(_frame(Color("28433d"),Color("89967d")),Rect2(19,18,54,78))
		for y in [27,45,67,85]:draw_line(Vector2(23,y),Vector2(28,y),Color("c9bc87"),2)
		icon_rect=Rect2(29,34,38,44)
	if artwork!=null:draw_texture_rect(artwork,icon_rect,false,Color(1,1,1,0.36) if disabled or spent else Color.WHITE)
	if disabled or spent:draw_rect(rect,Color(0.01,0.025,0.03,0.36))
	if remaining>0:
		draw_arc(size*0.5,minf(size.x,size.y)*0.4,-PI/2,PI*1.4,36,Color("7b8f91"),2,true)
		_text(str(remaining),Vector2(size.x*0.5-7,size.y*0.5+8),24,Color("eee4c9"))
	elif spent:_text("✓",Vector2(size.x-24,25),20,Color("b5c8b0"))
	if card:
		_text(title,Vector2(92,39),17,Color("f0e6cf"),size.x-105)
		_text(subtitle,Vector2(92,67),13,tint,size.x-105)
		_text("悬停查看效果",Vector2(92,94),12,Color("8fa79d"),size.x-105)
	elif key_hint!="":_text(key_hint,Vector2(6,size.y-5),12,Color("d5caac"))
	if selected:draw_rect(rect,tint,false,2)

func _frame(bg:Color,border:Color)->StyleBoxFlat:
	var box=StyleBoxFlat.new();box.bg_color=bg;box.border_color=border
	box.set_border_width_all(1);box.set_corner_radius_all(3)
	return box
func _text(value:String,at:Vector2,font_size:int,color:Color,width:float=-1):
	draw_string(get_theme_font("font"),at,value,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,color)
func refresh():queue_redraw()
func _get_drag_data(_position:Vector2):
	if not drag_enabled or item_id=="":return null
	var preview=TextureRect.new();preview.texture=artwork;preview.custom_minimum_size=Vector2(54,54)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return {"item":item_id,"kind":kind}
func _can_drop_data(_position:Vector2,payload):
	return slot_index>=0 and payload is Dictionary and payload.get("kind")==kind
func _drop_data(_position:Vector2,payload):dropped.emit(payload)
