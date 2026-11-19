#!/system/bin/sh
# customize.sh — SD Mounter v1.1
ui_print "- SD Mounter v1.1"
ui_print "- Cible: SM-A530W / Android 9 / Magisk"
ui_print "- Création config par défaut..."

# Config persistée — lue par service.sh et WebUI
cat > "$MODPATH/webroot/config_state.json" <<'EOF'
{
  "auto_run_on_boot":   true,
  "boot_delay_sec":     15,
  "media_scan_on_boot": false,
  "log_verbose":        true
}
EOF

ui_print "- Config écrite dans webroot/"
set_perm_recursive "$MODPATH/scripts" root root 0755 0755
set_perm_recursive "$MODPATH/logs"    root root 0755 0644
ui_print "- Redémarre pour activer le module."
