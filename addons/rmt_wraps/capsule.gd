class_name RmtCapsule
extends RefCounted
## Capsule math for RMT Wrap: a capsule is a segment a-b with a radius r (a sphere is a capsule with a == b).
## Everything here is plain arithmetic: deterministic, no physics server.


## closest points between segments p0-p1 and q0-q1: [s, t, point on p, point on q] (s, t in 0..1)
static func seg_closest(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> Array:
	var d1 := p1 - p0
	var d2 := q1 - q0
	var r := p0 - q0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return [0.0, 0.0, p0, q0]
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [s, t, p0 + d1 * s, q0 + d2 * t]


## how deep two capsules overlap: depth > 0 means they overlap by that much; `normal` points from capsule 2 toward capsule 1
## (the way to push capsule 1 out), `pa` / `pb` are the closest points on the two axes
static func overlap(a0: Vector3, a1: Vector3, ra: float, b0: Vector3, b1: Vector3, rb: float) -> Dictionary:
	var c := seg_closest(a0, a1, b0, b1)
	var pa: Vector3 = c[2]
	var pb: Vector3 = c[3]
	var d := pa - pb
	var dist := d.length()
	var n := d / dist if dist > 1e-9 else Vector3.UP
	return {"depth": ra + rb - dist, "normal": n, "pa": pa, "pb": pb, "s": c[0], "t": c[1]}


## the lowest point of a capsule (y)
static func bottom(a: Vector3, b: Vector3, r: float) -> float:
	return minf(a.y, b.y) - r
