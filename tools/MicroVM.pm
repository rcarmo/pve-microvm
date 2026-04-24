package PVE::QemuServer::MicroVM;

use strict;
use warnings;

use PVE::QemuServer::Helpers;
use PVE::QemuServer::Machine;
use PVE::QemuServer::Drive;
use PVE::QemuServer::Network;
use PVE::QemuServer::Agent;
use PVE::Storage;
use PVE::Tools qw(run_command);

use base 'Exporter';
our @EXPORT_OK = qw(is_microvm microvm_config_to_command microvm_validate_config);

=head1 NAME

PVE::QemuServer::MicroVM - QEMU microvm machine type support for Proxmox VE

=head1 DESCRIPTION

Provides command-line generation and config validation for QEMU's microvm
machine type. microvm guests use virtio-mmio devices instead of PCI, have
no VGA/ACPI/USB, and boot via direct kernel loading.

=cut

# Features that are NOT supported on microvm — error if explicitly set
my @UNSUPPORTED_OPTIONS = qw(
    bios tablet audio0 hostpci0 hostpci1 hostpci2 hostpci3
    usb0 usb1 usb2 usb3 usb4 usb5 usb6 usb7 usb8 usb9
    tpmstate0 efidisk0 rng0 parallel0 parallel1 parallel2
);

# Options silently ignored on microvm (auto-set by qm create, harmless)
my @IGNORED_OPTIONS = qw(
    vmgenid smbios1
);

# VGA values allowed on microvm (serial console redirect, or none)
my %ALLOWED_VGA = map { $_ => 1 } qw(serial0 serial1 serial2 serial3 none);

=head2 is_microvm($conf)

Returns true if the VM configuration uses the microvm machine type.

=cut

sub is_microvm {
    my ($conf) = @_;
    my $machine_conf = PVE::QemuServer::Machine::parse_machine($conf->{machine});
    return 0 if !$machine_conf || !$machine_conf->{type};
    return $machine_conf->{type} =~ m/^microvm/ ? 1 : 0;
}

=head2 microvm_validate_config($conf)

Dies if the configuration contains options incompatible with microvm.

=cut

sub microvm_validate_config {
    my ($conf) = @_;

    return if !is_microvm($conf);

    for my $opt (@UNSUPPORTED_OPTIONS) {
        die "option '$opt' is not supported with microvm machine type\n"
            if defined($conf->{$opt});
    }

    # VGA: only serial redirect or none is allowed (no actual VGA hardware)
    if (defined($conf->{vga})) {
        my $vga_type = $conf->{vga};
        $vga_type =~ s/,.*//;  # strip options like memory=X
        if (!$ALLOWED_VGA{$vga_type}) {
            die "vga '$vga_type' is not supported with microvm — use 'serial0' or 'none'\n";
        }
    }

    # Silently strip options that qm create auto-sets but microvm doesn't use
    for my $opt (@IGNORED_OPTIONS) {
        delete $conf->{$opt} if defined($conf->{$opt});
    }

    # Ensure serial0 is set so `qm terminal` can find the serial interface
    $conf->{serial0} = 'socket' if !defined($conf->{serial0});


    # microvm requires a kernel specified in args
    die "microvm requires a kernel — set 'args: -kernel /path/to/vmlinuz' in VM config\n"
        if !$conf->{args} || $conf->{args} !~ m/-kernel/;

    return;
}

=head2 microvm_config_to_command($storecfg, $vmid, $conf, $defaults, $options)

Generate the QEMU command line for a microvm guest. This is a stripped-down
version of the main config_to_command that skips PCI, VGA, ACPI, USB, BIOS,
and other features not supported by the microvm machine type.

Returns ($cmd, $vollist) where $cmd is an arrayref of command-line arguments
and $vollist is an arrayref of storage volume IDs used.

=cut

sub microvm_config_to_command {
    my ($storecfg, $vmid, $conf, $defaults, $options) = @_;

    my ($forcemachine, $forcecpu) =
        $options->@{qw(force-machine force-cpu)};

    microvm_validate_config($conf);

    my $cmd = [];
    my $vollist = [];

    my $arch = PVE::QemuServer::Helpers::get_vm_arch($conf);
    my $kvm_binary = PVE::QemuServer::Helpers::get_command_for_arch($arch);
    my $kvm = $conf->{kvm} // 1;

    # CPU affinity
    if ($conf->{affinity}) {
        push @$cmd, '/usr/bin/taskset', '--cpu-list', '--all-tasks', $conf->{affinity};
    }

    push @$cmd, $kvm_binary;
    push @$cmd, '-id', $vmid;

    my $vmname = $conf->{name} || "vm$vmid";
    push @$cmd, '-name', "$vmname,debug-threads=on";

    # microvm machine type with minimal features enabled
    # isa-serial=on  — needed for serial console
    # rtc=on         — needed for timekeeping
    # pit/pic=off    — not needed, reduces attack surface
    # microvm with PCIe enabled — virtio-mmio device discovery is broken
    # on kernel 6.12 built from Firecracker 6.1 config (only virtio-blk probes).
    # PCIe mode adds ~50ms but ALL virtio devices work reliably via PCI transport.
    push @$cmd, '-M', 'microvm,x-option-roms=off,pit=off,pic=off,isa-serial=on,rtc=on,acpi=on,pcie=on';

    # Use qboot for instant kernel loading (no SeaBIOS banner)
    my $qboot = '/usr/share/kvm/qboot.rom';
    if (-f $qboot) {
        push @$cmd, '-bios', $qboot;
    }

    push @$cmd, '-no-shutdown';
    push @$cmd, '-nodefaults';
    push @$cmd, '-no-user-config';
    push @$cmd, '-nographic';

    # KVM acceleration
    if ($kvm) {
        if (!defined PVE::QemuServer::kvm_version()) {
            die "KVM virtualisation configured, but not available.\n";
        }
        push @$cmd, '-enable-kvm';
    }

    # QMP socket — required for qm monitor/status/stop
    my $qmpsocket = PVE::QemuServer::Helpers::qmp_socket(
        { name => "VM $vmid", id => $vmid, type => 'qmp' }
    );
    push @$cmd, '-chardev', "socket,id=qmp,path=$qmpsocket,server=on,wait=off";
    push @$cmd, '-mon', "chardev=qmp,mode=control";

    # PID file — required for PVE process tracking
    push @$cmd, '-pidfile', PVE::QemuServer::Helpers::vm_pidfile_name($vmid);
    push @$cmd, '-daemonize';

    # ── CPU ──────────────────────────────────────────────────────
    my $sockets = $conf->{sockets} || 1;
    my $cores = $conf->{cores} || 1;
    my $maxcpus = $sockets * $cores;
    my $vcpus = $conf->{vcpus} || $maxcpus;
    push @$cmd, '-smp', "$vcpus,sockets=$sockets,cores=$cores,maxcpus=$maxcpus";

    if ($forcecpu) {
        push @$cmd, '-cpu', $forcecpu;
    } elsif ($kvm) {
        push @$cmd, '-cpu', 'host';
    }

    # ── Memory ───────────────────────────────────────────────────
    my $memory = $conf->{memory} || 512;
    push @$cmd, '-m', "${memory}M";

    # ── Balloon device ───────────────────────────────────────────
    # virtio-balloon-pci-non-transitional suppresses the PVE post-start
    # balloon warning and enables memory reporting.
    push @$cmd, '-device', 'virtio-balloon-pci-non-transitional,id=balloon0';

    # ── Serial console ───────────────────────────────────────────
    # Primary console for microvm — accessible via `qm terminal $vmid`
    my $serial_socket = "/var/run/qemu-server/${vmid}.serial0";
    push @$cmd, '-chardev', "socket,id=serial0,path=$serial_socket,server=on,wait=off";
    push @$cmd, '-serial', 'chardev:serial0';

    # ── Guest agent (optional) ───────────────────────────────────
    my $guest_agent = PVE::QemuServer::Agent::parse_guest_agent($conf);
    if ($guest_agent->{enabled}) {
        my $qgasocket = PVE::QemuServer::Helpers::qmp_socket(
            { name => "VM $vmid", id => $vmid, type => 'qga' }
        );
        push @$cmd, '-chardev', "socket,path=$qgasocket,server=on,wait=off,id=qga0";
        push @$cmd, '-device', 'virtio-serial-pci-non-transitional';
        push @$cmd, '-device', 'virtserialport,chardev=qga0,name=org.qemu.guest_agent.0';
    }

    # ── Block devices ────────────────────────────────────────────
    # Use virtio-blk-pci-non-transitional (virtio-mmio.
    # Supports all PVE storage backends: local dir, LVM, LVM-thin, ZFS,
    # Ceph/RBD, NFS, CIFS, GlusterFS — anything PVE::Storage::path() resolves.
    #
    # Storage type → what QEMU sees:
    #   local dir   → /var/lib/vz/images/<vmid>/vm-<vmid>-disk-0.qcow2
    #   LVM         → /dev/<vg>/vm-<vmid>-disk-0              (raw block)
    #   LVM-thin    → /dev/<vg>/vm-<vmid>-disk-0              (raw block)
    #   ZFS         → /dev/zvol/<pool>/vm-<vmid>-disk-0       (raw block)
    #   Ceph/RBD    → rbd:<pool>/vm-<vmid>-disk-0             (librbd)
    #   NFS/CIFS    → /mnt/pve/<store>/images/<vmid>/...      (file)
    for my $ds (PVE::QemuServer::Drive::valid_drive_names()) {
        next if !$conf->{$ds};
        next if $ds =~ m/^(efidisk|tpmstate)/;

        my $drive = PVE::QemuServer::Drive::parse_drive($ds, $conf->{$ds});
        next if !$drive;

        my $volid = $drive->{file};
        next if !$volid;
        next if PVE::QemuServer::Drive::drive_is_cdrom($drive, 1);

        my ($path, $format);
        my $is_rbd = 0;
        my $scfg;

        if ($volid =~ m|^/|) {
            # Absolute path (raw file or block device)
            $path = $volid;
            $format = $drive->{format} || 'raw';
        } else {
            # PVE-managed volume — resolve through storage layer
            my ($storeid) = PVE::Storage::parse_volume_id($volid, 1);
            $scfg = $storeid ? PVE::Storage::storage_config($storecfg, $storeid) : undef;

            ($path, undef) = PVE::Storage::path($storecfg, $volid);
            push @$vollist, $volid;

            $is_rbd = ($path =~ m/^rbd:/) ? 1 : 0;

            # Determine format: explicit > storage-detected > raw
            $format = $drive->{format};
            if (!$format) {
                eval { $format = PVE::Storage::volume_format($storecfg, $volid); };
                $format //= 'raw';
            }
            $format = 'rbd' if $is_rbd && !$drive->{format};
        }

        # Build -drive line
        my $drive_cmd;
        if ($is_rbd) {
            # RBD uses its own driver, path is the rbd: URI
            $drive_cmd = "file=$path,id=drive-$ds,if=none,format=rbd";
        } else {
            $drive_cmd = "file=$path,id=drive-$ds,if=none";
            $drive_cmd .= ",format=$format" if $format;
        }

        # Cache: use cache=none for block devices and direct-IO capable storage
        my $cache_direct = 0;
        if ($scfg) {
            $cache_direct = PVE::QemuServer::Drive::drive_uses_cache_direct($drive, $scfg);
        } elsif (-b $path || $is_rbd) {
            # Block device or RBD — always direct
            $cache_direct = 1;
        }
        $drive_cmd .= ",cache=none" if $cache_direct && !$drive->{cache};
        $drive_cmd .= ",cache=$drive->{cache}" if $drive->{cache};

        # AIO backend
        if ($scfg) {
            my $aio = PVE::QemuServer::Drive::aio_cmdline_option($scfg, $drive, $cache_direct);
            $drive_cmd .= ",aio=$aio";
        } elsif ($cache_direct) {
            # Default: io_uring if available, native otherwise
            my $aio = (-e '/sys/module/io_uring') ? 'io_uring' : 'native';
            $drive_cmd .= ",aio=$aio";
        }

        $drive_cmd .= ",detect-zeroes=on" if !PVE::QemuServer::Drive::drive_is_cdrom($drive, 1);

        # Throttling
        foreach my $type (['', '-total'], [_rd => '-read'], [_wr => '-write']) {
            my ($dir, $qmpname) = @$type;
            if (my $v = $drive->{"mbps$dir"}) {
                $drive_cmd .= ",throttling.bps$qmpname=" . int($v * 1024 * 1024);
            }
            if (my $v = $drive->{"iops$dir"}) {
                $drive_cmd .= ",throttling.iops$qmpname=$v";
            }
        }

        push @$cmd, '-drive', $drive_cmd;
        push @$cmd, '-device', "virtio-blk-pci-non-transitional,drive=drive-$ds";
    }

    # ── Network ──────────────────────────────────────────────────
    # Use virtio-net-pci-non-transitional (virtio-mmio
    for (my $i = 0; $i < 6; $i++) {
        my $netkey = "net$i";
        next if !$conf->{$netkey};

        my $net = PVE::QemuServer::Network::parse_net($conf->{$netkey});
        next if !$net;

        my $tapname = "tap${vmid}i${i}";
        my $netdev_cmd = "tap,id=netdev$i,ifname=$tapname";
        $netdev_cmd .= ",script=/usr/libexec/qemu-server/pve-bridge";
        $netdev_cmd .= ",downscript=/usr/libexec/qemu-server/pve-bridgedown";
        push @$cmd, '-netdev', $netdev_cmd;

        my $device_cmd = "virtio-net-pci-non-transitional,netdev=netdev$i";
        $device_cmd .= ",mac=$net->{macaddr}" if $net->{macaddr};
        push @$cmd, '-device', $device_cmd;
    }

    # ── vsock (host↔guest fast communication) ──────────────────
    # vsock provides a direct socket channel between host and guest
    # without requiring networking. CID is vmid + 1000 to avoid conflicts.
    # Guest uses: socat - VSOCK-CONNECT:2:<port>  (CID 2 = host)
    # Host uses:  socat - VSOCK-CONNECT:<cid>:<port>
    if (-e '/dev/vhost-vsock') {
        my $cid = $vmid + 1000;  # unique CID per VM
        push @$cmd, '-device', "vhost-vsock-pci-non-transitional,guest-cid=$cid";
    }

    # ── 9p filesystem sharing (QEMU built-in, no daemon needed) ────
    # Check for 9p share config: /var/run/pve-microvm/<vmid>-9p.conf
    # Each line: <tag> <host-path> [security_model]
    # Guest mounts with: mount -t 9p <tag> /mnt/<tag> -o trans=virtio,version=9p2000.L
    my $ninep_conf = "/var/run/pve-microvm/${vmid}-9p.conf";
    if (-f $ninep_conf) {
        my $ninep_id = 0;
        open(my $fh, '<', $ninep_conf) or warn "Cannot read $ninep_conf: $!";
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /^\s*#/ || $line =~ /^\s*$/;
            my ($tag, $path, $secmodel) = split(/\s+/, $line, 3);
            $secmodel //= 'mapped-xattr';
            next unless $tag && $path && -d $path;
            push @$cmd, '-fsdev', "local,id=fsdev${ninep_id},path=${path},security_model=${secmodel}";
            push @$cmd, '-device', "virtio-9p-pci-non-transitional,fsdev=fsdev${ninep_id},mount_tag=${tag}";
            $ninep_id++;
        }
        close($fh);
    }

    # ── virtiofs (shared host directories via virtiofsd) ──────────
    # Higher performance than 9p but requires virtiofsd daemon.
    # Guest mounts with: mount -t virtiofs shared /mnt/shared
    my $virtiofs_socket = "/var/run/pve-microvm/${vmid}-virtiofs.sock";
    if (-S $virtiofs_socket) {
        push @$cmd, '-chardev', "socket,id=virtiofs0,path=$virtiofs_socket";
        push @$cmd, '-device', 'vhost-user-fs-pci,queue-size=1024,chardev=virtiofs0,tag=shared';
        push @$cmd, '-object', 'memory-backend-memfd,id=mem,size=' . ($conf->{memory} || 512) . 'M,share=on';
        push @$cmd, '-numa', 'node,memdev=mem';
    }

    # ── Kernel / initrd / cmdline ────────────────────────────────
    # Passed through from the args config option.
    # Expected format:
    #   args: -kernel /path/to/vmlinuz -append "console=ttyS0 root=/dev/vda rw" [-initrd /path/to/initrd]
    # Must handle quoted strings properly (e.g. -append "..." is one argument).
    if ($conf->{args}) {
        my $args_str = $conf->{args};

        # Auto-inject initrd if using shipped kernel and no -initrd specified
        if ($args_str =~ m|-kernel /usr/share/pve-microvm/vmlinuz| && $args_str !~ m|-initrd|) {
            if (-f '/usr/share/pve-microvm/initrd') {
                $args_str =~ s|(-kernel /usr/share/pve-microvm/vmlinuz)|$1 -initrd /usr/share/pve-microvm/initrd|;
                # Also inject rdinit=/init if not present
                if ($args_str !~ m|rdinit=|) {
                    $args_str =~ s|console=ttyS0|rdinit=/init console=ttyS0|;
                }
            }
        }

        # Parse respecting double-quoted strings
        my @args;
        while ($args_str =~ /\G\s*("[^"]*"|\S+)/g) {
            my $arg = $1;
            $arg =~ s/^"(.*)"$/$1/;  # strip outer quotes
            push @args, $arg;
        }
        push @$cmd, @args;
    }

    return wantarray ? ($cmd, $vollist) : $cmd;
}

1;

__END__

=head1 EXAMPLES

Create a microvm guest:

  qm create 900 --machine microvm --memory 256 --cores 1 \
    --net0 virtio,bridge=vmbr0 \
    --scsi0 local-lvm:8 \
    --args '-kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw"'

  qm start 900
  qm terminal 900

=head1 LIMITATIONS

- No VGA/display (serial console only)
- No PCI passthrough
- No USB devices
- No UEFI/Secure Boot
- No ACPI (use QMP for shutdown)
- Direct kernel boot only (no BIOS)
- CD-ROM drives are ignored

=cut
