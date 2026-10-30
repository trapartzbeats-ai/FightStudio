# Fill: the frames between two keys, made for you

Branch `inbetween` (dev copy C:/Dev/BSP-Universe-motion). Started 2026-10-30 after looking at NVIDIA MotionBricks
(localai-org/motion-bricks.cpp): a network that fills the motion between a few poses before and a few poses after. We want
that in Fight Studio, but on our own rig, inside our own limits, with no GPU, no model download and no robot skeleton.

## What we have to work with

- **The clips**: 743 clips, 26,197 frames, but only 3,871 keys (about 5 per clip). They are all sparse and eased: the gen_*.py
  scripts and the hand-made ultimates. None of them is motion capture. A learned model (MotionBricks, Robust Motion
  In-betweening, Kimodo) needs hours of dense real motion, and we have none. So the main engine is built from animation rules,
  and the clips are used for what they really hold: **which poses a move passes through on the way, and how long it takes**.
- **The playback**: CBClipLib.pose_at lerps each Euler channel (Rz*Ry*Rx) between keys with the key's ease (linear, in, out,
  inout, hold, spline). Whatever Fill makes has to be plain keys that this plays back, so the game needs no change.
- **The rig**: rig v4 bone names on every fighter. Natural limits for every joint (animator_rig.json, FSARig.clamp_limits,
  fingers clamp_finger). Knees and elbows are hinges, and the hinge IK (FSAEval.solve_two_bone) now reaches exactly.
- **The feet**: CBFeet reads each model's real soles. In the match a planted clip is grounded every frame, but only up and down:
  nothing stops a planted foot sliding sideways while the body turns. `_foot_slide()` measures that.

## Research: how transitions are made

| Method | Idea | Use here |
|---|---|---|
| Key interpolation, slow in / slow out | what pose_at does | the baseline Fill has to beat |
| Hermite / squad on quaternions (Shoemake 1985; Kim, Kim & Shin 1995) | a curve through the poses that keeps the speed going through the keys | **Flow**: the motion carries the speed it had coming into A and leaving B |
| The animation principles (Thomas & Johnston): overlap, follow-through, anticipation, arcs, timing | the body does not move as one block | **Overlap, Anticipate, Overshoot, Timing** knobs |
| Motion warping / displacement mapping (Witkin & Popovic 1995; Bruderlin & Williams 1995) | take a real motion and bend it so it starts and ends where you need, keeping its detail | **Library** engine: a clip's motion bent onto A and B |
| Motion graphs / motion matching (Kovar et al. 2002; Clavet 2016) | search a library for the piece of motion that best joins two poses | **Library** search over every clip, mirrored too |
| Inertialization (Bollo 2016-18) | blend out the difference instead of the poses | the warp offsets fade with smoothstep |
| Footskate cleanup (Kovar, Schreiner & Gleicher 2002) | IK the legs so a foot in contact stays put | **Feet**: planted feet locked, steps lifted |
| MotionBricks (NVIDIA 2025), Robust Motion In-betweening (Harvey et al. 2020) | learned in-betweening from dense mocap | not now (no data, no GPU); the API is shaped so one could be added as a third engine |
| Duration prediction (MotionBricks' root/duration network) | how long should this take | the Library tells how many frames the same change took in our clips |

## The design

**Span**: two frames A < B, by default the keys around the playhead. Poses from the base keys (CBClipLib.pose_at), plus one
frame of context on each side for the speed coming in and going out (wraps on a loop, none at the clip's ends).

**Engine 1, Shape** (rules). Per bone, in quaternion space around A: r(u) = Hermite(0, Δ, m0, m1), q(u) = qA · exp(r(u)),
Δ = log(qA⁻¹ qB). Fingers (which add onto the parent finger key) and the hips offsets are Hermite per channel.
- **Timing**: smooth (stops at both ends), even, strike (slow start, hits B fast), settle (fast start, eases into B).
- **Flow** 0..1: blends the timing's end speeds toward the real speed coming in and going out (velocity continuity).
- **Overlap** 0..1: each joint starts a little later than its parent and catches up by B (hips > torso > chest > shoulders >
  elbows > hands > fingers, the tail behind the hips). Legs do not lag: the feet hold the ground.
- **Anticipate** 0..1: a small move the other way at the start, on the joints that turn a lot (> 10 degrees).
- **Overshoot** 0..1: goes a little past B before B, then settles onto it.

**Engine 2, Library** (our clips). Every clip is sampled at 30 frames a second into a pose index: quaternions of the 17 main
bones + the hips height. The search finds, in every clip (and mirrored), the stretch whose first pose is nearest A and last pose
nearest B, with a length near the span (0.5x to 2x; a small cost for stretching). The top matches are listed with a score. The
chosen stretch is played at the span's length and bent onto A and B (per bone q(u) = qM(u) · slerp(δA, δB, smoothstep(u)), the
offsets fade across). The match also gives a **suggested length**: how many frames that change took in the clip it came from.

**After either engine**
1. Every joint inside its natural limits (clamp_limits, clamp_finger): knees never bend forward.
2. **Feet** (planted clips): a foot standing at A and at B on the same spot (< 3 cm) is held there with the hinge leg IK,
   flat, for every in-between frame. A standing foot that moved is a **step**: it lifts on an arc (up to 12 cm) and lands.
3. **Air** (cm, 0 = off): the hips follow a jump arc that high above the line from A to B.
4. Keys are written every `step` frames (default: every 2 at 60 fps), tagged "breakdown" and `"fill": id`. Key A's ease is set
   to linear while the fill is on (the fill carries the timing now) and put back when it comes off.

**The record**: studio "fills": [{id, a, b, engine, settings, pick, a_ease}] so a fill can be changed live, redone or removed.
A fill is plain keys: it plays in the game with no change, and you can still edit any of its keys.

## Where it goes

- core/fill.gd (FSAFill): the engines, the index, the feet pass. No UI, no app state: testable headless.
- animator.gd: fill_span, fill_apply, fill_matches, fill_remove, fill_list (one undo step each).
- ui/panels.gd: a Fill panel (right column, after Adjust): span, engine, knobs (change live once filled), matches, feet, air,
  key step, the fills on this clip with REMOVE.
- api/api.gd + mcp/fight_studio_mcp.py: fill, fill_matches, fill_remove, fills.
- tests/animator_check.gd: _fill(): ends unchanged, limits, smoothness, flow speed, overlap order, feet held (slide before vs
  after), library finds a clip's own stretch, remove restores, undo.
- Fight Studio Desktop: src/core/fill.js + panel + API, checked against a Godot reference (D:/Cache/fight_studio_dev/ref_fill.json).
- README (manual), Fight Studio Book, InkBoard frame: when it merges.

## Results (2026-10-30)

- Godot animator checks 151/151; Fight Studio Desktop self-test 116/116. The desktop's fill keys equal Godot's (shape and
  library exact, legs through the feet IK within 0.0003 rad): reference D:/Cache/fight_studio_dev/ref_fill.gd -> ref_fill.json.
- Timing: smooth 16% of the move at a quarter of the time, strike 3%, settle 52%. Overlap 1: torso 12% > arm 6% > hand 2% at
  the same frame, the hand caught up by B. Flow: 0.072 per 2 frames carried on against 0.067 coming in (0.016 without).
- Feet: hips shifted 6 cm and turned 17 degrees over planted feet: 0.1 mm drift (5.5 mm without). A foot moved 15 cm steps
  with a 3.7 cm lift.
- Library: 743 clips indexed in 0.6-2.3 s (once), searched in 0.1 s (desktop) / 0.4 s (Godot). A stretch of a clip is found
  again exactly (cost 0.0004), mirrored too.
- Real clip, Vix's forward smash with its two strike keys taken out (f8-f22): two keys alone spin through badly; SHAPE strike
  whips round into the kick; LIBRARY's best is Carter's ftilt at 35% (weak: the panel says so, SHAPE suits it better).
  Picture: D:/Cache/fight_studio_dev/fill_demo/fill_demo_sheet.png.
- Found on the way and fixed: wrapping key B toward A turned a keyed spin (hips past a full turn) the short way; the game plays
  raw values, so Fill now does too. The keys of that clip also move the support foot 23 cm: Fill makes it a step (6 cm lift)
  where the clip slides it.

Open: README (manual) + Fight Studio Book pages when it merges; a third engine (a learned model) could plug into FSAFill.make
if we ever have dense motion to train on.
