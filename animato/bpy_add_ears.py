"""bpy script: give a City Breaker fighter ear bones (earL/earL2/earL3, earR/earR2/earR3) so ears can bend, flop and swing.

Injected by add_ears.py (__PATH__ / __KEY__ / __REGIONS__ = {side: {...}} for this fighter). The ear = the head-mesh vertices inside a
box (offsets from the head bone, metres, Blender axes: x sideways, y depth (-y = front), z up). Weights run along the ear's height:
base joint -> mid -> tip, fading out of the head at the bottom so there is no tear. New bones are children of `head`, point up, and
use the same world-aligned axes as the rest of the rig (X bends forward/back, Z tilts sideways).
A preview still with the ears bent is written to D:/Cache/ears_preview/<key>_ears.png.
"""
import json
import math
import os

import bpy
from mathutils import Euler, Vector

PATH = r"__PATH__"
KEY = "__KEY__"
REG = json.loads(r'''__REGIONS__''')

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=PATH)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith("_mesh"))
head_w = arm.matrix_world @ arm.pose.bones["head"].head
inv = arm.matrix_world.inverted()

FIRST = REG[0]["name"]
if FIRST in arm.data.bones:
    print("EARS already present")
else:
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    head_eb = eb["head"]
    names = {}
    for r in REG:
        sx = float(r.get("sx", 0.0))
        pts = [head_w + Vector((sx * abs(r["cx"]), r["cy"], r["z0"] + (r["z1"] - r["z0"]) * t)) for t in (0.0, 0.34, 0.67, 1.0)]
        prev = head_eb
        for i in range(3):
            n = r["name"] + ("" if i == 0 else str(i + 1))
            bone = eb.new(n)
            bone.head = inv @ pts[i]
            bone.tail = inv @ pts[i + 1]
            bone.align_roll(inv.to_3x3() @ Vector((0.0, -1.0, 0.0)))
            bone.parent = prev
            bone.use_connect = False
            prev = bone
            names[n] = i
    bpy.ops.object.mode_set(mode="OBJECT")
    me = mesh.data
    mw = mesh.matrix_world
    groups = {n: mesh.vertex_groups.new(name=n) for n in names}
    head_g = mesh.vertex_groups.get("head")
    neck_g = mesh.vertex_groups.get("neck")
    moved = {}
    for v in me.vertices:
        p = mw @ v.co - head_w
        for r in REG:
            sx = float(r.get("sx", 0.0))
            if sx == 0.0:
                inside_x = abs(p.x) <= r["hx"]
            else:
                px = p.x * sx
                inside_x = abs(r["cx"]) - r["hx"] <= px <= abs(r["cx"]) + r["hx"]
            if not (inside_x and abs(p.y - r["cy"]) <= r["hy"] and r["z0"] <= p.z <= r["z1"]):
                continue
            t = (p.z - r["z0"]) / max(r["z1"] - r["z0"], 1e-6)
            k = min(1.0, max(0.0, t / 0.35))
            k = k * k * (3 - 2 * k)
            if k <= 0.001:
                continue
            u = t * 3.0
            j = min(2, int(u))
            f = u - j
            nm = r["name"]
            w = {nm + ("" if j == 0 else str(j + 1)): 1.0 - f}
            if j < 2:
                w[nm + str(j + 2)] = f
            else:
                w[nm + "3"] = 1.0
            for g in (head_g, neck_g):
                if g is None:
                    continue
                try:
                    old = g.weight(v.index)
                except RuntimeError:
                    continue
                g.add([v.index], old * (1.0 - k), "REPLACE")
            for n, wt in w.items():
                groups[n].add([v.index], wt * k, "ADD")
            moved[nm] = moved.get(nm, 0) + 1
    print("EARS moved vertices", moved)

# preview: bend the ears and render a head close-up
os.makedirs("D:/Cache/ears_preview", exist_ok=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 480
scene.render.resolution_y = 480
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
cam_data = bpy.data.cameras.new("c")
cam = bpy.data.objects.new("c", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.lens = 60
if arm.animation_data is None:
    arm.animation_data_create()
arm.animation_data.action = None
from mathutils import Euler as _E
def _q(pb, e):   # keep the bones in QUATERNION mode: switching mode orphans every imported action's curves (the clips export flat)
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = _E(e, "XYZ").to_quaternion()
for pb in arm.pose.bones:
    _q(pb, (0, 0, 0))
tgt = head_w + Vector((0, 0, 0.25))
bent = {}
for r in REG:
    for i in range(3):
        n = r["name"] + ("" if i == 0 else str(i + 1))
        sx = float(r.get("sx", 0.0))
        bent[n] = (0.0, 0.0, (-0.6 if sx < 0 else 0.6)) if sx != 0.0 and r["name"].endswith("L") else (0.55, 0.0, 0.0)
for label, pose in (("rest", {}), ("bent", bent)):
    for pb in arm.pose.bones:
        _q(pb, (0, 0, 0))
    for n, e in pose.items():
        if n in arm.pose.bones:
            _q(arm.pose.bones[n], e)
    bpy.context.view_layer.update()
    cam.location = tgt + Vector((0.0, -1.7, 0.0))
    cam.rotation_euler = (tgt - cam.location).normalized().to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = "D:/Cache/ears_preview/%s_ears_%s.png" % (KEY, label)
    bpy.ops.render.render(write_still=True)
for pb in arm.pose.bones:
    _q(pb, (0, 0, 0))
# export keeps the actions (the clips): restore the idle as the active one
act = bpy.data.actions.get("fightIdle")
if act is not None:
    arm.animation_data.action = act
bpy.ops.export_scene.gltf(filepath=PATH, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS", export_yup=True)
print("WROTE", PATH)
