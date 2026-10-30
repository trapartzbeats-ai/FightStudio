class_name FSAApi
extends RefCounted
## The agent API: every method an agent (through the MCP server, mcp/fight_studio_mcp.py) can call. Same code path as the UI,
## so edits are live, undoable and logged as [agent] in History.
##
## Units: bone rotations in DEGREES ([x, y, z] on the bone's own axes on top of its rest; see `rig` for what each axis does),
## positions and the hips shift in METRES, world space with the fighter at the origin facing +Z (R bones on +X, L on -X).

const METHODS := {
	"ping": "-> 'pong'",
	"state": "-> what is open: fighter, clip, frame, length, fps, loop, keys, layers, constraints, selection, tool, unsaved",
	"rig": "-> bones (parent, group, side, mirror twin, what each axis does, limits), limbs for IK, masks, controls, sockets, rules",
	"list_fighters": "-> fighter keys",
	"set_fighter": "{fighter}",
	"list_clips": "{filter?} -> clip names (data/clips)",
	"open_clip": "{name, discard?: bool} (refuses with unsaved changes unless discard)",
	"import_motion": "{path (Mixamo FBX / GLB / glTF on disk), name?, anim?, in_place=true, limits=true, fingers=true, plant='auto', loop='auto', discard?: bool} -> report; opens the clip unsaved",
	"new_clip": "{name, frames=30, fps=30, loop=false, from_pose=true}",
	"save": "{} -> writes data/clips/<name>.json (layers + constraints baked for the game)",
	"save_as": "{name}",
	"get_clip": "{} -> settings + keys (rotations in degrees) + layers + constraints + locks + markers",
	"set_clip": "{frames?, fps?, loop?, plant?, override?, ease?, note?, marks?: {hit, clear}}",
	"set_frame": "{frame}",
	"get_pose": "{frame? (number or list), bones?: [names], final?: true (after constraints), world?: false (joint positions)} -> degrees / metres",
	"set_pose": "{frame?, bones: {name: [x,y,z] deg}, hips?: {dx,dy,dz} m, mode?: 'set'|'add', key?: true, mirror?: false} -> poses (and keys) at the frame",
	"ik_pose": "{bone, target: [x,y,z] m, frame?, key?: true, keep_end?: true} -> pull a hand / foot (limb bends) or any joint (parents bend) to a world point",
	"key": "{frame?, ease?, tag?} -> key the pose at the frame (the 'same key' elsewhere follows per propagate)",
	"list_keys": "{} -> [{f, ease, tag, link, lock, bones}]",
	"delete_keys": "{frames: [..]}",
	"move_keys": "{frames: [..], delta}",
	"set_keys": "{frames: [..], ease?, tag?: ''|'breakdown'|'extreme', lock?}",
	"set_key_values": "{frame, bones: {name: [x,y,z] deg}, hips?: {dx,dy,dz}} -> edit one key in place",
	"link_keys": "{frames: [..]} -> one pose shared by these frames (edit one, all follow)",
	"unlink_keys": "{frames: [..]}",
	"same_keys": "{frame} -> frames that are the same key (linked or the same pose)",
	"set_propagate": "{mode: off|linked|pose|bone}",
	"insert_frames": "{at, count}",
	"delete_frames": "{at, count}",
	"scale_time": "{factor, frames?: [..]}",
	"reverse": "{from, to}",
	"close_loop": "{} -> last frame = first key, linked",
	"mirror_pose": "{mode: l2r|r2l|flip, frame?, key?: true}",
	"reset_bones": "{bones: [..] ('hips_move' = the body shift), frame?, key?: true}",
	"breakdown": "{t: 0..1, frame?, key?: true} -> in-between of the keys around the frame",
	"list_poses": "{} -> pose library names",
	"save_pose": "{name, bones?: [..]}",
	"apply_pose": "{name, frame?, bones?: [..], weight?: 1, mirror?: false, key?: true}",
	"list_controls": "{frame?} -> [{name, value, min, max, drives}]",
	"set_control": "{name, value, frame?, key?: true}",
	"add_control": "{name, min?, max?, drives: [[bone, 'x'|'y'|'z'|'dx'|'dy'|'dz', amount (deg, or m for moves)]]}",
	"list_layers": "{}",
	"add_layer": "{name?, source: keys|clip, clip?, mode: add|add_delta|override, weight?, mask?: [bones / '@Group'] or preset name, start?, end?, fade_in?, fade_out?, offset?, speed?, cycle?}",
	"set_layer": "{id, ...same fields}",
	"merge": "{base? (clip to open as the base), discard?, clips: [{clip, parts?: Head|Spine|Arm L|Arm R|Hands|Hips|Legs|Tail (default arms + hands), start?, blend_in=10, blend_out=10, weight=1, cycle=false}], bake=false, name?} -> {layers, baked?}",
	"merge_add": "{clip, parts?, start? (-1 = current frame), blend_in=10, blend_out=10, weight=1, cycle=false} -> the layer",
	"merge_set": "{id, parts?, start?, blend_in?, blend_out?, weight?, cycle?, speed?, mute?} -> the layer",
	"merge_bake": "{name} -> {name, frames, keys, base}: ONE new clip from the base + clips on top (opens unsaved)",
	"show_panel": "{title}: bring a panel to the front (Merge, Adjust, Layers, Dope Sheet, Blend Lab, Clips, ...)",
	"adjust": "{bone, x=0, y=0, z=0 (degrees, the TOTAL turn of this adjustment), scope: all|frame|range, frame? (scope frame; default current), from?, to? (scope range), ease=6, mirror=false} -> {layers}; all zero removes it",
	"adjust_restore": "{id? | bone?} (neither = all adjustments) -> {restored}",
	"adjustments": "{} -> [{id, bone, scope, start, end, turn (degrees), text}]",
	"fill": "{from?, to? (default: the keys around the current frame), engine: shape|library, timing: smooth|even|strike|settle, flow=0.6, overlap=0.3, anticipate=0, overshoot=0 (0..1), feet=true (planted feet held / stepped), air=0 (cm jump arc), step=0 (key every N frames, 0 = auto), pick=0 (library match)} -> {id, from, to, keys, engine, match, feet, settings}: the frames between two keys made for you; the same span again replaces its fill and keeps the settings you leave out",
	"fill_matches": "{from?, to?, n=5} -> [{clip, from, to, mirror, cost, score (0..100), frames (how long that change took there)}]: library stretches that join the two poses",
	"fill_remove": "{id? (none = every fill)} -> {removed (keys)}",
	"fills": "{} -> [{id, a, b, settings, match?, text}]",
	"feet": "{planted? (sets the clip's plant flag first), step=1} -> {planted, soles {footL: {tilt0, ankle_cm}}, counts {flat, pivot, limit, sink, air}, frames [{f, footL: {state, low_cm, tilt}, footR}]}: how the feet stand in the match, per frame",
	"remove_layer": "{id}",
	"set_active_layer": "{id ('' = base)} -> where keys go",
	"list_constraints": "{}",
	"add_constraint": "{type: ik|pin|aim|limit|copy_rot|floor, ...} ik {limb: armL|armR|legL|legR, target: {pos:[x,y,z]} | {keys:[{f,pos}]} | {bone, offset}, keep_end}; pin {bone, what: both|position|rotation, pin_frame}; aim {bone, axis, target}; limit {bone, min_deg, max_deg}; copy_rot {bone, source, mix, mirror}; floor {bones, mode: floor|plant, height}; all: start, end (-1), influence, blend",
	"set_constraint": "{id, ...fields}",
	"remove_constraint": "{id}",
	"freeze": "{bone, from?, to?: -1, what?: both} -> pin a bone in the world",
	"bake_to_keys": "{} -> layers + constraints become keys (and switch off)",
	"lock": "{bones: [..], channels?: 'xyz'} -> frozen channels no tool can change",
	"unlock": "{bones: [..]}",
	"list_sockets": "{} -> {name: {bone, world: [x,y,z]}}",
	"add_marker": "{frame, name}",
	"list_props": "{} -> the clip's props [{id, name, shape, socket | grip, size?, offset, rot, scale, color}]",
	"add_prop": "{shape: block|cylinder|sphere|box|bat|blade|ball|can|phone, grip?: cylinder_R|sphere_L|block_R.., socket?, size?: [x,y,z] m, offset?, rot? deg, color?, name?} -> id (clip only, never in the game)",
	"set_prop": "{id, ...same fields}",
	"remove_prop": "{id} (or {all: true})",
	"set_view": "{layout?: 1|2|3|4|strip|4+strip, index?, preset?: Persp|Front|Three-Q|Side L|Side R|Back|Top|Follow, ortho?, onion?, tool?, bone?, focus_bone?, dist? m, yaw? deg, pitch? deg}",
	"screenshot": "{target: window|view|sheet, width?, height?, cols?, path?} -> {path} PNG (sheet = front/three-q/side/back x time)",
	"checks": "{} -> knee / limit / loop seam / foot slide / unkeyed findings",
	"transition_clip": "{clip_b, at, blend, name} -> a new clip: this one, then clip_b crossfading in",
	"undo": "{}",
	"redo": "{}",
	"history": "{} -> recent steps",
	"say": "{message} -> show a message to the user in the status bar",
	"bake_glb": "{} -> Animato bakes every saved clip into this fighter's GLB (Blender, background)",
}

var app: FSAApp


func call_method(m: String, p: Dictionary) -> Dictionary:
	if not METHODS.has(m):
		return _log(m, p, {"ok": false, "error": "unknown method %s (GET /methods lists them)" % m})
	var r: Variant = await _dispatch(m, p)
	var out: Dictionary
	if typeof(r) == TYPE_DICTIONARY and (r as Dictionary).has("error") and not (r as Dictionary).has("ok"):
		out = {"ok": false, "error": (r as Dictionary)["error"]}
	else:
		out = {"ok": true, "result": r}
	return _log(m, p, out)


func _log(m: String, p: Dictionary, out: Dictionary) -> Dictionary:
	var s := JSON.stringify(p)
	app.api_log.append({"time": Time.get_time_string_from_system(), "method": m, "summary": s.substr(0, 140) + ("..." if s.length() > 140 else ""), "ok": bool(out.get("ok", false))})
	if app.api_log.size() > 2000:
		app.api_log = app.api_log.slice(1000)
	if not bool(out.get("ok", false)):
		app.say("Agent call %s failed: %s" % [m, out.get("error", "")], "warn")
	app.changed.emit("api")
	return out


static func _deg3(v: Vector3) -> Array:
	return [snappedf(rad_to_deg(v.x), 0.01), snappedf(rad_to_deg(v.y), 0.01), snappedf(rad_to_deg(v.z), 0.01)]


static func _rad3(a: Variant) -> Vector3:
	var v := FSAEval._v3(a)
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))


static func _m3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _goto(p: Dictionary) -> void:
	if p.has("frame") and typeof(p["frame"]) != TYPE_ARRAY:
		app.playing = false
		app.set_frame(float(p["frame"]))


func _key_of(k: Dictionary) -> Dictionary:
	var out := k.duplicate(true)
	var rot: Dictionary = {}
	for b in (k.get("rot", {}) as Dictionary):
		rot[b] = _deg3(FSAEval._v3(k["rot"][b]))
	out["rot"] = rot
	return out


func _dispatch(m: String, p: Dictionary) -> Variant:
	var who := "agent"
	match m:
		"ping":
			return "pong"
		"state":
			return {"fighter": app.fighter, "clip": app.doc.name, "frame": app.frame, "frames": app.doc.frames, "fps": app.doc.fps, "loop": app.doc.loop,
				"plant": app.doc.plant, "keys": app.doc.key_frames(), "layers": app.doc.layers.size(), "constraints": app.doc.constraints.size(),
				"unsaved": app.history.dirty(), "new": app.is_new, "selected_bone": app.sel_bone, "selected_bones": app.sel_bones, "tool": app.tool,
				"active_layer": app.active_layer, "propagate": app.propagate, "autokey": app.autokey, "layout": app.canvas.layout,
				"pending_unkeyed_edit": not app.pending.is_empty(), "outside_edit": app.doc.outside_edit}
		"rig":
			return _rig()
		"list_fighters":
			return CBRoster.keys()
		"set_fighter":
			return {"ok": app.set_fighter(str(p.get("fighter", "")))} if str(p.get("fighter", "")) in CBRoster.keys() else {"error": "fighters: " + ", ".join(CBRoster.keys())}
		"list_clips":
			return app.list_clips(str(p.get("filter", "")))
		"import_motion":
			if app.history.dirty() and not bool(p.get("discard", false)):
				return {"error": "the open clip %s has unsaved changes: save first, or pass discard: true" % app.doc.name}
			var opts: Dictionary = p.duplicate()
			opts.erase("path")
			opts.erase("discard")
			return app.import_motion(str(p.get("path", "")), opts, "agent")
		"open_clip":
			if app.history.dirty() and not bool(p.get("discard", false)):
				return {"error": "the open clip %s has unsaved changes: save first, or pass discard: true" % app.doc.name}
			return {"opened": app.doc.name} if app.open_clip(str(p.get("name", "")), true) else {"error": "no clip named %s" % p.get("name", "")}
		"new_clip":
			if app.history.dirty() and not bool(p.get("discard", false)):
				return {"error": "the open clip %s has unsaved changes: save first, or pass discard: true" % app.doc.name}
			if FileAccess.file_exists(CBClipLib.DIR + str(p.get("name", "")) + ".json") and not bool(p.get("overwrite", false)):
				return {"error": "a clip named %s exists (open it, or pass overwrite: true)" % p.get("name", "")}
			if not app.new_clip(str(p.get("name", "")), int(p.get("frames", 30)), int(p.get("fps", 30)), bool(p.get("loop", false)), bool(p.get("from_pose", true)), who):
				return {"error": "bad name (letters, digits, _ and -)"}
			return {"created": app.doc.name, "frames": app.doc.frames, "fps": app.doc.fps}
		"save":
			return app.save(who)
		"save_as":
			return app.save_as(str(p.get("name", "")), who)
		"get_clip":
			var d := app.doc.to_dict()
			d["keys"] = app.doc.keys.map(func(k: Dictionary) -> Dictionary: return _key_of(k))
			d["saved"] = app.doc.saved   # "" = never saved in Fight Studio (a generator may rewrite it)
			d["units"] = "rot in degrees; hips_* in metres; layer keys / constraint limits in radians as stored"
			return d
		"set_clip":
			for k in ["frames", "fps", "loop", "plant", "override", "ease", "note", "marks"]:
				if p.has(k):
					app.set_clip_prop(k, p[k], who)
			return {"frames": app.doc.frames, "fps": app.doc.fps, "loop": app.doc.loop}
		"set_frame":
			_goto(p)
			return {"frame": app.frame}
		"get_pose":
			return _get_pose(p)
		"set_pose":
			return _set_pose(p, who)
		"ik_pose":
			return _ik_pose(p, who)
		"key":
			_goto(p)
			var r := app.key_now("Key f%d" % int(round(app.frame)), who)
			if p.has("ease") or p.has("tag"):
				for fld in ["ease", "tag"]:
					if p.has(fld):
						app.set_keys_field([int(round(app.frame))], fld, p[fld], who)
			return r
		"list_keys":
			var out: Array = []
			for k in app.doc.keys:
				var kd: Dictionary = k
				out.append({"f": kd["f"], "ease": kd.get("ease", app.doc.ease), "tag": kd.get("tag", "key"), "link": kd.get("link", ""), "lock": kd.get("lock", false),
					"bones": (kd.get("rot", {}) as Dictionary).keys()})
			return out
		"delete_keys":
			app.delete_keys((p.get("frames", []) as Array).map(func(x: Variant) -> int: return int(x)), who)
			return {"keys": app.doc.key_frames()}
		"move_keys":
			var ok := app.move_keys((p.get("frames", []) as Array).map(func(x: Variant) -> int: return int(x)), int(p.get("delta", 0)), who)
			return {"keys": app.doc.key_frames()} if ok else {"error": "keys cannot land on other keys, before frame 0, or move while locked"}
		"set_keys":
			var fs: Array = (p.get("frames", []) as Array).map(func(x: Variant) -> int: return int(x))
			for fld in ["ease", "tag", "lock"]:
				if p.has(fld):
					app.set_keys_field(fs, fld, p[fld], who)
			return {"ok": true}
		"set_key_values":
			return _set_key_values(p, who)
		"link_keys":
			app.link_keys((p.get("frames", []) as Array).map(func(x: Variant) -> int: return int(x)), who)
			return {"keys": app.doc.keys.map(func(k: Dictionary) -> Array: return [k["f"], k.get("link", "")])}
		"unlink_keys":
			app.unlink_keys((p.get("frames", []) as Array).map(func(x: Variant) -> int: return int(x)), who)
			return {"ok": true}
		"same_keys":
			return app.doc.partners(int(p.get("frame", 0)), app.bones, true)
		"set_propagate":
			if not (str(p.get("mode", "")) in ["off", "linked", "pose", "bone"]):
				return {"error": "mode: off | linked | pose | bone"}
			app.propagate = str(p["mode"])
			app.changed.emit("tool")
			return {"propagate": app.propagate}
		"insert_frames":
			app.insert_frames(int(p.get("at", 0)), int(p.get("count", 1)), who)
			return {"frames": app.doc.frames, "keys": app.doc.key_frames()}
		"delete_frames":
			app.delete_frames(int(p.get("at", 0)), int(p.get("count", 1)), who)
			return {"frames": app.doc.frames, "keys": app.doc.key_frames()}
		"scale_time":
			app.scale_time(float(p.get("factor", 1.0)), (p.get("frames", []) as Array).map(func(x: Variant) -> int: return int(x)), who)
			return {"frames": app.doc.frames, "keys": app.doc.key_frames()}
		"reverse":
			app.reverse_range(int(p.get("from", 0)), int(p.get("to", app.doc.frames)), who)
			return {"keys": app.doc.key_frames()}
		"close_loop":
			app.close_loop(who)
			return {"keys": app.doc.key_frames()}
		"mirror_pose":
			_goto(p)
			app.pose_mirror(str(p.get("mode", "l2r")), who)
			return _maybe_key(p, who)
		"reset_bones":
			_goto(p)
			app.reset_bones(p.get("bones", []) as Array, who)
			return _maybe_key(p, who)
		"breakdown":
			_goto(p)
			app.breakdown(float(p.get("t", 0.5)), who)
			return _maybe_key(p, who)
		"list_poses":
			return app.list_poses()
		"save_pose":
			var prev: Array = app.sel_bones
			if p.has("bones"):
				app.sel_bones = p["bones"]
			var ok2 := app.save_library_pose(str(p.get("name", "")), p.has("bones"))
			app.sel_bones = prev
			return {"saved": ok2}
		"apply_pose":
			_goto(p)
			var prev2: Array = app.sel_bones
			if p.has("bones"):
				app.sel_bones = p["bones"]
			var ok3 := app.apply_library_pose(str(p.get("name", "")), p.has("bones"), float(p.get("weight", 1.0)), bool(p.get("mirror", false)), who)
			app.sel_bones = prev2
			if not ok3:
				return {"error": "no pose named %s" % p.get("name", "")}
			return _maybe_key(p, who)
		"list_controls":
			_goto(p)
			var pose := app.editable_pose()
			return FSARig.controls().map(func(c: Dictionary) -> Dictionary: return {"name": c["name"], "value": snappedf(FSARig.control_value(c, pose), 0.001), "min": c.get("min", -1), "max": c.get("max", 1), "drives": c["drives"]})
		"set_control":
			_goto(p)
			for c in FSARig.controls():
				if str((c as Dictionary)["name"]) == str(p.get("name", "")):
					app.set_control(c, float(p.get("value", 0.0)), who)
					return _maybe_key(p, who)
			return {"error": "no control named %s" % p.get("name", "")}
		"add_control":
			var drives: Array = []
			for d in (p.get("drives", []) as Array):
				var ax := str(d[1])
				var idx := ["x", "y", "z"].find(ax)
				drives.append([str(d[0]), idx if idx >= 0 else ax, deg_to_rad(float(d[2])) if idx >= 0 else float(d[2])])
			FSARig.controls().append({"name": str(p.get("name", "control")), "min": float(p.get("min", -1.0)), "max": float(p.get("max", 1.0)), "drives": drives})
			FSARig.save_data()
			app.changed.emit("controls")
			return {"controls": FSARig.controls().size()}
		"list_layers":
			return app.doc.layers
		"add_layer":
			var def := p.duplicate(true)
			if typeof(def.get("mask", null)) == TYPE_STRING:
				def["mask"] = FSARig.MASKS.get(str(def["mask"]), [])
			return app.add_layer(def, who)
		"merge":
			if p.has("base") and str(p["base"]) != "" and str(p["base"]) != app.doc.name:
				if app.history.dirty() and not bool(p.get("discard", false)):
					return {"error": "the open clip %s has unsaved changes: save first, or pass discard: true" % app.doc.name}
				if not app.open_clip(str(p["base"]), true):
					return {"error": "no clip named %s" % p["base"]}
			var made: Array = []
			for c in (p.get("clips", []) as Array):
				var cd: Dictionary = c
				var l := app.merge_add(str(cd.get("clip", "")), cd.get("parts", FSAMerge.DEFAULT_PARTS), int(cd.get("start", 0)), int(cd.get("blend_in", 10)),
					int(cd.get("blend_out", 10)), float(cd.get("weight", 1.0)), bool(cd.get("cycle", false)), who)
				if l.is_empty():
					return {"error": "no clip named %s" % cd.get("clip", ""), "layers": made}
				made.append(l)
			var out := {"base": app.doc.name, "layers": made, "frames": FSAMerge.length(app.doc)}
			if bool(p.get("bake", false)):
				out["baked"] = app.merge_bake(str(p.get("name", app.doc.name + "_merged")), who)
			return out
		"merge_add":
			return app.merge_add(str(p.get("clip", "")), p.get("parts", FSAMerge.DEFAULT_PARTS), int(p.get("start", -1)), int(p.get("blend_in", 10)),
				int(p.get("blend_out", 10)), float(p.get("weight", 1.0)), bool(p.get("cycle", false)), who)
		"merge_set":
			var mp := p.duplicate(true)
			mp.erase("id")
			app.merge_set(str(p.get("id", "")), mp, who)
			return app.doc.layer_by_id(str(p.get("id", "")))
		"merge_bake":
			return app.merge_bake(str(p.get("name", app.doc.name + "_merged")), who)
		"adjust":
			var t := Vector3(deg_to_rad(float(p.get("x", 0.0))), deg_to_rad(float(p.get("y", 0.0))), deg_to_rad(float(p.get("z", 0.0))))
			var ls := app.adjust_part(str(p.get("bone", "")), t, str(p.get("scope", "all")), int(p.get("frame", -1)), int(p.get("from", 0)),
				int(p.get("to", -1)), int(p.get("ease", 6)), bool(p.get("mirror", false)), who)
			return {"layers": ls.map(func(l: Dictionary) -> String: return FSAAdjust.describe(l))}
		"adjust_restore":
			return {"restored": app.adjust_restore(str(p.get("id", "")), str(p.get("bone", "")), who)}
		"adjustments":
			var out: Array = []
			for l in FSAAdjust.adjust_layers(app.doc):
				var v := FSAAdjust.value(l)
				out.append({"id": l["id"], "bone": l.get("bone", ""), "scope": l.get("scope", ""), "start": l.get("start", 0), "end": l.get("end", -1),
					"turn": [snappedf(rad_to_deg(v.x), 0.01), snappedf(rad_to_deg(v.y), 0.01), snappedf(rad_to_deg(v.z), 0.01)], "text": FSAAdjust.describe(l)})
			return out
		"fill":
			return app.fill_apply(p.duplicate(true), who)
		"fill_matches":
			return app.fill_matches(p)
		"fill_remove":
			return {"removed": app.fill_remove(str(p.get("id", "")), who)}
		"fills":
			var fls: Array = []
			for fl in app.doc.fills:
				var fd: Dictionary = (fl as Dictionary).duplicate(true)
				fd["text"] = FSAFill.describe(fl)
				fls.append(fd)
			return fls
		"feet":
			if p.has("planted") and bool(p["planted"]) != app.doc.plant:
				app.set_clip_prop("plant", bool(p["planted"]))
			return app.feet_report(int(p.get("step", 1)))
		"show_panel":
			app.dock.show_panel(str(p.get("title", "")))
			return {"shown": str(p.get("title", ""))}
		"set_layer":
			var props := p.duplicate(true)
			props.erase("id")
			if typeof(props.get("mask", null)) == TYPE_STRING:
				props["mask"] = FSARig.MASKS.get(str(props["mask"]), [])
			app.set_layer(str(p.get("id", "")), props, who)
			return app.doc.layer_by_id(str(p.get("id", "")))
		"remove_layer":
			app.remove_layer(str(p.get("id", "")), who)
			return {"layers": app.doc.layers.size()}
		"set_active_layer":
			app.set_active_layer(str(p.get("id", "")))
			return {"active_layer": app.active_layer}
		"list_constraints":
			return app.doc.constraints
		"add_constraint":
			return app.add_constraint(_con_def(p), who)
		"set_constraint":
			var cp := _con_def(p)
			cp.erase("id")
			app.set_constraint(str(p.get("id", "")), cp, who)
			return app.doc.constraint_by_id(str(p.get("id", "")))
		"remove_constraint":
			app.remove_constraint(str(p.get("id", "")), who)
			return {"constraints": app.doc.constraints.size()}
		"freeze":
			var fr := int(p.get("from", round(app.frame)))
			return app.add_constraint({"type": "pin", "bone": str(p.get("bone", "")), "what": str(p.get("what", "both")), "pin_frame": fr, "start": fr, "end": int(p.get("to", -1)), "name": "FREEZE " + str(p.get("bone", ""))}, who)
		"bake_to_keys":
			app.bake_to_keys(who)
			return {"keys": app.doc.keys.size()}
		"lock":
			for b in (p.get("bones", []) as Array):
				app.set_lock(str(b), str(p.get("channels", "xyz")), who)
			return app.doc.locks
		"unlock":
			for b in (p.get("bones", []) as Array):
				app.set_lock(str(b), "", who)
			return app.doc.locks
		"list_sockets":
			var out2: Dictionary = {}
			for n in app.sock_specs:
				out2[n] = {"bone": (app.sock_specs[n] as Dictionary).get("bone", ""), "world": _m3(app.socket_world(str(n)))}
			return out2
		"list_props":
			return app.doc.props
		"add_prop":
			var shape := str(p.get("shape", "block"))
			var pr := {"id": FSADoc.new_id(app.doc.props, "prop"), "name": str(p.get("name", shape)), "shape": shape,
				"socket": str(p.get("socket", "fist_R")), "offset": p.get("offset", [0, 0, 0]), "rot": p.get("rot", [0, 0, 0]),
				"scale": float(p.get("scale", 1.0)), "color": str(p.get("color", "#9a9aa2"))}
			if p.has("grip"):
				pr["grip"] = str(p["grip"])
			if p.has("size"):
				pr["size"] = p["size"]
			app.mutate("Add prop " + shape, func() -> void: app.doc.props.append(pr), who)
			return {"id": pr["id"]}
		"set_prop":
			var pid := str(p.get("id", ""))
			app.mutate("Prop " + pid, _set_prop_fields.bind(pid, p), who)
			return app.doc.props
		"remove_prop":
			if bool(p.get("all", false)):
				app.mutate("Remove props", func() -> void: app.doc.props.clear(), who)
			else:
				var rid := str(p.get("id", ""))
				app.mutate("Remove prop", func() -> void: app.doc.remove_by_id(app.doc.props, rid), who)
			return app.doc.props
		"add_marker":
			var mf := int(p.get("frame", round(app.frame)))
			var mn := str(p.get("name", "marker"))
			app.mutate("Marker " + mn, func() -> void: app.doc.add_marker(mf, mn), who)
			return app.doc.markers
		"set_view":
			return _set_view(p)
		"screenshot":
			return await _screenshot(p)
		"checks":
			return app.run_checks()
		"transition_clip":
			if app.history.dirty() and not bool(p.get("discard", false)):
				return {"error": "save the open clip first (or pass discard: true)"}
			return {"ok": app.make_transition_clip(str(p.get("clip_b", "")), int(p.get("at", 0)), int(p.get("blend", 6)), str(p.get("name", "transition")), who), "clip": app.doc.name}
		"undo":
			app.undo()
			return {"keys": app.doc.key_frames()}
		"redo":
			app.redo()
			return {"keys": app.doc.key_frames()}
		"history":
			return app.history.labels(60)
		"say":
			app.say("Agent: " + str(p.get("message", "")), "agent")
			app.agent_flash = 1.0
			return {"shown": true}
		"bake_glb":
			if app.history.dirty():
				return {"error": "save the clip first: the bake reads the saved files"}
			var py := "D:/Projects/Animato/.venv/Scripts/python.exe"
			var script := "D:/Projects/Animato/bake_studio_clips.py"
			if not FileAccess.file_exists(py) or not FileAccess.file_exists(script):
				return {"error": "Animato not found"}
			var pid := OS.create_process(py, [script, app.fighter])
			app.say("Agent started an Animato bake of %s (Blender, background)." % app.fighter, "agent")
			return {"started": pid > 0, "pid": pid, "note": "the original GLB is kept in D:/Cache/chars_before_studio"}
	return {"error": "not handled: " + m}


func _rig() -> Dictionary:
	var sk := app.skel
	var bones: Array = []
	CBClipLib.apply_pose(app.stage.probe_skel, {})
	app.stage.probe_skel.force_update_all_bone_transforms()
	for i in sk.get_bone_count():
		var b := sk.get_bone_name(i)
		var lim: Dictionary = FSARig.limits().get(b, {})
		var limd: Dictionary = {}
		for ax in lim:
			limd[ax] = [snappedf(rad_to_deg(float(lim[ax][0])), 0.1), snappedf(rad_to_deg(float(lim[ax][1])), 0.1)]
		var par := sk.get_bone_parent(i)
		bones.append({"name": b, "parent": sk.get_bone_name(par) if par >= 0 else "", "group": FSARig.group_of(b), "side": FSARig.side_of(b),
			"mirror": FSARig.mirror_name(b), "axes": FSARig.hint(b), "limits_deg": limd, "locked": app.doc.lock_channels(b),
			"rest_world": _m3(app.stage.probe_skel.global_transform * app.stage.probe_skel.get_bone_global_pose(i).origin),
			"follows": CBClipLib.FOLLOW.get(b, [])})
	return {"fighter": app.fighter, "height_m": snappedf(app.stage.height, 0.01), "bones": bones, "limbs": FSARig.LIMBS, "masks": FSARig.MASKS.keys(),
		"controls": FSARig.controls().map(func(c: Dictionary) -> String: return str(c["name"])), "sockets": app.sock_specs.keys(),
		"space": "world metres, fighter at the origin facing +Z (the Front view looks at its face), up is +Y; this rig's R bones sit on +X, L bones on -X",
		"rotation": "per bone Euler degrees [x, y, z] on top of the rest, applied Z * Y * X (Blender XYZ); a bone missing from a key is at rest",
		"rules": ["a knee never bends forward: kneeL / kneeR X stays >= 0 (the tools clamp it)",
			"thigh (legL / legR) X negative = leg forward; knee X positive = bends; foot X positive = toes down",
			"arm X negative = raised forward; elbow X negative = bends; armL Z negative / armR Z positive = arm out to the side",
			"torso / chest / head X positive = lean / nod forward; Y = twist; Z = side lean",
			"spins and flips turn the hips (the body turns about its centre); hips dy moves the body up / down",
			"rolls reuse Vix's escape roll (City Breaker rule): tuck knees to the chest, one turn, crouch, stand",
			"fingers / tips / thumb close the whole hand (the extra finger bones follow them)"],
		"workflow": "open_clip or new_clip -> set_pose / ik_pose / apply_pose / set_control (each keys by default) -> screenshot target=sheet to look at it -> checks -> save"}


func _get_pose(p: Dictionary) -> Dictionary:
	var frames: Array = []
	if typeof(p.get("frame", null)) == TYPE_ARRAY:
		frames = p["frame"]
	else:
		frames = [float(p.get("frame", app.frame))]
	var want: Array = p.get("bones", [])
	var out: Dictionary = {}
	for f in frames:
		var sk := app.stage.probe_skel
		var pose: Dictionary
		if bool(p.get("final", true)):
			pose = app.final_pose_on(sk, float(f))
		else:
			pose = FSAEval.layer_pose(app.doc, float(f), app.bones)
			CBClipLib.apply_pose(sk, pose)
			sk.force_update_all_bone_transforms()
		if absf(float(f) - app.frame) < 0.001 and not app.pending.is_empty():
			pose = app.pending
		var bones: Dictionary = {}
		for b in (want if not want.is_empty() else app.bones):
			var e: Vector3 = pose.get(b, Vector3.ZERO)
			if not want.is_empty() or e.length_squared() > 1e-8:
				bones[b] = _deg3(e)
		var entry := {"bones": bones, "hips": {"dx": snappedf(float(pose.get("_dx", 0.0)), 0.0001), "dy": snappedf(float(pose.get("_dy", 0.0)), 0.0001), "dz": snappedf(float(pose.get("_dz", 0.0)), 0.0001)},
			"is_key": app.doc.has_key(int(round(float(f))))}
		if bool(p.get("world", false)):
			var wp: Dictionary = {}
			for b in (want if not want.is_empty() else app.bones):
				var bi := sk.find_bone(str(b))
				if bi >= 0:
					wp[b] = _m3(sk.global_transform * sk.get_bone_global_pose(bi).origin)
			entry["world"] = wp
		out[str(int(round(float(f)))) if absf(float(f) - round(float(f))) < 0.001 else str(f)] = entry
	return out if frames.size() > 1 else out.values()[0]


func _set_pose(p: Dictionary, who: String) -> Dictionary:
	_goto(p)
	var pose := app.editable_pose()
	var add := str(p.get("mode", "set")) == "add"
	var rad := bool(p.get("radians", false))
	var bad: Array = []
	var clamped: Array = []
	for b in (p.get("bones", {}) as Dictionary):
		if not (b in app.bones):
			bad.append(b)
			continue
		var v: Vector3 = FSAEval._v3(p["bones"][b]) if rad else _rad3(p["bones"][b])
		var old: Vector3 = pose.get(b, Vector3.ZERO)
		var want := old + v if add else v
		var got := app.doc.guard(str(b), old, want)
		if not got.is_equal_approx(want):
			clamped.append(b)
		pose[b] = got
		if bool(p.get("mirror", false)):
			var mn := FSARig.mirror_name(str(b))
			if mn != str(b):
				pose[mn] = app.doc.guard(mn, pose.get(mn, Vector3.ZERO), FSARig.mirror_euler(got))
	var h: Dictionary = p.get("hips", {})
	for ax in ["dx", "dy", "dz"]:
		if h.has(ax):
			pose["_" + ax] = (float(pose.get("_" + ax, 0.0)) if add else 0.0) + float(h[ax])
	app.edit_pose(pose, "Agent pose f%d" % int(round(app.frame)), bool(p.get("key", true)), who)
	var r := {"frame": int(round(app.frame)), "keyed": bool(p.get("key", true))}
	if not bad.is_empty():
		r["unknown_bones"] = bad
	if not clamped.is_empty():
		r["clamped_by_limits_or_locks"] = clamped
	return r


func _ik_pose(p: Dictionary, who: String) -> Dictionary:
	_goto(p)
	var b := str(p.get("bone", ""))
	if not (b in app.bones):
		return {"error": "no bone %s" % b}
	var was := app.keep_end
	app.keep_end = bool(p.get("keep_end", true))
	app.drag_begin("Agent IK " + b)
	app.drag_ik(b, FSAEval._v3(p.get("target", [0, 1, 0])))
	app.keep_end = was
	if bool(p.get("key", true)):
		app.key_now("Agent IK %s f%d" % [b, int(round(app.frame))], who)
	app._drag_start = {}
	var reached := app.joint_world(b)
	return {"frame": int(round(app.frame)), "reached": _m3(reached), "miss_m": snappedf(reached.distance_to(FSAEval._v3(p.get("target", [0, 1, 0]))), 0.0001)}


func _set_key_values(p: Dictionary, who: String) -> Dictionary:
	var f := int(p.get("frame", -1))
	var k := app.doc.key_at(f)
	if k.is_empty():
		return {"error": "no key at f%d (use set_pose with key: true to make one)" % f}
	if bool(k.get("lock", false)):
		return {"error": "the key at f%d is locked" % f}
	var before := FSADoc.pose_of_key(k, app.bones)
	var after := before.duplicate()
	for b in (p.get("bones", {}) as Dictionary):
		if b in app.bones:
			after[b] = app.doc.guard(str(b), before.get(b, Vector3.ZERO), _rad3(p["bones"][b]))
	for ax in ["dx", "dy", "dz"]:
		if (p.get("hips", {}) as Dictionary).has(ax):
			after["_" + ax] = float(p["hips"][ax])
	var updated: Array = []
	app.mutate("Agent edit key f%d" % f, func() -> void:
		app.doc.write_key(f, after, app.bones)
		if app.propagate != "off":
			updated.append_array(app.doc.propagate(f, before, after, app.bones, app.propagate)), who)
	return {"frame": f, "also_updated": updated}


func _maybe_key(p: Dictionary, who: String) -> Dictionary:
	if bool(p.get("key", true)):
		return app.key_now("", who)
	return {"frame": int(round(app.frame)), "keyed": false}


func _con_def(p: Dictionary) -> Dictionary:
	var d := p.duplicate(true)
	for fld in ["min_deg", "max_deg"]:
		if d.has(fld):
			d[fld.substr(0, 3)] = _v3_arr(_rad3(d[fld]))
			d.erase(fld)
	if d.has("target") and typeof(d["target"]) == TYPE_ARRAY:
		d["target"] = {"pos": d["target"]}
	return d


static func _v3_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _set_prop_fields(pid: String, p: Dictionary) -> void:
	for x in app.doc.props:
		if str((x as Dictionary)["id"]) == pid:
			for k in p:
				if k != "id":
					(x as Dictionary)[k] = p[k]


func _set_view(p: Dictionary) -> Dictionary:
	if p.has("layout"):
		app.set_layout(str(p["layout"]))
	if p.has("preset"):
		var i := int(p.get("index", 0))
		if i < app.canvas.views.size():
			(app.canvas.views[i] as FSAView).set_preset(str(p["preset"]))
			if p.has("ortho"):
				(app.canvas.views[i] as FSAView).ortho = bool(p["ortho"])
				(app.canvas.views[i] as FSAView)._cam()
	if p.has("onion"):
		app.set_onion(bool(p["onion"]))
	if p.has("tool"):
		app.set_tool(str(p["tool"]))
	if p.has("bone"):
		app.select_bone(str(p["bone"]))
	if p.has("focus_bone") or p.has("yaw") or p.has("pitch") or p.has("dist"):
		var vi := int(p.get("index", 0))
		if vi < app.canvas.views.size():
			var v := app.canvas.views[vi] as FSAView
			if p.has("yaw"):
				v.yaw = deg_to_rad(float(p["yaw"]))
			if p.has("pitch"):
				v.pitch = deg_to_rad(float(p["pitch"]))
			var tgt := v.target
			if p.has("focus_bone") and app.skel != null:
				var bi: int = app.skel.find_bone(str(p["focus_bone"]))
				if bi >= 0:
					tgt = app.skel.global_transform * app.skel.get_bone_global_pose(bi).origin
			v.frame_point(tgt, float(p.get("dist", v.dist)))
			app.focused_view = v   # the view render_view (screenshot target=view) uses
	return {"layout": app.canvas.layout, "views": app.canvas.views.map(func(v: FSAView) -> String: return v.preset)}


func _screenshot(p: Dictionary) -> Dictionary:
	var target := str(p.get("target", "sheet"))
	var w := int(p.get("width", 1920))
	var h := int(p.get("height", 1080))
	var path := str(p.get("path", ""))
	if path == "":
		DirAccess.make_dir_recursive_absolute(FSAApp.RENDERS)
		path = "%s/agent_%s_%s_%s.png" % [FSAApp.RENDERS, app.doc.name, target, Time.get_datetime_string_from_system().replace(":", "-")]
	match target:
		"window":
			await RenderingServer.frame_post_draw
			var img := app.get_viewport().get_texture().get_image()
			if img.save_png(path) != OK:
				return {"error": "could not write " + path}
		"view":
			if p.has("index") and int(p["index"]) < app.canvas.views.size():
				app.focused_view = app.canvas.views[int(p["index"])]
			path = await app.render_view(w, h, path)
		_:
			path = await app.render_strip(w, h, int(p.get("cols", 8)), path)
	return {"path": path} if path != "" else {"error": "render failed"}
