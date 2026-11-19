#!/system/bin/sh
# sd_probe.sh — SD Mounter v1.2
# Sortie : lignes key=value, parsées par le WebUI via split('=',1)
#
# v1.2 : toutes les vérifications de mount utilisent /proc/1/mounts (PID 1)
# et non la commande mount — celle-ci lit le namespace du process MMRL/WebView
# qui ne voit pas les bind-mounts créés en post-fs-data / service.sh.

SD_P1="/dev/block/mmcblk1p1"
SD_P2="/dev/block/mmcblk1p2"
EXT4_MOUNT="/mnt/ext4sd"
EXFAT_UUID="6603-7A19"
EXFAT_MOUNT="/mnt/media_rw/$EXFAT_UUID"

# ── Block devices ─────────────────────────────────────────────────
if [ -b "$SD_P1" ]; then echo "p1_block=found"; else echo "p1_block=missing"; fi
if [ -b "$SD_P2" ]; then echo "p2_block=found"; else echo "p2_block=missing"; fi

# ── exFAT (p1) mount ─────────────────────────────────────────────
# Lecture depuis /proc/1/mounts — namespace PID 1 (init), pas le namespace WebUI
P1_MOUNTED=0
cat /proc/1/mounts 2>/dev/null | grep -qE "$EXFAT_MOUNT|$EXFAT_UUID" && P1_MOUNTED=1
echo "p1_mounted=$P1_MOUNTED"

# Chemin de montage exFAT détecté
P1_PATH=$(cat /proc/1/mounts 2>/dev/null | grep -E "$EXFAT_UUID|$EXFAT_MOUNT" | awk '{print $2}' | head -1)
echo "p1_path=${P1_PATH:-none}"

# vold state pour public:179,33
VOLD_P1=$(sm list-volumes 2>/dev/null | grep "179,33" | awk '{print $2}')
echo "vold_p1=${VOLD_P1:-unknown}"

# ── ext4 (p2) mount ───────────────────────────────────────────────
P2_MOUNTED=0
cat /proc/1/mounts 2>/dev/null | grep -q " $EXT4_MOUNT " && P2_MOUNTED=1
echo "p2_mounted=$P2_MOUNTED"

# Utilisation ext4 (si monté)
if [ "$P2_MOUNTED" = "1" ]; then
    P2_USED=$(df -k "$EXT4_MOUNT" 2>/dev/null | tail -1 | awk '{print int($3/1024)}')
    P2_AVAIL=$(df -k "$EXT4_MOUNT" 2>/dev/null | tail -1 | awk '{print int($4/1024)}')
    echo "p2_used_mb=${P2_USED:-0}"
    echo "p2_avail_mb=${P2_AVAIL:-0}"
else
    echo "p2_used_mb=0"
    echo "p2_avail_mb=0"
fi

# ── Bind-mounts ───────────────────────────────────────────────────
# Lecture /proc/1/mounts — les bind-mounts créés en post-fs-data vivent
# dans le namespace de PID 1 et sont invisibles via la commande mount
# depuis le WebUI (namespace MMRL/WebView différent).
APP_BM=$(cat /proc/1/mounts 2>/dev/null | grep "^/dev/block/mmcblk1p2 /data/app/" | wc -l | xargs)
DATA_BM=$(cat /proc/1/mounts 2>/dev/null | grep "^/dev/block/mmcblk1p2 /data/data/" | wc -l | xargs)
echo "app_bm=$APP_BM"
echo "data_bm=$DATA_BM"

# Nombre d'entrées attendues (depuis ext4sd si monté)
if [ -d "$EXT4_MOUNT/app" ]; then
    APP_EXP=$(ls -1 "$EXT4_MOUNT/app" 2>/dev/null | wc -l | xargs)
else
    APP_EXP=0
fi
if [ -d "$EXT4_MOUNT/data" ]; then
    DATA_EXP=$(ls -1 "$EXT4_MOUNT/data" 2>/dev/null | wc -l | xargs)
else
    DATA_EXP=0
fi
echo "app_expected=$APP_EXP"
echo "data_expected=$DATA_EXP"

# ── /storage/UUID bind-mount (BUG 2 fix — exFAT visible aux apps) ─
STORAGE_PATH="/storage/$EXFAT_UUID"
if cat /proc/1/mounts 2>/dev/null | grep -q " $STORAGE_PATH "; then
    echo "storage_bind=ok"
else
    echo "storage_bind=missing"
fi

# ── Toutes les volumes vold (pipe-séparées) ───────────────────────
VOLS=$(sm list-volumes 2>/dev/null | tr '\n' '|')
echo "vold_all=$VOLS"

# ── Lignes mount SD depuis /proc/1/mounts (pipe-séparées) ────────
MT=$(cat /proc/1/mounts 2>/dev/null | grep -E "mmcblk1|$EXFAT_UUID|179,3[23]|ext4sd" | tr '\n' '|')
echo "mount_lines=${MT:-none}"

# ── Détection MBR fix (type byte p1) ─────────────────────────────
MBR_P1_TYPE=$(dd if=/dev/block/mmcblk1p1 bs=1 skip=450 count=1 2>/dev/null \
    | od -An -tx1 | tr -d ' \n' 2>/dev/null)
# Lire depuis le device entier (MBR offset 450)
MBR_TYPE=$(dd if=/dev/block/mmcblk1 bs=1 skip=450 count=1 2>/dev/null \
    | od -An -tx1 | tr -d ' \n' 2>/dev/null)
if [ "$MBR_TYPE" = "0c" ]; then
    echo "mbr_fix=applied"
elif [ "$MBR_TYPE" = "07" ]; then
    echo "mbr_fix=pending"
else
    echo "mbr_fix=unknown_${MBR_TYPE}"
fi

# ── Source exFAT (vold ou sdfat) ─────────────────────────────────
EXFAT_SRC=$(cat /proc/1/mounts 2>/dev/null | grep " /mnt/media_rw/6603-7A19 " \
    | awk '{print $1}' | head -1)
if echo "$EXFAT_SRC" | grep -q "vold"; then
    echo "exfat_source=vold"
elif echo "$EXFAT_SRC" | grep -q "mmcblk1p1"; then
    echo "exfat_source=sdfat"
elif [ -n "$EXFAT_SRC" ]; then
    echo "exfat_source=$EXFAT_SRC"
else
    echo "exfat_source=none"
fi
