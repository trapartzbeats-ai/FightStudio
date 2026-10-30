# Fight Studio Desktop

The Fight Studio animation app as a desktop program (Electron + three.js), no Godot needed. It opens and saves the same
clip files the game plays (`D:/Games/BSP-Universe/game/packs/city_breaker/data/clips/<name>.json`), with the same
interpolation, rules and file format as the Godot **Fight Studio Animator**
(`game/packs/city_breaker/animator`), so you can switch between the two on the same clip. Fighters load straight from the
game's GLBs (`assets/chars/<key>_fight.glb`); poses, rig controls and sockets are shared files.

```
cd D:\Projects\FightStudioDesktop
npm start                          # or: node_modules\electron\dist\electron.exe .
npm start -- --fighter=carter --clip=a_jab1
npm run selftest                   # 45 checks, prints to out/desktop.log
```

Options: `--fighter=` `--clip=` `--project=D:/Games/BSP-Universe` `--api-port=47651` `--no-api` `--windowed`
`--unfocusable` (a window that never takes your keyboard) `--shot=path.png` (screenshot and quit) `--verbose`.

## What it does (the same as the Godot Animator)

- **Canvas**: 1, 2, 3, quad, the **strip** (front / three-quarter / side / back x moments of the clip, live, the review-sheet
  look) or quad + strip. Each view: Persp, Front, Three-Q, Side L / R, Back, Top, Follow; ORTHO; `[ ]` maximize. One WebGL
  renderer draws every view through scissor regions; View > Render scale supersamples for HD / 4K.
- **Posing**: ROTATE (swing a joint, or drag a coloured ring to turn about one axis, LOCAL / GLOBAL), MOVE (slide the body),
  IK (pull a hand / foot and the limb bends; pull any other joint and its parents bend), X-MIRROR, knees never bend forward.
- **Keys**: K / AUTO KEY, eases (linear, in, out, inout, hold, spline), key types, lock keys, link keys, and **SAME KEY**
  (off / linked / same pose / same value): an updated key updates the same key elsewhere. Insert / delete frames, scale
  time, reverse, close loop, breakdowns.
- **Locks and freezing**: lock bones or single channels; FREEZE pins a bone in the world over a frame range.
- **Panels**: Clips, Poses (mirror, flip, copy / paste, pose library), Sockets (+ props), Properties, Controls (one slider,
  many bones; add your own), Layers (keys / clip layers, add / add_delta / override, masks, fades), Constraints (IK, freeze,
  aim, limit, copy, floor / plant), Outliner, Checks, Dope Sheet, Graph, Blend Lab (transitions, mixes), Agents, History,
  Render (HD / Full HD / QHD / 4K stills, the review sheet, PNG sequences).
- **Windows**: drag a tab onto another dock; right-click a tab to float the panel in its own window (close it to dock it
  back); Window > New canvas window for a second monitor. Splitters between docks; the arrangement is remembered.
- **Saving**: Ctrl+S. The first save of a clip in a session backs the old file up to `D:/Cache/fight_studio_backups`; clips
  "deleted" go to `D:/Cache/fight_studio_trash`. Live layers / constraints are baked into the game keys with the editable
  keys kept under `studio.base` (the same bake signature as the Godot app). File > Bake clips into the fighter GLB runs
  Animato; File > Open this clip in the Godot Fight Studio Animator.
- **A saved clip is yours**: every save stamps `studio.saved`, and the game's clip generators (`gen_clips.py`, `gen_cast.py`,
  `gen_unique.py`) skip a clip that carries it. Delete the clip here (trash folder) to hand it back to them.

## Agents

The app serves the agent API on `http://127.0.0.1:47651/rpc` (localhost only; `GET /methods`), the same methods as the
Godot Animator on :47650. The MCP server
`D:/Games/BSP-Universe/game/packs/city_breaker/animator/mcp/fight_studio_mcp.py` finds whichever app is running (or set
`FIGHT_STUDIO_URL`), and `studio_launch(app="electron")` starts this one. Register it once:

```
claude mcp add -s user fight-studio -- python D:/Games/BSP-Universe/game/packs/city_breaker/animator/mcp/fight_studio_mcp.py
```

## Files

`main.js` (window, file access limited to the game's clip / pose / data folders, pop-out windows, the HTTP API),
`preload.js`, `src/core/` (clip = the game's interpolation, doc, rig, evalc = layers + constraints + IK, body, history),
`src/app.js` (every edit), `src/stage.js` (3D world), `src/views.js` (canvas), `src/timeline.js` (dope sheet, graph),
`src/panels.js`, `src/shell.js` (menus, bars, docks, windows), `src/api.js`, `tests/selftest.js`.
