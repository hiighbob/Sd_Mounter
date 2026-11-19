#!/system/bin/sh
# sd_mount.sh — SD Mounter v1.5
# Adaptatif : vold OU sdfat pour exFAT selon état MBR.
# ext4 (mmcblk1p2) toujours géré par le module.
# POSIX sh strict — pas de bash, pas de tableaux.
#
# Steps:
#   (vide)     → all : exFAT(adaptatif) + ext4 + bind-mounts + /storage bind
#   early      → ext4 + bind-mounts SEULEMENT (post-fs-data, avant Zygote)
#   exfat      → monter mmcblk1p1 seulement (adaptatif)
#   ext4       → monter mmcblk1p2 seulement
#   bind       → bind-mounts seulement (ext4 doit être monté)
#   chown      → corriger UIDs sur ext4 (run once après install)
#   notify     → broadcast MEDIA_MOUNTED (scan média SD, ~3-4min)
#   fix-mbr    → changer type MBR p1: 0x07→0x0c (reboot requis après)
#   unmount    → démonter tout (arrêter les apps d'abord)

MODDIR=$(dirname "$0")/..
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd || echo "/data/adb/modules/sd-mounter")
LOG="$MODDIR/logs/mount.log"
mkdir -p "$MODDIR/logs"

# Rotation log (>500 lignes)
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null)" -gt 500 ]; then
    tail -300 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

exec >> "$LOG" 2>&1

SD_P1="/dev/block/mmcblk1p1"
SD_P2="/dev/block/mmcblk1p2"
EXT4_MOUNT="/mnt/ext4sd"
EXFAT_MOUNT="/mnt/media_rw/6603-7A19"
EXFAT_UUID="6603-7A19"

STEP="${1:-all}"
log() { echo "[$(date '+%F %T')] $1"; }
log "=== SD MOUNTER START (step=$STEP) ==="

# ════════════════════════════════════════════════════════════════════
# UNMOUNT
# ════════════════════════════════════════════════════════════════════
do_unmount() {
    log "--- UNMOUNT ---"
    STORAGE_PATH="/storage/$EXFAT_UUID"
    # /storage bind en premier
    if cat /proc/1/mounts 2>/dev/null | grep -q " $STORAGE_PATH "; then
        umount "$STORAGE_PATH" 2>/dev/null \
            && log "  umount OK: $STORAGE_PATH" \
            || log "  WARN umount: $STORAGE_PATH"
    fi
    # bind-mounts /data/app
    cat /proc/1/mounts 2>/dev/null | grep "^/dev/block/mmcblk1p2 /data/app/" \
        | awk '{print $2}' | while read -r dst; do
        umount "$dst" 2>/dev/null \
            && log "  umount OK: $dst" \
            || log "  WARN: $dst"
    done
    # bind-mounts /data/data
    cat /proc/1/mounts 2>/dev/null | grep "^/dev/block/mmcblk1p2 /data/data/" \
        | awk '{print $2}' | while read -r dst; do
        umount "$dst" 2>/dev/null \
            && log "  umount OK: $dst" \
            || log "  WARN: $dst"
    done
    # ext4
    if cat /proc/1/mounts 2>/dev/null | grep -q " $EXT4_MOUNT "; then
        umount "$EXT4_MOUNT" 2>/dev/null \
            && log "ext4 démonté OK" \
            || log "WARN: umount ext4 failed"
    fi
    # exFAT (seulement si monté par nous, pas par vold)
    if cat /proc/1/mounts 2>/dev/null | grep " $EXFAT_MOUNT " | grep -v "vold" | grep -q "mmcblk1p1\|sdfat"; then
        umount "$EXFAT_MOUNT" 2>/dev/null \
            && log "exFAT (sdfat) démonté OK" \
            || log "WARN: umount exFAT failed"
    fi
}

if [ "$STEP" = "unmount" ]; then
    do_unmount; log "=== SD MOUNTER END ==="; exit 0
fi

# ════════════════════════════════════════════════════════════════════
# FIX MBR — Changer type partition p1 : 0x07 (exFAT/NTFS) → 0x0c (FAT32 LBA)
# Cause confirmée du HiddenMount : vold (sgdisk --android-dump) ne reconnaît
# pas le type 0x07 comme partition SD valide quand p2=0x83 coexiste.
# Après le fix + reboot : vold monte exFAT normalement, /storage/UUID writable.
# Zero risque data : seul 1 octet du MBR change (pas le filesystem lui-même).
# ════════════════════════════════════════════════════════════════════
do_fix_mbr() {
    log "--- FIX MBR : type p1 0x07 → 0x0c ---"
    # Backup
    BACKUP="/sdcard/Download/mbr_backup_$(date +%Y%m%d_%H%M%S).bin"
    dd if=/dev/block/mmcblk1 bs=512 count=1 of="$BACKUP" 2>/dev/null \
        && log "  Backup: $BACKUP" \
        || log "  WARN: backup failed (continuer quand même)"
    # Vérifier état actuel (offset 450 = 0x1C2 = type byte p1 dans MBR)
    CURRENT=$(dd if=/dev/block/mmcblk1 bs=1 skip=450 count=1 2>/dev/null \
        | od -An -tx1 | tr -d ' \n')
    log "  Type actuel p1: 0x${CURRENT:-??}"
    if [ "$CURRENT" = "0c" ]; then
        log "  Déjà 0x0c — fix déjà appliqué. Reboot pour activer si pas encore fait."
        return 0
    fi
    if [ "$CURRENT" != "07" ]; then
        log "  WARN: type inattendu 0x${CURRENT} (attendu 0x07) — abort pour sécurité"
        return 1
    fi
    # Appliquer
    printf '\x0c' | dd of=/dev/block/mmcblk1 bs=1 seek=450 conv=notrunc 2>/dev/null
    RC=$?
    NEW=$(dd if=/dev/block/mmcblk1 bs=1 skip=450 count=1 2>/dev/null \
        | od -An -tx1 | tr -d ' \n')
    log "  Type après fix: 0x${NEW:-??}"
    if [ $RC -eq 0 ] && [ "$NEW" = "0c" ]; then
        log "  FIX MBR OK — REBOOT REQUIS"
        log "  Après reboot: vold monte exFAT nativement, /storage/$EXFAT_UUID writable"
    else
        log "  ERREUR fix MBR (exit=$RC, type=$NEW)"
    fi
}

if [ "$STEP" = "fix-mbr" ]; then
    do_fix_mbr; log "=== SD MOUNTER END ==="; exit 0
fi

# ════════════════════════════════════════════════════════════════════
# CHOWN — Corriger UIDs sur ext4 (run once après install)
# ════════════════════════════════════════════════════════════════════
do_chown() {
    log "--- CHOWN UIDs sur ext4 ---"
    if [ ! -d "$EXT4_MOUNT/data" ]; then
        log "WARN: $EXT4_MOUNT/data absent — ext4 monté ?"; return 1
    fi
    FIXED=0; SKIP=0; FAIL=0
    for src in "$EXT4_MOUNT/data/"/*/; do
        [ -d "$src" ] || continue
        pkg="${src%/}"; pkg="${pkg##*/}"
        [ -z "$pkg" ] && continue
        UID_LINE=$(pm dump "$pkg" 2>/dev/null | grep "userId=" | head -1)
        PKG_UID=$(echo "$UID_LINE" | sed 's/.*userId=//' | awk '{print $1}' | tr -d '[:space:]')
        if [ -z "$PKG_UID" ] || [ "$PKG_UID" = "0" ]; then
            log "  [chown] SKIP $pkg — UID introuvable"; SKIP=$((SKIP+1)); continue
        fi
        log "  [chown] $pkg → uid=$PKG_UID"
        chown -R "${PKG_UID}:${PKG_UID}" "$src" 2>&1
        RC=$?
        if [ $RC -eq 0 ]; then
            log "  [chown] OK: $pkg"; FIXED=$((FIXED+1))
        else
            log "  [chown] WARN exit=$RC: $pkg"; FAIL=$((FAIL+1))
        fi
    done
    log "  [chown] résultat: $FIXED OK / $SKIP skip / $FAIL FAIL"
}

if [ "$STEP" = "chown" ]; then
    do_chown; log "=== SD MOUNTER END ==="; exit 0
fi

# ════════════════════════════════════════════════════════════════════
# Attendre block devices
# ════════════════════════════════════════════════════════════════════
if [ "$STEP" = "all" ] || [ "$STEP" = "exfat" ] || [ "$STEP" = "ext4" ] || [ "$STEP" = "early" ]; then
    log "--- Attente block devices ---"
    WAITED=0
    while true; do
        NEED_P1=0; NEED_P2=0
        case "$STEP" in all|exfat) NEED_P1=1 ;; esac
        case "$STEP" in all|ext4|early) NEED_P2=1 ;; esac
        READY=1
        [ "$NEED_P1" = "1" ] && [ ! -b "$SD_P1" ] && READY=0
        [ "$NEED_P2" = "1" ] && [ ! -b "$SD_P2" ] && READY=0
        [ "$READY" = "1" ] && break
        sleep 1; WAITED=$((WAITED+1))
        [ $WAITED -ge 30 ] && log "WARN: timeout 30s" && break
    done
    log "Devices prêts après ${WAITED}s — p1=$([ -b "$SD_P1" ] && echo OK || echo ABSENT) p2=$([ -b "$SD_P2" ] && echo OK || echo ABSENT)"
fi

# ════════════════════════════════════════════════════════════════════
# EXFAT — Adaptatif : vold OU sdfat selon état MBR
# ════════════════════════════════════════════════════════════════════
_ensure_storage_bind() {
    STORAGE_PATH="/storage/$EXFAT_UUID"
    mkdir -p "$STORAGE_PATH"
    if cat /proc/1/mounts 2>/dev/null | grep -q " $STORAGE_PATH "; then
        log "  /storage bind déjà présent — skip"
        return 0
    fi
    # Si vold a monté via FUSE/sdcardfs, le chemin existe déjà en écriture
    if [ -w "$STORAGE_PATH" ]; then
        log "  /storage/$EXFAT_UUID writable (vold FUSE) — pas de bind nécessaire"
        return 0
    fi
    # Sinon bind-mount depuis notre sdfat mount
    mount --bind "$EXFAT_MOUNT" "$STORAGE_PATH" 2>&1
    RC=$?
    [ $RC -eq 0 ] \
        && log "  exFAT exposé sur $STORAGE_PATH OK" \
        || log "  WARN: bind $STORAGE_PATH failed (exit=$RC)"
}

mount_exfat() {
    log "--- Montage exFAT (mmcblk1p1) ---"
    mkdir -p "$EXFAT_MOUNT"

    # Si déjà monté (par vold ou par nous)
    if cat /proc/1/mounts 2>/dev/null | grep -q " $EXFAT_MOUNT "; then
        SOURCE=$(cat /proc/1/mounts 2>/dev/null | grep " $EXFAT_MOUNT " | awk '{print $1}' | head -1)
        if echo "$SOURCE" | grep -q "vold"; then
            log "exFAT monté par vold (MBR fix actif) — skip sdfat"
        else
            log "exFAT déjà monté ($SOURCE) — skip"
        fi
        _ensure_storage_bind
        return 0
    fi

    # Vérifier état vold AVANT de monter (MBR fix déjà appliqué ?)
    VOLD_STATE=$(sm list-volumes 2>/dev/null | grep "179,33" | awk '{print $2}')
    if [ "$VOLD_STATE" = "mounted" ]; then
        log "vold state=mounted (MBR fix actif) — pas de sdfat nécessaire"
        log "  /storage/$EXFAT_UUID accessible nativement via vold"
        return 0
    fi

    log "vold state=${VOLD_STATE:-unknown} → montage sdfat manuel"

    if [ ! -b "$SD_P1" ]; then
        log "WARN: $SD_P1 absent — skip montage exFAT"; return 1
    fi

    mount -t sdfat \
        -o uid=1023,gid=1023,fmask=0007,dmask=0007 \
        "$SD_P1" "$EXFAT_MOUNT" 2>&1
    RC=$?
    if [ $RC -eq 0 ]; then
        log "exFAT monté OK via sdfat sur $EXFAT_MOUNT"
    else
        log "WARN: sdfat exit=$RC — essai vfat..."
        mount -t vfat \
            -o uid=1023,gid=1023,fmask=0007,dmask=0007 \
            "$SD_P1" "$EXFAT_MOUNT" 2>&1
        RC=$?
        [ $RC -eq 0 ] \
            && log "exFAT monté OK via vfat" \
            || log "WARN: vfat aussi échoué — exFAT non disponible"
    fi

    sm mount public:179,33 2>/dev/null \
        && log "vold notifié OK" \
        || log "INFO: sm mount ignoré (HiddenMount bénin)"

    _ensure_storage_bind
    cat /proc/1/mounts 2>/dev/null | grep -q " $EXFAT_MOUNT " && return 0 || return 1
}

# ════════════════════════════════════════════════════════════════════
# EXT4 — mmcblk1p2
# ════════════════════════════════════════════════════════════════════
mount_ext4() {
    log "--- Montage ext4 (mmcblk1p2) ---"
    mkdir -p "$EXT4_MOUNT"
    if cat /proc/1/mounts 2>/dev/null | grep -q " $EXT4_MOUNT "; then
        log "ext4 déjà monté sur $EXT4_MOUNT — skip"; return 0
    fi
    if [ ! -b "$SD_P2" ]; then
        log "WARN: $SD_P2 absent — skip montage ext4"; return 1
    fi
    mount -t ext4 -o rw,relatime,seclabel "$SD_P2" "$EXT4_MOUNT" 2>&1
    RC=$?
    if [ $RC -eq 0 ]; then
        log "ext4 monté OK sur $EXT4_MOUNT"; return 0
    else
        log "WARN: seclabel exit=$RC — essai sans seclabel..."
        mount -t ext4 -o rw,relatime "$SD_P2" "$EXT4_MOUNT" 2>&1
        RC=$?
        [ $RC -eq 0 ] && log "ext4 monté OK (sans seclabel)" && return 0
        log "ERROR: ext4 mount failed (exit=$RC)"; return 1
    fi
}

# ════════════════════════════════════════════════════════════════════
# BIND-MOUNTS
# ════════════════════════════════════════════════════════════════════
do_bind_mounts() {
    log "--- Bind-mounts ---"
    if ! cat /proc/1/mounts 2>/dev/null | grep -q " $EXT4_MOUNT "; then
        log "ERROR: ext4 non monté — bind-mounts impossibles"; return 1
    fi
    APP_OK=0; APP_FAIL=0; DATA_OK=0; DATA_FAIL=0

    log "  [app] scan $EXT4_MOUNT/app/"
    if [ -d "$EXT4_MOUNT/app" ]; then
        for src in "$EXT4_MOUNT/app/"/*/; do
            [ -d "$src" ] || continue
            name="${src%/}"; name="${name##*/}"; [ -z "$name" ] && continue
            dst="/data/app/$name"
            [ ! -d "$dst" ] && mkdir -p "$dst"
            if cat /proc/1/mounts 2>/dev/null | grep -q " $dst "; then
                log "  [app] SKIP (déjà monté): $name"; APP_OK=$((APP_OK+1)); continue
            fi
            mount --bind "$src" "$dst" 2>&1
            RC=$?
            [ $RC -eq 0 ] \
                && { log "  [app] OK: $name"; APP_OK=$((APP_OK+1)); } \
                || { log "  [app] FAIL (exit=$RC): $name"; APP_FAIL=$((APP_FAIL+1)); }
        done
    else
        log "  [app] WARN: $EXT4_MOUNT/app absent"
    fi
    log "  [app] résultat: $APP_OK OK / $APP_FAIL FAIL"

    log "  [data] scan $EXT4_MOUNT/data/"
    if [ -d "$EXT4_MOUNT/data" ]; then
        for src in "$EXT4_MOUNT/data/"/*/; do
            [ -d "$src" ] || continue
            name="${src%/}"; name="${name##*/}"; [ -z "$name" ] && continue
            dst="/data/data/$name"
            if [ ! -d "$dst" ]; then
                log "  [data] WARN: $dst absent (app non installée ?) — skip"
                DATA_FAIL=$((DATA_FAIL+1)); continue
            fi
            if cat /proc/1/mounts 2>/dev/null | grep -q " $dst "; then
                log "  [data] SKIP (déjà monté): $name"; DATA_OK=$((DATA_OK+1)); continue
            fi
            mount --bind "$src" "$dst" 2>&1
            RC=$?
            [ $RC -eq 0 ] \
                && { log "  [data] OK: $name"; DATA_OK=$((DATA_OK+1)); } \
                || { log "  [data] FAIL (exit=$RC): $name"; DATA_FAIL=$((DATA_FAIL+1)); }
        done
    else
        log "  [data] WARN: $EXT4_MOUNT/data absent"
    fi
    log "  [data] résultat: $DATA_OK OK / $DATA_FAIL FAIL"
    return 0
}

# ════════════════════════════════════════════════════════════════════
# NOTIFY
# ════════════════════════════════════════════════════════════════════
notify_pm() {
    log "--- Notification MEDIA_MOUNTED (scan média SD, ~3-4min) ---"
    am broadcast -a android.intent.action.MEDIA_MOUNTED \
        --ez read-only false \
        -d "file:///storage/$EXFAT_UUID" 2>/dev/null \
        && log "broadcast OK" \
        || log "WARN: broadcast échoué"
}

# ════════════════════════════════════════════════════════════════════
# DISPATCH
# ════════════════════════════════════════════════════════════════════
case "$STEP" in
    all)
        mount_exfat
        mount_ext4 && do_bind_mounts
        ;;
    early)
        # post-fs-data : filesystem seulement, PAS de am/sm (framework absent)
        mount_ext4 && do_bind_mounts
        ;;
    exfat)
        mount_exfat
        ;;
    ext4)
        mount_ext4
        ;;
    bind)
        do_bind_mounts
        ;;
    notify)
        notify_pm
        ;;
    *)
        log "ERREUR: step inconnu '$STEP'"
        log "  Valides: all|early|exfat|ext4|bind|chown|fix-mbr|notify|unmount"
        ;;
esac

log "=== SD MOUNTER END (step=$STEP) ==="
