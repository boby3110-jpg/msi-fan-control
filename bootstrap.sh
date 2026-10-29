#!/bin/bash
# クリーンインストール直後の下ごしらえ（要 root）
#
#   sudo bash bootstrap.sh             → 続けて sudo bash install.sh
#   bash bootstrap.sh --dry-run        何をするかだけ表示（root 不要）
#
# 対応: Debian 系（apt）/ openSUSE 系（zypper）。
# 動作確認済みは Debian 13。openSUSE Tumbleweed は未検証。
#
# 本機 (MSI Prestige 13 Evo A12M / EC 13Q1EMS1) は msi-ec の対応機種
# 一覧に無いため、近縁機種の設定 CONF_G2_3 を firmware= で強制適用する。
# レジスタ一致は実測で確認済み（詳細は README）。
set -e

FORCE_FW=13Q2EMS1.110       # CONF_G2_3 を引くための代表ファーム名
EXPECT_EC=13Q1EMS1          # 本機の EC。BIOS 更新で変わったら要再検証

DRY=0; [ "$1" = "--dry-run" ] && DRY=1
run() { if [ "$DRY" = 1 ]; then echo "    [dry-run] $*"; else "$@"; fi; }

# テスト用に差し替えられるようにしておく（--dry-run と組み合わせて使う）
OS_RELEASE=${OS_RELEASE:-/etc/os-release}
KREL=${KREL:-$(uname -r)}

[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください"; exit 1; }

echo "→ 機種を確認"
MODEL=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)
if [ "$MODEL" != "MS-13Q1" ]; then
  echo "  ベースボードが MS-13Q1 ではありません ($MODEL)。"
  echo "  このツールは EC の生レジスタに書くため、未検証の機種では使えません。中止します。"
  exit 1
fi

echo "→ ディストリビューションを判定"
# shellcheck disable=SC1090
. "$OS_RELEASE"
case " ${ID:-} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) FAMILY=debian ;;
  *suse*)                    FAMILY=suse ;;
  *) echo "  未対応のディストリビューションです: ${PRETTY_NAME:-$ID}"
     echo "  必要なもの: dkms・現行カーネルのヘッダ・gcc/make・git・PyQt6・pkexec"
     exit 1 ;;
esac
echo "  ${PRETTY_NAME:-$ID} → $FAMILY 系"

echo "→ Secure Boot を確認"
if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
  echo "  ⚠️ Secure Boot が有効です。DKMS で作ったモジュールは署名と MOK 登録が"
  echo "     無いと読み込まれません。ディストリの手順で MOK を登録してから続けてください。"
else
  echo "  無効（署名は不要）"
fi

echo "→ 依存パッケージを導入"
case "$FAMILY" in
  debian)
    # Debian はメタパッケージで今後のカーネル更新にも追随させる
    if [ "${ID:-}" = debian ]; then HDR=linux-headers-amd64; else HDR=linux-headers-generic; fi
    run apt-get install -y dkms "$HDR" build-essential git python3-pyqt6 pkexec
    ;;
  suse)
    # 6.11.5-1-default → default。kernel-<flavor>-devel が DKMS のビルドに要る
    FLAVOR=${KREL##*-}
    # PyQt6 は Python のバージョン付きで提供される（python313-PyQt6 等）
    command -v python3 >/dev/null || run zypper --non-interactive install python3
    PYV=$(python3 -c 'import sys; print(f"{sys.version_info[0]}{sys.version_info[1]}")' 2>/dev/null || echo 3)
    # pkexec はパッケージ分割の有無が版で違うので、ファイル名で指定する
    run zypper --non-interactive install dkms "kernel-${FLAVOR}-devel" gcc make git \
        "python${PYV}-PyQt6" /usr/bin/pkexec
    # ローリングリリースでカーネル更新が頻繁なため、起動時の自動再ビルドを確実に有効化
    if systemctl list-unit-files dkms.service >/dev/null 2>&1; then
      run systemctl enable dkms.service
    fi
    ;;
esac

echo "→ msi-ec（DKMS 版）を導入"
# ⚠️ カーネル同梱（in-tree）の msi-ec は firmware= も debug 属性も持たない。
# 「モジュールがあるか」で判定すると、クリーンインストール直後に in-tree 版を
# 見つけて導入済みと誤認する。必要な機能（firmware パラメータ）の有無で判定する。
if /sbin/modinfo -F parm msi-ec 2>/dev/null | grep -q '^firmware:'; then
  echo "  導入済み（firmware= に対応した版が見つかった）。スキップ"
else
  echo "  未導入、または機能の足りない in-tree 版しか無い → DKMS で導入"
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] git clone https://github.com/BeardOverflow/msi-ec.git && make dkms-install"
  else
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    git clone --depth 1 https://github.com/BeardOverflow/msi-ec.git "$WORK/msi-ec"
    make -C "$WORK/msi-ec" dkms-install     # /etc/modules-load.d/msi-ec.conf も生成される
  fi
fi

echo "→ firmware= と debug= を設定"
if [ "$DRY" = 1 ]; then
  echo "    [dry-run] /etc/modprobe.d/msi-ec.conf ← options msi-ec firmware=$FORCE_FW debug=true"
else
  printf 'options msi-ec firmware=%s debug=true\n' "$FORCE_FW" > /etc/modprobe.d/msi-ec.conf
fi

echo "→ 読み込み直し"
run modprobe -r msi-ec 2>/dev/null || true
run modprobe msi-ec

[ "$DRY" = 1 ] && { echo; echo "dry-run のため以降の検証は省略"; exit 0; }

echo "→ 読み込まれた版を検証"
if [ ! -e /sys/devices/platform/msi-ec/debug/ec_set ]; then
  echo "  !! debug/ec_set がありません。DKMS 版ではなく in-tree 版が読み込まれています。"
  echo "     確認: modinfo -n msi-ec  （/updates/ 配下であるべき）"
  exit 1
fi
echo "  DKMS 版で稼働中: $(/sbin/modinfo -n msi-ec)"

echo "→ EC ファームを照合"
FW=$(cat /sys/devices/platform/msi-ec/fw_version 2>/dev/null || echo "")
echo "  実機の EC: ${FW:-取得失敗}"
case "$FW" in
  ${EXPECT_EC}*) echo "  想定どおり。CONF_G2_3 の適合は検証済み" ;;
  "")            echo "  !! 読み取れません"; exit 1 ;;
  *)             echo "  !! 想定 ($EXPECT_EC*) と異なります。レジスタ配置が変わっている恐れがあるため、"
                 echo "     README の \"Adding another model\" の手順で番地を確認し直してください。" ;;
esac

echo
echo "完了。続けて次を実行してください:"
echo "  sudo bash $(dirname "$0")/install.sh"
