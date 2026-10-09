extends SceneTree
const Catalog=preload("res://scripts/catalog.gd")
func same_value(a,b)->bool:
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_value(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same_value(a[i],b[i]):return false
		return true
	return a==b
func _initialize():call_deferred("run")
func run():
	var c=Catalog.new()
	var report=JSON.parse_string(FileAccess.get_file_as_string("user://training_camp_v2/checks/battles.json"))
	var errors:Array=[]
	var count=0
	for group in ["pure_ai","joint_and_preset","held_out_and_numbers"]:
		for row in report[group]:
			var recorded=row.snapshot
			var player=recorded.units[0]
			var fresh=c.snapshot(player.id,player.slots,player.artifacts,recorded.mode,recorded.choice,int(recorded.seed),recorded.order)
			# The explicitly recorded H4500 numeric experiment changes only this input.
			if row.label=="numbers/H4500" and fresh.ok:fresh.value.units[0].stats.Hmax=4500
			if not fresh.ok or not same_value(fresh.value,recorded):errors.append(row.label)
			count+=1
	var result={"count":count,"errors":errors,"scope":"Final catalog reproduces every recorded corpus start snapshot, including fixed opponent mastery"}
	var file=FileAccess.open("user://training_camp_v2/checks/corpus-compatibility.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("CORPUS_COMPATIBILITY count=%d errors=%d"%[count,errors.size()])
	quit(0 if errors.is_empty() else 1)
