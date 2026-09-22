#!/bin/bash
# クリーンインストール直後の下ごしらえ（要 root）
#
#   sudo bash bootstrap.sh   →  sudo bash install.sh
#
# 本機 (MSI Prestige 13 Evo A12M / EC 13Q1EMS1.503) は msi-ec の対応機種
# 一覧に無いため、近縁機種の設定 CONF_G2_3 を firmware= で強制適用する。
# レジスタ一致は実測で確認済み（詳細は README の「EC について分かったこと」）。
set -e

FORCE_FW=13Q2EMS1.110       # CONF_G2_3 を引くための代表ファーム名
EXPECT_EC=13Q1EMS1          # 本機の EC。BIOS 更新で変わったら要再検証

[ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください"; exit 1; }

echo "→ 機種を確認"
MODEL=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)
if [ "$MODEL" != "MS-13Q1" ]; then
  echo "  警告: ベースボードが MS-13Q1 ではありません ($MODEL)"
  echo "  このスクリプトは Prestige 13 Evo A12M 専用です。中止します。"
  exit 1
fi

echo "→ 依存パッケージを導入"
apt-get install -y dkms linux-headers-amd64 build-essential git \
                   python3-pyqt6 pkexec

echo "→ msi-ec を DKMS で導入"
if [ -e /sys/module/msi_ec ] || modinfo msi-ec >/dev/null 2>&1; then
  echo "  既に導入済み。スキップ"
else
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  git clone --depth 1 https://github.com/BeardOverflow/msi-ec.git "$WORK/msi-ec"
  make -C "$WORK/msi-ec" dkms-install     # /etc/modules-load.d/msi-ec.conf も生成される
fi

echo "→ firmware= と debug= を設定"
printf 'options msi-ec firmware=%s debug=true\n' "$FORCE_FW" > /etc/modprobe.d/msi-ec.conf

echo "→ 読み込み直し"
modprobe -r msi-ec 2>/dev/null || true
modprobe msi-ec

echo "→ EC ファームを照合"
FW=$(cat /sys/devices/platform/msi-ec/fw_version 2>/dev/null || echo "")
echo "  実機の EC: ${FW:-取得失敗}"
case "$FW" in
  ${EXPECT_EC}*) echo "  想定どおり。CONF_G2_3 の適合は検証済み" ;;
  "")            echo "  !! 読み取れません。msi-ec が読み込めていない可能性があります"; exit 1 ;;
  *)             echo "  !! 想定 ($EXPECT_EC*) と異なります。"
                 echo "     レジスタ配置が変わっている恐れがあるため、"
                 echo "     README の検証手順に従い、ec_dump で番地の配置を確認し直してください。" ;;
esac

echo
echo "完了。続けて次を実行してください:"
echo "  sudo bash $(dirname "$0")/install.sh"
