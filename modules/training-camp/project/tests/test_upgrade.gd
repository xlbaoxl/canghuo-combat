extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
const P=preload("res://scripts/presentation.gd")
const Math=preload("res://scripts/effect_math.gd")
const Protocol=preload("res://scripts/combat_protocol.gd")
var c=Catalog.new()
var checks:Array=[]
var failures:Array=[]
var cases:Dictionary={}
var proofs:Dictionary={}

func _initialize():call_deferred("run")
func check(condition:bool,id:String,label:String,actual=null)->void:
	var r={"case":id,"label":label,"pass":condition,"actual":actual}
	checks.append(r)
	if not cases.has(id):cases[id]=[]
	cases[id].append(r)
	if not condition:failures.append(r);push_error("FAIL "+id+" "+label+" "+str(actual))
func snap(slots:Array=["sword","guard","heal","qi"],arts:Array=[],catalog=null)->Dictionary:
	var cat=catalog if catalog!=null else c
	return cat.snapshot("C01",slots,arts,"mirror","normal").value
func fixture(slots:Array=["sword","guard","heal","qi"],arts:Array=[],catalog=null):
	var b=Battle.new(catalog if catalog!=null else c)
	var ok=b.start(snap(slots,arts,catalog))
	assert(ok.ok)
	return b
func action(b,slot:int,target:String="e",actor:String="p")->Dictionary:
	return {"kind":"cast","actor":actor,"slot":slot,"target":target,"window_id":b.state.window_id}
func end(b,actor:String="")->void:b.execute({"kind":"end","actor":actor if actor!="" else b.state.current,"window_id":b.state.window_id})
func burst(b,actor:String="p",A:int=70)->void:
	if b.state.current!="":b.close_window(false)
	for u in b.state.units:u.A=0;u.Z=0;u.opportunity_pending=false
	b.state.tickets=[]
	b.unit(actor).A=A;b.unit(actor).Z=100;b.unit(actor).opportunity_locked=false
	b.qualify_opportunities();b.advance()
	assert(b.state.current==actor and b.state.window_kind==Protocol.OPPORTUNITY)
func next_player(b,min_w:int=-1)->void:
	var wanted=b.unit("p").W+1 if min_w<0 else min_w
	var i=0
	while not b.state.ended and (b.state.current!="p" or b.unit("p").W<wanted) and i<30:
		end(b);i+=1
func isolated_tick(b)->void:
	if b.state.current!="":b.close_window(false)
	b.public_tick()
func customized(sentences:Array,id:String="test",cost:int=0):
	var data=c.data.duplicate(true)
	data.techniques.append({"id":id,"name":"试验法","source_family_id":id,"proficiency_group_id":"fire","version":1,"capacity":3,"prepared_qi_cost":cost,"sentences":sentences})
	return Catalog.new(data)
func damage_sentence(id:String,amount,target:String="enemy")->Dictionary:return {"id":id,"op":"damage","target":target,"amount":amount}
func event_of(b,name:String)->Array:return b.events.filter(func(e):return e.event_type==name)
func ids_of(rows:Array,key:String)->Array:
	var out:Array=[]
	for row in rows:out.append(row[key])
	return out
func poison_ticks(layers:int)->Dictionary:
	var b=fixture();b.damage("e","p",100,"direct","fixture")
	b.set_buff(b.unit("p"),"回春",layers);b.close_window(false)
	for i in range(layers):b.public_tick()
	return {"healed":b.unit("p").stats_log.periodic_heal_only_actual,"request":b.unit("p").stats_log.periodic_heal_requested,"accounting":b.accounting()}

func run()->void:
	check(c.errors.is_empty(),"T50","published content compiles",c.errors)
	var b=fixture();var old=action(b,0);var r=b.execute(old)
	check(r.ok and b.state.current=="e" and b.unit("p").R==1,"T01","normal cast closes its window")
	check(not b.execute(old).ok,"T01","stale second cast rejected")
	b=fixture();old=action(b,0);r=b.execute({"kind":"sword","actor":"p","target":"e"})
	check(r.ok and not b.execute(old).ok,"T02","sword consumes normal main action")
	b=fixture();burst(b);var W=b.unit("p").W
	for i in range(4):check(b.execute(action(b,i,"e" if i==0 else "p")).ok,"T03","burst slot "+str(i))
	check(b.unit("p").W==W and b.state.current=="p","T03","all four do not advance W")
	check(not b.execute(action(b,0)).ok,"T04","CD1 cannot repeat in one burst")
	b=fixture();b.unit("p").Z=99;b.execute(action(b,0))
	check(b.state.current=="p" and b.state.window_kind==Protocol.OPPORTUNITY and b.unit("p").W==2 and b.legal(action(b,0)).ok,"T05","normal W1 leads to burst W2 and CD1 ready")
	b=fixture(["pressure","guard","heal","qi"]);b.unit("p").Z=100;b.qualify_opportunities();b.execute(action(b,0))
	check(b.unit("p").W==2 and not b.legal(action(b,0)).ok,"T06","CD3 remains locked at W2")
	end(b);next_player(b,3);check(b.unit("p").W==3 and not b.legal(action(b,0)).ok,"T06","CD3 locked at W3")
	end(b);next_player(b,4);check(b.legal(action(b,0)).ok,"T06","CD3 ready at W4")
	var ready=b.unit("p").entries[0].ready_window
	b.unit("p").S=400;b.set_buff(b.unit("p"),"神速",3)
	check(b.unit("p").entries[0].ready_window==ready and b.root_sqrt(400)+3==23,"T07","speed affects accumulation not expiry")
	b=fixture(["ember_guard","guard","heal","qi"],["blade"]);burst(b);W=b.unit("p").W;var R=b.unit("p").R
	b.execute(action(b,0));check(b.unit("p").W==W and b.unit("p").R==R,"T08","multiple effects do not advance clocks")
	b=fixture();burst(b,"p",70);var t=b.state.t;var E=b.unit("p").E
	b.close_window(false);check(b.unit("p").A==70 and b.state.t==t and b.unit("p").E==E,"T09","burst preserves A and no free tick")
	b=fixture();burst(b,"p",100);check(b.state.window_kind==Protocol.OPPORTUNITY and b.unit("p").A==100,"T10","opportunity before preserved normal")
	end(b);check(b.state.current=="p" and b.state.window_kind==Protocol.NORMAL,"T10","ordinary qualification remains")
	b=fixture(["ember_guard","guard","heal","qi"]);b.unit("p").Z=99;b.execute(action(b,0))
	var spell=event_of(b,"SPELL_FINISHED")[0].event_id
	var opened=event_of(b,"OPPORTUNITY_OPENED")[0].event_id
	var closed=event_of(b,"NORMAL_CLOSED")[0].event_id
	check(spell<closed and closed<opened,"T11","root, normal close, burst are ordered")
	proofs.T11=b.events
	var b2=fixture();b2.close_window(false)
	b=fixture();b.close_window(false)
	b2.state.units.reverse()
	for q in [b,b2]:
		for u in q.state.units:u.Z=100
		q.qualify_opportunities()
	check(ids_of(b.state.tickets,"unit_id")==ids_of(b2.state.tickets,"unit_id"),"T12","storage order cannot choose tickets")
	b=fixture();burst(b);b.unit("p").Z=100;b.qualify_opportunities()
	check(not b.unit("p").opportunity_pending,"T13","no requalification inside locked burst")
	b.close_window(false);b.qualify_opportunities();check(not b.unit("p").opportunity_pending,"T13","close burst does not unlock")
	b.open_window(b.unit("p"),Protocol.NORMAL);b.close_window(false)
	check(b.unit("p").opportunity_pending,"T13","own normal close unlocks and qualifies")
	b=fixture();b.unit("e").Z=100;b.qualify_opportunities();b.damage("p","e",400,"direct","fatal")
	check(b.state.ended and b.state.tickets.is_empty() and not b.unit("e").opportunity_pending,"T14","terminal cancels pending ticket")
	b=fixture();b.unit("p").E=0;var before=JSON.stringify(b.state)
	check(not b.execute(action(b,0)).ok and JSON.stringify(b.state)==before,"T15","no qi failure is entirely atomic")
	b.unit("p").E=160;b.unit("p").H=5;b.set_buff(b.unit("p"),"撕裂",5);before=JSON.stringify(b.state)
	check(not b.execute(action(b,0)).ok and JSON.stringify(b.state)==before,"T15","payment cannot reach zero HP")
	var sentences=[damage_sentence("s1",5),{"id":"s2","op":"apply","target":"enemy","buff":"侵袭","amount":2,"condition":{"buff":"无常印记","min":1,"read_at":"GROUP_START"}}]
	var cat=customized(sentences,"conditional",10);b=fixture(["conditional","guard","heal","qi"],[],cat);r=b.execute(action(b,0))
	check(r.records.s2.e.status=="skipped" and b.unit("p").entries[0].ready_window==3 and r.after_payment_E==150,"T16","skipped sentence retains paid CD2")
	check(c.techniques.sword.CD==c.techniques.sword_deep.CD and c.techniques.sword.prepared_qi_cost==10,"T17","same structure growth not repriced at execution")
	check(c.techniques.sword_echo.N==2 and c.techniques.sword_echo.CD==2 and c.techniques.sword.N==1,"T18","independent repeat expands; old version remains")
	b=fixture(["pressure","guard","heal","qi"]);b.execute(action(b,0));next_player(b,2)
	check(b.execute({"kind":"swap","actor":"p","slot":0,"technique":"edge"}).ok,"T19","remove cooling family from A")
	check(b.unit("p").family_ready_window.niliu==4 and b.swap_ready(b.unit("p"),1,"pressure")==4,"T19","family waiting survives removal")
	end(b);next_player(b,3);b.execute({"kind":"swap","actor":"p","slot":1,"technique":"pressure"})
	check(not b.legal(action(b,1)).ok and b.effective_ready(b.unit("p"),1)==4,"T19","new slot cannot bypass same-family obligation")
	b=fixture(["ember_guard","guard","heal","qi"]);b.execute(action(b,0));next_player(b,2);E=b.unit("p").E
	check(b.execute({"kind":"swap","actor":"p","slot":0,"technique":"sword"}).ok and b.unit("p").entries[0].ready_window==4 and b.unit("p").E==E,"T20","slot keeps original expiry and swap is free")
	check(not b.execute({"kind":"swap","actor":"p","slot":1,"technique":"edge"}).ok and not b.legal(action(b,0)).ok,"T21","second prep and swapped cast rejected")
	b=fixture();burst(b);b.execute(action(b,0));check(not b.execute({"kind":"swap","actor":"p","slot":0,"technique":"edge"}).ok,"T21","used slot cannot swap")
	check(b.execute(action(b,1,"p")).ok,"T22","same CD other skill remains independent")
	cat=customized([damage_sentence("s1",10),{"id":"s2","op":"heal","amount":10,"target":"self"}],"drain")
	check(cat.techniques.drain.N==2,"T23","damage plus heal still two operations")
	var raw=cat.data.techniques.back().duplicate(true);raw.sentences[0].op="arbitrary_drain"
	check(not cat.compile(raw).ok,"T23","opaque composite operation rejected")
	for expr in [{"ref":"future","field":"hp_loss"},{"ref":"s1","field":"layers_added"},{"ref":"s1","field":"hp_loss","den":0},{"ref":"s1","field":"hp_loss","growth":2}]:
		raw=cat.data.techniques.back().duplicate(true);raw.sentences[1].amount=expr
		check(not cat.compile(raw).ok,"T24","invalid expression rejected",expr)
	b=fixture(["sword","guard","heal","qi"],["blade"]);b.unit("p").H=3;b.set_buff(b.unit("p"),"撕裂",100);b.set_buff(b.unit("p"),"锋锐",40);b.set_buff(b.unit("e"),"护体",20)
	E=b.unit("p").E;W=b.unit("p").W;var enemyH=b.unit("e").H
	b.unit("p").art_entries[0].last_normal=0
	b.collect_automatic(b.unit("p"),b.record("NORMAL_OPENED","p","p"));b.drain_responses()
	check(b.unit("p").H==3 and b.unit("p").E==E and b.unit("p").W==W and not b.unit("p").main_used,"T25","auto no owner payment/action")
	check(b.buff(b.unit("p"),"锋锐")==40 and b.buff(b.unit("e"),"护体")==12 and b.unit("e").H==enemyH,"T26","artifact no owner's sharpness; enemy shield still applies")
	b=fixture();b.set_buff(b.unit("p"),"撕裂",5);b.set_buff(b.unit("p"),"逆气",3);var ai=AI.new();var a=ai.choose(b,"easy");r=b.execute(a)
	check(r.after_payment_E==147 and b.unit("p").H==295,"T27","AI input has identical personal costs")
	var snapshot=snap();var pet=snapshot.units[0].duplicate(true);pet.unit_id="pet";pet.name="测试灵宠";pet.opportunity_enabled=false;pet.is_main=false;pet.initial_buffs={"撕裂":5,"逆气":3};snapshot.units.append(pet);snapshot.order.append("pet")
	b=Battle.new(c);b.start(snapshot);b.close_window(false);b.open_window(b.unit("pet"),Protocol.NORMAL);W=b.unit("p").W;E=b.unit("p").E
	r=b.execute(action(b,0,"e","pet"))
	check(r.after_payment_E==147 and b.unit("pet").H==295 and b.unit("p").E==E and b.unit("p").W==W,"T28","pet pays its own costs and owns its clocks")
	b=fixture(["sword","guard","heal","qi"],["talisman"]);r=b.damage("e","p",200,"direct","hostile")
	check(r.hp_loss==200 and b.unit("p").H==100 and b.buff(b.unit("p"),"护体")==70,"T29","posthit protection does not rewrite 200 loss")
	check(b.accounting().ok,"T29","damage and auto shield accounting")
	b=fixture(["sword","guard","heal","qi"],["talisman"]);b.damage("e","p",400,"direct","fatal")
	check(b.state.ended and b.buff(b.unit("p"),"护体")==0,"T30","fatal hit never triggers resurrection")
	b=fixture(["sword","guard","heal","qi"],["talisman"]);b.unit("p").H=100;b.set_buff(b.unit("p"),"护体",50);b.damage("e","p",20,"direct","blocked")
	check(not b.unit("p").art_entries[0].triggered,"T31","shield-only hit no low-health proc")
	b.set_buff(b.unit("p"),"撕裂",5);b.execute(action(b,0));check(not b.unit("p").art_entries[0].triggered,"T31","HP payment no low-health proc")
	cat=customized([damage_sentence("hit",200)]);cat.data.techniques.back().sentences[0].repeat=2;cat=Catalog.new(cat.data)
	b=fixture(["test","guard","heal","qi"],["talisman"],cat);r=b.execute(action(b,0))
	check(r.records["hit.0"].e.hp_loss==200 and r.records["hit.1"].e.shield_absorbed==70,"T32","response protects second not first strike")
	cat=customized([damage_sentence("all",10,"all_enemies")]);snapshot=snap(["test","guard","heal","qi"],[],cat)
	pet=snapshot.units[1].duplicate(true);pet.unit_id="e2";pet.is_main=false;pet.opportunity_enabled=false;snapshot.units.append(pet);snapshot.order.append("e2")
	b=Battle.new(cat);b.start(snapshot);b.set_buff(b.unit("p"),"锋锐",5);r=b.execute(action(b,0))
	var reversed=snapshot.duplicate(true);reversed.units.reverse();b2=Battle.new(cat);b2.start(reversed);b2.set_buff(b2.unit("p"),"锋锐",5);var r2=b2.execute(action(b2,0))
	check(r.records.all.e.hp_loss==r2.records.all.e.hp_loss and r.records.all.e2.hp_loss==r2.records.all.e2.hp_loss and r.records.all.e.damage_request==15 and r.records.all.e2.damage_request==15 and b.buff(b.unit("p"),"锋锐")==4 and b2.buff(b2.unit("p"),"锋锐")==4,"T33","atomic effects invariant; separately frozen snapshots legitimately have distinct cast IDs",[r.records,r2.records])
	cat=customized([damage_sentence("hit",10)]);cat.data.techniques.back().sentences[0].repeat=2;cat=Catalog.new(cat.data)
	b=fixture(["test","guard","heal","qi"],[],cat);b.set_buff(b.unit("p"),"锋锐",5);r=b.execute(action(b,0))
	check(r.records["hit.0"].e.damage_request==15 and r.records["hit.1"].e.damage_request==14,"T34","successive attacks read successive sharpness")
	b=fixture();b.unit("p").H=5;b.set_buff(b.unit("p"),"回春",5);b.set_buff(b.unit("p"),"侵袭",8);isolated_tick(b)
	check(b.unit("p").H==2 and not b.state.ended and b.buff(b.unit("p"),"侵袭")==4,"T35","same-tick net not premature death")
	b=fixture();b.unit("p").H=5;b.unit("e").H=5
	for u in b.state.units:b.set_buff(u,"侵袭",8)
	isolated_tick(b);check(b.state.result=="draw","T36","simultaneous terminal is draw")
	b=fixture(["sword","guard","heal","qi"],["blade"]);b.set_buff(b.unit("p"),"蚀骨",10);b.set_buff(b.unit("p"),"回春",5);b.set_buff(b.unit("p"),"侵袭",8);b.set_buff(b.unit("p"),"撕裂",10)
	b.close_window(false);b.set_buff(b.unit("p"),"撕裂",10);var H=b.unit("p").H;var autos=b.unit("p").stats_log.automatic
	burst(b);check(b.unit("p").H==H and b.buff(b.unit("p"),"回春")==5 and b.buff(b.unit("p"),"侵袭")==8 and b.unit("p").stats_log.automatic==autos,"T37","burst does not duplicate normal or public events")
	b.execute(action(b,0));check(b.unit("p").H==H-10,"T37","chosen spell still pays tear in burst")
	b.close_window(false);check(b.buff(b.unit("p"),"撕裂")==10,"T37","burst close does not halve tear")
	var data=c.data.duplicate(true);var art=data.artifacts.filter(func(x):return x.id=="talisman")[0].duplicate(true);art.id="talisman2";art.source_family_id="talisman2";art.priority=-1;data.artifacts.append(art);cat=Catalog.new(data)
	b=fixture(["sword","guard","heal","qi"],["talisman","talisman2"],cat);b.damage("e","p",200,"direct","test")
	var triggered=event_of(b,"AUTOMATIC_TRIGGERED")
	check(triggered.size()==2 and triggered[0].source_id=="talisman2" and b.buff(b.unit("p"),"护体")==140,"T38","snapshot-based stable priority responses")
	b.damage("e","p",150,"direct","again");check(event_of(b,"AUTOMATIC_TRIGGERED").size()==2,"T38","once flags prevent reentry")
	for split in [false,true]:
		cat=customized([damage_sentence("one",2),damage_sentence("two",3)] if split else [damage_sentence("one",5)])
		b=fixture(["test","guard","heal","qi"],[],cat);b.execute(action(b,0))
		check(b.unit("p").stats_log.z_damage==1,"T39","aggregate before round",split)
	cat=customized([damage_sentence("hit",100,"all_enemies"),damage_sentence("more",100,"all_enemies")]);snapshot=snap(["test","guard","heal","qi"],[],cat)
	pet=snapshot.units[1].duplicate(true);pet.unit_id="e2";pet.is_main=false;pet.opportunity_enabled=false;snapshot.units.append(pet);snapshot.order.append("e2")
	b=Battle.new(cat);b.start(snapshot);b.execute(action(b,0));check(b.unit("p").stats_log.z_damage==12,"T40","one root cap for multi-target multi-strike")
	cat=customized([damage_sentence("self",5,"self")]);b=fixture(["test","guard","heal","qi"],[],cat);b.execute(action(b,0));check(b.unit("p").stats_log.z_damage==0,"T41","self damage not rewarded")
	b=fixture();b.execute(action(b,2,"p"));check(b.unit("p").stats_log.z_damage==0,"T41","overhealing not rewarded")
	b=fixture();b.unit("e").H=1;b.execute(action(b,0));check(event_of(b,"ROOT_ACTION_CLOSED")[0].qualifying_hp_loss==1,"T41","overkill excluded from qualifying amount")
	b=fixture(["ember","guard","heal","qi"]);burst(b);b.execute(action(b,0));b.close_window(false)
	for i in range(3):b.public_tick()
	check(b.unit("p").stats_log.z_damage==0 and b.unit("e").stats_log.z_damage==0,"T42","burst and later DOT cannot refill behavior gauge")
	for scale in [1,10]:
		cat=customized([damage_sentence("hit",5*scale)]);snapshot=snap(["test","guard","heal","qi"],[],cat);snapshot.opportunity.combat_scale_ref=300*scale
		b=Battle.new(cat);b.start(snapshot);b.execute(action(b,0));check(b.unit("p").stats_log.z_damage==1,"T43","damage/reference scale invariance",scale)
	b=fixture();b.unit("p").Z=97;b.add_opportunity(b.unit("p"),10,"damage");b.qualify_opportunities();b.qualify_opportunities()
	check(b.unit("p").Z==100 and b.unit("p").stats_log.z_overflow==7 and b.state.tickets.size()==1,"T44","clamp and one ticket")
	b=fixture();burst(b);b.unit("p").Z=100;b.close_window(false);b.open_window(b.unit("e"),Protocol.NORMAL);b.close_window(false)
	check(b.unit("p").opportunity_locked and not b.unit("p").opportunity_pending,"T45","other normal doesn't unlock holder")
	b.open_window(b.unit("p"),Protocol.NORMAL);b.close_window(false);check(b.unit("p").opportunity_pending,"T45","holder normal unlocks")
	snapshot=c.snapshot("C01",["ember_guard","guard","heal","qi"],[],"mirror","normal",103,["p","e"],"expert").value
	b=Battle.new(c);b.start(snapshot);r=b.execute(action(b,0))
	check(r.records.s1.e.hp_loss==65 and r.records.s2.e.layers_added==13 and r.records.s3.p.layers_added==26,"T46","65 to13 to26 without repeated growth")
	var growth=Math.growth_inputs(snapshot.units[0],c.techniques.ember_guard)
	var before_amount=Math.root_amount(c.techniques.ember_guard.sentences[0].amount,growth)
	snapshot.units[0].stats.Hmax*=2;snapshot.units[0].stats.S*=2
	check(Math.root_amount(c.techniques.ember_guard.sentences[0].amount,Math.growth_inputs(snapshot.units[0],c.techniques.ember_guard))==before_amount,"T47","unbound H/S do not modify root effect")
	check(Math.growth_inputs(snapshot.units[0],c.techniques.sword).technique_bonus_bp==Math.growth_inputs(snapshot.units[0],c.techniques.sword_echo).technique_bonus_bp and c.techniques.sword.CD!=c.techniques.sword_echo.CD,"T48","family mastery shared, structure separate")
	var long_heal=poison_ticks(35);var short_heal=poison_ticks(4)
	check(long_heal.request==630 and short_heal.request==10,"T49","nonlinear spring requests 630 vs10",[long_heal,short_heal])
	for character in c.data.characters:
		for loadout in c.data.loadouts.values():
			check(c.validate(character.stats,loadout.slots,loadout.artifacts).ok,"T50","legal scaled preset "+character.id+" "+loadout.name)
		for diff in c.data.difficulties:
			check(c.snapshot(character.id,c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"mirror",diff.id).ok,"T50","legal mirror "+character.id+diff.id)
	b=fixture();b.set_buff(b.unit("p"),"侵袭",8);b.close_window(false)
	for i in range(4):b.public_tick()
	check(b.unit("p").stats_log.periodic_damage_requested==15 and b.unit("p").stats_log.periodic_net==-15 and b.accounting().ok,"T51","all15 DOT recorded and reconciled")
	var healing=poison_ticks(5);check(healing.healed==15 and healing.accounting.ok,"T51","all15 healing reconciled")
	b=fixture();b.damage("e","p",50,"direct","fixture");b.set_buff(b.unit("p"),"回春",5);b.set_buff(b.unit("p"),"侵袭",8);isolated_tick(b)
	check(b.unit("p").stats_log.periodic_damage_requested==8 and b.unit("p").stats_log.periodic_heal_requested==5 and b.unit("p").stats_log.periodic_net==-3 and b.accounting().ok,"T52","mixed requests and net preserved")
	data=c.data.duplicate(true);data.techniques[0].sentences[0].amount.base=17;cat=Catalog.new(data);b=fixture(["sword","guard","heal","qi"],[],cat)
	var model=P.skill_model(cat.techniques.sword,b.unit("p"),b,action(b,0));var fork=b.fork();var predicted=fork.execute(action(fork,0));r=b.execute(action(b,0))
	check(model.effect.contains("37") and r.records.s1.e.hp_loss==37 and predicted.records==r.records,"T53","data updates UI/fork/executor together")
	b=fixture();b.unit("p").E=0;old=action(b,0);r=b.execute(action(b,3,"p"));check(r.ok and not b.execute(old).ok,"T54","normal supply cannot secretly add attack")
	b=fixture();burst(b);b.unit("p").E=0;r=b.execute(action(b,3,"p"));check(r.ok and b.execute(action(b,0)).ok,"T55","burst supply then attack legal")
	# A >half-HP actor faces a lethal opponent opportunity followed by a normal action.
	data=c.data.duplicate(true)
	for v in data.techniques:
		if v.id=="guard":v.sentences[0].amount=250
		if v.id=="sword_deep":v.sentences[0].amount=230
	cat=Catalog.new(data);b=fixture(["guard","heal","qi","sword"],[],cat)
	b.unit("p").H=220;b.unit("e").slots=["sword_deep","","",""];b.unit("e").entries=[{"technique":"sword_deep","ready_window":1,"used":false},{"technique":"","ready_window":1,"used":false},{"technique":"","ready_window":1,"used":false},{"technique":"","ready_window":1,"used":false}]
	b.unit("e").Z=100;b.qualify_opportunities()
	for profile in ["normal","hard"]:
		var test=b.fork();a=ai.choose(test,profile)
		check(a.kind=="cast" and a.slot==0,"T56",profile+" selects preemptive protection above half HP",ai.last_trace)
	b=fixture();burst(b);a=action(b,0);b.state.ai_budget.p={"events":30000,"nodes":256,"truncated":true,"plan_window":b.state.window_id,"plan":[{"action":a,"expected_before":b.public_hash()}]}
	var chosen=ai.choose(b,"hard");check(chosen==a and ai.last_trace.reason.contains("后缀"),"T57","exhaustion preserves valid planned continuation")
	cat=Catalog.new(c.data);cat.data.ai.rollout_ticks=0;b=fixture([],[],cat) if false else fixture(["sword","guard","heal","qi"],[],cat)
	a=ai.choose(b,"hard");check(not ai.last_trace.get("coverage_complete",true) and ai.last_trace.reason.contains("未完整覆盖"),"T58","truncated replies never claimed complete",ai.last_trace)
	b=fixture();before=b.public_hash();fork=b.fork();r=fork.execute(action(fork,0))
	check(b.public_hash()==before,"T59","fork cannot mutate actual state")
	r2=b.execute(action(b,0));check(r.records==r2.records,"T59","forecast and actual effects agree")
	var stale=action(b,0);stale.actor="e";stale.window_id="old-window"
	check(not b.legal(stale).ok,"T59","late result bound to window rejected")
	var first=snap();b=Battle.new(c);b.start(first);b.execute(action(b,0));b.start(first)
	b2=Battle.new(c);b2.start(first)
	check(b.state==b2.state and b.events==b2.events,"T60","frozen retry resets entry, gauges and state exactly")
	var changed=snap(["ember","guard","heal","qi"],["jade"])
	check(first.loadout_hash!=changed.loadout_hash and changed.units[0].slots==changed.units[1].slots,"T60","changed loadout regenerates mirror")
	var preset1=c.snapshot("C01",["sword","guard","heal","qi"],[],"preset","P01").value
	var preset2=c.snapshot("C04",["ember","guard","heal","qi"],[],"preset","P01",103,["p","e"],"expert").value
	check(preset1.units[1]==preset2.units[1],"T60","preset does not copy changed player profile")
	first.rules="own-window-1.0";before=JSON.stringify(b.state)
	check(not b.start(first).ok and JSON.stringify(b.state)==before,"T61","old snapshot rejects without destroying current state")
	test_catalysts()
	var covered=cases.keys();covered.sort()
	var output={"rules":Protocol.RULES,"content":c.digest,"engine":Engine.get_version_info().string,"scope":"actual Godot executor and AI; graphical T59/T60/T61/T62 verified separately","checks":checks,"covered":covered,"failures":failures}
	var out=OS.get_environment("UPGRADE_VERIFY_DIR")
	if out.is_empty():out="user://upgrade_verification"
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("rules.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	FileAccess.open(out.path_join("ordering-proof.json"),FileAccess.WRITE).store_string(JSON.stringify(proofs,"\t"))
	print("UPGRADE_RULES checks=",checks.size()," cases=",covered.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

# 2026-10-05: author correction. Passive effect and active Cui are not the same entry.
func catalyst(b,slot:int,target:String="e")->Dictionary:
	return {"kind":"artifact","actor":"p","slot":slot,"target":target,"window_id":b.state.window_id}
func owner_auto_count(b,owner:String="p")->int:
	return b.events.filter(func(e):return e.event_type=="AUTOMATIC_TRIGGERED" and e.owner_id==owner).size()
func test_catalysts()->void:
	for id in c.artifacts:
		var artifact=c.artifacts[id]
		check(artifact.has("active") and artifact.active.CD==artifact.active.N,"CU01","compiled independent active "+id)
	var b=fixture(["sword","guard","heal","qi"],["blade"])
	check(owner_auto_count(b)==1 and not b.unit("p").art_entries[0].active_used and b.unit("p").art_entries[0].active_ready_window==1,"CU02","ordinary auto is once and leaves Cui ready")
	for command in [{"kind":"automatic","actor":"p","slot":0,"target":"e"},{"kind":"artifact_auto","actor":"p","slot":0,"target":"e"},{"kind":"artifact","actor":"p","slot":0,"target":"e","effect":"auto"}]:
		var before=JSON.stringify(b.state)
		check(not b.execute(command).ok and before==JSON.stringify(b.state),"CU03","manual auto injection rejected atomically",command)
	burst(b)
	b.set_buff(b.unit("p"),"锋锐",4);b.set_buff(b.unit("p"),"撕裂",3);b.set_buff(b.unit("p"),"逆气",5);b.set_buff(b.unit("p"),"凝神",2)
	var oldE=b.unit("p").E;var oldH=b.unit("p").H;var W=b.unit("p").W;var automatic=owner_auto_count(b)
	var auto_flags=b.unit("p").art_entries[0].duplicate(true)
	var result=b.execute(catalyst(b,0))
	check(result.ok and result.records.s1.e.damage_request==33 and b.unit("p").E==oldE-19 and b.unit("p").H==oldH-3,"CU04","Cui own effect, modified qi/HP costs and personal direct-hit modifiers")
	check(b.buff(b.unit("p"),"锋锐")==3 and b.unit("p").W==W and b.unit("p").art_entries[0].active_ready_window==W+1,"CU05","active consumes personal sharpness once, own CD, not extra W")
	check(owner_auto_count(b)==automatic and b.unit("p").art_entries[0].last_normal==auto_flags.last_normal and b.unit("p").art_entries[0].triggered==auto_flags.triggered,"CU06","Cui never repeats or resets auto trigger")
	var before=JSON.stringify(b.state)
	check(not b.execute(catalyst(b,0)).ok and before==JSON.stringify(b.state),"CU07","same-window Cui replay rejected")
	check(b.legal(action(b,0)).ok and not b.unit("p").entries[0].used,"CU08","Cui uses own entry, ordinary spell still available in burst")
	var commits=event_of(b,"SPELL_COMMITTED").filter(func(e):return e.source_kind=="ARTIFACT_CATALYST")
	check(commits.size()==1 and commits[0].resource_owner_id=="p" and commits[0].source_id=="catalyst_blade","CU09","manual source and payment trace explicit")
	b=fixture(["sword","guard","heal","qi"],["blade"]);W=b.unit("p").W;var window=b.state.window_id
	result=b.execute(catalyst(b,0));check(result.ok and b.state.window_id!=window and b.unit("p").stats_log.catalysts==1 and b.unit("p").stats_log.casts==1,"CU10","normal Cui consumes the single main action")
	check(b.unit("p").entries.all(func(x):return not x.used),"CU10","does not consume a technique slot")
	check(b.accounting().ok,"CU11","normal Cui resources reconcile")
	b=fixture(["sword","guard","heal","qi"],["jade"]);burst(b);b.unit("p").E=0;before=JSON.stringify(b.state)
	check(not b.execute(catalyst(b,0,"p")).ok and before==JSON.stringify(b.state),"CU12","Cui insufficient qi leaves all passive and active state unchanged")
	b.unit("p").E=100;b.unit("p").H=3;b.set_buff(b.unit("p"),"撕裂",3);before=JSON.stringify(b.state)
	check(not b.execute(catalyst(b,0,"p")).ok and before==JSON.stringify(b.state),"CU12","Cui cannot pay lethal HP")
	b=fixture(["sword","guard","heal","qi"],["talisman"]);b.damage("e","p",200,"direct","test");automatic=owner_auto_count(b)
	burst(b);oldH=b.unit("p").H;var shield=b.buff(b.unit("p"),"护体")
	result=b.execute(catalyst(b,0,"p"))
	check(result.ok and b.unit("p").H==oldH+40 and b.buff(b.unit("p"),"护体")==shield and owner_auto_count(b)==automatic,"CU13","already-triggered protection does not disable separate active healing")
	var snapshot=c.snapshot("C01",["sword","guard","heal","qi"],["blade"],"mirror","normal",103,["p","e"],"base",["blade"]).value
	b=Battle.new(c);b.start(snapshot)
	check(owner_auto_count(b)==0 and b.legal(catalyst(b,0)).ok,"CU14","automatic-only off switch does not disable Cui")
	var data=c.data.duplicate(true)
	for artifact in data.artifacts:
		if artifact.id=="blade":artifact.erase("active")
	var cat=Catalog.new(data);b=fixture(["sword","guard","heal","qi"],["blade"],cat)
	check(cat.errors.is_empty() and not b.legal(catalyst(b,0)).ok and not b.actions("p").any(func(x):return x.kind=="artifact"),"CU15","missing active never falls back to auto payload")
	data=c.data.duplicate(true)
	for artifact in data.artifacts:
		if artifact.id=="jade":artifact.active.sentences.append({"id":"s2","op":"heal","amount":1,"target":"self"})
	cat=Catalog.new(data);b=fixture(["sword","guard","heal","qi"],["jade"],cat);burst(b);W=b.unit("p").W
	result=b.execute(catalyst(b,0,"p"));check(result.ok and b.unit("p").art_entries[0].active_ready_window==W+2,"CU16","active CD compiles from independent N")
	next_player(b,W+1);check(not b.legal(catalyst(b,0,"p")).ok,"CU16","independent active waits at W+1")
	next_player(b,W+2);check(b.legal(catalyst(b,0,"p")).ok,"CU16","independent active ready at W+2")
	b=fixture(["sword","guard","heal","qi"],["blade"]);var ai=AI.new()
	for entry in b.unit("p").entries:entry.used=true
	b.unit("p").sword_used=true
	for profile in ["easy","normal","hard"]:
		var sim=b.fork();var hash=b.public_hash();var chosen=ai.choose(sim,profile)
		check(chosen.kind=="artifact" and sim.legal(chosen).ok and b.public_hash()==hash,"CU17","AI can choose distinct legal Cui "+profile,chosen)
	var model=P.artifact_model(c.artifacts.iron,c.character("C01"))
	check(model.effect.contains("5点直接") and model.effect.contains("5层撕裂") and model.effect.contains("【自动】") and model.effect.contains("【催】"),"CU18","auto attack and active tear are visibly different")
	b=fixture(["sword","guard","heal","qi"],["jade"]);var original=b.state.snapshot.duplicate(true);b.execute(catalyst(b,0,"p"));b.start(original)
	check(not b.unit("p").art_entries[0].active_used and b.unit("p").art_entries[0].active_ready_window==1 and owner_auto_count(b)==1,"CU19","retry resets active and auto independently")
