extends RefCounted
const Protocol=preload("res://scripts/combat_protocol.gd")
const Math=preload("res://scripts/effect_math.gd")
var last_trace:Dictionary={}

func value(b,actor:String)->int:
	var u=b.unit(actor)
	if b.state.ended:
		if b.state.result in ["draw","undecided","aborted","error"]:return 0
		return 1000000 if (b.state.result=="player")== (int(u.team)==0) else -1000000
	var targets=b.enemies(u)
	if targets.is_empty():return 1000000
	var enemy=b.unit(targets[0])
	return clampi(_position(b,u)-_position(b,enemy),-50000,50000)

func _position(b,u:Dictionary)->int:
	var health=Protocol.round_ratio(int(u.H)*10000,int(u.Hmax))
	var shield=Protocol.round_ratio(mini(b.buff(u,"护体"),int(u.Hmax))*2200,int(u.Hmax))
	var qi=Protocol.round_ratio(int(u.E)*650,int(u.M))
	# Only *unsettled* endpoint potential is estimated here. No past damage double-count.
	var incoming=0;var layers=b.buff(u,"侵袭")
	for i in range(5):incoming+=layers;layers/=2
	var recovery=0;layers=b.buff(u,"回春")
	for i in range(5):recovery+=layers;layers=maxi(0,layers-1)
	var bounded_heal=mini(recovery,maxi(0,int(u.Hmax)-int(u.H)+incoming))
	var periodic=(bounded_heal-incoming)*3500/int(u.Hmax)
	var erosion=-mini(1600,b.buff(u,"蚀骨")*80)
	var resources=clampi((b.buff(u,"凝神")-b.buff(u,"逆气"))*35+(b.buff(u,"鲸吞")-b.buff(u,"滞气"))*80,-900,900)
	var sharp=mini(300,b.buff(u,"锋锐")*12)
	var opportunity=int(u.Z)*5+(250 if u.opportunity_pending else 0)
	var marks=0
	var owns_consumer=false
	for entry in u.entries:
		if entry.technique=="seal_burst" and entry.ready_window<=u.W+1:owns_consumer=true
	if owns_consumer:
		for target in b.enemies(u):marks+=mini(260,b.buff(b.unit(target),"无常印记")*25)
	return health+shield+qi+clampi(periodic,-1800,1000)+erosion+resources+sharp+opportunity+marks

func _end(b,actor:String)->Dictionary:return {"kind":"end","actor":actor,"window_id":b.state.window_id}

func category(b,a:Dictionary)->String:
	if a.kind in ["end","swap"]:return a.kind
	if a.kind=="sword":return "output"
	var v=b.variant_for(b.unit(a.actor),a)
	for s in v.sentences:
		if s.op=="qi":return "resource"
		if s.op=="heal" or s.op=="remove" or (s.op=="apply" and s.get("buff","")=="护体"):return "survival"
		if s.op=="apply" and s.get("buff","")=="无常印记":return "prepare"
	return "output"

func _gain_hint(b,a:Dictionary)->int:
	if a.kind=="end":return 0
	var u=b.unit(a.actor)
	var foes=b.enemies(u)
	if a.kind=="swap":return -5
	var target=b.unit(a.get("target",a.actor))
	if a.kind=="sword":
		var amount=Math.root_amount(u.basic_attack,Math.growth_inputs(u,{}))
		return mini(int(target.H)+b.buff(target,"护体"),amount)*3
	var v=b.variant_for(u,a);var score=0
	var growth=Math.growth_inputs(u,v)
	for s in v.sentences:
		var amount=Math.root_amount(s.amount,growth) if s.amount is Dictionary and s.amount.get("kind","")=="scaled" else int(s.amount) if not s.amount is Dictionary else 0
		if s.op=="damage" and not target.is_empty():
			score+=mini(int(target.H)+b.buff(target,"护体"),amount)*3
			if amount>=target.H+b.buff(target,"护体"):score+=10000
		elif s.op=="heal":score+=mini(int(u.Hmax)-int(u.H),amount)*3
		elif s.op=="qi":score+=mini(int(u.M)-int(u.E),amount)
		elif s.op=="remove":
			for key in b.catalog.DEBUFFS:score+=b.buff(u,key)*10
		elif s.op=="apply":
			if s.buff=="护体":score+=mini(amount,maxi(0,int(u.Hmax)/2-b.buff(u,"护体")))
			elif s.buff=="回春":score+=mini(amount*(amount+1)/2,int(u.Hmax)-int(u.H))
			elif s.buff in ["逆气","滞气","蚀骨","锋锐","神速"]:score+=amount*6
	var cost=b.costs(u,v)
	return score-int(cost.qi)/2-int(cost.hp)*3

func cheap(b,actor:String)->Dictionary:
	var best=_end(b,actor);var score=0
	for a in b.actions(actor):
		var hint=_gain_hint(b,a)
		if hint>score:score=hint;best=a
	return best

func _trial(b,a:Dictionary,budget:Dictionary,event_limit:int):
	if int(budget.events)>event_limit-512:return null
	var sim=b.fork()
	var result=sim.execute(a)
	budget.events+=sim.event_count
	if not result.ok:return null
	return sim

func shallow(b,actor:String,style:String,budget:Dictionary,event_limit:int)->Dictionary:
	var best=_end(b,actor)
	var best_score=value(b,actor)
	var base=b.unit(actor)
	var target_ids=b.enemies(base)
	for a in b.actions(actor):
		if a.kind=="end":continue
		var sim=_trial(b,a,budget,event_limit)
		if sim==null:break
		var score=value(sim,actor)
		if style=="attack" and not target_ids.is_empty():score+=30*(int(b.unit(target_ids[0]).H)-int(sim.unit(target_ids[0]).H))
		if style=="protect":score+=20*(int(sim.unit(actor).H)-int(base.H))+5*(sim.buff(sim.unit(actor),"护体")-b.buff(base,"护体"))
		if score>best_score+2:best_score=score;best=a
	return best

func rollout(initial,actor:String,style:String,budget:Dictionary,event_limit:int)->Dictionary:
	var sim=initial.fork()
	var start_t=int(sim.state.t)
	var started=int(sim.state.window_seq)
	var opponent_completed=false
	var covered=false
	var truncated=false
	var moves=0
	while not sim.state.ended:
		if int(sim.state.t)-start_t>=int(sim.catalog.data.ai.rollout_ticks) or int(sim.state.window_seq)-started>=int(sim.catalog.data.ai.rollout_windows) or moves>=24 or budget.events+sim.event_count>event_limit-1024:
			truncated=true;break
		if sim.state.current==actor and opponent_completed:
			covered=true;break
		var current=str(sim.state.current)
		if current=="":sim.advance(32);continue
		var window=str(sim.state.window_id)
		var a=shallow(sim,current,style if current!=actor else "balanced",budget,event_limit-sim.event_count)
		sim.execute(a);moves+=1
		if sim.state.window_id!=window and current!=actor:opponent_completed=true
	if sim.state.ended:covered=true
	budget.events+=sim.event_count
	return {"b":sim,"style":style,"score":value(sim,actor),"complete":covered and not truncated,"truncated":truncated,"ticks":int(sim.state.t)-start_t,"windows":int(sim.state.window_seq)-started,"opponent_complete":opponent_completed,"endpoint_window_kind":sim.state.window_kind,"moves":moves}

func normal(b,actor:String,budget:Dictionary,event_limit:int)->Dictionary:
	# Explicitly observe immediate responses at *all* blood levels, not only <50%.
	var candidates:Array=[]
	for a in b.actions(actor):
		var sim=_trial(b,a,budget,event_limit)
		if sim==null:break
		if sim.state.current==actor and sim.state.window_id==b.state.window_id and not sim.state.ended:
			# In a burst the next input remains ours. A genuine two-step supply chain
			# is legal here; in a normal turn execute() already closed that window.
			var next=shallow(sim,actor,"balanced",budget,event_limit)
			if next.kind!="end":
				var follow=_trial(sim,next,budget,event_limit)
				if follow!=null:sim=follow
			if sim.state.current==actor and sim.state.window_id==b.state.window_id:
				var before_events=sim.event_count
				sim.execute(_end(sim,actor));budget.events+=sim.event_count-before_events
		var response=rollout(sim,actor,"attack",budget,event_limit)
		response.erase("b")
		candidates.append({"action":a,"score":response.score,"complete":response.complete,"coverage":response})
	var full=candidates.filter(func(x):return x.complete)
	if full.is_empty():return {"action":cheap(b,actor),"reason":"没有完整回应，按同一当前局部口径降级","coverage":{},"coverage_complete":false}
	var pool=full
	if pool.is_empty():return {"action":cheap(b,actor),"reason":"预算不足，按合法局部收益降级","coverage":[]}
	pool.sort_custom(func(a,c):return a.score>c.score)
	return {"action":pool[0].action,"reason":"实际普通／战机权限下的有限后续与威胁检查" if not full.is_empty() else "后续未完整覆盖，保守局部选择","coverage":pool[0].coverage}

func retain(nodes:Array,width:int)->Array:
	nodes.sort_custom(func(a,b):return a.score>b.score)
	var kept:Array=[];var categories:Array=[]
	for n in nodes:
		if not categories.has(n.category):kept.append(n);categories.append(n.category)
		if kept.size()>=width:return kept
	for n in nodes:
		if not kept.has(n):kept.append(n)
		if kept.size()>=width:break
	return kept

func search(b,actor:String,budget:Dictionary,event_limit:int,node_limit:int,width:int)->Dictionary:
	var reserve=maxi(event_limit/3,event_limit*int(b.catalog.data.ai.response_reserve_percent)/100)
	var generation_limit=event_limit-reserve
	var initial_window=str(b.state.window_id)
	var beam:Array=[{"b":b.fork(),"path":[],"score":value(b,actor),"category":"end"}]
	var completed:Array=[]
	var seen:Dictionary={}
	var truncated=false
	var max_depth=3 if b.state.window_kind==Protocol.NORMAL else 9
	for depth in range(max_depth):
		var next_beam:Array=[]
		for node in beam:
			if budget.nodes>=node_limit or budget.events>generation_limit-512:truncated=true;break
			for a in node.b.actions(actor,true):
				if budget.nodes>=node_limit or budget.events>generation_limit-512:truncated=true;break
				var sim=_trial(node.b,a,budget,generation_limit)
				if sim==null:truncated=true;break
				budget.nodes+=1
				var hash=sim.public_hash()
				if seen.has(hash):continue
				seen[hash]=true
				var path=node.path.duplicate(true)
				path.append({"action":a.duplicate(true),"expected_before":node.b.public_hash()})
				var item={"b":sim,"path":path,"score":value(sim,actor),"category":category(node.b,a)}
				if sim.state.ended or sim.state.window_id!=initial_window:completed.append(item)
				else:next_beam.append(item)
		if truncated or next_beam.is_empty():break
		beam=retain(next_beam,width)
	# Close surviving plans without granting a nonexistent second normal action.
	for node in beam:
		if node.b.state.current!=actor or node.b.state.window_id!=initial_window:continue
		if budget.events>generation_limit-512:break
		var a=_end(node.b,actor)
		var sim=_trial(node.b,a,budget,generation_limit)
		if sim!=null:
			var path=node.path.duplicate(true);path.append({"action":a,"expected_before":node.b.public_hash()})
			completed.append({"b":sim,"path":path,"score":value(sim,actor),"category":node.category})
	completed=retain(completed,width)
	var evaluated:Array=[]
	for item in completed:
		var responses:Array=[];var all_complete=true;var worst=1000001
		for style in ["attack","protect","balanced"]:
			if budget.events>event_limit-1024:
				all_complete=false;truncated=true
				responses.append({"style":style,"complete":false,"truncated":true,"reason":"预留回应预算用尽","ticks":0,"windows":0})
				continue
			var r=rollout(item.b,actor,style,budget,event_limit)
			r.erase("b");responses.append(r)
			all_complete=all_complete and r.complete
			worst=mini(worst,int(r.score))
		if all_complete:item.score=worst
		else:item.score=mini(int(item.score),value(b,actor))
		item.complete=all_complete;item.responses=responses;evaluated.append(item)
	var full=evaluated.filter(func(x):return x.complete)
	if full.is_empty():
		budget.truncated=true;budget.plan=[]
		return {"action":cheap(b,actor),"reason":"三种回应未完整覆盖，丢弃不同深度比较；统一当前局部降级","responses":evaluated[0].responses if not evaluated.is_empty() else [],"coverage_complete":false}
	var pool=full
	budget.truncated=budget.truncated or truncated
	if pool.is_empty():return {"action":cheap(b,actor),"reason":"没有完整候选，合法局部降级","responses":[],"coverage_complete":false}
	pool.sort_custom(func(a,c):return a.score>c.score)
	var best=pool[0]
	var plan=best.path.duplicate(true)
	var first=plan.pop_front() if not plan.is_empty() else {"action":_end(b,actor)}
	budget.plan=plan
	budget.plan_window=initial_window
	return {"action":first.action,"reason":"完整窗口方案与三种已完成回应" if not full.is_empty() else "回应均未完整覆盖，使用保守同终点候选；不宣称完成预判","responses":best.responses,"coverage_complete":not full.is_empty(),"candidates":evaluated.size(),"plan_remaining":plan.size()}

func choose(b,profile:String,actor:String="")->Dictionary:
	if actor=="":actor=str(b.state.current)
	var start=Time.get_ticks_usec()
	var observation=b.public_hash()
	var budget=b.state.ai_budget[actor]
	var cfg=b.catalog.data.ai
	var limit=int(cfg.window_events)*(3 if profile=="extreme" else 1)
	var detail:Dictionary={}
	if profile=="easy":
		var available=b.actions(actor)
		detail={"action":available[0] if not available.is_empty() else _end(b,actor),"reason":"固定合法入口顺序"}
	elif profile in ["hard","extreme"] and not budget.get("plan",[]).is_empty():
		var next=budget.plan[0]
		if budget.get("plan_window","")==b.state.window_id and next.expected_before==observation and b.legal(next.action).ok:
			budget.plan.pop_front();detail={"action":next.action,"reason":"继续已验证且仍匹配的计划后缀","plan_remaining":budget.plan.size()}
		else:budget.plan=[]
	if detail.is_empty():
		if budget.events>limit-1024 or budget.nodes>=int(cfg.nodes)*(3 if profile=="extreme" else 1):
			budget.truncated=true;detail={"action":cheap(b,actor),"reason":"本窗预算耗尽，按明确局部收益降级而非第一按钮"}
		elif profile=="normal":detail=normal(b,actor,budget,limit)
		else:detail=search(b,actor,budget,limit,int(cfg.nodes)*(3 if profile=="extreme" else 1),int(cfg.beam))
	var choice=detail.action
	if not b.legal(choice).ok:choice=_end(b,actor);detail.reason="候选已失效，合法结束"
	detail.erase("action")
	last_trace={"actor":actor,"t":b.state.t,"W":b.unit(actor).W,"R":b.unit(actor).R,"window_id":b.state.window_id,"window_kind":b.state.window_kind,"profile":profile,"observation":observation,"choice":choice.duplicate(true),"elapsed_us":Time.get_ticks_usec()-start,"nodes":budget.nodes,"events":budget.events,"truncated":budget.truncated,"responses":[]}
	last_trace.merge(detail,true)
	if not b.simulation:b.state.ai_traces.append(last_trace.duplicate(true))
	return choice
