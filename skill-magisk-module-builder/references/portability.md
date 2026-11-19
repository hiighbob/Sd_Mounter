# Portability Guide — From SM-A530W to Public Release

> Lire uniquement si l'utilisateur demande explicitement une release publique.

## Variables à paramétrer

| Variable hardcodée | Valeur SM-A530W | Remplacer par |
|---|---|---|
| `vol-id public:179,33` | mmcblk1p1 major:minor | `sm list-volumes all \| grep -v internal \| awk '{print $1}'` |
| UUID `6603-7A19` | Carte SD spécifique | Détection dynamique via `blkid` ou `sm list-volumes` |
| UUID ext4 `6c65f787-...` | Partition ext4 spécifique | Détecter ou configurer en customize.sh |
| `/dev/block/mmcblk1p1/p2` | Noms de bloc device | `readlink -f /dev/block/by-name/sdcard` ou détection |
| `minMagisk=26000` | OK pour la plupart | Laisser tel quel |

## customize.sh — détection au flash
```sh
# Détecter la partition SD au flash et stocker dans config
SD_UUID=$(sm list-volumes all 2>/dev/null | grep -v internal | awk '{print $3}' | head -1)
if [ -n "$SD_UUID" ]; then
    echo "SD_UUID=$SD_UUID" > "$MODPATH/config.prop"
    ui_print "- Carte SD détectée: $SD_UUID"
else
    ui_print "! Attention: carte SD non détectée"
fi
```

## module.prop pour release publique
```properties
id=<module-id>
name=<Human Name>
version=v1.0
versionCode=1
author=<github-username>
description=<description>
minMagisk=26000
updateJson=https://raw.githubusercontent.com/<user>/<repo>/main/update.json
```

## update.json
```json
{
  "version": "v1.0",
  "versionCode": 1,
  "zipUrl": "https://github.com/<user>/<repo>/releases/download/v1.0/<module>.zip",
  "changelog": "https://raw.githubusercontent.com/<user>/<repo>/main/CHANGELOG.md"
}
```

## SELinux — passage permissive → enforcing
Partout où le module utilise `chcon`, documenter et planifier :
- Remplacer `chcon -R u:object_r:app_data_file:s0` par `restorecon -RF`
- Tester avec `setenforce 1` avant release
