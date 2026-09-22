#!/bin/bash
# MSI ファン制御 GUI インストーラ (要 root)
set -e
[ "$(id -u)" -eq 0 ] || { echo "sudo bash install.sh で実行してください"; exit 1; }
S="$(cd "$(dirname "$0")" && pwd)"

echo "→ 依存関係を確認"
missing=""
python3 -c "import PyQt6" 2>/dev/null || missing="$missing python3-pyqt6"
command -v pkexec >/dev/null || missing="$missing pkexec"
[ -n "$missing" ] && { echo "未インストール:$missing"; echo "  sudo apt install$missing"; exit 1; }

echo "→ msi-ec が debug モードで動作しているか確認"
[ -e /sys/devices/platform/msi-ec/debug/ec_set ] || {
  echo "  /sys/devices/platform/msi-ec/debug/ec_set がありません"
  echo "  /etc/modprobe.d/msi-ec.conf に debug=true があるか確認してください"; exit 1; }

echo "→ ファイルを配置"
install -m 755 "$S/msi-fan-helper" /usr/local/bin/msi-fan-helper
install -m 755 "$S/msi-fan-gui"    /usr/local/bin/msi-fan-gui
install -m 755 "$S/msi-fan-autoboost" /usr/local/bin/msi-fan-autoboost
install -m 644 "$S/jp.local.msifan.policy" /usr/share/polkit-1/actions/jp.local.msifan.policy
install -m 644 "$S/msi-fan.desktop" /usr/share/applications/msi-fan.desktop
# 旧 SVG アイコンを撤去（scalable が PNG より優先されてしまうため）
rm -f /usr/share/icons/hicolor/scalable/apps/msi-fan.svg
for sz in 16 22 24 32 48 64 128 256 512; do
  install -D -m 644 "$S/icons/msi-fan-${sz}.png" \
          "/usr/share/icons/hicolor/${sz}x${sz}/apps/msi-fan.png"
done
install -m 644 "$S/msi-fan-restore.service"  /etc/systemd/system/msi-fan-restore.service
install -m 644 "$S/msi-fan-autoboost.service" /etc/systemd/system/msi-fan-autoboost.service

echo "→ systemd を更新"
systemctl daemon-reload
systemctl enable msi-fan-restore.service >/dev/null
# 監視デーモンは常駐させる（実測電力の公開を担うため）。
# 自動 Cooler Boost を実際に作動させるかは GUI の設定で決まる。
systemctl enable msi-fan-autoboost.service >/dev/null
systemctl restart msi-fan-autoboost.service
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
xdg-icon-resource forceupdate 2>/dev/null || true

echo
echo "完了しました。"
echo "  アプリメニューの「MSI ファン制御」、または端末で msi-fan-gui"
