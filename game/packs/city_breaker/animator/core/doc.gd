class_name FSADoc
extends RefCounted
## One clip being animated. It saves in the game's own clip format (data/clips/<name>.json, read by CBClipLib), so a clip made
## here plays in a fight and in the open world with no export step. What only the Animator uses rides along under "studio":
##
##   "studio": {"v": 2, "saved": "2026-10-29T10:12:05", "locks": {bone: "xz"}, "markers": [{f, name}], "props": [...],
##              "layers": [...], "constraints": [...],
##              "base": [...keys...], "baked_on": "vix", "bake_sig": "..."}     <- only when layers / constraints are baked
##
## With live layers or constraints the game "keys" are the BAKED result (a key on every frame) and "base" holds the keys you edit.
## A clip without them saves its keys as they are (sparse, eased), exactly like the old Studio and the gen_*.py scripts.
## If the game keys were changed somewhere else after a bake (old Studio, a script), the Animator takes those keys as the base
## and turns the layers / constraints off, so nothing is silently thrown away.
## "saved" is stamped on every save from the Animator or Fight Studio Desktop: the gen_*.py clip generators leave a clip that
## carries it alone (it is your work now). Delete the clip here (it goes to the trash folder) to hand it back to them.

const KNOWN := ["version", "name", "fps", "frames", "loop", "override", "plant", "ease", "keys", "studio"]
const EASES := ["linear", "in", "out", "inout", "hold", "spline"]
const TAGS := ["key", "breakdown", "extreme"]
const SNAP := 0.0001           # radians / metres written to the file
const MATCH_TOL := 0.002       # two keys are "the same pose" within this (radians)

var name := ""
var fps := 30
var frames := 24
var loop := false
var override := false
var plant := false
var ease := "linear"
var keys: Array = []           # base keys, sorted by frame, one per frame
var layers: Array = []
var constraints: Array = []
var locks: Dictionary = {}     # bone -> channels frozen ("x", "xz", "xyz")
var markers: Array = []        # [{f, name}]
var props: Array = []          # [{id, name, shape, socket, offset, rot, scale, color}]
var extra: Dictionary = {}     # every other field of the clip file, kept as it was (marks, ghosts, note, unbaked_from...)
var baked_on := ""
var outside_edit := false
var saved := ""                # when Fight Studio last saved this clip ("" = never: a generator's or another tool's clip)


static func from_clip(c: Dictionary) -> FSADoc:
	var d := FSADoc.new()
	for k in c:
		if not (str(k) in KNOWN):
			d.extra[k] = (c[k] as Variant)
	d.extra = d.extra.duplicate(true)
	d.name = str(c.get("name", ""))
	d.fps = maxi(1, int(c.get("fps", 30)))
	d.frames = maxi(1, int(c.get("frames", 24)))
	d.loop = bool(c.get("loop", false))
	d.override = bool(c.get("override", false))
	d.plant = bool(c.get("plant", false))
	d.ease = str(c.get("ease", "linear"))
	var st: Dictionary = c.get("studio", {}) if typeof(c.get("studio", {})) == TYPE_DICTIONARY else {}
	var game_keys: Array = (c.get("keys", []) as Array).duplicate(true)
	if st.has("base"):
		if str(st.get("bake_sig", "")) != sig(game_keys):
			d.outside_edit = true
			d.keys = game_keys
		else:
			d.keys = (st["base"] as Array).duplicate(true)
	else:
		d.keys = game_keys
	d.layers = (st.get("layers", []) as Array).duplicate(true)
	d.constraints = (st.get("constraints", []) as Array).duplicate(true)
	d.locks = (st.get("locks", {}) as Dictionary).duplicate(true)
	d.markers = (st.get("markers", []) as Array).duplicate(true)
	d.props = (st.get("props", []) as Array).duplicate(true)
	d.baked_on = str(st.get("baked_on", ""))
	d.saved = str(st.get("saved", ""))
	if d.outside_edit:
		for l in d.layers:
			(l as Dictionary)["mute"] = true
		for cn in d.constraints:
			(cn as Dictionary)["enabled"] = false
	d.normalize()
	return d


static func blank(clip_name: String, n_frames: int = 30, clip_fps: int = 30, looped: bool = false) -> FSADoc:
	return from_clip(CBClipLib.blank(clip_name, n_frames, clip_fps)).with_loop(looped)


func with_loop(on: bool) -> FSADoc:
	loop = on
	return self


## everything, for undo snapshots and the agent API
func to_dict() -> Dictionary:
	return {"name": name, "fps": fps, "frames": frames, "loop": loop, "override": override, "plant": plant, "ease": ease,
		"keys": keys.duplicate(true), "layers": layers.duplicate(true), "constraints": constraints.duplicate(true),
		"locks": locks.duplicate(true), "markers": markers.duplicate(true), "props": props.duplicate(true),
		"extra": extra.duplicate(true), "baked_on": baked_on}


func load_dict(d: Dictionary) -> void:
	name = str(d.get("name", name))
	fps = int(d.get("fps", fps))
	frames = int(d.get("frames", frames))
	loop = bool(d.get("loop", loop))
	override = bool(d.get("override", override))
	plant = bool(d.get("plant", plant))
	ease = str(d.get("ease", ease))
	keys = (d.get("keys", []) as Array).duplicate(true)
	layers = (d.get("layers", []) as Array).duplicate(true)
	constraints = (d.get("constraints", []) as Array).duplicate(true)
	locks = (d.get("locks", {}) as Dictionary).duplicate(true)
	markers = (d.get("markers", []) as Array).duplicate(true)
	props = (d.get("props", []) as Array).duplicate(true)
	extra = (d.get("extra", {}) as Dictionary).duplicate(true)
	baked_on = str(d.get("baked_on", ""))
	normalize()


## the clip file. `baked` = the game keys when layers / constraints are live (FSAEval.bake), else the base keys are written
func to_clip(baked: Array = []) -> Dictionary:
	var c: Dictionary = extra.duplicate(true)
	c["version"] = CBClipLib.FORMAT
	c["name"] = name
	c["fps"] = fps
	c["frames"] = frames
	c["loop"] = loop
	c["override"] = override
	if plant:
		c["plant"] = true
	if ease != "linear":
		c["ease"] = ease
	var st := {"v": 2}
	if saved != "":
		st["saved"] = saved
	if not locks.is_empty():
		st["locks"] = locks.duplicate(true)
	if not markers.is_empty():
		st["markers"] = markers.duplicate(true)
	if not props.is_empty():
		st["props"] = props.duplicate(true)
	if not layers.is_empty():
		st["layers"] = layers.duplicate(true)
	if not constraints.is_empty():
		st["constraints"] = constraints.duplicate(true)
	if baked.is_empty():
		c["keys"] = keys.duplicate(true)
	else:
		c["keys"] = baked
		st["base"] = keys.duplicate(true)
		st["baked_on"] = baked_on
		st["bake_sig"] = sig(baked)
	if st.size() > 1:
		c["studio"] = st
	return c


## true when the game cannot play the base keys as they are (a live layer or constraint changes the motion)
func needs_bake() -> bool:
	for l in layers:
		if not bool((l as Dictionary).get("mute", false)) and float((l as Dictionary).get("weight", 1.0)) > 0.0:
			return true
	for cn in constraints:
		if bool((cn as Dictionary).get("enabled", true)) and float((cn as Dictionary).get("influence", 1.0)) > 0.0:
			return true
	return false


## a signature of a key list that survives a JSON round trip (ints come back as floats). Values are counted in the file's own
## steps (SNAP), so a value can never sit on a rounding edge and flip between saves.
static func sig(ks: Array) -> String:
	var parts: PackedStringArray = []
	for k in ks:
		var kd: Dictionary = k
		var rot: Dictionary = kd.get("rot", {})
		var names := rot.keys()
		names.sort()
		var s := "%d|%d|%d|%d" % [int(kd.get("f", 0)), _q(kd.get("hips_dy", 0.0)), _q(kd.get("hips_dx", 0.0)), _q(kd.get("hips_dz", 0.0))]
		for b in names:
			var r: Array = rot[b]
			s += "|%s:%d,%d,%d" % [b, _q(r[0]), _q(r[1]), _q(r[2])]
		parts.append(s)
	return str(";".join(parts).hash())


static func _q(v: Variant) -> int:
	return int(round(float(v) / SNAP))


## keys sorted, one per frame (a later duplicate wins), frames as ints; ids on layers / constraints / props
func normalize() -> void:
	var by: Dictionary = {}
	for k in keys:
		var kd: Dictionary = k
		kd["f"] = int(round(float(kd.get("f", 0))))
		if not kd.has("rot") or typeof(kd["rot"]) != TYPE_DICTIONARY:
			kd["rot"] = {}
		by[int(kd["f"])] = kd
	var fs := by.keys()
	fs.sort()
	keys = []
	for f in fs:
		keys.append(by[f])
	if keys.is_empty():
		keys.append({"f": 0, "rot": {}, "hips_dy": 0.0})
	for list in [layers, constraints, props]:
		for item in list:
			if str((item as Dictionary).get("id", "")) == "":
				(item as Dictionary)["id"] = new_id(list, "x")
	for l in layers:
		var ld: Dictionary = l
		if ld.has("keys"):
			var lk: Array = ld["keys"]
			for k in lk:
				(k as Dictionary)["f"] = int(round(float((k as Dictionary).get("f", 0))))
			lk.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))


static func new_id(list: Array, prefix: String) -> String:
	var used: Dictionary = {}
	for it in list:
		used[str((it as Dictionary).get("id", ""))] = true
	var i := 1
	while used.has("%s%d" % [prefix, i]):
		i += 1
	return "%s%d" % [prefix, i]


# ---------------------------------------------------------------- keys

func key_frames() -> Array:
	var out: Array = []
	for k in keys:
		out.append(int((k as Dictionary)["f"]))
	return out


func key_index(f: int) -> int:
	for i in keys.size():
		if int((keys[i] as Dictionary)["f"]) == f:
			return i
	return -1


func has_key(f: int) -> bool:
	return key_index(f) >= 0


func key_at(f: int) -> Dictionary:
	var i := key_index(f)
	return keys[i] if i >= 0 else {}


func prev_key(f: float) -> int:
	var best := -1
	for k in keys:
		var kf := int((k as Dictionary)["f"])
		if float(kf) < f - 0.001:
			best = kf
	return best


func next_key(f: float) -> int:
	for k in keys:
		var kf := int((k as Dictionary)["f"])
		if float(kf) > f + 0.001:
			return kf
	return -1


func is_key_locked(f: int) -> bool:
	return bool(key_at(f).get("lock", false))


## the clip as CBClipLib reads it, for pose_at over the base keys
func source() -> Dictionary:
	return {"keys": keys, "loop": loop, "ease": ease, "fps": fps, "frames": frames}


func base_pose(f: float, bones: Array) -> Dictionary:
	return CBClipLib.pose_at(source(), f, bones)


## a pose read from one key: {bone: Vector3, "_dy".. }
static func pose_of_key(k: Dictionary, bones: Array) -> Dictionary:
	var out: Dictionary = {}
	var rot: Dictionary = k.get("rot", {})
	for b in bones:
		var r: Array = rot.get(b, [0.0, 0.0, 0.0])
		out[b] = Vector3(float(r[0]), float(r[1]), float(r[2]))
	out["_dy"] = float(k.get("hips_dy", 0.0))
	out["_dx"] = float(k.get("hips_dx", 0.0))
	out["_dz"] = float(k.get("hips_dz", 0.0))
	return out


## write a pose into a key dict (keeps the key's own fields: ease, tag, link, lock)
static func fill_key(k: Dictionary, pose: Dictionary, bones: Array) -> void:
	var rot: Dictionary = {}
	for b in bones:
		var e: Vector3 = pose.get(b, Vector3.ZERO)
		if e.length_squared() > 1e-10:
			rot[b] = [snappedf(e.x, SNAP), snappedf(e.y, SNAP), snappedf(e.z, SNAP)]
	k["rot"] = rot
	k["hips_dy"] = snappedf(float(pose.get("_dy", 0.0)), SNAP)
	for ax in ["dx", "dz"]:
		var v := snappedf(float(pose.get("_" + ax, 0.0)), SNAP)
		if absf(v) > 0.0 or k.has("hips_" + ax):
			k["hips_" + ax] = v


## set (or update) the key at frame f to a pose. Returns the key's pose before (empty when the key is new)
func write_key(f: int, pose: Dictionary, bones: Array) -> Dictionary:
	var i := key_index(f)
	if i >= 0:
		var k: Dictionary = keys[i]
		var before := pose_of_key(k, bones)
		fill_key(k, pose, bones)
		return before
	var nk := {"f": f}
	fill_key(nk, pose, bones)
	var at := keys.size()
	for j in keys.size():
		if int((keys[j] as Dictionary)["f"]) > f:
			at = j
			break
	keys.insert(at, nk)
	return {}


func delete_key(f: int) -> bool:
	var i := key_index(f)
	if i < 0 or keys.size() <= 1:
		return false
	keys.remove_at(i)
	return true


## move a set of keys by `delta` frames; refuses (false) when one would land on a key that is not moving or below frame 0
func move_keys(fs: Array, delta: int) -> bool:
	if delta == 0:
		return true
	var moving: Dictionary = {}
	for f in fs:
		moving[int(f)] = true
	for k in keys:
		var kf := int((k as Dictionary)["f"])
		if moving.has(kf):
			var nf := kf + delta
			if nf < 0:
				return false
			if has_key(nf) and not moving.has(nf):
				return false
	for k in keys:
		var kd: Dictionary = k
		if moving.has(int(kd["f"])):
			kd["f"] = int(kd["f"]) + delta
	normalize()
	return true


func set_key_field(f: int, field: String, value: Variant) -> bool:
	var i := key_index(f)
	if i < 0:
		return false
	var k: Dictionary = keys[i]
	if value == null or (field == "ease" and str(value) == "") or (field == "lock" and not bool(value)) or (field == "link" and str(value) == ""):
		k.erase(field)
	else:
		k[field] = value
	return true


## the keys that are "the same key" as frame f: the same link group, and (with `matching`) keys holding the same pose
func partners(f: int, bones: Array, matching: bool) -> Array:
	var out: Array = []
	var k := key_at(f)
	if k.is_empty():
		return out
	var link := str(k.get("link", ""))
	var mine := pose_of_key(k, bones)
	for o in keys:
		var od: Dictionary = o
		var of := int(od["f"])
		if of == f:
			continue
		if link != "" and str(od.get("link", "")) == link:
			out.append(of)
		elif matching and poses_equal(mine, pose_of_key(od, bones), bones, MATCH_TOL):
			out.append(of)
	return out


## carry an edit (before -> after at one key) to other keys: each partner gets the same change on the channels that changed.
## Locked keys are skipped. mode "pose": partners are found by pose (see partners()); "bone": per bone, any key holding the same
## value for that bone takes the change. Returns the frames updated.
func propagate(f: int, before: Dictionary, after: Dictionary, bones: Array, mode: String) -> Array:
	var changed: Array = []
	for b in bones:
		if (before.get(b, Vector3.ZERO) as Vector3).distance_to(after.get(b, Vector3.ZERO)) > 1e-6:
			changed.append(b)
	var hips_changed: Array = []
	for ax in ["_dy", "_dx", "_dz"]:
		if absf(float(before.get(ax, 0.0)) - float(after.get(ax, 0.0))) > 1e-6:
			hips_changed.append(ax)
	if changed.is_empty() and hips_changed.is_empty():
		return []
	var link := str(key_at(f).get("link", ""))
	var updated: Array = []
	for o in keys:
		var od: Dictionary = o
		var of := int(od["f"])
		if of == f or bool(od.get("lock", false)):
			continue
		var op := pose_of_key(od, bones)
		var take: Array = []
		var take_hips: Array = []
		if link != "" and str(od.get("link", "")) == link:
			take = changed
			take_hips = hips_changed
		elif mode == "pose" and poses_equal(before, op, bones, MATCH_TOL):
			take = changed
			take_hips = hips_changed
		elif mode == "bone":
			for b in changed:
				if (op.get(b, Vector3.ZERO) as Vector3).distance_to(before.get(b, Vector3.ZERO)) <= MATCH_TOL:
					take.append(b)
			for ax in hips_changed:
				if absf(float(op.get(ax, 0.0)) - float(before.get(ax, 0.0))) <= MATCH_TOL * 0.5:
					take_hips.append(ax)
		if take.is_empty() and take_hips.is_empty():
			continue
		for b in take:
			op[b] = (op.get(b, Vector3.ZERO) as Vector3) + (after.get(b, Vector3.ZERO) as Vector3) - (before.get(b, Vector3.ZERO) as Vector3)
		for ax in take_hips:
			op[ax] = float(op.get(ax, 0.0)) + float(after.get(ax, 0.0)) - float(before.get(ax, 0.0))
		fill_key(od, op, bones)
		updated.append(of)
	return updated


static func poses_equal(a: Dictionary, b: Dictionary, bones: Array, tol: float) -> bool:
	for bn in bones:
		if (a.get(bn, Vector3.ZERO) as Vector3).distance_to(b.get(bn, Vector3.ZERO)) > tol:
			return false
	for ax in ["_dy", "_dx", "_dz"]:
		if absf(float(a.get(ax, 0.0)) - float(b.get(ax, 0.0))) > tol * 0.5:
			return false
	return true


## link keys into one group (they become instances of one pose: the first frame's pose is copied to the others)
func link_keys(fs: Array, bones: Array, copy_pose: bool = true) -> String:
	if fs.size() < 2:
		return ""
	var used: Dictionary = {}
	for k in keys:
		used[str((k as Dictionary).get("link", ""))] = true
	var n := 1
	while used.has("L%d" % n):
		n += 1
	var id := "L%d" % n
	var src := key_at(int(fs[0]))
	var p := pose_of_key(src, bones)
	for f in fs:
		var k := key_at(int(f))
		if k.is_empty():
			continue
		k["link"] = id
		if copy_pose and int(f) != int(fs[0]) and not bool(k.get("lock", false)):
			fill_key(k, p, bones)
	return id


func unlink_keys(fs: Array) -> void:
	for f in fs:
		var k := key_at(int(f))
		k.erase("link")


# ---------------------------------------------------------------- frames

## push every key at or after `at` later by n frames (and the clip gets n frames longer)
func insert_frames(at: int, n: int) -> void:
	if n <= 0:
		return
	for k in keys:
		if int((k as Dictionary)["f"]) >= at:
			(k as Dictionary)["f"] = int((k as Dictionary)["f"]) + n
	_shift_ranges(at, n)
	frames += n


## remove frames [at, at + n): keys inside are dropped, later keys move up
func delete_frames(at: int, n: int) -> void:
	if n <= 0:
		return
	var out: Array = []
	for k in keys:
		var kf := int((k as Dictionary)["f"])
		if kf >= at and kf < at + n:
			continue
		if kf >= at + n:
			(k as Dictionary)["f"] = kf - n
		out.append(k)
	keys = out
	_shift_ranges(at + n, -n)
	frames = maxi(1, frames - n)
	normalize()


func _shift_ranges(at: int, n: int) -> void:
	for m in markers:
		if int((m as Dictionary).get("f", 0)) >= at:
			(m as Dictionary)["f"] = maxi(0, int((m as Dictionary)["f"]) + n)
	for cn in constraints:
		var c: Dictionary = cn
		for fld in ["start", "end", "pin_frame"]:
			if c.has(fld) and int(c[fld]) >= at:
				c[fld] = maxi(0, int(c[fld]) + n)
	for l in layers:
		var ld: Dictionary = l
		for fld in ["start", "end"]:
			if ld.has(fld) and int(ld[fld]) >= at:
				ld[fld] = maxi(0, int(ld[fld]) + n)
	var marks: Dictionary = extra.get("marks", {})
	for mk in marks:
		if float(marks[mk]) >= float(at):
			marks[mk] = maxf(0.0, float(marks[mk]) + n)


## stretch time by `factor` about `pivot` (only the keys in `fs` when given); colliding keys merge (the later one wins)
func scale_time(factor: float, pivot: int = 0, fs: Array = []) -> void:
	if factor <= 0.0:
		return
	var only: Dictionary = {}
	for f in fs:
		only[int(f)] = true
	for k in keys:
		var kd: Dictionary = k
		var kf := int(kd["f"])
		if only.is_empty() or only.has(kf):
			kd["f"] = maxi(0, int(round(pivot + (kf - pivot) * factor)))
	if only.is_empty():
		frames = maxi(1, int(round(frames * factor)))
		for m in markers:
			(m as Dictionary)["f"] = int(round(pivot + (int((m as Dictionary)["f"]) - pivot) * factor))
		var marks: Dictionary = extra.get("marks", {})
		for mk in marks:
			marks[mk] = pivot + (float(marks[mk]) - pivot) * factor
	normalize()


## play a stretch backwards: keys in [a, b] mirror in time
func reverse(a: int, b: int) -> void:
	for k in keys:
		var kd: Dictionary = k
		var kf := int(kd["f"])
		if kf >= a and kf <= b:
			kd["f"] = a + b - kf
	normalize()


# ---------------------------------------------------------------- locks

func lock_channels(bone: String) -> String:
	return str(locks.get(bone, ""))


func is_locked(bone: String, axis: int = -1) -> bool:
	var ch := lock_channels(bone)
	if axis < 0:
		return ch.length() >= 3
	return ["x", "y", "z"][axis] in ch


func set_lock(bone: String, channels: String) -> void:
	var clean := ""
	for c in ["x", "y", "z"]:
		if c in channels:
			clean += c
	if clean == "":
		locks.erase(bone)
	else:
		locks[bone] = clean


## write one bone into a pose, keeping its locked channels and the rig limits
func guard(bone: String, old: Vector3, want: Vector3, use_limits: bool = true) -> Vector3:
	var out := want
	for i in 3:
		if is_locked(bone, i):
			out[i] = old[i]
	if use_limits:
		out = FSARig.clamp_limits(bone, out)
	return out


# ---------------------------------------------------------------- layers / constraints / markers

func layer_by_id(id: String) -> Dictionary:
	for l in layers:
		if str((l as Dictionary).get("id", "")) == id:
			return l
	return {}


func constraint_by_id(id: String) -> Dictionary:
	for c in constraints:
		if str((c as Dictionary).get("id", "")) == id:
			return c
	return {}


func add_layer(def: Dictionary) -> Dictionary:
	var l := {"name": "Layer %d" % (layers.size() + 1), "mode": "add", "weight": 1.0, "mute": false, "solo": false, "mask": [],
		"source": "keys", "keys": [], "clip": "", "offset": 0, "speed": 1.0, "cycle": true, "start": 0, "end": -1, "fade_in": 0, "fade_out": 0}
	for k in def:
		l[k] = def[k]
	l["id"] = new_id(layers, "lyr")
	layers.append(l)
	return l


func add_constraint(def: Dictionary) -> Dictionary:
	var c := {"type": "ik", "name": "", "enabled": true, "influence": 1.0, "start": 0, "end": -1, "blend": 0}
	for k in def:
		c[k] = def[k]
	c["id"] = new_id(constraints, "con")
	if str(c["name"]) == "":
		c["name"] = "%s %s" % [str(c["type"]).to_upper(), str(c.get("bone", c.get("limb", "")))]
	constraints.append(c)
	return c


func remove_by_id(list: Array, id: String) -> bool:
	for i in list.size():
		if str((list[i] as Dictionary).get("id", "")) == id:
			list.remove_at(i)
			return true
	return false


func add_marker(f: int, label: String) -> void:
	markers.append({"f": f, "name": label})
	markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))
