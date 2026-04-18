package PVE::QemuServer::MicroVM;

use strict;
use warnings;

use PVE::QemuServer::Helpers;
use PVE::QemuServer::Machine;
use PVE::QemuServer::Drive;
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

# Features that are NOT supported on microvm
my @UNSUPPORTED_OPTIONS = qw(
    bios vga tablet audio0 hostpci0 hostpci1 hostpci2 hostpci3
    usb0 usb1 usb2 usb3 usb4 usb5 usb6 usb7 usb8 usb9
    vmgenid tpmstate0 efidisk0 rng0 parallel0 parallel1 parallel2
);

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
    push @$cmd, '-M', 'microvm,x-option-roms=off,pit=off,pic=off,isa-serial=on,rtc=on';

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

    # ── Serial console ───────────────────────────────────────────
    # Primary console for microvm — accessible via `qm terminal $vmid`
    my $serial_socket = "/var/run/qemu-server/${vmid}.serial0";
    push @$cmd, '-chardev', "socket,id=serial0,path=$serial_socket,server=on,wait=off";
    push @$cmd, '-serial', 'chardev:serial0';

    # ── Guest agent (optional) ───────────────────────────────────
    my $guest_agent = PVE::QemuServer::parse_guest_agent($conf);
    if ($guest_agent->{enabled}) {
        my $qgasocket = PVE::QemuServer::Helpers::qmp_socket(
            { name => "VM $vmid", id => $vmid, type => 'qga' }
        );
        push @$cmd, '-chardev', "socket,path=$qgasocket,server=on,wait=off,id=qga0";
        push @$cmd, '-device', 'virtio-serial-device';
        push @$cmd, '-device', 'virtserialport,chardev=qga0,name=org.qemu.guest_agent.0';
    }

    # ── Block devices ────────────────────────────────────────────
    # Use virtio-blk-device (virtio-mmio) instead of PCI variants
    for my $ds (PVE::QemuServer::Drive::valid_drive_names()) {
        next if !$conf->{$ds};
        next if $ds =~ m/^(efidisk|tpmstate)/;

        my $drive = PVE::QemuServer::Drive::parse_drive($ds, $conf->{$ds});
        next if !$drive;

        my $volid = $drive->{file};
        next if !$volid;
        next if PVE::QemuServer::Drive::drive_is_cdrom($drive, 1);

        my $path;
        if ($volid =~ m|^/|) {
            $path = $volid;
        } else {
            $path = PVE::Storage::path($storecfg, $volid);
            push @$vollist, $volid;
        }

        my $format = $drive->{format} || PVE::Storage::volume_format($storecfg, $volid);

        my $drive_cmd = "file=$path,id=drive-$ds,if=none";
        $drive_cmd .= ",format=$format" if $format;
        $drive_cmd .= ",cache=none,detect-zeroes=on";
        $drive_cmd .= ",aio=io_uring" if -e '/sys/module/io_uring';

        push @$cmd, '-drive', $drive_cmd;
        push @$cmd, '-device', "virtio-blk-device,drive=drive-$ds";
    }

    # ── Network ──────────────────────────────────────────────────
    # Use virtio-net-device (virtio-mmio) instead of PCI variants
    for (my $i = 0; $i < 6; $i++) {
        my $netkey = "net$i";
        next if !$conf->{$netkey};

        my $net = PVE::QemuServer::parse_net($conf->{$netkey});
        next if !$net;

        my $tapname = "tap${vmid}i${i}";
        my $netdev_cmd = "tap,id=netdev$i,ifname=$tapname";
        $netdev_cmd .= ",script=/var/lib/qemu-server/pve-bridge";
        $netdev_cmd .= ",downscript=/var/lib/qemu-server/pve-bridgedown";
        push @$cmd, '-netdev', $netdev_cmd;

        my $device_cmd = "virtio-net-device,netdev=netdev$i";
        $device_cmd .= ",mac=$net->{macaddr}" if $net->{macaddr};
        push @$cmd, '-device', $device_cmd;
    }

    # ── Kernel / initrd / cmdline ────────────────────────────────
    # Passed through from the args config option.
    # Expected format:
    #   args: -kernel /path/to/vmlinuz -append "console=ttyS0 root=/dev/vda rw" [-initrd /path/to/initrd]
    if ($conf->{args}) {
        my @args = split(/\s+/, $conf->{args});
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
