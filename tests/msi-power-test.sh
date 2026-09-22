#!/bin/bash
# 性能モードが実際に効いているかを、負荷時の消費電力で判定する (要 root)
[ "$(id -u)" -eq 0 ] || { echo "sudo で実行してください"; exit 1; }
exec python3 - "$@" <<'PY'
import time, glob, subprocess, os

R = "/sys/class/powercap/intel-rapl/intel-rapl:0"
D = "/sys/devices/platform/msi-ec"

def rd(p, d=None):
    try:
        return open(p).read().strip()
    except OSError:
        return d

def energy():
    return int(rd(f"{R}/energy_uj", "0"))

MAXE = int(rd(f"{R}/max_energy_range_uj", "0"))

def freqs():
    v = [int(rd(f, "0")) for f in glob.glob(
        "/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    return sum(v) / len(v) / 1000 if v else 0

print(f"性能モード : {rd(f'{D}/shift_mode')}")
print(f"PL1 / PL2  : {int(rd(f'{R}/constraint_0_power_limit_uw'))/1e6:.1f} W"
      f" / {int(rd(f'{R}/constraint_1_power_limit_uw'))/1e6:.1f} W")
print(f"カーブ     : 0x71 報告 {rd(f'{D}/cpu/realtime_fan_speed')}%  "
      f"温度 {rd(f'{D}/cpu/realtime_temperature')}C")
print()

n = os.cpu_count()
print(f"→ {n} スレッドで 60 秒負荷をかけます")
procs = [subprocess.Popen(["yes"], stdout=subprocess.DEVNULL) for _ in range(n)]
try:
    e0, t0 = energy(), time.monotonic()
    time.sleep(5)                      # 立ち上がりは捨てる
    print(f"{'経過':>6} {'消費電力':>10} {'温度':>7} {'平均クロック':>13} {'報告回転':>9}")
    samples = []
    for i in range(11):
        e0, t0 = energy(), time.monotonic()
        time.sleep(5)
        e1, t1 = energy(), time.monotonic()
        de = (e1 - e0) if e1 >= e0 else (e1 + MAXE - e0)
        w = de / 1e6 / (t1 - t0)
        temp = rd(f"{D}/cpu/realtime_temperature")
        fan = rd(f"{D}/cpu/realtime_fan_speed")
        mhz = freqs()
        samples.append((w, int(temp), mhz))
        print(f"{(i+1)*5:5d}s {w:9.1f} W {temp:>5} C {mhz:10.0f} MHz {fan:>7} %")
finally:
    for p in procs:
        p.terminate()

if samples:
    tail = samples[len(samples)//2:]      # 後半のみ＝定常状態
    aw = sum(s[0] for s in tail)/len(tail)
    at = sum(s[1] for s in tail)/len(tail)
    am = sum(s[2] for s in tail)/len(tail)
    print(f"\n定常状態の平均: {aw:.1f} W / {at:.0f} C / {am:.0f} MHz")
PY
