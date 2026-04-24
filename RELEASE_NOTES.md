# pve-microvm v0.3.0

Major release: 37 features, 13 Linux distros, 4 non-Linux OS, Firecracker compatibility.

## Highlights

- **13 Linux distributions** tested: Debian, Ubuntu, Alpine, Fedora, Rocky, Alma, Amazon, Oracle, Red Hat UBI, VMware Photon, Microsoft Azure Linux
- **Non-Linux guests**: 9Front (Plan 9), OSv (unikernel), gokrazy (Go appliance)
- **Firecracker rootfs compatibility** — import directly
- **Template profiles**: `--profile minimal|standard|full`, `--no-docker`, `--no-ssh`, `--no-agent`
- **5 package managers**: apt, apk, dnf/microdnf, tdnf, yum
- **Ephemeral VMs**: `pve-microvm-run -- command` (auto-cleanup)
- **virtiofs + vsock**: host dir sharing, SSH agent forwarding
- **GUI**: panel hiding, one-click clone, ⚡ icon
- **All PVE storage types**: LVM, LVM-thin, ZFS, dir, NFS, CIFS

## Upgrade

```bash
curl -sL https://github.com/rcarmo/pve-microvm/releases/download/v0.3.0/pve-microvm_0.3.0-1_all.deb -o /tmp/pve-microvm.deb
dpkg -i /tmp/pve-microvm.deb
```
