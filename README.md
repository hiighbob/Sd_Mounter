# SD Mounter v1.0

Magisk module pour SM-A530W · Android 9 · Magisk 30100

## Ce que fait ce module

1. **Monte mmcblk1p1** (exFAT, UUID 6603-7A19) → `/mnt/media_rw/6603-7A19`
2. **Monte mmcblk1p2** (ext4, ~20GB) → `/mnt/ext4sd`
3. **Restaure les bind-mounts** pour chaque app dont les données sont sur ext4 :
   - `/mnt/ext4sd/app/XXX` → `/data/app/XXX`
   - `/mnt/ext4sd/data/XXX` → `/data/data/XXX`
4. **WebUI MMRL** pour contrôler et monitorer les montages

## Structure ext4 attendue

```
/mnt/ext4sd/
  app/    — APKs déplacées (com.termux-XXX, com.zldev.iptvlisteditor-XXX, etc.)
  data/   — Données apps (com.termux, xyz.goodcloud.glinet, etc.)
```

## Installation

1. Flasher le ZIP dans MMRL / Magisk
2. Reboot
3. Ouvrir MMRL → SD Mounter → vérifier l'onglet Statut

## Logs

```
/data/adb/modules/sd-mounter/logs/
  mount.log         — moteur principal sd_mount.sh
  service.log       — service.sh (timing boot)
  post-fs-data.log  — post-fs-data.sh (création mount points)
```

## Commande manuelle

```sh
# Depuis Termux (root) ou adb shell
sh /data/adb/modules/sd-mounter/scripts/sd_mount.sh all
sh /data/adb/modules/sd-mounter/scripts/sd_mount.sh exfat
sh /data/adb/modules/sd-mounter/scripts/sd_mount.sh ext4
sh /data/adb/modules/sd-mounter/scripts/sd_mount.sh bind
sh /data/adb/modules/sd-mounter/scripts/sd_mount.sh unmount
```
