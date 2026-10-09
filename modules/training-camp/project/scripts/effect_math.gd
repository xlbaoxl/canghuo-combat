extends RefCounted
const Protocol=preload("res://scripts/combat_protocol.gd")
## Pure numeric resolver. It cannot mutate H/E, clocks, history or the UI.

static func growth_inputs(unit:Dictionary, variant:Dictionary)->Dictionary:
	var mastery=unit.get("mastery",{})
	var group=str(variant.get("proficiency_group_id",""))
	var family=str(variant.get("source_family_id",""))
	var sl=int(mastery.get("series_levels",{}).get(group,0))
	var tl=int(mastery.get("technique_levels",{}).get(family,0))
	return {"P":int(mastery.get("effect_power",20)),"series_bonus_bp":Protocol.SERIES_BP[clampi(sl,0,2)],"technique_bonus_bp":Protocol.TECHNIQUE_BP[clampi(tl,0,2)]}

static func rounded(n:int,d:int,mode:String="nearest")->int:
	if mode=="floor":return n/d
	if mode=="ceil":return Protocol.ceil_ratio(n,d)
	return Protocol.round_ratio(n,d)

static func root_amount(expr:Dictionary, growth:Dictionary)->int:
	var den=int(expr.get("a_den",1))
	var numerator=int(expr.base)*den+int(expr.get("a_num",0))*int(growth.P)
	var factor=10000
	if expr.get("proficiency",true):factor+=int(growth.series_bonus_bp)+int(growth.technique_bonus_bp)
	return rounded(numerator*factor,den*10000,str(expr.get("round","nearest")))

static func validate(expr, known:Dictionary, buffs:Dictionary)->String:
	if expr is int or expr is float:
		return "" if Protocol.whole(expr) else "效量必须是范围内的非负整数"
	if not expr is Dictionary:return "不支持的效量表达式"
	if not str(expr.get("round","nearest")) in ["nearest","floor","ceil"]:return "取整模式未知"
	if expr.get("kind","")=="scaled":
		if not expr.has("base") or not Protocol.whole(expr.base) or not Protocol.whole(expr.get("a_num",0),0,1000) or not Protocol.whole(expr.get("a_den",1),1,10000):return "成长系数非法"
		for key in expr:
			if not key in ["kind","base","a_num","a_den","proficiency","round"]:return "根效量包含未定义字段"
		return ""
	for key in expr:
		if not key in ["ref","field","ref_target","buff","stat","read_at","read_target","num","den","round","max","fallback"]:return "表达式包含未定义字段"
	var sources=int(expr.has("ref"))+int(expr.has("buff"))+int(expr.has("stat"))
	if sources!=1:return "表达式必须且只能有一个读取来源"
	if not Protocol.whole(expr.get("den",1),1,10000) or not Protocol.whole(expr.get("num",1),0,10000):return "比例系数非法"
	if expr.has("max") and not Protocol.whole(expr.max):return "效量上限非法"
	if expr.has("fallback") and not Protocol.whole(expr.fallback):return "替代值非法"
	if expr.has("ref"):
		if not known.has(expr.ref):return "引用必须指向已完成前句，不可未来引用或成环"
		if not expr.has("field") or not expr.field in Protocol.RESULT_FIELDS[known[expr.ref]]:return "结果字段与前句操作类型不匹配"
		if not expr.get("ref_target","target") in ["target","primary","self"]:return "结果目标未知"
		if expr.has("read_at") or expr.has("growth"):return "派生引用不重复绑定成长或实时读取"
	else:
		if not expr.get("read_at","") in ["CAST_START","GROUP_START"]:return "属性／状态读取必须声明时点"
		if not expr.get("read_target","") in ["target","self","primary"]:return "属性／状态读取必须声明目标"
		if expr.has("buff") and not buffs.has(expr.buff):return "读取未知状态"
		if expr.has("stat") and not expr.stat in Protocol.STATS:return "越权属性读取"
	return ""

static func resolve(expr, owner:Dictionary, tid:String, primary:String, records:Dictionary, group_units:Dictionary, cast_units:Dictionary, growth:Dictionary):
	if not expr is Dictionary:return int(expr)
	if expr.get("kind","")=="scaled":return root_amount(expr,growth)
	var value=0
	if expr.has("ref"):
		var ref_target=tid
		if expr.get("ref_target","target")=="self":ref_target=owner.id
		elif expr.get("ref_target","target")=="primary":ref_target=primary
		var record=records.get(expr.ref,{}).get(ref_target,{})
		if record.get("status","")!="executed":
			if expr.has("fallback"):value=int(expr.fallback)
			else:return null
		else:value=int(record[expr.field])
	else:
		var source=group_units if expr.read_at=="GROUP_START" else cast_units
		var read_id=owner.id if expr.read_target=="self" else primary if expr.read_target=="primary" else tid
		if not source.has(read_id):return int(expr.fallback) if expr.has("fallback") else null
		var u=source[read_id]
		value=int(u.get("buffs",{}).get(expr.buff,0)) if expr.has("buff") else int(u.get(expr.stat,0))
	var amount=rounded(value*int(expr.get("num",1)),int(expr.get("den",1)),str(expr.get("round","nearest")))
	return mini(amount,int(expr.get("max",100000000)))

static func describe(expr, growth:Dictionary)->String:
	if not expr is Dictionary:return str(int(expr))
	if expr.get("kind","")=="scaled":return str(root_amount(expr,growth))
	if expr.has("ref"):
		var terms={"hp_loss":"实际气血伤害","shield_absorbed":"实际护体吸收","layers_added":"实际新增层数","layers_removed":"实际消耗／移除层数","hp_restored":"实际恢复","damage_request":"伤害请求"}
		return "%s的%s×%d/%d"%[expr.ref,terms.get(expr.field,expr.field),int(expr.get("num",1)),int(expr.get("den",1))]
	return "%s×%d/%d"%[expr.get("buff",expr.get("stat","")),int(expr.get("num",1)),int(expr.get("den",1))]
