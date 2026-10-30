"""Fight Studio MCP server: lets agents animate in the Fight Studio Animator (Godot) or Fight Studio Desktop (Electron).

Both apps serve the same JSON API on 127.0.0.1 (Godot :47650, Electron :47651). This server finds whichever is running
(FIGHT_STUDIO_URL overrides), or starts one with studio_launch. Edits show live in the app, undo like the user's own, and
land in the clip files the game reads (game/packs/city_breaker/data/clips).

Units: bone rotations in DEGREES [x, y, z] on the bone's own axes; positions in METRES, the fighter at the origin facing +Z.
Start with studio_rig (what every axis does, the rules: a knee never bends forward), then pose / key / look / check / save.

Register (user scope):  claude mcp add -s user fight-studio -- python <this file>
"""
from __future__ import annotations

import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from typing import Any

from mcp.server.fastmcp import FastMCP, Image

GODOT_EXE = os.environ.get("FIGHT_STUDIO_GODOT", r"D:\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe")
PROJECT = os.environ.get("FIGHT_STUDIO_PROJECT", r"D:\Games\BSP-Universe")
SCENE = "res://game/packs/city_breaker/animator/animator.tscn"
ELECTRON_DIR = os.environ.get("FIGHT_STUDIO_ELECTRON", r"D:\Projects\FightStudioDesktop")
PORTS = {"godot": 47650, "electron": 47651}

mcp = FastMCP(
    "fight-studio",
    instructions=(
        "Animate City Breaker / BSP Universe characters in the Fight Studio app. Call studio_rig first to learn the bones and "
        "axis rules (degrees; a knee never bends forward; this rig's R bones sit on +X). Typical loop: studio_open_clip or "
        "studio_new_clip -> studio_set_pose / studio_ik_pose / studio_apply_pose / studio_set_control (each keys the frame) -> "
        "studio_screenshot (target='sheet' shows front, three-quarter, side and back across the clip) -> studio_checks -> "
        "studio_save. Use studio_say to tell the user what you did. Never discard the user's unsaved work."
    ),
)

_base: str | None = None


def _health(url: str) -> dict | None:
    try:
        with urllib.request.urlopen(url + "/health", timeout=1.5) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def _find() -> str:
    global _base
    env = os.environ.get("FIGHT_STUDIO_URL")
    if env:
        return env.rstrip("/")
    if _base and _health(_base):
        return _base
    for port in PORTS.values():
        url = f"http://127.0.0.1:{port}"
        if _health(url):
            _base = url
            return url
    raise RuntimeError("Fight Studio is not running. Call studio_launch (app='godot' or 'electron'), or open it yourself.")


def rpc(method: str, params: dict | None = None, timeout: float = 120.0) -> Any:
    body = json.dumps({"method": method, "params": params or {}}).encode("utf-8")
    req = urllib.request.Request(_find() + "/rpc", data=body, headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.loads(r.read().decode("utf-8"))
    if not out.get("ok"):
        raise RuntimeError(out.get("error", "failed"))
    return out.get("result")


def _clean(d: dict) -> dict:
    return {k: v for k, v in d.items() if v is not None}


# ------------------------------------------------------------------ app

@mcp.tool()
def studio_launch(app: str = "godot", fighter: str = "vix", clip: str = "w_walk") -> dict:
    """Start the Fight Studio if none is running. app: 'godot' (the in-game Animator) or 'electron' (Fight Studio Desktop)."""
    for name, port in PORTS.items():
        h = _health(f"http://127.0.0.1:{port}")
        if h:
            return {"already_running": name, **h}
    if app == "electron":
        exe = os.path.join(ELECTRON_DIR, "node_modules", "electron", "dist", "electron.exe")
        if not os.path.exists(exe):
            raise RuntimeError(f"Electron app not built at {ELECTRON_DIR} (npm install there first)")
        subprocess.Popen([exe, ELECTRON_DIR, f"--fighter={fighter}", f"--clip={clip}"], cwd=ELECTRON_DIR)
        port = PORTS["electron"]
    else:
        subprocess.Popen([GODOT_EXE, "--path", PROJECT, SCENE, "--", f"--fighter={fighter}", f"--clip={clip}"], cwd=PROJECT)
        port = PORTS["godot"]
    url = f"http://127.0.0.1:{port}"
    for _ in range(120):
        time.sleep(0.5)
        h = _health(url)
        if h:
            global _base
            _base = url
            return {"started": app, **h}
    raise RuntimeError("the app did not answer within 60 s")


@mcp.tool()
def studio_state() -> dict:
    """What is open: fighter, clip, current frame, length, fps, loop, key frames, layers, constraints, selection, unsaved flag."""
    return rpc("state")


@mcp.tool()
def studio_rig() -> dict:
    """The rig: every bone (parent, body group, side, mirror twin, what X/Y/Z do, limits in degrees), IK limbs, masks,
    controls, sockets, and the animation rules. Read this before posing."""
    return rpc("rig")


@mcp.tool()
def studio_call(method: str, params: dict | None = None) -> Any:
    """Call any API method directly (GET /methods on the app lists them all, e.g. 'list_keys', 'set_keys', 'scale_time')."""
    return rpc(method, params or {})


@mcp.tool()
def studio_say(message: str) -> dict:
    """Show a message to the user in the app's status bar (say what you changed, or ask them to look)."""
    return rpc("say", {"message": message})


# ------------------------------------------------------------------ clips

@mcp.tool()
def studio_list_clips(filter: str = "") -> list:
    """Clip names the game reads. Prefixes: a_ = fighter moves (a_<fighter>_<move> = one fighter's own), w_ = open world."""
    return rpc("list_clips", {"filter": filter})


@mcp.tool()
def studio_open_clip(name: str, discard: bool = False) -> dict:
    """Open a clip. Refuses if the open clip has unsaved changes, unless discard=True (only when the user said so)."""
    return rpc("open_clip", {"name": name, "discard": discard})


@mcp.tool()
def studio_adjust(bone: str, x: float = 0.0, y: float = 0.0, z: float = 0.0, scope: str = "all", frame: int | None = None,
                  start: int = 0, end: int = -1, ease: int = 6, mirror: bool = False) -> dict:
    """Tilt a body part on top of its keys (the Adjust panel; the keys never change, studio_adjust_restore takes it off).
    x / y / z = the TOTAL turn in degrees for this part + scope (calling again replaces it; all zero removes it). scope:
    "all" frames, "frame" = around `frame` (default: the current one) easing over `ease` frames each side (0 = that frame only),
    "range" = start..end (end -1 = the clip's end) easing over `ease` frames inside each end. mirror = the other side gets the
    mirrored turn (both shoulders up). Never turns a joint past its rig limits. studio_rig() says what each axis does."""
    p = {"bone": bone, "x": x, "y": y, "z": z, "scope": scope, "from": start, "to": end, "ease": ease, "mirror": mirror}
    if frame is not None:
        p["frame"] = frame
    return rpc("adjust", p)


@mcp.tool()
def studio_feet(planted: bool | None = None, step: int = 1, frames: bool = False) -> dict:
    """How the open clip's feet stand in the match (the Feet panel). A planted clip stands each foot on its real sole (read
    from the model's mesh: some models are not level at rest), levels the standing feet, reaches the legs down with the
    knee's own bend and lets a foot keyed onto its toes / heel pivot. Per foot-frame state: flat | pivot | limit (heel up,
    ankle at its natural bend) | sink (into the floor: only a clip that is not planted) | air. planted = set the clip's plant
    flag first (ground clips on, air clips off). frames = include every frame; without it, counts + the frames a foot sinks."""
    p = {"step": step}
    if planted is not None:
        p["planted"] = planted
    r = rpc("feet", p)
    if isinstance(r, dict) and not frames and "frames" in r:
        r["sinking"] = [fr for fr in r["frames"] if any(isinstance(v, dict) and v.get("state") == "sink" for v in fr.values())]
        r["frame_count"] = len(r.pop("frames"))
    return r


@mcp.tool()
def studio_adjust_restore(bone: str = "", id: str = "") -> dict:
    """Take adjustments off (the keys are as they were): one by id, every one on a bone, or all of them (no arguments).
    studio_call("adjustments") lists them."""
    return rpc("adjust_restore", {"bone": bone, "id": id})


@mcp.tool()
def studio_merge(clips: list[dict], base: str = "", name: str = "", bake: bool = True, discard: bool = False) -> dict:
    """One animation from several (the Merge panel). The base clip (base, or the open clip) gives the body; each entry of clips
    goes on top and gives only its parts: {"clip": name, "parts": ["Arm L", "Arm R", "Hands"] (any of Head, Spine, Arm L, Arm R,
    Hands, Hips, Legs, Tail; default arms + hands), "start": frame its frame 0 lands on, "blend_in": 10, "blend_out": 10,
    "weight": 1.0, "cycle": false}. A looping base repeats under longer clips. bake=True makes ONE new clip (name, default
    <base>_merged) that opens unsaved; the base clip is not touched. bake=False leaves the setup live to look at and tweak
    (studio_layers / studio_call("merge_set", {...})). Look with studio_screenshot, then studio_save."""
    p = {"clips": clips, "bake": bake, "discard": discard}
    if base:
        p["base"] = base
    if name:
        p["name"] = name
    return rpc("merge", p)


@mcp.tool()
def studio_import_motion(path: str, name: str = "", anim: str = "", in_place: bool = True, limits: bool = True,
                         fingers: bool = True, discard: bool = False) -> dict:
    """Import outside motion onto our rig as a new clip: a Mixamo animation FBX (with or without skin) or a GLB / glTF with a
    Mixamo-style skeleton. The clip opens unsaved (look at it with studio_screenshot, then studio_save). in_place takes the
    travel out (the game moves the fighter; the speed is kept in the clip's "import" block), limits keeps every joint inside the
    rig limits, fingers brings the finger motion. Returns the report (bones matched, frames, keys, loop, planted, clamped)."""
    p = {"path": path, "in_place": in_place, "limits": limits, "fingers": fingers, "discard": discard}
    if name:
        p["name"] = name
    if anim:
        p["anim"] = anim
    return rpc("import_motion", p)


@mcp.tool()
def studio_new_clip(name: str, frames: int = 30, fps: int = 30, loop: bool = False, from_pose: bool = True,
                    overwrite: bool = False) -> dict:
    """Make a new clip (letters, digits, _ and -). It starts from the pose on screen when from_pose. Loops get first = last key, linked."""
    return rpc("new_clip", {"name": name, "frames": frames, "fps": fps, "loop": loop, "from_pose": from_pose, "overwrite": overwrite})


@mcp.tool()
def studio_get_clip() -> dict:
    """The open clip: settings, keys (rotations in degrees), layers, constraints, locks, markers."""
    return rpc("get_clip")


@mcp.tool()
def studio_set_clip(frames: int | None = None, fps: int | None = None, loop: bool | None = None, plant: bool | None = None,
                    ease: str | None = None, note: str | None = None) -> dict:
    """Clip settings. plant = the game stands the lower foot on the floor. ease = default ease (linear, in, out, inout, hold, spline)."""
    return rpc("set_clip", _clean({"frames": frames, "fps": fps, "loop": loop, "plant": plant, "ease": ease, "note": note}))


@mcp.tool()
def studio_save(name: str | None = None) -> dict:
    """Save to data/clips/<name>.json (where the game reads it). With name: save as a new clip. Layers / constraints are baked for the game."""
    return rpc("save_as", {"name": name}) if name else rpc("save")


# ------------------------------------------------------------------ posing and keys

@mcp.tool()
def studio_get_pose(frame: float | list | None = None, bones: list[str] | None = None, final: bool = True, world: bool = False) -> dict:
    """The pose at a frame (or a list of frames): bone rotations in degrees, the hips shift in metres; world=True adds joint positions."""
    return rpc("get_pose", _clean({"frame": frame, "bones": bones, "final": final, "world": world}))


@mcp.tool()
def studio_set_pose(bones: dict, frame: float | None = None, hips: dict | None = None, mode: str = "set", key: bool = True,
                    mirror: bool = False) -> dict:
    """Pose bones at a frame and key it. bones = {"armR": [x, y, z] degrees, ...}; hips = {"dx", "dy", "dz"} metres (body shift).
    mode 'add' adds to the current values. mirror=True also sets each bone's twin, mirrored. Limits and locks are respected and reported."""
    return rpc("set_pose", _clean({"bones": bones, "frame": frame, "hips": hips, "mode": mode, "key": key, "mirror": mirror}))


@mcp.tool()
def studio_ik_pose(bone: str, target: list[float], frame: float | None = None, key: bool = True, keep_end: bool = True) -> dict:
    """Pull a joint to a world point [x, y, z] m: a hand / foot bends its limb (two-bone IK, keep_end keeps its angle), any other
    joint bends up to three parents. Returns how close it got."""
    return rpc("ik_pose", _clean({"bone": bone, "target": target, "frame": frame, "key": key, "keep_end": keep_end}))


@mcp.tool()
def studio_key(frame: float | None = None, ease: str | None = None, tag: str | None = None) -> dict:
    """Key the pose at the frame. ease: linear | in (whips into the next key: strikes) | out (settles) | inout | hold | spline (cycles).
    tag: '' | breakdown | extreme. Keys that are 'the same key' elsewhere follow the change (see studio_set_propagate)."""
    return rpc("key", _clean({"frame": frame, "ease": ease, "tag": tag}))


@mcp.tool()
def studio_keys(action: str = "list", frames: list[int] | None = None, delta: int | None = None, ease: str | None = None,
                tag: str | None = None, lock: bool | None = None) -> Any:
    """Key operations. action: list | delete | move (delta frames) | set (ease / tag / lock) | link (one shared pose) | unlink."""
    f = frames or []
    if action == "list":
        return rpc("list_keys")
    if action == "delete":
        return rpc("delete_keys", {"frames": f})
    if action == "move":
        return rpc("move_keys", {"frames": f, "delta": delta or 0})
    if action == "set":
        return rpc("set_keys", _clean({"frames": f, "ease": ease, "tag": tag, "lock": lock}))
    if action == "link":
        return rpc("link_keys", {"frames": f})
    if action == "unlink":
        return rpc("unlink_keys", {"frames": f})
    raise ValueError("action: list | delete | move | set | link | unlink")


@mcp.tool()
def studio_set_key_values(frame: int, bones: dict, hips: dict | None = None) -> dict:
    """Edit one existing key in place (degrees). Linked / same-pose keys follow per the propagate mode."""
    return rpc("set_key_values", _clean({"frame": frame, "bones": bones, "hips": hips}))


@mcp.tool()
def studio_set_propagate(mode: str) -> dict:
    """How an edited key updates 'the same key' elsewhere: off | linked | pose (keys holding the same pose, default) | bone (per bone value)."""
    return rpc("set_propagate", {"mode": mode})


@mcp.tool()
def studio_frames(action: str, at: int = 0, count: int = 1, factor: float = 1.0, to: int | None = None) -> dict:
    """Time edits. action: insert (count frames at 'at') | delete | scale (factor: 0.5 = twice as fast) | reverse (at..to) | close_loop."""
    if action == "insert":
        return rpc("insert_frames", {"at": at, "count": count})
    if action == "delete":
        return rpc("delete_frames", {"at": at, "count": count})
    if action == "scale":
        return rpc("scale_time", {"factor": factor})
    if action == "reverse":
        return rpc("reverse", {"from": at, "to": to if to is not None else 9999})
    if action == "close_loop":
        return rpc("close_loop")
    raise ValueError("action: insert | delete | scale | reverse | close_loop")


@mcp.tool()
def studio_pose_tool(action: str, frame: float | None = None, mode: str = "l2r", bones: list[str] | None = None, t: float = 0.5,
                     key: bool = True) -> dict:
    """Pose tools at a frame. action: mirror (mode l2r | r2l | flip) | reset (bones; 'hips_move' = the body shift) | breakdown (t 0..1)."""
    if action == "mirror":
        return rpc("mirror_pose", _clean({"mode": mode, "frame": frame, "key": key}))
    if action == "reset":
        return rpc("reset_bones", _clean({"bones": bones or [], "frame": frame, "key": key}))
    if action == "breakdown":
        return rpc("breakdown", _clean({"t": t, "frame": frame, "key": key}))
    raise ValueError("action: mirror | reset | breakdown")


@mcp.tool()
def studio_poses(action: str = "list", name: str = "", frame: float | None = None, bones: list[str] | None = None,
                 weight: float = 1.0, mirror: bool = False, key: bool = True) -> Any:
    """The pose library (data/poses). action: list | save (name, bones = only those) | apply (name, weight, mirror, bones)."""
    if action == "list":
        return rpc("list_poses")
    if action == "save":
        return rpc("save_pose", _clean({"name": name, "bones": bones}))
    if action == "apply":
        return rpc("apply_pose", _clean({"name": name, "frame": frame, "bones": bones, "weight": weight, "mirror": mirror, "key": key}))
    raise ValueError("action: list | save | apply")


@mcp.tool()
def studio_controls(action: str = "list", name: str = "", value: float = 0.0, frame: float | None = None, key: bool = True,
                    drives: list | None = None, min: float = -1.0, max: float = 1.0) -> Any:
    """Rig controls (one slider drives many bones: Fist L/R, Spine bend, Crouch, Guard up, Tail curl...). action: list | set
    (name, value) | add (name, drives = [[bone, 'x'|'y'|'z'|'dx'|'dy'|'dz', amount deg or m]], min, max)."""
    if action == "list":
        return rpc("list_controls", _clean({"frame": frame}))
    if action == "set":
        return rpc("set_control", _clean({"name": name, "value": value, "frame": frame, "key": key}))
    if action == "add":
        return rpc("add_control", {"name": name, "drives": drives or [], "min": min, "max": max})
    raise ValueError("action: list | set | add")


# ------------------------------------------------------------------ layers, constraints, locks

@mcp.tool()
def studio_layers(action: str = "list", id: str = "", fields: dict | None = None) -> Any:
    """Animation layers (blend clips / tweaks on top). action: list | add | set | remove | activate (keys go into it; id '' = base).
    fields for add / set: name, source (keys | clip), clip, mode (add | add_delta | override), weight, mask (bones, '@Group' or a
    preset: 'Upper body', 'Lower body', 'Arms', 'Arm L', 'Arm R', 'Legs', 'Head', 'Spine', 'Hands', 'Tail'), start, end,
    fade_in, fade_out, offset, speed, cycle."""
    f = fields or {}
    if action == "list":
        return rpc("list_layers")
    if action == "add":
        return rpc("add_layer", f)
    if action == "set":
        return rpc("set_layer", {"id": id, **f})
    if action == "remove":
        return rpc("remove_layer", {"id": id})
    if action == "activate":
        return rpc("set_active_layer", {"id": id})
    raise ValueError("action: list | add | set | remove | activate")


@mcp.tool()
def studio_constraints(action: str = "list", id: str = "", fields: dict | None = None) -> Any:
    """Constraints solved every frame. action: list | add | set | remove | bake (layers + constraints become keys).
    fields: type ik {limb: armL|armR|legL|legR, target: [x,y,z] or {keys: [{f, pos}]} or {bone, offset}, keep_end};
    pin {bone, what: both|position|rotation, pin_frame}; aim {bone, axis '+z', target}; limit {bone, min_deg, max_deg};
    copy_rot {bone, source, mix, mirror}; floor {bones, mode: floor|plant, height}. All: start, end (-1 = to the end),
    influence 0..1, blend (frames to fade at the range edges)."""
    f = fields or {}
    if action == "list":
        return rpc("list_constraints")
    if action == "add":
        return rpc("add_constraint", f)
    if action == "set":
        return rpc("set_constraint", {"id": id, **f})
    if action == "remove":
        return rpc("remove_constraint", {"id": id})
    if action == "bake":
        return rpc("bake_to_keys")
    raise ValueError("action: list | add | set | remove | bake")


@mcp.tool()
def studio_freeze(bone: str, start: int | None = None, end: int = -1, what: str = "both") -> dict:
    """Freeze a bone in the world (a planted foot, a hand on a wall) from 'start' (default: the current frame) to 'end'."""
    return rpc("freeze", _clean({"bone": bone, "from": start, "to": end, "what": what}))


@mcp.tool()
def studio_lock(bones: list[str], channels: str = "xyz", unlock: bool = False) -> dict:
    """Lock bone channels ('x', 'yz', 'xyz') so no tool (yours or the user's) changes them; unlock=True frees them."""
    return rpc("unlock", {"bones": bones}) if unlock else rpc("lock", {"bones": bones, "channels": channels})


@mcp.tool()
def studio_sockets() -> dict:
    """Sockets (named points on bones: fists, feet, ground) with their bone and world position now."""
    return rpc("list_sockets")


# ------------------------------------------------------------------ look, check, finish

@mcp.tool()
def studio_screenshot(target: str = "sheet", width: int = 1280, height: int = 720, cols: int = 8, index: int | None = None) -> Image:
    """A picture to check your work. target: sheet (front / three-quarter / side / back x 'cols' moments of the clip),
    view (a canvas view, index = which), window (the whole app)."""
    r = rpc("screenshot", _clean({"target": target, "width": width, "height": height, "cols": cols, "index": index}), timeout=180)
    return Image(path=r["path"])


@mcp.tool()
def studio_view(layout: str | None = None, index: int | None = None, preset: str | None = None, ortho: bool | None = None,
                onion: bool | None = None, frame: float | None = None, bone: str | None = None) -> dict:
    """Change what the user sees: layout 1|2|3|4|strip|4+strip, a view's camera preset (Persp, Front, Three-Q, Side L, Side R,
    Back, Top, Follow), onion skin, the current frame, the selected bone."""
    out = rpc("set_view", _clean({"layout": layout, "index": index, "preset": preset, "ortho": ortho, "onion": onion, "bone": bone}))
    if frame is not None:
        out["frame"] = rpc("set_frame", {"frame": frame})
    return out


@mcp.tool()
def studio_checks() -> list:
    """Problems in the clip: knees bending forward, joints past their limits, a loop seam that jumps, planted feet sliding, unkeyed edits."""
    return rpc("checks")


@mcp.tool()
def studio_transition(clip_b: str, at: int, blend: int, name: str, discard: bool = False) -> dict:
    """A new clip: the open clip, then clip_b taking over at frame 'at', crossfading over 'blend' frames (save it to keep it)."""
    return rpc("transition_clip", {"clip_b": clip_b, "at": at, "blend": blend, "name": name, "discard": discard})


@mcp.tool()
def studio_undo(redo: bool = False) -> dict:
    """Undo (or redo) the last change, yours or the user's."""
    return rpc("redo" if redo else "undo")


@mcp.tool()
def studio_history() -> list:
    """Recent changes, newest first ([agent] = made through this API)."""
    return rpc("history")


@mcp.tool()
def studio_bake_glb() -> dict:
    """After saving: Animato (headless Blender) bakes every studio clip into this fighter's GLB; the original is kept in
    D:/Cache/chars_before_studio. Ask the user before doing this."""
    return rpc("bake_glb")


if __name__ == "__main__":
    mcp.run()
