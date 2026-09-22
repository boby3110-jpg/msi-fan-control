# msi-fan-control

Fan curve, Cooler Boost, performance mode and charge-limit control for the
**MSI Prestige 13 Evo A12M** on Linux, built on top of
[msi-ec](https://github.com/BeardOverflow/msi-ec). PyQt6 GUI with a tray
icon, a privileged helper that only ever touches a whitelist of EC registers,
and systemd units that restore the settings at boot.

[日本語](#日本語)

> **⚠️ Read this before installing on anything other than an MS-13Q1**
>
> msi-ec exposes `fan_mode`, `cooler_boost`, `shift_mode` and the charge
> threshold through sysfs, and this tool uses those. But msi-ec does **not**
> expose the 6-point fan curve. This tool writes it directly to EC registers
> `0x6a`–`0x6f` (temperatures) and `0x72`–`0x77` (speeds), which I located
> and verified **only on the Prestige 13 Evo A12M (board `MS-13Q1`, EC
> `13Q1EMS1.102` / `.503`)**.
>
> On another model those addresses may be something else entirely. The
> helper therefore refuses raw EC writes unless `board_name` is in
> `SUPPORTED_BOARDS`. See [Adding another model](#adding-another-model)
> before removing that guard.

## What it does

- **6-point fan curve editor** — drag points on a graph or type them in.
  The graph is drawn as steps because that is how the EC applies it (see
  below). The region above the last temperature point is painted red
  because the EC stops following the curve there.
- **Cooler Boost** toggle, **performance mode** (`turbo` / `comfort` /
  `eco`, plus a way back to the factory `0xc0` state that msi-ec cannot
  express), **charge limit** with presets.
- **Live readout** of CPU temperature, reported fan %, mode, measured
  package power, battery % and estimated runtime.
- **Tray icon** with a charge-level ring; close hides to tray; `--tray`
  starts hidden. Tooltip carries all of the above.
- **Automatic Cooler Boost** above a temperature threshold, with a
  separate release threshold to avoid flapping.
- **Boot-time restore** of the curve and performance mode, since the EC
  forgets the curve when power is fully removed.

## Requirements

- MSI Prestige 13 Evo A12M (`MS-13Q1`). The EC firmware on this model is
  not in msi-ec's list; it works with `CONF_G2_3`, so the module is loaded
  with `firmware=13Q2EMS1.110`. A PR to add it upstream is
  [BeardOverflow/msi-ec#819](https://github.com/BeardOverflow/msi-ec/pull/819).
- msi-ec built with DKMS and loaded with `debug=true` (the curve is written
  through its `debug/ec_set` interface).
- Debian 13 / KDE Plasma 6 on Wayland is what this was written against.
  Other distributions should work; the packaging assumptions are
  `apt`, `systemd`, `polkit`, `python3-pyqt6`.

## Install

```bash
sudo bash bootstrap.sh   # deps, msi-ec via DKMS, /etc/modprobe.d entry, EC check
sudo bash install.sh     # GUI, helper, polkit policy, units, icons, autostart
```

`bootstrap.sh` aborts if the board is not `MS-13Q1`, and warns if the EC
firmware doesn't start with `13Q1EMS1` (a BIOS update could move the
registers). `install.sh` is idempotent and registers the GUI to autostart
in the tray for the invoking user.

Settings live in `/etc/msi-fan/` and are not part of this repository.

## Architecture

The GUI runs unprivileged and reads everything from sysfs. Writes go
through `pkexec msi-fan-helper`, which

- accepts raw EC writes only to `0x6a`–`0x6f` and `0x72`–`0x77`,
- validates the curve (ascending temperatures, non-decreasing speeds,
  sane ranges),
- refuses raw writes on a board it doesn't know,
- and uses msi-ec's own sysfs attributes for everything else.

This split is not optional on Wayland: root cannot open a GUI there, so the
privileged part has to be a separate non-GUI process.

`msi-fan-autoboost` is a small daemon that publishes measured package power
(from RAPL `energy_uj`, which is root-only) to `/run/msi-fan/power`, and
optionally turns Cooler Boost on above a threshold.

## What I learned about this EC

None of this is in msi-ec's documentation; all of it was measured.

**The curve is not interpolated.** The EC finds the first temperature point
at or above the current temperature and uses that point's speed. So
`speed[i]` applies for `temp[i-1] < T ≤ temp[i]`, with `speed[0]` below
`temp[0]`. There is roughly 5 °C of hysteresis on the way down.

**Above the last temperature point the curve does not apply.** The EC falls
back to its own behaviour (70 % here) and, worse, **Cooler Boost stops
working**. With the last point at 90 °C, a sustained all-core load sat at
95 °C and Cooler Boost only brought it to 92 °C; with the last point at 95
or 100 °C the same load dropped to 72 °C. The GUI warns if the last point
is below 100 °C. Note the as-found curve ended at 95 °C, so even the stock
setting has this hole.

**Cooler Boost runs the fan above the curve's 100 %.** With the curve
already commanding 100 % under load, enabling Cooler Boost took the package
from 95 °C to 89 °C. It takes about 20 s to kick in, and
`cpu/realtime_fan_speed` does not reflect it — that attribute reports what
the curve commanded, so the only way to see Cooler Boost working is the
temperature.

**Performance mode (`0xd2`) is effective but invisible to RAPL.** Measured
under sustained all-core load:

| mode | 0xd2 | package power | temp | avg clock |
|---|---|---|---|---|
| factory | 0xc0 | 36 W | 85 °C | 2510 MHz |
| turbo | 0xc4 | 36 W | 90 °C | 2521 MHz |
| comfort | 0xc1 | 20 W | 77 °C | 1697 MHz |
| eco | 0xc2 | 10 W | 52 °C | 692 MHz |

`constraint_*_power_limit_uw` stays at 36/64 W throughout, so the EC caps
power outside the RAPL limit registers; you can only see it in measured
energy. `0xc0` is the untouched factory state and is not one of msi-ec's
named modes, so `shift_mode` reads `unknown (192)` until you switch away —
and there is no way back through the sysfs attribute. The helper has a
`shift_reset` command that writes `0xc0` directly.

**`fan_mode` (`0xd4`) does nothing on this model.** `auto`, `silent` and
`advanced` all write correctly but the fan behaves identically under the
same load. `silent` does not stop the fan, contrary to msi-ec's README.

**The charge threshold is held by the EC**, survives reboots and OS
reinstalls, and `charge_control_start_threshold` is purely derived
(`end − 10`). Be aware that UPower applies its own preset (80/75) when you
enable the desktop "preserve battery health" toggle, overwriting whatever
you set here.

## Adding another model

Don't just remove the board check. Instead:

1. Load msi-ec with `debug=true` (and `firmware=` if your EC isn't listed).
2. Read `/sys/devices/platform/msi-ec/debug/ec_dump`. Look for two runs of
   six increasing bytes that look like temperatures (e.g. `32 3c 46 50 5a 5f`
   = 50,60,70,80,90,95) and speeds. On MS-13Q1 they are at `0x6a` and
   `0x72`.
3. Confirm by watching `cpu/realtime_fan_speed` change as the CPU crosses
   those temperatures under load — the `tests/` scripts do exactly this.
4. Only then add the board to `SUPPORTED_BOARDS` in `msi-fan-helper` and,
   if the addresses differ, adjust `TEMP_ADDRS` / `SPEED_ADDRS` in both the
   helper and the GUI.

## Tests

`tests/` holds the scripts used for the measurements above. They need
root, load the CPU, and always restore the previous state on exit.

| script | what it measures |
|---|---|
| `msi-ec-test.sh` | Cooler Boost effect, idle and under load |
| `msi-power-test.sh` | package power / temp / clock per performance mode |
| `msi-fan-mode-test.sh` | the three fan modes at idle |
| `msi-fan-mode-load-test.sh` | the three fan modes under load, aborts at 97 °C |

## License

MIT. See [LICENSE](LICENSE).

---

## 日本語

**MSI Prestige 13 Evo A12M** 用のファン制御ツールです。
[msi-ec](https://github.com/BeardOverflow/msi-ec) の上に、ファンカーブ6点の
編集・Cooler Boost・性能モード・充電上限を扱う PyQt6 GUI（トレイ常駐）、
EC の限られた番地にしか書かない特権ヘルパー、起動時に設定を復元する
systemd ユニットを載せたものです。

> **⚠️ MS-13Q1 以外で使う前に**
>
> ファンカーブは msi-ec が公開していない EC の生レジスタ
> （`0x6a`–`0x6f` 温度点、`0x72`–`0x77` 速度点）へ直接書きます。この番地は
> **Prestige 13 Evo A12M（ベースボード `MS-13Q1`、EC `13Q1EMS1.102` / `.503`）
> でのみ実測で確認**したものです。他機種では別の機能の番地かもしれないので、
> ヘルパーは `board_name` が `SUPPORTED_BOARDS` に無ければ生レジスタへの
> 書き込みを拒否します。外す前に上の "Adding another model" を読んでください。

### 導入

```bash
sudo bash bootstrap.sh   # 依存パッケージ、msi-ec (DKMS)、modprobe.d、EC 照合
sudo bash install.sh     # GUI・ヘルパー・polkit・ユニット・アイコン・自動起動
```

設定値は `/etc/msi-fan/` に保存され、このリポジトリには含まれません。

### この EC について分かったこと（要点）

- **カーブは補間されない。** 現在温度以上で最初に来る温度点の速度がそのまま出る。
  下降時は約5℃のヒステリシス。
- **最終温度点より上はカーブが効かない。** EC の既定動作（70%）に戻り、
  **Cooler Boost も効かなくなる。** 最終点は 100℃ にしておくこと。
- **Cooler Boost はカーブの 100% よりさらに上を回す。** 効き始めまで約20秒。
  `cpu/realtime_fan_speed` には現れないので、温度で判断する。
- **性能モード (`0xd2`) は強力に効くが RAPL の上限値には現れない。**
  実測で 36 W / 20 W / 10 W。`0xc0` は工場出荷状態で msi-ec の一覧に無く、
  一度切り替えると sysfs からは戻せない（ヘルパーの `shift_reset` で戻す）。
- **`fan_mode` (`0xd4`) はこの機種では無効。** 3モードとも同じ挙動。
  `silent` でもファンは止まらない。
- **充電上限は EC が保持**し、再起動や OS 再インストールを跨いで残る。
  デスクトップ環境の「バッテリー保護」トグルを有効にすると UPower が独自の
  プリセット（80/75）で上書きするので注意。

詳細な数値は英語セクションを参照してください。

### ライセンス

MIT
