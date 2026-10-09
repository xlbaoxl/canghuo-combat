extends RefCounted
const Protocol=preload("res://scripts/combat_protocol.gd")
const Math=preload("res://scripts/effect_math.gd")

const BUFFS={
	"护体":"每层抵挡1点直接伤害，总量不超过气血上限；不挡效果伤害或气血支付。",
	"锋锐":"本人每次直接攻击，对每目标加成不超过基础量；整次攻击后减1层。自动法宝不借用；主动催动中的本人攻击正常适用。",
	"神速":"每层使普通行动条每刻多增长1，不改变速度排序或战机自然增长。",
	"凝神":"每层使一次主动施法的灵气费用减少1，最低0；不减CD。",
	"鲸吞":"每层使每公共刻自然回气增加1。",
	"回春":"每公共刻恢复当前层数的气血，然后减1层；与周期伤害同时结算。",
	"侵袭":"每公共刻造成当前层数的效果伤害，然后层数减半向下取整。",
	"蚀骨":"仅在自己的普通回合前，每层造成当前气血1%的效果伤害；战机前不触发。",
	"撕裂":"每层使一次主动施法气血支付增加1；仅普通回合结束层数减半。",
	"逆气":"每层使一次主动施法灵气费用增加1，不改变CD。",
	"滞气":"每层使每公共刻自然回气减少1，最低1；不关闭法宝。",
	"无常印记":"只保存层数，由明确的功法读取或消耗，不自行产生收益。"
}
const DEBUFFS=["侵袭","蚀骨","撕裂","逆气","滞气"]
const OPS=["damage","heal","qi","apply","remove","consume"]
var data:Dictionary={}
var techniques:Dictionary={}
var artifacts:Dictionary={}
var errors:Array=[]
var digest:String=""

func _init(input:Dictionary={}):
	var loaded=input if not input.is_empty() else JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	if not loaded is Dictionary:
		errors.append("内容不是JSON对象")
		return
	data=loaded.duplicate(true)
	digest=JSON.stringify(data).sha256_text()
	if data.get("rules","")!=Protocol.RULES:errors.append("战斗规则版本不匹配")
	for row in data.get("techniques",[]):
		var r=compile(row)
		if r.ok and not techniques.has(row.id):techniques[row.id]=r.value
		else:errors.append(str(row.get("id","?"))+": "+r.get("reason","重复成品ID"))
	for row in data.get("artifacts",[]):
		var r=compile_artifact(row)
		if r.ok and not artifacts.has(row.id):artifacts[row.id]=r.value
		else:errors.append(str(row.get("id","?"))+": "+r.get("reason","重复法宝ID"))

func bad(reason:String)->Dictionary:return {"ok":false,"reason":reason}

func compile(row:Dictionary)->Dictionary:
	var v=row.duplicate(true)
	if not v.has_all(["id","source_family_id","proficiency_group_id","version","capacity","prepared_qi_cost","sentences"]):return bad("缺少成品结构／系列字段")
	if not Protocol.whole(v.prepared_qi_cost) or not Protocol.whole(v.get("hp_cost",0)):return bad("费用必须为非负整数")
	if not Protocol.whole(v.capacity,1,3):return bad("只开放一至三句容量")
	if not v.sentences is Array or v.sentences.is_empty():return bad("成品必须包含合法功能句")
	if v.has("requires"):
		if not v.requires is Dictionary or not BUFFS.has(v.requires.get("buff","")) or not Protocol.whole(v.requires.get("min",1),1):return bad("整门前提非法")
		if not v.requires.get("target","primary") in ["primary","self"]:return bad("前提目标非法")
	var expanded:Array=[]
	var known:Dictionary={}
	for source in v.sentences:
		if not source is Dictionary:return bad("功能句必须是对象")
		var s=source.duplicate(true)
		if not s.has_all(["op","id","amount","target"]) or not s.op in OPS:return bad("未知操作或缺少句字段")
		if not s.id is String or s.id.is_empty():return bad("功能句ID非法")
		if not s.target in ["self","enemy","ally","all_enemies"]:return bad("目标方案未知")
		if s.op in ["apply","remove","consume"] and not (BUFFS.has(s.get("buff","")) or (s.op=="remove" and s.get("buff","")=="debuffs")):return bad("状态不在白名单")
		if s.op=="damage" and not s.get("nature","direct") in ["direct","effect"]:return bad("伤害性质未知")
		if s.op=="qi" and not s.get("direction","ADD") in ["ADD","SUB"]:return bad("灵气操作方向未知")
		if not s.get("mode","QUANTITY") in ["QUANTITY","ALL"]:return bad("状态操作模式未知")
		if s.get("mode","")=="ALL" and not s.op in ["remove","consume"]:return bad("ALL仅用于显式移除／消耗")
		if s.has("condition"):
			if not s.condition is Dictionary or not BUFFS.has(s.condition.get("buff","")) or not Protocol.whole(s.condition.get("min",1),0):return bad("句内条件非法")
			if not s.condition.get("read_at","") in ["CAST_START","GROUP_START"]:return bad("句内条件未声明读取时点")
		if s.has("step_cost"):
			if not s.step_cost is Dictionary:return bad("分步费用非法")
			for key in s.step_cost:
				if not key in ["qi","hp"] or not Protocol.whole(s.step_cost[key]):return bad("分步费用只接受非负气血／灵气")
		var error=Math.validate(s.amount,known,BUFFS)
		if not error.is_empty():return bad(error)
		if not Protocol.whole(s.get("repeat",1),1,3):return bad("独立执行次数必须是1至3整数")
		var count=int(s.get("repeat",1))
		for i in range(count):
			var e=s.duplicate(true)
			e.id=s.id if count==1 else s.id+"."+str(i)
			if known.has(e.id):return bad("重复展开句ID")
			e.execution_id=i
			e.erase("repeat")
			expanded.append(e)
			known[e.id]=s.op
	if expanded.size()>int(v.capacity):return bad("展开后超过结构容量")
	v.sentences=expanded
	v.N=expanded.size()
	v.CD=v.N
	v.erase("k")
	v.prepared_qi_cost=int(v.prepared_qi_cost)
	v.hp_cost=int(v.get("hp_cost",0))
	return {"ok":true,"value":v,"reason":""}

func compile_artifact(row:Dictionary)->Dictionary:
	if not row.has_all(["id","name","source_family_id","F","trigger","auto"]):return bad("法宝缺少字段")
	if row.has("active") and not row.active is Dictionary:return bad("催动必须是独立成品对象")
	if not Protocol.whole(row.F,0,1000):return bad("法宝额度非法")
	if not row.trigger in ["BATTLE_ENTRY","NORMAL_OPENED","HP_DAMAGE_TAKEN"]:return bad("自动触发节点未开放")
	if row.trigger=="HP_DAMAGE_TAKEN" and not Protocol.whole(row.get("threshold",0),1,100):return bad("低血阈值非法")
	var v={"id":"auto_"+row.id,"source_family_id":row.source_family_id,"proficiency_group_id":"artifact","version":1,"capacity":3,"prepared_qi_cost":0,"sentences":[]}
	for i in range(row.auto.size()):
		var s=row.auto[i].duplicate(true)
		s.id="auto"+str(i)
		if s.has("step_cost") or (s.amount is Dictionary and s.amount.get("kind","")=="scaled"):return bad("自动法宝不借用主人支付／凝练")
		v.sentences.append(s)
	var result=compile(v)
	if not result.ok:return result
	var a=row.duplicate(true)
	a.auto=result.value.sentences
	a.F=int(a.F)
	if row.has("active"):
		var active=compile(row.active)
		if not active.ok:return bad("催动："+active.reason)
		if not str(active.value.source_family_id).begins_with("catalyst:"):return bad("催动同源ID必须与功法命名空间分开")
		a.active=active.value
	return {"ok":true,"value":a,"reason":""}

func character(id:String)->Dictionary:
	for row in data.get("characters",[]):
		if row.id==id:return row.duplicate(true)
	return {}

func opponent(id:String)->Dictionary:
	for row in data.get("enemies",[]):
		if row.id==id:return row.duplicate(true)
	return {}

func validate_mastery(m:Dictionary)->Dictionary:
	if not Protocol.whole(m.get("effect_power",-1),0,10000):return bad("必须显式填写人物效能P")
	for kind in ["series_levels","technique_levels"]:
		if not m.get(kind,{}) is Dictionary:return bad("熟练记录类型非法")
		for level in m.get(kind,{}).values():
			if not Protocol.whole(level,0,2):return bad("训练熟练等级只允许0至2")
	return {"ok":true,"reason":""}

func validate(stats:Dictionary,slots:Array,arts:Array)->Dictionary:
	for k in ["Hmax","M","Q","S"]:
		if not Protocol.whole(stats.get(k,-1),1):return bad("人物属性非法："+k)
	if slots.size()!=4 or arts.size()>2:return bad("需要四个功法格、至多两个法宝位置")
	var families:Array=[]
	var cost=0
	var active=0
	for id in slots:
		if id=="":continue
		if not techniques.has(id):return bad("未发布成品："+str(id))
		var v=techniques[id]
		if families.has(v.source_family_id):return bad("同源功法不能重复："+v.name)
		families.append(v.source_family_id)
		cost+=int(v.prepared_qi_cost)
		active+=1
	if active==0:return bad("至少装备一门主动功法")
	if cost>int(stats.M):return bad("承载超限：%d / %d 灵气"%[cost,stats.M])
	families=[]
	var F=0
	for id in arts:
		if id=="":continue
		if not artifacts.has(id):return bad("未发布法宝："+str(id))
		if families.has(artifacts[id].source_family_id):return bad("同源法宝不能重复")
		families.append(artifacts[id].source_family_id)
		F+=int(artifacts[id].F)
	if F>int(stats.Q):return bad("灵感超限：%d / %d 基础回气"%[F,stats.Q])
	return {"ok":true,"reason":"合法 · 承载 %d/%d · 灵感 %d/%d"%[cost,stats.M,F,stats.Q],"load":cost,"F":F}

func apply_profile(p:Dictionary,profile_id:String)->void:
	for profile in data.get("growth_profiles",[]):
		if profile.id!=profile_id:continue
		p.mastery.effect_power=int(profile.P)
		p.mastery.series_levels={}
		p.mastery.technique_levels={}
		for v in techniques.values():
			p.mastery.series_levels[v.proficiency_group_id]=int(profile.series_level)
			p.mastery.technique_levels[v.source_family_id]=int(profile.technique_level)
		p.growth_profile=profile_id
		return

func snapshot(char_id:String,slots:Array,arts:Array,mode:String,choice:String,seed:int=103,order:Array=["p","e"],profile_id:String="base",disabled_artifacts:Array=[])->Dictionary:
	if not errors.is_empty():return bad("内容校验失败："+str(errors))
	var p=character(char_id)
	if p.is_empty():return bad("人物不存在")
	if not data.growth_profiles.any(func(x):return x.id==profile_id):return bad("成长快照未发布")
	for id in disabled_artifacts:
		if not arts.has(id):return bad("停用项不属于当前法宝装配")
	apply_profile(p,profile_id)
	var legal=validate(p.stats,slots,arts)
	if not legal.ok:return legal
	p.slots=slots.duplicate(true)
	p.artifacts=arts.duplicate(true)
	p.disabled_artifacts=disabled_artifacts.duplicate(true)
	p.team=0
	p.unit_id="p"
	p.opportunity_enabled=true
	var e:Dictionary={}
	var ai=""
	var title=""
	if mode=="mirror":
		var diff:Dictionary={}
		for d in data.difficulties:
			if d.id==choice:diff=d
		if diff.is_empty():return bad("镜像难度未知")
		e=p.duplicate(true)
		e.name=p.name+"·镜像"
		e.stats.Hmax=round_ratio(int(e.stats.Hmax)*int(diff.percent),100)
		e.stats.S=maxi(1,round_ratio(int(e.stats.S)*int(diff.percent),100))
		ai=diff.ai
		title="镜像 · "+diff.name
	elif mode=="preset":
		e=opponent(choice)
		if e.is_empty():return bad("预设对手不存在")
		e.disabled_artifacts=[]
		ai=e.ai
		title="预设 · "+e.name
	else:return bad("战斗模式未知")
	e.team=1
	e.unit_id="e"
	e.opportunity_enabled=true
	legal=validate(e.stats,e.slots,e.artifacts)
	if not legal.ok:return bad("敌方配置非法："+legal.reason)
	for config in [p,e]:
		var m=validate_mastery(config.mastery)
		if not m.ok:return m
	var payload={"rules":Protocol.RULES,"content":data.version,"content_digest":digest,"save_schema":Protocol.SAVE_SCHEMA,"mode":mode,"choice":choice,"title":title,"seed":seed,"order":order.duplicate(),"units":[p,e],"enemy_ai":ai,"opportunity":data.opportunity.duplicate(true),"limits":data.limits.duplicate(true),"growth_profile":profile_id}
	payload.loadout_hash=JSON.stringify({"player":p,"rules":payload.rules,"content":digest}).sha256_text()
	return {"ok":true,"value":payload,"reason":""}

func validate_snapshot(s:Dictionary)->Dictionary:
	if s.get("rules","")!=Protocol.RULES or s.get("save_schema",0)!=Protocol.SAVE_SCHEMA:return bad("旧规则快照不能直接续战；请保留原档并从配装重新开战")
	if s.get("content","")!=data.version or s.get("content_digest","")!=digest:return bad("内容版本已变化；请重新确认战前快照")
	if not s.get("units",[]) is Array or s.units.size()<2:return bad("战斗单位不足")
	if not s.get("order",[]) is Array:return bad("缺少固定行动顺序")
	var ids:Array=[]
	for u in s.units:
		if not u is Dictionary or not u.has_all(["unit_id","team","stats","slots","artifacts","mastery"]):return bad("单位缺少开局字段")
		if not u.stats is Dictionary or not u.slots is Array or not u.artifacts is Array or not u.mastery is Dictionary:return bad("单位输入字段类型非法")
		if not Protocol.whole(u.team,0,1):return bad("训练阵营非法")
		if ids.has(u.unit_id) or not s.order.has(u.unit_id):return bad("单位ID重复或没有固定次序")
		ids.append(u.unit_id)
		if not u.get("basic_attack",{}) is Dictionary or not Math.validate(u.get("basic_attack",{}),{},BUFFS).is_empty():return bad("基础攻击表达式非法")
		var check=validate(u.stats,u.slots,u.artifacts)
		if not check.ok:return check
		check=validate_mastery(u.mastery)
		if not check.ok:return check
		for key in u.get("initial_buffs",{}):
			if not BUFFS.has(key) or not Protocol.whole(u.initial_buffs[key]):return bad("初始状态非法")
	if s.order.size()!=ids.size():return bad("固定次序与单位数量不匹配")
	for id in ids:
		if s.order.count(id)!=1:return bad("固定次序重复或缺失")
	var z=s.get("opportunity",{})
	for key in Protocol.GAUGE_DEFAULTS:
		if not Protocol.whole(z.get(key,-1),1 if key in ["maximum","combat_scale_ref"] else 0):return bad("战机参数非法："+key)
	if z.guard_weight!=0:return bad("防护来源奖励未开放，必须为0")
	for key in ["ticks","normal_windows","windows"]:
		if not Protocol.whole(s.get("limits",{}).get(key,-1),1):return bad("观察上限非法")
	return {"ok":true,"reason":""}

static func round_ratio(a:int,b:int)->int:return Protocol.round_ratio(a,b)
func describe(v:Dictionary)->String:return "%s\n灵气%d · CD%d（自己的出手机会，含战机）\n%s"%[v.name,v.prepared_qi_cost,v.CD,v.get("description","")]
