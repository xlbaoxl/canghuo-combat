extends RefCounted
## The player's wording is rendered from the same compiled expression as execution.
const Catalog=preload("res://scripts/catalog.gd")
const Math=preload("res://scripts/effect_math.gd")
const Protocol=preload("res://scripts/combat_protocol.gd")
const BUFF_EFFECTS=Catalog.BUFFS
const GRADE_NAMES=["","初级","中级","高级"]
const GRADE_COLORS=[Color.WHITE,Color("83baa6"),Color("73b9d0"),Color("ddad67")]

static func grade(v:Dictionary)->int:return clampi(int(v.get("N",1)),1,3)
static func icon(id:String)->Texture2D:
	return load("res://assets/skill_icons/"+id+".svg") if ResourceLoader.exists("res://assets/skill_icons/"+id+".svg") else load("res://assets/icons/blade.svg")

static func target_name(value:String)->String:
	return {"self":"自身","enemy":"选定敌人","ally":"选定友方","all_enemies":"所有存活敌人"}.get(value,value)

static func effect(v:Dictionary,player:Dictionary={})->String:
	var growth=Math.growth_inputs(player,v)
	var lines:Array=[]
	for index in range(v.get("sentences",[]).size()):
		var s=v.sentences[index]
		var amount=Math.describe(s.amount,growth)
		var who=target_name(s.target)
		var line=""
		match s.op:
			"damage":line="对%s造成%s点%s伤害。"%[who,amount,"效果" if s.get("nature","direct")=="effect" else "直接"]
			"heal":line="为%s恢复%s点气血。"%[who,amount]
			"qi":line="%s%s点灵气。"%["移除"+who+"的" if s.get("direction","ADD")=="SUB" else "为"+who+"恢复",amount]
			"apply":line="为%s施加%s层%s。"%[who,amount,s.buff]
			"remove","consume":line="%s%s的%s%s。"%["消耗" if s.op=="consume" else "移除",who,"全部" if s.get("mode","")=="ALL" else amount+"层", "减益状态" if s.buff=="debuffs" else s.buff]
		if s.has("condition"):line="条件：目标有至少%d层%s时，%s"%[s.condition.get("min",1),s.condition.buff,line]
		if v.sentences.size()>1:line="%d. %s"%[index+1,line]
		lines.append(line)
	if v.has("requires"):lines.push_front("施展前提：目标至少有%d层%s。"%[v.requires.min,v.requires.buff])
	return "\n".join(lines)

static func formula_detail(v:Dictionary,player:Dictionary)->String:
	var g=Math.growth_inputs(player,v)
	for s in v.get("sentences",[]):
		if s.amount is Dictionary and s.amount.get("kind","")=="scaled":
			var e=s.amount
			var bp=g.series_bonus_bp+g.technique_bonus_bp if e.get("proficiency",true) else 0
			return "效量来源：基础%d＋效能%d×%d/%d；熟练合计＋%s%%。派生句不重复放大。"%[e.base,g.P,e.get("a_num",0),e.get("a_den",1),str(bp/100)]
	return ""

static func skill_model(v:Dictionary,player:Dictionary,battle=null,action:Dictionary={})->Dictionary:
	var cost={"qi":int(v.prepared_qi_cost),"hp":int(v.get("hp_cost",0))}
	var E=int(player.get("E",player.get("stats",{}).get("M",0)))
	if battle!=null:cost=battle.costs(player,v)
	var model={"id":v.id,"title":v.name,"grade":GRADE_NAMES[grade(v)],"color":GRADE_COLORS[grade(v)],"effect":effect(v,player),"formula_detail":formula_detail(v,player),"buff_details":buff_details(v),"cost":cost.qi,"hp_cost":cost.hp,"before":E,"after":maxi(0,E-int(cost.qi)),"cooldown":int(v.CD),"availability":"","type":"功法"}
	if battle!=null and not action.is_empty() and int(action.get("slot",-1))>=0:
		var is_catalyst=action.get("kind","")=="artifact"
		var entry=player.art_entries[int(action.slot)] if is_catalyst else player.entries[int(action.slot)]
		var ready=int(entry.active_ready_window) if is_catalyst else maxi(int(entry.ready_window),int(player.get("family_ready_window",{}).get(v.source_family_id,1)))
		var used=entry.active_used if is_catalyst else entry.used
		if used:model.availability="本窗口已操作；最早在自己的第%d次出手机会恢复。"%maxi(int(player.W)+1,ready)
		elif ready>int(player.W):model.availability="还差%d次自己的出手机会（含战机）。"%[ready-int(player.W)]
		elif E<int(cost.qi):model.availability="灵气不足：还差%d。"%[int(cost.qi)-E]
		elif int(player.get("H",player.get("stats",{}).get("Hmax",0)))<=int(cost.hp):model.availability="气血支付后必须存活。"
	return model

static func automatic_effect(a:Dictionary)->String:
	var trigger={"BATTLE_ENTRY":"入场一次","NORMAL_OPENED":"每个普通回合开始","HP_DAMAGE_TAKEN":"受敌方实际气血伤害后，存活且首次低于%d%%气血"%a.get("threshold",40)}.get(a.trigger,a.trigger)
	return trigger+"：\n"+effect({"sentences":a.auto},{})

static func passive_model(a:Dictionary,player:Dictionary)->Dictionary:
	return {"id":a.id,"title":a.name+"·自动","grade":"自动功效","type":"法宝","F":int(a.F),"effect":automatic_effect(a)+"\n只由事件触发，不能点击施放；不支付主人资源，不消耗主人锋锐。","buff_details":buff_details({"sentences":a.auto})}

static func catalyst_model(a:Dictionary,player:Dictionary,battle=null,action:Dictionary={})->Dictionary:
	if not a.has("active"):return {}
	var model=skill_model(a.active,player,battle,action)
	model.id=a.id;model.title=a.name+"·催";model.grade="主动催动";model.type="法宝"
	model.effect="【催】\n"+model.effect+"\n这是独立主动能力，不再执行自动功效。普通回合占一次主动作；战机内本入口至多一次。"
	return model

static func artifact_model(a:Dictionary,player:Dictionary,battle=null,action:Dictionary={})->Dictionary:
	if not action.is_empty():return catalyst_model(a,player,battle,action)
	var effects="【自动】"+automatic_effect(a)
	var refs={"sentences":a.auto.duplicate(true)}
	if a.has("active"):
		effects+="\n\n【催】\n"+effect(a.active,player)+"\n基础灵气费用%d · CD %d。与自动功效独立。"%[a.active.prepared_qi_cost,a.active.CD]
		refs.sentences.append_array(a.active.sentences)
		refs.requires=a.active.get("requires",{})
	return {"id":a.id,"title":a.name,"grade":"法宝 · 自动／催","type":"法宝","F":int(a.F),"effect":effects,"buff_details":buff_details(refs)}

static func remaining(entry:Dictionary,player:Dictionary,catalog=null)->int:
	var ready=int(entry.get("ready_window",1))
	if catalog!=null:
		var v=catalog.techniques.get(entry.technique,{})
		ready=maxi(ready,int(player.get("family_ready_window",{}).get(v.get("source_family_id",""),1)))
	return maxi(0,ready-int(player.get("W",0)))

static func buff_details(v:Dictionary)->Array:
	var names:Array=[]
	collect_buff_refs(v.get("sentences",[]),names);collect_buff_refs(v.get("requires",{}),names)
	var out:Array=[]
	for name in names:out.append({"name":name,"effect":BUFF_EFFECTS[name]})
	return out
static func collect_buff_refs(value,names:Array)->void:
	if value is Dictionary:
		if value.has("buff"):
			for name in Catalog.DEBUFFS if value.buff=="debuffs" else [value.buff]:
				if BUFF_EFFECTS.has(name) and not names.has(name):names.append(name)
		for child in value.values():collect_buff_refs(child,names)
	elif value is Array:
		for child in value:collect_buff_refs(child,names)
static func reason(text:String)->String:return text
