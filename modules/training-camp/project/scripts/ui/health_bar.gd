extends Control
var fraction:float=1.0
var quantized:bool=false
var lit_segments:int=10
var tint:Color=Color("83bf85")
func _ready():mouse_filter=Control.MOUSE_FILTER_IGNORE
func set_health(H:int,Hmax:int):
	fraction=clampf(float(H)/maxi(1,Hmax),0,1)
	lit_segments=clampi(ceili(fraction*10),0,10)
	tint=Color("75bc82") if fraction>0.5 else Color("e2c66a") if fraction>=0.2 else Color("d96b64")
	queue_redraw()
func _draw():
	var width=(size.x-18)/10
	for i in range(10):
		var rect=Rect2(i*(width+2),0,width,size.y)
		draw_rect(rect,Color("172424"))
		var filled=1.0 if i<lit_segments else 0.0
		if not quantized:filled=clampf(fraction*10-i,0,1)
		if filled>0:draw_rect(Rect2(rect.position,Vector2(rect.size.x*filled,rect.size.y)),tint)
