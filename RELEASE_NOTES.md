# pve-microvm v0.3.18

## Upgrade safety

- Package upgrades no longer remove the patch stamp and blindly insert another
  Perl import/delegation block.
- When qemu-server is already patched, upgrades refresh `MicroVM.pm` and the UI
  without modifying `QemuServer.pm` again.
- If files and stamp are out of sync, the patcher checks existing markers before
  insertion, so applying twice remains idempotent.
- The CI suite executes the embedded QemuServer patcher twice against a fixture
  and requires exactly one import and one delegation block.

This release supersedes v0.3.17 for deployment.

## Guest lifecycle fixes

- Add PVE's qmeventd event monitor to every microVM QEMU command line.
  Guest-initiated shutdowns are now reaped correctly instead of leaving QEMU
  paused in `shutdown` state under `-no-shutdown`.
- `qm shutdown`, `qm reboot`, and the corresponding PVE web UI actions now work
  for standard-profile guests with the QEMU guest agent enabled.
- Add D-Bus to newly built Debian/Ubuntu templates so the guest agent can ask
  systemd/logind to schedule shutdown and reboot.

Existing Debian/Ubuntu guests built without D-Bus need:

```bash
apt-get update
apt-get install -y dbus
systemctl enable --now dbus
```

Guests created with `--no-agent` still have no guaranteed graceful shutdown
path; use `qm stop` or install and enable the QEMU guest agent.

## Configurable PVE bridge

- Add `--bridge BRIDGE` and `--bridge=BRIDGE` to
  `pve-microvm-template`.
- Remove hardcoded `vmbr0` from OpenWrt, OPNsense, and SmolBSD template paths.
- All template paths now honour the configured bridge.

## Tests and documentation

- Add parser tests for both bridge argument forms and missing values.
- Add command-builder contracts for qmeventd, QEMU reconnect compatibility,
  D-Bus, and hardcoded bridge prevention.
- Document shutdown/reboot diagnosis, existing-guest remediation, and the
  guest-agent limitation.
- Correct troubleshooting guidance: apply patches to the current qemu-server
  files directly; never restore a potentially stale backup before applying.

## Upgrade

Use the latest-release command from the installation guide, install the `.deb`,
and restart each running microVM so its QEMU process gains the qmeventd monitor.
Templates and stopped guests do not need to be started during the upgrade.
