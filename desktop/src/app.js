// Fight Studio Desktop - the app: state and every edit (UI, shortcuts and agents all come through here: undo, live views,
// history). The clip format, rules and agent API match the Godot Fight Studio Animator.
import * as THREE from "three";
import { Doc, poseOfKey, fillKey, EASES } from "./core/doc.js";
import { boneRot, rotQuat, eulerOf, sub3, add3, lerp3, dist3, v3, DEG, RAD, poseAt } from "./core/clip.js";
import * as R from "./core/rig.js";
import * as E from "./core/evalc.js";
import { History } from "./core/history.js";

export class App extends EventTarget {
  constructor() {
    super();
    Object.assign(this, {
      fighter: "vix", fighters: [], bones: [], doc: Doc.blank("untitled"), history: new History(), isNew: false, frame: 0, playing: false, speed: 1,
      playLoop: true, playRange: [0, -1], selBone: "hips", selBones: ["hips"], selKeys: [], selSocket: "", activeLayer: "", tool: "rotate",
      spaceGlobal: false, autokey: false, mirrorEdit: false, propagate: "pose", keepEnd: true, onion: { on: false, before: 2, after: 2, step: 3, keys: false },
      show: { bones: true, labels: true, trail: true, sockets: false, props: true, gameFeet: true, fingers: false }, stripCols: 8, stripFollow: false,
      pending: null, ctx: {}, poseCopy: null, keysCopy: [], agentFlash: 0, apiLog: [], status: "", statusKind: "info", sockSpecs: {}, ankle: 0,
      stage: null, views: null, info: null,
    });
    this._dragStart = null;
    this._trail = { key: "", pts: [] };
    this._curves = new Map();
  }

  emit(what) { this.dispatchEvent(new CustomEvent("changed", { detail: what })); }
  on(fn) { this.addEventListener("changed", (e) => fn(e.detail)); }
  say(text, kind = "info") { this.status = text; this.statusKind = kind; this.emit("status"); }

  // ================================================================ boot
  async boot(stage, views) {
    this.stage = stage;
    this.views = views;
    this.info = await window.host.info();
    E.setClipLoader((n) => window.host.loadClip(n));
    await R.loadRigData();
    this.fighters = await window.host.fighters();
    const args = this.info.args;
    const arg = (n, d) => (args.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).split("=").slice(1).join("=");
    this.fighter = this.fighters.includes(arg("fighter", "vix")) ? arg("fighter", "vix") : this.fighters[0];
    await this.setFighter(this.fighter, true);
    const sockets = (await window.host.loadData("sockets.json")) || {};
    this._sockData = sockets;
    this.loadSockets();
    const clip = arg("clip", "w_walk");
    if (!(await this.openClip(clip, true))) this.say(`No clip named ${clip}.`, "warn");
  }

  // ================================================================ frame
  playRangeFrames() {
    const a = Math.max(0, Math.min(this.playRange[0], this.doc.frames));
    const b = this.playRange[1] < 0 ? this.doc.frames : Math.max(a, Math.min(this.playRange[1], this.doc.frames));
    return [a, b];
  }

  tick(dt) {
    if (this.playing) {
      const [a, b] = this.playRangeFrames();
      let f = this.frame + dt * this.doc.fps * this.speed;
      if (f > b) {
        if (this.playLoop) f = a + ((f - a) % Math.max(1, b - a));
        else { f = b; this.playing = false; this.emit("play"); }
      }
      this.frame = f;
      this.applyNow();
      this.emit("frame");
    }
    if (this.agentFlash > 0) this.agentFlash = Math.max(0, this.agentFlash - dt * 0.8);
  }

  setFrame(f) {
    f = Math.max(0, Math.min(Number(f), this.doc.frames));
    if (Math.abs(f - this.frame) < 1e-4 && !this.pending) return;
    if (this.pending) {
      this.pending = null;
      this.say("The pose you changed was not keyed (K keys it; AUTO KEY keys every edit).", "warn");
    }
    this.frame = f;
    this.applyNow();
    this.emit("frame");
  }

  step(n) { this.playing = false; this.setFrame(Math.round(this.frame) + n); }
  gotoKey(dir) { const k = dir > 0 ? this.doc.nextKey(this.frame) : this.doc.prevKey(this.frame); if (k >= 0) this.setFrame(k); }
  togglePlay() {
    this.playing = !this.playing;
    if (!this.playing) { this.frame = Math.round(this.frame); this.applyNow(); }
    else this.pending = null;
    this.emit("play");
  }

  // ================================================================ posing
  editablePose() {
    return this.pending ? { ...this.pending } : E.layerPose(this.doc, this.frame, this.bones);
  }

  finalPoseOn(body, f) { return E.finalPose(this.doc, f, body, this.bones, this.ctx); }

  applyNow() {
    const st = this.stage;
    if (!st || !st.body) return;
    E.solvePose(this.doc, this.frame, st.body, this.bones, this.ctx, this.editablePose());
    st.model.position.y = 0;
    st.body.update();
    if (this.show.gameFeet && this.doc.plant) st.plant(this.ankle);
    st.updateOnion(this);
    if (this.show.props) st.placeProps(this);
    this.views && this.views.dirty();
  }

  jointWorld(n) { return this.stage.body.worldPos(n); }
  isBoneLocked(n) { return this.doc.isLocked(n); }

  selectBone(b, add = false) {
    if (!this.bones.includes(b)) return;
    if (add) {
      if (this.selBones.includes(b) && b !== this.selBone) this.selBones = this.selBones.filter((x) => x !== b);
      else if (!this.selBones.includes(b)) this.selBones.push(b);
    } else this.selBones = [b];
    this.selBone = b;
    this.views && this.views.dirty();
    this.emit("sel");
  }

  selectKeys(fs, add = false) {
    const out = add ? [...this.selKeys] : [];
    for (const f of fs) if (!out.includes(Number(f))) out.push(Number(f));
    this.selKeys = out;
    this.emit("keysel");
  }

  setTool(t) { this.tool = t; this.views && this.views.dirty(); this.emit("tool"); }

  dragBegin(label) {
    this._dragLabel = label;
    this._dragStart = this.editablePose();
    this.stage.probe.apply(this._dragStart);
  }

  dragEnd() {
    this._dragStart = null;
    if (!this.pending) return;
    if (this.autokey) this.keyNow(this._dragLabel);
    else this.emit("pending");
  }

  dragRotate(bone, axisWorld, angle) {
    if (!this._dragStart) this.dragBegin("Turn " + bone);
    this._setPending(this.rotateInPose(this._dragStart, bone, axisWorld, angle, this.stage.probe));
  }

  rotateInPose(base, bone, axisWorld, angle, body) {
    const pose = { ...base };
    if (!body.has(bone) || this.doc.isLocked(bone)) return pose;
    const own = base[bone] || [0, 0, 0];
    const total = boneRot(base, bone);
    const pq = body.parentWorldQuat(bone);
    const restQ = body.rest.get(bone).q;
    const lOld = restQ.clone().multiply(rotQuat(total));
    const rw = new THREE.Quaternion().setFromAxisAngle(axisWorld.clone().normalize(), angle);
    const lNew = pq.clone().invert().multiply(rw).multiply(pq).multiply(lOld);
    const eNew = E.nearestEuler(eulerOf(restQ.clone().invert().multiply(lNew)), total);
    pose[bone] = this.doc.guard(bone, own, sub3(eNew, sub3(total, own)));
    this._mirrorInto(pose, bone);
    return pose;
  }

  _mirrorInto(pose, bone) {
    if (!this.mirrorEdit) return;
    const m = R.mirrorName(bone);
    if (m === bone || !this.bones.includes(m)) return;
    pose[m] = this.doc.guard(m, pose[m] || [0, 0, 0], R.mirrorEuler(pose[bone]));
  }

  dragMove(deltaWorld) {
    if (!this._dragStart) this.dragBegin("Move body");
    if (this.doc.isLocked("hips")) return;
    const pose = { ...this._dragStart };
    const hips = this.stage.probe.bone("hips");
    const pq = this.stage.probe.parentWorldQuat("hips").invert();
    const d = deltaWorld.clone().applyQuaternion(pq);
    pose._dx = (this._dragStart._dx || 0) + d.x;
    pose._dy = (this._dragStart._dy || 0) + d.y;
    pose._dz = (this._dragStart._dz || 0) + d.z;
    if (hips) this._setPending(pose);
  }

  dragIK(bone, targetWorld) {
    if (!this._dragStart) this.dragBegin("IK " + bone);
    const body = this.stage.probe;
    body.apply(this._dragStart);
    if (!body.has(bone)) return;
    const touched = new Set();
    const limb = R.limbOfEnd(bone);
    if (limb) {
      const ids = R.LIMBS[limb];
      const keep = this.keepEnd ? body.worldQuat(ids[2]) : null;
      E.solveTwoBone(body, ids[0], ids[1], ids[2], targetWorld, E.autoPole(body, limb, ...ids), keep, 1);
      ids.forEach((n) => touched.add(n));
    } else if (bone === "hips") {
      return this.dragMove(targetWorld.clone().sub(body.worldPos("hips")));
    } else {
      E.ccd(body, bone, targetWorld).forEach((n) => touched.add(n));
    }
    const pose = E.readBack(body, this._dragStart, touched);
    for (const n of touched) {
      pose[n] = this.doc.guard(n, this._dragStart[n] || [0, 0, 0], pose[n]);
      this._mirrorInto(pose, n);
    }
    this._setPending(pose);
  }

  _setPending(pose) {
    this.pending = pose;
    this.applyNow();
    this.emit("pending");
  }

  editPose(pose, label, key = false, who = "you") {
    this._setPending(pose);
    if (this.autokey || key) return this.keyNow(label, who);
    return { frame: Math.round(this.frame), keyed: false };
  }

  setBoneEuler(bone, e, label = "") {
    const p = this.editablePose();
    p[bone] = this.doc.guard(bone, p[bone] || [0, 0, 0], e);
    this._mirrorInto(p, bone);
    this.editPose(p, label || "Set " + bone);
  }

  setHipsShift(ax, v) {
    const p = this.editablePose();
    p["_" + ax] = v;
    this.editPose(p, "Hips " + ax);
  }

  revertPending() {
    if (!this.pending) return;
    this.pending = null;
    this.applyNow();
    this.emit("pending");
    this.say("Unkeyed changes thrown away.");
  }

  // ================================================================ document changes
  mutate(label, fn, who = "you") {
    const before = this.doc.toDict();
    const r = fn();
    this.doc.normalize();
    this.history.commit(label, before, this.doc.toDict(), who);
    if (who !== "you") this.agentFlash = 1;
    this.docChanged();
    return r;
  }

  docChanged() {
    this.ctx = {};
    this._trail.key = "";
    this._curves.clear();
    this.selKeys = this.selKeys.filter((f) => this.doc.hasKey(f));
    this.applyNow();
    this.views && this.views.stripDirty();
    this.updateTitle();
    this.emit("doc");
  }

  updateTitle() { window.host.setTitle(`Fight Studio Desktop - ${this.fighter} / ${this.doc.name}${this.history.dirty() ? " *" : ""}`); }

  undo() {
    const e = this.history.undo();
    if (!e) return this.say("Nothing to undo.");
    this.doc.loadDict(e.before);
    this.pending = null;
    this.docChanged();
    this.say("Undid: " + e.label);
  }

  redo() {
    const e = this.history.redo();
    if (!e) return this.say("Nothing to redo.");
    this.doc.loadDict(e.after);
    this.pending = null;
    this.docChanged();
    this.say("Redid: " + e.label);
  }

  // ================================================================ keys
  keyNow(label = "", who = "you") {
    const f = Math.round(this.frame);
    if (this.doc.isKeyLocked(f)) {
      this.say(`The key at f${f} is locked (Key menu > Unlock).`, "warn");
      return { ok: false, error: "key locked" };
    }
    const pose = this.editablePose();
    let updated = [];
    const layer = this.activeLayer ? this.doc.layerById(this.activeLayer) : null;
    if (layer) this._keyLayer(f, pose, label, who, layer);
    else {
      this.mutate(label || `Key f${f}`, () => {
        const before = this.doc.writeKey(f, pose, this.bones);
        if (before && this.propagate !== "off") updated = this.doc.propagate(f, before, pose, this.bones, this.propagate);
      }, who);
    }
    this.pending = null;
    this.applyNow();
    this.say(`Keyed f${f}` + (updated.length ? ` - also updated the same key at f${updated.join(", f")}` : ""), who !== "you" ? "agent" : "ok");
    this.emit("pending");
    return { ok: true, frame: f, also_updated: updated };
  }

  _keyLayer(f, want, label, who, l) {
    if ((l.source || "keys") !== "keys") return this.say(`Layer ${l.name} plays a clip; pick a keys layer or the base.`, "warn");
    const now = E.layerPose(this.doc, f, this.bones);
    const w = Math.max(0.05, E.layerWeight(l, f, this.doc.frames));
    const own = E.layerValue(l, f, this.bones, this.doc.loop) || {};
    const lp = {};
    for (const b of this.bones) lp[b] = own[b] || [0, 0, 0];
    for (const b of R.maskBones(l.mask || [], this.bones)) {
      const d = sub3(want[b] || [0, 0, 0], now[b] || [0, 0, 0]);
      if (Math.hypot(...d) > 1e-6) lp[b] = add3(lp[b], d.map((x) => x / w));
    }
    for (const ax of ["_dy", "_dx", "_dz"]) lp[ax] = (own[ax] || 0) + ((want[ax] || 0) - (now[ax] || 0)) / w;
    this.mutate(label || `Key layer ${l.name} f${f}`, () => {
      const ks = l.keys || (l.keys = []);
      let k = ks.find((x) => x.f === f);
      if (!k) { k = { f }; ks.push(k); }
      fillKey(k, lp, this.bones);
    }, who);
  }

  deleteKeys(fs, who = "you") {
    if (!fs.length) fs = [Math.round(this.frame)];
    const locked = fs.filter((f) => this.doc.isKeyLocked(f));
    this.mutate("Delete keys", () => fs.forEach((f) => !this.doc.isKeyLocked(f) && this.doc.deleteKey(f)), who);
    this.selKeys = [];
    this.say(`Deleted ${fs.length - locked.length} key(s)${locked.length ? ` (${locked.length} locked kept)` : ""}.`);
  }

  moveKeys(fs, delta, who = "you") {
    if (!this.doc.canMove(fs, delta)) {
      this.say("Keys cannot land on other keys, go before frame 0, or move while locked.", "warn");
      return false;
    }
    this.mutate(`Move keys ${delta > 0 ? "+" : ""}${delta}`, () => this.doc.moveKeys(fs, delta), who);
    this.selKeys = fs.map((f) => f + delta);
    this.emit("keysel");
    return true;
  }

  setKeysField(fs, field, value, who = "you") {
    if (!fs.length) fs = [Math.round(this.frame)];
    this.mutate("Key " + field, () => fs.forEach((f) => this.doc.setKeyField(f, field, value)), who);
  }

  setKeyChannel(f, bone, axis, value, who = "you") {
    const k = this.doc.keyAt(f);
    if (!k || this.doc.isKeyLocked(f) || this.doc.isLocked(bone, axis)) return this.say("Locked.", "warn");
    const before = poseOfKey(k, this.bones);
    const after = { ...before };
    const e = [...(after[bone] || [0, 0, 0])];
    e[axis] = value;
    after[bone] = R.clampLimits(bone, e);
    this.mutate(`Set ${bone} ${"XYZ"[axis]} f${f}`, () => {
      this.doc.writeKey(f, after, this.bones);
      if (this.propagate !== "off") this.doc.propagate(f, before, after, this.bones, this.propagate);
    }, who);
  }

  setKeyHips(f, ax, value, who = "you") {
    const k = this.doc.keyAt(f);
    if (!k || this.doc.isKeyLocked(f)) return;
    const before = poseOfKey(k, this.bones);
    const after = { ...before, ["_" + ax]: value };
    this.mutate(`Hips ${ax} f${f}`, () => {
      this.doc.writeKey(f, after, this.bones);
      if (this.propagate !== "off") this.doc.propagate(f, before, after, this.bones, this.propagate);
    }, who);
  }

  linkKeys(fs, who = "you") {
    if (fs.length < 2) return this.say("Select two or more keys to link (they become the same key: edit one, all follow).", "warn");
    const id = this.mutate("Link keys", () => this.doc.linkKeys(fs, this.bones, true), who);
    this.say(`Linked f${fs.join(", f")} as ${id}: they now share one pose.`, "ok");
  }

  unlinkKeys(fs, who = "you") { this.mutate("Unlink keys", () => this.doc.unlinkKeys(fs), who); }

  copyKeys(fs) {
    const lo = Math.min(...fs);
    this.keysCopy = fs.map((f) => { const k = structuredClone(this.doc.keyAt(f)); k.f -= lo; delete k.link; delete k.lock; return k; });
    this.say(`Copied ${this.keysCopy.length} key(s).`);
  }

  pasteKeys(at, who = "you") {
    if (!this.keysCopy.length) return this.say("No keys copied.", "warn");
    this.mutate(`Paste keys at f${at}`, () => {
      for (const k of this.keysCopy) {
        const nf = at + k.f;
        if (this.doc.isKeyLocked(nf)) continue;
        this.doc.writeKey(nf, poseOfKey(k, this.bones), this.bones);
        for (const fld of ["ease", "tag"]) if (k[fld]) this.doc.setKeyField(nf, fld, k[fld]);
      }
    }, who);
  }

  mirrorKeys(fs, who = "you") {
    this.mutate("Mirror keys", () => {
      for (const f of fs) {
        const k = this.doc.keyAt(f);
        if (k && !k.lock) this.doc.writeKey(f, this.mirrored(poseOfKey(k, this.bones), "flip"), this.bones);
      }
    }, who);
  }

  // ================================================================ frames / clip
  insertFrames(at, n, who = "you") { this.mutate(`Insert ${n} frames at f${at}`, () => this.doc.insertFrames(at, n), who); }
  deleteFrames(at, n, who = "you") { this.mutate(`Delete ${n} frames at f${at}`, () => this.doc.deleteFrames(at, n), who); this.setFrame(Math.min(this.frame, this.doc.frames)); }
  scaleTime(factor, fs = [], who = "you") { this.mutate(`Scale time x${factor}`, () => this.doc.scaleTime(factor, fs.length ? Math.min(...fs) : 0, fs), who); }
  reverseRange(a, b, who = "you") { this.mutate(`Reverse f${a}-f${b}`, () => this.doc.reverse(a, b), who); }

  setClipProp(prop, value, who = "you") {
    this.mutate("Clip " + prop, () => {
      const d = this.doc;
      if (prop === "frames") d.frames = Math.max(1, value | 0);
      else if (prop === "fps") d.fps = Math.max(1, value | 0);
      else if (prop === "note") d.extra.note = String(value);
      else if (prop === "marks") d.extra.marks = value;
      else d[prop] = value;
    }, who);
    if (this.frame > this.doc.frames) this.setFrame(this.doc.frames);
  }

  closeLoop(who = "you") {
    const k0 = this.doc.keys[0];
    this.mutate("Close loop", () => {
      this.doc.writeKey(this.doc.frames, poseOfKey(k0, this.bones), this.bones);
      this.doc.loop = true;
      this.doc.linkKeys([k0.f, this.doc.frames], this.bones, false);
    }, who);
    this.say(`Frame ${this.doc.frames} is now the same key as frame ${k0.f} (linked): the loop is seamless.`, "ok");
  }

  setLock(bone, channels, who = "you") { this.mutate(`Lock ${bone} ${channels || "off"}`, () => this.doc.setLock(bone, channels), who); }

  toggleLockSelected() {
    const lockAll = !this.doc.isLocked(this.selBone);
    this.mutate(lockAll ? "Lock" : "Unlock", () => this.selBones.forEach((b) => this.doc.setLock(b, lockAll ? "xyz" : "")));
    this.say((lockAll ? "Locked " : "Unlocked ") + this.selBones.join(", "));
  }

  // ================================================================ pose tools
  mirrored(pose, mode) {
    const out = { ...pose };
    for (const b of this.bones) {
      const m = R.mirrorName(b);
      const e = pose[b] || [0, 0, 0];
      if (m === b) { if (mode === "flip") out[b] = R.mirrorEuler(e); continue; }
      const side = R.sideOf(b);
      if (mode === "flip" || (mode === "l2r" && side === "L") || (mode === "r2l" && side === "R")) out[m] = R.mirrorEuler(e);
    }
    if (mode === "flip") out._dx = -(pose._dx || 0);
    return out;
  }

  poseMirror(mode, who = "you") {
    const p = this.editablePose();
    const m = this.mirrored(p, mode);
    for (const b of this.bones) m[b] = this.doc.guard(b, p[b] || [0, 0, 0], m[b] || [0, 0, 0], false);
    return this.editPose(m, { flip: "Flip pose", l2r: "Mirror L to R", r2l: "Mirror R to L" }[mode] || "Mirror", false, who);
  }

  resetBones(list, who = "you") {
    const p = this.editablePose();
    for (const b of list) {
      if (b === "hips_move") { p._dx = 0; p._dy = 0; p._dz = 0; }
      else if (!this.doc.isLocked(b)) p[b] = this.doc.guard(b, p[b] || [0, 0, 0], [0, 0, 0], false);
    }
    return this.editPose(p, "Reset " + (list.length < 4 ? list.join(", ") : `${list.length} bones`), false, who);
  }

  copyPose() { this.poseCopy = this.editablePose(); this.say(`Pose copied (f${Math.round(this.frame)}).`); }

  pastePose(mirror = false, onlySel = false) {
    if (!this.poseCopy) return this.say("No pose copied.", "warn");
    const src = mirror ? this.mirrored(this.poseCopy, "flip") : this.poseCopy;
    this.editPose(this.applyPoseDict(this.editablePose(), src, onlySel ? this.selBones : [], 1), "Paste pose");
  }

  applyPoseDict(base, src, only, weight) {
    const out = { ...base };
    for (const b of only.length ? only : this.bones) {
      const cur = base[b] || [0, 0, 0];
      out[b] = this.doc.guard(b, cur, lerp3(cur, src[b] || [0, 0, 0], weight));
    }
    if (!only.length || only.includes("hips")) for (const ax of ["_dy", "_dx", "_dz"]) out[ax] = (base[ax] || 0) + ((src[ax] || 0) - (base[ax] || 0)) * weight;
    return out;
  }

  breakdown(t, who = "you") {
    const a = this.doc.prevKey(this.frame + 0.001), b = this.doc.nextKey(this.frame);
    if (a < 0 || b < 0) return this.say("A breakdown needs a key before and after this frame.", "warn");
    const pa = poseOfKey(this.doc.keyAt(a), this.bones), pb = poseOfKey(this.doc.keyAt(b), this.bones);
    const mid = {};
    for (const n of this.bones) mid[n] = lerp3(pa[n], pb[n], t);
    for (const ax of ["_dy", "_dx", "_dz"]) mid[ax] = pa[ax] + (pb[ax] - pa[ax]) * t;
    return this.editPose(this.applyPoseDict(this.editablePose(), mid, [], 1), `Breakdown ${Math.round(t * 100)}%`, false, who);
  }

  setControl(ctl, value, who = "you") {
    const p = this.editablePose();
    const np = R.setControl(ctl, p, value);
    for (const b of this.bones) np[b] = this.doc.guard(b, p[b] || [0, 0, 0], np[b] || [0, 0, 0]);
    return this.editPose(np, "Control " + ctl.name, false, who);
  }

  async listPoses() { return window.host.listPoses(); }

  async saveLibraryPose(name, onlySel = false) {
    name = String(name).trim().replace(/ /g, "_");
    if (!/^[A-Za-z0-9_\-]+$/.test(name)) { this.say("Not a good pose name.", "warn"); return false; }
    const p = this.editablePose();
    const rot = {};
    for (const b of onlySel ? this.selBones : this.bones) {
      const e = p[b] || [0, 0, 0];
      if (onlySel || Math.hypot(...e) > 1e-5) rot[b] = e.map((x) => Math.round(x * 10000) / 10000);
    }
    const ok = await window.host.savePose({ name, rot, hips_dy: p._dy || 0, hips_dx: p._dx || 0, hips_dz: p._dz || 0, partial: onlySel, from: `${this.doc.name} f${Math.round(this.frame)}` });
    this.say(ok ? `Saved pose "${name}".` : "Could not save the pose.", ok ? "ok" : "error");
    this.emit("poses");
    return ok;
  }

  async applyLibraryPose(name, onlySel, weight, mirror, who = "you") {
    const d = await window.host.loadPose(name);
    if (!d) return false;
    let p = poseOfKey({ rot: d.rot, hips_dy: d.hips_dy, hips_dx: d.hips_dx, hips_dz: d.hips_dz }, this.bones);
    if (mirror) p = this.mirrored(p, "flip");
    let only = onlySel ? this.selBones : [];
    if (d.partial && !only.length) only = Object.keys(d.rot || {});
    this.editPose(this.applyPoseDict(this.editablePose(), p, only, weight), "Pose " + name, false, who);
    return true;
  }

  // ================================================================ layers / constraints
  async addLayer(def, who = "you") {
    if (def.source === "clip") await E.preloadClip(def.clip);
    return this.mutate("Add layer", () => this.doc.addLayer(def), who);
  }

  async setLayer(id, props, who = "you") {
    const l = this.doc.layerById(id);
    if (!l) return;
    if (props.clip) await E.preloadClip(props.clip);
    this.mutate("Layer " + Object.keys(props).join(", "), () => Object.assign(l, props), who);
  }

  removeLayer(id, who = "you") {
    if (this.activeLayer === id) this.activeLayer = "";
    this.mutate("Remove layer", () => this.doc.removeById(this.doc.layers, id), who);
  }

  setActiveLayer(id) {
    this.activeLayer = id;
    this.pending = null;
    this.applyNow();
    const l = this.doc.layerById(id);
    this.say(l ? `Keys now go into layer "${l.name}".` : "Keys now go into the base clip.");
    this.emit("layer");
  }

  addConstraint(def, who = "you") {
    def = structuredClone(def);
    const r3 = (p) => [p.x, p.y, p.z].map((x) => Math.round(x * 1000) / 1000);
    if (def.type === "ik" && (!def.target || !Object.keys(def.target).length)) {
      const end = (R.LIMBS[def.limb] || [])[2];
      if (end) def.target = { pos: r3(this.jointWorld(end)) };
    }
    if (def.type === "aim" && (!def.target || !Object.keys(def.target).length)) def.target = { pos: r3(this.jointWorld(def.bone || "head").add(new THREE.Vector3(0, 0, 1.5))) };
    if (def.type === "pin" && def.pin_frame === undefined) { def.pin_frame = Math.round(this.frame); if (def.start === undefined) def.start = def.pin_frame; }
    return this.mutate("Add " + (def.type || "constraint"), () => this.doc.addConstraint(def), who);
  }

  setConstraint(id, props, who = "you") {
    const c = this.doc.constraintById(id);
    if (c) this.mutate("Constraint " + Object.keys(props).join(", "), () => Object.assign(c, props), who);
  }

  removeConstraint(id, who = "you") { this.mutate("Remove constraint", () => this.doc.removeById(this.doc.constraints, id), who); }

  moveInList(list, id, dir, label) {
    this.mutate(label, () => {
      const i = list.findIndex((x) => x.id === id);
      if (i < 0) return;
      const j = Math.max(0, Math.min(list.length - 1, i + dir));
      const [it] = list.splice(i, 1);
      list.splice(j, 0, it);
    });
  }

  pinSelected(end = -1, who = "you") {
    const f = Math.round(this.frame);
    const c = this.addConstraint({ type: "pin", bone: this.selBone, what: "both", pin_frame: f, start: f, end, name: "FREEZE " + this.selBone }, who);
    this.say(`${this.selBone} is frozen in the world from f${f}.`, "ok");
    return c;
  }

  bakeToKeys(who = "you") {
    const baked = E.bake(this.doc, this.stage.probe, this.bones, this.ctx);
    this.mutate("Bake layers + constraints into keys", () => {
      this.doc.keys = baked;
      this.doc.layers.forEach((l) => (l.mute = true));
      this.doc.constraints.forEach((c) => (c.enabled = false));
    }, who);
    this.say(`Baked ${baked.length} frames into keys; layers muted, constraints off (undo brings them back).`, "ok");
  }

  async makeTransitionClip(clipB, at, blend, name, who = "you") {
    const cb = await E.preloadClip(clipB);
    if (!cb) { this.say(`No clip named ${clipB}.`, "warn"); return false; }
    const tmp = Doc.fromClip(this.doc.toClip());
    tmp.addLayer({ name: "to " + clipB, mode: "override", source: "clip", clip: clipB, offset: at, cycle: !!cb.loop, start: at, fade_in: blend });
    tmp.frames = at + Number(cb.frames || 24);
    tmp.constraints = [];
    const baked = E.bake(tmp, this.stage.probe, this.bones, {});
    const nd = Doc.blank(name, tmp.frames, this.doc.fps);
    nd.keys = baked;
    nd.plant = this.doc.plant;
    nd.extra.note = `Blend Lab: ${this.doc.name} -> ${clipB} at f${at} over ${blend} frames`;
    this._setDoc(nd, true);
    this.say(`Made ${name} (${nd.frames} frames). Save it to keep it.`, "ok");
    return true;
  }

  // ================================================================ clips and fighters
  async listClips(filter = "") { return (await window.host.listClips()).filter((n) => !filter || n.includes(filter)); }

  async openClip(name, discard = false) {
    if (this.history.dirty() && !discard) {
      if (!(await window.host.confirm(`"${this.doc.name}" has changes that are not saved. Open "${name}" anyway (changes are lost)?`))) return false;
    }
    const c = await window.host.loadClip(name);
    if (!c) return false;
    const d = Doc.fromClip(c);
    for (const l of d.layers) if (l.source === "clip") await E.preloadClip(l.clip);
    this._setDoc(d, false);
    this.say(d.outsideEdit ? `${name} was changed outside after a bake: those keys are the base now, layers and constraints are off.` : `Opened ${name} (${d.frames} frames @ ${d.fps} fps, ${d.keys.length} keys).`, d.outsideEdit ? "warn" : "info");
    return true;
  }

  _setDoc(d, asNew) {
    this.doc = d;
    this.isNew = asNew;
    this.history.clear();
    if (asNew) this.history.savedAt = -1;
    Object.assign(this, { pending: null, selKeys: [], activeLayer: "", frame: 0, playing: false, playRange: [0, -1] });
    this.docChanged();
    this.emit("clip");
  }

  newClip(name, frames, fps, loop, fromPose, who = "you") {
    name = String(name).trim();
    if (!/^[A-Za-z0-9_\-]+$/.test(name)) { this.say("Clip names use letters, digits, _ and - only.", "warn"); return false; }
    const start = this.editablePose();
    const d = Doc.blank(name, frames, fps, loop);
    if (fromPose) {
      d.writeKey(0, start, this.bones);
      if (loop) { d.writeKey(frames, start, this.bones); d.linkKeys([0, frames], this.bones, false); }
    }
    this._setDoc(d, true);
    if (who !== "you") this.agentFlash = 1;
    this.say(`New clip ${name}. Pose it, key it (K), save it (Ctrl+S).`, "ok");
    return true;
  }

  async save(who = "you") {
    if (!this.doc.name || this.doc.name === "untitled") return { ok: false, error: "needs a name (Save as)" };
    let baked = [];
    if (this.doc.needsBake()) {
      this.doc.bakedOn = this.fighter;
      baked = E.bake(this.doc, this.stage.probe, this.bones, {});
    }
    const was = this.doc.saved;
    this.doc.saved = Doc.stamp();
    const r = await window.host.saveClip(this.doc.toClip(baked));
    if (!r.ok) { this.doc.saved = was; this.say("Could not save: " + r.error, "error"); return r; }
    E.forgetClips();
    this.history.markSaved();
    this.isNew = false;
    this.updateTitle();
    this.say(`Saved ${this.doc.name}${baked.length ? " (layers + constraints baked for the game)" : ""}.` +
      (was ? "" : " It is yours now: the clip generators (gen_*.py) leave it alone."), who !== "you" ? "agent" : "ok");
    this.emit("saved");
    return { ok: true, path: r.path, baked: baked.length > 0, saved: this.doc.saved };
  }

  async saveAs(name, who = "you") {
    if (!/^[A-Za-z0-9_\-]+$/.test(String(name))) return { ok: false, error: "bad name" };
    this.doc.name = name;
    this.history.savedAt = -1;
    return this.save(who);
  }

  async trashClip(name) {
    const ok = await window.host.trashClip(name);
    if (ok) { this.say(`Moved ${name} to the trash folder.`); this.emit("clips"); }
    return ok;
  }

  async setFighter(k, first = false) {
    const url = await window.host.modelUrl(k);
    if (!url) { this.say(`No model for ${k}.`, "warn"); return false; }
    await this.stage.loadFighter(url, k);
    this.fighter = k;
    this.bones = this.stage.body.names;
    this.stage.body.apply({});
    let lo = Infinity;
    for (const b of ["footL", "footR"]) if (this.stage.body.has(b)) lo = Math.min(lo, this.jointWorld(b).y);
    this.ankle = lo === Infinity ? 0 : Math.max(0, lo);
    if (!this.bones.includes(this.selBone)) { this.selBone = "hips"; this.selBones = ["hips"]; }
    if (!first) { this.loadSockets(); this.views && this.views.frameAll(); this.docChanged(); }
    this.emit("fighter");
    return true;
  }

  // ================================================================ sockets
  loadSockets() {
    const d = this._sockData || {};
    this.sockSpecs = {};
    for (const n in d.sockets || {}) this.sockSpecs[n] = { ...d.sockets[n], ...(((d.fighters || {})[this.fighter] || {})[n] || {}) };
  }

  socketWorld(n) {
    const sp = this.sockSpecs[n];
    const body = this.stage.body;
    if (!sp || !body.has(sp.bone)) return new THREE.Vector3();
    const p = body.worldPos(sp.bone);
    const off = new THREE.Vector3(...v3(sp.offset || [0, 0, 0]));
    if (sp.t !== undefined && sp.to && body.has(sp.to)) p.lerp(body.worldPos(sp.to), Number(sp.t));
    p.add(off.applyQuaternion(body.worldQuat(sp.bone)));
    if (sp.ground) p.y = 0;
    return p;
  }

  async saveSockets(thisFighterOnly) {
    const d = structuredClone(this._sockData || { sockets: {} });
    if (thisFighterOnly) {
      const fd = (d.fighters ||= {})[this.fighter] || {};
      for (const n in this.sockSpecs) {
        const shared = d.sockets[n] || {};
        const diff = {};
        for (const k in this.sockSpecs[n]) if (JSON.stringify(shared[k]) !== JSON.stringify(this.sockSpecs[n][k])) diff[k] = this.sockSpecs[n][k];
        if (Object.keys(diff).length) fd[n] = diff;
      }
      d.fighters[this.fighter] = fd;
    } else for (const n in this.sockSpecs) d.sockets[n] = this.sockSpecs[n];
    await window.host.saveData("sockets.json", d);
    this._sockData = d;
    this.loadSockets();
    this.say(`Sockets saved (${thisFighterOnly ? "this fighter only" : "every fighter"}).`, "ok");
  }

  // ================================================================ overlay data, curves, checks
  overlayTargets() {
    const out = [];
    for (const c of this.doc.constraints) {
      if (c.enabled === false) continue;
      if (c.type === "ik" || c.type === "aim") out.push({ pos: E.targetPoint(c.target, this.frame, this.stage.body), color: "#a77bff", label: c.name });
      else if (c.type === "pin" && this.ctx["pin:" + c.id]) out.push({ pos: this.ctx["pin:" + c.id].p, color: "#5ce08a", label: c.name });
    }
    return out;
  }

  trail() {
    const key = `${this.selBone}|${this.history.undoStack.length}|${this.doc.name}|${this.fighter}`;
    if (this._trail.key !== key) {
      const pts = [];
      const body = this.stage.probe;
      if (body.has(this.selBone)) for (let f = 0; f <= this.doc.frames; f++) { this.finalPoseOn(body, f); pts.push(body.worldPos(this.selBone)); }
      this._trail = { key, pts };
    }
    return this._trail.pts;
  }

  graphCurves(bone) {
    const key = `${bone}|${this.history.undoStack.length}|${this.doc.name}`;
    if (this._curves.has(key)) return this._curves.get(key);
    const lay = [], fin = [], hips = [], hipsF = [];
    const live = E.hasLiveConstraints(this.doc);
    for (let f = 0; f <= this.doc.frames; f++) {
      const lp = E.layerPose(this.doc, f, this.bones);
      lay.push(lp[bone] || [0, 0, 0]);
      hips.push([lp._dx || 0, lp._dy || 0, lp._dz || 0]);
      if (live) {
        const fp = E.solvePose(this.doc, f, this.stage.probe, this.bones, this.ctx, lp);
        fin.push(fp[bone] || [0, 0, 0]);
        hipsF.push([fp._dx || 0, fp._dy || 0, fp._dz || 0]);
      }
    }
    const out = { layer: lay, final: fin, hips, hipsFinal: hipsF };
    this._curves.clear();
    this._curves.set(key, out);
    return out;
  }

  runChecks() {
    const out = [];
    for (const k of this.doc.keys) {
      for (const b in k.rot || {}) {
        const e = v3(k.rot[b]);
        if (b.startsWith("knee") && e[0] < -0.01) out.push({ level: "error", f: k.f, text: `${b} bends FORWARD at f${k.f} (${Math.round(e[0] * DEG)}°): a knee never does` });
        else if (R.breaksLimits(b, e)) out.push({ level: "warn", f: k.f, text: `${b} is past its limit at f${k.f}` });
      }
      if (k.f > this.doc.frames) out.push({ level: "warn", f: k.f, text: `key at f${k.f} is after the end (f${this.doc.frames})` });
    }
    if (this.doc.loop) {
      const a = E.layerPose(this.doc, 0, this.bones), b = E.layerPose(this.doc, this.doc.frames, this.bones);
      let worst = 0, wb = "";
      for (const n of this.bones) { const d = dist3(a[n], b[n]); if (d > worst) { worst = d; wb = n; } }
      if (worst > 0.02) out.push({ level: "warn", f: this.doc.frames, text: `loop seam: ${wb} jumps ${Math.round(worst * DEG)}° from the last frame to the first (Key > Close loop)` });
    }
    if (this.doc.plant) {
      const slide = this.footSlide();
      if (slide > 0.04) out.push({ level: "warn", f: -1, text: `planted foot slides ${(slide * 100).toFixed(1)} cm while on the floor (freeze it: Rig > Freeze)` });
    }
    if (this.doc.outsideEdit) out.push({ level: "warn", f: -1, text: "keys were edited outside after a bake; layers / constraints were switched off" });
    if (this.pending) out.push({ level: "warn", f: Math.round(this.frame), text: `the pose at f${Math.round(this.frame)} is changed but not keyed` });
    if (!out.length) out.push({ level: "ok", f: -1, text: "All good: knees, limits, loop seam, feet." });
    return out;
  }

  // the most the planted foot drifts in one stretch of contact, after taking out the clip's own steady travel (a walk cycle
  // slides its planted foot back by the stride on the spot: the game moves the body forward at that speed)
  footSlide() {
    const body = this.stage.probe;
    if (!body.has("footL") || !body.has("footR")) return 0;
    const runs = [];
    let cur = -1, run = null;
    for (let f = 0; f <= this.doc.frames; f++) {
      this.finalPoseOn(body, f);
      const a = body.worldPos("footL"), b = body.worldPos("footR");
      const low = a.y <= b.y ? 0 : 1;
      const p = low ? b : a;
      if (low !== cur) { cur = low; run = { f0: f, p0: p, f1: f, p1: p }; runs.push(run); }
      run.f1 = f;
      run.p1 = p;
    }
    let dx = 0, dz = 0, dt = 0;
    for (const r of runs) { dx += r.p1.x - r.p0.x; dz += r.p1.z - r.p0.z; dt += r.f1 - r.f0; }
    const vx = dt ? dx / dt : 0, vz = dt ? dz / dt : 0;
    let worst = 0;
    for (const r of runs) {
      const t = r.f1 - r.f0;
      worst = Math.max(worst, Math.hypot(r.p1.x - r.p0.x - vx * t, r.p1.z - r.p0.z - vz * t));
    }
    return worst;
  }
}
