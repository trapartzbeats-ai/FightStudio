# Fight Studio

A Godot 4.7 studio for authoring **animation, effects and sockets** on rigged fighters, with procedural body motion:

- **POSE**: bone sliders, key frames, proportional editing, mirror L/R, fist/open hands, knee-safety check. Clips are plain JSON (`data/clips/*.json`) built into `Animation` resources at load.
- **SOCKETS**: named points that ride a bone (point along a bone, offset, zone radius + falloff, ground and sole sockets), so effects always land on the right spot.
- **EFFECTS**: preview effects from the RMT Effects add-on, put **cues** on a clip's timeline, stack **combos**.
- **PAIR**: stage a victim next to the attacker and key its reaction on the same timeline (grabs, throws, finishers).
- **SECONDARY**: tails, ears, fingers, crests move by themselves (`SpringBoneSimulator3D`) with stiffness / drag / gravity per joint.
- **REACT**: IK-like hit reaction: the part of the victim a blow lands on moves with it, nearby bones follow in proportion, a spring settles it; the attacker recoils.
- Save, **Export GLB**, and **Bake** (the `animato/` scripts key studio clips into a GLB through headless Blender).

## What is here, and what is not

This is the **code and data format** only. It is lifted out of the City Breaker fighting-game pack of BSP Universe, and keeps that folder layout
(`game/packs/city_breaker/...`) so it drops into a project at the same paths. The characters, stages and the RMT Effects add-on are **not** included
(they belong to the game): you bring a rigged fighter (GLB with a `Skeleton3D` + `AnimationPlayer`, bones such as hips/torso/chest/head/armL/elbowL/handL/legL/kneeL/footL),
a `CBRoster`/`CBSave`/`CBFx` equivalent (this code calls `CBRoster.model_path(key)`, `CBSave.setting`, the `Rmtfx` autoload), and adapt the bone names in `data/*.json`.
`tools/` has headless checks (`studio_check`, `react_check`, `pair_check`) that need those assets.

Rig axis conventions the clips assume are written at the top of `clip_lib.gd` (a knee never bends forward: the Studio and the bake scripts enforce it).

`animato/` are scripts for Animato (a local FastAPI + headless Blender tool, patched here to use an installed Blender): `bpy_add_clips2.py` authors movement clips, `bpy_add_ears.py` adds ear/crest chains, `bake_studio_clips.py` bakes Studio clips. Paths inside are the author's; edit the constants at the top.

Never switch a pose bone's `rotation_mode` before a glTF export of a rig whose actions use quaternions: the actions export flat.

License: MIT.
