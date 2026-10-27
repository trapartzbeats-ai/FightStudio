"""Bake the Fight Studio clips (data/clips/*.json) into the fighter GLBs through Animato (headless Blender).

  python bake_studio_clips.py vix             one fighter
  python bake_studio_clips.py all             all eight
  python bake_studio_clips.py vix --stage-only    leave the result in D:/Cache/studio_baked instead of shipping it

Starts the Animato server itself if it is not running (and stops only that server). The original GLB is kept in
D:/Cache/chars_before_studio the first time. After shipping, Godot re-imports the GLB on its next start.
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

import requests

BASE = "http://127.0.0.1:8123"
PACK = "D:/Games/bsp-universe/game/packs/city_breaker/assets/chars"
CLIPS = "D:/Games/bsp-universe/game/packs/city_breaker/data/clips"
UPLOAD = "D:/Projects/Animato/public/upload"
STAGE = "D:/Cache/studio_baked"
BACKUP = "D:/Cache/chars_before_studio"
ALL = ["vix", "carter", "al", "slum", "guru", "bigbill", "rhino", "goat"]

args = sys.argv[1:]
stage_only = "--stage-only" in args
keys = [a for a in args if not a.startswith("--")] or ["vix"]
if keys == ["all"]:
    keys = ALL

clips = [json.load(open(p, encoding="utf-8")) for p in sorted(glob.glob(CLIPS + "/*.json"))]
if not clips:
    print("no studio clips in", CLIPS)
    raise SystemExit(0)
print("clips:", [c["name"] for c in clips])


def up() -> bool:
    try:
        requests.get(BASE + "/api/health", timeout=2)
        return True
    except Exception:
        try:
            return requests.get(BASE + "/", timeout=2).status_code < 600
        except Exception:
            return False


server = None
if not up():
    server = subprocess.Popen([sys.executable, "-m", "uvicorn", "main:app", "--port", "8123", "--host", "127.0.0.1"],
                              cwd="D:/Projects/Animato", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(40):
        time.sleep(0.5)
        if up():
            break
try:
    os.makedirs(STAGE, exist_ok=True)
    os.makedirs(BACKUP, exist_ok=True)
    template = open("bpy_bake_studio.py", encoding="utf-8").read()
    for key in keys:
        src = f"{PACK}/{key}_fight.glb"
        with open(src, "rb") as f:
            r = requests.post(BASE + "/api/upload", files={"file": (f"{key}_fight.glb", f, "model/gltf-binary")}, timeout=300)
        r.raise_for_status()
        name = r.json()["filename"]
        script = template.replace("__PATH__", f"{UPLOAD}/{name}").replace("__CLIPS__", json.dumps(clips))
        body = requests.post(BASE + "/api/run", data=script, headers={"content-type": "text/plain"}, timeout=1200).json()
        print(key, [ln for ln in body.get("stdout", "").splitlines() if ln.startswith("BAKED")])
        if not body.get("ok"):
            print("STDERR:", body.get("stderr", "")[-1500:])
            raise SystemExit(1)
        shutil.copyfile(f"{UPLOAD}/{name}", f"{STAGE}/{key}_fight.glb")
        if not stage_only:
            if not os.path.exists(f"{BACKUP}/{key}_fight.glb"):
                shutil.copyfile(src, f"{BACKUP}/{key}_fight.glb")
            shutil.copyfile(f"{STAGE}/{key}_fight.glb", src)
            print("shipped", key)
finally:
    if server is not None:
        server.terminate()
