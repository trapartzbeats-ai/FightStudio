class_name CBWrapPose
extends RefCounted
## Shared by the wrap tools: a fighter model at match height, posed on a clip frame the way CBAnim poses it in a match
## (planted clips stand the lower foot on the floor at y = 0 and lay planted feet flat).

const WRAPS := "res://game/packs/city_breaker/data/wraps/%s.collide.json"
const MOVES := "res://game/packs/city_breaker/data/moves/%s.json"
const RIG := "res://game/packs/city_breaker/data/animator_rig.json"

var key := ""
var model: Node3D
var skel: Skeleton3D
var body: RmtWrapBody
var bones: Array = []
var ankle := 0.0
var feet: Array = []   # foot piece ids
var solver: RmtBodySolve
var last_solve := {}
var last_pose := {}    # the clip's own Euler pose on the last frame posed


## loads the fighter under `parent`, scaled to its match height, with its Collision Wrap
func _init(p_key: String, parent: Node) -> void:
	key = p_key
	model = (load(CBRoster.model_path(key)) as PackedScene).instantiate() as Node3D
	parent.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skel.reset_bone_poses()
	var moves: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOVES % key))
	model.scale = Vector3.ONE * (float(moves.get("height_m", 2.0)) / mesh_height(model))
	body = RmtWrapBody.new(RmtWrapBody.load_wrap(WRAPS % key), skel)
	for i in skel.get_bone_count():
		bones.append(skel.get_bone_name(i))
	CBClipLib.apply_pose(skel, {})
	skel.force_update_all_bone_transforms()
	ankle = INF
	for b in ["footL", "footR"]:
		var bi := skel.find_bone(b)
		if bi >= 0:
			ankle = minf(ankle, (skel.global_transform * skel.get_bone_global_pose(bi)).origin.y)
	for p in body.pieces:
		if str(p["id"]).begins_with("foot"):
			feet.append(p["id"])
	solver = CBWraps.make_solver(skel, key, model)


## the model's own height at scale 1 (as CBFighter measures it)
static func mesh_height(m: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		var t := Transform3D.IDENTITY
		var cur: Node = mm
		while cur != null and cur != m:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var bb := t * mm.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	return maxf(aabb.size.y, 0.5)


## pose a clip frame; true when the clip is planted (the floor at y = 0 counts). `solve` runs the Body Solve after it, as a
## match would (call solver.reset() at the start of a clip)
func pose(c: Dictionary, f: float, solve: bool = false) -> bool:
	model.position = Vector3.ZERO
	last_pose = CBClipLib.pose_at(c, f, bones)
	CBClipLib.apply_pose(skel, last_pose)
	skel.force_update_all_bone_transforms()
	var plant := bool(c.get("plant", false))
	if plant:
		model.position.y = CBAnim.plant(skel, 0.0, ankle)
		CBAnim.flat_feet(skel)
		skel.force_update_all_bone_transforms()
	if solve:
		last_solve = solver.solve(0.0 if plant else NAN)
	return plant


## the clashes on the current pose: {"self": [...RmtWrapBody.clashes], "floor": [{i, excess}]}
func clashes(tol: float, planted: bool) -> Dictionary:
	var caps := body.capsules()
	var fl: Array = []
	if planted:
		fl = body.under_floor(0.0, tol, feet, caps)
		for u in body.under_floor(0.0, tol + 0.02, [], caps):   # feet may sink a little (soles)
			if str(body.pieces[u["i"]]["id"]) in feet:
				fl.append(u)
	return {"self": body.clashes(tol, caps), "floor": fl, "caps": caps}
