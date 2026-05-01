#!/bin/bash
# build-exo-template.sh — Create a minimal exo microvm template
#
# Builds a Debian trixie-slim image with exo[cpu] pre-installed.
# Models are stored on a separate volume (/models).
#
# Usage:
#   build-exo-template.sh [--vmid 9020] [--storage local-lvm]
#
# Requirements:
#   - pve-microvm installed
#   - Network access (pip, GitHub, PyPI)
#   - ~4 GB temp space for build
#
# Output:
#   - Template VMID with exo ready to run
#   - Separate models volume for shared model storage
set -euo pipefail

VMID=9020
STORAGE="local-lvm"
DISK_SIZE="2G"
NAME="microvm-exo-cpu"
TAGS="microvm,exo,inference"
KERNEL="/usr/share/pve-microvm/vmlinuz"
INITRD="/usr/share/pve-microvm/initrd"

log()  { echo "[exo-template] $*"; }
die()  { echo "[exo-template] ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --vmid)   VMID="$2"; shift 2 ;;
        --storage) STORAGE="$2"; shift 2 ;;
        --name)   NAME="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

log "Building exo CPU template"
log "  VMID:    $VMID"
log "  Storage: $STORAGE"

# ── Pull and unpack base image ───────────────────────────────────
log "Pulling debian:trixie-slim..."
skopeo copy docker://debian:trixie-slim "oci:$WORKDIR/oci:latest" >/dev/null 2>&1
umoci unpack --image "$WORKDIR/oci:latest" "$WORKDIR/bundle" >/dev/null 2>&1
R="$WORKDIR/bundle/rootfs"

# ── Prepare rootfs ───────────────────────────────────────────────
for dir in proc sys dev dev/pts run tmp sbin usr/local/bin usr/sbin models; do
    mkdir -p "$R/$dir"
done

# ── Chroot: install exo ─────────────────────────────────────────
log "Installing packages + exo[cpu] in chroot..."
mount --bind /proc "$R/proc"
mount --bind /sys "$R/sys"
mount --bind /dev "$R/dev"
cp /etc/resolv.conf "$R/etc/resolv.conf"

chroot "$R" bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip python3-dev \
  git curl ca-certificates build-essential \
  libopenblas-dev pkg-config \
  systemd systemd-sysv dbus \
  openssh-server qemu-guest-agent \
  isc-dhcp-client iproute2 sudo

# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# Install exo in a venv
mkdir -p /opt/exo
cd /opt/exo
uv venv --python python3 .venv
. .venv/bin/activate
uv pip install "exo[cpu]"

# Verify
/opt/exo/.venv/bin/exo --help >/dev/null 2>&1 && echo "exo installed OK" || echo "exo install FAILED"

# Enable services
systemctl enable serial-getty@ttyS0.service ssh qemu-guest-agent 2>/dev/null || true

# Root password
echo "root:microvm" | chpasswd
mkdir -p /etc/ssh
[ -f /etc/ssh/sshd_config ] && sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config

# Networking
mkdir -p /etc/network/interfaces.d
printf "auto eth0\niface eth0 inet dhcp\n" > /etc/network/interfaces.d/eth0

# fstab — root + models volume
cat > /etc/fstab << FSTABEOF
/dev/vda  /        ext4 errors=remount-ro 0 1
LABEL=exo-models /models ext4 defaults,nofail 0 2
FSTABEOF

echo "microvm-exo" > /etc/hostname
echo "127.0.0.1 localhost microvm-exo" > /etc/hosts

# HuggingFace cache → models volume
mkdir -p /models/huggingface /root/.cache
ln -sf /models/huggingface /root/.cache/huggingface

# Exo systemd service
cat > /etc/systemd/system/exo.service << SVCEOF
[Unit]
Description=exo distributed inference
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/exo
Environment=PATH=/opt/exo/.venv/bin:/usr/bin:/bin
Environment=HF_HOME=/models/huggingface
Environment=EXO_HOME=/opt/exo
ExecStart=/opt/exo/.venv/bin/exo
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl enable exo 2>/dev/null || true

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache/pip /root/.cache/uv
'

umount "$R/dev" "$R/sys" "$R/proc" 2>/dev/null

# ── Check size ───────────────────────────────────────────────────
log "Rootfs: $(du -sh "$R" | cut -f1)"

# ── Create ext4 disk ─────────────────────────────────────────────
log "Creating ${DISK_SIZE} disk..."
RAW="$WORKDIR/disk.raw"
dd if=/dev/zero of="$RAW" bs=1M count=$(echo "$DISK_SIZE" | sed 's/G/*1024/;s/M//' | bc) status=none
mkfs.ext4 -F -L microvm-root -d "$R" "$RAW" >/dev/null 2>&1

# ── Create PVE VM ────────────────────────────────────────────────
log "Creating template VM $VMID..."
qm destroy "$VMID" --purge 2>/dev/null || true

qm create "$VMID" \
  --machine microvm \
  --memory 4096 \
  --cores 2 \
  --name "$NAME" \
  --serial0 socket --vga serial0 \
  --agent 1 \
  --net0 virtio,bridge=vmbr0 \
  --tags "$TAGS" \
  --args "-kernel $KERNEL -initrd $INITRD -append \"console=ttyS0 root=/dev/vda rw quiet\"" 2>&1

log "Importing disk..."
IMPORT_OUT=$(qm importdisk "$VMID" "$RAW" "$STORAGE" 2>&1)
VOLID=$(echo "$IMPORT_OUT" | grep -oP "unused0: successfully imported disk '\K[^']+")
[ -z "$VOLID" ] && VOLID="${STORAGE}:vm-${VMID}-disk-0"

qm set "$VMID" --scsi0 "$VOLID" 2>&1
qm set "$VMID" --scsi1 "${STORAGE}:cloudinit,media=cdrom" 2>&1
qm set "$VMID" --ipconfig0 ip=dhcp --ciuser root 2>&1

log "Converting to template..."
qm template "$VMID" 2>&1

log ""
log "=== Template ready: $NAME (VMID $VMID) ==="
log ""
log "Usage:"
log ""
log "  # Clone"
log "  qm clone $VMID <vmid> --name exo-node --full"
log ""
log "  # Add models volume (create once, reuse across clones)"
log "  qm set <vmid> --scsi2 ${STORAGE}:<models-volume>"
log "  # Or create a new one:"
log "  # pvesm alloc ${STORAGE} <vmid> vm-<vmid>-models 32G"
log "  # mkfs.ext4 -L exo-models /dev/pve/vm-<vmid>-models"
log "  # qm set <vmid> --scsi2 ${STORAGE}:vm-<vmid>-models"
log ""
log "  # Start"
log "  qm set <vmid> --memory 8192 --cores 4"
log "  qm start <vmid>"
log ""
log "  # Inside the VM:"
log "  mount /models"
log "  systemctl start exo"
log "  # exo auto-discovers peers on the same network"
