class_name FSAStage
extends Node
## The 3D world every canvas view looks into: the review-sheet look (plum sky, lavender floor with an orange 0.5 m grid, a warm
## horizon), the fighter being animated, onion-skin ghosts, a hidden probe body (motion trails, bakes) and socket props.
## The world lives in a hidden SubViewport; each view only adds a camera and shares world_3d.

const FLOOR_SHADER := """shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wp.xz * 2.0 + 0.5) - 0.5) / fwidth(wp.xz * 2.0);
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	vec2 g1 = abs(fract(wp.xz * 0.5 + 0.5) - 0.5) / fwidth(wp.xz * 0.5);
	float major = 1.0 - clamp(min(g1.x, g1.y), 0.0, 1.0);
	float centre = 1.0 - clamp(min(abs(wp.x), abs(wp.z)) / fwidth(wp.x) * 0.7, 0.0, 1.0);
	vec3 base = mix(vec3(0.33, 0.31, 0.38), vec3(0.95, 0.6, 0.25), max(line * 0.6, major));
	ALBEDO = mix(base, vec3(1.0, 0.78, 0.35), centre * 0.6);
	ROUGHNESS = 0.9;
}"""

var world := World3D.new()
var host := SubViewport.new()
var env := Environment.new()
var sun := DirectionalLight3D.new()
var floor_mi := MeshInstance3D.new()
var model: Node3D
var skel: Skeleton3D
var bones: Array = []
var probe: Node3D
var probe_skel: Skeleton3D
var ghosts: Array = []          # [{node, skel, tint}]
var props_root := Node3D.new()
var height := 1.8
var fighter := ""


func _ready() -> void:
	host.size = Vector2i(4, 4)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.world_3d = world
	host.own_world_3d = false
	add_child(host)
	build_env(env)
	world.environment = env
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
	sun.directional_shadow_max_distance = 30.0
	host.add_child(sun)
	floor_mi.mesh = floor_mesh()
	floor_mi.material_override = floor_material()
	host.add_child(floor_mi)
	host.add_child(props_root)


static func build_env(e: Environment) -> void:
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a2430")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.98, 0.72, 0.42)
	e.fog_density = 0.0035
	e.fog_sky_affect = 0.0
	e.fog_height = 0.6
	e.fog_height_density = 0.08


static var _floor_mesh: PlaneMesh
static var _floor_mat: ShaderMaterial


static func floor_mesh() -> PlaneMesh:
	if _floor_mesh == null:
		_floor_mesh = PlaneMesh.new()
		_floor_mesh.size = Vector2(240, 240)
	return _floor_mesh


static func floor_material() -> ShaderMaterial:
	if _floor_mat == null:
		_floor_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = FLOOR_SHADER
		_floor_mat.shader = sh
	return _floor_mat


## load a fighter model (all AnimationPlayers off: the Animator poses the skeleton itself)
static func instance_fighter(k: String) -> Node3D:
	var path := CBRoster.model_path(k)
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var m := ps.instantiate() as Node3D
	for ap in m.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).active = false
	for at in m.find_children("*", "AnimationTree", true, false):
		(at as AnimationTree).active = false
	return m


static func skeleton_of(m: Node3D) -> Skeleton3D:
	var list := m.find_children("*", "Skeleton3D", true, false)
	return list[0] as Skeleton3D if not list.is_empty() else null


func load_fighter(k: String) -> bool:
	var m := instance_fighter(k)
	if m == null:
		return false
	if model != null:
		model.queue_free()
	if probe != null:
		probe.queue_free()
	fighter = k
	model = m
	host.add_child(model)
	skel = skeleton_of(model)
	bones = []
	for i in skel.get_bone_count():
		bones.append(skel.get_bone_name(i))
	probe = instance_fighter(k)
	probe.visible = false
	host.add_child(probe)
	probe_skel = skeleton_of(probe)
	CBClipLib.apply_pose(skel, {})
	skel.force_update_all_bone_transforms()
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	height = maxf(aabb.end.y, 1.0)
	set_ghost_count(ghosts.size())
	return true


# ---------------------------------------------------------------- onion skin

## how many ghost bodies (onion skin) to keep ready
func set_ghost_count(n: int) -> void:
	for g in ghosts:
		(g["node"] as Node3D).queue_free()
	ghosts.clear()
	if fighter == "":
		return
	for i in n:
		var m := instance_fighter(fighter)
		host.add_child(m)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghosts.append({"node": m, "skel": skeleton_of(m), "mat": null})


func tint_ghost(i: int, c: Color) -> void:
	var g: Dictionary = ghosts[i]
	var mat: StandardMaterial3D = g["mat"]
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.no_depth_test = false
		g["mat"] = mat
		for mi in (g["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
	mat.albedo_color = c


# ---------------------------------------------------------------- props on sockets

## grey proxies with a size ("size": [x, y, z] m) are for placement work; "grip": "cylinder_R" etc. puts a prop in the hand
## by CBGrip (the same frame the game uses) instead of on a socket
const PROP_SHAPES := ["box", "bat", "blade", "ball", "can", "phone", "block", "cylinder", "sphere"]
const PROXY_SIZES := {"block": [0.08, 0.15, 0.02], "cylinder": [0.084, 0.16, 0.084], "sphere": [0.22, 0.22, 0.22]}


## props ride sockets: rebuilt from the clip's prop list
func build_props(props: Array, sockets: Dictionary) -> void:
	for c in props_root.get_children():
		c.queue_free()
	for p in props:
		var pd: Dictionary = p
		var mi := MeshInstance3D.new()
		var shape := str(pd.get("shape", "box"))
		if PROXY_SIZES.has(shape):
			mi.mesh = CBGrip.proxy_mesh(shape, FSAEval._v3(pd.get("size", PROXY_SIZES[shape])))
		else:
			mi.mesh = prop_mesh(shape)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(str(pd.get("color", "#c8c0d0")))
		mat.roughness = 0.6
		mi.material_override = mat
		mi.set_meta("prop", pd)
		props_root.add_child(mi)


static func prop_mesh(shape: String) -> Mesh:
	match shape:
		"bat":
			var c := CylinderMesh.new()
			c.top_radius = 0.035
			c.bottom_radius = 0.018
			c.height = 0.85
			return c
		"blade":
			var b := BoxMesh.new()
			b.size = Vector3(0.05, 0.9, 0.01)
			return b
		"ball":
			var s := SphereMesh.new()
			s.radius = 0.11
			s.height = 0.22
			return s
		"can":
			var c2 := CylinderMesh.new()
			c2.top_radius = 0.033
			c2.bottom_radius = 0.033
			c2.height = 0.12
			return c2
		"phone":
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.075, 0.15, 0.01)
			return b2
	var bx := BoxMesh.new()
	bx.size = Vector3(0.2, 0.2, 0.2)
	return bx


## place props on their sockets for the current pose
func place_props(skel_ref: Skeleton3D, sock_specs: Dictionary) -> void:
	for mi in props_root.get_children():
		var pd: Dictionary = mi.get_meta("prop", {})
		if str(pd.get("grip", "")) != "":   # in the hand by grip kind: cylinder_R, sphere_L, block_R ...
			var gk := str(pd["grip"]).split("_")
			var shape := str(pd.get("shape", "block"))
			var sz := FSAEval._v3(pd.get("size", PROXY_SIZES.get(shape, [0.1, 0.1, 0.1])))
			var gt := CBGrip.frame(skel_ref, gk[1] if gk.size() > 1 else "R", gk[0], sz)
			var gl := Transform3D(Basis.from_euler(FSAEval._v3(pd.get("rot", [0, 0, 0])) * (PI / 180.0)), FSAEval._v3(pd.get("offset", [0, 0, 0])))
			(mi as Node3D).visible = bool(pd.get("visible", true))
			(mi as Node3D).global_transform = gt * gl
			continue
		var sp: Dictionary = sock_specs.get(str(pd.get("socket", "")), {})
		var bi := skel_ref.find_bone(str(sp.get("bone", pd.get("bone", "handR"))))
		if bi < 0:
			(mi as Node3D).visible = false
			continue
		(mi as Node3D).visible = bool(pd.get("visible", true))
		var g := skel_ref.global_transform * skel_ref.get_bone_global_pose(bi)
		var off := CBSockets.offset(skel_ref, bi, sp) if not sp.is_empty() else Vector3.ZERO
		var local := Transform3D(Basis.from_euler(FSAEval._v3(pd.get("rot", [0, 0, 0])) * (PI / 180.0)).scaled(Vector3.ONE * float(pd.get("scale", 1.0))), off + FSAEval._v3(pd.get("offset", [0, 0, 0])))
		(mi as Node3D).global_transform = g * local
