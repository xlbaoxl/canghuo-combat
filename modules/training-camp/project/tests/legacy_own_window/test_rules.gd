extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
var c=Catalog.new()
var checks:Array=[]
var failures:Array=[]

func check(condition:bool,name:String)->void:
	checks.append(name)
	if not condition:failures.append(name);push_error("FAIL "+name)

func fixture(slots:Array=["sword","guard","heal","qi"],arts:Array=[]):
	var b=Battle.new(c)
	b.start(c.snapshot("C01",slots,arts,"mirror","normal").value)
	return b

func cast(slot:int,target:String="e")->Dictionary:return {"kind":"cast","actor":"p","slot":slot,"target":target}

func step_to_player(b)->void:
	b.execute({"kind":"end","actor":"p"})
	var safe=0
	while b.state.current!="p" and not b.state.ended and safe<20:
		b.execute({"kind":"end","actor":b.state.current})
		safe+=1

func _initialize()->void:
	call_deferred("run")

func run()->void:
	check(c.errors.is_empty(),"content compile")
	check(c.techniques.size()==16 and c.artifacts.size()==6,"all published library exists")
	for pair in [["sword",1],["ember",2],["ember_guard",3]]:
		var b=fixture([pair[0],"guard","heal","qi"])
		var r=b.execute(cast(0))
		check(r.ok and b.unit("p").entries[0].ready==1+pair[1],"G01 N%d ready W%d"%[pair[1],pair[1]+1])
		var now=b.unit("p").W
		b.execute(cast(1,"p"))
		check(b.unit("p").W==now,"G01 multiaction does not advance W")
		check(not b.execute(cast(0)).ok,"G02 no same-entry repeat")
		for i in range(pair[1]):step_to_player(b)
		check(b.unit("p").W==pair[1]+1 and b.legal(cast(0)).ok,"G01 earliest legal own window")
	var b=fixture(["ember_guard","guard","heal","qi"])
	b.execute(cast(0));step_to_player(b)
	check(b.unit("p").W==2,"G02 cooldown fixture")
	var E=b.unit("p").E
	check(b.execute({"kind":"swap","actor":"p","slot":0,"technique":"sword"}).ok,"G02 swap while waiting")
	check(b.unit("p").entries[0].ready==4 and b.unit("p").E==E,"G02 retain window and no payment")
	check(not b.legal(cast(0)).ok,"G02 swapped slot unavailable this window")
	step_to_player(b)
	check(not b.legal(cast(0)).ok,"G02 inherited W3 still waiting")
	step_to_player(b)
	check(b.legal(cast(0)).ok,"G02 W4 restored")
	check(not c.validate(c.character("C01").stats,["sword","sword_deep","guard","qi"],[]).ok,"G03 same source rejects")
	check(not c.validate({"M":100,"Q":1},["sword","guard","heal","qi"],["jade"]).ok,"G03 capacity rejects")
	check(not c.validate(c.character("C02").stats,["sword","guard","heal","qi"],["jade","blade","robe"]).ok,"G03 third artifact rejected")
	b=fixture()
	b.unit("p").E=0
	var before=JSON.stringify(b.state)
	check(not b.execute(cast(0)).ok and JSON.stringify(b.state)==before,"G04 failed payment atomic")
	b=fixture(["seal_burst","guard","heal","qi"])
	before=JSON.stringify(b.state)
	check(not b.execute(cast(0)).ok and JSON.stringify(b.state)==before,"G04 whole cast prerequisite atomic")
	b=fixture(["ember_guard","guard","heal","qi"])
	b.unit("e").buffs["护体"]=1000
	var r=b.execute(cast(0))
	check(r.records.s1.e.actual==0 and r.records.s2.e.actual==0 and r.records.s3.p.actual==0,"G05 zero actual derived chain not missing")
	check(b.unit("p").E==1130 and b.unit("p").entries[0].ready==4,"G04 success remains paid despite zero")
	b=fixture()
	b.unit("p").buffs={"护体":900,"撕裂":10,"凝神":100,"逆气":25}
	r=b.execute(cast(0))
	check(b.unit("p").E==1515 and b.unit("p").H==2990 and b.buff(b.unit("p"),"护体")==900,"G05 cost shield-independent and merged modifiers")
	var hit=b.damage("e","p",30,"effect","test")
	check(hit.actual==30 and b.buff(b.unit("p"),"护体")==900,"G05 effect bypass shield")
	b=fixture()
	b.unit("p").H=2000
	b.unit("p").buffs={"回春":5,"侵袭":8,"鲸吞":20,"滞气":1000,"神速":2}
	b.unit("p").E=0
	var J=b.unit("p").J
	b.public_tick()
	check(b.unit("p").H==1997 and b.buff(b.unit("p"),"回春")==4 and b.buff(b.unit("p"),"侵袭")==4,"G06 shared tick net health and decay")
	check(b.unit("p").E==1,"G06 qi floor one")
	check(b.unit("p").S==121 and b.unit("p").J==mini(100,J+13),"G06 speed buff never changes sorting S")
	b=fixture()
	b.unit("p").buffs={"撕裂":11,"蚀骨":3}
	step_to_player(b)
	check(b.buff(b.unit("p"),"撕裂")==5 and b.unit("p").H==2910,"G06 tear own END and erosion current health")
	check(b.root_sqrt(121)==11 and b.root_sqrt(120)==11 and b.root_sqrt(2)==1,"integer sqrt rounding")
	check(Catalog.round_ratio(5,2)==3,"half-up rounding")
	var synthetic=c.techniques.sword.duplicate(true)
	synthetic.id="multi"
	synthetic.source_family_id="multi"
	synthetic.sentences=[{"id":"s1","op":"damage","amount":100,"target":"all_enemies"}]
	synthetic=c.compile(synthetic).value
	c.techniques.multi=synthetic
	var snap=c.snapshot("C01",["multi","guard","heal","qi"],[],"mirror","normal").value
	var extra=snap.units[1].duplicate(true)
	extra.unit_id="e2"
	extra.name="辅助单位"
	snap.units.append(extra)
	snap.order.append("e2")
	b=Battle.new(c);b.start(snap)
	b.unit("p").buffs["锋锐"]=70
	r=b.execute(cast(0))
	check(r.records.s1.e.request==170 and r.records.s1.e2.request==170 and b.buff(b.unit("p"),"锋锐")==69,"G07 multi-target sharpness snapshot once")
	check(synthetic.N==1 and c.techniques.sword_echo.N==2,"G07 independent repeat versus multi-target")
	var reversed=snap.duplicate(true)
	reversed.units.reverse()
	var b2=Battle.new(c);b2.start(reversed);b2.unit("p").buffs["锋锐"]=70
	var r2=b2.execute(cast(0))
	check(r.records==r2.records,"G07 target traversal order independent")
	var invalid=c.techniques.sword.duplicate(true)
	invalid.sentences[0].amount={"ref":"future","den":0}
	check(not c.compile(invalid).ok,"G07 invalid result DAG and denominator")
	c.techniques.erase("multi")
	b=fixture(["sword","guard","heal","qi"],["jade","blade"])
	check(b.buff(b.unit("p"),"护体")==280 and b.unit("p").E==1600,"G08 entry once free")
	var sim=b.fork()
	check(sim.unit("p").entry_done and sim.unit("p").art_entries[0].triggered,"G08 fork doesn't reenter")
	check(b.execute({"kind":"artifact","actor":"p","slot":0,"target":"p"}).ok and not b.legal({"kind":"artifact","actor":"p","slot":0,"target":"p"}).ok,"G08 catalyst own entry once")
	b=fixture(["sword","guard","heal","qi"],["talisman"])
	b.damage("e","p",1900,"direct","test")
	check(b.unit("p").H==1100 and b.buff(b.unit("p"),"护体")==700,"G08 postdamage first threshold")
	b.damage("e","p",900,"direct","test")
	check(b.buff(b.unit("p"),"护体")==0 and b.unit("p").art_entries[0].triggered,"G08 no repeated threshold")
	b=fixture(["sword","guard","heal","qi"],["talisman"])
	b.damage("e","p",5000,"direct","test")
	check(b.state.ended and b.buff(b.unit("p"),"护体")==0,"G08 fatal damage not rescued")
	for char in c.data.characters:
		for d in c.data.difficulties:
			var ss=c.snapshot(char.id,["ember","guard","heal","qi"],["jade","blade"],"mirror",d.id)
			check(ss.ok,"G09 mirror "+char.id+d.id)
			check(ss.value.units[0].slots==ss.value.units[1].slots and ss.value.units[0].artifacts==ss.value.units[1].artifacts,"G17 copied structure "+char.id+d.id)
			check(ss.value.units[1].stats.M==char.stats.M and ss.value.units[1].stats.Q==char.stats.Q,"G18 M/Q unchanged "+char.id+d.id)
		for enemy in c.data.enemies:check(c.snapshot(char.id,["ember","guard","heal","qi"],["jade","blade"],"preset",enemy.id).ok,"G09 preset "+char.id+enemy.id)
	b=fixture()
	var original=b.state.snapshot.duplicate(true)
	b.execute({"kind":"swap","actor":"p","slot":0,"technique":"ember"})
	check(b.unit("e").slots[0]=="sword","G17 mirror runtimes independent")
	b.start(original)
	check(b.unit("p").slots[0]=="sword" and b.unit("p").H==3000 and b.unit("p").E==1600,"G10 original retry snapshot")
	var s1=c.snapshot("C01",["sword","guard","heal","qi"],[],"mirror","normal").value
	var s2=c.snapshot("C01",["ember","guard","heal","qi"],["jade"],"mirror","normal").value
	check(s1.loadout_hash!=s2.loadout_hash and s2.units[1].slots[0]=="ember","G19 mirror refresh hash")
	var p1=c.snapshot("C01",["sword","guard","heal","qi"],[],"preset","P02").value
	var p2=c.snapshot("C04",["ember","guard","heal","qi"],["jade"],"preset","P02").value
	check(p1.units[1].stats==p2.units[1].stats and p1.units[1].slots==p2.units[1].slots,"G20 preset independent")
	var original_mastery=c.data.characters[0].mastery.duplicate(true)
	c.data.characters[0].mastery.potency=200
	var separate=c.snapshot("C01",["sword","guard","heal","qi"],[],"preset","P01").value
	check(separate.units[1].mastery.potency==100,"G20 preset mastery independent of player")
	c.data.characters[0].mastery=original_mastery
	b=fixture();b2=fixture()
	for a in [cast(0),cast(1,"p"),{"kind":"end","actor":"p"}]:b.execute(a);b2.execute(a)
	check(b.events==b2.events and b.state==b2.state,"G11 decisions identical across presentationless modes")
	b=fixture();b.state.t=600;b.state.current="";b.unit("p").J=0;b.unit("e").J=0;b.advance()
	check(b.state.result=="undecided","G12 observation cap not loss")
	b=fixture();b.unit("p").H=5;b.unit("e").H=5;b.unit("p").buffs={"侵袭":8};b.unit("e").buffs={"侵袭":8};b.public_tick()
	check(b.state.result=="draw","G06 simultaneous public submission draw")
	b=fixture()
	before=JSON.stringify(b.state)
	sim=b.fork();sim.execute(cast(0))
	check(JSON.stringify(b.state)==before,"G14 simulation isolated")
	b.execute(cast(0))
	check(b.unit("e").H==sim.unit("e").H and b.unit("p").E==sim.unit("p").E,"G14 prediction matches real execution")
	var ai=AI.new()
	b=fixture()
	var a=ai.choose(b,"hard")
	var trace=ai.last_trace.duplicate(true)
	check(b.legal(a).ok and trace.responses.size()==3,"A08 three opponent response assumptions")
	check(trace.nodes<=256 and trace.events<=30000+256,"G15 bounded window computation")
	b.state.ai_budget.p={"nodes":256,"events":30000,"truncated":true}
	a=ai.choose(b,"hard")
	check(b.legal(a).ok and ai.last_trace.truncated,"G15 legal fallback")
	var observation=b.public_hash()
	var fake_ui={"hover":"guard","pending":"heal","favorites":["pressure"]}
	a=ai.choose(b,"normal")
	fake_ui.pending="sword"
	var a2=ai.choose(b,"normal")
	check(a==a2 and b.public_hash()==observation,"G13 UI intent never in observation")
	# Tactical fixtures use the real published executor.
	b=fixture(["sword_deep","guard","heal","qi"]);b.unit("e").H=400
	a=ai.choose(b,"normal")
	check(a.kind=="cast" and a.slot==0,"A01 actual lethal action")
	b=fixture(["sword_deep","guard","heal","qi"]);b.unit("p").E=0;b.unit("e").H=400
	a=ai.choose(b,"normal")
	check(a.kind=="cast" and a.slot==3,"A02 supply then legal lethal chain")
	b=fixture(["seal","seal_burst","guard","qi"])
	a=ai.choose(b,"hard")
	check(a.kind=="cast" and a.slot in [0,2],"A05 preparation candidate remains reachable")
	b=fixture(["guard","heal","qi","calm"]);b.unit("p").buffs["护体"]=3000;b.unit("p").sword_used=true
	a=ai.choose(b,"normal")
	check(not (a.kind=="cast" and a.slot in [0,1,2]),"A07 no overflowing heal/shield/qi")
	b=fixture(["sword_deep","guard","heal","qi"])
	b.unit("p").H=600
	b.unit("p").E=220
	b.unit("e").E=390
	a=ai.choose(b,"normal")
	print("A04 action ",a)
	var defense=b.fork()
	defense.execute(a)
	for i in range(7):
		if defense.state.ended or defense.state.current!="p":break
		defense.execute(ai.choose(defense,"normal"))
	while not defense.state.ended and defense.state.current=="e":defense.execute(ai.choose(defense,"easy"))
	check(defense.unit("p").H>0,"A04 ordinary legal protection sequence survives actual immediate threat")
	a=ai.choose(b,"hard")
	check(b.legal(a).ok,"A04 hard response stays legal")
	defense=b.fork()
	defense.execute(a)
	for i in range(7):
		if defense.state.ended or defense.state.current!="p":break
		defense.execute(ai.choose(defense,"hard"))
	while not defense.state.ended and defense.state.current=="e":defense.execute(ai.choose(defense,"easy"))
	check(defense.unit("p").H>0,"A04 hard whole-window protection survives actual immediate threat")
	# Search receives the actual inherited recovery clock for a swapped entry.
	b=fixture(["sword_echo","guard","heal","qi"])
	b.unit("p").entries[0].ready=4
	sim=b.fork()
	check(sim.execute({"kind":"swap","actor":"p","slot":0,"technique":"ember"}).ok,"A06 valid future swap")
	check(not sim.legal(cast(0)).ok and sim.unit("p").entries[0].ready==4,"A06 new technique cannot rescue the current window")
	for i in range(2):step_to_player(sim)
	check(not sim.legal(cast(0)).ok,"A06 inherited W3 recovery still too late")
	step_to_player(sim)
	check(sim.legal(cast(0)).ok,"A06 same swap reaches real W4 readiness")
	b=fixture(["sword_deep","guard","heal","qi"]);b.unit("e").H=400
	a=ai.choose(b,"extreme")
	check(b.legal(a).ok and ai.last_trace.nodes<=768 and ai.last_trace.events<=90000,"Extreme experiment same algorithm enlarged budget remains legal")
	# Full capacity remains legal for all mirror difficulties, including simple.
	for char in c.data.characters:
		var full=c.techniques.sword.duplicate(true)
		full.id="full"
		full.source_family_id="full"
		full.prepared_qi_cost=char.stats.M
		c.techniques.full=full
		var Ffull=c.artifacts.jade.duplicate(true)
		Ffull.id="full_art"
		Ffull.source_family_id="full_art"
		Ffull.F=char.stats.Q
		c.artifacts.full_art=Ffull
		for d in c.data.difficulties:
			var full_snap=c.snapshot(char.id,["full","","",""],["full_art"],"mirror",d.id)
			check(full_snap.ok and full_snap.value.units[1].slots[0]=="full","G18 exact M/Q "+char.id+d.id)
	c.techniques.erase("full")
	c.artifacts.erase("full_art")
	# A condition skip creates missing result, never an executed zero.
	var missing=c.techniques.ember_guard.duplicate(true)
	missing.id="missing"
	missing.source_family_id="missing"
	missing.sentences[0].condition={"buff":"无常印记","min":1}
	c.techniques.missing=missing
	b=fixture(["missing","guard","heal","qi"])
	r=b.execute(cast(0))
	check(r.records.s1.e.status=="skipped" and r.records.s2.e.status=="skipped" and r.records.s3.p.status=="skipped","G04 missing prior result skips entire dependent chain")
	check(b.unit("p").E==1130 and b.unit("p").entries[0].ready==4,"G04 skipped chain does not refund or shorten N")
	c.techniques.erase("missing")
	# Faster actors can receive two own windows before the opponent's first.
	var fast=c.snapshot("C04",["sword","guard","heal","qi"],[],"mirror","normal").value
	fast.units[1].stats.S=25
	b=Battle.new(c);b.start(fast)
	step_to_player(b)
	check(b.unit("p").W==2 and b.unit("e").W==0,"A10 real speed ordering is not forced alternation")
	var dir="user://training_camp_v2/checks"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file=FileAccess.open(dir+"/rules.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"rules":c.data.rules,"content":c.data.version,"checks":checks,"failures":failures,"count":checks.size()},"\t"))
	print("RULES_RESULT checks=%d failures=%d report=%s"%[checks.size(),failures.size(),ProjectSettings.globalize_path(dir)])
	quit(0 if failures.is_empty() else 1)
