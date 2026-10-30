# RMT Wrap: body parts that never go through (plan, 2026-10-29)

**Goal (the user's priority).** A unit's body parts stop going into its own body and through objects: an arm doesn't sink
into the chest, a hand doesn't pass through the head, legs don't cross through each other, a tail doesn't swing through a leg,
and a fist, foot or knee doesn't go through the floor, a wall, a prop or another fighter.

There are two wraps. **The Collision Wrap comes first.** The Hit Wrap waits until later, starting on effects and objects (part 2).

| Name | Answers | When |
|---|---|---|
| **Collision Wrap** | *What can't pass through what?* Body part vs own body, vs the floor / walls / props, vs other fighters | **now** |
| **Hit Wrap** (+ Masks) | *Did that really touch?* Hits from the true shape of a limb, an effect or an object | later; effects and objects first, fighter hits keep the boxes until you say |

---

# Part 1: the Collision Wrap

## 1. Today

- Nothing stops a body part going through anything. `CBAnim.update` (`anim.gd`) poses the skeleton straight from the clip,
  so when a clip puts a hand inside the chest, the hand is inside the chest.
- The only collision is one capsule per fighter (`fighter.gd`) for moving on the stage. Limbs have none.
- Fighters are on their own physics layers so they pass through each other; `_jostle` only nudges grounded fighters on the X axis.
- Tails, ears and crests are spring chains (`CBSecondary`, Godot `SpringBoneSimulator3D`) with no colliders, so they swing
  through the legs and body.
- The clips come from `gen_*.py` and Fight Studio, and nothing checks them for parts going inside each other.

## 2. The idea

### 2.1 The wrap: smooth capsules fitted to the body

Each fighter gets a Collision Wrap of about 16 to 22 **capsules and spheres** riding the bones: head, neck, chest, belly, hips,
upper arms, forearms, fists, thighs, shins, feet, tail segments, ears, horns and crest. Capsules, not exact hulls, because
pushing needs smooth, stable surfaces and capsule-vs-capsule is cheap.

The **Wrap Baker** fits them from the real mesh:
- Each vertex goes to the bone that owns most of its weight. Each bone gets a capsule along the bone (joint to child joint) with
  a radius at the 80th percentile of the vertices' distance to that axis, so the capsule sits **just inside the skin** and
  never sticks out to cause a false clash.
- The torso splits into belly + chest, so Bill Collector's gut and Vix's waist are each their real size.
- It saves to `data/wraps/<fighter>.collide.json`, with a debug picture of every fighter wrapped.

### 2.2 Which pairs may touch

- **Neighbours are skipped**: parts one joint apart (upper arm vs chest at the shoulder, thigh vs hips) are always close.
- **Pairs that overlap in the rest pose are skipped**, so they never fight the model's own shape.
- **Soft pairs** get a tolerance: in a deep crouch the thigh may press 2 cm into the belly, like flesh squashing.
- All of this is baked into the wrap file, and any pair can be edited by hand.

### 2.3 The Body Solve (runs every frame, after the clip pose)

In `CBAnim.update`, the order becomes: clip pose -> plant + flat feet -> **Body Solve** -> spring chains -> hits.

1. **Find overlaps.** Closest points between capsules (exact and fast), giving the depth, contact point and push direction for
   every overlapping pair.
2. **Decide who moves.** Each part has a rank: hips and spine hold, then the head, then the upper limbs, forearms, hands, and
   the tail and ears last. **Planted feet never move.** The lower-ranked part gives way.
3. **Bend, don't teleport.** The part that gives way is pushed out along the contact normal by turning the joints of its chain
   (hand -> elbow -> shoulder, up to 3 joints), within the rig's joint limits (`data/animator_rig.json`; knees never bend
   forward). Four passes settle chains of contacts, such as a hand against a forearm against the chest.
4. **No pops.** A correction eases in and out over a few frames and is capped per frame, so an arm slides around the body
   instead of snapping. When the clip stops overlapping, the correction fades out.

It is deterministic (same pose in, same pose out) and cheap: about 150 capsule pairs per fighter, and only the pairs that
overlap reach the solver. Budget: under 0.3 ms per fighter.

### 2.4 Through objects

- **Floor, walls, platforms, props.** Limb capsules query the world's own colliders through Godot physics (Jolt
  `collide_shape` / `get_rest_info`), so every stage deck, building and prop that already has collision counts at once, with
  no new data. A fist that would go into the floor or a wall stops on the surface, and a kick at a wall folds back.
- **Other fighters.** Each fighter's wrap is an obstacle to the others, and a punch rests on the opponent's chest instead of
  going inside it. (The first plan also had bodies pushing each other, replacing `_jostle`. C3 dropped that: it moved fighters
  and changed when hits land, so the SSB64 jostle stays.)
- **Tails, ears and crests.** Godot's spring bones take capsule colliders (`SpringBoneCollisionCapsule3D`), so the wrap's
  capsules are given to them and the springs bounce off the legs and body by themselves.

### 2.5 Gameplay stays the same

The Body Solve changes **what you see**, not the fight. Hits, hurt checks, frame data, held and thrown items, shots and grab
holds all read the clip's own pose, as before, so no move gets shorter or longer. Making hits use the solved pose belongs with the Hit Wrap (part 2).

## 3. Phases

| # | Phase | Done when |
|---|---|---|
| C0 | **Baker + clash report** (no game change). Bake the wraps for all 11 fighters with a debug picture of each. `tools/body_clash.gd` runs every clip on every fighter, frame by frame, and lists each part going into its own body or under the floor: which pair, how deep (cm) and on which frames. | the report, worst first, with contact sheets of the worst clips with wraps drawn |
| C1 | **Body Solve.** `addons/rmt_wraps` (wrap data, capsule math, solver with ranks, joint limits and smoothing) with golden tests; hooked into `CBAnim.update` for matches. | clash report after the solve: no part more than 1 cm into its own body (outside soft pairs) on any frame of any clip; no pops (correction change per frame capped); all City Breaker checks pass; side-by-side proof video (before / after) |
| C2 | **Springs collide.** Tails, ears and crests get the wrap's capsules as colliders. | proof: Al's and Vix's tails during walk, run, roll and smash, no tail through a leg |
| C3 | **Through objects.** Limbs against world colliders (floor, walls, platforms, props) and against other fighters; the trunk and head shift the whole model out of the stage; the SSB64 jostle stays (fighter positions never change); the open world's `GameCBBody` gets the same hook. | proof on TEST LAB and in the open world: jab at a wall, kick at the floor, two fighters trading at close range, nothing goes through |
| C4 | **Fight Studio** (when the other agent is done with it). A wraps overlay in every view and the strip, a "clash" lane on the timeline, the Body Solve as a **Collide** constraint (on, off, or baked into the clip's keys), and MCP tools `studio_wraps` / `studio_clash` so agents check their own animations. Both apps share the solver (JS port in Desktop). | an agent animates a move, `studio_clash` shows clean, and the strip shows it |

### C0 results (2026-10-29, dev copy C:/Dev/BSP-Universe-dev, branch wraps-dev)

Built: `addons/rmt_wraps` (capsule math, `RmtWrapFit`, `RmtWrapBody`), `data/wraps/<key>.collide.json` for all 11 fighters
(15-25 capsules each, rules in `data/wraps/wrap_rules.json`), tools `wrap_bake.gd`, `wrap_sheet.gd` (pictures), `body_clash.gd`
(report), `wrap_pose.gd` (match posing). Report and pictures: `reports/wraps_c0/`.

- 913 fighter x clip runs, 34,207 frames in about 1 minute. **712 runs have a part going into the body** (more than 1 cm past
  the rest pose and the flesh allowance), and **272 have parts under the floor**.
- What goes through most: forearm into the chest (532 clips), hand into the head (442), toes under the floor (383), forearm
  into the head (364), hand into the chest (218), tail through a thigh (216). Worst: 30-36 cm (a fist right through the head).
- **Bug found:** `a_kat_bthrow` is planted, so when Kat flips upside down the game stands her raised feet on the floor and
  sinks her head 1.18 m under it. The same can happen to any planted clip that turns the body over.
- **Fit fixes for C1:**
  - The Bill Collector's paper body is flat, and a capsule can't be: he needs a flat piece (a box or hull).
  - Guru's peacock train is weighted to his legs, so his leg capsules wrap the train.
  - Some thigh capsules reach up into the hips, from the shorts' weights.
  - Fit limbs along the bone segment, not the whole cloud.

### C1 results (2026-10-29, dev copy)

Built:
- `addons/rmt_wraps/body_solve.gd` (`RmtBodySolve`) and `game/packs/city_breaker/wraps.gd` (`CBWraps.make_solver`).
- Hooked into `CBAnim.update` after plant + flat feet. Hits read the clip pose (`CBAnim.hit_world` and `CBFighter.hit_pos` in
  `hitbox_world`, `limb_dir` and `hurt_segments`), so fights are unchanged. `--no-wraps` (or `CBWraps.enabled = false`) shows
  the clips as keyed.

The fit got better:
- Limbs fit only the vertices between their joints (no shorts over the hip).
- The Bill Collector's paper body is a row of thin capsules (rules `fighters.bigbill.flat`).
- Guru's train is capped (`max_r`).

**Natural joint limits for every joint** (user, 2026-10-29: "wrist, elbows, fingers, feet need the same constraint types like
knees; the body shouldn't bend in unnatural ways"):
- `data/animator_rig.json` now has `limits` for the spine, neck, head, shoulders, elbows, wrists, hips, knees, ankles and
  fingers, plus `hinge` (elbows and knees bend about X only).
- The axes were checked on axis_probe sheets:
  - Ankle: +X points the toes down, -X lifts them (up to 40°).
  - Wrist: X bends it forward/back, Y twists, Z bends it sideways (±29°).
- The solve never turns a joint past these, or past the clip's own value where the clip already goes further. Fight Studio's
  tools clamp to the same ranges.
- Fingers get only a safe range on every axis for now: the curl axis differs between the plain rig v4 hands and the
  Mixamo-based hands, so each rig's fingers still need probing.

Numbers (913 fighter x clip runs, 34,207 frames, solve with 2 passes per frame):

| | as keyed | with the Body Solve |
|---|---|---|
| clash rows deeper than 5 cm | 2,590 | 276 |
| deeper than 20 cm | 150 | 4 |
| clips with a clash over 5 cm | 580 | 119 |
| clips with parts under the floor | 272 | 70 (mostly toes within a few cm) |
| largest joint correction | - | 92° (tails, ears, crests only; arms and wrists are capped by `max_turn`) |

Four passes per frame give 107 clips over 5 cm instead of 119, at about 1.6x the cost.

- **The clips also bend joints past natural ranges themselves** (the report's "bends" table). Elbows bend sideways (110
  clips, up to 24° past), wrists go too far (up to 53°), ankles point the toes down too far (up to 70°), hips and shoulders go
  past up to 46°. The solve never makes these worse; fixing them is a clip edit.
- **Cost** (debug build, Carter's own clips): the clip pose takes 0.63 ms and the solve 0.79 ms per fighter per frame. This is
  over the 0.3 ms target. Next: skip the solve on frames with no contacts and no carried correction, and a GDExtension if a
  release build is still too slow.
- **Still left:**
  - Rhino's landing spine fold (the spine is capped at a small turn on purpose).
  - Al's tail on the floor in his down-tilt (fixed for real by C2, springs with colliders).
  - The Bill Collector's hand against his paper body.
  - Kat's knees crossing in her walk (both feet planted, so neither leg may move).
- Checks: `tools/wrap_check.gd`, 25 checks pass. `tools/rules_check` passes 73 of 73 both with the solve and with
  `--no-wraps` (the fight is unchanged), and the animator checks pass 67 of 67 with the new limits. Proof videos (before / after): Carter's air dodge and idle guard (fist out of
  the face), Kat's back throw (above the floor), Vix's special punch (tail out of the leg).

### C2 results (2026-10-29, dev copy)

**Where the springs run.** Spring chains (`CBSecondary`: tails, ears, crests, poms, fins) run on the select screen, in the old
Studio and in the open world (`GameCBBody`). Matches play the clip pose only, and the Body Solve covers tails there.

**What changed.** `CBSecondary.build_specs` now takes the fighter `key` (or reads it from the model file) and does two things:
- **Colliders** (`CBWraps.spring_colliders`):
  - Every joint of a chain gets the radius of its own wrap capsule.
  - The simulator gets the body's other capsules as colliders, except the neighbour at the chain's root. The head still counts
    for an ear.
  - Each collider is shrunk by the smallest amount the chain already sits in it at rest, so the chain just touches it at rest
    and anything deeper is pushed out.
- **After-springs pass** (`CBWraps.spring_guard`, `addons/rmt_wraps/wrap_modifier.gd`):
  - A Body Solve that may move only the chain pieces runs as the last skeleton modifier.
  - Springs alone can only push their joints out, so a tail threaded tight between the legs still slips in; this pass catches it.

`build_specs(..., collide = false)` keeps the old free springs.

Measured with the springs simulating (`tools/spring_clash.gd`: wait, walk, run, dash, rolls, fsmash, dash attack, jump, land,
special punch, damage fall, open-world walk / run), frames with a chain more than 1 cm inside the body:

| fighter | springs free | springs + wrap |
|---|---|---|
| vix | 223 of 583 (worst 24.8 cm) | 16 (worst 2.5 cm) |
| carter | 151 of 627 (18.8 cm) | 6 (5.1 cm) |
| al | 64 of 667 (24.6 cm) | 0 |
| slum / guru / rhino | 22 / 4 / 35 | 0 / 0 / 0 |
| hype | 184 of 571 (11.3 cm) | 44 (7.8 cm, ears against the neck) |
| kat | 476 of 591 (24.3 cm) | 162 (7.5 cm, tail against her thighs) |

Kat's tail sits 15-20 cm inside her baggy-pants capsules at rest, so the room left is tiny. The user may rebuild the tailed
models with the tail separate from the body; a re-bake (`tools/wrap_bake.gd`) picks up any new model.

- Checks: `wrap_check.gd` passes 30 of 30. The new checks: Al's tail collides with the legs, Carter's ears with his head, the
  guard is the last modifier, and Al's roll with springs stays under 2 cm. The animator checks pass 67 of 67.
- `tools/studio_check` (old Studio) stops at "every fighter's baked clips must still move". The fighter GLBs no longer carry a
  `jab` animation, which is unrelated to the wraps and already the case before.
- Videos (springs free on the left, wrap on the right), in `reports/wraps_c2`: Vix's roll, Al's roll, Kat's special punch,
  Carter's dash attack, Hype's open-world run.

### C3 results (2026-10-29, dev copy)

**What changed:**
- **The stage.** Limbs, head and tails stay out of the stage's solid decks. These are found through Godot physics, on layer 1
  only: one-way platforms stay passable, as in Smash. One broad query around the body comes first; precise capsule queries run
  only for parts near a collider (`RmtBodySolve.world`).
- **Other fighters.** Limbs stay out of the other fighters' bodies (`RmtBodySolve.others`: their wraps from their last solve,
  via `CBWraps.others_for`). A grab partner is left out, because holding someone means touching them. A punch now rests on the
  chest it hits instead of sinking in.
- **Whole-model nudge.** The trunk, neck and head can't bend far, so when one of them is inside the stage (a head in the deck
  under a ledge) the whole model shifts out instead: at most 25 cm, at once, easing back once free. This is visual only, and
  only against the stage.
- **Toggles:** `--no-wraps` (clips as keyed), `--no-wrap-world` and `--no-wrap-others`.

**Decisions taken on the way:**
- **No nudge against other fighters.** Shifting the model away from another body makes it drift from where its hits land, so
  hits would look like they connect on a body that has moved. Against other fighters, limbs bend; that is all.
- **The jostle stays pure SSB64.** A wrap-based jostle (bodies never closer than their trunks) was tried and dropped: it moved
  fighters, so Carter's jab on the Bill Collector landed 8 frames later. Fighter positions are untouched.
- **Everything the game decides reads the clip's own pose,** never the pose you see: hits, hurt checks, held items (their hit
  points), thrown and dropped items, shots, grab holds. `CBFighter.hit_pos` and `CBAnim.hit_world` now rebuild the clip pose
  from skeleton space relative to the fighter at the moment of asking, so a move after posing (the jostle, a teleport) carries
  it along as it did before the wraps. Held items are drawn in the hand you see (`global_transform`) and hit from the clip's
  hand (`CBItem._game_xf`). Effects (sparks, glints) still follow the visible pose.

**The bug that failed 4 rules checks** (Bob-omb, staling, KO at 180%, respawn):
- The solver moved the model with `global_position`. Setting a global position makes Godot rebuild the node's rotation from its
  basis. On a model pitched past 90 degrees (a fighter tilted by a throw) that reads back as a flipped twin, with y and z turned
  by PI, and the next frame's `rotation.x = ...` kept it.
- The fighter stayed upside down after the grab checks, with its hurt checks under the floor, so the Bob-omb flew through it.
- Found by bisecting (`--no-wrap-world` passed 73/73, `--no-wrap-others` failed the same 4) and a frame-by-frame probe of P2.
- Fixed: `RmtBodySolve._shift` moves the model through its local `position`. `wrap_check` now checks that a pitched model keeps
  its rotation through a shift.

**Measured in real matches** (`tools/match_clash.tscn`: CPU 3 vs CPU 3 on Marina, 1,800 frames, about 30 s per pair). Frames
with limbs in the stage / limbs in the other body / trunks overlapping, more than 2 cm (feet 4 cm), clips as keyed -> wraps on:

| pair | limbs in the stage | limbs in the other body | trunks overlapping |
|---|---|---|---|
| vix vs carter | 161 -> 57 | 304 -> 195 | 59 -> 57 |
| al vs kat | 332 -> 51 | 236 -> 154 | 43 -> 43 |
| bigbill vs rhino | 1,091 -> 125 | 178 -> 143 | 55 -> 66 |
| hype vs guru | 126 -> 38 | 147 -> 116 | 12 -> 12 |
| slum vs goat | 82 -> 9 | 94 -> 68 | 4 -> 4 |
| vic vs carter | 140 -> 48 | 89 -> 60 | 13 -> 13 |
| **all (10,800 frames)** | **1,932 -> 328 (-83%)** | **1,048 -> 736 (-30%)** | 186 -> 195 |

What's left is mostly the trunk and head against the other body. Bending can't move them, and on purpose nothing shifts the
whole model against another fighter. The trunk column counts the pose you see, so it moves a little either way; the fight
itself doesn't: after 1,800 frames, Bill Collector vs Rhino and Vix vs Carter end at exactly the same positions (to 4 decimals),
damage and stocks with the wraps on and off (`reports/wraps_c3/game_fingerprint.txt`).

**Checks:**
- `rules_check` passes 73 of 73 with the wraps and 73 of 73 with `--no-wraps`.
- `wrap_check` passes 35 of 35: a fist in a wall comes out, a head in a wall shifts the model and it eases back, a fist in
  another fighter stops at the body, and a pitched model keeps its rotation.
- Proof strips (`reports/wraps_c3`, `match_standalone --demo --zoom=4 --unfocusable`): Carter's jab and forward tilt on the
  Bill Collector, as keyed vs wraps on. The jab lands on frame 126 both ways.

**Not done in C3:** the open world's `GameCBBody` (another session's uncommitted file in the main checkout, not in this branch).
It needs one hook: set `solver.world` / `solver.others` the way `CBAnim.update` does.

## 4. Decisions (my picks, change any)

1. **Capsules and spheres** for the Collision Wrap: smooth, stable and cheap. Exact hulls are for the Hit Wrap.
2. **Fix it at run time, not by rewriting clips**, so every clip is covered: generated ones, Fight Studio ones and future ones.
   Fight Studio can still bake the fix into a clip on purpose (C4).
3. **Visual only first.** Hits keep reading the clip pose, so fight balance doesn't move.
4. **Ranks:** hips/spine > head > upper limb > forearm > hand > tail/ears; planted feet are fixed.
5. **World obstacles through Godot physics** (they already exist); self and fighter-vs-fighter on our own capsule math (deterministic).

## 5. Risks

- **A clip that relies on a pass-through** (a hand behind the back that clips the hip) will look different. The C0 report shows
  every such case first, and a pair can be made soft or excluded.
- **A big push can look like a twitch.** That's why the solve is capped and smoothed; the proof videos check for it.
- **Open world code belongs to another session** (`game/world/cb_body.gd`). C3 adds one hook call there, coordinated, not a rewrite.

---

# Part 2: the Hit Wrap (later)

Kept from the first plan, now second:

- **Hit Wrap:** tight shapes (convex hulls) fitted to limbs, objects and effects. A hit lands when the striking part's wrap
  first touches the target's, found by a sub-frame sweep. Clips are analytic, so poses between frames are exact, and fast limbs
  can't skip a target. Each hit gives the exact contact point, normal and time: sparks where it touched, a freeze on contact,
  reactions by body region, clanks on real overlap.
- **Masks:** flags painted over frames onto parts (hot = it hits, intangible, invincible, armor, guard, grab, weak spot). A hit
  becomes "these parts are hot from frame 5 to 8" instead of a box.
- **Effects:** rendered frame by frame, outline traced, so fire and beams hit only where they're drawn.
- **Order:** effects, projectiles and items first (they have no real shape today), then fighter hits when you want them, with
  a truth test that measures the old boxes against what visibly touched (false hits, misses, skips) and a small grace margin
  for feel. The SSB64 damage and knockback numbers never change.

It shares the add-on (`addons/rmt_wraps`), the baker and the debug draw with the Collision Wrap, so part 1 builds most of what
part 2 needs.
