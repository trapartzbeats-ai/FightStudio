"""Add the missing City Breaker fight clips to fighters through Animato (server on :8123), staging results in D:/Cache/authored2.

  python author_clips2.py vix            one fighter
  python author_clips2.py all            all eight
  python author_clips2.py --ship vix ... copy the staged GLB over the pack (the original is kept in D:/Cache/chars_before_clips2)
"""
import json, shutil, struct, sys
import requests

BASE = "http://127.0.0.1:8123"
PACK = "D:/Games/bsp-universe/game/packs/city_breaker/assets/chars"
UPLOAD = "D:/Projects/Animato/public/upload"
STAGE = "D:/Cache/authored2"
BACKUP = "D:/Cache/chars_before_clips2"
ALL = ["vix", "carter", "al", "slum", "guru", "bigbill", "rhino", "goat"]

args = sys.argv[1:]
ship = "--ship" in args
keys = [a for a in args if not a.startswith("--")]
if keys == ["all"]:
    keys = ALL
import os
os.makedirs(STAGE, exist_ok=True)
os.makedirs(BACKUP, exist_ok=True)
for key in keys:
    if ship:
        src = f"{STAGE}/{key}_fight.glb"
        if not os.path.exists(f"{BACKUP}/{key}_fight.glb"):
            shutil.copyfile(f"{PACK}/{key}_fight.glb", f"{BACKUP}/{key}_fight.glb")
        shutil.copyfile(src, f"{PACK}/{key}_fight.glb")
        print("shipped", key)
        continue
    with open(f"{PACK}/{key}_fight.glb", "rb") as f:
        r = requests.post(BASE + "/api/upload", files={"file": (f"{key}_fight.glb", f, "model/gltf-binary")}, timeout=300)
    r.raise_for_status()
    name = r.json()["filename"]
    script = open("bpy_add_clips2.py", encoding="utf-8").read().replace("__PATH__", f"{UPLOAD}/{name}").replace("__PREFIX__", key)
    r = requests.post(BASE + "/api/run", data=script, headers={"content-type": "text/plain"}, timeout=1200)
    body = r.json()
    out = body.get("stdout", "")
    print(key, "run", r.status_code, [l for l in out.splitlines() if l.startswith(("ADDED", "WROTE"))])
    if not body.get("ok"):
        print("STDERR:", body.get("stderr", "")[-2000:]); raise SystemExit(1)
    with open(f"{UPLOAD}/{name}", "rb") as f:
        data = f.read()
    ln = struct.unpack_from("<I", data, 12)[0]
    anims = [a.get("name") for a in json.loads(data[20:20 + ln].decode("utf-8")).get("animations", [])]
    print(key, "animations", len(anims), "originals intact:", all(a in anims for a in ("fightIdle", "jab", "slam", "victory")))
    shutil.copyfile(f"{UPLOAD}/{name}", f"{STAGE}/{key}_fight.glb")
