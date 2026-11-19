# WebUI X / MMRL Platform Reference

> Read this file whenever a module needs anything beyond the basic tab template:
> custom permissions, dynamic theming, debugging, plugin/dex loading, shortcuts,
> Application Info flags, or anything touching `config.json`.
>
> Sources: mmrl.dev/guide/webuix/* · docs.mmrl.dev · github.com/MMRLApp/WXU ·
> github.com/MMRLApp/WebUI-X-Portable · github.com/MMRLApp/WebUI-API

---

## 1. What WebUI X actually is (NOT a plain WebView)

WebUI X is the engine MMRL (and WebUI X Portable, the standalone APK) use to render
`webroot/index.html`. It originated from KernelSU's WebUI (KSU v0.8.1+) but has been
heavily extended. The important point for module authors:

- **It is a managed Compose host around a WebView**, not a bare `WebView` Activity.
  MMRL injects CSS variables (theme, insets), JS interfaces (`window.$<id>`, `ksu`,
  `global`), and lifecycle hooks (`wx` events) before/while your page loads.
- **Content Security Policy (CSP)** is enforced by default
  (`default-src 'self' data: blob: {domain}; script-src 'self' 'unsafe-inline'
  'unsafe-eval' {domain}; ...`). Inline scripts/styles work, but loading remote
  scripts from a domain not in `{domain}`/`connect-src` will be blocked unless you
  widen `contentSecurityPolicy` in `config.json`.
- **Kill Shell**: by default (`killShellWhenBackground: true`) any `exec()`/shell
  processes your WebUI started are killed when the app goes to background. Long-running
  background work belongs in `service.sh`, not in JS `exec()` loops.
- **Strict isolation**: each module's WebUI runs in its own instance; you cannot
  reach into another module's `window.$<id>` interface.
- **Native-feeling chrome**: status bar styling, window insets, pull-to-refresh,
  back-button handling, and history-fallback (SPA routing) are all handled by the
  host — not by you reimplementing them in HTML/CSS.

This is why a WebUI X module can feel and behave like a real native settings screen
while remaining "just" `webroot/index.html` + JS — and why it's almost always faster
to build than a standalone `.apk` for the same config UI.

---

## 2. `config.json` / `config.mmrl.json`

Place at:
```
webroot/config.json
webroot/config.mmrl.json   ← MMRL-specific overrides, same schema, takes priority in MMRL
```

Full schema (Moshi-parsed, all fields optional unless noted):

```jsonc
{
  "modId": "your-module-id",
  "require": {
    "packages": [
      {
        "code": -1,
        "packageName": "com.topjohnwu.magisk",      // string OR array of strings
        "supportText": "Requires Magisk",
        "supportLink": "https://github.com/topjohnwu/Magisk"
      }
    ]
  },
  "permissions": ["wx.permission.ROOT_PATH"],
  "title": "Human Title",          // shown in WebUI X header / shortcut
  "icon": "icon.webp",             // path relative to webroot, used for shortcut
  "windowResize": true,            // adapt to keyboard/resize (default true)
  "backHandler": true,             // default back button handling (default true)
  "backInterceptor": null,         // "javascript" -> handle back in JS via wx events
  "refreshInterceptor": null,      // "javascript" | "native"
  "exitConfirm": true,             // confirm dialog before closing WebUI
  "pullToRefresh": false,          // beta gesture
  "historyFallback": false,        // SPA routing fallback
  "historyFallbackFile": "index.html",
  "autoStatusBarsStyle": true,     // auto-match status bar to your theme
  "killShellWhenBackground": true, // since v96 — kill exec() procs on background
  "contentSecurityPolicy": "default-src 'self' data: blob: {domain}; script-src 'self' 'unsafe-inline' 'unsafe-eval' {domain}; style-src 'self' 'unsafe-inline' {domain}; connect-src *",
  "caching": true,                 // since v181
  "cachingMaxAge": 86400,          // since v181, seconds
  "dexFiles": [                    // since v215 (WXU plugins)
    { "type": "dex", "path": "plugins/webui.dex", "className": "dev.mmrl.Global", "cache": true }
  ],
  "extra": {
    "pm": { "allowUrlPackageFetch": true }
  }
}
```

### Practical notes
- **Don't widen CSP "just in case"** — only add the exact domains you actually
  `fetch()`/load scripts from. A wide-open CSP defeats the security benefit over
  legacy WebView WebUI.
- `killShellWhenBackground: true` (default) means: if the module relies on a
  long shell loop kicked off from the WebUI, set this to `false` **and** document
  why — or better, move the loop to `service.sh`.
- `dexFiles` is how the WXU plugin ecosystem loads — see §4.
- `historyFallback` matters only if you build a JS-router SPA (rare for these
  module UIs; the tab-based single-page template in this skill doesn't need it).

---

## 3. Native theming — insets & colors (the "native feel" trick)

In `<head>`, link MMRL's internal stylesheets **before** your own CSS:

```html
<link rel="stylesheet" type="text/css" href="https://mui.kernelsu.org/internal/insets.css">
<link rel="stylesheet" type="text/css" href="https://mui.kernelsu.org/internal/colors.css">
```

> ⚠️ `https://mui.kernelsu.org/mmrl/` is **deprecated** — always use `/internal/`.

These provide CSS custom properties that mirror the **user's current MMRL/WebUI X
theme** (Material You dynamic colors) and the device's window insets:

```css
body {
  padding-top: var(--window-inset-top);
  padding-bottom: var(--window-inset-bottom);
  background-color: var(--background);
}
.card {
  background-color: var(--surfaceContainer);
  border-radius: 20px;
}
.card span { color: var(--inverseSurface); }
```

This is an **alternative** to this skill's hand-rolled dark "JetBrains Mono / Syne"
design-token theme (still valid, especially for portable/standalone WebUI X usage
or when you want a fixed brand look). Pick one:
- **Hand-rolled dark theme** (this skill's default template) → consistent look
  regardless of host app theme, good for "hacker tool" aesthetic.
- **`/internal/insets.css` + `colors.css`** → looks like a native MMRL settings
  page, adapts to the user's Material You theme/dark-light mode automatically.

Both can be combined: load `insets.css` always (for safe-area padding), and
either load `colors.css` or your own `:root` palette for colors.

---

## 4. Built-in JS interfaces

### 4.1 `window.$<sanitizedModId>` — the modern interface

`sanitizedModId` = your `modId` with every char that isn't `[A-Za-z0-9_.]`
replaced by `_`. WebUI X exposes a `ModuleInterface` (and related `FileInterface`,
`FileInputInterface`, `FileOutputInterface`) under `window.$<sanitizedModId>`.

```javascript
// e.g. modId "sd-mounter" -> sanitizedModId "sd_mounter"
const mod = window.$sd_mounter;

mod.hasAccessToFileSystem;   // boolean
mod.windowTopInset;          // px, status bar height
mod.isDarkMode;              // boolean — current host theme
mod.recompose();             // ask host to re-layout/re-theme
mod.createShortcut();        // pin home-screen shortcut using config.json title/icon
mod.createShortcut("Custom Title", "icon.webp"); // override title/icon
```

Always guard usage:
```javascript
if (typeof window.$sd_mounter !== 'undefined' && Object.keys(window.$sd_mounter).length) {
  // running inside WebUI X
}
```

### 4.2 `ksu.*` — legacy / cross-compatible bridge

Still the most portable surface (works across MMRL, WebUI X Portable, and legacy
KernelSU WebUI). This is the bridge documented in the main SKILL.md template:

```javascript
ksu.exec(cmd, options_json, callback_name)
ksu.moduleInfo()              // -> JSON {moduleDir, id, name, ...}
ksu.readFile(path)
ksu.writeFile(path, content)
ksu.listFile(path)
ksu.toast(message)
ksu.listAllPackages()
ksu.getPackagesInfo(json_pkg_names_array)
```

**Recommendation**: use `ksu.*` for shell/file basics (max portability across
root managers), and `window.$<id>` only for WebUI-X-specific niceties (theme
detection, insets, shortcuts, recompose).

---

## 5. WXU plugin & `global.require()` — extending the JS environment

Since WebUI X v213/v215, modules can ship **`.dex`/`.apk` plugins** (built with the
[WXU](https://github.com/MMRLApp/WXU) Gradle template) that register extra JS
modules accessible via `global.require()`:

```javascript
const fs      = global.require("wx:fs");       // FileSystem
const reflect = global.require("wx:reflect");  // Java reflection bridge
const process = global.require("wx:process");  // process spawning/management
const module  = global.require("wx:module");   // module-info helpers
const pm      = global.require("wx:pm");        // PackageManager
const pty     = global.require("wx:pty");       // Pty.Shell — interactive shell (v213+)
```

To enable, `config.json` needs:
```jsonc
{
  "dexFiles": [
    { "type": "dex", "path": "plugins/webui.dex", "className": "dev.mmrl.Global" }
  ],
  "extra": {
    "pm": { "allowUrlPackageFetch": true }
  }
}
```

`"extra".pm.allowUrlPackageFetch: true` additionally enables fetching package
metadata/icons via:
```
https://mui.kernelsu.org/.package/<packageName>/info.json
https://mui.kernelsu.org/.package/<packageName>/icon.(jpg|png|webp)
```
— useful for building app-picker UIs without shipping your own icon assets.

> **When to reach for this**: only when `ksu.exec()` + `window.$<id>` genuinely
> aren't enough — e.g. you need a real interactive PTY (`wx:pty`), Java reflection
> into framework internals (`wx:reflect`), or PackageManager queries beyond
> `ksu.listAllPackages()`. For 95% of tab-based config UIs, the `ksu.*` bridge is
> sufficient and far simpler to maintain.

---

## 6. Application Info Flags (via `pm` plugin)

Once `pm = global.require("wx:pm")` is available, you can read raw
`ApplicationInfo.flags` bitmask for any package:

```javascript
const info = JSON.parse(pm.getApplicationInfo("com.topjohnwu.magisk"));
const FLAG_SYSTEM      = 1 << 0;
const FLAG_DEBUGGABLE  = 1 << 1;
const FLAG_HAS_CODE    = 1 << 2;
const isSystemApp = (info.flags & FLAG_SYSTEM) !== 0;
```

Common flags worth checking in module UIs:

| Flag | Bit | Meaning |
|---|---|---|
| `FLAG_SYSTEM` | `1<<0` | installed in `/system` |
| `FLAG_DEBUGGABLE` | `1<<1` | app is debuggable |
| `FLAG_PERSISTENT` | `1<<3` | persistent process |
| `FLAG_UPDATED_SYSTEM_APP` | `1<<7` | system app w/ user update |
| `FLAG_STOPPED` | `1<<21` | force-stopped |
| `FLAG_SUSPENDED` | `1<<30` | suspended by PM |

Don't use `FLAG_SYSTEM` for security/trust decisions — only for display/diagnostics
(e.g. "is this a system app you're about to freeze?" warnings in an AppNuker-style
module).

---

## 7. Debugging WebUI X modules

This is the workflow to actually use, in order of effort:

1. **Eruda console (built-in)** — WebUI X auto-injects [Eruda](https://eruda.liriliri.io/),
   a mobile dev-console overlay. Enable "Auto Open Eruda" in WebUI X settings to
   get `console.log`, element inspector, network tab, and a JS REPL directly on
   the device, no PC needed. This is the primary debug loop for this user's
   PC-less workflow.
   - Use the element inspector to grab real class names/ids before writing CSS
     selectors or `querySelector` calls.
   - `console.log()` from any injected/body script shows up here.

2. **Remote URL debugging** — WebUI X Portable can point a module's WebUI at
   `http://localhost:<port>` instead of the packaged `webroot/`. This lets you
   iterate on HTML/CSS/JS served from a local dev server (e.g. a tiny
   `busybox httpd` on-device, or `python3 -m http.server` if available) without
   re-flashing the module zip on every change. Reserve this for active UI
   development sessions; ship the static `webroot/` for releases.

3. **Developer Mode** — toggle in WebUI X / MMRL settings. Reveals module IDs,
   `sanitizedModId`, and extra metrics in the UI — useful when debugging
   `window.$<id>` interface availability.

4. **Logs tab pattern** (this skill's template) — for *runtime* (post-flash,
   non-interactive) debugging, the Logs tab reading `service.log` /
   `post-fs-data.log` remains the most reliable: Eruda only helps while you're
   actively looking at the screen, but boot-time script failures need persisted
   logs.

**Anti-pattern**: don't build custom in-page "debug consoles" from scratch —
Eruda already provides this, and a hand-rolled one adds maintenance burden for
no benefit.

---

## 8. Custom CSS/JS patching (end-user side, good to know)

WebUI X Portable supports **per-module user patches** that live outside your
module entirely:

```
/data/adb/.config/<id>/
├── style/patch.css        # injected, can override your CSS with !important
└── js/
    ├── head/*.js|*.mjs     # injected into <head>
    └── body/*.js|*.mjs     # injected into <body>, .mjs = ES module
```

Implications for module authors:
- Don't fight this — if a user patches your UI, that's expected/supported by
  the platform, not a bug report against your module.
- If your module exposes a "theme" or "advanced" tab, you can mention this
  mechanism in your README as the "power user" customization path instead of
  building your own theme-switcher.

---

## 9. Shortcuts (home-screen pinning)

Since WebUI X v33404+, with a launcher that supports pinned shortcuts:

```jsonc
// config.mmrl.json
{ "title": "sd-mounter", "icon": "icon.webp" }
```

```javascript
window.$<sanitizedModId>.createShortcut();                 // uses config title/icon
window.$<sanitizedModId>.createShortcut("Mount SD", "icon.webp"); // override
```

Good fit for: modules whose primary interaction is "open this one screen and
tap a button" (e.g. `sd-mounter`'s mount/unmount toggle) — the user can launch
it directly without going through MMRL.

---

## 10. Decision guide — which API surface do I need?

| Need | Use |
|---|---|
| Run shell command, read/write files, toast | `ksu.*` (always available, most portable) |
| Detect host dark/light theme, status-bar inset, recompose | `window.$<sanitizedModId>` |
| Native look matching user's MMRL theme | `/internal/insets.css` + `/internal/colors.css` |
| Interactive shell/PTY, reflection, deep PackageManager queries | WXU `global.require("wx:*")` + `dexFiles` in `config.json` |
| App icons/info without shipping assets | `pm` plugin + `extra.pm.allowUrlPackageFetch` |
| Pin module to home screen | `config.mmrl.json` + `createShortcut()` |
| Debug on-device, no PC | Eruda (auto-injected) |
| Iterate on UI without reflashing | Remote URL debugging (`localhost`) |
