#!/bin/bash
# 指定したファンモードを高負荷で評価する (要 root)
#   使い方: sudo bash msi-fan-mode-load-test.sh {auto|silent|advanced}
# 97℃ に達した時点で即座に中断し auto に戻す。
[ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください"; exit 1; }
M=${1:?モードを指定してください (auto/silent/advanced)}
D=/sys/devices/platform/msi-ec

cleanup() { pkill -x yes 2>/dev/null; echo auto > $D/fan_mode; echo "→ 負荷停止・auto に戻しました"; }
trap cleanup EXIT

echo "$M" > $D/fan_mode
sleep 1
echo "モード: $(cat $D/fan_mode)   0xd4: $(echo d4 > $D/debug/ec_get; cat $D/debug/ec_get)"
echo "→ $(nproc) スレッドで負荷開始（97℃ で自動中断）"
echo
for i in $(seq $(nproc)); do yes >/dev/null & done

for i in $(seq 20); do
  sleep 3
  t=$(cat $D/cpu/realtime_temperature)
  f=$(cat $D/cpu/realtime_fan_speed)
  printf "  %s  temp=%2s C  報告回転=%3s %%\n" "$(date +%T)" "$t" "$f"
  if [ "$t" -ge 97 ] 2>/dev/null; then
    echo "  !! 97℃ に達したため中断します"
    exit 1
  fi
done
