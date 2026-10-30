# RMT Wrap

Shapes fitted to the real thing instead of hand-placed boxes. Part 1 is the **Collision Wrap**, so body parts never go
through their own body or the floor. The plan and results are in `game/packs/city_breaker/WRAPS_PLAN.md`.

| File | What it is |
|---|---|
| `capsule.gd` (`RmtCapsule`) | Capsule math: closest points between segments, overlap depth, push normal, lowest point. |
| `wrap_fit.gd` (`RmtWrapFit`) | Fits a wrap to a skinned model. Each bone gets a capsule from the vertices it owns, just inside the skin: limbs between their joints, hubs and end parts along their flesh, flat parts as a row of thin capsules. It also lists the pairs to check, with the rest overlap and flesh allowance of each. |
| `wrap_body.gd` (`RmtWrapBody`) | A wrap on a live skeleton: where the capsules are now, which go into each other, and which are under a floor. |
| `wrap_modifier.gd` (`RmtWrapModifier`) | The Body Solve as a skeleton modifier. Placed after spring bones, it pushes what they swing into the body back out. Only `solver.movers` may move. |
| `body_solve.gd` (`RmtBodySolve`) | Runs after the clip pose and pushes parts back out by bending their own joints. It respects ranks, joint limits (hinges, natural ranges) and planted feet, lifts the whole body if it is under the floor, and smooths corrections from frame to frame so nothing pops. It also keeps parts out of `world` (any collider on `world_mask`, through Godot physics: one broad query around the body, precise capsule queries only near a collider) and out of `others` (other bodies' capsules). When the trunk or head can't bend out of the world, it shifts the whole model (`lift_node`, through its local position, at most `nudge_max` = 25 cm, at once, easing back); never against another body, where the model would drift from where its hits land. |

## Wrap file

`<thing>.collide.json` stores lengths in skeleton space, with the model at scale 1:

```json
{"version": 1, "kind": "collide",
 "pieces": [{"id": "handL", "bone": "handL", "a": [x, y, z], "b": [x, y, z], "r": 0.079, "rank": 5, "verts": 230}],
 "pairs": [["handL", "head", 0.0, 0.0]],
 "rules": {}}
```

Each pair is `[id1, id2, allow, soft]`:

- `allow`: how deep the two pieces overlap at rest, in skeleton space. That much is the model's own shape and never counts.
- `soft`: how much further they may press like flesh, in world metres.

## Use (City Breaker)

```gdscript
var solver := CBWraps.make_solver(skel, "vix", model_root)   # once
solver.solve(floor_y)       # every frame, right after the clip pose; NAN when no floor counts (in the air)
```

`CBAnim` does this in matches. Everything the game decides reads the clip's own pose, rebuilt relative to the fighter when asked
(`CBAnim.hit_world`, `CBFighter.hit_pos`): hits, hurt checks, held items' hit points (`CBItem._game_xf`), thrown and dropped
items, shots, grab holds. Only effects follow the pose you see.
In a match the solve also gets the stage's solid decks (layer 1; one-way platforms stay passable) and the other fighters'
wraps from their last solve (`CBWraps.others_for`, leaving out a grab partner). Toggles: `CBWraps.world_on` and `CBWraps.others_on`.
Spring chains collide with the body when they are built through `CBSecondary.build_specs` (colliders from
`CBWraps.spring_colliders`, then the last pass from `CBWraps.spring_guard`).
Set `CBWraps.enabled = false` to see the clips exactly as keyed.

## Tools (`game/packs/city_breaker/tools/`)

- **wrap_bake.gd:** bakes `data/wraps/<key>.collide.json` from each model, using the rules in `data/wraps/wrap_rules.json`.
- **body_clash.gd:** clash report for every clip and frame. Add `--solve` to run it with the Body Solve on.
- **wrap_sheet.gd:** pictures. Wrap sheet, `--shots=key:clip[:frame]`, or `--video=key:clip` for before/after frames.
- **axis_probe.gd:** shows which way each Euler axis turns a joint. Set joint limits from this, never by guessing.
- **spring_clash.gd:** tails, ears and crests with the springs simulating, free vs with the wrap.
- **match_clash.gd** (`.tscn`): real CPU vs CPU matches measured every frame (limbs in the stage, in the other body,
  trunks overlapping). One pair per run, with `--no-wraps` for the before.
- **wrap_check.gd:** the checks.
