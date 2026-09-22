#!/bin/bash
# ファンモード 3 種の挙動をアイドル時に観察する (要 root)
# 負荷はかけないので安全。終了時は必ず auto に戻す。
[ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください"; exit 1; }
D=/sys/devices/platform/msi-ec
orig=$(cat $D/fan_mode)
restore() { echo auto > $D/fan_mode; echo; echo "→ auto に戻しました (開始時: $orig)"; }
trap restore EXIT

raw() { echo d4 > $D/debug/ec_get; cat $D/debug/ec_get; }

for m in auto silent advanced; do
  echo "───── $m ─────"
  echo $m > $D/fan_mode
  sleep 2
  echo "  0xd4 生値 = $(raw)   fan_mode = $(cat $D/fan_mode)"
  for i in 1 2 3 4 5 6; do
    t=$(cat $D/cpu/realtime_temperature)
    f=$(cat $D/cpu/realtime_fan_speed)
    printf "  %s  temp=%2s C  報告回転=%3s %%\n" "$(date +%T)" "$t" "$f"
    if [ "$t" -ge 90 ] 2>/dev/null; then
      echo "  !! 90℃ を超えたため中止します"; exit 1
    fi
    sleep 3
  done
  echo
done
