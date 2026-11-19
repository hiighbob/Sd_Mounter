# Root Ecosystem Synergy — Magisk · KernelSU · APatch · LSPosed/Zygisk · Shizuku

> Read this when a module needs to detect, cooperate with, or avoid conflicting
> with other root-adjacent components on the device — or when the user asks
> "will this work alongside X?" / "should this be a Magisk module or an Xposed
> module?" / "can I use Shizuku for this instead?"

---

## 1. The layers, top to bottom

```
┌─────────────────────────────────────────────────────────┐
│ WebUI X / MMRL  — config UI layer (webroot/, JS bridges) │
├─────────────────────────────────────────────────────────┤
│ Module manager app — Magisk Manager / KernelSU / APatch  │
│   installs & toggles modules, runs install scripts       │
├─────────────────────────────────────────────────────────┤
│ Module runtime — systemless overlay (Magic Mount/        │
│   OverlayFS) + post-fs-data.sh / service.sh execution     │
├─────────────────────────────────────────────────────────┤
│ Zygisk / Zygisk-Next / APatch KPM — process-injection     │
│   layer, hosts LSPosed, DenyList/hide logic                │
├─────────────────────────────────────────────────────────┤
│ Root provider — Magisk daemon / KernelSU kernel module /  │
│   APatch kernel patch — grants su, mounts, SELinux policy │
├─────────────────────────────────────────────────────────┤
│ Shizuku — ADB/root-shell-spawned privileged service,      │
│   independent of the above; apps bind to it for elevated  │
│   API access without full root                            │
└─────────────────────────────────────────────────────────┘
```

A WebUI X Magisk module sits at the **top two layers**: it's a module (3rd layer)
with a config UI (1st layer). Everything below is context it can *query* and
*cooperate with*, but generally shouldn't try to replace.

---

## 2. Root providers — what changes per provider

| | Magisk | KernelSU (+Next) | APatch / SukiSU Ultra |
|---|---|---|---|
| Mechanism | userspace daemon + magiskinit | kernel module/patch (GKI) | kernel patch (KPM support) |
| Module mount | Magic Mount or OverlayFS | OverlayFS | OverlayFS / KPM |
| `su` grant UI | Magisk app | Manager app | Manager app |
| WebUI support | v28.1+ native; older = needs WebUI X / KSU WebUI standalone | native since v0.8.1 (origin of WebUI X) | via WebUI X (cross-compat) |
| sepolicy.rule | ✅ supported | different path — KSU has its own sepolicy injection | varies |
| `ksu.*` JS bridge | ✅ (via WebUI X) | ✅ (native origin) | ✅ (via WebUI X) |
| KPM (kernel patch modules) | ❌ | ❌ | ✅ APatch/SukiSU only |

**Module-author takeaway**: write `module.prop` + scripts to be root-manager
agnostic where possible (the shell-script/`webroot/` pattern in this skill works
across all three). Only branch behavior on root manager when:
- using `sepolicy.rule` (Magisk-specific path),
- using KPM (`templates/kpm/`, APatch/SukiSU only),
- targeting root-manager-specific JS APIs beyond the `ksu.*` baseline.

---

## 3. Zygisk, Zygisk-Next, and LSPosed

- **Zygisk** = Magisk's process-injection framework (built into Magisk, or via
  **Zygisk-Next** as a standalone module on KernelSU/other managers that dropped
  built-in Zygisk).
- **LSPosed** is itself a *Zygisk module* (or, on older setups, a separate
  Xposed framework) that then loads further Xposed modules (Java hooks into app
  processes).
- A **WebUI X Magisk module** and an **LSPosed module** are different packaging
  formats for different jobs:
  - Filesystem overlay / boot scripts / system properties / SELinux → **Magisk
    module** (this skill's default target).
  - Runtime Java method hooking inside specific app processes → **LSPosed/Xposed
    module** (`templates/xposed/`, needs LSPosed installed + Zygisk enabled).
- **They compose**: a single project can ship *both* — a Magisk module for
  filesystem/boot-time setup and webroot config UI, that also drops an Xposed
  `.dex`/APK for LSPosed to load. Decide this in Phase 3 "Gather requirements"
  (see main SKILL.md, question 2 — "Zygisk needed?").

**Conflict checks worth surfacing in a module's Status tab**:
```sh
# Is Zygisk active at all?
[ -d /data/adb/modules/zygisk* ] 2>/dev/null && echo "Zygisk-Next present"
# Is LSPosed installed?
pm path org.lsposed.manager 2>/dev/null
```

---

## 4. Shizuku — when it's the better tool than a Magisk module

[Shizuku](https://shizuku.rikka.app/) runs a privileged service started via ADB
(`adb shell sh /sdcard/Android/data/.../start.sh`) or, on rooted devices, via
`su`. Apps then bind to that service for elevated `PackageManager`/system API
access **without needing root themselves**.

| Scenario | Better fit |
|---|---|
| Persistent boot-time filesystem/script changes, system overlays, SELinux | **Magisk module** |
| One-off privileged action triggered from a *separate companion app* you're building (not a WebUI) | **Shizuku**-bound app |
| You want a WebUI X module's `webroot/` to also be testable from a non-rooted/secondary device for UI dev | WebUI X Portable supports **non-rooted devices** for UI preview — Shizuku not required for this |
| Need `pm`/`am`/`appops` style calls from a normal app process | Shizuku API in that app |

For this user's workflow (Magisk modules with WebUI X config UIs on the
SM-A530W), Shizuku is rarely the right tool *for the module itself* — but it's
worth knowing about if a request describes "an app that needs elevated access
without flashing a module," which is a different deliverable than this skill's
default Magisk-module-with-WebUI output. Flag this distinction to the user if
their description sounds like a standalone app rather than a flashable module.

---

## 5. Device-specific synergy notes — SM-A530W (Android 9, Magisk 30100)

- **SELinux permissive** — `sepolicy.rule` patches are effectively no-ops here
  but should still be written/documented for portability to enforcing devices
  (see `references/portability.md`).
- **No OverlayFS** — Magisk uses **Magic Mount** on this kernel
  (4.4.111-Quantum_pie-V4.0). Modules relying on OverlayFS-only behaviors
  (some newer KernelSU patterns) won't translate directly; stick to the
  Magic-Mount-compatible `system/` overlay structure.
- **Zygisk availability** depends on the installed Magisk build/variant on this
  device — confirm before assuming Zygisk-dependent modules (incl. some LSPosed
  setups) will load. If unconfirmed, surface this as a requirement check in the
  module's Status tab rather than assuming.
- **WebUI X via MMRL** is the confirmed working path on this device
  (User-Agent `WebUI X/433`). This is the primary target for all GUI work —
  default to it before considering a native APK or a separate Shizuku-based app.

---

## 6. Quick decision tree

```
User wants...
  "a config screen for my script/tweak"
        → WebUI X Magisk module (this skill's default)

  "to hook into another app's runtime behavior"
        → LSPosed/Xposed module (needs Zygisk) — can still ship
          alongside a Magisk module + WebUI for its own settings

  "kernel-level patching (KPM)"
        → APatch/SukiSU only — templates/kpm/

  "an app that needs elevated access but user won't flash a module"
        → Shizuku-bound app — different deliverable, flag to user

  "anything else with a UI on this device"
        → WebUI X webroot — almost always faster to build and
          iterate (Eruda debugging, no APK signing/build step)
          than a native Android app
```
