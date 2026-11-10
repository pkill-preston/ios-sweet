# ios-ginkgo

**Apple's iOS 16 on the Xiaomi Redmi Note 8 (`ginkgo`, Qualcomm SM6125 / Snapdragon 665).**

This is a port of [ios-sweet](https://github.com/dipa-studio/ios-sweet) (Redmi Note 10
Pro, SM7150) to the Redmi Note 8. It boots Apple's open-source XNU kernel
(xnu-8796, the iOS 16 generation) from RAM with `fastboot boot` and, once the
drivers exist, runs the unmodified iOS 16.7.16 iPhone X userland on top.

**Status: bring-up, Phase 2.** No kernel has booted on this phone yet. The
current state is:

| Area | State |
| --- | --- |
| Host tooling | QEMU harness (`tools/qemu-ginkgo.py`, framebuffer patched to this panel) |
| Device description | ADT generator (`tools/mkadt.py`) carries this phone's memory map, GIC, panel and eMMC host |
| Kernel | machine config `GINKGO` (Kryo 260, ARMv8.0 + crypto, no PAC/PAN, 16K pages) |
| Storage | **not written yet**: `shim/emmc.c` against `sdhci@4744000` must replace `shim/ufs.c` |
| Panel | **not written yet**: FT8719 Huaxing, 1080x2340, DSI video mode |
| Touch | **not written yet**: FocalTech FT8719 over SPI, reset GPIO 87, IRQ 88 |
| Phone boot | not attempted; bring-up images will use `fastboot boot` only |

## Hardware (measured, not assumed)

The porting plan this project started from assumed an NT36672A panel and Novatek
touch, i.e. the sweet-class hardware. This unit is different:

| Item | Value |
| --- | --- |
| SoC | SM6125, Kryo 260: 4x Cortex-A73 @2.0 GHz + 4x Cortex-A53 @1.8 GHz |
| Panel | `dsi_ft8719_huaxing_vid_display` - FocalTech FT8719, Huaxing, 1080x2340 @60 Hz |
| Framebuffer | `cont_splash_region@0x5c000000`, size `0xf00000` |
| Touch | FocalTech FTS, IC `0x8719`, SPI 8 MHz, reset GPIO 87, IRQ GPIO 88 |
| GIC | `arm,gic-v3`, distributor `0xf200000`, redistributors `0xf300000` (stride `0x20000`) |
| eMMC | `sdhci@4744000` (`qcom,sdhci-msm-v5`), Samsung DP6DAB, 58.3 GiB, HS400, 8-bit |
| DRAM | `0x40000000+0x3dd00000`, `0x80000000+0x40000000`, `0xc0000000+0x80000000` |
| GPU | Adreno 610, `kgsl-3d0@5900000`, chipid `0x6010000` |

The full table, with sources and the corrections to the original plan, is in
`docs/hardware-inventory.md` of the parent project (`note8-ios`).

## Safety

- Nothing is ever flashed to `boot`, `dtbo`, `vbmeta` or the bootloader
  partitions. Bring-up uses `fastboot boot`, which loads into RAM only.
- `persist`, `modemst1/2`, `fsg` and `fsc` are backed up and hash-verified
  before any device write; the iOS root, when it exists, goes into `userdata`.
- The kernel and the shim must never write outside `userdata` (see the deny-list
  in the parent project's plan).

## Build

The kernel builds on macOS with Apple's toolchain, via GitHub Actions
(`.github/workflows/xnu.yml`, `runs-on: macos-15`, Xcode 16):

```sh
gh workflow run xnu.yml -R pkill-preston/ios-sweet
gh run download <run-id> -R pkill-preston/ios-sweet -n xnu-kernel -D xnu/out
```

Then, on Linux, with `qemu-system-aarch64`:

```sh
python3 tools/mkadt.py /tmp/qemu.adt --qemu
python3 tools/mkpayload.py xnu/out/kernel.development.ginkgo /tmp/qemu.adt /tmp/payload.bin \
    --cmdline 'debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam rd=md0'
python3 tools/qemu-ginkgo.py /tmp/payload.bin /tmp/run --secs 20 --live-serial
```

See `docs/QEMU_TESTING.md`.

## Layout

| Path | What |
| --- | --- |
| `xnu/patches/` | XNU patches, applied on top of blacktop/darwin-xnu-build |
| `shim/` | the boot shim the bootloader starts (`fastboot boot` image) |
| `tools/` | ADT/payload/QEMU tooling |
| `docs/` | QEMU testing notes |
| `NOTES.md` | working notes; the ginkgo section is first, the rest is the upstream sweet handoff (historical) |

## Credits

Fork of [dipa-studio/ios-sweet](https://github.com/dipa-studio/ios-sweet) (MIT).
Upstream notes, patches and design are theirs; the ginkgo device layer is this
project's.
