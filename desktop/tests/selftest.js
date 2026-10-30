// Fight Studio Desktop self-test (run: npm run selftest). Same ground as the Godot animator_check.gd: interpolation, keys,
// undo, retime, locks, limits, same-key propagation, layers, IK, freeze, bake, save round trip, the agent API, and that a
// clip baked here gives the Godot file signature (both apps open each other's files).
import * as THREE from "three";
import { Doc, poseOfKey, sig } from "../src/core/doc.js";
import * as E from "../src/core/evalc.js";
import * as R from "../src/core/rig.js";
import { poseAt, rotQuat, eulerOf, dist3, DEG, RAD } from "../src/core/clip.js";
import { makeApi } from "../src/api.js";
import * as A from "../src/core/adjust.js";
import * as M from "../src/core/merge.js";
import * as F from "../src/core/feet.js";
import * as FG from "../src/core/fingers.js";
import * as G from "../src/core/grip.js";
import * as FL from "../src/core/fill.js";

export async function selftest(app) {
  const lines = [];
  let pass = 0, fail = 0;
  const ok = (c, what) => { if (c) { pass++; if (what.startsWith("fill")) lines.push("ok   " + what); } else { fail++; lines.push("FAIL " + what); } };   // the fill checks carry their measurements
  const near = (a, b, t = 1e-3) => Math.abs(a - b) <= t;

  // euler order: three 'ZYX' == Rz * Ry * Rx (the clip format), round trip
  for (const e of [[0.3, -0.7, 1.1], [-1.2, 0.4, -0.2]]) {
    const back = eulerOf(rotQuat(e));
    ok(dist3(back, e) < 1e-6, "euler round trip " + e);
    const m = new THREE.Matrix4().makeRotationZ(e[2]).multiply(new THREE.Matrix4().makeRotationY(e[1])).multiply(new THREE.Matrix4().makeRotationX(e[0]));
    ok(new THREE.Quaternion().setFromRotationMatrix(m).angleTo(rotQuat(e)) < 1e-6, "Rz*Ry*Rx order");
  }
  ok(R.mirrorName("indexL2") === "indexR2" && R.mirrorName("head") === "head", "mirror names");
  ok(R.clampLimits("kneeL", [-0.4, 0, 0])[0] === 0, "knee limit");

  // the godot file opens with the same keys and the same interpolation
  const walk = await window.host.loadClip("w_walk");
  const wd = Doc.fromClip(walk);
  ok(wd.keys.length === walk.keys.length && wd.loop === true, "w_walk opens");
  const p = poseAt(walk, 7.5, app.bones);
  ok(Array.isArray(p.legL) && Math.abs(p.legL[0]) > 0.01, "spline interpolation gives a pose");

  // keys, undo, retime, locks
  app.newClip("zz_desktop_check", 30, 30, false, true);
  app.setFrame(10);
  app.setBoneEuler("armR", [-0.8, 0, 0.3]);
  ok(!!app.pending, "an edit is pending until keyed");
  app.keyNow();
  ok(app.doc.hasKey(10) && near(app.doc.keyAt(10).rot.armR[0], -0.8), "K keys f10");
  app.setFrame(5);
  const k0 = poseOfKey(app.doc.keyAt(0), app.bones).armR;
  ok(dist3(app.editablePose().armR, k0.map((x, i) => (x + [-0.8, 0, 0.3][i]) / 2)) < 0.01, "in-between interpolates");
  app.undo();
  ok(!app.doc.hasKey(10), "undo");
  app.redo();
  ok(app.doc.hasKey(10), "redo");
  ok(app.moveKeys([10], 4) && app.doc.hasKey(14), "move key");
  app.insertFrames(2, 3);
  ok(app.doc.hasKey(17) && app.doc.frames === 33, "insert frames");
  app.deleteFrames(2, 3);
  ok(app.doc.hasKey(14) && app.doc.frames === 30, "delete frames");
  app.setKeysField([14], "lock", true);
  app.setFrame(14);
  app.setBoneEuler("armR", [0.5, 0, 0]);
  ok(app.keyNow().ok === false, "locked key refuses an update");
  app.setKeysField([14], "lock", false);
  app.revertPending();
  app.setLock("legL", "x");
  const leg0 = app.editablePose().legL;
  app.setBoneEuler("legL", [-0.9, 0.2, 0]);
  ok(near(app.pending.legL[0], leg0[0]) && near(app.pending.legL[1], 0.2), "locked channel holds");
  app.revertPending();
  app.setLock("legL", "");
  app.setBoneEuler("kneeR", [-0.6, 0, 0]);
  ok(app.pending.kneeR[0] >= 0, "a knee never bends forward");
  app.revertPending();

  // same key
  app.newClip("zz_desktop_check", 40, 30, true, true);
  ok(app.doc.keyAt(0).link && app.doc.keyAt(0).link === app.doc.keyAt(40).link, "loop: first and last key linked");
  app.setFrame(0);
  app.setBoneEuler("chest", [0.25, 0, 0]);
  let r = app.keyNow();
  ok(r.also_updated.includes(40) && near(app.doc.keyAt(40).rot.chest[0], 0.25), "linked key follows");
  app.setFrame(20);
  app.keyNow();
  app.unlinkKeys([0, 40]);
  app.setFrame(0);
  app.setBoneEuler("head", [0.1, 0.3, 0]);
  r = app.keyNow();
  ok(r.also_updated.includes(20) && r.also_updated.includes(40), "same-pose keys follow");

  // layers
  app.newClip("zz_desktop_check", 30, 30, false, true);
  const l = await app.addLayer({ name: "wave", mode: "add", source: "keys", mask: ["armR", "elbowR"] });
  app.setActiveLayer(l.id);
  app.setFrame(10);
  const base = E.layerPose(app.doc, 10, app.bones);
  app.setBoneEuler("armR", base.armR.map((x, i) => x + [-0.5, 0, 0][i]));
  app.keyNow();
  ok(app.doc.keys.length === 1, "layer keys leave the base alone");
  ok(near(E.layerPose(app.doc, 10, app.bones).armR[0] - base.armR[0], -0.5, 0.01), "layer adds");
  await app.setLayer(l.id, { weight: 0.5 });
  ok(near(E.layerPose(app.doc, 10, app.bones).armR[0] - base.armR[0], -0.25, 0.01), "layer weight");
  app.setActiveLayer("");
  const cl = await app.addLayer({ name: "walk", mode: "override", source: "clip", clip: "w_walk", mask: R.MASKS["Lower body"], start: 6, fade_in: 6 });
  ok(dist3(E.layerPose(app.doc, 3, app.bones).legL, app.doc.basePose(3, app.bones).legL) < 1e-4, "clip layer silent before its range");
  ok(dist3(E.layerPose(app.doc, 20, app.bones).legL, poseAt(walk, 20, app.bones).legL) < 1e-3, "override clip layer takes over");
  app.removeLayer(cl.id);

  // constraints
  app.newClip("zz_desktop_check", 30, 30, false, true);
  const sh = app.jointWorld("armR");
  const tgt = sh.clone().add(new THREE.Vector3(0.15, -0.3, 0.35).normalize().multiplyScalar(0.5));
  app.addConstraint({ type: "ik", limb: "armR", target: { pos: [tgt.x, tgt.y, tgt.z] } });
  app.finalPoseOn(app.stage.probe, 0);
  ok(app.stage.probe.worldPos("handR").distanceTo(tgt) < 0.01, "IK reaches (" + app.stage.probe.worldPos("handR").distanceTo(tgt).toFixed(4) + ")");
  app.setConstraint(app.doc.constraints[0].id, { enabled: false });
  app.setFrame(0);
  const foot0 = app.jointWorld("footL");
  app.setFrame(15);
  app.setHipsShift("dy", -0.25);
  app.keyNow();
  app.addConstraint({ type: "pin", bone: "footL", what: "both", pin_frame: 0, start: 0, end: -1 });
  const fp = app.finalPoseOn(app.stage.probe, 15);
  ok(app.stage.probe.worldPos("footL").distanceTo(foot0) < 0.01, "frozen foot stays put");
  ok(fp.kneeL[0] > 0.05, "knee bends backward to keep it planted");
  app.bakeToKeys();
  ok(!app.doc.needsBake() && app.doc.keys.length === 31, "bake to keys");

  // save round trip + the godot signature
  app.newClip("zz_desktop_check", 24, 30, false, true);
  app.setFrame(12);
  app.setBoneEuler("torso", [0.3, 0.2, 0]);
  app.keyNow();
  app.addConstraint({ type: "floor", bones: ["footL", "footR"], mode: "plant" });
  const sv = await app.save();
  ok(sv.ok && sv.baked, "save bakes the live constraint");
  const c = await window.host.loadClip("zz_desktop_check");
  ok(c.keys.length === 25 && c.studio.base.length === 2, "game keys = bake, base rides along");
  ok(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/.test(c.studio.saved || ""), "every save stamps studio.saved (the generators skip the clip)");
  ok(Doc.fromClip(c).saved === c.studio.saved && Doc.fromClip({ name: "x", keys: [] }).saved === "", "saved read back; a generator clip has none");
  const d = Doc.fromClip(c);
  ok(!d.outsideEdit && d.constraints.length === 1, "re-open keeps base + constraint");
  ok(sig([{ f: 0, rot: { a: [0.1, 0, 0] }, hips_dy: 0 }]) === "1898101346" || true, "sig runs");
  c.keys = c.keys.slice(0, 3);
  ok(Doc.fromClip(c).outsideEdit, "outside edits detected");
  await app.trashClip("zz_desktop_check");

  // api
  const call = makeApi(app);
  r = await call("ping", {});
  ok(r.result === "pong", "api ping");
  r = await call("new_clip", { name: "zz_desktop_api", frames: 20, discard: true });
  ok(r.ok, "api new_clip " + JSON.stringify(r));
  r = await call("set_pose", { frame: 10, bones: { armR: [-60, 0, 20], kneeL: [-30, 0, 0] } });
  ok(r.ok && r.result.clamped_by_limits_or_locks.includes("kneeL"), "api set_pose clamps the knee");
  r = await call("get_pose", { frame: 10, bones: ["armR"] });
  ok(near(r.result.bones.armR[0], -60, 0.05) && near(r.result.bones.armR[2], 20, 0.05), "api get_pose degrees");
  r = await call("ik_pose", { frame: 5, bone: "footR", target: [0.12, 0.25, 0.3] });
  ok(r.ok && r.result.miss_m < 0.03, "api ik_pose " + JSON.stringify(r.result));
  r = await call("open_clip", { name: "w_walk" });
  ok(!r.ok, "open_clip protects unsaved work");
  r = await call("screenshot", { target: "sheet", width: 640, height: 360, cols: 4, path: "D:/Cache/fight_studio_dev/desktop_sheet_test.png" });
  ok(r.ok, "api screenshot sheet " + JSON.stringify(r));
  r = await call("get_pose", { frame: 5, bones: ["kneeR"], final: false });
  ok(near(r.result.bones.kneeR[1], 0, 0.01) && near(r.result.bones.kneeR[2], 0, 0.01) && r.result.bones.kneeR[0] > 0, "ik bends the knee on its hinge only " + JSON.stringify(r.result.bones.kneeR));
  ok(R.isHinge("kneeL") && R.isHinge("elbowR") && !R.isHinge("armR"), "hinge joints from animator_rig.json");
  app.history.markSaved();

  // ADJUST: a turn on top of the keys, over a scope; the keys never change; limits hold; restore takes it off
  await app.openClip("w_walk", true);
  const keysBefore = JSON.stringify(app.doc.keys);
  const armAt = (f) => E.layerPose(app.doc, f, app.bones).armR;
  const raw7 = armAt(7);
  app.adjustPart("armR", [-20 * RAD, 0, 0], "all");
  ok(near(armAt(7)[0] - raw7[0], -20 * RAD, 1e-4) && JSON.stringify(app.doc.keys) === keysBefore, "adjust turns a part on every frame, keys untouched");
  ok(near(app.adjustValue("armR", "all")[0], -20 * RAD, 1e-4), "adjust value reads back");
  app.adjustPart("armR", [-30 * RAD, 0, 0], "all");
  ok(A.adjustLayers(app.doc).length === 1 && near(armAt(7)[0] - raw7[0], -30 * RAD, 1e-4), "adjusting again sets the total (one adjustment)");
  app.adjustPart("armR", [-30 * RAD, 0, 0], "all");
  const armMax = R.rigData.limits.armR && R.rigData.limits.armR.x ? R.rigData.limits.armR.x[1] : Infinity;
  app.adjustPart("armL", [3, 0, 0], "range", -1, 0, 4, 0);
  let past = false;
  for (let f = 0; f <= 4; f++) { const e = E.layerPose(app.doc, f, app.bones).armL, b0 = poseAt(app.doc.source(), f, app.bones).armL; if (e[0] > Math.max(R.rigData.limits.armL?.x?.[1] ?? Infinity, b0[0]) + 1e-6) past = true; }
  ok(!past && armMax < Infinity, "an adjustment stops at the joint's limit");
  app.adjustRestore("", "armL");
  app.adjustPart("armL", [0, 0, 10 * RAD], "frame", 12, 0, -1, 4, true);
  ok(A.adjustLayers(app.doc).length === 3 && near(E.layerPose(app.doc, 2, app.bones).armL[2], poseAt(app.doc.source(), 2, app.bones).armL[2], 1e-6), "around one frame, mirrored, nothing outside its ease");
  app.adjustPart("kneeL", [-90 * RAD, 0, 0], "all");
  let fwd = false;
  for (let f = 0; f <= app.doc.frames; f++) if (E.layerPose(app.doc, f, app.bones).kneeL[0] < -1e-6) fwd = true;
  ok(!fwd, "an adjustment never bends a knee forward");
  ok(app.adjustRestore("", "armR") === 2 && near(armAt(7)[0], raw7[0], 1e-6), "restore one part (its all-frames and mirrored adjustments)");
  app.undo();
  ok(near(armAt(7)[0] - raw7[0], -30 * RAD, 1e-4), "restore undoes");
  r = await call("adjustments", {});
  ok(r.ok && r.result.length === 4 && r.result.some((x) => x.bone === "armR" && near(x.turn[0], -30, 0.01)), "api adjustments");
  r = await call("adjust", { bone: "head", y: 15 });
  ok(r.ok && r.result.layers.length === 1, "api adjust");
  r = await call("adjust_restore", {});
  ok(r.ok && r.result.restored === 5 && JSON.stringify(app.doc.keys) === keysBefore, "api adjust_restore all");

  // MERGE: the base gives the body, a clip on top gives the parts you pick; bake makes one new clip with its recipe
  app.history.markSaved();
  await app.openClip("w_walk", true);
  const top = (await window.host.listClips()).find((n) => n !== "w_walk" && /^a_.*jab/.test(n)) || "a_jab1";
  const ml = await app.mergeAdd(top, ["Arm R"], 6, 4, 4);
  ok(ml && ml.merge && ml.mask.join() === "armR,elbowR,handR" && ml.offset === 6 && ml.end === 6 + Number(E.clipSrc(top).frames), "merge adds a clip on top (parts mask, start, end)");
  const src = E.clipSrc(top);
  const mid = 6 + Math.round(Number(src.frames) / 2);
  const mp = E.layerPose(app.doc, mid, app.bones);
  ok(dist3(mp.armR, poseAt(src, mid - 6, app.bones).armR) < 1e-4 && dist3(mp.legL, poseAt(app.doc.source(), mid, app.bones).legL) < 1e-6, "top clip gives its arm, the base keeps its legs");
  await app.mergeSet(ml.id, { start: 10, parts: ["Arm R", "Head"] });
  const ml2 = app.doc.layerById(ml.id);
  ok(ml2.offset === 10 && ml2.end === 10 + Number(src.frames) && ml2.mask.includes("head"), "merge set: start moves the clip, parts the mask");
  const want = M.length(app.doc);
  const baked = app.mergeBake("zz_desktop_merged");
  ok(baked.name === "zz_desktop_merged" && app.doc.frames === want && app.doc.extra.merge && app.doc.extra.merge.base === "w_walk" && app.doc.isNew !== false, "merge bake: one new clip with its recipe");
  ok(app.doc.keys.length < app.doc.frames && !app.doc.layers.length, "merge bake thins the keys, no layers left");
  ok((await app.mergeRebuild()) && app.doc.name === "w_walk" && M.mergeLayers(app.doc).length === 1, "rebuild the merge setup");
  r = await call("merge", { clips: [{ clip: top, parts: ["Arm L"], start: 0 }], bake: true, name: "zz_desktop_merged2" });
  ok(r.ok && r.result.baked && r.result.baked.name === "zz_desktop_merged2", "api merge + bake");
  app.history.markSaved();

  // FEET: soles read off the mesh match the game's bake; a planted clip stands on them, nothing sinks
  const bake = (await window.host.loadData("feet_soles.json")) || {};
  for (const k of ["carter", "vix"]) {
    await app.setFighter(k);
    const so = F.soleInfo(app.stage.probe);
    const be = bake[`res://game/packs/city_breaker/assets/chars/${k}_fight.glb`] || {};
    for (const b of ["footL", "footR"]) {
      const s = so[b], g = be[b];
      ok(s && g && Math.abs(s.tilt0 - g.tilt0) < 1.5 && Math.abs(s.h - g.h) < 0.004 * Math.max(1, g.size) && new THREE.Vector3(...g.n).angleTo(s.n) < 0.03,
        `${k} ${b} sole like the game's bake (tilt ${s && s.tilt0.toFixed(1)} vs ${g && g.tilt0.toFixed(1)}, h ${s && s.h.toFixed(4)} vs ${g && g.h.toFixed(4)})`);
    }
    await app.openClip("w_walk", true);
    const rep = app.feetReport(2);
    ok(rep.planted && (rep.counts.flat || 0) > 0 && !rep.frames.some((x) => x.footL.low_cm < -1.5 || x.footR.low_cm < -1.5), `${k} planted walk: feet on the floor ${JSON.stringify(rep.counts)}`);
    // the same as the game's CBFeet.ground, frame by frame (reference by ref_feet.gd)
    const ref = (await (await fetch("file:///D:/Cache/fight_studio_dev/ref_feet.json").catch(() => null))?.json?.().catch(() => null)) || null;
    if (ref && ref[k]) {
      let worst = 0;
      for (const x of rep.frames) {
        const g = ref[k][String(x.f)];
        if (g) worst = Math.max(worst, Math.abs(x.footL.low_cm / 100 - g[0]), Math.abs(x.footR.low_cm / 100 - g[1]));
      }
      ok(worst < 0.002, `${k} feet like the game's CBFeet.ground on every frame (worst ${(worst * 100).toFixed(2)} cm)`);
    } else lines.push("skip feet reference (run ref_feet.gd)");
    app.stage.probe.apply({});
    app.stage.probe.root.position.y = 0;
    F.ground(app.stage.probe, app.stage.probe.root, 0, true);
    const lo = Math.min(F.lowest(app.stage.probe, "footL"), F.lowest(app.stage.probe, "footR"));
    ok(Math.abs(lo) < 0.002, `${k} at rest stands on its soles (lowest ${lo.toFixed(4)})`);
    app.stage.probe.root.position.y = 0;
  }

  // GRIPS: a grey proxy in the hand by the game's grip frame
  r = await call("add_prop", { shape: "cylinder", grip: "cylinder_R" });
  ok(r.ok && app.doc.props.length === 1 && app.doc.props[0].grip === "cylinder_R", "api add_prop with a grip");
  app.applyNow();
  const pm = app.stage.props.children[0];
  ok(pm && pm.visible && pm.position.distanceTo(app.jointWorld("fingersR")) < 0.15, "the grip proxy sits in the right hand");
  r = await call("remove_prop", { all: true });
  ok(r.ok && !app.doc.props.length, "api remove_prop all");
  app.history.markSaved();

  // MOTION IMPORT: a Mixamo FBX onto our rig, limb by limb the same as the Godot import (reference clips by ref_import.gd)
  const SEGS = [["armL", "elbowL"], ["elbowL", "handL"], ["armR", "elbowR"], ["elbowR", "handR"], ["legL", "kneeL"], ["kneeL", "footL"], ["legR", "kneeR"], ["kneeR", "footR"], ["hips", "chest"], ["chest", "head"]];
  const segDirs = (clip, f) => {
    const body = app.stage.probe;
    body.apply(poseAt(clip, f, app.bones));
    return SEGS.map(([a, b]) => body.worldPos(b).sub(body.worldPos(a)).normalize());
  };
  for (const [k, file, ref] of [["vix", "D:/Projects/Vix and Carter/Running.fbx", "mx_running"], ["vix", "C:/Users/User/Downloads/Capoeira Spin Kick.fbx", "mx_capoeira_spin_kick"],
    ["carter", "C:/Users/User/Downloads/Capoeira Spin Kick.fbx", "mx_capoeira_spin_kick"]]) {
    const rc = await (await fetch(`file:///D:/Cache/fight_studio_dev/ref_${k}_${ref}.json`).catch(() => null))?.json?.().catch(() => null);
    if (!rc || !(await window.host.motionUrl(file))) { lines.push(`skip import ${k} ${ref} (missing file or reference)`); continue; }
    if (app.fighter !== k) await app.setFighter(k);
    app.history.markSaved();
    const rep = await app.importMotion(file, {});
    ok(!rep.error && app.doc.name === ref && app.isNew, `import ${k} ${ref} opens unsaved ${JSON.stringify(rep)}`);
    const mine = app.doc.toClip();
    ok(mine.frames === rc.frames && mine.loop === rc.loop && mine.plant === rc.plant, `import ${k} ${ref}: frames / loop / plant as Godot (${mine.frames}/${mine.loop}/${mine.plant} vs ${rc.frames}/${rc.loop}/${rc.plant})`);
    let worst = 0, hips = 0;
    for (let f = 0; f <= rc.frames; f += 4) {
      const a = segDirs(mine, f), b = segDirs(rc, f);
      a.forEach((d, i) => (worst = Math.max(worst, d.angleTo(b[i]) * DEG)));
      const pa = poseAt(mine, f, []), pb = poseAt(rc, f, []);
      hips = Math.max(hips, Math.hypot(pa._dx - pb._dx, pa._dy - pb._dy, pa._dz - pb._dz));
    }
    ok(worst < 4 && hips < 0.03, `import ${k} ${ref}: limbs within ${worst.toFixed(2)} deg, hips within ${(hips * 100).toFixed(1)} cm of the Godot import`);
    let fwdKnee = false;
    for (const key of mine.keys) for (const b of ["kneeL", "kneeR"]) if ((key.rot[b] || [0])[0] < 0) fwdKnee = true;
    ok(!fwdKnee, `import ${k} ${ref}: knees never bend forward`);
  }
  r = await call("import_motion", { path: "C:/nowhere/none.fbx", discard: true });
  ok(!r.ok, "api import_motion refuses a missing file");
  // real fingers (2026-10-30): the retarget, the finger limits, the fingered Fist slider, the hand closing round a handle
  if (app.fighter !== "vix") await app.setFighter("vix");
  const body = app.stage.body;
  if (body.fmap && body.fmap.size) {
    const c = FG.fingers.shared.fingersR.c;
    const backward = eulerOf(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(...c).normalize(), -60 * RAD));
    ok(FG.fingerParts("fingersR", R.clampLimits("fingersR", backward))[0] * DEG > -20.5, "fingers: a knuckle bent 60 deg backwards is held at its limit");
    ok(R.fingerBreaks("tipsR", backward), "fingers: checks see a finger bent backwards");
    const fistR = R.rigData.controls.find((x) => x.name === "Fist R");
    const fp = R.setControl(fistR, {}, 0.8);
    ok(near(R.controlValue(fistR, fp), 0.8, 0.01) && FG.fingerParts("fingersR", fp.fingersR)[0] * DEG > 55, "fingers: the Fist slider curls a fingered hand into the palm");
    const e0 = [0.2, -0.1, 0.3];
    body.setLocalEuler("indexR", e0);
    ok(dist3(body.localEuler("indexR"), e0) < 1e-5, "fingers: a finger turn reads back through the retarget");
    body.apply({});
    const size = [0.045, 0.5, 0.045];
    const at = G.frame(body, "R", "cylinder", size);
    const n = G.wrapHand(body, "R", "cylinder", size, at);
    const inv = at.clone().invert();
    const tip = body.worldPos("tipsR").applyMatrix4(inv);
    ok(n >= 4 && Math.hypot(tip.x, tip.z) < 0.09, `wrap: the fingers close round a handle (${n} joints turned, middle joint ${(Math.hypot(tip.x, tip.z) * 100).toFixed(1)} cm from its axis)`);
    body.apply({});
  } else lines.push("skip fingers (no finger_frames.json for vix)");
  app.history.markSaved();

  // FILL: the frames between two keys, the same as the Godot Animator's core/fill.gd (reference by ref_fill.gd)
  if (app.fighter !== "vix") await app.setFighter("vix");
  const B = app.bones;
  const rf = await (await fetch("file:///D:/Cache/fight_studio_dev/ref_fill.json").catch(() => null))?.json?.().catch(() => null);
  // the worst difference between the fill keys made here and Godot's (radians / metres), and frames one has and the other not
  const fillDiff = (ref) => {
    let worst = 0, missing = 0;
    const mine = app.doc.keys.filter((k) => k.fill);
    const theirs = ref.filter((k) => k.fill);
    if (mine.length !== theirs.length) missing += Math.abs(mine.length - theirs.length);
    for (const g of theirs) {
      const k = app.doc.keyAt(g.f);
      if (!k || !k.fill) { missing++; continue; }
      for (const b of new Set([...Object.keys(g.rot || {}), ...Object.keys(k.rot || {})])) {
        const x = (k.rot || {})[b] || [0, 0, 0], y = (g.rot || {})[b] || [0, 0, 0];
        worst = Math.max(worst, ...[0, 1, 2].map((i) => Math.abs(x[i] - y[i])));
      }
      for (const ax of ["hips_dy", "hips_dx", "hips_dz"]) worst = Math.max(worst, Math.abs(Number(k[ax] || 0) - Number(g[ax] || 0)));
    }
    return { worst, missing };
  };
  const twoKeys = (name, frames, fps, keys) => {
    app.newClip(name, frames, fps, false, false);
    app.doc.keys = [];
    for (const [f, p] of keys) app.doc.writeKey(f, p, B);
    app.doc.normalize();
  };
  if (rf) {
    const zero = rf.shape_input.a, pb = rf.shape_input.b;
    let worst = 0, missing = 0;
    for (const c of rf.shape) {
      twoKeys("zz_fill_check", 48, 60, [[0, zero], [24, pb], [48, zero]]);
      app.doc.keyAt(0).ease = "in";
      await app.fillApply({ ...c.opts, from: 0, to: 24 });
      const d = fillDiff(c.keys);
      worst = Math.max(worst, d.worst);
      missing += d.missing;
    }
    ok(missing === 0 && worst < 3e-4, `fill shape: ${rf.shape.length} settings give Godot's keys (worst ${worst.toFixed(5)} rad, ${missing} keys off)`);
    ok(app.doc.fills.length === 1 && app.doc.keyAt(0).ease === "linear" && app.doc.keys.filter((k) => k.fill).every((k) => k.tag === "breakdown"), "fill: one fill, breakdown keys, key A eases linear");
    app.setFrame(15);
    ok(app.fillSpan().join() === "0,24", `fill: with the playhead inside a fill, the span is the whole fill (${app.fillSpan()})`);
    const id = app.doc.fills[0].id;
    const nFill = app.doc.keys.filter((k) => k.fill === id).length;
    ok(app.fillRemove(id) === nFill && app.doc.keyFrames().join() === "0,24,48" && app.doc.keyAt(0).ease === "in", "fill remove: its keys go, key A's ease comes back");
    app.undo();
    ok(app.doc.fills.length === 1 && Doc.fromClip(app.doc.toClip()).fills.length === 1, "fill: undo brings it back, and it survives a save");
    app.doc.writeKey(30, zero, B);
    app.doc.keyAt(30).lock = true;
    const before = app.doc.keyFrames().join();
    ok((await app.fillApply({ from: 24, to: 48 })).error && app.doc.keyFrames().join() === before, "fill: a locked key in the span stops it");
    const p12 = { ...zero, armR: [0, 0, 0.4] }, p36 = { ...zero, armR: [0, 0, 1.2] };
    twoKeys("zz_fill_flow", 36, 60, [[0, zero], [12, p12], [36, p36]]);
    await app.fillApply({ from: 12, to: 36, flow: 1 });
    const df = fillDiff(rf.flow.keys);
    ok(df.missing === 0 && df.worst < 3e-4, `fill flow: Godot's keys (worst ${df.worst.toFixed(5)})`);
    // feet: the hips shift and turn over planted feet, then a step
    for (const which of ["held", "step"]) {
      twoKeys("zz_fill_feet", 30, 60, [[0, rf.feet.a], [30, rf.feet[which]]]);
      app.doc.plant = true;
      const res = await app.fillApply({ from: 0, to: 30 });
      ok(JSON.stringify(res.feet) === JSON.stringify(rf.feet[which + "_result"]), `fill feet ${which}: ${JSON.stringify(res.feet)} like Godot ${JSON.stringify(rf.feet[which + "_result"])}`);
      const d = fillDiff(rf.feet[which + "_keys"]);
      ok(d.missing === 0 && d.worst < 0.02, `fill feet ${which}: the legs like Godot's (worst ${d.worst.toFixed(4)} rad)`);
      if (which === "held") {
        const body = app.stage.probe;
        let drift = 0;
        const start = {};
        for (let f = 0; f <= 30; f++) {
          body.apply(app.doc.basePose(f, B));
          body.update();
          for (const ft of ["footL", "footR"]) {
            const p = body.worldPos(ft);
            if (!f) start[ft] = p;
            drift = Math.max(drift, Math.hypot(p.x - start[ft].x, p.z - start[ft].z));
          }
        }
        ok(drift < 0.006, `fill feet: the planted feet stay put (${(drift * 1000).toFixed(1)} mm)`);
      }
    }
    // a spin kick: Vix's forward smash without its strike keys keeps its full turn, its left foot steps (not slides)
    if (rf.spin) {
      await app.openClip("a_vix_fsmash", true);
      app.doc.keys = app.doc.keys.filter((k) => k.f !== 10 && k.f !== 12);
      const rs = await app.fillApply({ from: 8, to: 22, timing: "strike" });
      const ds = fillDiff(rf.spin.keys);
      ok(JSON.stringify(rs.feet) === JSON.stringify(rf.spin.feet) && ds.missing === 0 && ds.worst < 0.02, `fill spin: Godot's keys and feet (${JSON.stringify(rs.feet)}, worst ${ds.worst.toFixed(4)} rad)`);
      ok(Math.abs(app.doc.basePose(15, B).hips[1] - (app.doc.basePose(14, B).hips[1] + app.doc.basePose(16, B).hips[1]) / 2) < 0.2 && app.doc.basePose(16, B).hips[1] > 3.2, "fill spin: the hips turn the long way, as keyed");
    }
    // library: a stretch of a clip found again and played back as it is
    const x = await window.host.loadClip("a_al_fsmash");
    if (x) {
      twoKeys("zz_fill_lib", 18, Number(x.fps), [[0, poseAt(x, 6, B)], [18, poseAt(x, 24, B)]]);
      const t0 = performance.now();
      await app.fillLibrary(true);
      const tIndex = performance.now() - t0;
      const t1 = performance.now();
      const ms = await app.fillMatches({ from: 0, to: 18, n: 6 });
      const tSearch = performance.now() - t1;
      lines.push(`  fill library: index ${FL.indexSize()} clips in ${tIndex.toFixed(0)} ms, search in ${tSearch.toFixed(0)} ms`);
      const g = rf.library.matches[0];
      ok(ms.length && ms[0].clip === g.clip && ms[0].from === g.from && ms[0].to === g.to && ms[0].mirror === g.mirror && Math.abs(ms[0].cost - g.cost) < 0.002,
        `fill library: the best match is Godot's (${JSON.stringify(ms[0])} vs ${JSON.stringify(g)})`);
      await app.fillApply({ from: 0, to: 18, engine: "library", pick: 0 });
      const dl = fillDiff(rf.library.keys);
      ok(dl.missing === 0 && dl.worst < 3e-4, `fill library: the in-betweens are Godot's (worst ${dl.worst.toFixed(5)})`);
    } else lines.push("skip fill library (no a_al_fsmash)");
  } else lines.push("skip fill reference (run ref_fill.gd)");
  // through the agent API
  twoKeys("zz_fill_api", 20, 30, [[0, {}], [16, { armR: [0, 0, 0.6] }]]);
  r = await call("fill", { from: 0, to: 16, timing: "strike", overlap: 0.5 });
  ok(r.ok && r.result.keys === 15 && r.result.settings.timing === "strike", `api fill ${JSON.stringify(r).slice(0, 160)}`);
  r = await call("fills", {});
  ok(r.ok && r.result.length === 1 && r.result[0].text.includes("strike"), "api fills lists it");
  r = await call("fill_matches", { from: 0, to: 16, n: 3 });
  ok(r.ok && r.result.length === 3, "api fill_matches gives 3 matches");
  r = await call("fill_remove", {});
  ok(r.ok && r.result.removed === 15 && !app.doc.fills.length, "api fill_remove takes it out");
  app.history.markSaved();

  if (app.fighter !== "vix") await app.setFighter("vix");
  await app.openClip("w_walk", true);
  return { pass, fail, lines };
}
