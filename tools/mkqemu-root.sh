#!/bin/bash
# Build the tiny HFS+ ramdisk that lets QEMU boot past "VM bootstrap done".
#
#   tools/mkqemu-root.sh OUT.img [SIZE_MB] [INIT_BINARY]
#
# The kernel gets the image as /chosen/memory-map RAMDisk (mkpayload.py
# --ramdisk) and mounts it as root with rd=md0. The only thing on it is
# /sbin/launchd = a static arm64 Mach-O that prints its PID and heartbeats,
# which is what XNU execs as PID 1 (tools/sweet-init.S + tools/mkinit.py).
#
# Needs hfsprogs (mkfs.hfsplus, fsck.hfsplus) and sudo for the loop mount.
# Arch: hfsprogs is in the AUR (e.g. `paru -S hfsprogs`); Debian/Ubuntu:
# `sudo apt install hfsprogs`. Without them the kernel panics in bsd_init
# with "no root device" because md0 cannot be mounted.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${1:?usage: mkqemu-root.sh OUT.img [SIZE_MB] [INIT_BINARY]}
SIZE_MB=${2:-64}
INIT=${3:-}

for t in mkfs.hfsplus; do
	command -v "$t" >/dev/null ||
		{ echo "error: $t not found; install hfsprogs (AUR: paru -S hfsprogs)" >&2; exit 1; }
done
command -v sudo >/dev/null || { echo "error: sudo needed for the loop mount" >&2; exit 1; }

# 1. init binary: build it if the caller did not pass one.
if [ -z "$INIT" ]; then
	command -v clang >/dev/null || { echo "error: clang not found" >&2; exit 1; }
	clang -target arm64-apple-ios16.0 -c tools/sweet-init.S -o "${OUT%.img}.init.o"
	python3 tools/mkinit.py "${OUT%.img}.init.o" "${OUT%.img}.init"
	INIT=${OUT%.img}.init
fi

# 2. fresh image
rm -f "$OUT"
truncate -s "${SIZE_MB}M" "$OUT"
mkfs.hfsplus -v GinkgoQEMU -s "$OUT" >/dev/null

# 3. populate: XNU's bsd_init execs /sbin/launchd as PID 1.
mnt=$(mktemp -d)
sudo mount -t hfsplus -o loop,force "$OUT" "$mnt"
trap 'sudo umount "$mnt"; rmdir "$mnt"' EXIT
sudo install -D -m 0755 "$INIT" "$mnt/sbin/launchd"
sudo mkdir -p "$mnt/dev" "$mnt/private/var"
sudo chmod 0755 "$mnt/dev" "$mnt/private" "$mnt/private/var"
sudo sync
sudo umount "$mnt"
rmdir "$mnt"
trap - EXIT

# 4. report what the kernel will mount
echo "$OUT: $(stat -c %s "$OUT") bytes"
sudo fsck.hfsplus -n "$OUT" | tail -2 || true
cat <<EOF

Boot it:

  python3 tools/mkadt.py /tmp/qemu.adt --qemu
  python3 tools/mkpayload.py xnu/out/kernel.development.ginkgo /tmp/qemu.adt \\
      /tmp/payload-qemu.bin --ramdisk $OUT \\
      --cmdline 'debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam rd=md0'
  ../../tools/qemu-ginkgo.py /tmp/payload-qemu.bin /tmp/qemu-root \\
      --secs 40 --kernel xnu/out/kernel.development.ginkgo

Expected after "VM bootstrap done": BSD root md0, hfs mounted, then
"sbin/launchd" as PID 1 and the init's heartbeat.
EOF
