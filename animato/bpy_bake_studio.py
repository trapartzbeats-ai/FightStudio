"""bpy script: bake the Fight Studio clips (data/clips/*.json) into a baked City Breaker fighter GLB.

Injected by bake_studio_clips.py (__PATH__ / __CLIPS__ = a JSON list of clips). Keeps every existing action; a clip of the same name
is replaced. The Studio's per-bone Euler (radians, order XYZ = Rz*Ry*Rx) are exactly Blender's pose-bone euler on this rig, so they
are keyed as they are. hips_dy = hips height change (bone-local Y is up on this rig). Frames are scaled to the file's scene fps so the
clip lasts what it lasts in the Studio, and no other clip changes length.
"""
import json
from mathutils import Euler

import bpy

PATH = r"__PATH__"
CLIPS = json.loads(r'''__CLIPS__''')

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=PATH)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
if arm.animation_data is None:
    arm.animation_data_create()
fps_scene = float(bpy.context.scene.render.fps)
bones = [b.name for b in arm.pose.bones]
done = []
for clip in CLIPS:
    name = clip["name"]
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
    scale = fps_scene / float(clip.get("fps", 30))
    for k in sorted(clip["keys"], key=lambda k: k["f"]):
        frame = 1 + float(k["f"]) * scale
        for b in bones:
            pb = arm.pose.bones[b]
            pb.rotation_mode = "QUATERNION"   # never switch mode: it orphans the other actions' curves
            rot = k.get("rot", {}).get(b, [0.0, 0.0, 0.0])
            pb.rotation_quaternion = Euler((float(rot[0]), float(rot[1]), float(rot[2])), "XYZ").to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if b == "hips":
                pb.location = (0.0, float(k.get("hips_dy", 0.0)), 0.0)
                pb.keyframe_insert("location", frame=frame)
    done.append(name)
arm.animation_data.action = bpy.data.actions.get("fightIdle")
bpy.ops.export_scene.gltf(filepath=PATH, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS", export_yup=True)
print("BAKED", done)
