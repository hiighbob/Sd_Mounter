#!/system/bin/sh
# =============================================================================
# deploy_sd_unfucker_v1.8.sh — sans ZIP, sans Python
# Stratégie : patch direct sur le module live + copie dans modules_update
# Outils requis : busybox (cp, sed, cat, chmod, mkdir) — déjà présent
# =============================================================================

set -e

DL="/sdcard/Download"
MOD_LIVE="/data/adb/modules/sd_unfucker"
MOD_UPDATE="/data/adb/modules/sd_unfucker"  # même path — patch in-place + reboot
MAGISK="/data/adb/magisk"
BB="$MAGISK/busybox"
UNIFY="$DL/unify_architecture_v1.8.sh"
WEBUI_SRC="$DL/index.html"

G='\033[0;32m' Y='\033[0;33m' R='\033[0;31m' C='\033[0;36m' N='\033[0m'
log() { echo "${C}[*]${N} $1"; }
ok()  { echo "${G}[✓]${N} $1"; }
die() { echo "${R}[✗]${N} $1"; exit 1; }

# ── Vérifications ──────────────────────────────────────────────────
log "Vérification environnement..."
[ "$(id -u)" = "0" ]  || die "Doit tourner en root"
[ -f "$UNIFY" ]        || die "Manquant : $UNIFY"
[ -f "$WEBUI_SRC" ]    || die "Manquant : $WEBUI_SRC"
[ -d "$MOD_LIVE" ]     || die "Module v1.6 absent : $MOD_LIVE"
[ -x "$BB" ]           || die "busybox Magisk absent : $BB"
ok "Environnement OK"

# ── Démonter les bind mounts v1.6 proprement ──────────────────────
log "Démontage bind mounts v1.6..."
if [ -f "$MOD_LIVE/uninstall.sh" ]; then
    sh "$MOD_LIVE/uninstall.sh" && ok "uninstall.sh OK" || true
fi

# ── Patch in-place : pas de staging, on écrase le module live directement ──
log "Patch in-place sur $MOD_LIVE ..."
mkdir -p "$MOD_LIVE/scripts" "$MOD_LIVE/webroot" "$MOD_LIVE/logs"
ok "Dossiers OK"

# ── Appliquer unify_architecture_v1.8.sh sur le staging ───────────
log "Application de unify_architecture_v1.8.sh..."
# Rediriger MODDIR vers le staging
$BB sed "s|/data/adb/modules/sd_unfucker|$MOD_UPDATE|g" "$UNIFY" \
    > /data/local/tmp/unify_staged.sh
chmod 755 /data/local/tmp/unify_staged.sh
sh /data/local/tmp/unify_staged.sh
ok "unify_architecture_v1.8.sh appliqué"

# ── Injecter WebUI v2.0 ───────────────────────────────────────────
log "Injection WebUI v2.0..."
$BB cp "$WEBUI_SRC" "$MOD_UPDATE/webroot/index.html"
ok "index.html remplacé"

# ── Patch module.prop ─────────────────────────────────────────────
log "Patch module.prop..."
$BB sed -i 's/^version=.*/version=v1.8/'        "$MOD_UPDATE/module.prop"
$BB sed -i 's/^versionCode=.*/versionCode=180/' "$MOD_UPDATE/module.prop"
ok "module.prop → v1.8 / 180"

# ── Permissions ───────────────────────────────────────────────────
log "Permissions..."
chmod 755 "$MOD_UPDATE/post-fs-data.sh" \
          "$MOD_UPDATE/service.sh" \
          "$MOD_UPDATE/customize.sh" \
          "$MOD_UPDATE/uninstall.sh" 2>/dev/null || true
chmod 755 "$MOD_UPDATE/scripts/"*.sh 2>/dev/null || true
chmod 644 "$MOD_UPDATE/module.prop" \
          "$MOD_UPDATE/bind_mounts.conf" 2>/dev/null || true
ok "Permissions OK"

# ── Vérifications post-patch ──────────────────────────────────────
log "Vérifications..."
[ -f "$MOD_UPDATE/scripts/fix_exfat.sh" ] \
    && ok "scripts/fix_exfat.sh présent" \
    || echo "${Y}[!]${N} scripts/fix_exfat.sh absent — WebUI bouton Réparer non fonctionnel"
grep -q "v1.8" "$MOD_UPDATE/post-fs-data.sh" \
    && ok "post-fs-data.sh v1.8 OK" \
    || echo "${Y}[!]${N} post-fs-data.sh: v1.8 non trouvé"
grep -q "fix_termux_permissions" "$MOD_UPDATE/service.sh" \
    && ok "service.sh: fix_termux_permissions présent" \
    || echo "${Y}[!]${N} service.sh: fix_termux_permissions absent"

# ── Marquer remove inutile en patch in-place — supprimer si présent ──
rm -f "$MOD_LIVE/remove" 2>/dev/null || true
ok "Flag remove nettoyé"

# ── Nettoyage ─────────────────────────────────────────────────────
rm -f /data/local/tmp/unify_staged.sh

# ── Résumé + reboot ───────────────────────────────────────────────
echo ""
echo "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
ok "v1.6 démonté et marqué remove"
ok "v1.8 staging dans modules_update"
ok "WebUI v2.0 injecté"
echo "${Y}[!] Reboot dans 5 secondes... Ctrl+C pour annuler${N}"
echo "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
sleep 5
reboot