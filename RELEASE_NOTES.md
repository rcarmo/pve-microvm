# pve-microvm v0.1.6

Cloud-init, qemu-guest-agent, and Docker support.

## What's new

- **Cloud-init** — config drive on scsi1, SSH key injection, hostname, DHCP
- **First-boot setup** — `microvm-setup` systemd oneshot installs:
  - cloud-init (nocloud datasource for PVE)
  - qemu-guest-agent (graceful shutdown, IP reporting)
  - Docker CE (Engine + Compose + Buildx)
- **Template with cloud-init drive** — `pve-microvm-template` now adds scsi1 cloudinit
- **Roadmap additions** — SSH agent forwarding, network isolation, egress allow-list

## Usage

```bash
pve-microvm-template
qm clone 9000 901 --name sandbox --full
qm set 901 --sshkeys ~/.ssh/authorized_keys
qm start 901
# First boot: ~60s (package install), then:
ssh root@<vm-ip>
docker run hello-world
qm shutdown 901
```
