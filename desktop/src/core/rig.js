// What the app knows about rig v4 (shared with the Godot Animator: the same data/animator_rig.json): groups, masks, limbs,
// mirror names, axis hints, joint limits (a knee never bends forward) and controls (one slider, many bones).
import { clamp } from "./clip.js";

export const GROUPS = [
  ["Body", ["root", "hips", "torso", "chest", "neck", "head"]],
  ["Arm L", ["armL", "elbowL", "handL"]],
  ["Arm R", ["armR", "elbowR", "handR"]],
  ["Hand L", ["fingersL", "tipsL", "nailL", "thumbL", "thumbL2", "indexL", "indexL2", "indexL3", "ringL", "ringL2", "ringL3", "pinkyL", "pinkyL2", "pinkyL3"]],
  ["Hand R", ["fingersR", "tipsR", "nailR", "thumbR", "thumbR2", "indexR", "indexR2", "indexR3", "ringR", "ringR2", "ringR3", "pinkyR", "pinkyR2", "pinkyR3"]],
  ["Leg L", ["legL", "kneeL", "footL"]],
  ["Leg R", ["legR", "kneeR", "footR"]],
];

export const MASKS = {
  "Full body": [],
  "Upper body": ["torso", "chest", "neck", "head", "armL", "elbowL", "handL", "armR", "elbowR", "handR", "@Hand L", "@Hand R"],
  "Lower body": ["hips", "legL", "kneeL", "footL", "legR", "kneeR", "footR"],
  Arms: ["armL", "elbowL", "handL", "armR", "elbowR", "handR", "@Hand L", "@Hand R"],
  "Arm L": ["armL", "elbowL", "handL", "@Hand L"],
  "Arm R": ["armR", "elbowR", "handR", "@Hand R"],
  Legs: ["legL", "kneeL", "footL", "legR", "kneeR", "footR"],
  Head: ["neck", "head", "@Ears"],
  Spine: ["torso", "chest", "neck"],
  Hands: ["@Hand L", "@Hand R"],
  Tail: ["@Tail"],
};

export const LIMBS = {
  armL: ["armL", "elbowL", "handL"], armR: ["armR", "elbowR", "handR"],
  legL: ["legL", "kneeL", "footL"], legR: ["legR", "kneeR", "footR"],
};

const HINTS = {
  leg: "X - thigh forward, + back   Z leg out to the side   Y turn the leg",
  knee: "X + bends the knee (never negative: a knee does not bend forward)",
  foot: "X + points the toes down",
  arm: "X - raises the arm forward, + swings it back   Z arm out to the side",
  elbow: "X - bends the elbow",
  hand: "X bends the wrist   Z tilts it",
  torso: "X + leans forward   Y twist   Z side lean",
  chest: "X + leans forward   Y twist   Z side lean",
  neck: "X + nods forward   Y turn",
  head: "X + nods forward   Y turns the head   Z tilts it",
  hips: "whole body turns about the hips: X + forward somersault, Y spin, Z roll. Move = hips dx / dy / dz",
  root: "the feet point; clips leave it at rest",
  tail: "X curls the tail up / down   Z swishes it side to side",
  fingers: "X curls the fingers   Z spreads them",
  tips: "X curls the last finger joint",
  thumb: "X curls the thumb   Z swings it away from the hand",
  ear: "X folds the ear forward / back   Z tilts it",
  crest: "X bends the crest forward / back   Z tilts it",
  pom: "X / Z tip the pompom",
  fin: "X / Z tilt the fin",
};

export const DEFAULT_LIMITS = {
  kneeL: { x: [0.0, 2.7] }, kneeR: { x: [0.0, 2.7] },
  elbowL: { x: [-2.75, 0.08] }, elbowR: { x: [-2.75, 0.08] },
};

export const DEFAULT_CONTROLS = [
  { name: "Fist L", min: 0, max: 1, drives: [["fingersL", 0, -1.45], ["tipsL", 0, -1.25], ["thumbL", 0, -0.7], ["thumbL2", 0, -0.5]] },
  { name: "Fist R", min: 0, max: 1, drives: [["fingersR", 0, -1.45], ["tipsR", 0, -1.25], ["thumbR", 0, -0.7], ["thumbR2", 0, -0.5]] },
  { name: "Spine bend", min: -1, max: 1, drives: [["torso", 0, 0.35], ["chest", 0, 0.35], ["neck", 0, 0.15], ["head", 0, 0.15]] },
  { name: "Spine twist", min: -1, max: 1, drives: [["torso", 1, 0.3], ["chest", 1, 0.3], ["neck", 1, 0.2], ["head", 1, 0.2]] },
  { name: "Spine side", min: -1, max: 1, drives: [["torso", 2, 0.25], ["chest", 2, 0.25], ["neck", 2, 0.1]] },
  { name: "Head look", min: -1, max: 1, drives: [["neck", 1, 0.45], ["head", 1, 0.75]] },
  { name: "Head nod", min: -1, max: 1, drives: [["neck", 0, 0.3], ["head", 0, 0.45]] },
  { name: "Crouch", min: 0, max: 1, drives: [["legL", 0, -0.95], ["legR", 0, -0.95], ["kneeL", 0, 1.7], ["kneeR", 0, 1.7], ["footL", 0, -0.7], ["footR", 0, -0.7], ["torso", 0, 0.25], ["hips", "dy", -0.32]] },
  { name: "Guard up", min: 0, max: 1, drives: [["armL", 0, -0.9], ["armR", 0, -0.9], ["elbowL", 0, -2.0], ["elbowR", 0, -2.0], ["armL", 2, -0.25], ["armR", 2, 0.25]] },
  { name: "Tail curl", min: -1, max: 1, drives: [["tail", 0, 0.35], ["tail2", 0, 0.45], ["tail3", 0, 0.55]] },
  { name: "Tail sway", min: -1, max: 1, drives: [["tail", 2, 0.3], ["tail2", 2, 0.4], ["tail3", 2, 0.5]] },
  { name: "Ears back", min: -1, max: 1, drives: [["earL", 0, 0.6], ["earR", 0, 0.6], ["earL2", 0, 0.3], ["earR2", 0, 0.3]] },
];

export const rigData = { controls: DEFAULT_CONTROLS.map((c) => structuredClone(c)), limits: structuredClone(DEFAULT_LIMITS) };
let rigFile = {};   // the whole file as read: its other fields (hinge, notes) are written back untouched

export async function loadRigData() {
  const d = await window.host.loadData("animator_rig.json");
  if (d && d.controls) {
    rigFile = d;
    rigData.controls = d.controls;
    rigData.limits = d.limits || structuredClone(DEFAULT_LIMITS);
  } else {
    await saveRigData();
  }
}

// joints that bend on one axis only (data/animator_rig.json "hinge"): the IK bends them on X and turns the limb to the pole
export const isHinge = (b) => (rigFile.hinge || ["elbowL", "elbowR", "kneeL", "kneeR"]).includes(b);

export function saveRigData() {
  return window.host.saveData("animator_rig.json", { ...rigFile, version: rigFile.version ?? 1, controls: rigData.controls, limits: rigData.limits });
}

export function groupOf(b) {
  for (const [g, list] of GROUPS) if (list.includes(b)) return g;
  if (b.startsWith("tail")) return "Tail";
  if (b.startsWith("ear")) return "Ears";
  return "Extras";
}

export function grouped(bones) {
  const order = GROUPS.map((g) => g[0]).concat(["Tail", "Ears", "Extras"]);
  const by = {};
  for (const b of bones) (by[groupOf(b)] ||= []).push(b);
  return order.filter((g) => by[g]).map((g) => [g, by[g]]);
}

export function maskBones(mask, bones) {
  if (!mask || !mask.length) return [...bones];
  const out = [];
  for (const m of mask) {
    if (String(m).startsWith("@")) {
      for (const b of bones) if (groupOf(b) === m.slice(1) && !out.includes(b)) out.push(b);
    } else if (bones.includes(m) && !out.includes(m)) out.push(m);
  }
  return out;
}

const MIRROR_RE = /^(.*?)([LR])(\d*)$/;
export function mirrorName(b) {
  const m = MIRROR_RE.exec(b);
  return m ? m[1] + (m[2] === "L" ? "R" : "L") + m[3] : b;
}

export function sideOf(b) {
  if (mirrorName(b) === b) return "";
  return MIRROR_RE.exec(b)[2];
}

export const mirrorEuler = (e) => [e[0], -e[1], -e[2]];

export function hint(b) {
  const keys = Object.keys(HINTS).sort((a, c) => c.length - a.length);
  for (const k of keys) if (b.startsWith(k)) return HINTS[k];
  return "X / Y / Z turn the bone about its own axes";
}

export function clampLimits(b, e) {
  const lim = rigData.limits[b];
  if (!lim) return e;
  const out = [...e];
  ["x", "y", "z"].forEach((ax, i) => {
    if (lim[ax]) out[i] = clamp(out[i], lim[ax][0], lim[ax][1]);
  });
  return out;
}

// an edit on top of the clip never turns a joint past its rig limits (knees never bend forward); where the clip itself is
// already past a limit, the clip's own value is the edge (an edit never makes it worse)
export function withinLimits(b, e, before) {
  const lim = rigData.limits[b];
  if (!lim) return e;
  const out = [...e];
  ["x", "y", "z"].forEach((ax, i) => {
    if (lim[ax]) out[i] = clamp(e[i], Math.min(lim[ax][0], before[i]), Math.max(lim[ax][1], before[i]));
  });
  return out;
}

export function breaksLimits(b, e) {
  const c = clampLimits(b, e);
  return Math.hypot(c[0] - e[0], c[1] - e[1], c[2] - e[2]) > 0.01;
}

export function limbOfEnd(b) {
  for (const k in LIMBS) if (LIMBS[k][2] === b) return k;
  return "";
}

function chan(pose, bone, ax) {
  if (typeof ax === "string") return Number(pose["_" + ax] || 0);
  return (pose[bone] || [0, 0, 0])[ax];
}

function setChan(pose, bone, ax, v) {
  if (typeof ax === "string") { pose["_" + ax] = v; return; }
  const e = [...(pose[bone] || [0, 0, 0])];
  e[ax] = v;
  pose[bone] = e;
}

export function controlValue(ctl, pose) {
  let num = 0, den = 0;
  for (const d of ctl.drives || []) {
    const amt = Number(d[2]);
    num += amt * chan(pose, d[0], d[1]);
    den += amt * amt;
  }
  return den > 0 ? num / den : 0;
}

export function setControl(ctl, pose, value) {
  const out = { ...pose };
  const cur = controlValue(ctl, pose);
  for (const d of ctl.drives || []) setChan(out, d[0], d[1], chan(out, d[0], d[1]) + (value - cur) * Number(d[2]));
  return out;
}
