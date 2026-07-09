# pve-microvm v0.3.17

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
