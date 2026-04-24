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
│   ├── pve-microvm.postinst          # Apply patches + dpkg trigger
│   ├── pve-microvm.prerm             # Revert patches
│   ├── pve-microvm.triggers          # Watch qemu-server files
│   └── patches/
├── docs/                             # Documentation
│   ├── pve-microvm-demo.gif
│   ├── installation.md
│   ├── usage.md
│   ├── architecture.md
│   ├── configuration.md
│   ├── known-issues.md
│   ├── limitations.md
│   ├── troubleshooting.md
│   └── development.md
├── doc/                              # Config templates
│   ├── microvm-defaults.conf
│   └── microvm-images.conf
├── kernel/                           # Kernel build
│   ├── pve-microvm-6.12.config       # Overlay on defconfig
│   ├── build-kernel.sh               # Automated build
│   └── README.md
├── tools/                            # Runtime tools
│   ├── MicroVM.pm                    # Perl module
│   ├── microvm-init                  # Init for minimal images
│   ├── microvm-setup                 # First-boot package installer
│   ├── pve-microvm-patch             # Patch manager
│   ├── pve-microvm-template          # Template creator
│   ├── pve-oci-import                # OCI importer
│   ├── pve-microvm-share             # virtiofs share manager
│   ├── pve-microvm-9p               # 9p share manager (no daemon)
│   ├── pve-microvm-ssh-agent         # SSH agent forwarder
│   ├── pve-microvm-run               # Ephemeral VM runner
│   └── pve-microvm-bench             # Boot time benchmarking
├── ui/                               # Web UI extensions
│   ├── pve-microvm.css               # Icon + tag styles
│   └── pve-microvm.js                # Wizard, hardware view, clone menu
└── .github/workflows/
    ├── ci.yml                        # Build on push/PR
    └── build.yml                     # Release on tag
```

## Building

```bash
# Build .deb (without kernel)
dpkg-buildpackage -us -uc -b

# Build kernel + initrd
cd kernel && ./build-kernel.sh

# Full release (done by CI on tag push)
git tag -a v0.X.Y -m "..." && git push origin v0.X.Y
```

## Testing locally

```bash
scp tools/MicroVM.pm root@pve:/usr/share/perl5/PVE/QemuServer/MicroVM.pm
scp ui/pve-microvm.js root@pve:/usr/share/pve-manager/js/pve-microvm.js
ssh root@pve qm create 999 --machine microvm --memory 128
ssh root@pve qm destroy 999
```

## Key source references

- `tools/MicroVM.pm` — QEMU command generation, device selection, config validation
- `tools/pve-microvm-patch` — Python-based patching of Machine.pm and QemuServer.pm
- `ui/pve-microvm.js` — ExtJS monkey-patches for PVE web UI
- `kernel/build-kernel.sh` — defconfig + overlay + module + initrd build
- `kernel/pve-microvm-6.12.config` — kernel config overlay

## References

- [QEMU microvm docs](https://www.qemu.org/docs/master/system/i386/microvm.html)
- [Proxmox `qemu-server` source](https://git.proxmox.com/git/qemu-server.git)
- [Proxmox `pve-manager` source](https://git.proxmox.com/git/pve-manager.git)
- [virtio-mmio specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html)
