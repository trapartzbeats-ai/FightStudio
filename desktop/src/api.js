// The agent API (port :47651 through main.js): the same methods as the Godot Animator's api.gd, so the one MCP server drives
// either app. Rotations in DEGREES, positions in METRES, the fighter at the origin facing +Z (R bones on +X, L on -X).
import * as THREE from "three";
import * as R from "./core/rig.js";
import * as E from "./core/evalc.js";
import { poseOfKey } from "./core/doc.js";
import { DEG, RAD, v3, dist3 } from "./core/clip.js";

export const METHODS = {
  ping: "-> 'pong'", state: "what is open", rig: "bones, axes, limits, limbs, masks, controls, sockets, rules", list_fighters: "", set_fighter: "{fighter}",
  list_clips: "{filter?}", open_clip: "{name, discard?}", new_clip: "{name, frames=30, fps=30, loop=false, from_pose=true, overwrite?}", save: "{}", save_as: "{name}",
  get_clip: "{} (rot in degrees)", set_clip: "{frames?, fps?, loop?, plant?, override?, ease?, note?, marks?}", set_frame: "{frame}",
  get_pose: "{frame? (number or list), bones?, final?: true, world?: false}", set_pose: "{frame?, bones: {name: [x,y,z] deg}, hips?: {dx,dy,dz}, mode?: set|add, key?: true, mirror?}",
  ik_pose: "{bone, target: [x,y,z], frame?, key?: true, keep_end?: true}", key: "{frame?, ease?, tag?}", list_keys: "{}", delete_keys: "{frames}", move_keys: "{frames, delta}",
  set_keys: "{frames, ease?, tag?, lock?}", set_key_values: "{frame, bones: {..deg}, hips?}", link_keys: "{frames}", unlink_keys: "{frames}", same_keys: "{frame}",
  set_propagate: "{mode: off|linked|pose|bone}", insert_frames: "{at, count}", delete_frames: "{at, count}", scale_time: "{factor, frames?}", reverse: "{from, to}", close_loop: "{}",
  mirror_pose: "{mode: l2r|r2l|flip, frame?, key?}", reset_bones: "{bones, frame?, key?}", breakdown: "{t, frame?, key?}", list_poses: "{}", save_pose: "{name, bones?}",
  apply_pose: "{name, frame?, bones?, weight?, mirror?, key?}", list_controls: "{frame?}", set_control: "{name, value, frame?, key?}", add_control: "{name, min?, max?, drives}",
  list_layers: "{}", add_layer: "{...}", set_layer: "{id, ...}", remove_layer: "{id}", set_active_layer: "{id}", list_constraints: "{}", add_constraint: "{type, ...}",
  set_constraint: "{id, ...}", remove_constraint: "{id}", freeze: "{bone, from?, to?, what?}", bake_to_keys: "{}", lock: "{bones, channels?}", unlock: "{bones}",
  list_sockets: "{}", add_marker: "{frame, name}", set_view: "{layout?, index?, preset?, ortho?, onion?, tool?, bone?}", screenshot: "{target: window|view|sheet, width?, height?, cols?, path?}",
  checks: "{}", transition_clip: "{clip_b, at, blend, name}", undo: "{}", redo: "{}", history: "{}", say: "{message}", bake_glb: "{}",
};

const deg3 = (e) => e.map((x) => Math.round(x * DEG * 100) / 100);
const rad3 = (a) => v3(a).map((x) => x * RAD);
const m3 = (p) => [p.x, p.y, p.z].map((x) => Math.round(x * 10000) / 10000);
const ints = (a) => (a || []).map((x) => Math.round(Number(x)));

export function makeApi(app) {
  const who = "agent";
  const go = (p) => { if (p.frame !== undefined && !Array.isArray(p.frame)) { app.playing = false; app.setFrame(Number(p.frame)); } };
  const maybeKey = (p) => (p.key !== false ? app.keyNow("", who) : { frame: Math.round(app.frame), keyed: false });

  const D = {
    ping: () => "pong",
    state: () => ({ fighter: app.fighter, clip: app.doc.name, frame: app.frame, frames: app.doc.frames, fps: app.doc.fps, loop: app.doc.loop, plant: app.doc.plant,
      keys: app.doc.keyFrames(), layers: app.doc.layers.length, constraints: app.doc.constraints.length, unsaved: app.history.dirty(), new: app.isNew,
      selected_bone: app.selBone, selected_bones: app.selBones, tool: app.tool, active_layer: app.activeLayer, propagate: app.propagate, autokey: app.autokey,
      layout: app.views.main.layout, pending_unkeyed_edit: !!app.pending, outside_edit: app.doc.outsideEdit }),
    rig: () => {
      const body = app.stage.probe;
      body.apply({});
      return { fighter: app.fighter, height_m: Math.round(app.stage.height * 100) / 100,
        bones: app.bones.map((b) => ({ name: b, parent: body.parentName(b), group: R.groupOf(b), side: R.sideOf(b), mirror: R.mirrorName(b), axes: R.hint(b),
          limits_deg: Object.fromEntries(Object.entries(R.rigData.limits[b] || {}).map(([k, v]) => [k, v.map((x) => Math.round(x * DEG * 10) / 10)])),
          locked: app.doc.lockChannels(b), rest_world: m3(body.worldPos(b)) })),
        limbs: R.LIMBS, masks: Object.keys(R.MASKS), controls: R.rigData.controls.map((c) => c.name), sockets: Object.keys(app.sockSpecs),
        space: "world metres, fighter at the origin facing +Z (the Front view looks at its face), up is +Y; this rig's R bones sit on +X, L bones on -X",
        rotation: "per bone Euler degrees [x, y, z] on top of the rest, applied Z * Y * X (Blender XYZ); a bone missing from a key is at rest",
        rules: ["a knee never bends forward: kneeL / kneeR X stays >= 0 (the tools clamp it)", "thigh (legL / legR) X negative = leg forward; knee X positive = bends; foot X positive = toes down",
          "arm X negative = raised forward; elbow X negative = bends; armL Z negative / armR Z positive = arm out to the side", "torso / chest / head X positive = lean / nod forward; Y = twist; Z = side lean",
          "spins and flips turn the hips; hips dy moves the body up / down", "rolls reuse Vix's escape roll (City Breaker rule)", "fingers / tips / thumb close the whole hand"],
        workflow: "open_clip or new_clip -> set_pose / ik_pose / apply_pose / set_control (each keys by default) -> screenshot target=sheet -> checks -> save" };
    },
    list_fighters: () => app.fighters,
    set_fighter: async (p) => (app.fighters.includes(p.fighter) ? { ok: await app.setFighter(p.fighter) } : { error: "fighters: " + app.fighters.join(", ") }),
    list_clips: (p) => app.listClips(p.filter || ""),
    open_clip: async (p) => {
      if (app.history.dirty() && !p.discard) return { error: `the open clip ${app.doc.name} has unsaved changes: save first, or pass discard: true` };
      return (await app.openClip(String(p.name || ""), true)) ? { opened: app.doc.name } : { error: "no clip named " + p.name };
    },
    new_clip: async (p) => {
      if (app.history.dirty() && !p.discard) return { error: `the open clip ${app.doc.name} has unsaved changes: save first, or pass discard: true` };
      if ((await window.host.clipExists(String(p.name))) && !p.overwrite) return { error: `a clip named ${p.name} exists (open it, or pass overwrite: true)` };
      if (!app.newClip(String(p.name || ""), Number(p.frames || 30), Number(p.fps || 30), !!p.loop, p.from_pose !== false, who)) return { error: "bad name (letters, digits, _ and -)" };
      return { created: app.doc.name, frames: app.doc.frames, fps: app.doc.fps };
    },
    save: () => app.save(who),
    save_as: (p) => app.saveAs(String(p.name || ""), who),
    get_clip: () => ({ ...app.doc.toDict(), saved: app.doc.saved, keys: app.doc.keys.map((k) => ({ ...k, rot: Object.fromEntries(Object.entries(k.rot || {}).map(([b, e]) => [b, deg3(e)])) })), units: "rot in degrees; hips_* in metres" }),
    set_clip: (p) => { for (const k of ["frames", "fps", "loop", "plant", "override", "ease", "note", "marks"]) if (p[k] !== undefined) app.setClipProp(k, p[k], who); return { frames: app.doc.frames, fps: app.doc.fps, loop: app.doc.loop }; },
    set_frame: (p) => { go(p); return { frame: app.frame }; },
    get_pose: (p) => {
      const frames = Array.isArray(p.frame) ? p.frame : [p.frame ?? app.frame];
      const want = p.bones || [];
      const out = {};
      for (const f of frames) {
        const body = app.stage.probe;
        let pose = p.final !== false ? app.finalPoseOn(body, Number(f)) : E.layerPose(app.doc, Number(f), app.bones);
        if (p.final === false) body.apply(pose);
        if (Math.abs(Number(f) - app.frame) < 1e-3 && app.pending) pose = app.pending;
        const bones = {};
        for (const b of want.length ? want : app.bones) { const e = pose[b] || [0, 0, 0]; if (want.length || Math.hypot(...e) > 1e-4) bones[b] = deg3(e); }
        const entry = { bones, hips: { dx: pose._dx || 0, dy: pose._dy || 0, dz: pose._dz || 0 }, is_key: app.doc.hasKey(Math.round(Number(f))) };
        if (p.world) entry.world = Object.fromEntries((want.length ? want : app.bones).filter((b) => body.has(b)).map((b) => [b, m3(body.worldPos(b))]));
        out[String(Math.round(Number(f)))] = entry;
      }
      return frames.length > 1 ? out : Object.values(out)[0];
    },
    set_pose: (p) => {
      go(p);
      const pose = app.editablePose();
      const bad = [], clamped = [];
      for (const b in p.bones || {}) {
        if (!app.bones.includes(b)) { bad.push(b); continue; }
        const v = p.radians ? v3(p.bones[b]) : rad3(p.bones[b]);
        const old = pose[b] || [0, 0, 0];
        const want = p.mode === "add" ? old.map((x, i) => x + v[i]) : v;
        const got = app.doc.guard(b, old, want);
        if (dist3(got, want) > 1e-6) clamped.push(b);
        pose[b] = got;
        if (p.mirror) { const mn = R.mirrorName(b); if (mn !== b) pose[mn] = app.doc.guard(mn, pose[mn] || [0, 0, 0], R.mirrorEuler(got)); }
      }
      for (const ax of ["dx", "dy", "dz"]) if (p.hips && p.hips[ax] !== undefined) pose["_" + ax] = (p.mode === "add" ? pose["_" + ax] || 0 : 0) + Number(p.hips[ax]);
      app.editPose(pose, `Agent pose f${Math.round(app.frame)}`, p.key !== false, who);
      const r = { frame: Math.round(app.frame), keyed: p.key !== false };
      if (bad.length) r.unknown_bones = bad;
      if (clamped.length) r.clamped_by_limits_or_locks = clamped;
      return r;
    },
    ik_pose: (p) => {
      go(p);
      if (!app.bones.includes(p.bone)) return { error: "no bone " + p.bone };
      const was = app.keepEnd;
      app.keepEnd = p.keep_end !== false;
      const t = new THREE.Vector3(...v3(p.target));
      app.dragBegin("Agent IK " + p.bone);
      app.dragIK(p.bone, t);
      app.keepEnd = was;
      app._dragStart = null;
      if (p.key !== false) app.keyNow(`Agent IK ${p.bone} f${Math.round(app.frame)}`, who);
      const got = app.jointWorld(p.bone);
      return { frame: Math.round(app.frame), reached: m3(got), miss_m: Math.round(got.distanceTo(t) * 10000) / 10000 };
    },
    key: (p) => { go(p); const r = app.keyNow(`Key f${Math.round(app.frame)}`, who); for (const f of ["ease", "tag"]) if (p[f] !== undefined) app.setKeysField([Math.round(app.frame)], f, p[f], who); return r; },
    list_keys: () => app.doc.keys.map((k) => ({ f: k.f, ease: k.ease || app.doc.ease, tag: k.tag || "key", link: k.link || "", lock: !!k.lock, bones: Object.keys(k.rot || {}) })),
    delete_keys: (p) => { app.deleteKeys(ints(p.frames), who); return { keys: app.doc.keyFrames() }; },
    move_keys: (p) => (app.moveKeys(ints(p.frames), Number(p.delta || 0), who) ? { keys: app.doc.keyFrames() } : { error: "keys cannot land on other keys, before frame 0, or move while locked" }),
    set_keys: (p) => { for (const f of ["ease", "tag", "lock"]) if (p[f] !== undefined) app.setKeysField(ints(p.frames), f, p[f], who); return { ok: true }; },
    set_key_values: (p) => {
      const f = Math.round(Number(p.frame)), k = app.doc.keyAt(f);
      if (!k) return { error: `no key at f${f} (use set_pose with key: true to make one)` };
      if (k.lock) return { error: `the key at f${f} is locked` };
      const before = poseOfKey(k, app.bones), after = { ...before };
      for (const b in p.bones || {}) if (app.bones.includes(b)) after[b] = app.doc.guard(b, before[b], rad3(p.bones[b]));
      for (const ax of ["dx", "dy", "dz"]) if (p.hips && p.hips[ax] !== undefined) after["_" + ax] = Number(p.hips[ax]);
      let updated = [];
      app.mutate(`Agent edit key f${f}`, () => { app.doc.writeKey(f, after, app.bones); if (app.propagate !== "off") updated = app.doc.propagate(f, before, after, app.bones, app.propagate); }, who);
      return { frame: f, also_updated: updated };
    },
    link_keys: (p) => { app.linkKeys(ints(p.frames), who); return { keys: app.doc.keys.map((k) => [k.f, k.link || ""]) }; },
    unlink_keys: (p) => { app.unlinkKeys(ints(p.frames), who); return { ok: true }; },
    same_keys: (p) => app.doc.partners(Math.round(Number(p.frame || 0)), app.bones, true),
    set_propagate: (p) => { if (!["off", "linked", "pose", "bone"].includes(p.mode)) return { error: "mode: off | linked | pose | bone" }; app.propagate = p.mode; app.emit("tool"); return { propagate: app.propagate }; },
    insert_frames: (p) => { app.insertFrames(Number(p.at || 0), Number(p.count || 1), who); return { frames: app.doc.frames, keys: app.doc.keyFrames() }; },
    delete_frames: (p) => { app.deleteFrames(Number(p.at || 0), Number(p.count || 1), who); return { frames: app.doc.frames, keys: app.doc.keyFrames() }; },
    scale_time: (p) => { app.scaleTime(Number(p.factor || 1), ints(p.frames), who); return { frames: app.doc.frames, keys: app.doc.keyFrames() }; },
    reverse: (p) => { app.reverseRange(Number(p.from || 0), Number(p.to ?? app.doc.frames), who); return { keys: app.doc.keyFrames() }; },
    close_loop: () => { app.closeLoop(who); return { keys: app.doc.keyFrames() }; },
    mirror_pose: (p) => { go(p); app.poseMirror(p.mode || "l2r", who); return maybeKey(p); },
    reset_bones: (p) => { go(p); app.resetBones(p.bones || [], who); return maybeKey(p); },
    breakdown: (p) => { go(p); app.breakdown(Number(p.t ?? 0.5), who); return maybeKey(p); },
    list_poses: () => app.listPoses(),
    save_pose: async (p) => { const prev = app.selBones; if (p.bones) app.selBones = p.bones; const ok = await app.saveLibraryPose(String(p.name || ""), !!p.bones); app.selBones = prev; return { saved: ok }; },
    apply_pose: async (p) => {
      go(p);
      const prev = app.selBones;
      if (p.bones) app.selBones = p.bones;
      const ok = await app.applyLibraryPose(String(p.name || ""), !!p.bones, Number(p.weight ?? 1), !!p.mirror, who);
      app.selBones = prev;
      return ok ? maybeKey(p) : { error: "no pose named " + p.name };
    },
    list_controls: (p) => { go(p); const pose = app.editablePose(); return R.rigData.controls.map((c) => ({ name: c.name, value: Math.round(R.controlValue(c, pose) * 1000) / 1000, min: c.min, max: c.max, drives: c.drives })); },
    set_control: (p) => { go(p); const c = R.rigData.controls.find((x) => x.name === p.name); if (!c) return { error: "no control named " + p.name }; app.setControl(c, Number(p.value || 0), who); return maybeKey(p); },
    add_control: async (p) => {
      const drives = (p.drives || []).map((d) => { const i = ["x", "y", "z"].indexOf(String(d[1])); return [String(d[0]), i >= 0 ? i : String(d[1]), i >= 0 ? Number(d[2]) * RAD : Number(d[2])]; });
      R.rigData.controls.push({ name: String(p.name || "control"), min: Number(p.min ?? -1), max: Number(p.max ?? 1), drives });
      await R.saveRigData();
      app.emit("fighter");
      return { controls: R.rigData.controls.length };
    },
    list_layers: () => app.doc.layers,
    add_layer: (p) => { const d = { ...p }; if (typeof d.mask === "string") d.mask = R.MASKS[d.mask] || []; return app.addLayer(d, who); },
    set_layer: async (p) => { const d = { ...p }; delete d.id; if (typeof d.mask === "string") d.mask = R.MASKS[d.mask] || []; await app.setLayer(p.id, d, who); return app.doc.layerById(p.id); },
    remove_layer: (p) => { app.removeLayer(p.id, who); return { layers: app.doc.layers.length }; },
    set_active_layer: (p) => { app.setActiveLayer(p.id || ""); return { active_layer: app.activeLayer }; },
    list_constraints: () => app.doc.constraints,
    add_constraint: (p) => app.addConstraint(conDef(p), who),
    set_constraint: (p) => { const d = conDef(p); delete d.id; app.setConstraint(p.id, d, who); return app.doc.constraintById(p.id); },
    remove_constraint: (p) => { app.removeConstraint(p.id, who); return { constraints: app.doc.constraints.length }; },
    freeze: (p) => { const fr = Number(p.from ?? Math.round(app.frame)); return app.addConstraint({ type: "pin", bone: p.bone, what: p.what || "both", pin_frame: fr, start: fr, end: Number(p.to ?? -1), name: "FREEZE " + p.bone }, who); },
    bake_to_keys: () => { app.bakeToKeys(who); return { keys: app.doc.keys.length }; },
    lock: (p) => { for (const b of p.bones || []) app.setLock(b, p.channels || "xyz", who); return app.doc.locks; },
    unlock: (p) => { for (const b of p.bones || []) app.setLock(b, "", who); return app.doc.locks; },
    list_sockets: () => Object.fromEntries(Object.keys(app.sockSpecs).map((n) => [n, { bone: app.sockSpecs[n].bone, world: m3(app.socketWorld(n)) }])),
    add_marker: (p) => { const f = Number(p.frame ?? Math.round(app.frame)); app.mutate("Marker " + p.name, () => app.doc.addMarker(f, String(p.name || "marker")), who); return app.doc.markers; },
    set_view: (p) => {
      const vh = app.views.main;
      if (p.layout) vh.setLayout(String(p.layout));
      if (p.preset) { const v = vh.views[Number(p.index || 0)]; if (v) { v.setPreset(p.preset); if (p.ortho !== undefined) { v.ortho = !!p.ortho; v.update(); } } }
      if (p.onion !== undefined) { app.onion.on = !!p.onion; app.applyNow(); }
      if (p.tool) app.setTool(p.tool);
      if (p.bone) app.selectBone(p.bone);
      app.emit("tool");
      return { layout: vh.layout, views: vh.views.map((v) => v.preset) };
    },
    screenshot: async (p) => {
      const kind = p.target || "sheet";
      if (kind === "window") {
        app.views.render(true);
        await new Promise((r) => requestAnimationFrame(() => r()));
        const path = await window.host.captureWindow(p.path || "");
        return path ? { path } : { error: "could not capture" };
      }
      if (kind === "view" && p.index !== undefined) app.views.main.focused = app.views.main.views[Number(p.index)] || app.views.main.focused;
      const path = await app.ui.picture(kind === "view" ? "view" : "sheet", Number(p.width || 1920), Number(p.height || 1080), Number(p.cols || 8), p.path || "");
      return path ? { path } : { error: "render failed" };
    },
    checks: () => app.runChecks(),
    transition_clip: async (p) => {
      if (app.history.dirty() && !p.discard) return { error: "save the open clip first (or pass discard: true)" };
      return { ok: await app.makeTransitionClip(String(p.clip_b || ""), Number(p.at || 0), Number(p.blend ?? 6), String(p.name || "transition"), who), clip: app.doc.name };
    },
    undo: () => { app.undo(); return { keys: app.doc.keyFrames() }; },
    redo: () => { app.redo(); return { keys: app.doc.keyFrames() }; },
    history: () => app.history.labels(60),
    say: (p) => { app.say("Agent: " + (p.message || ""), "agent"); app.agentFlash = 1; app.views.dirty(); return { shown: true }; },
    bake_glb: async () => (app.history.dirty() ? { error: "save the clip first: the bake reads the saved files" } : window.host.bakeAnimato(app.fighter)),
  };

  async function windowShot() {
    app.views.render(true);
    const c = app.views.main;
    const out = document.createElement("canvas");
    out.width = c.gl.width;
    out.height = c.gl.height;
    const g = out.getContext("2d");
    g.drawImage(c.gl, 0, 0);
    g.drawImage(c.ov, 0, 0, out.width, out.height);
    return out.toDataURL("image/png").split(",")[1];
  }

  function conDef(p) {
    const d = structuredClone(p);
    for (const f of ["min_deg", "max_deg"]) if (d[f]) { d[f.slice(0, 3)] = rad3(d[f]); delete d[f]; }
    if (Array.isArray(d.target)) d.target = { pos: d.target };
    return d;
  }

  return async function call(method, params) {
    if (method === "__health") return { ok: true, result: { fighter: app.fighter, clip: app.doc.name } };
    if (method === "__methods") return { ok: true, result: METHODS };
    if (method === "__can_close") {
      if (!app.history.dirty()) return { ok: true, result: true };
      return { ok: true, result: await window.host.confirm(`"${app.doc.name}" has changes that are not saved. Quit anyway?`) };
    }
    let out;
    if (!D[method]) out = { ok: false, error: `unknown method ${method} (GET /methods lists them)` };
    else {
      try {
        const r = await D[method](params || {});
        out = r && typeof r === "object" && !Array.isArray(r) && r.error && r.ok === undefined ? { ok: false, error: r.error } : { ok: true, result: r };
      } catch (e) {
        out = { ok: false, error: String(e && e.message ? e.message : e) };
      }
    }
    const s = JSON.stringify(params || {});
    app.apiLog.push({ time: new Date().toLocaleTimeString(), method, summary: s.length > 140 ? s.slice(0, 140) + "..." : s, ok: out.ok });
    if (!out.ok) app.say(`Agent call ${method} failed: ${out.error}`, "warn");
    app.emit("api");
    return out;
  };
}
