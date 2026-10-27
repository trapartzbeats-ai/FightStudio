"""bpy script v2: author the City Breaker fight clips that a baked fighter is missing.

Injected by author_clips2.py (__PATH__ / __PREFIX__). Every existing action is kept; a clip is only added when the
file does not have it yet. Adds (if missing):
  guard roll hit_light hit_heavy land            (the first batch, vix + carter already have them)
  jump fall doubleJump airDodge dash tumble      (air + movement batch: the fighter used to hold fightIdle in the air)
Every clip keys EVERY bone so no pose bleeds from the previous action. Renders a still per new clip to D:/Cache/anim_preview.
"""

import math
import os

import bpy
from mathutils import Euler, Vector

PATH = r"__PATH__"
PREFIX = "__PREFIX__"
PREVIEW_DIR = r"D:/Cache/anim_preview"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=PATH)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
if arm.animation_data is None:
    arm.animation_data_create()
ALL_BONES = [b.name for b in arm.pose.bones]
REPLACE = {"guard", "roll", "hit_light", "hit_heavy", "land", "jump", "fall", "doubleJump", "airDodge", "dash", "tumble"}   # v2: knees bent the wrong way in v1
for _n in REPLACE:
    _a = bpy.data.actions.get(_n)
    if _a is not None:
        bpy.data.actions.remove(_a)
HAVE = {a.name for a in bpy.data.actions}
print("HAVE", sorted(HAVE))


# ---- conventions measured on rig v4 (character faces -Y, up +Z; probe in D:/Cache/axes_probe.py):
#   thigh X: negative = thigh forward (hip flexion); knee X: POSITIVE = knee flexion (shin swings back); foot X + = toes down
#   arm X: negative = arm raised forward; elbow X: negative = flexion; armL Z negative / armR Z positive = arm out to the side
#   legL Z negative / legR Z positive = leg out to the side; torso/chest/head X positive = lean forward
#   hips: rotation X + = forward somersault, Y = yaw; location local Y = up
L1, L2 = 0.574, 0.546   # thigh and shin length (m)
LEAN_K = {"bigbill": 0.3}.get(PREFIX, 1.0)   # Big Bill is a burrito: his torso is one lump, so lean a lot less


def pose(**kw):
    """Semantic pose -> bone rotations. thigh/knee/foot/arm/elbow take (left, right) pairs or one number for both."""
    def two(v):
        return v if isinstance(v, tuple) else (v, v)
    p = {}
    tl, tr = two(kw.get("thigh", 0.0)); kl, kr = two(kw.get("knee", 0.0)); fl, fr = two(kw.get("foot", 0.0))
    al, ar = two(kw.get("arm", 0.0)); el, er = two(kw.get("elbow", 0.0))
    ao = kw.get("arm_out", 0.0); lo = kw.get("leg_out", 0.0)
    p["legL"] = (-tl, 0.0, -lo); p["legR"] = (-tr, 0.0, lo)
    p["kneeL"] = (kl, 0.0, 0.0); p["kneeR"] = (kr, 0.0, 0.0)
    p["footL"] = (fl, 0.0, 0.0); p["footR"] = (fr, 0.0, 0.0)
    p["armL"] = (-al, 0.0, -ao); p["armR"] = (-ar, 0.0, ao)
    p["elbowL"] = (-el, 0.0, 0.0); p["elbowR"] = (-er, 0.0, 0.0)
    lean = kw.get("lean", 0.0) * LEAN_K
    p["torso"] = (lean * 0.45, kw.get("twist", 0.0), 0.0)
    p["chest"] = (lean * 0.35, kw.get("twist", 0.0) * 0.4, 0.0)
    p["head"] = (kw.get("head", lean * 0.2), -kw.get("twist", 0.0) * 0.8, 0.0)
    return p


def squat(a):
    """Both feet stay under the hips: thigh forward a, knee bent so the shin is near vertical; returns (thigh, knee, hips drop)."""
    k = a + math.asin(min(1.0, L1 * math.sin(a) / L2))
    drop = (L1 + L2) - (L1 * math.cos(a) + L2 * math.cos(k - a))
    return a, k, -drop


def key(frame, p, spin=(0.0, 0.0, 0.0), dz=0.0):
    """Key EVERY bone every time (no bleed between clips). spin = hips rotation (centre of mass), dz = hips height change (m)."""
    for name in ALL_BONES:
        pb = arm.pose.bones.get(name)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        if name in ("kneeL", "kneeR") and p.get(name, (0.0, 0.0, 0.0))[0] < -0.01:
            raise ValueError("%s would bend forward (knee X must be >= 0): %r" % (name, p.get(name)))
        rot = tuple(sp + p.get("hips", (0.0, 0.0, 0.0))[i] for i, sp in enumerate(spin)) if name == "hips" else p.get(name, (0.0, 0.0, 0.0))
        pb.rotation_quaternion = Euler(rot, "XYZ").to_quaternion()
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if name == "hips":
            pb.location = (0.0, dz, 0.0)
            pb.keyframe_insert("location", frame=frame)


def new_action(name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
    return act


def blend(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, (0.0, 0.0, 0.0)), b.get(k, (0.0, 0.0, 0.0))
        out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out


NEUTRAL = {}
_t, _k, _dz = squat(0.45)
GUARD = pose(thigh=(_t + 0.1, _t - 0.1), knee=(_k + 0.15, _k - 0.1), arm=0.55, elbow=1.9, arm_out=-0.05, lean=0.45, twist=0.28, head=0.12, leg_out=0.08)
GUARD_DZ = _dz
HIT_LIGHT = pose(thigh=0.15, knee=0.3, arm=0.5, arm_out=0.5, elbow=0.7, lean=-0.5, head=-0.3)
HIT_HEAVY = pose(thigh=(0.55, -0.1), knee=(0.95, 0.45), foot=(0.6, 0.0), arm=0.9, arm_out=0.9, elbow=0.4, lean=-1.1, head=-0.6)
_t, _k, _dz = squat(0.95)
LAND = pose(thigh=_t, knee=_k, arm=0.3, arm_out=0.6, elbow=0.4, lean=1.0)
LAND_DZ = _dz
_t, _k, _dz = squat(0.7)
CROUCH = pose(thigh=_t, knee=_k, arm=-0.6, elbow=0.3, lean=0.8)
CROUCH_DZ = _dz
TUCK = pose(thigh=1.7, knee=2.3, arm=1.1, arm_out=-0.1, elbow=1.6, lean=1.5, head=0.35)
JUMP_RISE = pose(thigh=(0.9, -0.15), knee=(1.4, 0.6), foot=(0.2, 0.7), arm=0.8, arm_out=0.35, elbow=0.5, lean=-0.1)
STRETCH = pose(thigh=-0.05, knee=0.1, foot=0.8, arm=1.5, arm_out=0.3, elbow=0.15, lean=-0.2)
FALL_A = pose(thigh=(0.45, -0.2), knee=(0.75, 0.6), foot=0.3, arm=0.3, arm_out=1.0, elbow=0.35, lean=-0.1)
FALL_B = pose(thigh=(0.3, 0.15), knee=(0.6, 0.55), foot=0.3, arm=0.15, arm_out=1.15, elbow=0.25, lean=-0.1, head=-0.15)
AIR_DODGE = pose(thigh=0.1, knee=0.3, arm=0.0, arm_out=1.45, elbow=0.1, leg_out=0.25, lean=0.2)
DASH = pose(thigh=(0.8, -0.7), knee=(0.6, 1.4), foot=(0.0, 0.9), arm=(-0.6, 0.9), elbow=(1.0, 1.2), lean=1.0, head=-0.5)
TUMBLE = pose(thigh=0.3, knee=0.5, arm=0.2, arm_out=1.0, elbow=0.5, leg_out=0.5, lean=0.3, head=-0.3)
TAU = math.tau


def add(name, builder):
    if name in HAVE:
        return False
    new_action(name)
    builder()
    return True


def b_guard():
    key(1, NEUTRAL); key(6, GUARD, dz=GUARD_DZ); key(30, GUARD, dz=GUARD_DZ); key(40, NEUTRAL)


def b_hit_light():
    key(1, NEUTRAL); key(3, HIT_LIGHT, spin=(-0.15, 0, 0)); key(10, HIT_LIGHT, spin=(-0.15, 0, 0)); key(18, NEUTRAL)


def b_hit_heavy():
    key(1, NEUTRAL); key(4, HIT_HEAVY, spin=(-0.4, 0, 0)); key(16, HIT_HEAVY, spin=(-0.4, 0, 0)); key(28, NEUTRAL)


def b_land():
    key(1, LAND, dz=LAND_DZ); key(6, LAND, dz=LAND_DZ); key(14, NEUTRAL)


def b_roll():
    key(1, NEUTRAL); key(3, CROUCH, dz=CROUCH_DZ); key(5, TUCK, dz=-0.55)
    key(9, TUCK, spin=(math.pi, 0, 0), dz=-0.55); key(13, TUCK, spin=(TAU, 0, 0), dz=-0.55)
    key(15, CROUCH, spin=(TAU, 0, 0), dz=CROUCH_DZ); key(18, NEUTRAL, spin=(TAU, 0, 0))


def b_jump():
    key(1, NEUTRAL); key(4, CROUCH, dz=CROUCH_DZ); key(7, STRETCH); key(16, JUMP_RISE); key(22, blend(JUMP_RISE, FALL_A, 0.5))


def b_fall():
    key(1, FALL_A); key(13, FALL_B); key(25, FALL_A)


def b_double_jump():
    key(1, JUMP_RISE); key(4, TUCK); key(9, TUCK, spin=(math.pi, 0, 0)); key(14, TUCK, spin=(TAU, 0, 0)); key(19, FALL_A, spin=(TAU, 0, 0))


def b_air_dodge():
    key(1, NEUTRAL); key(3, AIR_DODGE); key(8, AIR_DODGE, spin=(0, math.pi, 0)); key(13, AIR_DODGE, spin=(0, TAU, 0)); key(17, FALL_A, spin=(0, TAU, 0))


def b_dash():
    key(1, NEUTRAL); key(4, DASH, dz=-0.05); key(12, DASH, dz=-0.05); key(18, NEUTRAL)


def b_tumble():
    key(1, TUMBLE); key(10, TUMBLE, spin=(math.pi, 0, 0)); key(19, TUMBLE, spin=(TAU, 0, 0))


ORDER = [("guard", b_guard, 18), ("roll", b_roll, 8), ("hit_light", b_hit_light, 6), ("hit_heavy", b_hit_heavy, 8), ("land", b_land, 4),
         ("jump", b_jump, 8), ("fall", b_fall, 6), ("doubleJump", b_double_jump, 9), ("airDodge", b_air_dodge, 8), ("dash", b_dash, 8), ("tumble", b_tumble, 6)]
added = [n for n, fn, _ in ORDER if add(n, fn)]
print("ADDED", added)

if added:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 360
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 1.05))
    cam.location = target + Vector((7.0, 0.0, 0.3))
    cam.rotation_euler = (target - cam.location).normalized().to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 42
    for clip, _fn, frame in ORDER:
        if clip not in added:
            continue
        arm.animation_data.action = bpy.data.actions[clip]
        scene.frame_set(frame)
        scene.render.filepath = f"{PREVIEW_DIR}/{PREFIX}_{clip}.png"
        bpy.ops.render.render(write_still=True)
        # front view too (the character faces -Y): checks arms out to the side, legs apart
        cam.location = target + Vector((0.0, -7.0, 0.3))
        cam.rotation_euler = (target - cam.location).normalized().to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = f"{PREVIEW_DIR}/{PREFIX}_{clip}_front.png"
        bpy.ops.render.render(write_still=True)
        cam.location = target + Vector((7.0, 0.0, 0.3))
        cam.rotation_euler = (target - cam.location).normalized().to_track_quat("-Z", "Y").to_euler()

arm.animation_data.action = bpy.data.actions.get("fightIdle")
bpy.ops.export_scene.gltf(filepath=PATH, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS", export_yup=True)
print("KNEECHECK OK (key() refuses a knee that bends forward)")
print("WROTE", PATH)
