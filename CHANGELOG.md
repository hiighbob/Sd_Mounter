# SD Mounter — Changelog

## v1.4 (2026-06-14)
- WebUI rebuildé sur le template SKILL V5 (design tokens, badges, sticky header/tabs)
- colorize() aligné sur classes .ok/.warn/.err/.dim (vs .ok-line ancienne version)
- Toast position corrigée : bottom:90px (au-dessus nav bar)
- Boutons step via data-step + addEventListener (plus d'onclick= inline)
- Tab switching via addEventListener (SKILL pattern)
- Scripts shell inchangés (corrects depuis v1.3)

 (2026-06-14)
- **BUG 1 fix** : sd_probe.sh — comptage bind-mounts corrigé (grep ^/dev/block/mmcblk1p2)
- **BUG 1 bis fix** : do_unmount() — même correctif, démontage WebUI fonctionnel
- **BUG 2 fix** : bind-mount /storage/6603-7A19 → /mnt/media_rw/6603-7A19
  exFAT désormais visible dans FX, MiXplorer et toutes les apps SAF
- WebUI Status : 2 nouvelles cartes (/storage/ bind, ext4 libre)

 (2026-06-14)

### Fixes
- **sd_probe.sh** : toutes les vérifications de mount remplacées par `cat /proc/1/mounts`
  au lieu de la commande `mount`. La commande `mount` lit le namespace du process
  MMRL/WebView — pas le namespace système. Les bind-mounts créés en post-fs-data
  vivaient dans le namespace de PID 1 et étaient invisibles → Status affichait 0/12
  et 0/9 même avec tous les bind-mounts actifs. Corrigé.
- **sd_mount.sh `do_unmount()`** : même correction namespace → le bouton "Tout démonter"
  du WebUI trouve maintenant correctement les bind-mounts à démonter.

### Nouveautés
- **Bouton "Corriger UIDs" (chown)** : corrige le "Permission Denied" sur les données
  d'apps stockées sur ext4 (ex. Termux Bootstrap Error). Récupère l'UID courant via
  `pm dump <pkg>` et applique `chown -R` dynamiquement. À lancer une fois après l'install
  ou après réinstallation d'une app.
- **Bouton "Exposer SD exFAT"** : transfère le contrôle de mmcblk1p1 de notre mount
  sdfat vers vold (`sm mount public:179,33`), rendant la SD visible dans le gestionnaire
  de fichiers / galerie. Les bind-mounts ext4 (mmcblk1p2) restent intacts.
- **sd_mount.sh step `exfat-expose`** : implémentation shell du toggle exFAT.
- **sd_mount.sh step `chown`** : correction UIDs dynamique pour tous les packages dans
  /mnt/ext4sd/data/.

### UX
- Onglet **Debug supprimé** (option D) — le diagnostic ksu est rarement nécessaire
  en production. Les logs système restent accessibles sur disque.
- Onglet **Logs simplifié** (option B) : affiche uniquement `mount.log` (le plus utile),
  sans sub-tabs. `service.log` et `post-fs-data.log` restent sur disque :
  `/data/adb/modules/sd-mounter/logs/`.
- Version bump : v1.1 → v1.2 dans topbar et module.prop.

---

## v1.1 (2026-06-14)

### Fix principal
- **Timing /data/app** : les bind-mounts APK sont maintenant appliqués dans
  `post-fs-data.sh` (step `early`) **avant** le scan PackageManager/Zygote.
  En v1.0, les bind-mounts arrivaient dans `service.sh` (+36s après boot),
  après que PM avait déjà scanné /data/app → apps invisibles dans le launcher.
  Confirmé : 12/12 app OK + 9/9 data OK en ~1 seconde en post-fs-data.

### Découverte secondaire
- `notify_pm` (broadcast MEDIA_MOUNTED) déclenche un scan média SD complet de ~3-4min
  sur ce device. Sans rapport avec le fix /data/app. Découplé en step `notify`,
  désactivé par défaut (`media_scan_on_boot: false`), bouton manuel dans le WebUI.

### Architecture
- `service.sh` : step `all` devient filet de sécurité idempotent (SKIP si déjà monté).
  Garde l'exFAT (nécessite `sm`, pas dispo en post-fs-data).

---

## v1.0 (2026-06-13)

- Version initiale
- Montage exFAT (mmcblk1p1 → /mnt/media_rw/6603-7A19 via sdfat)
- Montage ext4 (mmcblk1p2 → /mnt/ext4sd avec seclabel)
- Bind-mounts /data/app/* et /data/data/* depuis ext4sd
- WebUI : Status / Actions / Config / Logs / Debug
- Idempotence : SKIP si déjà monté

## v1.5
- sd_mount.sh : adaptatif exFAT — détecte si vold a monté nativement (MBR fix)
  ou fait le sdfat + /storage bind (mode fallback HiddenMount)
- sd_mount.sh : nouveau step `fix-mbr` — change type MBR p1 0x07→0x0c
  avec backup automatique dans /sdcard/Download/. Reboot requis après.
- sd_probe.sh : nouveau output `mbr_fix` (applied/pending) et `exfat_source`
  (vold/sdfat/none)
- WebUI : Status — 2 nouvelles lignes (MBR fix status + source exFAT)
- WebUI : Actions — bouton "Fix MBR + Reboot" avec confirmation
- Supprimé : step exfat-expose (obsolète, remplacé par fix-mbr)
