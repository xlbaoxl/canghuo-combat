extends Panel
const P=preload("res://scripts/presentation.gd")
const BUFF_NAME_COLOR="#e8bd72"
const WIDTH=394.0
var model:Dictionary={}
var body:RichTextLabel
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var skin=StyleBoxFlat.new();skin.bg_color=Color(0.035,0.065,0.07,0.98);skin.border_color=Color("b2a371")
	skin.set_border_width_all(1);skin.set_corner_radius_all(4);skin.shadow_size=10
	add_theme_stylebox_override("panel",skin)
	body=RichTextLabel.new();add_child(body);body.position=Vector2(18,14);body.size=Vector2(WIDTH-36,288)
	body.bbcode_enabled=true;body.scroll_active=false;body.mouse_filter=Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_size_override("normal_font_size",16)
	set_model(model)
func set_model(value:Dictionary):
	model=value
	if body==null:return
	var color:Color=model.get("color",Color("dbbd82"))
	var text="[color=#%s][font_size=22]%s[/font_size][/color]   [color=#a8b9aa]%s[/color]\n\n"%[color.to_html(false),model.get("title",""),model.get("grade","")]
	text+="[color=#eee7d1]%s[/color]\n\n"%highlight_buff_names(model.get("effect",""))
	if not model.get("formula_detail","").is_empty():text+="[color=#98b49d]%s[/color]\n\n"%model.formula_detail
	if model.has("F"):text+="[color=#85cddb]装配灵感 %d[/color]\n"%model.F
	if model.has("cost"):
		text+="[color=#85cddb]灵气消耗 %d     CD %d（自身出手机会）[/color]\n"%[model.cost,model.cooldown]
		text+="灵气 [color=#d9e4da]%d[/color] → [color=#%s]%d[/color]（%s）\n"%[model.before,"e19978" if model.before<model.cost else "87d5bd",model.after,model.get("after_label","扣费后")]
		if int(model.get("hp_cost",0))>0:text+="[color=#d99b81]气血支付 %d[/color]\n"%model.hp_cost
		if not model.get("availability","").is_empty():text+="[color=#d5b38c]%s[/color]\n"%model.availability
	var buffs:Array=model.get("buff_details",[])
	if not buffs.is_empty():
		text+="\n"
		for i in range(buffs.size()):
			text+="%s：[color=#bccbc0]%s[/color]"%[buff_name_span(buffs[i].name),highlight_buff_names(buffs[i].effect)]
			if i<buffs.size()-1:text+="\n"
	body.text=text
	size=Vector2(WIDTH,clampf(body.get_content_height()+34,140,676))
	body.size.y=size.y-28

func buff_name_span(name:String)->String:
	return "[color=%s][b]%s[/b][/color]"%[BUFF_NAME_COLOR,name]

func highlight_buff_names(description:String)->String:
	var names=P.BUFF_EFFECTS.keys()
	names.sort_custom(func(a,b):return a.length()>b.length())
	var result=""
	var offset=0
	while offset<description.length():
		var matched=false
		for name in names:
			if description.substr(offset,name.length())==name:
				result+=buff_name_span(name)
				offset+=name.length()
				matched=true
				break
		if not matched:
			var character=description.substr(offset,1)
			result+="[lb]" if character=="[" else ("[rb]" if character=="]" else character)
			offset+=1
	return result
