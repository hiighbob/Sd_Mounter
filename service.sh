#!/system/bin/sh
# service.sh — SD Mounter v1.1
# Lance sd_mount.sh après boot_completed.
#
# v1.1 : ext4 + bind-mounts /data/app et /data/data sont déjà faits par
# post-fs-data.sh (step "early", avant Zygote/PM scan). Le step "all" ici
# est idempotent : mount_ext4 et do_bind_mounts SKIP tout ce qui est déjà
# monté (sert de filet de sécurité si "early" a échoué — ext4 pas encore
# dispo en post-fs-data par ex.). exFAT + notify PM nécessitent le framework
# (sm/am) donc restent ici.
MODDIR=${0%/*}
LOG="$MODDIR/logs/service.log"
mkdir -p "$MODDIR/logs"
exec >> "$LOG" 2>&1

echo ""
echo "============================================"
echo "[$(date '+%F %T')] SERVICE START"
echo "============================================"

# ── Lire config ───────────────────────────────────────────────────
CFG="$MODDIR/webroot/config_state.json"
read_cfg() {
    key="$1"; default="$2"
    if [ -f "$CFG" ]; then
        val=$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*" "$CFG" \
              | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"' | xargs)
        [ -n "$val" ] && echo "$val" || echo "$default"
    else
        echo "$default"
    fi
}

AUTO=$(read_cfg "auto_run_on_boot" "true")
echo "[service] auto_run_on_boot=$AUTO"

if [ "$AUTO" != "true" ]; then
    echo "[service] Auto-run désactivé — attente trigger WebUI"
    exit 0
fi

# ── Attendre boot_completed ───────────────────────────────────────
WAITED=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3; WAITED=$((WAITED+3))
    [ $WAITED -ge 120 ] && echo "[service] WARN timeout boot_completed" && break
done
echo "[service] boot_completed après ${WAITED}s"

# Extra marge pour vold/sm/sdcard daemon (empirique sur SM-A530W)
DELAY=$(read_cfg "boot_delay_sec" "15")
echo "[service] Délai extra: ${DELAY}s"
sleep "$DELAY"

# ── Lancer le monteur ─────────────────────────────────────────────
echo "[service] Lancement sd_mount.sh (all = exfat + ext4 + bind, sans notify)..."
sh "$MODDIR/scripts/sd_mount.sh"
EXIT=$?
echo "[service] sd_mount.sh exit=$EXIT"

# ── Scan média SD (optionnel — ~3-4min, broadcast MEDIA_MOUNTED) ──
# Confirmé sur ce device : ce broadcast déclenche un scan média complet
# de la SD (~3-4min sur 40GB exFAT) et n'aide PAS PM à voir /data/app
# (déjà réglé par "early" en post-fs-data). Désactivé par défaut.
SCAN=$(read_cfg "media_scan_on_boot" "false")
echo "[service] media_scan_on_boot=$SCAN"
if [ "$SCAN" = "true" ]; then
    echo "[service] Lancement sd_mount.sh notify (scan média SD, peut prendre 3-4min)..."
    sh "$MODDIR/scripts/sd_mount.sh" notify
    echo "[service] sd_mount.sh notify exit=$?"
fi

echo "[$(date '+%F %T')] SERVICE END"
