# MSI GS76 Stealth on Linux

*Version française : [README.fr.md](README.fr.md).*

Fixes for the **MSI GS76 Stealth 11UH** on Arch Linux, tested on
[Omarchy](https://omarchy.org): fan curve and settings access, two BIOS ACPI bugs,
a slow battery query that stutters games, and idle power draw on the internal screen.
Each fix is independent, has its own installer, checker and uninstaller, and can be
undone.

- Eight fixes in `correctifs/`, each with a `LISEZMOI.md` (in French) that explains the
  problem and exactly what is installed.
- A research part in [`recherche/`](recherche/README.md): the tools, raw measurements
  and open questions behind the fixes. None of it is needed to use them.
- `verifier-tout.sh`: one table that checks every fix.

## Target hardware

| | |
|---|---|
| Model | MSI GS76 Stealth 11UH |
| BIOS | `E17M1IMS.119` |
| EC firmware | `17M1EMS1.113` |

The fixes were measured on this exact machine. The installers accept a machine whose DMI
`product_name` contains `GS76` **and** whose firmware is `17M1` (msi-ec `fw_version`
starting with `17M1`, otherwise DMI `bios_version` starting with `E17M1`). They refuse
anything else unless you pass `--force`. Other GS76 variants (for example the 11UG) may
work, but nothing here proves it.

## The eight fixes

| # | Folder | Problem | Measured effect | Risk |
|---|---|---|---|---|
| 1 | `1-pilote-msi-ec` | Fan mode, shift mode, Cooler Boost and the charge limit can only be set by root, and the `msi-ec` driver shipped with a kernel can lag behind the project | Installs the upstream `msi-ec` driver at a pinned commit through DKMS and opens the settings to the `msi-ec` group; no figure | Low: replaces the DKMS `msi-ec` module; the previous one is restored on uninstall only if its sources are still in `/usr/src` |
| 2 | `2-ssdt` | BIOS ACPI bugs: `\_TZ.ETMD` is never defined, so `_OSC` fails and Intel DTT settings never reach `thermald`; the I2C touchpad also shows up as a `SynPS/2` mouse | The `_OSC` errors are gone and the PS/2 alias disappears (see [research](recherche/README.md), section 2); no performance figure | **Medium: acts at boot** (add-only SSDT injected through the initramfs). If the system misbehaves, pick the Snapper snapshot "avant SSDT GS76 (acpi_override)" in the Limine boot menu |
| 3 | `3-thermald` | After fix 2, user space starts about 0.5 s earlier and `thermald` can start before `intel_rapl_*`, so it runs without RAPL | `thermald` waits up to 5 s for RAPL; no figure. **Only useful with fix 2** | Low: one systemd drop-in |
| 4 | `4-batterie` | The BIOS `_BST` method takes about 114 ms, so every battery read stutters (widget, power manager, games) | A 5-minute kernel cache plus a background refresh moves the cost away from games; no figure for the cache itself | Low: a tmpfiles entry, a systemd timer, original `cache_time` restored on uninstall |
| 5 | `5-ecran` | MSI's VBT disables Panel Self Refresh, and at 360 Hz the panel's PSR setup time (330 us) is too long, so the CPU never reaches deep idle states | About 2.9 W to 1.45 W at idle (package power, 60 Hz with PSR forced) | Low to medium: writes to i915 debugfs at boot; refresh rate change needs Hyprland 0.56 or later (`--force` skips that check too) |
| 6 | `6-widget-ventilateurs` | No way to see or change the fan mode from the bar | A bar widget (Omarchy plugin, separate repository); needs fix 1 | Low: a user plugin |
| 7 | `7-hibernation` | After resuming from hibernation, the PL2 power limit stays at the BIOS factory value (120 W): neither the kernel nor `thermald` rewrites it | `thermald` is restarted on resume; 45/64 W restored in 4 s (measured by simulating the post-hibernation state) | Low: one systemd unit |
| 8 | `8-vbt` | MSI's VBT does not declare the internal AUO `0xE295` panel: `i915` falls back to an entry with neither PSR nor DRRS | PSR active at 60 Hz without forcing, and automatic drop to 60 Hz in 360 Hz mode when the image is still; gain in watts not measured. Makes the forced PSR of fix 5 redundant | Medium: affects the display from boot, kernel marked *tainted*; snapshot and uninstaller |

Details, variables (`SEUIL_CHARGE`, `RAFRAICHISSEMENT`, ...) and uninstall notes are in
each folder's `LISEZMOI.md`.

## Prerequisites

- Arch Linux, `bash`, `git`, systemd
- Omarchy: for the refresh-rate part of fix 5 and for fix 6
- `dkms` and the kernel headers of each installed kernel (fix 1)
- `mkinitcpio` (fixes 2 and 8)
- `python3` (fix 8)
- util-linux `column` (for `verifier-tout.sh`)
- Fix 5's refresh-rate part also needs `hyprctl` (Hyprland 0.56 or later), `jq`, `socat` and UPower
- Optional: Limine and Snapper (boot snapshot rollback for fix 2); `limine-mkinitcpio` is used when present

## Recommended order

1. **Fix 1** (driver), then **log out and back in**: group membership only applies on the
   next login.
2. **Fix 2** (SSDT), then **reboot**. Then **fix 3**.
3. **Fix 4** (battery) and **fix 5** (screen); they are independent of the others.
4. **Fix 6** (widget), once fix 1 is active.

## Usage

From the folder of the fix you want:

    cd correctifs/1-pilote-msi-ec
    sudo ./installer.sh        # install (add --force to skip the hardware check)
    ./verifier.sh              # check, no privileges
    sudo ./desinstaller.sh     # undo

`verifier.sh` prints `OK`, `ABSENT` or `DÉFAUT <detail>` and exits 0 (healthy), 1 (not
installed) or 2 (fault). Installers and uninstallers are idempotent and keep a backup of
whatever they replace in `/var/lib/msi-gs76-linux/`.

Fix 6 is installed through Omarchy instead:

    omarchy plugin add https://github.com/swald54000/omarchy-msi-fans.git --enable

and removed with `omarchy plugin remove swald.fans`; its `./verifier.sh` works like the
others.

To check everything at once, without privileges:

    ./verifier-tout.sh

It runs every `verifier.sh` and prints one line per fix: healthy, not installed or faulty.

## Rollback

Fixes 1 to 5 each have a `sudo ./desinstaller.sh` that restores what the installer saved; fix 6 is removed with `omarchy plugin remove swald.fans`. Fix 2
acts at boot: if the system no longer starts correctly, choose the Snapper snapshot
"avant SSDT GS76 (acpi_override)" (taken by the installer when `snapper` is present) in
the Limine boot menu, then run its uninstaller.

## Known limits

- The auxiliary (third) fan under GPU load has **not been verified**; the research
  documents what is known (community sources only).
- The USB keyboard enumeration failure (error -71) is only in
  [`recherche/`](recherche/README.md), as an **unconfirmed hypothesis**; it is not a fix.
- The fixes target this exact model and firmware. The installers refuse other machines
  unless you use `--force`.
- If you used an older version of the battery fix, run fix 4's installer again.

**Change of 17 November 2026.** Fix 1 now installs the upstream `msi-ec` driver instead of
a fork, which is no longer maintained and will be deleted. If you installed the earlier
version, run its installer again and update the fan widget to 2.2.0 or later; the fan curve
chart goes away, everything else stays. Details in
[`correctifs/1-pilote-msi-ec/LISEZMOI.md`](correctifs/1-pilote-msi-ec/LISEZMOI.md).

## Security

The installers and uninstallers run as root: **read them before running them**. The installers
download only the upstream msi-ec driver, at a pinned commit (fix 1); the widget comes through
`omarchy plugin add`. The research tools are
different: most need root and were written for one machine; read
[`recherche/README.md`](recherche/README.md) before running any.

## Tests

    bash tests/lancer.sh

Runs every test against a temporary root with fake system tools; nothing touches `/usr`,
`/etc`, `/sys` or `/var`.

## Related projects

- [msi-ec](https://github.com/MControlSuite/msi-ec): the driver installed by fix 1
- [omarchy-msi-fans](https://github.com/swald54000/omarchy-msi-fans): the widget of fix 6
- [KLC Light](https://github.com/swald54000/klc-light): per-key keyboard lighting editor
  for the same machine
- [Research](recherche/README.md): measurements and open questions

## License

MIT, see [LICENSE](LICENSE).
