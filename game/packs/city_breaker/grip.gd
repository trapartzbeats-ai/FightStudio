class_name CBGrip
extends RefCounted
## Held objects sit in the hand the same way in the game and in Fight Studio: a frame built from the hand's own bones every
## frame (never a bone-attachment offset, which differs per model and put Vix's spray can through his wrist). Three kinds:
##   cylinder - can, bottle, bat / sword handle: inside the finger curl, the axis (Y) along the knuckle line pinky -> index
##   sphere   - ball, bomb, orb: cupped in front of the palm
##   block    - box, phone, card: flat on the palm, its long side (Y) along the fingers
## size = the object's extents in metres (cylinder x = diameter, y = length; sphere x = diameter; block x, y, z). Frame axes:
## Y = the object's axis, Z = out of the palm. Pair each kind with its hand pose: data/poses/grip_<kind>_<side>.json.
## Works on 3-finger (Vix) and 4-finger rigs (rig v4 finger bones).

const KINDS := ["cylinder", "sphere", "block"]


static func _bone(skel: Skeleton3D, name: String) -> Vector3:
	var i := skel.find_bone(name)
	if i < 0:
		return Vector3.INF
	return skel.global_transform * skel.get_bone_global_pose(i).origin


## the hand's own frame: wrist -> knuckles (along), pinky -> index (across), and which way the palm faces (palm)
static func hand_axes(skel: Skeleton3D, side: String) -> Dictionary:
	var hand := _bone(skel, "hand" + side)
	var fing := _bone(skel, "fingers" + side)
	var tips := _bone(skel, "tips" + side)
	var idx := _bone(skel, "index" + side)
	var pin := _bone(skel, "pinky" + side)
	if hand == Vector3.INF or fing == Vector3.INF:
		return {}
	var along := (fing - hand)
	var reach := along.length()
	along = along.normalized()
	var across := (idx - pin) if idx != Vector3.INF and pin != Vector3.INF else Vector3.ZERO
	across = across - along * across.dot(along)
	if across.length() < 0.002:
		across = along.cross(Vector3.UP)
	across = across.normalized()
	# the palm, from the hand's handedness (checked on Vix and Carter joints, loop 1): fingers forward + thumb side up ->
	# a right palm faces the body's midline = along x across; a left palm the other way. The fingertip curl is not used:
	# half-open poses gave it the wrong sign (the ball sat on the back of Carter's hand).
	var palm := along.cross(across) * (1.0 if side == "R" else -1.0)
	return {"hand": hand, "fing": fing, "tips": tips if tips != Vector3.INF else fing + along * reach * 0.6,
		"along": along, "across": across, "palm": palm.normalized(), "reach": reach}


## where a held object sits (world transform) for the current pose
static func frame(skel: Skeleton3D, side: String, kind: String, size: Vector3) -> Transform3D:
	var a := hand_axes(skel, side)
	if a.is_empty():
		return Transform3D.IDENTITY
	var along: Vector3 = a["along"]
	var across: Vector3 = a["across"]
	var palm: Vector3 = a["palm"]
	var hand: Vector3 = a["hand"]
	var fing: Vector3 = a["fing"]
	var tips: Vector3 = a["tips"]
	var y := along
	var center := fing
	# the bones run through the middle of the hand: everything sits out past the palm skin (about a fifth of the
	# wrist -> knuckle length, 2.4-2.5 cm on Vix and Carter), or a block vanishes into the palm (review loop 2)
	var pd := (a["reach"] as float) * 0.2
	match kind:
		"cylinder":   # in the tunnel the curled fingers make, under the knuckles
			y = across
			center = fing + palm * (size.x * 0.5 + pd * 0.6) - along * (a["reach"] as float) * 0.12
		"sphere":     # cupped: in front of the palm, between the wrist and the knuckles
			center = hand.lerp(fing, 0.55) + palm * (size.x * 0.5 + pd * 0.5)
		_:            # flat on the palm, the long side along the fingers
			center = hand.lerp(fing, 0.55) + palm * (size.z * 0.5 + pd)
	var z := palm - y * palm.dot(y)
	if z.length() < 0.001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), center)


## a grey proxy of a kind and size (for placement work in Fight Studio and test scenes)
static func proxy_mesh(kind: String, size: Vector3) -> Mesh:
	match kind:
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = size.x * 0.5
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 20
			return c
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x * 0.5
			s.height = size.x
			return s
	var b := BoxMesh.new()
	b.size = size
	return b
