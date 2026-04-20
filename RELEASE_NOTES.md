# pve-microvm v0.1.23

Storage compatibility fix + guest agent reliability.

## Fixes

- **Dir/ZFS/NFS storage**: template and OCI import tools now correctly
  parse `qm importdisk` output for volume IDs. Previously hardcoded
  LVM naming (`storage:vm-VMID-disk-0`) which doesn't work for dir-type
  storage (`storage:VMID/vm-VMID-disk-0.qcow2`).
- **Guest agent**: mask broken stock `qemu-guest-agent.service` (can't
  clear `BindsTo=` via drop-in on Trixie), use custom `microvm-agent.service`
  with `Restart=always`.
- **DHCP**: `microvm-dhcp.service` uses `dhclient` as fallback for reliable
  networking (systemd-networkd has config matching issues with microvm devtmpfs).

## Storage types now supported

| Storage | Volume format | Status |
|---|---|---|
| LVM / LVM-thin | `local-lvm:vm-900-disk-0` | ✅ |
| Dir (local) | `local:900/vm-900-disk-0.qcow2` | ✅ (fixed) |
| ZFS pool | `local-zfs:vm-900-disk-0` | ✅ |
| NFS/CIFS | `nfs:900/vm-900-disk-0.qcow2` | ✅ |

## Upgrade

```bash
curl -sL https://github.com/rcarmo/pve-microvm/releases/download/v0.1.23/pve-microvm_0.1.23-1_all.deb -o /tmp/pve-microvm.deb
dpkg -i /tmp/pve-microvm.deb
```

Rebuild templates after upgrading to get the new DHCP + agent services.
