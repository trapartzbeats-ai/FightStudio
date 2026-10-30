# Fight Studio Desktop

The Fight Studio animation app as a desktop program (Electron + three.js), no Godot needed. It opens and saves the same clip
files the game plays (`<project>/game/packs/city_breaker/data/clips/<name>.json`), with the same interpolation, rules and file
format as the Godot **Fight Studio Animator** (`game/packs/city_breaker/animator`), so you can switch between the two on the same
clip. Fighters load straight from the game's GLBs (`assets/chars/<key>_fight.glb`); poses, rig controls and sockets are shared files.

## Install

Run `FightStudioDesktop-Setup-<version>.exe` (Windows 10 / 11, 64-bit). On first start it asks for the **game project folder**:
the Godot project with `game/packs/city_breaker` in it. File > Choose the game project folder changes it later.

The installer is not code-signed, so Windows SmartScreen may say "Windows protected your PC": click More info > Run anyway.

## Run from source

```
cd D:\Projects\FightStudioDesktop
npm install
npm start                          # or: node_modules\electron\dist\electron.exe .
npm start -- --fighter=carter --clip=a_jab1
npm run selftest                   # 116 checks, prints to out/desktop.log
npm run dist                       # builds dist/FightStudioDesktop-Setup-<version>.exe
```

Options: `--fighter=` `--clip=` `--project=<Godot project>` `--api-port=47651` `--no-api` `--windowed`
`--unfocusable` (a window that never takes your keyboard) `--shot=path.png` (screenshot and quit) `--verbose`.
`FIGHT_STUDIO_PROJECT` sets the project too, and `FIGHT_STUDIO_GODOT` the Godot exe for File > Open in the Godot Animator.

## What it does (the same as the Godot Animator)

- **Canvas**: 1, 2, 3, quad, the **strip** (front / three-quarter / side / back x moments of the clip, live, the review-sheet
  look) or quad + strip. Each view: Persp, Front, Three-Q, Side L / R, Back, Top, Follow; ORTHO; `[ ]` maximize. One WebGL
  renderer draws every view through scissor regions; View > Render scale supersamples for HD / 4K.
- **Posing**: ROTATE (swing a joint, or drag a coloured ring to turn about one axis, LOCAL / GLOBAL), MOVE (slide the body),
  IK (pull a hand / foot and the limb bends; pull any other joint and its parents bend), X-MIRROR. Every joint stays in its
  natural range (`data/animator_rig.json`): knees and elbows are hinges, and the IK bends them only on their hinge.
- **Keys**: K / AUTO KEY, eases (linear, in, out, inout, hold, spline), key types, lock keys, link keys, and **SAME KEY**
  (off / linked / same pose / same value): an updated key updates the same key elsewhere. Insert / delete frames, scale
  time, reverse, close loop, breakdowns.
- **Locks and freezing**: lock bones or single channels; FREEZE pins a bone in the world over a frame range.
- **Adjust**: tilt a part across the whole clip, a frame range or around one frame, without touching its keys (drag TILT,
  Shift for fine). Adjusted parts get a `*` in the Outliner; RESTORE takes an adjustment off; it never turns a joint past
  its limits.
- **Merge**: one animation from several. The open clip is the base; each clip on top gives only the parts you light up
  (Head, Spine, Arm L / R, Hands, Hips, Legs, Tail) from a start frame, blending in and out. BAKE makes one new clip and
  keeps the recipe, so REBUILD THE SETUP brings it back.
- **Fill**: the frames between two keys, made for you. SHAPE makes the move by the rules of good motion (timing smooth /
  even / strike / settle, Flow through the keys, Overlap, Anticipate, Overshoot); LIBRARY finds how your own clips make the
  same change (mirrored too) and bends it onto your two keys. Joints stay in their limits, planted feet stay put or step,
  keyed spins stay spins. The made frames are plain breakdown keys; once filled the knobs change it live; REMOVE gives the
  keys back. The same as the Godot Animator's Fill (its `FILL_PLAN.md` has the research and design).
- **Feet**: a planted clip stands each foot on its real sole (read off the model's mesh, the same as the game's
  `CBFeet.ground`): feet levelled, legs reached down with the knee's own bend, toes / heel pivots kept, nothing into the
  floor. The Feet panel shows per-foot lanes (flat / pivot / limit / sink / air) across the clip.
- **Motion import**: File > Import motion takes a Mixamo FBX (or a GLB / glTF with a Mixamo-style skeleton) onto our rig as
  a new clip: lined up from T-pose to our A-pose, in place, inside the joint limits, loop / planted detected.
- **Panels**: Clips, Poses (mirror, flip, copy / paste, pose library), Sockets (+ props, and grey grip proxies that sit in the
  hand by the game's grip frame), Properties, Controls (one slider, many bones; add your own), Adjust, Fill, Layers (keys / clip
  layers, add / add_delta / override, masks, fades), Constraints (IK, freeze, aim, limit, copy, floor / plant), Outliner,
  Checks, Dope Sheet, Graph, Blend Lab (transitions, mixes), Merge, Feet, Agents, History, Render (HD / Full HD / QHD / 4K
  stills, the review sheet, PNG sequences).
- **Windows**: drag a tab onto another dock; right-click a tab to float the panel in its own window (close it to dock it
  back); Window > New canvas window for a second monitor. Splitters between docks; the arrangement is remembered.
- **Saving**: Ctrl+S. The first save of a clip in a session backs the old file up (`fight_studio_backups`); clips "deleted"
  go to `fight_studio_trash`, and renders to `fight_studio_renders`, all under `D:/Cache` when it exists, otherwise
  `Documents/Fight Studio`. Live layers / constraints are baked into the game keys with the editable keys kept under
  `studio.base` (the same bake signature as the Godot app).
- **A saved clip is yours**: every save stamps `studio.saved`, and the game's clip generators (`gen_clips.py`, `gen_cast.py`,
  `gen_unique.py`) skip a clip that carries it. Delete the clip here (trash folder) to hand it back to them.

## Agents

The app serves the agent API on `http://127.0.0.1:47651/rpc` (localhost only; `GET /methods`), the same methods as the Godot
Animator on :47650, including merge, adjust, feet, fill, import_motion and the prop / grip calls. The MCP server ships with the game
project (`game/packs/city_breaker/animator/mcp/fight_studio_mcp.py`), finds whichever app is running (or set
`FIGHT_STUDIO_URL`), and `studio_launch(app="electron")` starts this one. Register it once:

```
claude mcp add -s user fight-studio -- python <project>/game/packs/city_breaker/animator/mcp/fight_studio_mcp.py
```

The Agents panel shows the MCP config with the server's path in the project you picked.

## Files

`main.js` (window, file access limited to the game's clip / pose / data folders, the project folder setting, pop-out windows,
the HTTP API), `preload.js`, `src/core/` (clip = the game's interpolation, doc, rig, evalc = layers + constraints + IK, body,
history, adjust, merge, feet, fill, grip, motion_import), `src/app.js` (every edit), `src/stage.js` (3D world), `src/views.js`
(canvas), `src/timeline.js` (dope sheet, graph), `src/panels.js`, `src/shell.js` (menus, bars, docks, windows), `src/api.js`,
`tests/selftest.js`, `build/` (the installer icon).

The heading font is Oswald (`src/fonts/oswald600.woff2`, SIL Open Font License).
