// Every dock panel: builds once, refreshes on app changes.
import { h, button, heading, hint, row, label, select, check, num, slider, list, AX } from "./ui.js";
import * as R from "./core/rig.js";
import { EASES, newId, poseOfKey } from "./core/doc.js";
import { targetPoint } from "./core/evalc.js";
import { DEG, RAD, v3 } from "./core/clip.js";
import { PROP_SHAPES } from "./stage.js";
import { renderPicture } from "./views.js";

const MCP = "D:/Games/BSP-Universe/game/packs/city_breaker/animator/mcp/fight_studio_mcp.py";
export const mcpConfig = () => JSON.stringify({ mcpServers: { "fight-studio": { command: "python", args: [MCP] } } }, null, 2);
const body = () => h("div", { class: "pbody" });
const prompt = (app, text, value, fn) => app.ui.prompt(text, value, fn);

// ==================================================================== CLIPS
export function Clips(app) {
  const el = body();
  const search = h("input", { placeholder: "search clips...", oninput: () => refill() });
  const filters = ["All", "Mine (no prefix)", "World (w_)", "Fighter moves (a_)", "This fighter's own"];
  const filt = select(filters, filters[0], () => refill());
  const l = list(null, (i, t) => app.openClip(t));
  l.el.style.minHeight = "300px";
  el.append(heading("Clips"), hint("Every clip the game reads (data/clips). Double-click to open."), search, filt, l.el,
    row(button("OPEN", () => l.text() && app.openClip(l.text())), button("NEW", () => prompt(app, "Name for the new clip (starts from the pose on screen):", "my_clip", (n) => app.newClip(n, 30, 30, false, true))),
      button("DUPLICATE", () => prompt(app, `Save a copy of ${app.doc.name} as:`, app.doc.name + "_v2", (n) => app.saveAs(n)))),
    row(button("AS LAYER", () => { if (l.text()) { app.addLayer({ name: l.text(), source: "clip", clip: l.text(), mode: "override", mask: R.MASKS["Upper body"] }); app.ui.showPanel("Layers"); } }, "Blend the selected clip on top as a layer"),
      button("TO TRASH", async () => { const n = l.text(); if (n && (await window.host.confirm(`Move ${n} to D:/Cache/fight_studio_trash?`))) { await app.trashClip(n); refill(); } }, "Clips are never deleted: they move to the trash folder"),
      button("RELOAD", () => refill())));
  let all = [];
  async function refill(reload = false) {
    if (reload || !all.length) all = await window.host.listClips();
    const q = search.value.trim().toLowerCase();
    const m = filters.indexOf(filt.value);
    const names = all.filter((s) => (m === 1 ? !s.startsWith("a_") && !s.startsWith("w_") : m === 2 ? s.startsWith("w_") : m === 3 ? s.startsWith("a_") : m === 4 ? s.startsWith(`a_${app.fighter}_`) : true) && (!q || s.toLowerCase().includes(q)));
    l.set(names, names.indexOf(app.doc.name), names.map((n) => (n === app.doc.name ? "#ffc93c" : "")));
  }
  app.on((w) => { if (["clips", "saved", "clip", "fighter"].includes(w)) refill(w !== "clip"); });
  refill(true);
  return el;
}

// ==================================================================== PROPERTIES
export function Props(app) {
  const el = body();
  const boneName = h("div", { class: "big" });
  const boneHint = hint("");
  const rot = [], locks = [];
  el.append(heading("Bone"), boneName, boneHint);
  for (let i = 0; i < 3; i++) {
    const s = slider(["X  turn", "Y  turn", "Z  turn"][i], -180, 180, 0.5, 0, () => onRot(), { color: AX[i], title: "Degrees on the bone's own axes" });
    const lk = check("lock", false, () => onLock(), "Freeze this channel: no tool can change it");
    s.el.append(lk);
    rot.push(s); locks.push(lk.querySelector("input"));
    el.append(s.el);
  }
  el.append(row(button("RESET BONE", () => app.resetBones(app.selBones)), button("MIRROR TO OTHER SIDE", () => {
    const m = R.mirrorName(app.selBone);
    if (m === app.selBone) return app.say(`${m} is a centre bone.`, "warn");
    const p = app.editablePose();
    p[m] = app.doc.guard(m, p[m] || [0, 0, 0], R.mirrorEuler(p[app.selBone] || [0, 0, 0]));
    app.editPose(p, `Mirror ${app.selBone} to ${m}`);
  }), button("KEY", () => app.keyNow())));
  el.append(heading("Body move (hips shift)"));
  const hips = ["dx", "dy", "dz"].map((ax, i) => {
    const s = slider({ dx: "side (m)", dy: "height (m)", dz: "forward (m)" }[ax], -1.5, 1.5, 0.005, 0, (v) => app.setHipsShift(ax, v), { color: AX[i] });
    el.append(s.el);
    return s;
  });
  el.append(heading("This key"));
  const keyInfo = h("div", { class: "txt" });
  const ease = select(EASES, "linear", (v) => app.setKeysField([Math.round(app.frame)], "ease", v), "How the motion leaves this key toward the next");
  const tag = select(["key", "breakdown", "extreme"], "key", (v) => app.setKeysField([Math.round(app.frame)], "tag", v === "key" ? "" : v));
  const klock = check("locked", false, (on) => app.setKeysField([Math.round(app.frame)], "lock", on), "A locked key cannot be changed, moved or deleted");
  el.append(keyInfo, row(label("ease"), ease, label("type"), tag, klock));
  el.append(heading("Clip"));
  const plant = check("plant feet (the game stands the lower foot on the floor)", false, (on) => app.setClipProp("plant", on));
  const over = check("override a baked clip of the same name", false, (on) => app.setClipProp("override", on));
  const dease = select(EASES, "linear", (v) => app.setClipProp("ease", v), "The ease of every key without its own");
  const note = h("input", { placeholder: "note", onchange: () => app.setClipProp("note", note.value) });
  const marks = h("div");
  el.append(plant, over, row(label("default ease"), dease), note, heading("Marks and markers"),
    hint("hit / clear: the frames a move's hitbox goes live and ends. Markers are your notes on the ruler."), marks,
    row(button("HIT HERE", () => setMark("hit")), button("CLEAR HERE", () => setMark("clear")),
      button("+ MARKER", () => prompt(app, "Marker name:", "contact", (n) => { const f = Math.round(app.frame); app.mutate("Marker " + n, () => app.doc.addMarker(f, n)); }))));
  function setMark(m) { app.setClipProp("marks", { ...(app.doc.extra.marks || {}), [m]: Math.round(app.frame) }); }
  function onRot() { app.setBoneEuler(app.selBone, rot.map((s) => Number(s.r.value) * RAD)); }
  function onLock() { app.setLock(app.selBone, locks.map((c, i) => (c.checked ? "xyz"[i] : "")).join("")); }
  function refresh() {
    const b = app.selBone, p = app.editablePose();
    boneName.textContent = b + (app.selBones.length > 1 ? `   (${app.selBones.length} selected)` : "");
    boneHint.textContent = R.hint(b);
    const e = p[b] || [0, 0, 0];
    rot.forEach((s, i) => { s.set(e[i] * DEG); locks[i].checked = app.doc.isLocked(b, i); s.disable(app.doc.isLocked(b, i)); });
    hips.forEach((s, i) => s.set(p[["_dx", "_dy", "_dz"][i]] || 0));
    const f = Math.round(app.frame), k = app.doc.keyAt(f);
    if (!k) keyInfo.textContent = `f${f} is between keys (K sets one)`;
    else {
      const partners = app.doc.partners(f, app.bones, true);
      keyInfo.textContent = `f${f} is a key${k.link ? "  - linked " + k.link : ""}${partners.length ? "  - same pose as f" + partners.join(", f") : ""}`;
      ease.value = k.ease || app.doc.ease;
      tag.value = k.tag || "key";
      klock.querySelector("input").checked = !!k.lock;
    }
    [ease, tag, klock.querySelector("input")].forEach((x) => (x.disabled = !k));
    plant.querySelector("input").checked = app.doc.plant;
    over.querySelector("input").checked = app.doc.override;
    dease.value = app.doc.ease;
    if (document.activeElement !== note) note.value = app.doc.extra.note || "";
    marks.innerHTML = "";
    const mk = app.doc.extra.marks || {};
    for (const m in mk) marks.append(h("div", { class: "txt", style: `color:${m === "hit" ? "#ff4d4d" : "#4fd1ff"}` }, `${m}  f${Number(mk[m]).toFixed(1)}`));
    app.doc.markers.forEach((m, i) => marks.append(row(h("span", { class: "txt", style: "color:#ffc93c" }, `marker ${m.name}  f${m.f}`), button("x", () => app.mutate("Remove marker", () => app.doc.markers.splice(i, 1))))));
  }
  app.on((w) => { if (["sel", "frame", "doc", "pending", "clip", "fighter", "tool"].includes(w)) refresh(); });
  return el;
}

// ==================================================================== CONTROLS
export function Controls(app) {
  const el = body();
  const box = h("div");
  el.append(heading("Controls"), hint("One slider moves several bones together (a fist, a spine curl, a crouch). The slider reads the pose; key the result with K or AUTO KEY."), box);
  const nameIn = h("input", { placeholder: "new control name" });
  const target = h("select");
  const boneSel = h("select");
  const axSel = select(["X", "Y", "Z", "move side", "move up", "move forward"], "X", () => {});
  const amount = num(30, () => {}, { min: -180, max: 180, title: "How far the channel goes at value 1 (degrees, or cm for moves)" });
  el.append(heading("Add your own control"), nameIn, target, row(boneSel, axSel, amount),
    row(button("ADD DRIVE", () => add()), button("REMOVE CONTROL", () => { if (target.selectedIndex > 0) { R.rigData.controls.splice(target.selectedIndex - 1, 1); build(); } }),
      button("SAVE CONTROLS", async () => { await R.saveRigData(); app.say("Controls saved to data/animator_rig.json (shared with the Godot Animator).", "ok"); })));
  let sliders = [];
  function add() {
    const i = axSel.selectedIndex;
    const ax = [0, 1, 2, "dx", "dy", "dz"][i];
    const amt = i < 3 ? Number(amount.value) * RAD : Number(amount.value) / 100;
    const bone = i < 3 ? boneSel.value : "hips";
    if (target.selectedIndex > 0) R.rigData.controls[target.selectedIndex - 1].drives.push([bone, ax, amt]);
    else {
      if (!nameIn.value.trim()) return app.say("Name the new control first.", "warn");
      R.rigData.controls.push({ name: nameIn.value.trim(), min: -1, max: 1, drives: [[bone, ax, amt]] });
    }
    build();
    app.say("Control updated (SAVE CONTROLS keeps it).", "ok");
  }
  function build() {
    box.innerHTML = "";
    sliders = R.rigData.controls.map((ctl) => {
      const s = slider(ctl.name, Number(ctl.min ?? -1), Number(ctl.max ?? 1), 0.01, 0, (v) => app.setControl(ctl, v), { title: `${ctl.drives.length} bone channels` });
      s.el.style.display = ctl.drives.some((d) => app.bones.includes(d[0])) ? "" : "none";
      box.append(s.el);
      return s;
    });
    target.innerHTML = "";
    target.add(new Option("(new control)"));
    for (const c of R.rigData.controls) target.add(new Option(c.name));
    boneSel.innerHTML = "";
    for (const b of app.bones) boneSel.add(new Option(b));
    refresh();
  }
  function refresh() {
    const p = app.editablePose();
    R.rigData.controls.forEach((c, i) => sliders[i] && sliders[i].set(R.controlValue(c, p)));
  }
  app.on((w) => { if (w === "fighter") build(); else if (["frame", "doc", "pending", "clip"].includes(w)) refresh(); });
  build();
  return el;
}

// ==================================================================== LAYERS
export function Layers(app) {
  const el = body();
  let selId = "";
  const l = list((i) => { selId = app.doc.layers[i].id; edit(); });
  const clipIn = h("input", { placeholder: "clip to blend in (name)" });
  const ed = h("div");
  el.append(heading("Layers"), hint("KEYS layers tweak without touching the base keys; CLIP layers blend another clip in. add = adds its turns, add_delta = adds a clip's motion from its first frame, override = blends toward it. Masks pick bones, fades blend in and out. Saving bakes them for the game."),
    row(button("+ KEYS LAYER", () => { const ly = app.addLayer({ name: `tweak ${app.doc.layers.length + 1}`, mode: "add", source: "keys" }); ly.then((x) => { selId = x.id; app.setActiveLayer(x.id); }); }), button("BASE", () => app.setActiveLayer(""), "Key into the base clip again")),
    row(clipIn, button("+ CLIP LAYER", async () => {
      const n = clipIn.value.trim();
      if (!(await window.host.loadClip(n))) return app.say(`No clip named ${n}.`, "warn");
      const ly = await app.addLayer({ name: n, mode: "override", source: "clip", clip: n, mask: R.MASKS["Upper body"] });
      selId = ly.id;
    })), l.el, ed, row(button("BAKE ALL INTO KEYS", () => app.bakeToKeys())));
  const put = (k, v) => app.setLayer(selId, { [k]: v });
  function edit() {
    ed.innerHTML = "";
    const ly = app.doc.layerById(selId);
    if (!ly) return;
    const nm = h("input", { value: ly.name, onchange: () => put("name", nm.value) });
    const maskNames = Object.keys(R.MASKS);
    const cur = maskNames.find((m) => JSON.stringify(R.MASKS[m]) === JSON.stringify(ly.mask || [])) || "Full body";
    ed.append(h("hr"), nm,
      row(label("mode"), select(["add", "add_delta", "override"], ly.mode || "add", (v) => put("mode", v)), check("mute", ly.mute, (v) => put("mute", v)), check("solo", ly.solo, (v) => put("solo", v))),
      slider("weight", 0, 1, 0.01, Number(ly.weight ?? 1), (v) => put("weight", v)).el,
      row(label("bones"), select(maskNames, cur, (v) => put("mask", R.MASKS[v]))),
      row(label("from"), num(ly.start || 0, (v) => put("start", v | 0)), label("to"), num(ly.end ?? -1, (v) => put("end", v | 0), { title: "-1 = to the end" })),
      row(label("fade in"), num(ly.fade_in || 0, (v) => put("fade_in", v | 0)), label("out"), num(ly.fade_out || 0, (v) => put("fade_out", v | 0))));
    if (ly.source === "clip") {
      const ce = h("input", { value: ly.clip, onchange: () => put("clip", ce.value) });
      ed.append(row(label("clip"), ce), row(label("offset"), num(ly.offset || 0, (v) => put("offset", v | 0)), label("speed"), num(ly.speed ?? 1, (v) => put("speed", v), { step: 0.05 }), check("cycle", ly.cycle !== false, (v) => put("cycle", v))));
    } else ed.append(button(app.activeLayer === selId ? "KEYING THIS LAYER" : "KEYS GO HERE", () => app.setActiveLayer(selId), "Pose and press K: the key lands in this layer", app.activeLayer === selId ? "on" : ""));
    ed.append(row(button("UP", () => app.moveInList(app.doc.layers, selId, -1, "Reorder layers")), button("DOWN", () => app.moveInList(app.doc.layers, selId, 1, "Reorder layers")),
      button("REMOVE", () => { app.removeLayer(selId); selId = ""; })));
  }
  function refresh() {
    l.set(app.doc.layers.map((x) => `${x.id === app.activeLayer ? "> " : ""}${x.name}  [${x.source} ${x.mode} ${Math.round((x.weight ?? 1) * 100)}%]${x.mute ? "  MUTED" : x.solo ? "  SOLO" : ""}`), app.doc.layers.findIndex((x) => x.id === selId));
    edit();
  }
  app.on((w) => { if (["doc", "clip", "layer"].includes(w)) refresh(); });
  return el;
}

// ==================================================================== CONSTRAINTS
export function Constraints(app) {
  const el = body();
  let selId = "";
  const l = list((i) => { selId = app.doc.constraints[i].id; edit(); });
  const ed = h("div");
  const grid = h("div", { class: "grid3" });
  const adds = [["IK ARM L", { type: "ik", limb: "armL" }], ["IK ARM R", { type: "ik", limb: "armR" }], ["IK LEG L", { type: "ik", limb: "legL" }], ["IK LEG R", { type: "ik", limb: "legR" }],
    ["AIM HEAD", { type: "aim", bone: "head", axis: "+z" }], ["FLOOR", { type: "floor", bones: ["footL", "footR"], mode: "floor" }], ["PLANT FEET", { type: "floor", bones: ["footL", "footR"], mode: "plant", name: "PLANT feet" }]];
  for (const [t, def] of adds) grid.append(button(t, () => { selId = app.addConstraint(def).id; refresh(); }));
  grid.append(button("FREEZE SEL", () => { selId = app.pinSelected().id; refresh(); }, "Freeze the selected bone where it is now, from this frame on"));
  grid.append(button("LIMIT SEL", () => { selId = app.addConstraint({ type: "limit", bone: app.selBone, min: [-1, -1, -1], max: [1, 1, 1] }).id; refresh(); }));
  el.append(heading("Constraints"), hint("Rules solved every frame on top of the keys: IK (a hand / foot reaches a target), FREEZE (a bone stays put in the world), AIM (the head follows a point), LIMIT, COPY, FLOOR / PLANT. Purple crosshairs are their targets. Saving bakes them for the game."),
    grid, l.el, ed, row(button("BAKE ALL INTO KEYS", () => app.bakeToKeys())));
  const put = (k, v) => app.setConstraint(selId, { [k]: v });
  const vecRow = (text, v, fn, step = 0.01) => {
    const ins = [0, 1, 2].map((i) => num(Math.round(v[i] * 1000) / 1000, () => fn(ins.map((x) => Number(x.value))), { step, width: 72 }));
    return row(label(text), ...ins);
  };
  const boneSel = (cur, fn) => select(app.bones, cur, fn);
  function edit() {
    ed.innerHTML = "";
    const c = app.doc.constraintById(selId);
    if (!c) return;
    ed.append(h("hr"), h("div", { class: "big", style: "color:#a77bff" }, c.name || c.type), check("on", c.enabled !== false, (v) => put("enabled", v)),
      slider("influence", 0, 1, 0.01, Number(c.influence ?? 1), (v) => put("influence", v)).el,
      row(label("from"), num(c.start || 0, (v) => put("start", v | 0)), label("to"), num(c.end ?? -1, (v) => put("end", v | 0), { title: "-1 = to the end" }), label("blend"), num(c.blend || 0, (v) => put("blend", v | 0), { title: "Frames to fade at the range edges" })));
    if (c.type === "ik" || c.type === "aim") {
      const p = targetPoint(c.target, app.frame, app.stage.body);
      ed.append(vecRow("target m", [p.x, p.y, p.z], (v) => put("target", { pos: v })),
        row(button("TARGET = HERE NOW", () => {
          const end = c.type === "ik" ? R.LIMBS[c.limb][2] : c.bone || "head";
          const w = app.jointWorld(end);
          if (c.type === "aim") w.z += 1.5;
          put("target", { pos: [w.x, w.y, w.z].map((x) => Math.round(x * 1000) / 1000) });
        }), button("KEY TARGET", () => {
          const tg = structuredClone(c.target || {});
          const f = Math.round(app.frame);
          const q = targetPoint(tg, app.frame, app.stage.body);
          tg.keys = (tg.keys || []).filter((k) => k.f !== f).concat([{ f, pos: [q.x, q.y, q.z].map((x) => Math.round(x * 1000) / 1000) }]).sort((a, b) => a.f - b.f);
          delete tg.pos;
          put("target", tg);
        }, "Key the target here: it moves between its keys")));
      if (c.type === "ik") ed.append(check("hand / foot keeps its angle", c.keep_end !== false, (v) => put("keep_end", v)));
      else ed.append(row(label("bone"), boneSel(c.bone || "head", (v) => put("bone", v)), label("looks along"), select(["+z", "-z", "+x", "-x", "+y", "-y"], c.axis || "+z", (v) => put("axis", v))));
    } else if (c.type === "pin") {
      ed.append(row(label("bone"), boneSel(c.bone, (v) => put("bone", v)), select(["both", "position", "rotation"], c.what || "both", (v) => put("what", v))),
        row(label("frozen as at f"), num(c.pin_frame || 0, (v) => put("pin_frame", v | 0)), button("AT THIS FRAME", () => put("pin_frame", Math.round(app.frame)))));
    } else if (c.type === "limit") {
      ed.append(boneSel(c.bone, (v) => put("bone", v)), vecRow("min deg", v3(c.min).map((x) => x * DEG), (v) => put("min", v.map((x) => x * RAD)), 1), vecRow("max deg", v3(c.max).map((x) => x * DEG), (v) => put("max", v.map((x) => x * RAD)), 1));
    } else if (c.type === "copy_rot") {
      ed.append(row(label("bone"), boneSel(c.bone, (v) => put("bone", v)), label("copies"), boneSel(c.source, (v) => put("source", v))),
        slider("mix", -2, 2, 0.01, Number(c.mix ?? 1), (v) => put("mix", v)).el, check("mirrored", c.mirror, (v) => put("mirror", v)));
    } else if (c.type === "floor") {
      const be = h("input", { value: (c.bones || ["footL", "footR"]).join(","), onchange: () => put("bones", be.value.replace(/ /g, "").split(",")) });
      ed.append(row(select(["floor", "plant"], c.mode || "floor", (v) => put("mode", v)), label("height"), num(c.height || 0, (v) => put("height", v), { step: 0.01 })), row(label("bones"), be));
    }
    ed.append(row(button("UP", () => app.moveInList(app.doc.constraints, selId, -1, "Reorder constraints")), button("DOWN", () => app.moveInList(app.doc.constraints, selId, 1, "Reorder constraints")),
      button("REMOVE", () => { app.removeConstraint(selId); selId = ""; })));
  }
  function refresh() {
    l.set(app.doc.constraints.map((c) => `${c.enabled === false ? "(off) " : ""}${c.name}  ${Math.round((c.influence ?? 1) * 100)}%  f${c.start || 0}-${(c.end ?? -1) < 0 ? "end" : c.end}`), app.doc.constraints.findIndex((c) => c.id === selId));
    edit();
  }
  app.on((w) => { if (["doc", "clip"].includes(w)) refresh(); });
  return el;
}

// ==================================================================== OUTLINER
export function Outliner(app) {
  const el = body();
  const tree = h("div", { class: "tree" });
  const collapsed = { "Hand L": true, "Hand R": true, Ears: true, Extras: true };
  el.append(heading("Outliner"), hint("Bones by body part. Tick LOCK to freeze a bone (no tool can turn it). Click a group to select all of it."), tree);
  function refresh() {
    tree.innerHTML = "";
    const counts = {};
    for (const k of app.doc.keys) for (const b in k.rot || {}) counts[b] = (counts[b] || 0) + 1;
    for (const [g, bones] of R.grouped(app.bones)) {
      tree.append(h("div", { class: "tg", onclick: (e) => {
        if (e.offsetX < 18) { collapsed[g] = !collapsed[g]; refresh(); return; }
        const bs = R.maskBones(["@" + g], app.bones);
        app.selectBone(bs[0]);
        bs.slice(1).forEach((b) => app.selectBone(b, true));
      } }, (collapsed[g] ? "+ " : "- ") + g));
      if (collapsed[g]) continue;
      for (const b of bones) {
        const side = R.sideOf(b);
        const lock = h("input", { type: "checkbox", checked: app.doc.isLocked(b), onclick: (e) => e.stopPropagation(), onchange: () => app.setLock(b, lock.checked ? "xyz" : "") });
        tree.append(h("div", { class: "tb" + (app.selBones.includes(b) ? " sel" : ""), onclick: (e) => app.selectBone(b, e.shiftKey) },
          h("span", { style: `color:${side === "L" ? "#4fd1ff" : side === "R" ? "#ff5d8f" : "#f4efe6"}` }, b),
          h("span", { class: "tc" }, app.doc.lockChannels(b) && !app.doc.isLocked(b) ? app.doc.lockChannels(b) : ""), lock, h("span", { class: "tc" }, String(counts[b] || 0))));
      }
    }
  }
  app.on((w) => { if (["doc", "fighter", "clip", "sel"].includes(w)) refresh(); });
  return el;
}

// ==================================================================== POSES
export function Poses(app) {
  const el = body();
  const g = h("div", { class: "grid3" });
  for (const [t, fn] of [["MIRROR L>R", () => app.poseMirror("l2r")], ["MIRROR R>L", () => app.poseMirror("r2l")], ["FLIP", () => app.poseMirror("flip")], ["COPY", () => app.copyPose()],
    ["PASTE", () => app.pastePose(false)], ["PASTE MIRROR", () => app.pastePose(true)], ["RESET SEL", () => app.resetBones(app.selBones)], ["RESET ALL", () => app.resetBones([...app.bones, "hips_move"])], ["KEY  K", () => app.keyNow()]]) g.append(button(t, fn));
  const l = list(null, () => apply(false, false));
  l.el.style.minHeight = "160px";
  const w = slider("weight", 0, 1, 0.01, 1, () => {});
  w.set(1);
  el.append(heading("Pose tools"), g, heading("Breakdown"), hint("Between the key before and the key after: slide toward either, then key it."),
    slider("lean", 0, 1, 0.01, 0.5, (v) => app.breakdown(v), { title: "0 = the previous key, 1 = the next key" }).el,
    heading("Pose library"), hint("Poses you keep (data/poses, shared with the Godot Animator). Whole body or selected bones, mirrored, blended by weight."), l.el, w.el,
    row(button("APPLY", () => apply(false, false)), button("ON SELECTED", () => apply(true, false)), button("MIRRORED", () => apply(false, true))),
    row(button("SAVE POSE", () => prompt(app, "Pose name:", `pose_${app.doc.name}_f${Math.round(app.frame)}`, (n) => app.saveLibraryPose(n))),
      button("SAVE SELECTED", () => prompt(app, "Partial pose (selected bones):", `part_${app.selBone}`, (n) => app.saveLibraryPose(n, true)))));
  function apply(sel, mir) {
    if (!l.text()) return app.say("Pick a pose in the list.", "warn");
    app.applyLibraryPose(l.text(), sel, Number(w.r.value), mir);
  }
  async function refresh() { l.set(await app.listPoses()); }
  app.on((w2) => { if (w2 === "poses") refresh(); });
  refresh();
  return el;
}

// ==================================================================== SOCKETS + PROPS
export function Sockets(app) {
  const el = body();
  const l = list((i, t) => { app.selSocket = t.split("   ")[0]; app.views.dirty(); edit(); });
  const ed = h("div");
  const pl = list((i) => { propSel = app.doc.props[i].id; editProp(); });
  const ped = h("div");
  let propSel = "";
  const shape = select(PROP_SHAPES, "bat", () => {});
  el.append(heading("Sockets"), hint("Named points on bones (effects, props, hit points). Shared by every fighter unless saved for this one."),
    check("show sockets in the views", app.show.sockets, (v) => { app.show.sockets = v; app.views.dirty(); }), l.el, ed,
    row(button("+ SOCKET", () => prompt(app, "Socket name:", "my_socket", (n) => { app.sockSpecs[n] = { bone: app.selBone, offset: [0, 0, 0] }; app.selSocket = n; refresh(); })),
      button("SAVE ALL", () => app.saveSockets(false)), button("SAVE THIS FIGHTER", () => app.saveSockets(true))),
    heading("Props on sockets"), hint("Stand-in objects held at a socket so you can animate with them. Saved in the clip, never in the game."), pl.el,
    row(shape, button("+ PROP AT SOCKET", () => app.mutate("Add prop", () => app.doc.props.push({ id: newId(app.doc.props, "prop"), name: shape.value, shape: shape.value, socket: app.selSocket || "fist_R", offset: [0, 0, 0], rot: [0, 0, 0], scale: 1, color: "#c8c0d0" })))), ped);
  function edit() {
    ed.innerHTML = "";
    const sp = app.sockSpecs[app.selSocket];
    if (!sp) return;
    const off = v3(sp.offset);
    const ins = [0, 1, 2].map((i) => num(off[i], () => { sp.offset = ins.map((x) => Number(x.value)); app.views.dirty(); }, { step: 0.005, width: 72 }));
    ed.append(row(label("bone"), select(app.bones, sp.bone, (v) => { sp.bone = v; app.views.dirty(); })), row(label("offset"), ...ins), check("on the ground under the bone", sp.ground, (v) => { sp.ground = v; app.views.dirty(); }));
  }
  const setProp = (k, v) => app.mutate("Prop " + k, () => { const p = app.doc.props.find((x) => x.id === propSel); if (p) p[k] = v; });
  function editProp() {
    ped.innerHTML = "";
    const p = app.doc.props.find((x) => x.id === propSel);
    if (!p) return;
    const socks = Object.keys(app.sockSpecs).sort();
    const vec = (fld, step) => { const v = v3(p[fld]); const ins = [0, 1, 2].map((i) => num(v[i], () => setProp(fld, ins.map((x) => Number(x.value))), { step, width: 66 })); return row(label(fld), ...ins); };
    ped.append(row(label("socket"), select(socks, p.socket, (v) => setProp("socket", v))), vec("offset", 0.005), vec("rot", 1), slider("scale", 0.1, 4, 0.05, p.scale ?? 1, (v) => setProp("scale", v)).el,
      row(h("input", { type: "color", value: p.color || "#c8c0d0", onchange: (e) => setProp("color", e.target.value) }), button("REMOVE PROP", () => app.mutate("Remove prop", () => app.doc.removeById(app.doc.props, propSel)))));
  }
  function refresh() {
    const names = Object.keys(app.sockSpecs).sort();
    l.set(names.map((n) => `${n}   (${app.sockSpecs[n].bone})`), names.indexOf(app.selSocket));
    edit();
    pl.set(app.doc.props.map((p) => `${p.name} on ${p.socket}`), app.doc.props.findIndex((p) => p.id === propSel));
    editProp();
  }
  app.on((w) => { if (["fighter", "clip", "doc"].includes(w)) refresh(); });
  return el;
}

// ==================================================================== BLEND LAB
export function Blend(app) {
  const el = body();
  const clipB = h("input", { placeholder: "clip B (type to search)", oninput: () => search() });
  const found = list((i, t) => (clipB.value = t));
  found.el.style.minHeight = "90px";
  const at = num(12, () => {}, { min: 0 });
  const span = num(6, () => {}, { min: 0 });
  const name = h("input", { placeholder: "new clip name" });
  const maskSel = select(Object.keys(R.MASKS), "Upper body", () => {});
  const w = slider("mix weight", 0, 1, 0.01, 1, () => {});
  w.set(1);
  el.append(heading("Blend Lab"), hint("TRANSITION: this clip, then B takes over at a frame, crossfading over N frames (try it as a layer, or make a new clip). MIX: B on top on some bones only, or B's motion added on top."),
    clipB, found.el, row(label("B starts at f"), at, label("crossfade frames"), span, button("AT CURRENT FRAME", () => (at.value = Math.round(app.frame)))),
    row(button("TRY AS LAYER", async () => { if (await ok()) { await app.addLayer({ name: "to " + clipB.value, mode: "override", source: "clip", clip: clipB.value.trim(), offset: Number(at.value), cycle: false, start: Number(at.value), fade_in: Number(span.value) }); app.ui.showPanel("Layers"); } }),
      name, button("MAKE TRANSITION CLIP", async () => { if (await ok()) app.makeTransitionClip(clipB.value.trim(), Number(at.value), Number(span.value), name.value.trim() || `${app.doc.name}_to_${clipB.value.trim()}`); })),
    h("hr"), w.el, row(label("bones"), maskSel, button("MIX B ON THESE BONES", () => mix("override")), button("ADD B'S MOTION", () => mix("add_delta"), "Adds B's movement from its first frame on top")));
  async function ok() { if (!(await window.host.loadClip(clipB.value.trim()))) { app.say("Pick clip B first.", "warn"); return false; } return true; }
  async function mix(mode) { if (await ok()) { await app.addLayer({ name: `${clipB.value} ${mode}`, mode, source: "clip", clip: clipB.value.trim(), weight: Number(w.r.value), mask: R.MASKS[maskSel.value] }); app.ui.showPanel("Layers"); } }
  let all = [];
  async function search() {
    if (!all.length) all = await window.host.listClips();
    const q = clipB.value.trim();
    found.set(all.filter((c) => !q || c.includes(q)).slice(0, 60));
  }
  search();
  return el;
}

// ==================================================================== AGENTS
export function Agents(app) {
  const el = h("div", { class: "pbody split" });
  const head = h("div", { class: "big", style: "color:#a77bff" });
  const log = list();
  log.el.style.flex = "1";
  const left = h("div", { class: "col", style: "flex:1.6" }, head, log.el);
  const right = h("div", { class: "col", style: "flex:1" }, heading("Connect an agent"),
    hint("Agents animate here through MCP: they read the rig, pose, key, blend, add constraints, render pictures to check their work, and save. Their edits show live (purple frame), are in History and undo like yours."),
    h("textarea", { readOnly: true, rows: 7, value: mcpConfig() }),
    row(button("COPY MCP CONFIG", () => { navigator.clipboard.writeText(mcpConfig()); app.say("MCP config copied.", "ok"); }), button("CLEAR LOG", () => { app.apiLog = []; refresh(); })));
  el.append(left, right);
  function refresh() {
    head.textContent = `AGENT API on http://127.0.0.1:${app.info?.apiPort || 47651}/rpc  -  ${app.apiLog.length} calls`;
    const items = app.apiLog.slice(-300).reverse();
    log.set(items.map((e) => `${e.time}  ${e.method}  ${e.summary}`), -1, items.map((e) => (e.ok ? "" : "#ff4d4d")));
  }
  app.on((w) => { if (w === "api") refresh(); });
  refresh();
  return el;
}

// ==================================================================== HISTORY
export function HistoryPanel(app) {
  const el = body();
  const l = list(null, (i) => { for (let n = 0; n <= i; n++) app.undo(); });
  l.el.style.flex = "1";
  el.append(row(heading("History"), button("UNDO", () => app.undo()), button("REDO", () => app.redo()), hint("newest first; [agent] = an agent's. Double-click undoes back to that step.")), l.el);
  const refresh = () => { const ls = app.history.labels(200); l.set(ls, -1, ls.map((t) => (t.startsWith("[agent]") ? "#a77bff" : ""))); };
  app.on((w) => { if (["doc", "clip", "saved"].includes(w)) refresh(); });
  return el;
}

// ==================================================================== CHECKS
export function Checks(app) {
  const el = body();
  let res = [];
  const l = list((i) => { if (res[i].f >= 0) app.setFrame(res[i].f); });
  l.el.style.flex = "1";
  el.append(row(heading("Checks"), button("RUN", () => run(), "Knees never bend forward, joint limits, the loop seam, planted feet sliding, unkeyed edits")), l.el);
  function run() {
    res = app.runChecks();
    l.set(res.map((r) => r.text), -1, res.map((r) => ({ error: "#ff4d4d", warn: "#ff7a1a", ok: "#5ce08a" }[r.level])));
  }
  app.on((w) => { if (["saved", "clip"].includes(w)) run(); });
  return el;
}

// ==================================================================== RENDER
export function Render(app) {
  const el = body();
  const SIZES = [["HD 1280 x 720", 1280, 720], ["Full HD 1920 x 1080", 1920, 1080], ["QHD 2560 x 1440", 2560, 1440], ["4K 3840 x 2160", 3840, 2160], ["Square 1080", 1080, 1080], ["Vertical 1080 x 1920", 1080, 1920]];
  const res = select(SIZES.map((s, i) => [String(i), s[0]]), "1", () => {});
  const cols = num(8, () => {}, { min: 2, max: 24 });
  const a = num(0, () => {}, { min: 0 }), b = num(app.doc.frames, () => {}, { min: 0 });
  const last = hint("");
  const wh = () => SIZES[Number(res.value)];
  el.append(heading("Render"), hint("Pictures of your animation at HD or 4K, saved to D:/Cache/fight_studio_renders. Stills use the view you clicked last."), res,
    row(button("STILL OF THE VIEW", async () => (last.textContent = await app.ui.picture("view", wh()[1], wh()[2]))), label("sheet columns"), cols,
      button("REVIEW SHEET (4 ANGLES)", async () => (last.textContent = await app.ui.picture("sheet", wh()[1], wh()[2], Number(cols.value))))),
    row(label("frames"), a, label("to"), b, button("PNG SEQUENCE", async () => {
      const was = app.frame;
      const dir = `D:/Cache/fight_studio_renders/${app.fighter}_${app.doc.name}_seq_${wh()[1]}x${wh()[2]}`;
      for (let f = Number(a.value); f <= Number(b.value); f++) {
        app.frame = f; app.pending = null; app.applyNow();
        await app.ui.picture("view", wh()[1], wh()[2], 8, `${dir}/f${String(f).padStart(4, "0")}.png`);
      }
      app.frame = was; app.applyNow();
      last.textContent = dir;
      app.say("Rendered frames to " + dir, "ok");
    })), row(button("OPEN THE FOLDER", () => window.host.openPath("D:/Cache/fight_studio_renders"))), last);
  app.on((w) => { if (w === "clip") b.value = app.doc.frames; });
  return el;
}

export { renderPicture, poseOfKey };
