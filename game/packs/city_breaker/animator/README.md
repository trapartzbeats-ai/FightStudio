# Fight Studio Animator

The animation app for City Breaker and the BSP Universe open world. It edits the same clip files the game plays
(`game/packs/city_breaker/data/clips/<name>.json`), so what you save is in the next fight or walk with no export step.
The old Studio (`studio/studio.tscn`: effects, pairs, secondary motion) is still there: **File > Open the old Studio**.

```
godot --path . res://game/packs/city_breaker/animator/animator.tscn  [-- --fighter=vix --clip=w_walk --layout=4]
```

Options after `--`: `--fighter=` `--clip=` `--layout=1|2|3|4|strip|4+strip` `--api-port=47650` `--no-api` `--windowed`
`--unfocusable` (a test window that never takes your keyboard) `--shot=path.png` (screenshot and quit).

## The screen

| Area | What it is |
|---|---|
| Menu bar | File, Edit, Key, Pose, Rig, View, Window, Agents, Help. Every item names its shortcut. |
| Tool bar | Fighter, the clip chip (`*` = unsaved), SELECT / ROTATE / MOVE / IK, LOCAL / GLOBAL axes, X-MIRROR, AUTO KEY, SAME KEY mode, ONION, TRAIL, layouts 1-4 / STRIP / 4+S, UNDO / REDO / SAVE. |
| Canvas | The views. 1, 2, 3, quad, STRIP (front / three-quarter / side / back x moments of the clip, live) or quad over a strip. Each view: camera preset (Persp, Front, Three-Q, Side L/R, Back, Top, Follow), ORTHO, `[ ]` maximize. Renders at your screen's real pixels (HD / 4K sharp; View > Render scale supersamples). |
| Transport | Play, step, key to key, frame, length, fps, LOOP, speed, play range IN / OUT / ALL, the key's ease, DEL KEY and the big KEY button (SET KEY between keys, UPDATE KEY on one, orange `*` when the pose changed and is not keyed). |
| Docks | Tabs you can drag between the left, right-top, right-bottom and bottom docks. Right-click a tab: float it in its own OS window (a second monitor), move it, hide it. Close a floated window to dock it back. Window > New canvas window opens more views in their own window. The arrangement is saved. |

## Posing (the views)

- **ROTATE (E)**: drag a joint to swing it in the view. Drag a coloured ring to turn about that axis only (red X, green Y,
  blue Z; LOCAL = the bone's axes, GLOBAL = the world's, X key). The outer white ring turns in the view plane.
- **MOVE (W)**: slide the whole body (hips shift); the arrows move along one axis.
- **IK (T)**: pull a hand or foot and the limb bends to reach (the hand / foot keeps its angle). Pull any other joint (head,
  chest, tail tip, a finger) and up to three parents bend (CCD).
- Right-drag orbit, middle-drag pan, wheel zoom, double-click a joint to frame it, `` ` `` maximizes the view under the mouse.
- **X-MIRROR (M)**: an edit on one side is mirrored to the other side as you make it.
- Knees never bend forward: every tool clamps the rig limits (`data/animator_rig.json`, kneeL / kneeR X >= 0).

## Keys, frames, and "the same key"

- **K** keys the pose (in-betweens interpolate with the game's own `CBClipLib.pose_at`). **AUTO KEY (N)** keys every edit.
  Changing frame drops an unkeyed edit (the status bar says so); **Esc** throws it away.
- **Ease** per key: linear, in (whips into the next pose: strikes), out (settles), inout, hold, spline (cycles).
- **Key types**: key (gold), breakdown (blue), extreme (red) - right-click keys in the dope sheet.
- **SAME KEY mode** (tool bar or Key menu): when you update a key, the same key elsewhere takes the same change.
  `linked` = keys you linked (Key > Link: one pose on many frames), `pose` (default) = keys holding the same pose (a loop's
  first and last key, a stance you come back to), `value` = per bone, keys holding the same value for that bone. A new loop
  clip starts with its first and last key linked; **Key > Close loop** does it for any clip.
- **Lock a key** (right-click) and nothing can change, move or delete it.
- Frames: insert / delete frames at the current frame, scale time (whole clip or selected keys), reverse selected keys.
- **Breakdown** (Pose panel slider or Pose menu): an in-between leaning toward the previous or next key.

## Locks and freezing

- **Lock a bone** (L, the Outliner's LOCK column, or Properties per channel X / Y / Z): no tool can turn it - yours, mirror,
  paste, controls, IK, agents.
- **Freeze a bone in the world** (Rig > Freeze, Constraints > FREEZE SEL): a pin constraint holds the bone where it is at a
  frame (a planted foot while the body moves, a hand on a wall). Hands / feet bend their limb to stay put.

## Panels

| Panel | Use |
|---|---|
| Clips | Every clip (search, filters: mine / world `w_` / moves `a_` / this fighter's own / baked GLB animations). Open, New, Duplicate, AS LAYER, TO TRASH (`D:/Cache/fight_studio_trash`, never deleted). |
| Properties | The selected bone's X / Y / Z (degrees) with per-channel locks, mirror to the other side, body move (hips shift), this key's ease / type / lock, clip settings (plant feet, override, default ease, note), the move's hit / clear marks and your markers. |
| Controls | One slider drives many bones: Fist L / R, Spine bend / twist / side, Head look / nod, Crouch, Guard up, Tail curl / sway, Ears back. The slider reads the pose. Add your own (bone, axis, amount), SAVE CONTROLS. |
| Fill | The frames between two keys, made for you: by the rules of good motion (SHAPE) or from how your own clips make the same change (LIBRARY). See Filling between keys. |
| Layers | KEYS layers (tweak an arm without touching the base keys; KEYS GO HERE makes K key into it) and CLIP layers (blend another clip in). Modes add / add_delta / override, weight, mute / solo, bone masks (Upper body, Arms, Legs...), range with fade in / out, offset / speed / cycle. |
| Constraints | IK arm / leg (target fixed, keyed, or on a bone), FREEZE (pin), AIM (head follows a point), LIMIT, COPY rotation, FLOOR / PLANT. Influence, range, blend frames, order. BAKE ALL INTO KEYS. |
| Outliner | Bones by body part with lock ticks and key counts; click a group to select it all. |
| Poses | Mirror L>R / R>L, flip, copy / paste (mirrored), reset, the breakdown slider, and the pose library (`data/poses`): save whole or selected bones, apply whole / on selected / mirrored, blended by weight. |
| Sockets | The fighter's sockets (pink diamonds): bone, offset, ground; save for all fighters or this one. Props (bat, blade, ball, can, phone, box) held at a socket while you animate - stored in the clip, never in the game. |
| Dope Sheet | Ruler (scrub; markers, hit / clear marks, effect cues), ALL KEYS (drag to retime, ease bars, purple arcs = linked keys), layer and constraint ranges, a row per bone. Shift-click, box-select, drag, right-click menu. Ctrl + wheel zooms, middle-drag pans. |
| Graph | The selected bone's X / Y / Z curves in degrees (or the hips shift in cm), dashed = the final motion after layers and constraints. Drag a key point up / down to change it, sideways to retime. |
| Blend Lab | Transitions (this clip, then B crossfading in at a frame: as a layer, or as a new clip) and mixes (B on some bones, or B's motion added on top). |
| Agents | The agent API address, the MCP config to copy, and a log of every agent call. |
| History | Every change, newest first; `[agent]` marks an agent's. Double-click undoes back to that step. |
| Checks | Knees bending forward, joints past limits, the loop seam, planted feet sliding, unkeyed edits. Click a finding to jump there. |
| Render | Stills of a view, the four-angle review sheet, or a PNG sequence at HD, Full HD, QHD, 4K, square or vertical, to `D:/Cache/fight_studio_renders`. |

## Saving

**Ctrl+S** writes `data/clips/<name>.json`. The first save of a clip in a session backs the old file up to
`D:/Cache/fight_studio_backups`. With live layers or constraints the game keys are **baked** (a key on every frame) and your
editable keys ride along under `"studio": {"base": [...]}` with the layers, constraints, locks, markers and props. If those
game keys are later changed somewhere else (the old Studio, a `gen_*.py` script), the Animator takes them as the base and
switches the layers / constraints off, so nothing is lost silently. **File > Bake clips into the fighter GLB** runs Animato
(`D:/Projects/Animato/bake_studio_clips.py`, headless Blender; the original GLB is kept in `D:/Cache/chars_before_studio`).

**A saved clip is yours.** Every save stamps `"studio": {"saved": "<date time>"}`, and the clip generators (`tools/gen_clips.py`,
`gen_cast.py`, `gen_unique.py`) skip any clip that carries it, so re-running them never writes over work done here (they print
the clips they kept). To hand a clip back to the generators, delete it here (it goes to `D:/Cache/fight_studio_trash`) and run
`python tools/gen_cast.py`.

## Importing motion (Mixamo)

**File > Import motion (Mixamo FBX, GLB)...** brings any Mixamo animation onto our rig as a new clip. It works on every
fighter: the clip uses our bones. Pick the file, then choose:
- **Name:** from the file name, e.g. `mx_capoeira_spin_kick`.
- **In place** (on): the straight-line travel comes out of the hips, because the game moves the fighter. The speed is kept in
  the clip's `"import"` block.
- **Rig limits** (on): every joint stays inside `data/animator_rig.json`'s limits, so knees never bend forward.
- **Fingers** (on): the finger motion comes too, on fighters that have those finger bones.

The clip opens **unsaved**: play it, check the strip, fix what you like, then Save.

How it works (`core/motion_import.gd`, `FSAMotionImport`):
- **Motion:** each of our bones takes its Mixamo bone's turn away from Mixamo's rest pose, in world space.
- **Rest poses:** Mixamo rests in a T-pose and we rest in an A-pose, so each bone is first lined up with its Mixamo bone.
- **Hips:** scaled by the two rigs' hips height.
- **Sides:** Mixamo's Left is our R. Both rigs face +Z.
- **Loop and planted:** set when the clip looks like one.
- **Keys:** a key is dropped when a straight line between its neighbours already gives it.

Mixamo: download **Without Skin** (with skin works too), at any frame rate. GLB and glTF files with a Mixamo-style skeleton
work the same way. Agents: `studio_import_motion(path, ...)`. Checks: `tools/motion_import_check.gd` imports test files onto
Vix, Carter and the Bill Collector and compares every limb's direction with the source (about 1 degree on average).

## Adjusting a part (Adjust panel)

Tilts a body part on top of its keys, without changing them. Use it to raise the shoulders on every frame of a walk,
straighten an arm, bring the hands together for a clap, or take a fist out of the face.

1. **Pick the part.** Click it in a view, or choose it in **part**. Tick **both sides** to give the other side the same turn,
   mirrored. The line under it says what X, Y and Z do for that part.
2. **Pick where it applies:**
   - **all frames**
   - **around this frame**: eases over **ease** frames each side; ease 0 means that frame only.
   - **frame range**: from / to, easing inside each end. **PLAY RANGE** uses the IN / OUT range.
3. **Turn it.** Press **< TILT >** on an axis and drag left or right (hold Shift for fine steps), or type the degrees.
   - The value is the total turn of that adjustment; **0** clears an axis.
   - One drag is one undo step.

Adjusted parts get a **\*** in the Outliner and are listed under **Adjusted**:
- **RESTORE** takes one off, and **RESTORE ALL** takes them all off. The keys come back exactly as they were.
- **APPLY INTO KEYS** bakes them into the clip.

An adjustment never turns a joint past its rig limits, so knees never bend forward. Where the clip itself is already past a
limit, the adjustment won't push it further. Each adjustment is an add layer tagged `adjust` (`core/adjust.gd`, `FSAAdjust`).
Agents use `studio_adjust(bone, x, y, z, scope, frame, start, end, ease, mirror)` and `studio_adjust_restore(bone)`.

## Filling between keys (Fill panel)

Makes the frames between two keys for you, so two good poses become a move. The made frames are plain keys (type
**breakdown**, blue in the Dope Sheet): the game plays them as they are, and you can still edit any of them.

1. **Pick the span.** Put the playhead between two keys (2 frames apart or more), or tick **play range** to use IN / OUT.
   Inside a fill, the span is the whole fill.
2. **Pick the engine:**
   - **SHAPE** makes the move by the rules of good motion:
     - **timing**: *smooth* (eases in and out), *even*, *strike* (slow start, hits the end pose fast), *settle* (fast start,
       eases into it).
     - **Flow**: carries the speed the motion has coming into the first key and going out of the last, so it doesn't stop at
       the keys.
     - **Overlap**: each joint trails the one it hangs from and catches up by the end: the hand after the arm, the arm after
       the chest, the tail after the hips. Legs don't trail.
     - **Anticipate**: a small wind-up the other way first.
     - **Overshoot**: goes a little past the end pose and settles onto it.
   - **LIBRARY** looks through every clip (mirrored too) for the stretch that best joins the two poses, plays it at your
     span's length and bends it so it starts and ends exactly on your keys. **SEARCH** lists the matches with a score and how
     many frames that change took there (a hint for your span's length). Under 50% it says the match is weak: SHAPE will
     usually do better.
3. **FILL.** Once a span is filled, every knob changes it live (one undo step while you drag).

On every fill:
- Every joint stays inside its natural range: knees never bend forward.
- **hold planted feet** (planted clips): a foot standing at both keys stays on its spot (leg IK, flat). A standing foot the
  keys move takes a step on an arc instead of sliding. In a spin (the hips turn a lot) a held foot pivots on its spot.
- A turn keyed past half a circle (a spin kick) stays a spin, the way the game plays the keys.
- **air** (cm): the hips go up on a jump arc that high in the middle.
- **key every** N frames (0: every 2 at 60 fps, every frame at 30).

**REMOVE** takes a fill out: its keys go and the keys around it are as they were. **Filled** lists every fill on the clip
(GO puts the playhead in it). The settings are saved with the clip (`"studio": {"fills": [...]}`), so a fill can still be
changed or removed after a save. `core/fill.gd` (`FSAFill`); the research and design are in `FILL_PLAN.md`. Agents use
`studio_fill(start, end, engine, timing, flow, overlap, anticipate, overshoot, feet, air, step, pick)`,
`studio_fill_matches` and `studio_fill_remove`.

## Merging clips (Merge panel)

Builds one animation from several, like layering clips in Blender's NLA editor with some parts muted. The **open clip is
the base** and gives the body.

1. **Put clips on top.** Search, then **PUT ON TOP**. The clip starts at the current frame and gives the arms and hands.
2. **Pick its parts.** Light up the chips on its row (**Head, Spine, Arm L, Arm R, Hands, Hips, Legs, Tail**) for the parts
   that come from that clip.
3. **Place and blend it.**
   - **start f**: where the clip's frame 0 lands (**NOW** uses the current frame).
   - **blend in** / **out**: frames to fade over.
   - **weight**, **loop it** (repeat it to the end), **mute**.
4. **Play** to see it. A looping base, like a walk or a run, repeats under clips that run longer. The bake covers the full
   length; the timeline shows the base's own length.
5. **BAKE INTO ONE CLIP** makes a new clip, opened unsaved:
   - The keys are thinned, so it stays editable.
   - The base clip is not changed.
   - The recipe is stored in the new clip, so **REBUILD THE SETUP** opens its base with the clips on top again.

Each clip on top is an ordinary override layer tagged `merge`, so the Layers panel shows it too (`core/merge.gd`, `FSAMerge`).
Agents use `studio_merge(clips=[{"clip", "parts", "start", "blend_in", "blend_out"}], base=..., name=..., bake=True)`.

## Feet on the floor (Feet panel)

The match stands every planted clip on the fighters' real soles (`feet.gd`, `CBFeet`). The views show it too, with
View > Game feet on. The models are not all level at rest. Carter, Al, Guru, Hype and Vic were built in a stance: one foot
turned out, lower than the other, and its sole up to 24 degrees off level. So the ankle bone and the rest pose don't say
where a sole is. Instead, each foot's sole is read off the mesh: its plane, the ankle's height over it, and its contact
points at every tilt. On every frame of a planted clip:

1. **Level.** Each standing foot is levelled on its own sole, keeping where its toes point.
   - A foot the clip keys onto its toes or heel (ankle 17 to 34 degrees or more from rest) keeps that and pivots on it.
   - So does a foot the leg can't put flat there (a back leg stretched out behind).
2. **Limits.** Ankles stay inside their natural turn. In a deep crouch the heel lifts instead of the ankle over-bending.
3. **Body.** The body is raised or lowered so the lower sole, not the ankle, is on the floor.
4. **Legs.** The legs reach each standing foot onto the floor.
   - The knee keeps the clip's own bend and never goes straighter than its rest bend.
   - When a leg can't reach, the body comes down a little.
   - No foot ever goes into the floor.

A foot well off the floor (a kick, a step) keeps exactly what the clip keys.

The **Feet** panel (bottom dock) shows how the feet stand on each frame:

- **Lanes**, one per foot: green = flat, amber = pivot, violet = heel up at the ankle's limit, red = into the floor,
  grey = off the floor. Click a lane to go to that frame.
- A line for the current frame.
- The model's own sole facts.
- **planted**: the clip's plant flag. Turn it on for ground clips and off for air clips.

Agents use `studio_feet` (API `feet`).

The soles are baked in `data/feet_soles.json` (`tools/feet_bake.gd`). Run that again after a model changes. A stale entry is
ignored and the mesh is read again; that's just slower (50 to 330 ms per model).

Proof: `tools/feet_probe.gd` measures every fighter's planted clips on the mesh, before and with `--ground`.
`tools/feet_shot.gd` renders a before / after strip. `tools/feet_check.gd` holds the rules (79 checks).

## Agents (MCP)

The app serves a JSON API on `http://127.0.0.1:47650/rpc` (localhost only; `GET /methods` lists every method). The MCP
server `mcp/fight_studio_mcp.py` wraps it (and the Electron Fight Studio Desktop on :47651):

```
claude mcp add -s user fight-studio -- python D:/Games/BSP-Universe/game/packs/city_breaker/animator/mcp/fight_studio_mcp.py
```

Tools: `studio_launch`, `studio_state`, `studio_rig`, clips (`list / open / new / get / set / save`), `studio_set_pose`
(degrees, keys by default, mirror), `studio_ik_pose`, `studio_key`, `studio_keys` (list / delete / move / set / link /
unlink), `studio_set_key_values`, `studio_set_propagate`, `studio_frames`, `studio_pose_tool`, `studio_poses`,
`studio_controls`, `studio_layers`, `studio_constraints`, `studio_freeze`, `studio_lock`, `studio_sockets`,
`studio_screenshot` (returns the picture: the four-angle sheet, a view or the window), `studio_view`, `studio_checks`,
`studio_transition`, `studio_undo`, `studio_history`, `studio_say`, `studio_bake_glb`, `studio_import_motion`, `studio_merge`,
`studio_adjust`, `studio_adjust_restore`, `studio_feet`, `studio_fill`, `studio_fill_matches`, `studio_fill_remove`, and
`studio_call` for anything else.
Agent edits go through the same undo and show live (a purple frame and AGENT EDITING in the views).

## Checks

```
godot --headless --path . --script res://game/packs/city_breaker/animator/tests/animator_check.gd
```
151 checks: Euler order, mirror, limits, keys, undo / redo, retime, frames, locked keys and channels, linked and same-pose
propagation, keys / clip layers, IK on target, a frozen foot staying put, bake, save round trip, outside-edit detection,
Merge, Adjust, Feet, Fill (timings, flow, overlap, anticipate, overshoot, feet held and stepped, a spin, the library) and
the agent API.

## Files

`animator.gd` (the app: every edit goes through it), `core/` (doc = the clip, eval = layers + constraints + IK, history,
rig = groups, mirror, limits, controls, fill = the in-betweens), `ui/` (stage = the 3D world, view, canvas, strip, dock, dope sheet, graph, panels,
menus, toolbar, theme), `api/` (server + methods), `mcp/` (the MCP server), `tests/`. Data it writes: `data/clips`,
`data/poses`, `data/animator_rig.json`, `data/sockets.json` (when you save sockets).
