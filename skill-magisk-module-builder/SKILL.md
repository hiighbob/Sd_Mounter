---
name: magisk-module-builder
description: >
  Build Magisk/KernelSU/APatch modules with a WebUI X + MMRL graphical interface
  (SM-A530W / Android 9 / Magisk 30100 target, portable on explicit request).
  This is the primary, fastest way to ship an "app-like" config tool for root
  tweaks on this device — a webroot/ UI in MMRL beats writing and signing a
  native .apk for almost any settings/status/log screen. Use this skill whenever
  the user wants to create, extend or fix a Magisk module, a WebUI X interface,
  module shell scripts (post-fs-data.sh, service.sh, customize.sh), debug a
  WebUI via Eruda, work with config.json/WXU plugins, or build any Android root
  automation with a GUI. Triggers for: "make a module for X", "add a WebUI to
  my module", "magisk script that does Y", "I want a MMRL module", "debug my
  webroot", or any Magisk/KernelSU/APatch module creation with UI. Checking
  IzzySoft/MMAR for an existing module first is a helpful bonus, never a
  blocker — proceed straight to building if the user already knows what they want.
---

# Magisk Module Builder — WebUI X / MMRL Edition

> Target device locked: **SM-A530W · Android 9 · Magisk 30100 · WebUI X/433**
> For public/portable release: ask explicitly → read `references/portability.md`

## Core idea

For this user, **"build a Magisk module" almost always means "build a
`webroot/` WebUI X app that MMRL renders."** WebUI X gives you, for free:
native-feeling theming and window insets, a Compose-managed WebView with CSP
and process isolation, an on-device Eruda debug console, root shell access via
`ksu.exec()`, and (via the WXU plugin) deeper hooks (`global.require("wx:fs")`,
`wx:pm`, `wx:pty`, etc.). That's a faster, lighter loop than writing, signing,
and sideloading a native `.apk` — no Android Studio, no PC, no signing keys.

Reach for a native APK / separate Shizuku-bound app only when the request is
clearly *not* "a config/status screen for a root tweak" — see
`references/root-ecosystem-synergy.md` §6 for the decision tree.

---

## Quick-Start Checklist (read before generating ANYTHING)

Before writing one line of code, confirm:

- [ ] Module `id` chosen (lowercase, hyphens only, matches future dir name)
- [ ] Scope of `webroot/` tabs defined (max 5 tabs on 412px viewport)
- [ ] Shell scripts needed: which of `post-fs-data.sh`, `service.sh`, `customize.sh`
- [ ] Does it need persistent state? → `bind_mounts.conf` pattern or JSON in `webroot/`
- [ ] SELinux impact? (this device = permissive, but document enforcing path)
- [ ] Anything beyond `ksu.exec`/`ksu.readFile`/tabs? → skim
      `references/webuix-platform.md` for `config.json`, theming, WXU plugins,
      shortcuts, debugging
- [ ] Touches LSPosed/Zygisk/Shizuku/another root-layer component? → skim
      `references/root-ecosystem-synergy.md`
- [ ] *(optional bonus, see Phase 0 below)* Worth a quick IzzySoft/MMAR check?

---

## Device Context (auto-injected — never ask the user for this)

```
Device      : Samsung Galaxy A8 2018 (SM-A530W)
Android     : 9 (PPR1.180610.011.A530WVLUHCUH2)
Kernel      : 4.4.111-Quantum_pie-V4.0-A530W (aarch64)
Magisk      : 30100  (Magic Mount — no OverlayFS on this kernel)
WebUI X     : v433  →  User-Agent: WebUI X/433 (Linux; Android 9; SM-A530W; Magisk/30100)
SELinux     : Permissive
Viewport    : 412×846 px · pixel ratio 2.625 · viewport 411×845
WebView     : Android System WebView (Android 9 base = Chrome ~67-74)
mmcblk1p1   : exFAT · UUID 6603-7A19 · vol-id public:179,33
mmcblk1p2   : ext4  · UUID 6c65f787-ec30-7f4c-a2bd-f961b2b7e9e0 · ~20GB
Internal    : ~96% full (critical — always check space before writes)
Root shell  : ksu.exec() bridge via window.ksu (Magisk provider)
MODDIR      : /data/adb/modules/<id>  (get dynamically via ksu.moduleInfo())
```

For how this fits with LSPosed, Zygisk, KernelSU/APatch, and Shizuku on this
device, see `references/root-ecosystem-synergy.md` §5.

---

## Module Structure (canonical)

```
<module-id>/
├── module.prop          REQUIRED — see template below
├── META-INF/
│   └── com/google/android/
│       ├── update-binary    REQUIRED — Magisk installer script
│       └── updater-script   REQUIRED — one line: #MAGISK
├── post-fs-data.sh      optional — before Zygote (filesystem ops only)
├── service.sh           optional — after framework (am, pm, sm, getprop)
├── customize.sh         optional — runs during flash (UI_PRINT, set_perm, etc.)
├── webroot/
│   ├── index.html       presence = WebUI X enabled in MMRL
│   └── config.json      optional — see references/webuix-platform.md §2
├── scripts/             shell scripts called by WebUI or service.sh
├── logs/
│   └── .gitkeep
├── README.md            auto-included by this skill
└── CHANGELOG.md         auto-included by this skill
```

**ZIP PACKAGING RULE — CRITICAL:**
```bash
# ALWAYS package from INSIDE the module directory
cd /tmp/<module-id> && zip -r /tmp/<module-id>.zip . -x "*.DS_Store"
# NEVER: zip -r module.zip module-dir/  ← adds parent folder → "not a Magisk module"
```

---

## module.prop Template

```properties
id=<module-id>
name=<Human Name>
version=v1.0
versionCode=1
author=local
description=<one line description>
minMagisk=26000
```

---

## Shell Script Patterns

### post-fs-data.sh — before Zygote
```sh
#!/system/bin/sh
# PURPOSE: Filesystem operations ONLY. No am/pm/sm commands — framework not up.
# RUNS: After /data mounted, before Zygote starts.
MODDIR=${0%/*}
LOG="$MODDIR/logs/post-fs-data.log"
mkdir -p "$MODDIR/logs"
echo "[$(date '+%F %T')] START" >> "$LOG"
# ... filesystem ops ...
echo "[$(date '+%F %T')] END" >> "$LOG"
```

### service.sh — after framework
```sh
#!/system/bin/sh
# PURPOSE: Android framework commands (am, pm, sm, getprop).
# RUNS: After sys.boot_completed=1
MODDIR=${0%/*}
LOG="$MODDIR/logs/service.log"
mkdir -p "$MODDIR/logs"

# ALWAYS use boot_completed loop — never sleep N (fragile)
BOOT_WAIT=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3; BOOT_WAIT=$((BOOT_WAIT+3))
    [ $BOOT_WAIT -ge 90 ] && break
done
sleep 5  # vold/sm finish margin on this device
```

### customize.sh — during flash
```sh
#!/system/bin/sh
# Runs in Magisk installer environment (busybox available)
# UI_PRINT "message"  → shows in installer terminal
# set_perm <file> <owner> <group> <perm> [context]
# SKIPUNZIP=1  → don't auto-extract (handle manually)
ui_print "- Installing <module-name> v1.0"
ui_print "- Device: $(getprop ro.product.model)"
set_perm_recursive "$MODPATH/scripts" root root 0755 0644
```

---

## WebUI X — Essentials (the part every module needs)

For the full platform reference (config.json, theming, WXU plugins, debugging,
shortcuts, Application Info flags) read **`references/webuix-platform.md`**.
The two pieces below are needed in *every* module's `webroot/index.html`:

### exec bridge (mandatory wrapper)
```javascript
// ALWAYS use this wrapper — never call ksu.exec() directly in business logic
let _cbId = 0;
function exec(cmd) {
  return new Promise((resolve) => {
    const name = '_cb' + (_cbId++);
    window[name] = function(code, stdout, stderr) {
      delete window[name];
      resolve({ code: parseInt(code), stdout: stdout || '', stderr: stderr || '' });
    };
    try {
      if (typeof ksu !== 'undefined') ksu.exec(cmd, '', name);
      else resolve({ code: -1, stdout: '', stderr: 'No ksu bridge' });
    } catch(e) { resolve({ code: -99, stdout: '', stderr: String(e) }); }
  });
}
```

### MODDIR — always dynamic
```javascript
// NEVER hardcode MODDIR — use moduleInfo()
let MOD = '/data/adb/modules/<id>';  // fallback only
try {
  if (typeof ksu !== 'undefined') {
    const info = JSON.parse(ksu.moduleInfo());
    if (info && info.moduleDir) MOD = info.moduleDir;
  }
} catch(e) {}
```

**Debugging while building**: enable "Auto Open Eruda" in WebUI X settings —
this gives a real on-device console/inspector/REPL, no PC needed. See
`references/webuix-platform.md` §7 for the full debug workflow (Eruda, remote
URL debugging, Developer Mode).

---

## WebUI X — HTML Structure Template

```html
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title><MODULE NAME></title>
<style>
  /* === DESIGN TOKENS — change here only === */
  :root {
    --bg:      #0d0f14;  --surface: #151820;  --card:   #1c2030;
    --border:  #252a38;  --accent:  #00d4aa;  --accent2:#82aaff;
    --warn:    #ffb340;  --err:     #ff5370;
    --text:    #e2e8f0;  --muted:   #5a6380;
    --mono: 'JetBrains Mono', monospace;
    --sans: 'Syne', sans-serif;
  }
  * { box-sizing:border-box; margin:0; padding:0; -webkit-tap-highlight-color:transparent; }
  body { font-family:var(--sans); background:var(--bg); color:var(--text);
         min-height:100vh; padding:0 0 80px; }

  /* === HEADER (sticky) === */
  .header { background:linear-gradient(135deg,#0d1520,#0d0f14); border-bottom:1px solid var(--border);
            padding:20px 16px 16px; position:sticky; top:0; z-index:100; }
  .header-title { font-size:18px; font-weight:800;
    background:linear-gradient(90deg,var(--accent),var(--accent2));
    -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
  .header-sub { font-size:11px; color:var(--muted); font-family:var(--mono); margin-top:2px; }

  /* === TABS (sticky below header) === */
  .tabs { display:flex; gap:4px; padding:12px 16px 0; border-bottom:1px solid var(--border);
          background:var(--bg); position:sticky; top:65px; z-index:99; }
  .tab { flex:1; padding:8px 4px; font-size:11px; font-weight:600; text-align:center;
         border:none; background:transparent; color:var(--muted); cursor:pointer;
         border-bottom:2px solid transparent; transition:all .2s;
         text-transform:uppercase; letter-spacing:.5px; font-family:var(--sans); }
  .tab.active { color:var(--accent); border-bottom-color:var(--accent); }

  /* === PAGES === */
  .page { display:none; padding:16px; }
  .page.active { display:block; }

  /* === CARDS === */
  .card { background:var(--card); border:1px solid var(--border);
          border-radius:12px; padding:14px; margin-bottom:12px; }
  .card-title { font-size:10px; font-weight:600; text-transform:uppercase;
                letter-spacing:1px; color:var(--muted); margin-bottom:10px;
                font-family:var(--mono); }

  /* === BUTTONS === */
  .btn { width:100%; padding:12px; border:none; border-radius:10px; font-size:13px;
         font-weight:600; cursor:pointer; margin-bottom:8px; transition:all .2s;
         font-family:var(--sans); }
  .btn:active { transform:scale(0.97); }
  .btn-primary { background:var(--accent);    color:#000; }
  .btn-warn    { background:var(--warn);      color:#000; }
  .btn-danger  { background:var(--err);       color:#fff; }
  .btn-ghost   { background:var(--surface);   color:var(--text);
                 border:1px solid var(--border); }
  .btn-sm      { padding:8px 12px; font-size:11px; width:auto; margin-bottom:4px; }
  .btn:disabled { opacity:.4; cursor:not-allowed; }

  /* === TERMINAL OUTPUT === */
  .terminal { background:#0a0c10; border:1px solid var(--border); border-radius:8px;
              padding:10px; font-family:var(--mono); font-size:11px; line-height:1.7;
              max-height:220px; overflow-y:auto; white-space:pre-wrap; }
  .terminal .ok   { color:var(--accent); }
  .terminal .warn { color:var(--warn); }
  .terminal .err  { color:var(--err); }
  .terminal .dim  { color:var(--muted); }

  /* === BADGES === */
  .badge { display:inline-flex; align-items:center; gap:5px; padding:3px 8px;
           border-radius:20px; font-size:11px; font-family:var(--mono); font-weight:700; }
  .badge::before { content:'●'; font-size:8px; }
  .badge-ok   { background:#00d4aa33; color:var(--accent); }
  .badge-warn { background:#ffb34033; color:var(--warn); }
  .badge-err  { background:#ff537033; color:var(--err); }
  .badge-off  { background:#ffffff11; color:var(--muted); }

  /* === SPINNER === */
  .spinner { display:inline-block; width:12px; height:12px; border:2px solid currentColor;
             border-top-color:transparent; border-radius:50%;
             animation:spin .7s linear infinite; vertical-align:middle; margin-right:6px; }
  @keyframes spin { to { transform:rotate(360deg); } }

  /* === TOAST === */
  #toast { position:fixed; bottom:90px; left:50%; transform:translateX(-50%) translateY(20px);
           background:var(--card); border:1px solid var(--border); color:var(--text);
           padding:10px 16px; border-radius:20px; font-size:12px; opacity:0;
           transition:all .3s; pointer-events:none; z-index:999; white-space:nowrap; }
  #toast.show { opacity:1; transform:translateX(-50%) translateY(0); }
  #toast.ok   { border-color:var(--accent); color:var(--accent); }
  #toast.warn { border-color:var(--warn);   color:var(--warn); }
  #toast.err  { border-color:var(--err);    color:var(--err); }
</style>
</head>
<body>

<div class="header">
  <div class="header-title">⚡ <MODULE NAME></div>
  <div class="header-sub"><DEVICE INFO LINE></div>
</div>

<div class="tabs" id="tabs">
  <button class="tab active" data-tab="status">Statut</button>
  <button class="tab" data-tab="action">Action</button>
  <button class="tab" data-tab="logs">Logs</button>
</div>

<div id="toast"></div>

<!-- TAB: STATUT -->
<div id="tab-status" class="page active">
  <!-- status content -->
</div>

<!-- TAB: ACTION -->
<div id="tab-action" class="page">
  <!-- action content -->
</div>

<!-- TAB: LOGS -->
<div id="tab-logs" class="page">
  <div class="card">
    <div class="card-title">Logs</div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px" id="log-btns"></div>
    <div id="log-output" class="terminal">Sélectionne un log.</div>
  </div>
</div>

<script>
'use strict';

// ── ksu exec bridge ────────────────────────────────────────────────
let _cbId = 0;
function exec(cmd) {
  return new Promise((resolve) => {
    const name = '_cb' + (_cbId++);
    window[name] = function(code, stdout, stderr) {
      delete window[name];
      resolve({ code: parseInt(code), stdout: stdout||'', stderr: stderr||'' });
    };
    try {
      if (typeof ksu !== 'undefined') ksu.exec(cmd, '', name);
      else resolve({ code:-1, stdout:'', stderr:'No ksu' });
    } catch(e) { resolve({ code:-99, stdout:'', stderr:String(e) }); }
  });
}

// ── MODDIR ────────────────────────────────────────────────────────
let MOD = '/data/adb/modules/<module-id>';
try {
  if (typeof ksu !== 'undefined') {
    const info = JSON.parse(ksu.moduleInfo());
    if (info && info.moduleDir) MOD = info.moduleDir;
  }
} catch(e) {}

// ── Tab switching ─────────────────────────────────────────────────
document.querySelectorAll('.tab').forEach(btn => {
  btn.addEventListener('click', () => {
    const id = btn.dataset.tab;
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t===btn));
    document.querySelectorAll('.page').forEach(p => {
      p.classList.toggle('active', p.id === 'tab-' + id);
    });
    if (id === 'status') loadStatus();
    if (id === 'logs')   loadLog(currentLog || '<first-log-name>');
  });
});

// ── Toast ─────────────────────────────────────────────────────────
let _toastTimer;
function toast(msg, type='ok') {
  const el = document.getElementById('toast');
  el.textContent = msg; el.className = 'show ' + type;
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => el.className = '', 3000);
}

// ── Terminal colorizer ────────────────────────────────────────────
function colorize(lines) {
  return lines.map(l => {
    if (l.includes('SUCCES') || l.includes('OK') || l.includes('exit=0'))
      return '<span class="ok">' + l + '</span>';
    if (l.includes('ERREUR') || l.includes('ECHEC') || l.includes('ERROR'))
      return '<span class="err">' + l + '</span>';
    if (l.includes('WARN') || l.includes('exit=') && !l.includes('exit=0'))
      return '<span class="warn">' + l + '</span>';
    return '<span class="dim">' + l + '</span>';
  }).join('\n');
}

// ── Log viewer ────────────────────────────────────────────────────
let currentLog = null;
function buildLogButtons(names) {
  const wrap = document.getElementById('log-btns');
  wrap.innerHTML = names.map(n =>
    '<button class="btn btn-ghost btn-sm" onclick="loadLog(\'' + n + '\')">' + n + '</button>'
  ).join('');
}
async function loadLog(name) {
  currentLog = name;
  const el = document.getElementById('log-output');
  el.innerHTML = '<span class="dim">Chargement...</span>';
  const r = await exec('tail -150 ' + MOD + '/logs/' + name + '.log 2>/dev/null || echo "(vide)"');
  el.innerHTML = colorize(r.stdout.split('\n'));
  el.scrollTop = el.scrollHeight;
}

// ── Reboot ────────────────────────────────────────────────────────
async function rebootDevice() {
  if (!confirm('Redémarrer maintenant ?')) return;
  toast('Redémarrage...', 'warn');
  await exec('reboot');
}

// ── Init ──────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  buildLogButtons(['service', 'post-fs-data']);
  loadStatus();
});

// ── Module-specific functions below ──────────────────────────────
async function loadStatus() {
  // TODO: implement per module
}
</script>
</body>
</html>
```

> **Native-theme variant**: instead of (or in addition to) the dark design-token
> theme above, you can link `https://mui.kernelsu.org/internal/insets.css` and
> `colors.css` for a theme that matches the user's MMRL Material You theme. See
> `references/webuix-platform.md` §3 for when to pick which.

---

## Anti-Patterns — Known Failures (never repeat these)

| Anti-pattern | Symptom | Fix |
|---|---|---|
| `zip -r module.zip module-dir/` | "not a Magisk module" | `cd module-dir && zip -r ../module.zip .` |
| `sed` pour modifier JS avec `&&` ou chars spéciaux | Corruption silencieuse du JS | Toujours utiliser `python3 -c "content.replace(...)"` |
| `sleep 12` fixe dans service.sh | Boot lent → sm pas prêt | Boucle `getprop sys.boot_completed` |
| `const MOD = '/data/adb/modules/...'` hardcodé | Cassé si id change | `JSON.parse(ksu.moduleInfo()).moduleDir` |
| `onclick="switchTab()"` avant `<script>` | `ReferenceError` si script crashe | Un seul `<script>` block, tab switching via `addEventListener` |
| `chcon` manuel pour SELinux | MCS labels incorrects (mode enforcing) | `restorecon -RF` ou documenter comme TODO enforcing |
| `exec('cat file.json')` pour lire webroot | Shell inutile | `ksu.readFile(MOD + '/webroot/file.json')` |
| Template literals avec `SUCCÈS` (char é) dans sed | Corruption charset | Utiliser Python ou éviter les accents dans les patterns sed |
| Double `<script>` blocks | Scope JS isolé | Un seul bloc `<script>` par page |
| Widening `contentSecurityPolicy` to `*` "just in case" | Defeats CSP security benefit, may get module flagged | Only add the exact domain(s) actually used |
| Long-running `exec()` loop kicked off from WebUI | Killed when app backgrounds (`killShellWhenBackground`) | Move to `service.sh`; WebUI only triggers/reads status |
| Hand-rolling a debug console in the WebUI | Wasted effort | Use built-in Eruda (`references/webuix-platform.md` §7) |

---

## Génération d'un module — Workflow token-efficient

### Étape 1 : Clarification minimale (1 échange max)
Poser ces questions UNIQUEMENT si non déduisibles du contexte :
- Nom/id du module ?
- Fonctions principales (≤5 bullets) ?
- Scripts shell nécessaires ? (post-fs/service/customize)
- Tabs WebUI ? (défaut : Statut + Action + Logs)
- Besoin de `config.json` (permissions, CSP custom, dexFiles/WXU, shortcut) ?
  → si oui, lire `references/webuix-platform.md` avant de générer.

### Étape 2 : Générer dans cet ordre (une passe, pas d'itérations)
1. `module.prop`
2. `customize.sh` (si nécessaire)
3. Scripts shell (post-fs-data.sh, service.sh, scripts/)
4. `webroot/index.html` — utiliser le template ci-dessus, adapter les sections
5. `webroot/config.json` (si besoin identifié à l'étape 1)
6. `README.md` + `CHANGELOG.md`
7. Packager : `cd /tmp/<id> && zip -r /tmp/<id>.zip .`

### Étape 3 : Vérification avant livraison
```bash
# Vérifier structure zip (module.prop doit être à la racine)
unzip -l /tmp/<id>.zip | grep module.prop  # doit retourner "  module.prop"

# Vérifier JS (pas de corruption)
python3 -c "
import re; c=open('webroot/index.html').read()
js=c[c.index('<script>')+8:c.rindex('</script>')]
assert not re.search(r'(const|let)\s+\w+=.*;(const|let)', js), 'JS corruption'
print('JS OK — ' + str(len(js)) + ' chars')
"
```

---

## Phase 0 (OPTIONAL BONUS) — Existing-module check

This is a quick *value-add*, not a gate. If the user already knows what they
want, skip straight to Étape 1 above. Only run this when:
- the user explicitly asks "does something like this exist?", or
- the request is broad/generic enough ("a hosts blocker", "an app freezer")
  that a well-known existing module is likely a near-perfect fit.

If running it:
1. Check `references/izzy_cache_meta.json` freshness (>30 days → offer refresh).
2. Search `references/izzy_cache.json` per `references/izzy-discovery.md`.
3. Present matches **alongside** an offer to build custom — never block on this,
   and never make the user wait through a discovery report they didn't ask for.

Full protocol, scoring, and cache-management commands: `references/izzy-discovery.md`.

---

## REFERENCE FILES

| File | When to read |
|------|-------------|
| `references/webuix-platform.md` | Anything beyond basic tabs: `config.json`, theming, built-in interfaces, WXU plugins/`global.require`, Application Info flags, debugging (Eruda), patching, shortcuts |
| `references/root-ecosystem-synergy.md` | Module interacts with/needs to detect LSPosed, Zygisk, KernelSU/APatch, Shizuku, or device-specific kernel constraints |
| `references/mmrl-modules.md` | GUI patterns from popular MMRL modules (bindhosts, AppNuker, Zygisk-Assistant) |
| `references/portability.md` | User explicitly wants a public/portable release |
| `references/izzy-discovery.md` | Optional bonus existing-module search (Phase 0) — protocol + cache rules |

---

*Skill: magisk-module-builder · V4 · WebUI X / MMRL focus · G-FORCE integration*
