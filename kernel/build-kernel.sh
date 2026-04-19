#!/bin/bash
# build-kernel.sh — build a minimal microvm kernel for pve-microvm
#
# Downloads the specified kernel source, applies the pve-microvm config
# (Firecracker base + PVE overlay), and produces a vmlinuz binary.
#
# Usage:
#   ./build-kernel.sh [--version 6.12.22] [--output /path/to/vmlinuz]
#
# Requirements: build-essential, flex, bison, libelf-dev, bc, libssl-dev, wget

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORIG_DIR="$(pwd)"
DEFAULT_VERSION="6.12.22"
DEFAULT_OUTPUT="${SCRIPT_DIR}/vmlinuz-microvm"

VERSION="$DEFAULT_VERSION"
OUTPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --output)  OUTPUT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--version 6.12.22] [--output /path/to/vmlinuz]"
            exit 0
            ;;
        *)  shift ;;
    esac
done

# Resolve output path (make relative paths relative to the caller's cwd)
if [ -z "$OUTPUT" ]; then
    OUTPUT="$DEFAULT_OUTPUT"
elif [[ "$OUTPUT" != /* ]]; then
    OUTPUT="${ORIG_DIR}/${OUTPUT}"
fi

MAJOR=$(echo "$VERSION" | cut -d. -f1)
BUILD_DIR="/tmp/pve-microvm-kernel-build"

echo "=== pve-microvm kernel builder ==="
echo "Kernel version: $VERSION"
echo "Output:         $OUTPUT"
echo ""

# Verify build tools
for tool in make gcc flex bison bc; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: missing build tool: $tool"
        echo "Install with: apt install build-essential flex bison libelf-dev bc libssl-dev"
        exit 1
    }
done

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download kernel source
TARBALL="linux-${VERSION}.tar.xz"
if [ ! -f "$TARBALL" ]; then
    echo "Downloading kernel ${VERSION}..."
    wget -q --show-progress \
        "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/${TARBALL}"
fi

# Extract
SRCDIR="linux-${VERSION}"
if [ ! -d "$SRCDIR" ]; then
    echo "Extracting..."
    tar xf "$TARBALL"
fi

cd "$SRCDIR"

# Apply config: start from defconfig then merge our microvm config
echo "Applying config..."
make defconfig >/dev/null 2>&1

# Merge our microvm-specific config on top of defconfig
if [ -f "${SCRIPT_DIR}/pve-microvm-6.12.config" ]; then
    scripts/kconfig/merge_config.sh -m .config "${SCRIPT_DIR}/pve-microvm-6.12.config" >/dev/null 2>&1 || {
        cat "${SCRIPT_DIR}/pve-microvm-6.12.config" >> .config
    }
fi

# Resolve dependencies
make olddefconfig >/dev/null 2>&1

# Verify critical configs survived olddefconfig
echo "Verifying critical configs..."
for cfg in CONFIG_VIRTIO_NET CONFIG_VIRTIO_BALLOON CONFIG_VIRTIO_CONSOLE CONFIG_VIRTIO_BLK CONFIG_VIRTIO_MMIO CONFIG_MODULES; do
    val=$(grep "^${cfg}=" .config 2>/dev/null || echo "MISSING")
    echo "  $val"
done

# Build kernel + modules
NCPU=$(nproc)
echo "Building kernel with ${NCPU} CPUs..."
make -j"$NCPU" bzImage 2>&1 | tail -n 5
echo "Building modules..."
make -j"$NCPU" modules 2>&1 | tail -n 3

# Install modules to a temp dir
MOD_DIR=$(mktemp -d)
make modules_install INSTALL_MOD_PATH="$MOD_DIR" INSTALL_MOD_STRIP=1 2>&1 | tail -n 3

# Build minimal initramfs with just the virtio modules
echo "Building initramfs..."
INITRD_DIR=$(mktemp -d)
mkdir -p "$INITRD_DIR"/{bin,lib/modules,proc,sys,dev,mnt,tmp}

# Copy virtio modules
find "$MOD_DIR" -name 'virtio_net.ko*' -o -name 'virtio_balloon.ko*' -o -name 'virtio_console.ko*' \
  -o -name 'virtio_mmio.ko*' -o -name 'virtio_ring.ko*' -o -name 'virtio.ko*' \
  -o -name 'virtio_blk.ko*' \
  -o -name 'net_failover.ko*' -o -name 'failover.ko*' -o -name 'hw_random.ko*' \
  -o -name 'virtio_rng.ko*' | while read -r mod; do
    cp "$mod" "$INITRD_DIR/lib/modules/" 2>/dev/null
done
echo "  Modules: $(ls "$INITRD_DIR/lib/modules/" | wc -l) files, $(du -sh "$INITRD_DIR/lib/modules/" | cut -f1)"

# Create init script that loads modules then execs real init
cat > "$INITRD_DIR/init" <<'INITSCRIPT'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev

# Load virtio modules in dependency order
for mod in /lib/modules/virtio.ko* /lib/modules/virtio_ring.ko* \
           /lib/modules/virtio_mmio.ko* \
           /lib/modules/virtio_blk.ko* \
           /lib/modules/failover.ko* /lib/modules/net_failover.ko* \
           /lib/modules/virtio_net.ko* \
           /lib/modules/virtio_console.ko* \
           /lib/modules/virtio_balloon.ko* \
           /lib/modules/virtio_rng.ko*; do
    [ -f "$mod" ] && insmod "$mod" 2>/dev/null
done

# Wait for root device to appear (modules need a moment)
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -b /dev/vda ] && break
    sleep 0.2
done

# Mount and switch to real root
if [ -b /dev/vda ]; then
    mount -t ext4 /dev/vda /mnt 2>/dev/null || mount /dev/vda /mnt 2>/dev/null
    if [ -x /mnt/sbin/init ] || [ -L /mnt/sbin/init ]; then
        # Move mounts into new root
        mount --move /proc /mnt/proc 2>/dev/null || umount /proc
        mount --move /sys /mnt/sys 2>/dev/null || umount /sys
        mount --move /dev /mnt/dev 2>/dev/null || umount /dev
        exec switch_root /mnt /sbin/init
    fi
fi

# Fallback: drop to shell
echo "pve-microvm: root mount failed, dropping to shell"
exec /bin/sh
INITSCRIPT
chmod 755 "$INITRD_DIR/init"

# We need busybox-static for the initrd (insmod, mount, switch_root)
# Prefer busybox-static package, then system busybox, then download
BUSYBOX=""
if [ -f /usr/bin/busybox-static ]; then
    BUSYBOX=/usr/bin/busybox-static
elif command -v busybox >/dev/null 2>&1; then
    # Check if it's statically linked
    if file $(which busybox) | grep -q 'statically linked'; then
        BUSYBOX=$(which busybox)
    fi
fi
if [ -z "$BUSYBOX" ]; then
    # Download static busybox
    echo "Downloading static busybox..."
    curl -sL "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" -o "$INITRD_DIR/bin/busybox" 2>/dev/null || \
    curl -sL "https://www.busybox.net/downloads/binaries/1.31.0-x86_64-uclibc/busybox" -o "$INITRD_DIR/bin/busybox" 2>/dev/null || true
    BUSYBOX="$INITRD_DIR/bin/busybox"
fi
if [ -n "$BUSYBOX" ] && [ -f "$BUSYBOX" ]; then
    cp "$BUSYBOX" "$INITRD_DIR/bin/busybox" 2>/dev/null || true
    chmod 755 "$INITRD_DIR/bin/busybox"
    for cmd in sh mount umount insmod modprobe switch_root sleep grep dmesg cat ls ip; do
        ln -sf busybox "$INITRD_DIR/bin/$cmd"
    done
else
    echo "WARNING: no static busybox found, initrd may not work"
fi

# Create cpio initramfs
INITRD_OUT="${OUTPUT%.vmlinuz*}"
[ "$INITRD_OUT" = "$OUTPUT" ] && INITRD_OUT="$(dirname "$OUTPUT")"
INITRD_OUT="${INITRD_OUT}/initrd-microvm"

(cd "$INITRD_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9) > "$INITRD_OUT"
INITRD_SIZE=$(du -sh "$INITRD_OUT" | cut -f1)
echo "  Initrd: $INITRD_OUT ($INITRD_SIZE)"

rm -rf "$MOD_DIR" "$INITRD_DIR"

# Copy kernel output
BZIMAGE="arch/x86/boot/bzImage"
if [ -f "$BZIMAGE" ]; then
    cp "$BZIMAGE" "$OUTPUT"
    SIZE=$(du -sh "$OUTPUT" | cut -f1)
    echo ""
    echo "=== Build complete ==="
    echo "Kernel: $OUTPUT ($SIZE)"
    echo "Version: $VERSION"
    echo ""
    echo "Install to Proxmox node:"
    echo "  scp $OUTPUT root@pve-node:/usr/share/pve-microvm/vmlinuz"
else
    echo "ERROR: bzImage not found at $BZIMAGE"
    exit 1
fi
