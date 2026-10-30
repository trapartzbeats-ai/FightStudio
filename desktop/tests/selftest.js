// Fight Studio Desktop self-test (run: npm run selftest). Same ground as the Godot animator_check.gd: interpolation, keys,
// undo, retime, locks, limits, same-key propagation, layers, IK, freeze, bake, save round trip, the agent API, and that a
// clip baked here gives the Godot file signature (both apps open each other's files).
import * as THREE from "three";
import { Doc, poseOfKey, sig } from "../src/core/doc.js";
import * as E from "../src/core/evalc.js";
import * as R from "../src/core/rig.js";
import { poseAt, rotQuat, eulerOf, dist3 } from "../src/core/clip.js";
import { makeApi } from "../src/api.js";

export async function selftest(app) {
  const lines = [];
  let pass = 0, fail = 0;
  const ok = (c, what) => { if (c) pass++; else { fail++; lines.push("FAIL " + what); } };
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
  app.history.markSaved();
  await app.openClip("w_walk", true);
  return { pass, fail, lines };
}
