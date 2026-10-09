extends RefCounted
## The authoritative transaction executor. No animation, wall clock or UI callback
## changes state. Both human input and AI forks enter through legal()/execute().
const Catalog=preload("res://scripts/catalog.gd")
const Protocol=preload("res://scripts/combat_protocol.gd")
const Math=preload("res://scripts/effect_math.gd")
var catalog
var state:Dictionary={}
var events:Array=[]
var event_count:int=0
var simulation:bool=false
var capture_visual:bool=false
var _draining:bool=false
var _dispatching:bool=false
var _root:Dictionary={}

func _init(content=null):catalog=content if content!=null else Catalog.new()

func start(snapshot:Dictionary)->Dictionary:
	var checked=catalog.validate_snapshot(snapshot)
	if not checked.ok:return checked
	events=[];event_count=0;_root={};_draining=false;_dispatching=false
	state={"snapshot":snapshot.duplicate(true),"rules":Protocol.RULES,"content":catalog.data.version,
		"battle_id":JSON.stringify(snapshot).sha256_text().substr(0,16),"phase":"INIT","t":0,
		"current":"","window_kind":"","window_id":"","window_seq":0,"units":[],
		"ended":false,"result":"","reason":"","cast_seq":0,"action_seq":0,"group_seq":0,
		"qualification_batch":0,"tickets":[],"responses":[],"ai_traces":[],"ai_budget":{},"revision":0}
	for config in snapshot.units:
		var u=config.duplicate(true)
		u.id=str(config.unit_id)
		for k in ["Hmax","M","Q","S"]:u[k]=int(config.stats[k])
		u.P=int(config.mastery.effect_power)
		u.H=u.Hmax;u.E=u.M;u.A=0;u.Z=0;u.W=0;u.R=0
		u.opportunity_enabled=bool(config.get("opportunity_enabled",false))
		u.opportunity_pending=false;u.opportunity_locked=false
		u.buffs=config.get("initial_buffs",{}).duplicate(true)
		u.hostile_status={}
		for key in u.buffs:
			if Catalog.DEBUFFS.has(key):u.hostile_status[key]=true
		if u.buffs.has("护体"):u.buffs["护体"]=mini(int(u.buffs["护体"]),u.Hmax)
		u.sword_used=false;u.main_used=false;u.swap_used=false;u.window_actions=0
		u.family_ready_window={};u.entries=[];u.art_entries=[]
		u.stats_log=_new_stats()
		for id in config.slots:u.entries.append({"technique":id,"ready_window":1,"used":false,"operation":"none"})
		for id in config.artifacts:
			if id!="":u.art_entries.append({"artifact":id,"triggered":false,"last_normal":0,"enabled":not config.get("disabled_artifacts",[]).has(id),"active_ready_window":1,"active_used":false})
		state.units.append(u)
	state.phase="ENTRY_RESOLVE"
	# All units exist before any entry effect; collection and execution are separate.
	for u in ordered_units():
		var e=record("BATTLE_ENTRY",u.id,u.id,{"kind":"entry"},context(u.id,"SYSTEM","entry"))
		collect_automatic(u,e)
	drain_responses()
	check_result()
	if not state.ended:advance()
	return {"ok":true}

func _new_stats()->Dictionary:
	var result={}
	for key in ["direct","effect","direct_taken","effect_taken","hp_cost","qi_cost","heal","shield","shield_absorbed","qi_gain","qi_removed","qi_overflow","heal_overflow","shield_overflow","casts","catalysts","swaps","windows","normal_windows","opportunity_windows","swords","automatic","empty","periodic_damage_requested","periodic_heal_requested","periodic_net","periodic_damage_only_actual","periodic_heal_only_actual","z_passive","z_damage","z_overflow","z_rejected"]:result[key]=0
	return result

func unit(id:String)->Dictionary:
	for u in state.get("units",[]):
		if u.id==id:return u
	return {}

func ordered_units()->Array:
	var result=state.units.duplicate()
	result.sort_custom(func(a,b):return order_index(a.id)<order_index(b.id))
	return result

func order_index(id:String)->int:
	var index=state.snapshot.order.find(id)
	return index if index>=0 else 100000

func enemies(actor:Dictionary)->Array:
	var result:Array=[]
	for u in ordered_units():
		if u.team!=actor.team and u.H>0:result.append(u.id)
	return result

func allies(actor:Dictionary)->Array:
	var result:Array=[]
	for u in ordered_units():
		if u.team==actor.team and u.H>0:result.append(u.id)
	return result

func view()->Array:
	var result:Array=[]
	for u in ordered_units():
		result.append({"id":u.id,"name":u.name,"art":u.get("art",""),"H":u.H,"Hmax":u.Hmax,"E":u.E,"M":u.M,"A":u.A,"Z":u.Z,"W":u.W,"R":u.R,"P":u.P,
			"buffs":u.buffs.duplicate(true),"entries":u.entries.duplicate(true),"art_entries":u.art_entries.duplicate(true),"family_ready_window":u.family_ready_window.duplicate(true),
			"main_used":u.main_used,"swap_used":u.swap_used,"sword_used":u.sword_used,"opportunity_pending":u.opportunity_pending,"opportunity_locked":u.opportunity_locked})
	return result

func context(owner:String,kind:String,source:String)->Dictionary:
	return {"owner_id":owner,"actor_id":owner,"source_kind":kind,"source_id":source,"resource_owner_id":"",
		"root_action_id":"","parent_event_id":0,"cast_id":"","sentence_id":"","execution_id":0,"effect_group_id":"",
		"window_id":state.get("window_id",""),"window_kind":state.get("window_kind",""),"origin_window_kind":state.get("window_kind",""),"active_spell":false,"reward_eligible":false,"uses_personal_modifiers":false,"hostile":false}

func record(type:String,owner:String,target:String,payload:Dictionary={},ctx:Dictionary={})->Dictionary:
	event_count+=1
	state.revision+=1
	var u=unit(owner)
	var e={"event_type":type,"kind":"fact","id":event_count,"event_id":event_count,"rules":Protocol.RULES,"content":catalog.data.version,"battle_id":state.battle_id,
		"phase":state.phase,"t":state.t,"window_id":state.window_id,"window_kind":state.window_kind,"W":u.get("W",0),"R":u.get("R",0),
		"actor":owner,"target":target,"target_ids":[target] if target!="" else [],"owner_id":owner,"actor_id":owner,"source_kind":"SYSTEM","source_id":"",
		"resource_owner_id":"","root_action_id":"","parent_event_id":0,"cast_id":"","sentence_id":"","execution_id":0,"effect_group_id":"","origin_window_kind":"","reward_eligible":false}
	e.merge(ctx,true);e.merge(payload,true)
	if capture_visual and not simulation:e.visual=view()
	if not simulation:events.append(e.duplicate(true))
	return e

func _snapshot_units()->Dictionary:
	var result={}
	for u in state.units:result[u.id]=u.duplicate(true)
	return result

func buff(u:Dictionary,key:String)->int:return int(u.get("buffs",{}).get(key,0))
func set_buff(u:Dictionary,key:String,amount:int)->void:
	if amount<=0:u.buffs.erase(key);u.get("hostile_status",{}).erase(key)
	else:u.buffs[key]=amount

func root_sqrt(n:int)->int:return Protocol.isqrt_round(n)

func check_result()->void:
	if state.ended:return
	var teams:Array=[]
	var main_only=state.snapshot.get("victory_mode","main_units")=="main_units"
	for u in state.units:
		if main_only and not u.get("is_main",u.id in ["p","e"]):continue
		if u.H>0 and not teams.has(u.team):teams.append(u.team)
	if teams.is_empty():finish("draw","同批结算双方主战角色倒下")
	elif teams.size()==1:finish("player" if teams[0]==0 else "enemy","对方主战角色倒下")

func finish(result:String,reason:String)->void:
	if state.get("ended",false):return
	state.ended=true;state.result=result;state.reason=reason;state.phase="BATTLE_END"
	var canceled={"tickets":state.tickets.duplicate(true),"responses":state.responses.duplicate(true)}
	state.tickets=[];state.responses=[]
	for u in state.units:u.opportunity_pending=false
	record("BATTLE_FINISHED","","",{"kind":"end","text":reason,"result":result,"cancelled":canceled})
	state.current="";state.window_id="";state.window_kind=""

func _check_limits()->bool:
	var limits=state.snapshot.limits
	if state.t>=int(limits.ticks):finish("undecided","达到公共刻观察上限");return true
	for u in state.units:
		if u.R>=int(limits.normal_windows) or u.W>=int(limits.windows):finish("undecided","达到自身窗口观察上限");return true
	return false

func advance(max_ticks:int=600)->void:
	if _dispatching or state.ended or state.current!="":return
	_dispatching=true
	var advanced=0
	while not state.ended and state.current=="":
		state.phase="DISPATCH"
		drain_responses()
		if state.ended or _check_limits():break
		qualify_opportunities()
		var ticket={}
		while not state.tickets.is_empty():
			var candidate=state.tickets.pop_front()
			var holder=unit(candidate.unit_id)
			if not holder.is_empty() and holder.H>0 and holder.opportunity_pending and not holder.opportunity_locked:
				ticket=candidate;break
		if not ticket.is_empty():
			open_window(unit(ticket.unit_id),Protocol.OPPORTUNITY)
			continue
		var ready:Array=[]
		for u in state.units:
			if u.H>0 and u.A>=100:ready.append(u)
		ready.sort_custom(func(a,b):return a.S>b.S if a.S!=b.S else order_index(a.id)<order_index(b.id))
		if not ready.is_empty():open_window(ready[0],Protocol.NORMAL);continue
		if advanced>=max_ticks:break
		public_tick()
		advanced+=1
	_dispatching=false

func open_window(u:Dictionary,kind:String)->void:
	if state.ended or u.H<=0:return
	state.phase="WINDOW_PRE"
	state.window_id="";state.window_kind=""
	if kind==Protocol.NORMAL:
		record("NORMAL_PRE",u.id,u.id,{"candidate_window_kind":kind})
		var erosion=Protocol.round_ratio(int(u.H)*buff(u,"蚀骨"),100)
		if erosion>0:
			var ctx=context("","PERIODIC_STATE","蚀骨")
			ctx.actor_id="status:"+u.id+":蚀骨";ctx.hostile=bool(u.hostile_status.get("蚀骨",false))
			resolve_damage_group({},[u.id],{u.id:erosion},"effect",ctx,{})
		if state.ended or u.H<=0:return
	state.phase="WINDOW_OPEN"
	state.window_seq+=1
	state.window_id=state.battle_id+":w"+str(state.window_seq)
	state.window_kind=kind;state.current=u.id
	u.W+=1;u.stats_log.windows+=1
	if kind==Protocol.NORMAL:u.R+=1;u.stats_log.normal_windows+=1
	else:
		u.Z=0;u.opportunity_pending=false;u.opportunity_locked=true
		u.stats_log.opportunity_windows+=1
	u.sword_used=false;u.main_used=false;u.swap_used=false;u.window_actions=0
	for slot in u.entries:slot.used=false;slot.operation="none"
	for entry in u.art_entries:entry.active_used=false
	state.ai_budget[u.id]={"nodes":0,"events":0,"truncated":false,"plan":[],"plan_window":state.window_id}
	record("WINDOW_OPENED",u.id,u.id,{"kind":"window","text":("普通回合" if kind==Protocol.NORMAL else "战机回合"),"candidate_window_kind":kind})
	if kind==Protocol.NORMAL:
		var e=record("NORMAL_OPENED",u.id,u.id)
		collect_automatic(u,e)
	else:record("OPPORTUNITY_OPENED",u.id,u.id,{"kind":"opportunity","A":u.A,"Z":u.Z})
	drain_responses()
	if not state.ended:state.phase="DECISION"

func close_window(dispatch:bool=true)->void:
	if state.ended:return
	var u=unit(state.current)
	if u.is_empty():return
	state.phase="WINDOW_CLOSE"
	if u.window_actions==0:u.stats_log.empty+=1
	var normal=state.window_kind==Protocol.NORMAL
	if normal:
		set_buff(u,"撕裂",buff(u,"撕裂")/2)
		u.A=0;u.opportunity_locked=false
	record("NORMAL_CLOSED" if normal else "OPPORTUNITY_CLOSED",u.id,u.id,{"kind":"window_end","text":"普通回合结束" if normal else "战机结束","A":u.A})
	drain_responses()
	state.current="";state.window_kind="";state.window_id=""
	if not state.ended:
		qualify_opportunities()
		state.phase="DISPATCH"
		if dispatch:advance()

func add_opportunity(u:Dictionary,amount:int,channel:String,ctx:Dictionary={})->void:
	if not u.opportunity_enabled or u.H<=0 or amount<=0:return
	var before=int(u.Z)
	var cap=int(state.snapshot.opportunity.maximum)
	u.Z=mini(cap,before+amount)
	var actual=int(u.Z)-before
	u.stats_log["z_passive" if channel=="passive" else "z_damage"]+=actual
	u.stats_log.z_overflow+=amount-actual
	record("GAUGE_CHANGED",u.id,u.id,{"before":before,"after":u.Z,"requested":amount,"actual":actual,"overflow":amount-actual,"channel":channel,"locked":u.opportunity_locked},ctx)

func qualify_opportunities()->void:
	if state.ended:return
	var eligible:Array=[]
	for u in state.units:
		if u.H>0 and u.opportunity_enabled and u.Z>=int(state.snapshot.opportunity.maximum) and not u.opportunity_pending and not u.opportunity_locked:eligible.append(u)
	if eligible.is_empty():return
	state.qualification_batch+=1
	eligible.sort_custom(func(a,b):return a.S>b.S if a.S!=b.S else order_index(a.id)<order_index(b.id))
	for u in eligible:
		u.opportunity_pending=true
		var ticket={"unit_id":u.id,"t":state.t,"batch":state.qualification_batch,"speed":u.S,"order":order_index(u.id)}
		state.tickets.append(ticket)
		record("OPPORTUNITY_QUALIFIED",u.id,u.id,{"kind":"qualified","ticket":ticket,"text":"战机就绪，等待安全调度点"})

func public_tick()->void:
	if state.ended:return
	assert(state.current=="", "Public time cannot advance inside an active window")
	state.phase="PUBLIC_TICK"
	var before=_snapshot_units()
	state.t+=1
	var receipts:Array=[]
	var gauge_receipts:Array=[]
	# Read the common pre-tick snapshot and commit all units before any response.
	for u in ordered_units():
		if u.H<=0:continue
		var old=before[u.id]
		var q=maxi(1,int(old.Q)+buff(old,"鲸吞")-buff(old,"滞气"))
		var gain=mini(int(old.M)-int(old.E),q)
		u.E=old.E+gain;u.stats_log.qi_gain+=gain;u.stats_log.qi_overflow+=q-gain
		u.A=mini(100,int(old.A)+maxi(5,root_sqrt(int(old.S))+buff(old,"神速")))
		var spring=buff(old,"回春");var invasion=buff(old,"侵袭")
		u.H=clampi(int(old.H)+spring-invasion,0,int(old.Hmax))
		set_buff(u,"回春",maxi(0,spring-1));set_buff(u,"侵袭",invasion/2)
		var net=int(u.H)-int(old.H)
		u.stats_log.periodic_damage_requested+=invasion;u.stats_log.periodic_heal_requested+=spring;u.stats_log.periodic_net+=net
		if spring==0:u.stats_log.periodic_damage_only_actual+=maxi(0,-net)
		if invasion==0:u.stats_log.periodic_heal_only_actual+=maxi(0,net)
		receipts.append({"target_id":u.id,"H_before":old.H,"H_after":u.H,"E_before":old.E,"E_after":u.E,"damage_request":invasion,"heal_request":spring,"net_hp_change":net,"qi_gained":gain,"qi_overflow":q-gain,"hostile":bool(old.hostile_status.get("侵袭",false)),"buffs_before":old.buffs,"buffs_after":u.buffs.duplicate(true)})
		if u.opportunity_enabled and u.H>0:
			var amount=int(state.snapshot.opportunity.passive_gain)
			var previous=int(u.Z)
			u.Z=mini(int(state.snapshot.opportunity.maximum),previous+amount)
			u.stats_log.z_passive+=u.Z-previous;u.stats_log.z_overflow+=amount-(u.Z-previous)
			gauge_receipts.append({"owner":u.id,"before":previous,"after":u.Z,"requested":amount,"actual":u.Z-previous,"overflow":amount-(u.Z-previous),"channel":"passive","locked":u.opportunity_locked})
	var group=record("PUBLIC_TICK_COMMITTED","","",{"kind":"clock","receipts":receipts})
	for z in gauge_receipts:record("GAUGE_CHANGED",z.owner,z.owner,z,{"parent_event_id":group.event_id})
	check_result()
	if state.ended:return
	for r in receipts:
		if r.net_hp_change<0 and r.damage_request>0 and r.hostile:
			var u=unit(r.target_id)
			var e=record("PERIODIC_NET_HP_LOSS","",u.id,{"actual":-r.net_hp_change,"target_H":u.H,"target_Hmax":u.Hmax,"hostile":true,"kind":"public_effect","text":"周期效果"},{"parent_event_id":group.event_id,"source_kind":"PERIODIC_STATE"})
			collect_automatic(u,e)
	drain_responses()
	if not state.ended:qualify_opportunities()

func costs(u:Dictionary,v:Dictionary)->Dictionary:
	return {"qi":maxi(0,int(v.prepared_qi_cost)+buff(u,"逆气")-buff(u,"凝神")),"hp":maxi(0,int(v.get("hp_cost",0))+buff(u,"撕裂"))}

func variant_for(u:Dictionary,a:Dictionary)->Dictionary:
	if a.get("kind","")=="artifact":
		var index=int(a.get("slot",-1))
		if index>=0 and index<u.art_entries.size():return catalog.artifacts.get(u.art_entries[index].artifact,{}).get("active",{})
	if a.get("kind","")=="cast" and int(a.get("slot",-1))>=0 and int(a.slot)<u.entries.size():return catalog.techniques.get(u.entries[int(a.slot)].technique,{})
	return {}

func effective_ready(u:Dictionary,index:int)->int:
	var slot=u.entries[index]
	var v=catalog.techniques.get(slot.technique,{})
	return maxi(int(slot.ready_window),int(u.family_ready_window.get(v.get("source_family_id",""),1)))

func swap_ready(u:Dictionary,index:int,technique:String)->int:
	var v=catalog.techniques[technique]
	return maxi(int(u.W)+1,maxi(int(u.entries[index].ready_window),int(u.family_ready_window.get(v.source_family_id,1))))

func legal(a:Dictionary)->Dictionary:
	return _legal_command(a,false)

func _legal_command(a:Dictionary,committing:bool)->Dictionary:
	if state.is_empty() or state.ended:return catalog.bad("战斗已经结束或尚未开始")
	if state.phase!="DECISION" and not (committing and state.phase=="ACTION_VALIDATE"):return catalog.bad("当前处于结算阶段，不能插入指令")
	var u=unit(str(a.get("actor",state.current)))
	if u.is_empty() or u.id!=state.current or u.H<=0:return catalog.bad("当前不是该单位的出手机会")
	if a.has("window_id") and a.window_id!=state.window_id:return catalog.bad("指令来自已经结束的窗口")
	var kind=str(a.get("kind",""))
	if kind=="end":return {"ok":true,"reason":""}
	if not kind in ["cast","sword","swap","artifact"]:return catalog.bad("未知指令；自动功效不能手动发动")
	if kind=="artifact":
		for key in a:
			if not key in ["kind","actor","slot","target","window_id"]:return catalog.bad("催动指令只选择独立主动成品，不能指定自动效果或触发器")
	if kind=="swap":
		var index=int(a.get("slot",-1))
		if index<0 or index>=4:return catalog.bad("功法格不存在")
		if u.swap_used:return catalog.bad("本窗口已经准备换法一次")
		if u.main_used and state.window_kind==Protocol.NORMAL:return catalog.bad("普通主动作已提交")
		if u.entries[index].used:return catalog.bad("本格本窗口已操作")
		var id=str(a.get("technique",""))
		if not catalog.techniques.has(id):return catalog.bad("换入法门未发布")
		var slots=u.slots.duplicate()
		if slots[index]==id:return catalog.bad("已经装配该成品")
		slots[index]=id
		return catalog.validate({"Hmax":u.Hmax,"M":u.M,"Q":u.Q,"S":u.S},slots,u.artifacts)
	if state.window_kind==Protocol.NORMAL and u.main_used:return catalog.bad("普通回合仅允许一次主动作")
	if kind=="sword":
		if u.sword_used:return catalog.bad("本窗口已经挥剑")
		if not enemies(u).has(a.get("target","")):return catalog.bad("请选择存活敌人")
		return {"ok":true,"reason":""}
	var index=int(a.get("slot",-1))
	var ready=1
	if kind=="artifact":
		if index<0 or index>=u.art_entries.size():return catalog.bad("法宝入口不存在")
		if u.art_entries[index].active_used:return catalog.bad("本法宝的催本窗口已用")
		ready=int(u.art_entries[index].active_ready_window)
	else:
		if index<0 or index>=4:return catalog.bad("功法格不存在")
		if u.entries[index].used:return catalog.bad("本格本窗口已操作")
		ready=effective_ready(u,index)
	var v=variant_for(u,a)
	if v.is_empty():return catalog.bad("该法宝未定义催动" if kind=="artifact" else "空功法格")
	if u.W<ready:return catalog.bad("还差%d次自己的出手机会（含战机）"%[ready-u.W])
	var primary=str(a.get("target",u.id))
	for s in v.sentences:
		if s.target in ["enemy","all_enemies"] and not enemies(u).has(primary):return catalog.bad("请选择存活敌人")
		if s.target=="ally" and not allies(u).has(primary):return catalog.bad("请选择存活友方")
	if v.has("requires"):
		var target=unit(u.id if v.requires.get("target","primary")=="self" else primary)
		if target.is_empty() or buff(target,v.requires.buff)<int(v.requires.min):return catalog.bad("目标需要至少%d层%s"%[v.requires.min,v.requires.buff])
	var c=costs(u,v)
	if u.E<c.qi:return catalog.bad("灵气不足：需要%d，当前%d"%[c.qi,u.E])
	if u.H<=c.hp:return catalog.bad("气血支付后必须存活：需要%d"%c.hp)
	return {"ok":true,"reason":"","cost":c}

func actions(actor:String,with_swaps:bool=false)->Array:
	var out:Array=[]
	var u=unit(actor)
	if u.is_empty() or state.ended or state.phase!="DECISION" or state.current!=actor:return out
	for i in range(4):
		var v=catalog.techniques.get(u.entries[i].technique,{})
		if not v.is_empty():
			var target_type="self"
			for s in v.sentences:
				if s.target in ["enemy","all_enemies"]:target_type="enemy"
				elif s.target=="ally" and target_type!="enemy":target_type="ally"
			var targets=enemies(u) if target_type=="enemy" else allies(u) if target_type=="ally" else [actor]
			for target in targets:
				var a={"kind":"cast","actor":actor,"slot":i,"target":target,"window_id":state.window_id}
				if legal(a).ok:out.append(a)
		if with_swaps and not u.swap_used and not u.entries[i].used:
			var added=0
			var choices=["heal_clean","guard","qi"] if u.H*2<u.Hmax or buff(u,"蚀骨")>0 else ["sword_deep","ember","pressure"]
			for id in choices:
				var a={"kind":"swap","actor":actor,"slot":i,"technique":id,"window_id":state.window_id}
				if legal(a).ok:out.append(a);added+=1
				if added>=int(catalog.data.ai.swaps):break
	# Only the separately compiled active payload can become a manual/AI action.
	for i in range(u.art_entries.size()):
		var v=catalog.artifacts[u.art_entries[i].artifact].get("active",{})
		if v.is_empty():continue
		var target_type="self"
		for s in v.sentences:
			if s.target in ["enemy","all_enemies"]:target_type="enemy"
			elif s.target=="ally" and target_type!="enemy":target_type="ally"
		for target in enemies(u) if target_type=="enemy" else allies(u) if target_type=="ally" else [actor]:
			var a={"kind":"artifact","actor":actor,"slot":i,"target":target,"window_id":state.window_id}
			if legal(a).ok:out.append(a)
	for target in enemies(u):
		var a={"kind":"sword","actor":actor,"target":target,"window_id":state.window_id}
		if legal(a).ok:out.append(a)
	out.append({"kind":"end","actor":actor,"window_id":state.window_id})
	return out

func execute(a:Dictionary)->Dictionary:
	if state.is_empty() or state.ended or state.phase!="DECISION":return legal(a)
	state.phase="ACTION_VALIDATE"
	var validity=_legal_command(a,true)
	# Validation is atomic: a rejected command restores the exact decision state.
	if not validity.ok:
		state.phase="DECISION"
		return validity
	state.phase="ACTION_COMMIT"
	var u=unit(str(a.get("actor",state.current)))
	if a.kind=="end":close_window();return {"ok":true}
	if a.kind=="swap":
		var slot=u.entries[int(a.slot)]
		slot.technique=a.technique;u.slots[int(a.slot)]=a.technique
		slot.used=true;slot.operation="swap";u.swap_used=true
		u.window_actions+=1;u.stats_log.swaps+=1
		record("LOADOUT_CHANGED",u.id,u.id,{"kind":"swap","text":"换入 "+catalog.techniques[a.technique].name,"ready_window":swap_ready(u,a.slot,a.technique)},context(u.id,"PREPARATION",a.technique))
		state.phase="DECISION"
		return {"ok":true}
	state.phase="ACTION_COMMIT"
	state.action_seq+=1
	var root_id=state.battle_id+":a"+str(state.action_seq)
	var ctx=context(u.id,"BASIC_ATTACK" if a.kind=="sword" else "ARTIFACT_CATALYST" if a.kind=="artifact" else "ACTIVE_SPELL",a.kind)
	ctx.root_action_id=root_id;ctx.resource_owner_id=u.id if a.kind in ["cast","artifact"] else ""
	ctx.reward_eligible=u.opportunity_enabled and state.window_kind==Protocol.NORMAL
	ctx.active_spell=a.kind in ["cast","artifact"];ctx.uses_personal_modifiers=true
	_root={"id":root_id,"owner_id":u.id,"damage":0,"context":ctx.duplicate(true)}
	u.main_used=true;u.window_actions+=1
	var result:Dictionary={"ok":true,"records":{}}
	if a.kind=="sword":
		u.sword_used=true;u.stats_log.swords+=1
		var grow=Math.growth_inputs(u,{})
		var amount=Math.root_amount(u.basic_attack,grow)
		record("BASIC_ATTACK_COMMITTED",u.id,a.target,{"kind":"cast","text":"挥剑"},ctx)
		resolve_damage_group(u,[a.target],{a.target:amount},"direct",ctx,{})
	else:
		var v=variant_for(u,a)
		var paid=validity.cost
		u.E-=paid.qi;u.H-=paid.hp
		u.stats_log.qi_cost+=paid.qi;u.stats_log.hp_cost+=paid.hp;u.stats_log.casts+=1
		if a.kind=="artifact":
			u.art_entries[int(a.slot)].active_used=true
			u.art_entries[int(a.slot)].active_ready_window=u.W+int(v.CD)
			u.stats_log.catalysts+=1
		else:
			u.entries[int(a.slot)].used=true;u.entries[int(a.slot)].operation="cast"
			u.entries[int(a.slot)].ready_window=u.W+int(v.CD)
			u.family_ready_window[v.source_family_id]=u.W+int(v.CD)
		state.cast_seq+=1
		ctx.cast_id=state.battle_id+":c"+str(state.cast_seq);ctx.source_id=v.id
		var committed=record("SPELL_COMMITTED",u.id,a.get("target",u.id),{"kind":"cast","text":v.name,"qi_cost":paid.qi,"hp_cost":paid.hp,"N":v.N,"CD":v.CD,"ready_window":u.W+v.CD},ctx)
		ctx.parent_event_id=committed.event_id
		_root.context=ctx.duplicate(true)
		result.after_payment_E=int(u.E)
		var cast_snapshot=_snapshot_units()
		var growth=Math.growth_inputs(u,v)
		var status="completed"
		for s in v.sentences:
			if state.ended or u.H<=0:status="cancelled_by_terminal";break
			var step=execute_sentence(u,s,str(a.get("target",u.id)),result.records,ctx,cast_snapshot,growth)
			if not step:status="interrupted_step_cost";break
		result.cast_id=ctx.cast_id
		record("SPELL_FINISHED",u.id,a.get("target",u.id),{"completion":status,"records":result.records.duplicate(true)},ctx)
	result.after_effect_E=int(u.E)
	result.after_effect_H=int(u.H)
	close_root()
	if not state.ended:
		if state.window_kind==Protocol.NORMAL:close_window()
		else:state.phase="DECISION"
	return result

func close_root()->void:
	if _root.is_empty():return
	if not state.ended:state.phase="ACTION_CLOSE"
	var u=unit(_root.owner_id)
	var ctx=_root.context
	if not state.ended and ctx.reward_eligible:
		var z=state.snapshot.opportunity
		var amount=mini(int(z.root_gain_cap),int(z.damage_weight)*int(_root.damage)/int(z.combat_scale_ref))
		add_opportunity(u,amount,"damage",ctx)
	elif not state.ended and _root.damage>0:u.stats_log.z_rejected+=_root.damage
	record("ROOT_ACTION_CLOSED",u.id,u.id,{"qualifying_hp_loss":_root.damage,"reward_eligible":ctx.reward_eligible,"completion":"terminal" if state.ended else "completed"},ctx)
	_root={}
	if not state.ended:qualify_opportunities()

func target_ids(u:Dictionary,s:Dictionary,primary:String)->Array:
	if s.target=="self":return [u.id]
	if s.target=="all_enemies":return enemies(u)
	if s.target=="ally":return [primary] if allies(u).has(primary) else []
	return [primary]

func execute_sentence(u:Dictionary,s:Dictionary,primary:String,records:Dictionary,base_context:Dictionary,cast_units:Dictionary,growth:Dictionary)->bool:
	state.phase="EFFECT_RESOLVE" if not _draining else "RESPONSE_DRAIN"
	var ctx=base_context.duplicate(true)
	ctx.sentence_id=s.id;ctx.execution_id=int(s.get("execution_id",0))
	if s.has("step_cost"):
		var cost=s.step_cost
		if u.E<int(cost.get("qi",0)) or u.H<=int(cost.get("hp",0)):
			record("PAYMENT_REJECTED",u.id,u.id,{"reason":"分步费用不足，停止后句"},ctx)
			return false
		u.E-=int(cost.get("qi",0));u.H-=int(cost.get("hp",0))
		u.stats_log.qi_cost+=int(cost.get("qi",0));u.stats_log.hp_cost+=int(cost.get("hp",0))
		record("STEP_PAYMENT_COMMITTED",u.id,u.id,{"qi_cost":cost.get("qi",0),"hp_cost":cost.get("hp",0)},ctx)
	var group_units=_snapshot_units()
	var targets=target_ids(u,s,primary)
	var amounts={};var results={}
	for tid in targets:
		var t=group_units.get(tid,{})
		if t.is_empty() or t.H<=0:results[tid]={"status":"skipped","reason":"目标失效"};continue
		if s.has("condition"):
			var read=cast_units.get(tid,{}) if s.condition.read_at=="CAST_START" else t
			if buff(read,s.condition.buff)<int(s.condition.get("min",1)):results[tid]={"status":"skipped","reason":"条件不满足"};continue
		var amount=Math.resolve(s.amount,u,tid,primary,records,group_units,cast_units,growth)
		if amount==null:results[tid]={"status":"skipped","reason":"前句结果缺失"};continue
		if s.op=="consume" and s.get("required",false) and buff(t,s.buff)<int(amount):
			record("PAYMENT_REJECTED",u.id,tid,{"reason":"句内消耗不足，未部分扣除"},ctx)
			return false
		amounts[tid]=int(amount)
	if s.op=="damage":
		var valid_targets:Array=[]
		for tid in targets:
			if amounts.has(tid):valid_targets.append(tid)
		results.merge(resolve_damage_group(u,valid_targets,amounts,str(s.get("nature","direct")),ctx,group_units),true)
	else:
		state.group_seq+=1;ctx.effect_group_id=state.battle_id+":g"+str(state.group_seq)
		var changes:Array=[]
		for tid in targets:
			if not amounts.has(tid):continue
			var t=unit(tid);var old=group_units[tid];var amount=int(amounts[tid]);var r={}
			if s.op=="heal":
				var actual=mini(amount,int(old.Hmax)-int(old.H))
				t.H=old.H+actual;t.stats_log.heal+=actual;t.stats_log.heal_overflow+=amount-actual
				r={"heal_request":amount,"hp_restored":actual,"heal_overflow":amount-actual,"actual":actual,"request":amount,"overflow":amount-actual}
			elif s.op=="qi":
				var subtract=s.get("direction","ADD")=="SUB"
				var actual=mini(amount,int(old.E) if subtract else int(old.M)-int(old.E))
				t.E=old.E-actual if subtract else old.E+actual
				if subtract:t.stats_log.qi_removed+=actual
				else:t.stats_log.qi_gain+=actual;t.stats_log.qi_overflow+=amount-actual
				r={"qi_request":amount,"qi_restored":0 if subtract else actual,"qi_removed":actual if subtract else 0,"qi_overflow":amount-actual,"actual":actual,"request":amount,"overflow":amount-actual}
			elif s.op=="apply":
				var before=buff(old,s.buff)
				var actual=mini(amount,maxi(0,int(old.Hmax)-before)) if s.buff=="护体" else amount
				set_buff(t,s.buff,before+actual)
				if u.get("team",-1)!=t.team and Catalog.DEBUFFS.has(s.buff) and actual>0:t.hostile_status[s.buff]=true
				if s.buff=="护体":t.stats_log.shield+=actual;t.stats_log.shield_overflow+=amount-actual
				r={"layers_requested":amount,"layers_added":actual,"layers_before":before,"layers_after":before+actual,"layers_overflow":amount-actual,"actual":actual,"request":amount,"overflow":amount-actual,"buff":s.buff}
			elif s.op in ["remove","consume"]:
				var removed=0;var total_before=0
				for key in Catalog.DEBUFFS if s.buff=="debuffs" else [s.buff]:
					var before=buff(old,key);var delta=before if s.get("mode","")=="ALL" else mini(amount,before)
					total_before+=before;removed+=delta;set_buff(t,key,before-delta)
				r={"layers_requested":total_before if s.get("mode","")=="ALL" else amount,"layers_removed":removed,"layers_before":total_before,"layers_after":total_before-removed,"actual":removed,"request":amount,"buff":s.buff,"mode":s.get("mode","QUANTITY")}
			r.status="executed";r.cast_id=ctx.cast_id;r.sentence_id=s.id;r.execution_id=ctx.execution_id;r.target_id=tid
			results[tid]=r;changes.append(r)
		var group=record("EFFECT_GROUP_COMMITTED",ctx.owner_id,primary,{"op":s.op,"results":changes,"target_ids":targets},ctx)
		ctx.parent_event_id=group.event_id
		for r in changes:
			var payload=r.duplicate(true);payload.kind=s.op
			record("STATUS_CHANGED" if s.op in ["apply","remove","consume"] else "EFFECT_RESULT",ctx.owner_id,r.target_id,payload,ctx)
		check_result()
	for tid in results:
		if results[tid].status=="skipped":record("EFFECT_SKIPPED",ctx.owner_id,tid,{"kind":"skip","reason":results[tid].reason,"text":results[tid].reason},ctx)
	records[s.id]=results.duplicate(true)
	if not state.ended and not _draining:drain_responses()
	return true

func resolve_damage_group(owner:Dictionary,targets:Array,amounts:Dictionary,nature:String,ctx:Dictionary,group_units:Dictionary)->Dictionary:
	var old=_snapshot_units() if group_units.is_empty() else group_units
	var results={};var receipts:Array=[]
	if targets.is_empty():return results
	state.group_seq+=1;ctx=ctx.duplicate(true);ctx.effect_group_id=state.battle_id+":g"+str(state.group_seq)
	var uses_edge=ctx.get("uses_personal_modifiers",false) and nature=="direct" and not owner.is_empty()
	var edge=buff(old.get(owner.get("id",""),{}),"锋锐") if uses_edge else 0
	for tid in targets:
		var target=old.get(tid,{})
		if target.is_empty() or target.H<=0:continue
		var base=int(amounts[tid]);var request=base+mini(edge,base) if uses_edge else base
		var absorbed=mini(buff(target,"护体"),request) if nature=="direct" else 0
		var loss=mini(int(target.H),maxi(0,request-absorbed))
		var live=unit(tid)
		live.H=target.H-loss
		if absorbed>0:set_buff(live,"护体",buff(target,"护体")-absorbed)
		live.stats_log.shield_absorbed+=absorbed
		live.stats_log["direct_taken" if nature=="direct" else "effect_taken"]+=loss
		if not owner.is_empty():owner.stats_log["direct" if nature=="direct" else "effect"]+=loss
		var hostile=bool(ctx.get("hostile",false)) or (not owner.is_empty() and owner.team!=live.team)
		if not _root.is_empty() and ctx.get("root_action_id","")==_root.id and ctx.get("reward_eligible",false) and hostile:_root.damage+=loss
		var r={"status":"executed","target_id":tid,"base_request":base,"damage_request":request,"hp_loss":loss,"shield_absorbed":absorbed,"overkill":request-absorbed-loss,
			"request":request,"actual":loss,"absorbed":absorbed,"nature":nature,"hostile":hostile,"target_H":live.H,"target_Hmax":live.Hmax,"text":ctx.get("source_id",""),"cast_id":ctx.get("cast_id",""),"sentence_id":ctx.get("sentence_id",""),"execution_id":ctx.get("execution_id",0)}
		results[tid]=r;receipts.append(r)
	# Shared edge is consumed once for this attack, never once per target.
	if uses_edge and not receipts.is_empty():set_buff(owner,"锋锐",maxi(0,edge-1))
	var group=record("EFFECT_GROUP_COMMITTED",ctx.get("owner_id",""),"",{"op":"damage","nature":nature,"results":receipts,"target_ids":targets},ctx)
	ctx.parent_event_id=group.event_id
	for r in receipts:
		var visual=r.duplicate(true);visual.kind="damage"
		record("EFFECT_RESULT",ctx.get("owner_id",""),r.target_id,visual,ctx)
	# No player/AI/response can interleave a partially committed target group.
	check_result()
	if not state.ended:
		for r in receipts:
			if r.hp_loss>0:
				var e=record("HP_DAMAGE_TAKEN",ctx.get("owner_id",""),r.target_id,r,ctx)
				collect_automatic(unit(r.target_id),e)
		if not _draining:drain_responses()
	return results

func damage(actor:String,target:String,base:int,nature:String,source:String)->Dictionary:
	# Test/content adapter still enters the exact atomic damage-group path.
	var owner=unit(actor)
	var ctx=context(actor,"DIRECT_EFFECT",source)
	ctx.uses_personal_modifiers=true
	return resolve_damage_group(owner,[target],{target:base},nature,ctx,{}).get(target,{})

func collect_automatic(u:Dictionary,event:Dictionary)->void:
	if state.ended or u.is_empty() or u.H<=0:return
	var incoming:Array=[]
	for index in range(u.art_entries.size()):
		var entry=u.art_entries[index];var a=catalog.artifacts[entry.artifact]
		if not entry.enabled:continue
		var event_type=str(event.event_type)
		var accepted=(a.trigger==event_type) or (a.trigger=="HP_DAMAGE_TAKEN" and event_type=="PERIODIC_NET_HP_LOSS")
		if not accepted:continue
		if a.trigger=="NORMAL_OPENED":
			if entry.last_normal==u.R:continue
			entry.last_normal=u.R
		else:
			if entry.triggered:continue
			if a.trigger=="HP_DAMAGE_TAKEN":
				if not event.get("hostile",false) or int(event.get("actual",0))<=0:return
				if int(event.get("target_H",0))<=0 or int(event.target_H)*100>=int(event.target_Hmax)*int(a.threshold):continue
			entry.triggered=true
		var task={"owner_id":u.id,"artifact_id":a.id,"slot":index,"event_id":event.event_id,"priority":int(a.get("priority",0)),"order":order_index(u.id),"instance_id":u.id+":artifact:"+str(index),"root_action_id":event.get("root_action_id",""),"origin_window_kind":event.get("origin_window_kind",""),"evidence":{"event_type":event_type,"H":event.get("target_H",u.H),"Hmax":u.Hmax}}
		incoming.append(task)
	incoming.sort_custom(func(a,b):
		if a.priority!=b.priority:return a.priority<b.priority
		if a.order!=b.order:return a.order<b.order
		return a.slot<b.slot)
	state.responses.append_array(incoming)
	# New tasks append to an existing boundary, not a recursive language stack.
	if not _draining:
		state.responses.sort_custom(func(a,b):
			if a.event_id!=b.event_id:return a.event_id<b.event_id
			if a.priority!=b.priority:return a.priority<b.priority
			if a.order!=b.order:return a.order<b.order
			return a.slot<b.slot)

func drain_responses()->void:
	if _draining or state.ended or state.responses.is_empty():return
	_draining=true
	var previous_phase=state.phase
	var processed=0
	while not state.responses.is_empty() and not state.ended:
		if processed>=256:
			finish("error","自动响应超过安全上限，已保留因果记录；不是正常停滞")
			break
		processed+=1
		state.phase="RESPONSE_DRAIN"
		var task=state.responses.pop_front()
		var owner=unit(task.owner_id)
		if owner.is_empty() or owner.H<=0:
			record("RESPONSE_CANCELLED",task.owner_id,"",{"reason":"来源失效","task":task})
			continue
		var a=catalog.artifacts[task.artifact_id]
		var targets=enemies(owner)
		var needs_enemy=false
		for s in a.auto:
			if s.target in ["enemy","all_enemies"]:needs_enemy=true
		if needs_enemy and targets.is_empty():record("RESPONSE_CANCELLED",owner.id,"",{"reason":"无合法目标","task":task});continue
		var ctx=context(owner.id,"ARTIFACT_AUTO",a.id)
		ctx.actor_id=task.instance_id;ctx.root_action_id=task.root_action_id
		ctx.origin_window_kind=task.origin_window_kind;ctx.parent_event_id=task.event_id
		state.cast_seq+=1;ctx.cast_id=state.battle_id+":auto"+str(state.cast_seq)
		owner.stats_log.automatic+=1
		record("AUTOMATIC_TRIGGERED",owner.id,owner.id,{"kind":"auto","text":a.name,"trigger_evidence":task.evidence},ctx)
		var primary=targets[0] if not targets.is_empty() else owner.id
		var records={};var snapshot=_snapshot_units()
		for s in a.auto:
			if state.ended:break
			execute_sentence(owner,s,primary,records,ctx,snapshot,{"P":0,"series_bonus_bp":0,"technique_bonus_bp":0})
	_draining=false
	if not state.ended:state.phase=previous_phase

func accounting()->Dictionary:
	var out={};var all_ok=true
	for u in state.units:
		var s=u.stats_log
		var expected_h=int(u.stats.Hmax)-int(s.direct_taken)-int(s.effect_taken)+int(s.heal)-int(s.hp_cost)+int(s.periodic_net)
		var expected_e=int(u.stats.M)+int(s.qi_gain)-int(s.qi_cost)-int(s.qi_removed)
		var ok=expected_h==u.H and expected_e==u.E
		out[u.id]={"H":u.H,"expected_H":expected_h,"E":u.E,"expected_E":expected_e,"ok":ok}
		all_ok=all_ok and ok
	return {"ok":all_ok,"units":out}

func fork():
	var copy=get_script().new(catalog)
	for key in state:
		if key=="ai_traces":copy.state[key]=[]
		elif key=="snapshot":copy.state[key]=state[key]
		elif state[key] is Dictionary or state[key] is Array:copy.state[key]=state[key].duplicate(true)
		else:copy.state[key]=state[key]
	copy._root=_root.duplicate(true)
	copy.simulation=true
	copy.event_count=0
	return copy

func public_hash()->String:
	var observable={"rules":Protocol.RULES,"content":catalog.digest}
	for key in ["t","current","window_kind","window_id","window_seq","phase","units","tickets","responses","ended","result","cast_seq","action_seq","group_seq","qualification_batch"]:observable[key]=state.get(key)
	return JSON.stringify(observable).sha256_text()
