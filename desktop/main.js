// Fight Studio Desktop - main process.
// Opens the app window (HD, maximized), gives the page safe file access to the game's clip folders, lets panels pop out into
// their own windows, and serves the agent API on http://127.0.0.1:47651 (the same methods as the Godot Animator on :47650,
// so one MCP server, game/packs/city_breaker/animator/mcp/fight_studio_mcp.py, drives either app).
const { app, BrowserWindow, ipcMain, shell, screen, dialog } = require("electron");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { spawn } = require("child_process");
const { pathToFileURL } = require("url");

const ARGS = process.argv.slice(1);
const arg = (name, dflt) => {
  const a = ARGS.find((x) => x.startsWith(`--${name}=`));
  return a ? a.slice(name.length + 3) : dflt;
};
const flag = (name) => ARGS.includes(`--${name}`);

const PROJECT = process.env.FIGHT_STUDIO_PROJECT || arg("project", "D:/Games/BSP-Universe");
const PACK = path.join(PROJECT, "game/packs/city_breaker");
const DIRS = {
  clips: path.join(PACK, "data/clips"),
  poses: path.join(PACK, "data/poses"),
  chars: path.join(PACK, "assets/chars"),
  data: path.join(PACK, "data"),
  trash: "D:/Cache/fight_studio_trash",
  backups: "D:/Cache/fight_studio_backups",
  renders: "D:/Cache/fight_studio_renders",
};
const API_PORT = Number(arg("api-port", 47651));
const ANIMATO_PY = "D:/Projects/Animato/.venv/Scripts/python.exe";
const ANIMATO_BAKE = "D:/Projects/Animato/bake_studio_clips.py";

let win = null;
const LOG = path.join(__dirname, "out", "desktop.log");
fs.mkdirSync(path.dirname(LOG), { recursive: true });
fs.writeFileSync(LOG, "");
// Electron is a GUI app on Windows: its console often goes nowhere, so the log also goes to out/desktop.log
function log(...a) {
  const line = a.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(" ");
  try { fs.appendFileSync(LOG, line + "\n"); } catch {}
  console.log(line);
}
let apiServer = null;
const pending = new Map();
let rpcSeq = 1;

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
}

function safeName(n) {
  return typeof n === "string" && /^[A-Za-z0-9_\-]+$/.test(n);
}

function readJson(p) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
}

function writeJson(p, obj) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(obj, null, 2), "utf8");
}

// ------------------------------------------------------------------ file access for the page (only these folders)
const backedUp = new Set();
const handlers = {
  info: () => ({ project: PROJECT, dirs: DIRS, args: ARGS, apiPort: API_PORT, version: app.getVersion() }),
  listClips: () => (fs.existsSync(DIRS.clips) ? fs.readdirSync(DIRS.clips).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort() : []),
  loadClip: (name) => (safeName(name) ? readJson(path.join(DIRS.clips, name + ".json")) : null),
  clipExists: (name) => safeName(name) && fs.existsSync(path.join(DIRS.clips, name + ".json")),
  saveClip: (clip) => {
    if (!clip || !safeName(clip.name)) return { ok: false, error: "bad clip name" };
    const p = path.join(DIRS.clips, clip.name + ".json");
    if (fs.existsSync(p) && !backedUp.has(clip.name)) {
      fs.mkdirSync(DIRS.backups, { recursive: true });
      fs.copyFileSync(p, path.join(DIRS.backups, `${clip.name}_${stamp()}.json`));
      backedUp.add(clip.name);
    }
    writeJson(p, clip);
    return { ok: true, path: p };
  },
  trashClip: (name) => {
    if (!safeName(name)) return false;
    const p = path.join(DIRS.clips, name + ".json");
    if (!fs.existsSync(p)) return false;
    fs.mkdirSync(DIRS.trash, { recursive: true });
    fs.copyFileSync(p, path.join(DIRS.trash, `${name}_${stamp()}.json`));
    fs.unlinkSync(p);
    return true;
  },
  listPoses: () => (fs.existsSync(DIRS.poses) ? fs.readdirSync(DIRS.poses).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort() : []),
  loadPose: (name) => (safeName(name) ? readJson(path.join(DIRS.poses, name + ".json")) : null),
  savePose: (pose) => {
    if (!pose || !safeName(pose.name)) return false;
    writeJson(path.join(DIRS.poses, pose.name + ".json"), pose);
    return true;
  },
  loadData: (file) => (/^[a-z_]+\.json$/.test(file) ? readJson(path.join(DIRS.data, file)) : null),
  saveData: (file, obj) => {
    if (!/^(animator_rig|sockets)\.json$/.test(file)) return false;
    writeJson(path.join(DIRS.data, file), obj);
    return true;
  },
  fighters: () => (fs.existsSync(DIRS.chars) ? fs.readdirSync(DIRS.chars).filter((f) => f.endsWith("_fight.glb")).map((f) => f.slice(0, -10)).sort() : []),
  modelUrl: (key) => {
    if (!safeName(key)) return null;
    const p = path.join(DIRS.chars, key + "_fight.glb");
    return fs.existsSync(p) ? pathToFileURL(p).href : null;
  },
  writePng: (file, base64) => {
    const p = file && file.length ? file : path.join(DIRS.renders, `desktop_${stamp()}.png`);
    if (!/\.png$/i.test(p)) return null;
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, Buffer.from(base64, "base64"));
    return p;
  },
  openPath: (p) => shell.openPath(p),
  captureWindow: async (file) => {
    if (!win) return null;
    const img = await win.webContents.capturePage();
    const p = file && /\.png$/i.test(file) ? file : path.join(DIRS.renders, `desktop_window_${stamp()}.png`);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, img.toPNG());
    return p;
  },
  bakeAnimato: (fighter) => {
    if (!safeName(fighter) || !fs.existsSync(ANIMATO_PY) || !fs.existsSync(ANIMATO_BAKE)) return { ok: false, error: "Animato not found" };
    const child = spawn(ANIMATO_PY, [ANIMATO_BAKE, fighter], { cwd: path.dirname(ANIMATO_BAKE), detached: true, stdio: "ignore" });
    child.unref();
    return { ok: true, pid: child.pid };
  },
  openGodotAnimator: (fighter, clip) => {
    const exe = "D:/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe";
    if (!fs.existsSync(exe)) return false;
    const child = spawn(exe, ["--path", PROJECT, "res://game/packs/city_breaker/animator/animator.tscn", "--", `--fighter=${fighter}`, `--clip=${clip}`], { detached: true, stdio: "ignore" });
    child.unref();
    return true;
  },
  confirm: async (text) => {
    const r = await dialog.showMessageBox(win, { type: "question", buttons: ["Yes", "Cancel"], defaultId: 0, cancelId: 1, message: text, title: "Fight Studio" });
    return r.response === 0;
  },
  setTitle: (t) => win && win.setTitle(t),
  quit: (code) => {
    app.exit(code || 0);
  },
  log: (...a) => log(...a),
};

for (const [name, fn] of Object.entries(handlers)) {
  ipcMain.handle("fs:" + name, (_e, ...a) => fn(...a));
}

// ------------------------------------------------------------------ agent API
ipcMain.on("rpc:result", (_e, id, out) => {
  const p = pending.get(id);
  if (p) {
    pending.delete(id);
    p(out);
  }
});

function callPage(method, params) {
  return new Promise((resolve) => {
    if (!win) return resolve({ ok: false, error: "no window" });
    const id = rpcSeq++;
    pending.set(id, resolve);
    win.webContents.send("rpc:call", id, method, params || {});
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        resolve({ ok: false, error: "timed out" });
      }
    }, 180000);
  });
}

function startApi() {
  apiServer = http.createServer((req, res) => {
    const send = (obj) => {
      const body = Buffer.from(JSON.stringify(obj));
      res.writeHead(200, { "content-type": "application/json", "content-length": body.length });
      res.end(body);
    };
    const url = (req.url || "").split("?")[0];
    if (req.method === "GET" && url === "/health") {
      callPage("__health", {}).then((h) => send({ ok: true, app: "fight-studio-desktop", version: app.getVersion(), ...(h.result || {}) }));
      return;
    }
    if (req.method === "GET" && url === "/methods") {
      callPage("__methods", {}).then(send);
      return;
    }
    if (req.method === "POST" && url === "/rpc") {
      let body = "";
      req.on("data", (c) => (body += c));
      req.on("end", () => {
        let msg;
        try {
          msg = JSON.parse(body);
        } catch {
          return send({ ok: false, error: 'body must be JSON: {"method": ..., "params": {...}}' });
        }
        callPage(String(msg.method || ""), msg.params || {}).then(send);
      });
      return;
    }
    send({ ok: false, error: "use POST /rpc, GET /methods or GET /health" });
  });
  apiServer.on("error", (e) => log("agent API could not start:", e.message));
  apiServer.listen(API_PORT, "127.0.0.1");
}

// ------------------------------------------------------------------ windows
function createWindow() {
  const area = screen.getPrimaryDisplay().workAreaSize;
  const hidden = flag("hidden");
  win = new BrowserWindow({
    width: Math.min(1920, Math.round(area.width * 0.96)),
    height: Math.min(1080, Math.round(area.height * 0.94)),
    minWidth: 1100,
    minHeight: 680,
    show: false,
    backgroundColor: "#0d0b0f",
    title: "Fight Studio Desktop",
    autoHideMenuBar: true,
    focusable: !flag("unfocusable"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      backgroundThrottling: false,
    },
  });
  win.setMenuBarVisibility(false);
  // panels and canvases pop out into real windows (same page, so they stay live)
  win.webContents.setWindowOpenHandler(({ features }) => ({
    action: "allow",
    overrideBrowserWindowOptions: {
      backgroundColor: "#16131a",
      autoHideMenuBar: true,
      title: "Fight Studio",
      focusable: !flag("unfocusable"),
      webPreferences: { contextIsolation: true, nodeIntegration: false },
    },
  }));
  win.webContents.on("console-message", (_e, level, message, line, source) => {
    if (level >= 2 || flag("verbose")) log(`[page ${level >= 3 ? "error" : "warn"}] ${message} (${path.basename(String(source))}:${line})`);
  });
  win.webContents.on("render-process-gone", (_e, d) => log("renderer gone:", d.reason));
  win.loadFile(path.join(__dirname, "src/index.html"));
  win.once("ready-to-show", () => {
    if (hidden) return;
    if (area.width >= 1600 && !flag("windowed")) win.maximize();
    win.show();
  });
  win.on("close", async (e) => {
    if (win.__closing) return;
    e.preventDefault();
    const r = await callPage("__can_close", {});
    if (r && r.result === true) {
      win.__closing = true;
      win.close();
    }
  });
  win.on("closed", () => {
    win = null;
  });
}

app.whenReady().then(() => {
  createWindow();
  if (!flag("no-api")) startApi();
});

app.on("window-all-closed", () => app.quit());
