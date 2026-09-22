#!/bin/bash
# msi-ec cooler_boost 効果検証 (要 root)
D=/sys/devices/platform/msi-ec
raw() { echo 98 > $D/debug/ec_get; cat $D/debug/ec_get; }
st()  { printf "%s  0x98=%s  attr=%-3s fan=%3s%%  temp=%2s C\n" \
        "$(date +%T)" "$(raw)" "$(cat $D/cooler_boost)" \
        "$(cat $D/cpu/realtime_fan_speed)" "$(cat $D/cpu/realtime_temperature)"; }

[ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください"; exit 1; }

echo "───── 段階1: 無負荷でビットが定着するか ─────"
echo off > $D/cooler_boost; sleep 1
echo "[boost off]"; st
echo on  > $D/cooler_boost; sleep 1
echo "[boost on ]"; st
echo "  ↑ 0x98 の最上位ビットが立てば 06→86 になるはず"
for i in 1 2 3; do sleep 2; st; done
echo off > $D/cooler_boost; sleep 1

load_start() { for c in $(seq $(nproc)); do yes >/dev/null & done; }
load_stop()  { pkill -x yes; }

echo; echo "───── 段階2: 高負荷 + boost OFF (40秒) ─────"
load_start; trap load_stop EXIT
for i in $(seq 8); do sleep 5; st; done

echo; echo "───── 段階3: 高負荷のまま boost ON (40秒) ─────"
echo on > $D/cooler_boost
for i in $(seq 8); do sleep 5; st; done

load_stop; trap - EXIT
echo off > $D/cooler_boost
echo; echo "→ 負荷停止・boost off に戻しました"
