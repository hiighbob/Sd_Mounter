#!/system/bin/sh
# post-fs-data.sh — SD Mounter v1.1
# v1.1 : mmcblk1p2 (ext4) EST disponible ici (confirmé par les logs du
# premier boot — setrw OK avant Zygote). On monte ext4 + bind-mounts
# /data/app et /data/data MAINTENANT, avant le scan PackageManager.
# (exFAT/vold/sm/am restent dans service.sh — framework pas dispo ici.)
MODDIR=${0%/*}
LOG="$MODDIR/logs/post-fs-data.log"
mkdir -p "$MODDIR/logs"
exec >> "$LOG" 2>&1

echo ""
echo "============================================"
echo "[$(date '+%F %T')] POST-FS-DATA START"
echo "============================================"

# ── Créer les points de montage (tôt pour que vold les voit) ─────
for mp in /mnt/ext4sd /mnt/media_rw/6603-7A19; do
    if [ ! -d "$mp" ]; then
        mkdir -p "$mp" && echo "[post-fs] Créé: $mp" || echo "[post-fs] WARN mkdir failed: $mp"
    else
        echo "[post-fs] Existe déjà: $mp"
    fi
done

# ── Enlever write-protect sur mmcblk1 (flag hardware) ───────────
for dev in /dev/block/mmcblk1 /dev/block/mmcblk1p1 /dev/block/mmcblk1p2; do
    if [ -b "$dev" ]; then
        blockdev --setrw "$dev" 2>/dev/null \
            && echo "[post-fs] setrw OK: $dev" \
            || echo "[post-fs] WARN setrw failed: $dev"
    fi
done

echo "[post-fs] Lancement sd_mount.sh early (ext4 + bind-mounts, avant PM scan)..."
sh "$MODDIR/scripts/sd_mount.sh" early
echo "[post-fs] sd_mount.sh early exit=$?"
echo "[$(date '+%F %T')] POST-FS-DATA END"
