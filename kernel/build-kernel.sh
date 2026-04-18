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

# Apply config: Firecracker base + PVE overlay
echo "Applying config..."
cp "${SCRIPT_DIR}/base-x86_64-6.1.config" .config

# Merge overlay config
if [ -f "${SCRIPT_DIR}/pve-microvm-overlay.config" ]; then
    scripts/kconfig/merge_config.sh -m .config "${SCRIPT_DIR}/pve-microvm-overlay.config" >/dev/null 2>&1 || {
        # Fallback: manual append + olddefconfig
        cat "${SCRIPT_DIR}/pve-microvm-overlay.config" >> .config
    }
fi

# Resolve dependencies and set defaults for new options
make olddefconfig >/dev/null 2>&1

# Build
NCPU=$(nproc)
echo "Building with ${NCPU} CPUs..."
make -j"$NCPU" bzImage 2>&1 | tail -n 5

# Copy output
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
