# Fight Studio

Tools for animating rigged fighters, from the City Breaker fighting game in BSP Universe. There are three parts that share one clip
format (`data/clips/<name>.json`), so a clip made in one opens in the others:

| Part | Where | What it is |
|---|---|---|
| **Fight Studio Animator** | `game/packs/city_breaker/animator/` | The animation app, in Godot 4.7. |
| **Fight Studio Desktop** | `desktop/`, installer on [Releases](https://github.com/trapartzbeats-ai/FightStudio/releases) | The same app as an Electron + three.js desktop program, no Godot needed. |
| **fight-studio MCP** | `game/packs/city_breaker/animator/mcp/` | An MCP server that lets agents animate in either app. |
| **RMT Wrap** | `addons/rmt_wraps/`, `game/packs/city_breaker/wraps.gd` | Collision Wrap: body parts never go through their own body, the floor, the stage or another fighter. |

The original **Fight Studio** (sockets, effects, pairs, secondary motion, hit reactions) is also here, in `game/packs/city_breaker/studio/`.

## Fight Studio Animator (Godot)

```
godot --path . res://game/packs/city_breaker/animator/animator.tscn  [-- --fighter=vix --clip=w_walk --api-port=47650]
```

**Canvas**
- Views: 1, 2, 3 or 4 at once, each with its own camera (Front, Three-Q, Side, Back, Top, Persp, Follow).
- **Strip**: front / three-quarter / side / back rows across the whole clip, live as you edit.
- Renders at full screen resolution, sharp in HD and 4K.

**Posing**
- **Rotate**: rings for one axis at a time, local or global, or swing a joint by dragging it.
- **Move** the body, or pull a hand or foot with **IK**.
- X-mirror editing.
- Every joint has a natural range (`data/animator_rig.json`): knees and elbows are hinges, and a knee never bends forward.

**Keys and frames**
- Eases: linear, in, out, smooth, hold, spline.
- **Same key**: an updated key updates the matching keys elsewhere in the clip (linked keys, the same pose, the same value).
- Insert or delete frames, retime, reverse, close a loop, make breakdowns.

**Locks and freeze**
- Lock whole bones or single X/Y/Z channels.
- Freeze pins a bone in the world over a range of frames (a planted foot while the body moves).

**Rig tools**
- **Constraints**: IK, freeze, aim, limit, copy rotation, floor / plant.
- **Controls**: one slider moves many bones (fist, crouch, guard...), and you can add your own.
- **Sockets** with stand-in props (bat, blade, ball) attached while you animate.

**Blending and building clips**
- **Layers**: add, add-delta or override, with bone masks and fades.
- **Blend Lab**: transitions from one clip into another.
- **Merge**: one animation built from several.
- **Adjust**: tilt one part across the whole clip.
- **Fill**: the frames between two keys, made for you: by the rules of good motion (timing, flow, overlap, anticipation,
  overshoot) or from how your own clips make the same change. Joints stay in their limits, planted feet stay put or step,
  keyed spins stay spins.
- **Feet**: stand on the real soles.
- **Motion import**: bring Mixamo motion onto the rig.

**Windows**
- Toolbars, a dope sheet and a graph editor.
- Panels dock anywhere or pop out into their own window, and you can open extra canvas windows.

**Saving**
- The first save of a clip backs up the old file, and "deleted" clips go to a trash folder.
- Every save stamps `studio.saved`, so the game's clip generators leave that clip alone.

**Agent API**: `http://127.0.0.1:47650/rpc` (localhost only). Agent edits show live in the app and undo like yours.

**Checks**: `godot --headless --path . --script res://game/packs/city_breaker/animator/tests/animator_check.gd -- --no-api`

**Running from the Godot editor**: with Embed Game on, the editor owns the window, and dialogs open inside the app.

The full manual is `game/packs/city_breaker/animator/README.md`.

## Fight Studio Desktop (Electron)

**Install (Windows 10 / 11, 64-bit):** download `FightStudioDesktop-Setup-1.2.0.exe` from the
[Releases](https://github.com/trapartzbeats-ai/FightStudio/releases) page and run it.
- On first start it asks for the game project folder: the Godot project with `game/packs/city_breaker` in it. File > Choose
  the game project folder changes it later.
- The installer is not code-signed, so SmartScreen may say "Windows protected your PC": click More info > Run anyway.

**From source:**

```
cd desktop
npm install
npm start            # -- --fighter=carter --clip=a_jab1 --project=<your Godot project>
npm run selftest     # 116 checks
npm run dist         # builds dist/FightStudioDesktop-Setup-<version>.exe
```

- Same file format, interpolation, rules and bake signature as the Godot app.
- The same tools too: Adjust, Merge, Fill (its keys match the Godot app's), Feet (real soles, matched to the game's `CBFeet`
  within 2 mm), Mixamo motion import (matched limb by limb to the Godot import), real finger limits and grip proxies.
- Loads fighters straight from the game's GLBs.
- Agent API on `:47651`.
- File access is limited to the project's clip, pose and data folders. Backups, trash and renders go to
  `Documents/Fight Studio` (or `D:/Cache` when that folder exists).

## fight-studio MCP

```
claude mcp add -s user fight-studio -- python game/packs/city_breaker/animator/mcp/fight_studio_mcp.py
```

It finds whichever app is running (`:47650` or `:47651`, or `FIGHT_STUDIO_URL`). Tools, all `studio_*`:

- `launch`, `open`, `new`, `save`
- `get_pose` / `set_pose` (degrees), `ik_pose`, `key`, `keys`, `frames`
- `controls`, `layers`, `constraints`, `freeze`, `lock`, `sockets`
- `screenshot` (the four-angle review sheet), `checks`, `transition`, `undo`, `bake_glb`
- `import_motion`, `merge`, `adjust`, `feet`, `fill`, `fill_matches`, `fill_remove`

## RMT Wrap: the Collision Wrap

Shapes fitted to the real models instead of hand-placed boxes:

- **The wrap**: each character gets 15 to 25 capsules, baked from its skin weights to sit just inside the skin
  (`data/wraps/<key>.collide.json`, `tools/wrap_bake.gd`).
- **The Body Solve** (`addons/rmt_wraps/body_solve.gd`) runs every frame after the clip pose:
  - A part that went into the body, the floor, the stage or another character bends back out at its own joints, shoulder first.
  - Every joint stays inside its natural range, and planted feet stay put.
  - Fixes ease in and out over a few frames, so nothing pops.
- **Springs**: tails, ears and crests bounce off the body.
- **Visual only**: everything the game decides reads the clip's own pose, so fights play exactly as before.

Results on City Breaker's 11 fighters (`WRAPS_PLAN.md`, pictures and videos in `reports/wraps_c0` to `wraps_c3`):
- Parts more than 5 cm into the body, across all clips: 2,590 → 276.
- Spring chains inside the body: down to 0 for four of the eight characters with chains.
- In real matches, limbs in the stage: up to 1,091 → 24 frames per 30 seconds of fighting.

How to wire it into a game: `addons/rmt_wraps/INTEGRATION.md`.

## What is here, and what is not

This is the **code and data format** only. It is lifted out of the City Breaker pack and keeps its folder layout
(`game/packs/city_breaker/...`), so it drops into a project at the same paths.

The characters, stages and the RMT Effects add-on are **not** included; they belong to the game. You bring:
- A rigged fighter: a GLB with a `Skeleton3D` and an `AnimationPlayer`, with bones such as hips/torso/chest/head/armL/elbowL/handL/
  legL/kneeL/footL.
- `CBRoster`, `CBSave` and `CBFx` equivalents (the code calls `CBRoster.model_path(key)`, `CBSave.setting` and the `Rmtfx` autoload).
- Bone names adapted in `data/*.json`.

`tools/` has headless checks (`studio_check`, `react_check`, `pair_check`) that need those assets.

Rig axis conventions are at the top of `clip_lib.gd`, and the joint ranges in `data/animator_rig.json` were checked by turning each
joint on each axis.

`animato/` holds scripts for Animato, a local FastAPI + headless Blender tool:
- `bpy_add_clips2.py` authors movement clips.
- `bpy_add_ears.py` adds ear and crest chains.
- `bake_studio_clips.py` bakes Studio clips into a GLB.

Paths inside the code are the author's (`D:/Games/BSP-Universe`, `D:/Cache`...); edit the constants at the top.

Never switch a pose bone's `rotation_mode` before a glTF export of a rig whose actions use quaternions: the actions export flat.

License: MIT.
