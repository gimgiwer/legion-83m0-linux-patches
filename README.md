# Lenovo Legion 83M0: Linux DSDT & Hardware Fixes

DSDT patches, kernel module configs, and ACPI handlers for Lenovo Legion 5 15AHP9 / 16AHP9 / R7000 (2024–2026). Validated against BIOS `RGCN35WW` and EC `RGEC35WW`.

---

## Target Hardware

| Component | Specification | Notes |
| :--- | :--- | :--- |
| **Laptop Model** | Lenovo Legion R7000 AHP10 (Type `83M0`) | Global equivalents: Legion 5 15AHP9 / 16AHP9 (Board `LNVNB161216`) |
| **CPU** | AMD Ryzen 7 H 255 (8C/16T, Hawk Point Zen 4) | Family 25, Model 117, Stepping 2 |
| **iGPU** | AMD Radeon 780M Graphics | RDNA 3, PCI ID `1002:1900` |
| **dGPU** | NVIDIA GeForce RTX 5060 Laptop GPU | Blackwell GB206M, PCI ID `10de:2d59` |
| **EC** | ITE Embedded Controller (IT8258) | ACPI Path: `\_SB.PCI0.LPC0.EC0` |
| **Firmware** | BIOS `RGCN35WW` / EC `RGEC35WW` | Tested baseline |

---

## The Fixes

### 1. Instant Suspend Wakeup (~0.98s Loop)
- **Symptom:** System exits `s2idle` after ~0.98s. Sleep is non-functional.
- **Root Cause:** Internal Intel AX210 Bluetooth module at USB port `\_SB.PCI0.GP17.XHC0.RHUB.PRT5` spuriously asserts `GPE03` wake notifications during suspend.
- **Fix:** Override `_PRW` on `PRT5` to `Package(2) { Zero, Zero }`. Disables wake triggers; Bluetooth remains fully operational in S0.
- **Patch:** [`patches/dsdt_sleep_bt_led.patch`](patches/dsdt_sleep_bt_led.patch) (or insert manually from [`patches/snippets.asl`](patches/snippets.asl)).

### 2. Autonomous Power Button Breathing LED
- **Symptom:** Power button LED remains solid or unlit in `s2idle`.
- **Root Cause:** Stock DSDT does not trigger the hardware breathing PWM on the power button LED in Linux during sleep.
- **Fix:** Hook into ACPI sleep methods:
  - **`_PTS` (Prepare To Sleep):** Acquire EC mutex `LFCM` (timeout `0x0FA0`), write `0x02` to EC register `PCBS` (ECRAM offset `0x42`).
  - **`_WAK` (Wake):** Write `0x00` to `PCBS` to restore active profile coloring.
- **Patch:** Included in [`patches/dsdt_sleep_bt_led.patch`](patches/dsdt_sleep_bt_led.patch).

### 3. Screen Backlight (Tianma 2.5K 180Hz DC-Dimming)
- **Symptom:** Software brightness slider moves, but physical panel backlight does not respond.
- **Root Cause:** Physical panel backlight is wired directly to the **Lenovo EC**, controlled via WMI GUID `603E9613-EF25-4338-A3D0-C46177516DB7` (`nvidia_wmi_ec_backlight`). The APU interface `amdgpu_bl1` is a disconnected dummy PWM.
- **Caveat:** Do **not** pass `acpi_backlight=native` in kernel cmdline. It forces `backlight_native`, causing `nvidia-wmi-ec-backlight` to fail probing with `-ENODEV`.
- **Fix:**
  1. Add `options nvidia-wmi-ec-backlight force=1` to [`modprobe.d/nvidia-wmi-ec-backlight.conf`](modprobe.d/nvidia-wmi-ec-backlight.conf) (bypasses ACPI backlight type heuristic).
  2. Drop `acpi_backlight=native` from bootloader cmdline.
  3. Point your compositor/shell to `nvidia_wmi_ec_backlight` (e.g. Noctalia via [`noctalia/brightness.toml`](noctalia/brightness.toml)).

### 4. Performance Profile Switch Hotkey (Fn+Q)
- **Hardware Event:** Emits ACPI WMI event on `PNP0C14:02` with scancode `000000e3`.
- **Fix:** Hook into `/etc/acpi/handler.sh` to cycle `powerprofilesctl` and dispatch OSD notifications (dynamically detects active seat0 Wayland session). See [`acpi/handler_wmi_fn_q.sh`](acpi/handler_wmi_fn_q.sh).

### 5. Copilot Key Remap
- **Hardware Event:** Physical Copilot key sends `KEY_LEFTMETA + KEY_LEFTSHIFT + KEY_F23` via `ITE Device 8258` (`/dev/input/event5`).
- **Fix:** Bind `Mod+Shift+F23` in your Wayland compositor (Niri, Hyprland, Sway) to whatever action you need.

---

## Installation

Both methods inject the patched DSDT into early RAM without modifying physical flash.

### Method A: Arch Linux / CachyOS (mkinitcpio)

1. **Extract and decompile current DSDT:**
   ```bash
   cat /sys/firmware/acpi/tables/DSDT > dsdt.dat
   iasl -d dsdt.dat
   ```

2. **Apply patch:**
   ```bash
   patch -F3 dsdt.dsl < patches/dsdt_sleep_bt_led.patch
   ```
   > **Note:** If line offsets have drifted due to different BIOS revisions or compiler formatting, insert the changes manually using [`patches/snippets.asl`](patches/snippets.asl).

3. **Recompile to AML:**
   ```bash
   iasl -tc dsdt.dsl
   ```

4. **Install override:**
   ```bash
   sudo mkdir -p /etc/initcpio/acpi_override
   sudo cp dsdt.aml /etc/initcpio/acpi_override/dsdt.aml
   ```

5. **Configure mkinitcpio:**
   Add `acpi_override` before `autodetect` in `HOOKS` (`/etc/mkinitcpio.conf`):
   ```text
   HOOKS=(base systemd acpi_override autodetect ...)
   ```

6. **Rebuild initramfs & bootloader:**
   ```bash
   sudo mkinitcpio -P
   sudo limine-update   # If using Limine
   ```

---

### Method B: Generic Early CPIO (Fedora / Ubuntu / GRUB / systemd-boot)

1. **Create CPIO archive:**
   ```bash
   mkdir -p kernel/firmware/acpi
   cp dsdt.aml kernel/firmware/acpi/dsdt.aml
   find kernel | cpio -H newc --create > /boot/acpi_override.cpio
   ```

2. **Update bootloader:**
   Prepend `/boot/acpi_override.cpio` as the first initrd entry before the distribution initramfs.

3. **Verify:**
   ```bash
   dmesg | grep -iE "ACPI:.*DSDT.*(found|override)"
   ```

---

## Safety & Firmware Updates

> [!WARNING]
> **Before updating BIOS firmware:**
> Always **disable the DSDT override** in your bootloader/initramfs before flashing a BIOS update (e.g. from `RGCN35WW` to a newer version). Booting a newly flashed BIOS with an old DSDT table override will cause ACPI table mismatches, which can corrupt fan control, power delivery sequencing, and EC communication. After successfully updating the BIOS, dump the fresh DSDT, re-verify offsets, and recompile.

---

## Disclaimer

Low-level ACPI table override. Developed and verified on BIOS `RGCN35WW` / Lenovo Legion 83M0. Use at your own risk.
