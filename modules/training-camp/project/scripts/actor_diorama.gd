extends Node3D
## Actor presentation adapter. No combat rules or position bonuses live here.
const SCREEN=Vector2(1280,720)
const ACTOR_HEIGHTS={"p":3.0,"e":3.0,"pet":1.0,"guard":1.2}
var camera:Camera3D
var actor_positions:Dictionary={}
var actor_roots:Dictionary={}
var actor_sprites:Dictionary={}
var shields:Dictionary={}
var textures:Dictionary={}
var rows:Array=[]
var receipt:Dictionary={}
var elapsed:float=1.0

func _mesh(shape:Mesh,material:Material,at:Vector3,parent:Node3D=null)->MeshInstance3D:
	var node=MeshInstance3D.new()
	node.mesh=shape;node.material_override=material;node.position=at
	(parent if parent!=null else self).add_child(node)
	return node

func _build_actors()->void:
	for id in ["p","e"]:
		var root=Node3D.new();root.name="Actor_"+id
		add_child(root);root.position=actor_positions.get(id,Vector3.ZERO)
		actor_roots[id]=root
		var sprite=Sprite3D.new()
		sprite.billboard=BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.shaded=false;sprite.double_sided=true
		sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
		root.add_child(sprite);actor_sprites[id]=sprite
		var shadow_mat=StandardMaterial3D.new()
		shadow_mat.albedo_color=Color(0,0,0,0.25)
		shadow_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		var shadow=CylinderMesh.new();shadow.top_radius=0.62;shadow.bottom_radius=0.62;shadow.height=0.004
		_mesh(shadow,shadow_mat,Vector3(0,0.015,0),root)
		var shield_mat=StandardMaterial3D.new()
		shield_mat.albedo_color=Color(0.44,0.91,0.77,0.14)
		shield_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		shield_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		var orb=SphereMesh.new();orb.radius=1.1;orb.height=3.4
		shields[id]=_mesh(orb,shield_mat,Vector3(0,1.55,0),root)
		shields[id].hide()

func sync_visual(units:Array)->void:
	rows=units
	_update_visual()

func animate(event:Dictionary)->void:
	receipt=event;elapsed=0
	if event.has("visual"):rows=event.visual
	_update_visual()

func _process(delta:float)->void:
	elapsed+=delta
	_update_visual()

func _update_visual()->void:
	for actor in rows:
		var id=str(actor.id)
		if not actor_sprites.has(id):continue
		var sprite:Sprite3D=actor_sprites[id]
		var moving=receipt.get("actor","")==id and elapsed<0.72
		var action="attack"
		if moving:
			if receipt.get("kind","") in ["apply","heal","qi"]:action="cast_2"
			elif receipt.get("kind","")=="cast":action="cast_1"
		var beast=str(actor.art)=="cinder_horn_ox"
		if beast:action="attack"
		var path="res://assets/characters/"+str(actor.art)+"/"+action+".png"
		if not textures.has(path):textures[path]=load(path)
		sprite.texture=textures[path]
		sprite.hframes=4 if beast else 8;sprite.vframes=4 if beast else 1
		sprite.frame=mini(15 if beast else 7,int(elapsed/(0.045 if beast else 0.085))) if moving else 0
		sprite.pixel_size=3.0/(410.0 if beast else 384.0)
		sprite.position.y=(220.0 if beast else 256.0)*sprite.pixel_size
		sprite.flip_h=id=="e" and not beast
		sprite.modulate=Color.WHITE if actor.H>0 else Color(0.45,0.45,0.48,0.6)
		shields[id].visible=int(actor.get("buffs",{}).get("护体",0))>0
		actor_roots[id].position=actor_positions.get(id,Vector3.ZERO)
		if receipt.get("target","")==id and receipt.get("kind","")=="damage" and elapsed<0.3:
			actor_roots[id].position.x+=sin(elapsed*85)*0.07

func actor_center_screen(id:String)->Vector2:
	return actor_feet_screen(id).lerp(actor_head_screen(id),0.5)

func actor_feet_screen(id:String)->Vector2:
	return camera.unproject_position(to_global(actor_positions.get(id,Vector3.ZERO)))

func actor_head_screen(id:String)->Vector2:
	return camera.unproject_position(to_global(actor_positions.get(id,Vector3.ZERO)+Vector3(0,float(ACTOR_HEIGHTS.get(id,3)),0)))

func _screen_to_floor(point:Vector2,height:float)->Vector3:
	var hit=Plane(Vector3.UP,height).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
	return hit if hit!=null else Vector3.ZERO
