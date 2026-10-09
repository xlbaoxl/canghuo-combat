extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const AI=preload("res://scripts/ai.gd")
const P=preload("res://scripts/presentation.gd")
var checks:Array=[]
var errors:Array=[]
func check(ok:bool,name:String):
	checks.append(name)
	if not ok:errors.append(name);push_error(name)
func _initialize():call_deferred("run")
func run():
	var c=Catalog.new()
	for char in c.data.characters:
		for diff in c.data.difficulties:
			var snap=c.snapshot(char.id,c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"mirror",diff.id).value
			var shown=Battle.new(c);shown.capture_visual=true
			var plain=Battle.new(c)
			shown.start(snap);plain.start(snap)
			var ai=AI.new()
			for i in range(24):
				check(shown.state==plain.state,"Visual receipts preserve actual state %s/%s/%d"%[char.id,diff.id,i])
				if shown.state.ended:break
				var action=ai.choose(plain,"easy")
				shown.state.ai_budget=plain.state.ai_budget.duplicate(true)
				shown.state.ai_traces=plain.state.ai_traces.duplicate(true)
				check(shown.execute(action)==plain.execute(action),"Same actual execution with visual playback %s/%s/%d"%[char.id,diff.id,i])
			var stripped:Array=[]
			for event in shown.events:
				if event.kind=="clock":continue
				var row=event.duplicate(true);row.erase("id");row.erase("visual");stripped.append(row)
			var original:Array=[]
			for event in plain.events:
				var row=event.duplicate(true);row.erase("id");original.append(row)
			check(stripped==original,"All rule receipts unchanged "+char.id+diff.id)
	for profile in ["easy","normal","hard"]:
		var snap=c.snapshot("C01",c.data.loadouts.balanced.slots,c.data.loadouts.balanced.artifacts,"mirror","normal").value
		var shown=Battle.new(c);shown.capture_visual=true;shown.start(snap)
		var plain=Battle.new(c);plain.start(snap)
		var ai=AI.new();var other=AI.new()
		check(ai.choose(shown,profile)==other.choose(plain,profile) and shown.state.ai_budget==plain.state.ai_budget,"Visual capture preserves AI action and shared budget "+profile)
	var player={"id":"p","H":3000,"Hmax":3000,"E":1600,"M":1600,"W":1,"buffs":{"凝神":90,"逆气":25,"撕裂":12}}
	var b=Battle.new(c)
	for id in c.techniques:
		var v=c.techniques[id];var model=P.skill_model(v,player,b)
		var cost=b.costs(player,v)
		check(model.cost==cost.qi and model.hp_cost==cost.hp and model.after==player.E-cost.qi,"Presentation uses all actual cost modifiers "+id)
		check(not model.effect.is_empty() and P.icon(id)!=null,"Effect and original icon available "+id)
	var pressure=P.skill_model(c.techniques.pressure,player,b)
	check(pressure.buff_details.size()==3 and pressure.buff_details[0].name=="逆气" and pressure.buff_details[1].name=="滞气" and pressure.buff_details[2].name=="蚀骨","All pressure applications have distinct named Buff definitions")
	check(not pressure.effect.contains("增加施法") and not pressure.effect.contains("降低回气"),"Buff consequences kept out of direct skill effect")
	var clean=P.skill_model(c.techniques.heal_clean,player,b)
	check(clean.buff_details.size()==5,"Cleanse also explains all removed debuffs")
	var repeated=c.techniques.guard.duplicate(true)
	repeated.sentences.append(repeated.sentences[0].duplicate(true))
	check(P.buff_details(repeated).size()==1,"Repeated Buff references produce only one explanation")
	for id in c.artifacts:
		var model=P.artifact_model(c.artifacts[id],player,b)
		check(model.buff_details==P.buff_details({"sentences":c.artifacts[id].active.sentences+c.artifacts[id].auto}),"Artifact glossary covers automatic and active effects "+id)
	var f=FileAccess.open("user://training_camp_v2/checks/presentation.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"count":checks.size(),"checks":checks,"errors":errors},"\t"))
	print("PRESENTATION_RESULT checks=%d errors=%d"%[checks.size(),errors.size()])
	quit(0 if errors.is_empty() else 1)
