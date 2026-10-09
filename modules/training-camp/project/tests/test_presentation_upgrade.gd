extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
const Battle=preload("res://scripts/battle.gd")
const P=preload("res://scripts/presentation.gd")
var checks:Array=[]
var failures:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks.append({"pass":ok,"label":label})
	if not ok:failures.append(label);push_error(label)
func run():
	var c=Catalog.new()
	for profile in c.data.growth_profiles:
		for id in c.techniques:
			var b=Battle.new(c)
			var snapshot=c.snapshot("C01",[id,"","",""],[],"mirror","normal",103,["p","e"],profile.id).value
			b.start(snapshot)
			if c.techniques[id].has("requires"):b.set_buff(b.unit("e"),"无常印记",9)
			b.set_buff(b.unit("p"),"凝神",2);b.set_buff(b.unit("p"),"逆气",3);b.set_buff(b.unit("p"),"撕裂",1)
			var action={"kind":"cast","actor":"p","slot":0,"target":"e"}
			var model=P.skill_model(c.techniques[id],b.unit("p"),b,action)
			var before=b.public_hash();var predicted=b.fork();var pre=predicted.execute(action);var actual=b.execute(action)
			check(pre.ok and actual.ok and pre.records==actual.records,"prediction "+profile.id+" "+id)
			var paid=b.events.filter(func(e):return e.event_type=="SPELL_COMMITTED")[0]
			check(paid.qi_cost==model.cost and paid.hp_cost==model.hp_cost,"actual cost "+profile.id+" "+id)
			check(model.cooldown==c.techniques[id].N and model.cooldown>=1,"CD source "+profile.id+" "+id)
			check(not model.effect.is_empty() and model.effect!=c.techniques[id].get("description",""),"generated description "+profile.id+" "+id)
			check(b.public_hash()!=before and b.public_hash()==predicted.public_hash(),"real and fork result "+profile.id+" "+id)
	for id in c.artifacts:
		var model=P.artifact_model(c.artifacts[id],c.character("C01"))
		check(model.effect.contains("【自动】") and model.effect.contains("【催】"),"separate equipped descriptions "+id)
		var b=Battle.new(c);b.start(c.snapshot("C01",["sword","guard","heal","qi"],[id],"mirror","normal").value)
		var a={"kind":"artifact","actor":"p","slot":0,"target":"e"}
		for effect in c.artifacts[id].active.sentences:
			if effect.target=="self":a.target="p"
		b.set_buff(b.unit("p"),"逆气",3);b.set_buff(b.unit("p"),"凝神",2);b.set_buff(b.unit("p"),"撕裂",1)
		var active=P.catalyst_model(c.artifacts[id],b.unit("p"),b,a)
		var predicted=b.fork().execute(a);var receipt=b.execute(a)
		var paid=b.events.filter(func(e):return e.event_type=="SPELL_COMMITTED" and e.source_kind=="ARTIFACT_CATALYST")[0]
		check(active.cost==paid.qi_cost and active.hp_cost==paid.hp_cost and active.cooldown==c.artifacts[id].active.CD,"catalyst live cost and CD "+id)
		check(receipt.records==predicted.records,"catalyst preview and execution "+id)
		check(not P.passive_model(c.artifacts[id],b.unit("p")).has("cost"),"automatic info never becomes paid skill "+id)
	var report={"rules":c.data.rules,"content":c.digest,"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"scope":"computed view-model and executor; native widgets tested separately"}
	var folder=OS.get_environment("UPGRADE_VERIFY_DIR")
	if folder.is_empty():folder="user://upgrade_verification"
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("presentation.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("UPGRADE_PRESENTATION checks=",checks.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
