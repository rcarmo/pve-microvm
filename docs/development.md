# Development

## Repository structure

```
pve-microvm/
├── Makefile
├── README.md
├── RELEASE_NOTES.md
├── LICENSE
├── debian/                           # Debian packaging
│   ├── changelog
│   ├── control
│   ├── rules
│   ├── pve-microvm.postinst
│   ├── pve-microvm.prerm
│   └── patches/
├── docs/                             # Documentation
│   ├── pve-microvm-demo.gif
│   ├── installation.md
│   ├── usage.md
│   ├── architecture.md
│   ├── configuration.md
│   ├── limitations.md
│   ├── troubleshooting.md
│   └── development.md
├── doc/                              # Config templates
│   ├── microvm-defaults.conf
│   └── microvm-images.conf
├── kernel/                           # Kernel build
│   ├── base-x86_64-6.1.config
│   ├── pve-microvm-overlay.config
│   ├── build-kernel.sh
│   └── README.md
├── tools/                            # Runtime tools
│   ├── MicroVM.pm                    # Perl module
│   ├── microvm-init                  # Init for minimal images
│   ├── pve-microvm-patch             # Patch manager
│   ├── pve-microvm-template          # Template creator
│   └── pve-oci-import                # OCI importer
├── ui/                               # Web UI extensions
│   ├── pve-microvm.css
│   └── pve-microvm.js
└── .github/workflows/
    ├── ci.yml                        # Build on push/PR
    └── build.yml                     # Release on tag
```

## Building

```bash
# Build .deb (without kernel)
dpkg-buildpackage -us -uc -b

# Build kernel (requires build tools)
cd kernel && ./build-kernel.sh

# Full release (done by CI)
git tag -a v0.1.5 -m "v0.1.5" && git push origin v0.1.5
```

## Testing locally

```bash
# On a test Proxmox node
scp tools/MicroVM.pm root@pve:/usr/share/perl5/PVE/QemuServer/MicroVM.pm
scp tools/pve-microvm-patch root@pve:/usr/share/pve-microvm/
ssh root@pve /usr/share/pve-microvm/pve-microvm-patch apply

# Test
ssh root@pve qm create 999 --machine microvm --memory 128
ssh root@pve qm destroy 999
```

## Key source references

- `qemu-server/src/PVE/QemuServer/Machine.pm` — machine type definitions
- `qemu-server/src/PVE/QemuServer.pm` — `config_to_command()` entry
- [QEMU microvm source](https://gitlab.com/qemu-project/qemu/-/blob/master/hw/i386/microvm.c)
- [Firecracker kernel configs](https://github.com/firecracker-microvm/firecracker/tree/main/resources/guest_configs)

## References

- [QEMU microvm docs](https://www.qemu.org/docs/master/system/i386/microvm.html)
- [Ubuntu microvm docs](https://ubuntu.com/server/docs/explanation/virtualisation/qemu-microvm/)
- [Proxmox `qemu-server` source](https://git.proxmox.com/git/qemu-server.git)
- [Proxmox Developer Documentation](https://pve.proxmox.com/wiki/Developer_Documentation)
- [virtio-mmio specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html)
