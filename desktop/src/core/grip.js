// Held objects sit in the hand the same way in the game and in Fight Studio (a port of the game's grip.gd, CBGrip): a frame
// built from the hand's own bones every frame (never a bone-attachment offset, which differs per model). Three kinds:
//   cylinder - can, bottle, bat / sword handle: inside the finger curl, the axis (Y) along the knuckle line pinky -> index
//   sphere   - ball, bomb, orb: cupped in front of the palm
//   block    - box, phone, card: flat on the palm, its long side (Y) along the fingers
// size = the object's extents in metres (cylinder x = diameter, y = length; sphere x = diameter; block x, y, z). Frame axes:
// Y = the object's axis, Z = out of the palm. Pair each kind with its hand pose: data/poses/grip_<kind>_<side>.json.
import * as THREE from "three";

export const KINDS = ["cylinder", "sphere", "block"];
export const PROXY_SIZES = { block: [0.08, 0.15, 0.02], cylinder: [0.084, 0.16, 0.084], sphere: [0.22, 0.22, 0.22] };

const at = (body, n) => (body.has(n) ? body.worldPos(n) : null);

// the hand's own frame: wrist -> knuckles (along), pinky -> index (across), and which way the palm faces (palm)
export function handAxes(body, side) {
  const hand = at(body, "hand" + side), fing = at(body, "fingers" + side), tips = at(body, "tips" + side);
  const idx = at(body, "index" + side), pin = at(body, "pinky" + side);
  if (!hand || !fing) return null;
  const along = fing.clone().sub(hand);
  const reach = along.length();
  along.normalize();
  let across = idx && pin ? idx.clone().sub(pin) : new THREE.Vector3();
  across.sub(along.clone().multiplyScalar(across.dot(along)));
  if (across.length() < 0.002) across = along.clone().cross(new THREE.Vector3(0, 1, 0));
  across.normalize();
  // the palm, from the hand's handedness: fingers forward + thumb side up -> a right palm faces the body's midline
  const palm = along.clone().cross(across).multiplyScalar(side === "R" ? 1 : -1).normalize();
  return { hand, fing, tips: tips || fing.clone().add(along.clone().multiplyScalar(reach * 0.6)), along, across, palm, reach };
}

// where a held object sits (a world Matrix4) for the current pose
export function frame(body, side, kind, size) {
  const a = handAxes(body, side);
  if (!a) return new THREE.Matrix4();
  let y = a.along.clone();
  let center;
  // the bones run through the middle of the hand: everything sits out past the palm skin (about a fifth of the wrist ->
  // knuckle length), or a block vanishes into the palm
  const pd = a.reach * 0.2;
  if (kind === "cylinder") {   // in the tunnel the curled fingers make, under the knuckles
    y = a.across.clone();
    center = a.fing.clone().add(a.palm.clone().multiplyScalar(size[0] * 0.5 + pd * 0.6)).sub(a.along.clone().multiplyScalar(a.reach * 0.12));
  } else if (kind === "sphere") {   // cupped: in front of the palm, between the wrist and the knuckles
    center = a.hand.clone().lerp(a.fing, 0.55).add(a.palm.clone().multiplyScalar(size[0] * 0.5 + pd * 0.5));
  } else {   // flat on the palm, the long side along the fingers
    center = a.hand.clone().lerp(a.fing, 0.55).add(a.palm.clone().multiplyScalar(size[2] * 0.5 + pd));
  }
  let z = a.palm.clone().sub(y.clone().multiplyScalar(a.palm.dot(y)));
  if (z.length() < 0.001) z = y.clone().cross(new THREE.Vector3(1, 0, 0));
  z.normalize();
  const x = y.clone().cross(z).normalize();
  return new THREE.Matrix4().makeBasis(x, y, z).setPosition(center);
}

// a grey proxy of a kind and size (for placement work)
export function proxyGeometry(kind, size) {
  if (kind === "cylinder") return new THREE.CylinderGeometry(size[0] * 0.5, size[0] * 0.5, size[1], 20);
  if (kind === "sphere") return new THREE.SphereGeometry(size[0] * 0.5, 24, 16);
  return new THREE.BoxGeometry(size[0], size[1], size[2]);
}
