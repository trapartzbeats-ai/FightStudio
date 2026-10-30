# Wiring RMT Wrap into a game

How City Breaker hooks the Collision Wrap in. The game files themselves (`anim.gd`, `fighter.gd`, `item.gd`, `shot.gd`) belong to the
game and aren't in this repo, so these are the parts that matter, taken from them.

## 1. Bake a wrap for each character

```
godot --headless --path . --script res://game/packs/city_breaker/tools/wrap_bake.gd [-- --who=vix]
```

It writes `data/wraps/<key>.collide.json` from the model's skin weights, with the rules in `data/wraps/wrap_rules.json` (merges,
ranks, soft pairs, chains, max turns, per-character overrides). Re-run it whenever a model changes. Joint ranges come from
`data/animator_rig.json` (`limits` + `hinge`).

## 2. Run the Body Solve right after the clip pose, every frame

In `CBAnim.update(f)`, after the clip pose is on the skeleton and the planted feet are on the floor:

```gdscript
# 1) keep the clip's own pose for the game logic, BEFORE the solve moves anything (relative to the character, so a teleport or a
#    push after posing carries it along)
_owner = f
_hit_rel = f.global_transform.affine_inverse() * skel.global_transform
_hit_pose.resize(skel.get_bone_count())
for i in skel.get_bone_count():
	_hit_pose[i] = skel.get_bone_global_pose(i)

# 2) the Body Solve: parts out of the body, the floor, the stage and the other characters
if CBWraps.enabled and f.model != null:
	if not _solver_tried:
		_solver_tried = true
		solver = CBWraps.make_solver(skel, f.key, f.model)    # f.model = the node it may lift / nudge (visual only)
	if solver != null:
		solver.world = f.get_world_3d().direct_space_state if CBWraps.world_on else null   # solid colliders (layer 1)
		solver.world_exclude = [f.get_rid()]
		solver.others = CBWraps.others_for(f) if CBWraps.others_on else []              # other characters' capsules
		solver.solve(f.global_position.y if planted_and_grounded else NAN)               # floor height, or NAN in the air
		wrap_caps = solver.body.capsules()                                               # what the others stay out of


## where the clip puts a bone this frame (world), before the Body Solve
func hit_world(i: int) -> Transform3D:
	if i >= 0 and i < _hit_pose.size() and _owner != null and is_instance_valid(_owner):
		return _owner.global_transform * _hit_rel * (_hit_pose[i] as Transform3D)
	return skel.global_transform * skel.get_bone_global_pose(i)
```

## 3. Everything the game decides reads the clip pose (this is the rule that matters)

The solve changes only what you see. Anything that decides the game reads the clip's own pose (`hit_world`), never the drawn
bones:

```gdscript
## on the character
func hit_pos(b: String) -> Vector3:
	var i := skel.find_bone(b)
	return anim.hit_world(i).origin
```

- Hitboxes and hurtboxes: `hitbox_world`, `limb_dir(bone, true)`, `hurt_segments` use `hit_pos`.
- Held items: draw the item in the visible hand, but keep a second transform in the clip's hand (`_game_xf`) for what it hits with
  and where it's thrown from.
- Thrown and dropped items, projectiles, grab holds: use `hit_pos`.
- Only effects (sparks, glints) follow the drawn bones.

Without this, a hand lifted out of the floor changes where a thrown item starts, and fights stop playing the same. City Breaker's
rules check (73 checks) caught exactly that.

## 4. Spring chains (tails, ears, crests)

Build them through `CBSecondary.build_specs(skel, specs, key)` (`secondary.gd`):
- Each chain gets the wrap's capsules as colliders (`CBWraps.spring_colliders`).
- A Body Solve that moves only the chains runs last (`CBWraps.spring_guard`, an `RmtWrapModifier`).

`collide = false` keeps the free springs.

## 5. Measure

| Tool | Measures |
|---|---|
| `tools/body_clash.gd` | Every clip, every frame. Add `--solve` to compare with the Body Solve on. |
| `tools/spring_clash.gd` | Springs, free vs wrapped. |
| `tools/match_clash.tscn` | Real CPU vs CPU matches. Run with `--no-wraps` for the before. |
| `tools/wrap_sheet.gd` | Pictures and before/after videos. |
| `tools/axis_probe.gd` | Which way each joint axis turns. |
| `tools/wrap_check.gd` | 34 checks. |

These tools need the game's characters and classes (`CBRoster`, `CBAnim`, `CBMatch`...), as the README says.

The plan, the decisions and every phase's results are in `game/packs/city_breaker/WRAPS_PLAN.md`. The before/after pictures and
videos are in `game/packs/city_breaker/reports/wraps_c0` to `wraps_c3`.
