extends "res://scripts/actor_diorama.gd"
## A presentation-only, open-front stone stage. Every surface is real geometry;
## only the existing transparent actors use artwork. Cells never change rules.
const CELL_SIZE: float = 1.8
const CELL_PITCH: float = 1.9
const TEAM_OFFSET: float = 3.8
const FLOOR_Y: float = 0.06
const DEFAULT_CELLS := {
	"p": {"team": "player", "row": 2, "col": 1},
	"e": {"team": "enemy", "row": 1, "col": 1},
	"pet": {"team": "player", "row": 0, "col": 0},
	"guard": {"team": "player", "row": 2, "col": 2}}
const STONE_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 stone_color : source_color = vec4(0.40,0.49,0.48,1.0);
uniform float variation = 0.07;
varying vec3 world_point;
float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float fine = hash3(floor(world_point * 62.0));
	float coarse = hash3(floor(world_point * 5.5));
	float vein = sin(world_point.x * 4.2 + world_point.z * 3.6 + coarse * 1.2);
	float grain = (fine - 0.5) * variation + (coarse - 0.5) * variation * 0.30;
	ALBEDO = stone_color.rgb * (0.98 + grain + vein * 0.013);
	ROUGHNESS = 0.90;
	SPECULAR = 0.22;
}
"""
var camera_view: int = 0
var grid_visible: bool = true
var cell_meshes: Dictionary = {}
var _actor_cells: Dictionary = {}
var _grid_root: Node3D
var _hover_root: Node3D
var _stone_shader: Shader
var _materials: Dictionary = {}

func _ready() -> void:
	_build_environment()
	_make_materials()
	_build_stone_stage()
	_build_room_frame()
	_build_grid_overlay()
	_build_hover()
	if _actor_cells.size() != DEFAULT_CELLS.size(): reset_positions()
	_build_actors()
	set_camera_view(camera_view)
	set_grid_visible(grid_visible)

func _build_environment() -> void:
	camera = Camera3D.new()
	camera.name = "StageCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1; camera.far = 100.0
	add_child(camera); camera.current = true
	set_camera_view(camera_view)
	var world := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("152a30")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("bdd3ce")
	atmosphere.ambient_light_energy = 0.68
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = atmosphere; add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "SoftUpperLeftLight"
	sun.rotation_degrees = Vector3(-52, -24, 0)
	sun.light_color = Color("fff0d4"); sun.light_energy = 1.05
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 35.0
	sun.shadow_blur = 1.5; add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 5.0, 4.0)
	fill.light_color = Color("bddfdf"); fill.light_energy = 0.55
	fill.omni_range = 18.0; fill.omni_attenuation = 1.2
	add_child(fill)

func _make_materials() -> void:
	_stone_shader = Shader.new(); _stone_shader.code = STONE_CODE
	_materials.floor_a = _stone(Color("6d8580"), 0.10)
	_materials.floor_b = _stone(Color("657d79"), 0.10)
	_materials.base = _stone(Color("435c5b"), 0.10)
	_materials.edge = _stone(Color("78908a"), 0.07)
	_materials.wall = _stone(Color("314e4b"), 0.06)
	_materials.wall_panel = _stone(Color("3d5c56"), 0.06)
	_materials.dark = _stone(Color("1e3837"), 0.05)
	_materials.walk = _stone(Color("263e3e"), 0.07)
	_materials.backdrop = _stone(Color("1b3236"), 0.02)
	_materials.bronze = _solid(Color("af9054"), 0.45, 0.48)
	_materials.dark_bronze = _solid(Color("5a634c"), 0.62, 0.30)
	_materials.grid_player = _solid(Color("a7bfb0"), 0.75, 0.0)
	_materials.grid_enemy = _solid(Color("beaf8e"), 0.75, 0.0)
	var lantern := _solid(Color("edca7d"), 0.62, 0.0)
	lantern.emission_enabled = true; lantern.emission = Color("e8b563")
	lantern.emission_energy_multiplier = 0.7
	_materials.lantern = lantern

func _stone(tint: Color, variation: float) -> ShaderMaterial:
	var material := ShaderMaterial.new(); material.shader = _stone_shader
	material.set_shader_parameter("stone_color", tint)
	material.set_shader_parameter("variation", variation)
	return material

func _solid(tint: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint; material.roughness = rough; material.metallic = metal
	return material

func _box(dimensions: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var shape := BoxMesh.new(); shape.size = dimensions
	var object := _mesh(shape, material, at, parent)
	object.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return object

func _slab(dimensions: Vector3, at: Vector3, material: Material, bevel: float = 0.04) -> MeshInstance3D:
	# Separate flat faces keep bevels readable at the 720p prototype camera.
	var half := dimensions * 0.5
	var inset := [Vector3(-half.x + bevel, half.y, -half.z + bevel), Vector3(-half.x + bevel, half.y, half.z - bevel), Vector3(half.x - bevel, half.y, half.z - bevel), Vector3(half.x - bevel, half.y, -half.z + bevel)]
	var rim := [Vector3(-half.x, half.y - bevel, -half.z), Vector3(-half.x, half.y - bevel, half.z), Vector3(half.x, half.y - bevel, half.z), Vector3(half.x, half.y - bevel, -half.z)]
	var base := [Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z)]
	var normals := [Vector3.LEFT, Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(surface, inset[0], inset[1], inset[2], inset[3], Vector3.UP)
	for side: int in range(4):
		var next: int = (side + 1) % 4
		_quad(surface, inset[side], inset[next], rim[next], rim[side], (normals[side] + Vector3.UP).normalized())
		_quad(surface, rim[side], rim[next], base[next], base[side], normals[side])
	_quad(surface, base[3], base[2], base[1], base[0], Vector3.DOWN)
	var object := _mesh(surface.commit(), material, at)
	object.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return object

func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for point: Vector3 in [a, b, c, a, c, d]:
		surface.set_normal(normal); surface.add_vertex(point)

func _build_stone_stage() -> void:
	_box(Vector3(40, 0.16, 30), Vector3(0, -0.96, -1.0), _materials.backdrop).name = "GroundBelowStage"
	_slab(Vector3(14.6, 0.58, 7.2), Vector3(0, -0.43, 0), _materials.base, 0.11).name = "ThickStoneFoundation"
	_slab(Vector3(14.4, 0.20, 7.0), Vector3(0, -0.16, 0), _materials.dark, 0.035).name = "RecessedGroutBed"
	# Exactly nine individually modelled cells per side. No tactical cells in
	# the central dark aisle; the foundation is intentionally continuous below it.
	for team: String in ["player", "enemy"]:
		for row: int in range(3):
			for col: int in range(3):
				var center: Vector3 = _cell_center(team, row, col)
				var slab := _slab(Vector3(CELL_SIZE, 0.20, CELL_SIZE), center - Vector3(0, 0.10, 0), _materials.floor_a if (row + col) % 2 == 0 else _materials.floor_b, 0.035)
				slab.name = "Cell_%s_%d_%d" % [team, row, col]
				slab.set_meta("team", team); slab.set_meta("row", row); slab.set_meta("col", col)
				cell_meshes[_cell_key(team, row, col)] = slab
	_slab(Vector3(1.6, 0.14, 5.64), Vector3(0, -0.11, 0), _materials.walk, 0.025).name = "CentralSeparationAisle"
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.035, 0.025, 5.72), Vector3(side * 0.93, FLOOR_Y + 0.004, 0), _materials.dark_bronze)
		_slab(Vector3(0.42, 0.22, 7.0), Vector3(side * 6.98, -0.04, 0), _materials.edge, 0.045)
	for z: float in [-3.22, 3.22]:
		_slab(Vector3(14.4, 0.22, 0.46), Vector3(0, -0.04, z), _materials.edge, 0.045)
		_box(Vector3(14.18, 0.045, 0.035), Vector3(0, -0.13, z + (0.235 if z > 0 else -0.235)), _materials.dark_bronze)
	# Broad front fascia and sparse joints show actual thickness without
	# turning the front edge into another row of gameplay tiles.
	for x: float in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]:
		_box(Vector3(0.028, 0.28, 0.018), Vector3(x, -0.45, 3.601), _materials.dark)
	_slab(Vector3(2.6, 0.18, 0.52), Vector3(0, -0.68, 3.84), _materials.base, 0.04)

func _build_room_frame() -> void:
	# The back wall and progressively lower side walls form the box. The
	# front stays open: no roof card or beam can cover heads in the back row.
	_box(Vector3(14.4, 3.58, 0.34), Vector3(0, 1.69, -3.58), _materials.wall).name = "RearWall"
	_box(Vector3(14.55, 0.25, 0.66), Vector3(0, 3.58, -3.45), _materials.dark)
	_box(Vector3(14.65, 0.08, 0.72), Vector3(0, 3.76, -3.45), _materials.bronze)
	for x: float in [-4.55, 4.55]:
		_box(Vector3(3.8, 2.44, 0.10), Vector3(x, 1.76, -3.35), _materials.wall_panel)
		_box(Vector3(3.65, 0.055, 0.035), Vector3(x, 2.92, -3.28), _materials.dark_bronze)
		_box(Vector3(3.65, 0.055, 0.035), Vector3(x, 0.59, -3.28), _materials.dark_bronze)
		for offset: float in [-1.77, 1.77]: _box(Vector3(0.055, 2.38, 0.035), Vector3(x + offset, 1.76, -3.28), _materials.dark_bronze)
		for offset: float in [-1.07, 0.0, 1.07]:
			_box(Vector3(0.06, 1.62, 0.052), Vector3(x + offset, 1.75, -3.26), _materials.dark)
	_box(Vector3(2.95, 3.13, 0.11), Vector3(0, 1.54, -3.34), _materials.dark)
	var ring := TorusMesh.new(); ring.inner_radius = 0.62; ring.outer_radius = 0.71; ring.rings = 40; ring.ring_segments = 8
	var emblem := _mesh(ring, _materials.dark_bronze, Vector3(0, 2.15, -3.24)); emblem.rotation.x = PI * 0.5
	var seal := _box(Vector3(0.46, 0.46, 0.10), Vector3(0, 2.15, -3.23), _materials.bronze); seal.rotation.z = PI * 0.25
	for x: float in [-6.92, -2.23, 2.23, 6.92]: _pillar(Vector3(x, 0, -3.29), 3.58)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 7.06
		_box(Vector3(0.30, 2.74, 2.24), Vector3(x, 1.28, -2.28), _materials.wall)
		_box(Vector3(0.36, 0.17, 2.35), Vector3(x, 2.71, -2.28), _materials.edge)
		_box(Vector3(0.28, 1.35, 1.65), Vector3(x, 0.59, -0.36), _materials.wall)
		_box(Vector3(0.36, 0.13, 1.73), Vector3(x, 1.33, -0.36), _materials.edge)
		_box(Vector3(0.28, 0.48, 2.15), Vector3(x, 0.17, 1.52), _materials.wall)
		_box(Vector3(0.38, 0.12, 2.20), Vector3(x, 0.47, 1.52), _materials.edge)
		_pillar(Vector3(x, 0, 2.76), 0.73)
		_lantern(Vector3(side * 6.33, 1.74, -2.98))

func _pillar(base: Vector3, height: float) -> void:
	_slab(Vector3(0.58, 0.24, 0.58), base + Vector3(0, 0.05, 0), _materials.base, 0.05)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.15; shaft.bottom_radius = 0.19; shaft.height = maxf(0.10, height - 0.32)
	shaft.radial_segments = 8; shaft.rings = 1
	var object := _mesh(shaft, _materials.dark, base + Vector3(0, height * 0.5, 0))
	object.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_box(Vector3(0.34, 0.095, 0.34), base + Vector3(0, 0.25, 0), _materials.bronze)
	_box(Vector3(0.34, 0.095, 0.34), base + Vector3(0, height - 0.14, 0), _materials.dark_bronze)
	_slab(Vector3(0.56, 0.18, 0.54), base + Vector3(0, height, 0), _materials.edge, 0.035)

func _lantern(at: Vector3) -> void:
	_box(Vector3(0.30, 0.40, 0.23), at, _materials.lantern)
	for y: float in [-0.23, 0.23]: _box(Vector3(0.43, 0.09, 0.34), at + Vector3(0, y, 0), _materials.dark_bronze)
	for x: float in [-0.17, 0.17]: _box(Vector3(0.035, 0.46, 0.27), at + Vector3(x, 0, 0), _materials.dark)
	var light := OmniLight3D.new(); add_child(light); light.position = at + Vector3(0, 0, 0.34)
	light.light_color = Color("efc780"); light.light_energy = 0.45; light.omni_range = 2.8

func _build_grid_overlay() -> void:
	_grid_root = Node3D.new(); _grid_root.name = "TacticalGridInlay"; add_child(_grid_root)
	for team: String in ["player", "enemy"]:
		var material: Material = _materials.grid_player if team == "player" else _materials.grid_enemy
		for row: int in range(3):
			for col: int in range(3):
				var center: Vector3 = _cell_center(team, row, col) + Vector3(0, 0.004, 0)
				for side: float in [-1.0, 1.0]:
					_box(Vector3(CELL_SIZE - 0.12, 0.008, 0.014), center + Vector3(0, 0, side * (CELL_SIZE * 0.5 - 0.07)), material, _grid_root)
					_box(Vector3(0.014, 0.008, CELL_SIZE - 0.12), center + Vector3(side * (CELL_SIZE * 0.5 - 0.07), 0, 0), material, _grid_root)

func _build_hover() -> void:
	_hover_root = Node3D.new(); _hover_root.name = "HoveredCell"; add_child(_hover_root)
	var wash := _solid(Color(0.83, 0.71, 0.40, 0.12))
	wash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane := PlaneMesh.new(); plane.size = Vector2(CELL_SIZE - 0.04, CELL_SIZE - 0.04)
	_mesh(plane, wash, Vector3(0, 0.015, 0), _hover_root)
	var edge := _solid(Color("e4c17c")); edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side: float in [-1.0, 1.0]:
		_box(Vector3(CELL_SIZE - 0.05, 0.012, 0.045), Vector3(0, 0.02, side * (CELL_SIZE * 0.5 - 0.03)), edge, _hover_root)
		_box(Vector3(0.045, 0.012, CELL_SIZE - 0.05), Vector3(side * (CELL_SIZE * 0.5 - 0.03), 0.02, 0), edge, _hover_root)
	_hover_root.hide()

func set_camera_view(index: int) -> void:
	camera_view = clampi(index, 0, 2)
	if camera == null: return
	var positions := [Vector3(0, 9.0, 12.7), Vector3(2.7, 9.0, 13.5), Vector3(0, 6.7, 13.8)]
	var targets := [Vector3(0, 1.35, 0), Vector3(0, 1.12, 0), Vector3(0, 1.25, 0)]
	camera.position = positions[camera_view]
	camera.fov = [43.0, 44.0, 44.0][camera_view]
	camera.look_at(to_global(targets[camera_view]), Vector3.UP)

func set_grid_visible(enabled: bool) -> void:
	grid_visible = enabled
	if is_instance_valid(_grid_root): _grid_root.visible = enabled

func _cell_key(team: String, row: int, col: int) -> String:
	return "%s:%d:%d" % [team, row, col]

func _valid_cell(team: String, row: int, col: int) -> bool:
	return team in ["player", "enemy"] and row >= 0 and row < 3 and col >= 0 and col < 3

func _cell_center(team: String, row: int, col: int) -> Vector3:
	return Vector3((-TEAM_OFFSET if team == "player" else TEAM_OFFSET) + (col - 1) * CELL_PITCH, FLOOR_Y, (row - 1) * CELL_PITCH)

func cell_at_screen(point: Vector2) -> Dictionary:
	if camera == null or not Rect2(Vector2.ZERO, SCREEN).has_point(point): return {}
	var ray_origin: Vector3 = camera.project_ray_origin(point)
	var ray_normal: Vector3 = camera.project_ray_normal(point)
	var floor_plane := Plane(global_basis.y.normalized(), to_global(Vector3(0, FLOOR_Y, 0)))
	var intersection: Variant = floor_plane.intersects_ray(ray_origin, ray_normal)
	if intersection == null: return {}
	var local_point: Vector3 = to_local(intersection)
	for team: String in ["player", "enemy"]:
		for row: int in range(3):
			for col: int in range(3):
				var center: Vector3 = _cell_center(team, row, col)
				if absf(local_point.x - center.x) <= CELL_SIZE * 0.5 and absf(local_point.z - center.z) <= CELL_SIZE * 0.5:
					return {"team": team, "row": row, "col": col, "center": center}
	return {}

func set_actor_cell(id: String, team: String, row: int, col: int) -> bool:
	if not DEFAULT_CELLS.has(id) or not _valid_cell(team, row, col): return false
	if team != ("enemy" if id == "e" else "player"): return false
	for other_id: String in _actor_cells:
		if other_id == id: continue
		var occupied: Dictionary = _actor_cells[other_id]
		if str(occupied.team) == team and int(occupied.row) == row and int(occupied.col) == col: return false
	_actor_cells[id] = {"team": team, "row": row, "col": col}
	actor_positions[id] = _cell_center(team, row, col) + Vector3(0, 0.025, 0)
	if actor_roots.has(id): actor_roots[id].position = actor_positions[id]
	return true

func get_actor_cell(id: String) -> Dictionary:
	if not _actor_cells.has(id): return {}
	var result: Dictionary = _actor_cells[id].duplicate(true)
	result.center = _cell_center(str(result.team), int(result.row), int(result.col))
	return result

func align_combat_teams(units: Array) -> void:
	# Presentation placement follows the model's team; combat never reads a cell.
	for actor in units:
		var id: String = str(actor.id)
		if not _actor_cells.has(id): continue
		var team: String = str(actor.team)
		if team not in ["player", "enemy"]: continue
		if str(_actor_cells[id].team) != team:
			var cell: Dictionary = DEFAULT_CELLS[id].duplicate(true)
			cell.team = team
			_actor_cells[id] = cell
			actor_positions[id] = _cell_center(team, int(cell.row), int(cell.col)) + Vector3(0, 0.025, 0)
		if actor_sprites.has(id):
			actor_sprites[id].flip_h = (team == "enemy") if id in ["p", "e"] else (team == "player")

func apply_layout(layout: Dictionary) -> bool:
	# Validate the whole proposed arrangement first so actors may swap places
	# without an intermediate occupancy conflict or a partially applied layout.
	if layout.size() != DEFAULT_CELLS.size(): return false
	var occupied: Dictionary = {}
	var candidate: Dictionary = {}
	for id: String in DEFAULT_CELLS:
		var value: Variant = layout.get(id)
		if not value is Dictionary or not value.get("team") is String: return false
		for coordinate: String in ["row", "col"]:
			if not (value.get(coordinate) is int or value.get(coordinate) is float): return false
			if not is_finite(float(value[coordinate])) or float(value[coordinate]) != floorf(float(value[coordinate])): return false
		var team: String = str(value.team)
		var row: int = int(value.row); var col: int = int(value.col)
		if not _valid_cell(team, row, col) or team != ("enemy" if id == "e" else "player"): return false
		var key: String = _cell_key(team, row, col)
		if occupied.has(key): return false
		occupied[key] = true
		candidate[id] = {"team": team, "row": row, "col": col}
	_actor_cells = candidate
	for id: String in candidate:
		var cell: Dictionary = candidate[id]
		actor_positions[id] = _cell_center(str(cell.team), int(cell.row), int(cell.col)) + Vector3(0, 0.025, 0)
		if actor_roots.has(id): actor_roots[id].position = actor_positions[id]
	return true

func reset_positions() -> void:
	_actor_cells.clear()
	for id: String in DEFAULT_CELLS:
		var cell: Dictionary = DEFAULT_CELLS[id]
		set_actor_cell(id, str(cell.team), int(cell.row), int(cell.col))

func highlight_cell(cell: Dictionary) -> void:
	if not is_instance_valid(_hover_root): return
	var team: String = str(cell.get("team", ""))
	var row: int = int(cell.get("row", -1)); var col: int = int(cell.get("col", -1))
	_hover_root.visible = _valid_cell(team, row, col)
	if _hover_root.visible: _hover_root.position = _cell_center(team, row, col)

func cell_screen_polygon(team: String, row: int, col: int) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if camera == null or not _valid_cell(team, row, col): return polygon
	var center: Vector3 = _cell_center(team, row, col)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		polygon.append(camera.unproject_position(to_global(center + Vector3(corner.x * CELL_SIZE * 0.5, 0, corner.y * CELL_SIZE * 0.5))))
	return polygon

func actor_feet_screen(id: String) -> Vector2:
	return camera.unproject_position(to_global(actor_positions.get(id, Vector3.ZERO))) if camera != null else Vector2(640, 470)

func actor_head_screen(id: String) -> Vector2:
	var point: Vector3 = actor_positions.get(id, Vector3.ZERO)
	point.y += float(ACTOR_HEIGHTS.get(id, 2.3))
	return camera.unproject_position(to_global(point)) if camera != null else Vector2(640, 330)

func _motion_offset(id: String, offset: Vector2) -> Vector3:
	# Camera-relative motion follows the actual cell, including the side view.
	var feet: Vector2 = actor_feet_screen(id)
	var from_world: Vector3 = _screen_to_floor(feet, to_global(Vector3(0, FLOOR_Y, 0)).y)
	var to_world: Vector3 = _screen_to_floor(feet + Vector2(offset.x, 0), to_global(Vector3(0, FLOOR_Y, 0)).y)
	var result: Vector3 = to_local(to_world) - to_local(from_world)
	var screen_height: float = maxf(1.0, actor_feet_screen(id).y - actor_head_screen(id).y)
	result.y = maxf(0.0, -offset.y * float(ACTOR_HEIGHTS[id]) / screen_height)
	return result
