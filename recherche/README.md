# Research: MSI GS76 Stealth on Linux

*Version française : [README.fr.md](README.fr.md).*

This folder holds the investigation behind the fixes in `correctifs/`: the tools, the raw
measurements and what they show. **None of it is needed to use the fixes.**

> **Warning: these are research tools, not fixes.**
> Most of them need root. The EC tools load `ec_sys` **read-only**
> (`modprobe ec_sys write_support=0`) and stop if `ec_sys` is already loaded with write
> support; they unload it at the end. Some tools change settings for the duration of a
> measurement (fan mode, `shift_mode`, `super_battery`, screen refresh rate, i915 PSR,
> battery cache, USB/PCI devices, services) and restore them at the end, including on
> Ctrl-C. Two of them install system files (`diagnostics-energie/enable-psr.sh`,
> `usb-clavier/install.sh`). They were written for one machine: read a script before
> running it. No EC byte was ever written directly during this research.

## Machine and labels

Measured machine: MSI GS76 Stealth 11UH, BIOS `E17M1IMS.119`, EC firmware
`17M1EMS1.113` (string stored in the EC at `0xA0`, build date 2022-04-22) —
**verified on this machine**.

Every claim below carries one label:

- **verified on this machine**: measured or read on the machine above, with the tools in
  this folder;
- **community source** (named): taken from another project, not measured here.

Community sources:

- YAMDCC GS76 config: Codeberg `Sparronator9999/YAMDCC`, file
  `Configs/MSI-Stealth-GS76-11UG.xml` (same EC firmware);
- msi-ec (`github.com/BeardOverflow/msi-ec`): issues #325 (GS76 11UG) and #848,
  pull requests #143 and #772;
- MControlCenter (MSI Control Center alternative for Linux).

## Contents

| Folder | What |
|---|---|
| `ec/` | EC dump tools, decoder, sysfs/EC comparison, 12 read-only dumps |
| `super-battery/` | Super Battery and power-limit tests (prepared, results not published yet) |
| `diagnostics-energie/` | Idle-power diagnostics (C-states, PSR, refresh rate) and their outputs (`*.txt`) |
| `usb-clavier/` | Kernel quirk for the keyboard RGB controller: **unconfirmed hypothesis** |

## 1. EC register map

Values read in `ec/dumps/` with `ec/decode.py` (**verified on this machine** unless noted).
The dumps were taken in `comfort` shift mode with an 80 % charge limit.

| Address | Meaning | Observed | Label |
|---|---|---|---|
| `0x68` | CPU temperature (°C) | 51–59 | verified (equals the package temperature) |
| `0x6A`–`0x70` | CPU curve temperatures | 52 60 65 70 82 88 100 | bytes verified; meaning community (YAMDCC, MControlCenter, PR #143, #848) |
| `0x71` | CPU fan, current speed (%) | 0, then 60 under load | verified |
| `0x72`–`0x78` | CPU curve speeds (%) | 0 45 50 60 65 70 75 | bytes verified; meaning community (same sources) |
| `0x7A`–`0x7F` | CPU hysteresis (°C, rise − fall) | 7 3 3 3 3 3 | bytes verified; meaning community (YAMDCC) |
| `0x80` | GPU temperature (°C) | 0 | verified (0 while the dGPU sleeps in RTD3) |
| `0x82`–`0x88` | GPU curve temperatures | 55 61 65 71 77 87 100 | bytes verified; meaning community |
| `0x89` | GPU fan, current speed (%) | 0 | verified (dGPU asleep) |
| `0x8A`–`0x90` | GPU curve speeds (%) | 0 50 60 70 75 80 110 | bytes verified; meaning community |
| `0x92`–`0x97` | GPU hysteresis (°C) | 8 3 3 3 3 5 | bytes verified; meaning community (YAMDCC) |
| `0x98` bit 7 | Cooler Boost | bit clear (off) | community (msi-ec, MControlCenter) |
| `0xA0`–`0xBB` | EC firmware version and build date | `17M1EMS1.113`, 2022-04-22 | verified |
| `0xBF` | USB power share | `0x28` | value verified; `0x28` = on, `0x08` = off: community (MControlCenter) |
| `0xC8`–`0xC9` | CPU fan tachometer: period, big-endian | `0x00A6` at 60 % | verified under load |
| `0xCA`–`0xCB` | GPU fan tachometer | 0 | community (PR #772, MControlCenter); not seen spinning |
| `0xCC`–`0xCD` | Third (auxiliary) fan tachometer | 0 | community (issue #325); **not verified under GPU load** |
| `0xD2` | `shift_mode` | `0xC1` | value verified; YAMDCC names `C0` Balanced (absent from msi-ec), `C1` silent/fans capped at 60 % (= msi-ec `comfort`), `C2` max battery 10 W, `C4` high performance: community, not all verified |
| `0xD4` | `fan_mode` | auto `0x0D`, silent `0x1D`, advanced `0x8D` | verified |
| `0xD7` | Charge limit: `0x80` + percent | `0xD0` (80 %) | verified |
| `0xEB` (mask `0x0F`) | Super Battery | `0x0` (off) | verified (see § 4) |

Fan speed in rpm = constant / period: 478000 in PR #772, 480000 in MControlCenter
(**community source**). Measured: period `0xA6` (166) gives about 2880 rpm while msi-ec
reported 60 % (**verified on this machine**, `ec-dump-load.sh`).

Behaviour:

- Switching `fan_mode` between auto, silent and advanced changes only `0xD4`: the curve
  table is identical in all three modes — **verified on this machine**.
- In silent mode the CPU fan stayed at 0 % up to 66 °C — **verified on this machine**.
- In auto mode, under full CPU load, the fan started only after about 35 s, at about
  64 °C — **verified on this machine**. Issue #848 reports that auto mode ignores or caps
  the curve and advanced mode applies it — **community source**.
- `realtime_fan_speed` (msi-ec) is a percentage, not rpm — **verified on this machine**.
- The `msi_wmi_platform` hwmon fans `fan1`–`fan4` always read 0 rpm, which makes
  `sensors` misleading — **verified on this machine**.
- The third fan spins when the GPU reaches about 66 °C; the EC forces the GPU fan to at
  least 70 % when the CPU reaches 76 °C; MSI Center hides the last row of the curve —
  **community source** (issue #325).
- MControlCenter writes raw EC bytes without validating them, sets advanced mode by
  writing `0x8D` to `0xD4`, and re-applies it after resume because the EC resets the
  mode — **community source** (MControlCenter).
- Running `nvidia-smi` wakes the dGPU — **verified on this machine**.

### Open question: 6 or 7 temperatures per curve?

The seven bytes `0x6A`–`0x70` hold 52 60 65 70 82 88 100 and `0x82`–`0x88` hold
55 61 65 71 77 87 100 (**verified on this machine**). Two readings exist:

- **6 thresholds, 7 speeds** (`s0 t1 s1 … t6 s6`; the seventh byte, 100, is left
  untouched): YAMDCC GS76 config, MControlCenter, PR #143 — **community source**. The
  six hysteresis bytes fit this reading: the fall temperatures they give
  (45 57 62 67 79 85 for the CPU) match the YAMDCC default.
- **7 temperature/speed pairs**: issue #848 (firmware `15K1IMS1`, same addresses) —
  **community source**.

**This is not settled.** No write experiment has been made. `decode.py` and the msi-ec
fork (correctif 1) use the 6-threshold model.

## 2. BIOS ACPI bugs and their measured effect

- **Battery status `_BST`**: the method ends with `Sleep (0x64)`, so every uncached
  battery read takes about 114 ms; each poll causes a visible stutter in games —
  **verified on this machine** (`measure-battery.sh`). With the `Sleep` removed (test
  with a full DSDT override, not published) a read takes about 13 ms, the value in
  section 1 of `diag-root.txt` — **verified on this machine**. Published workaround: battery
  cache (correctif 4).
- **Full DSDT override rejected**: it hard-codes firmware memory addresses. Once the
  firmware moved its ACPI regions by `0x10000`; the override then pointed to stale PCI
  windows and the NVMe drive was not found at boot — **verified on this machine**.
  Hence the add-only SSDT (correctif 2), which contains no address.
- **`\_TZ.ETMD` missing**: `\_SB.IETM._OSC` aborts, so Intel DTT settings never reach
  `thermald` — **verified on this machine**. The SSDT defines `ETMD`; the `_OSC` errors
  are gone — **verified on this machine**. Side effect: user space starts about 0.5 s
  earlier and `thermald` can start before `intel_rapl` (correctif 3) — **verified on
  this machine**.
- **PS/2 alias of the I2C touchpad**: the touchpad also appears as a `SynPS/2` mouse;
  setting `PS2M.I2CT = 1` in the SSDT removes the alias — **verified on this machine**.
  The `PS2M._STA` method also sleeps 500 ms at boot; that cannot be removed without
  editing the DSDT — **verified on this machine** (DSDT read).
- **Duplicate `PEG0`/`PEG2`/`PEG3` objects** (`AE_ALREADY_EXISTS`): harmless (`PEG0` is
  the NVMe drive, the GPU is `PEG1`) — **verified on this machine**.
- **No PCIe ASPM declared in the FADT**, so Linux does not manage ASPM itself; but the
  BIOS already enables ASPM L1/L1.2 on most links (`diag-root.txt`, section 2), so
  `pcie_aspm=force` is not needed — **verified on this machine**.
- **EC query `0xC1` every second** with no handler (15 queries in 15 s,
  `diag-root.txt`, section 3) — **verified on this machine**.
- **WMI stubs `WQAK`/`WQAL`/`WMAJ`** declared but not implemented: harmless —
  **verified on this machine**.

## 3. Idle power: PSR, 60 vs 360 Hz, C-states

All figures: CPU package power (RAPL) and package C-state residency at idle, from the
`*.txt` files in `diagnostics-energie/` — **verified on this machine**.

- At 360 Hz the package never goes below PC2 (about 90 % of the time in PC2, 0 % in
  deeper states; `diag-root.txt`, `diag-psr.txt`).
- Not a BIOS limit: MSR `0xE2` allows down to PC10 on every CPU (locked;
  `pkg-limit.txt`).
- Not wakeups, external USB devices, Ethernet, the card reader or services: cutting each
  of them leaves the package in PC2 (`diag-idle2.txt`, `diag-services.txt`,
  `diag-wakeups.txt`).
- The display engine is the cause: screen off, power drops from 2.97 W to 1.84 W and the
  package reaches PC3 83 % of the time (`diag-display.txt`).
- The panel supports PSR1, but MSI's VBT disables it: i915 logs "PSR disabled by flag",
  even with `i915.enable_psr=1` (`diag-psr2.txt`).
- Forcing PSR1 through debugfs (`i915_edp_psr_debug` = `0x3`): at 360 Hz PSR stays off
  ("PSR setup time (330 us) too long"); at 60 Hz it turns on (`diag-psr.txt`).

| Refresh rate | PSR | Package power | Deepest state reached |
|---|---|---|---|
| 360 Hz | off | 2.92 W | PC2 91 % |
| 360 Hz | forced | 2.87 W | PC2 91 % |
| 60 Hz | off | 1.73 W | PC3 80 % |
| 60 Hz | forced, active | 1.45 W | PC3 84 % |

Source: `diag-psr.txt` (20 s per step). Published fix: PSR forced at boot and 60 Hz on
battery (correctif 5).

Caveats on the raw outputs: the 60 Hz step of `diag-idle.txt` is not reliable (the script
uses `hyprctl keyword monitor`, which Hyprland 0.56 silently ignores; use
`diag-psr.txt`); in `diag-display.txt`, the screen-state lines are empty because of a
quoting error in the script (Python `SyntaxError` kept in the output), the measurements
are not affected.

## 4. Super Battery and power limits

- The EC enforces the CPU power limits through `intel-rapl-mmio:0`; the MSR limits
  (`intel-rapl:0`, 95/120 W) stay inert — **verified on this machine**.
- PL1/PL2 set by the EC per `shift_mode`: `comfort` 45/64 W, `eco` 10/10 W, `turbo`
  70/109 W — **verified on this machine**. YAMDCC describes `C2` as a 10 W max-battery
  mode — **community source**.
- Entering `eco` makes the EC set `super_battery` (`0xEB`, mask `0x0F`) by itself;
  leaving `eco` clears it. On the GS76, "Eco" already **is** MSI's Super Battery —
  **verified on this machine**.
- Once, in `comfort` before any change (state at boot?), MMIO read 90/109 W until
  `comfort` was written again — **verified on this machine**, cause unknown.

`sb-ec.sh` (on AC: EC dump and MMIO limits for 8 combinations of `shift_mode` and
`super_battery`) and `sb-batterie.sh` (on battery: average power in 5 states) are ready;
their results are not published yet.

## 5. USB keyboard quirk: unconfirmed hypothesis

The keyboard RGB controller (SteelSeries KLC, USB `1038:113a`) sometimes fails to
enumerate at boot: `can't set config #1, error -71`, or `device not accepting address,
error -71` (keyboard lighting dead) — **verified on this machine**:

- -71 seen on 1 boot out of 6 in one series; over 46 boots in the journal, 5 boots with
  the "set config" variant and 3 with the total failure;
- in an analysis of 40 boots, every total failure came after a warm reboot (3 of 17
  reboots, 0 of 23 boots from power-off); a port power-cycle does not recover it, a full
  power-off does.

Lead: the controller is USB 2.01 and announces USB2 LPM (BOS USB 2.0 extension,
`bmAttributes 0x2`), and Linux enables `usb2_hardware_lpm` on it — **verified on this
machine**. Hypothesis: L1 LPM during enumeration causes the protocol error. Test:
kernel parameter `usbcore.quirks=1038:113a:k` (`USB_QUIRK_NO_LPM`, this device only);
in the kernel, `NO_LPM` makes `usb_device_supports_lpm()` return 0 — **verified on this
machine** (kernel 7.3 source).

**Not confirmed**: it needs many warm reboots without error before any conclusion. That
is why it is not a fix.

## Running the tools

Run them with `sudo` **from your own account** (not from a root shell): the scripts find
your user through `SUDO_USER` to give you the output files and, for the screen tests, to
reach your Hyprland session. Outputs are written **in the current directory**:

    mkdir -p ~/mesures-gs76 && cd ~/mesures-gs76
    sudo bash /path/to/recherche/ec/ec-dump.sh

| Tool | Root | Effect | Output |
|---|---|---|---|
| `ec/ec-dump.sh` | yes | EC read-only; switches `fan_mode` auto/silent/advanced, then restores it | `./dumps/*.bin` |
| `ec/ec-dump-load.sh` | yes | EC read-only; fan in auto, loads all cores 60 s, then restores the mode | `./dumps/*-charge-*.bin` |
| `ec/decode.py` | no | decodes dumps: `python3 -I ec/decode.py ec/dumps/*.bin` | screen |
| `ec/verifier-sysfs.sh` | yes (live) / no (with a dump) | compares the msi-ec fork attributes with an EC dump; `--surveiller N` samples GPU and third fan every 10 s; `SEUIL_CHARGE` = expected limit (80) | screen |
| `super-battery/sb-ec.sh` | yes, on AC | EC read-only; switches `shift_mode`/`super_battery`, restores `comfort` + off | `./dumps/`, `./resultats-ec.txt` |
| `super-battery/sb-batterie.sh` | yes, on battery | battery cache at 1 s during the test, then restored; `MESURE` = seconds per state (120) | `./resultats-batterie.txt` |
| `diagnostics-energie/diag-root.sh` | yes | read-only (battery cache briefly at 0) | `./diag-root.txt` |
| `diagnostics-energie/diag-idle.sh` | yes | screen 360 → 60 → 360 Hz | `./diag-idle.txt` |
| `diagnostics-energie/diag-idle2.sh` | yes | forces PSR, cuts external USB, Ethernet and card reader for about 40 s | `./diag-idle2.txt` |
| `diagnostics-energie/diag-wakeups.sh` | yes | read-only | `./diag-wakeups.txt` |
| `diagnostics-energie/diag-services.sh` | yes | stops then restarts `voxtype` (user service), `nvidia-powerd`, `thermald` | `./diag-services.txt` |
| `diagnostics-energie/diag-display.sh` | yes | KMS debug, screen off for 25 s | `./diag-display.txt` |
| `diagnostics-energie/diag-psr.sh` | yes | forces PSR1, screen 360/60 Hz, restored | `./diag-psr.txt` |
| `diagnostics-energie/diag-psr2.sh` | yes | KMS debug, screen 360 → 60 Hz | `./diag-psr2.txt` |
| `diagnostics-energie/measure-battery.sh` | yes | times 5 uncached battery reads | screen |
| `diagnostics-energie/read-pkg-limit.sh` | yes | reads MSR `0xE2` (loads `msr`) | `./pkg-limit.txt` |
| `diagnostics-energie/enable-psr.sh` | yes | **installs** `i915-psr-force.service` (working version of correctif 5) | system |
| `usb-clavier/install.sh` / `uninstall.sh` | yes | **adds/removes** the quirk in `/etc/limine-entry-tool.d/` (Limine only) | system |
| `usb-clavier/verifier.sh` | no | quirk active? -71 errors this boot? | screen |

The screen tests assume the GS76 panel (`eDP-2`, 1920x1080 at 360/60 Hz) and a Hyprland
session. `diag-idle2.sh` uses the GS76 PCI addresses of the Ethernet controller and card
reader.

## About the published outputs

The `*.txt` files and the dumps were reviewed before publication. Changes: output paths
reduced to the file name; external USB mouse and keyboard models replaced by a generic
label (`diag-idle2.txt`); user application names replaced by `[application utilisateur]`
in `diag-wakeups.txt`; PCI addresses shortened to `bus:device.function` in
`diag-root.txt`. The EC dumps contain no serial number; their only text is the EC
firmware version and build date. The measurements themselves are unchanged.
