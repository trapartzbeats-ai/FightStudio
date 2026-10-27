"""Add ear bones to City Breaker fighters through Animato (headless Blender). The ear regions live in data/ears.json (per fighter).

  python add_ears.py vix              one fighter, result staged in D:/Cache/ears_baked (preview stills in D:/Cache/ears_preview)
  python add_ears.py vix --ship       copy the staged GLB over the pack (the original stays in D:/Cache/chars_before_ears)

Starts its own Animato server if needed (and stops only that one).
"""
import json
import os
import shutil
import subprocess
import sys
import time

import requests

BASE = "http://127.0.0.1:8123"
PACK = "D:/Games/bsp-universe/game/packs/city_breaker"
UPLOAD = "D:/Projects/Animato/public/upload"
STAGE = "D:/Cache/ears_baked"
BACKUP = "D:/Cache/chars_before_ears"

args = sys.argv[1:]
ship = "--ship" in args
keys = [a for a in args if not a.startswith("--")]
regions = json.load(open(PACK + "/data/ears.json", encoding="utf-8"))["fighters"]
os.makedirs(STAGE, exist_ok=True)
os.makedirs(BACKUP, exist_ok=True)

if ship:
    for k in keys:
        if not os.path.exists(f"{BACKUP}/{k}_fight.glb"):
            shutil.copyfile(f"{PACK}/assets/chars/{k}_fight.glb", f"{BACKUP}/{k}_fight.glb")
        shutil.copyfile(f"{STAGE}/{k}_fight.glb", f"{PACK}/assets/chars/{k}_fight.glb")
        print("shipped", k)
    raise SystemExit(0)


def up() -> bool:
    try:
        return requests.get(BASE + "/", timeout=2).status_code < 600
    except Exception:
        return False


server = None
if not up():
    server = subprocess.Popen([sys.executable, "-m", "uvicorn", "main:app", "--port", "8123", "--host", "127.0.0.1"], cwd="D:/Projects/Animato",
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(40):
        time.sleep(0.5)
        if up():
            break
try:
    tpl = open("bpy_add_ears.py", encoding="utf-8").read()
    for k in keys:
        if k not in regions or not regions[k]:
            print(k, "has no ear region in ears.json")
            continue
        with open(f"{PACK}/assets/chars/{k}_fight.glb", "rb") as f:
            name = requests.post(BASE + "/api/upload", files={"file": (f"{k}_fight.glb", f, "model/gltf-binary")}, timeout=300).json()["filename"]
        script = tpl.replace("__PATH__", f"{UPLOAD}/{name}").replace("__KEY__", k).replace("__REGIONS__", json.dumps(regions[k]))
        body = requests.post(BASE + "/api/run", data=script, headers={"content-type": "text/plain"}, timeout=1200).json()
        print(k, [ln for ln in body.get("stdout", "").splitlines() if ln.startswith(("EARS", "WROTE"))])
        if not body.get("ok"):
            print("STDERR:", body.get("stderr", "")[-1500:])
            raise SystemExit(1)
        shutil.copyfile(f"{UPLOAD}/{name}", f"{STAGE}/{k}_fight.glb")
finally:
    if server is not None:
        server.terminate()
