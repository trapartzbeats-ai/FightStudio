class_name FSAMerge
extends RefCounted
## Merge: one new animation from several. The open clip is the BASE (it gives the body); clips ON TOP give only the body
## parts you pick (the arms of a cheer, a clap, a wave over a walk), each from a start frame, blending in and out. Every clip on
## top is an ordinary override layer tagged "merge" (the Layers panel shows it too), so playing previews it live. Baking makes
## ONE new clip (keys thinned so it stays editable) and leaves the base clip as it is; the recipe rides along in the new clip
## ("merge": base + layers), so the setup can be rebuilt.

## body parts a clip on top can give, in the order the chips show them
const PARTS := ["Head", "Spine", "Arm L", "Arm R", "Hands", "Hips", "Legs", "Tail"]
const PART_BONES := {
	"Head": ["neck", "head", "@Ears"],
	"Spine": ["torso", "chest"],
	"Arm L": ["armL", "elbowL", "handL"],
	"Arm R": ["armR", "elbowR", "handR"],
	"Hands": ["@Hand L", "@Hand R"],
	"Hips": ["hips"],
	"Legs": ["legL", "kneeL", "footL", "legR", "kneeR", "footR"],
	"Tail": ["@Tail"],
}
const DEFAULT_PARTS := ["Arm L", "Arm R", "Hands"]


## the layer mask for a set of parts
static func mask_for(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		for b in (PART_BONES.get(str(p), []) as Array):
			if not b in out:
				out.append(b)
	return out


## a clip on top as a layer: clip frame 0 lands on `start`; a one-shot ends when its clip does, a cycled one runs to the end
static func layer_def(clip: String, parts: Array, start: int, blend_in: int, blend_out: int, weight: float = 1.0, cycle: bool = false, speed: float = 1.0) -> Dictionary:
	var c := FSAEval.clip_src(clip)
	var n := int(c.get("frames", 24))
	return {"name": clip, "mode": "override", "source": "clip", "clip": clip, "merge": true, "parts": parts.duplicate(),
		"mask": mask_for(parts), "start": start, "offset": start, "end": -1 if cycle else start + int(round(float(n) / maxf(speed, 0.01))),
		"fade_in": blend_in, "fade_out": blend_out, "weight": weight, "cycle": cycle, "speed": speed}


## when one field changes, the ones that follow it (start moves the clip with it; cycle / speed move the end)
static func follow(l: Dictionary, props: Dictionary) -> Dictionary:
	var out := props.duplicate()
	var start := int(out.get("start", l.get("start", 0)))
	var cycle := bool(out.get("cycle", l.get("cycle", false)))
	var speed := float(out.get("speed", l.get("speed", 1.0)))
	if out.has("parts"):
		out["mask"] = mask_for(out["parts"])
	if out.has("start"):
		out["offset"] = start
	if out.has("start") or out.has("cycle") or out.has("speed"):
		var n := int(FSAEval.clip_src(str(l.get("clip", ""))).get("frames", 24))
		out["end"] = -1 if cycle else start + int(round(float(n) / maxf(speed, 0.01)))
	return out


static func merge_layers(doc: FSADoc) -> Array:
	return doc.layers.filter(func(l: Dictionary) -> bool: return bool(l.get("merge", false)))


## how long the merged clip is: the base, or the last clip on top if that runs longer
static func length(doc: FSADoc) -> int:
	var n := doc.frames
	for l in merge_layers(doc):
		if not bool(l.get("mute", false)) and int(l.get("end", -1)) > n:
			n = int(l["end"])
	return n


## the base's keys repeated to cover `frames` (a looping base: a walk keeps walking under a long clap)
static func repeated_keys(doc: FSADoc, frames: int) -> Array:
	var keys: Array = doc.keys.duplicate(true)
	if not doc.loop or frames <= doc.frames or doc.frames <= 0:
		return keys
	var out: Array = []
	var cycle := 0
	while cycle * doc.frames <= frames:
		for k in keys:
			var f := int(k["f"]) + cycle * doc.frames
			if cycle > 0 and int(k["f"]) == 0:
				continue   # a loop's first key is its last key: once
			if f > frames + doc.frames:
				break
			var nk: Dictionary = (k as Dictionary).duplicate(true)
			nk["f"] = f
			out.append(nk)
		cycle += 1
	return out


## the merged clip as a new document (unsaved): the base + everything live on it, baked, thinned, with its recipe
static func bake(doc: FSADoc, skel: Skeleton3D, bones: Array, name: String, tolerance: float = 0.01) -> FSADoc:
	var n := length(doc)
	var tmp := FSADoc.from_clip(doc.to_clip())
	tmp.keys = repeated_keys(doc, n)
	tmp.loop = false
	tmp.frames = n
	var baked := FSAEval.bake(tmp, skel, bones, {})
	var nd := FSADoc.blank(name, n, doc.fps)
	nd.keys = baked
	nd.loop = false
	nd.plant = doc.plant
	var recipe: Array = []
	var from: PackedStringArray = []
	for l in merge_layers(doc):
		if bool(l.get("mute", false)):
			continue
		recipe.append({"clip": l["clip"], "parts": l.get("parts", []), "start": l.get("start", 0), "blend_in": l.get("fade_in", 0),
			"blend_out": l.get("fade_out", 0), "weight": l.get("weight", 1.0), "cycle": l.get("cycle", false), "speed": l.get("speed", 1.0)})
		from.append("%s (%s from f%d)" % [l["clip"], ", ".join(PackedStringArray(l.get("parts", []))), int(l.get("start", 0))])
	nd.extra["note"] = "Merge: %s with %s" % [doc.name, "; ".join(from)]
	nd.extra["merge"] = {"base": doc.name, "layers": recipe}
	var c := nd.to_clip()
	CBAnimTools.reduce_keys(c, bones, tolerance)
	return FSADoc.from_clip(c)
