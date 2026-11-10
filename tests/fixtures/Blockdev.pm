# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2011-2026 Proxmox Server Solutions GmbH
# See AGPL-3.0.txt in this directory.
# Extracted from proxmox/qemu-server (AGPL-3.0-or-later), commit
# 27e51213d75e9fdf067153c8008794e84d69af8a, src/PVE/QemuServer/Blockdev.pm.
# Only mapping and resize routines are needed for dependency-free regression tests.
package PVE::QemuServer::Blockdev;
use strict;
use warnings;

sub qdev_id_to_drive_id {
    my ($qdev_id) = @_;

    if ($qdev_id =~ m|^/machine/peripheral/(virtio(\d+))/virtio-backend$|) {
        return $1;
    } elsif ($qdev_id =~ m{^/machine/(?:system|virt)\.flash0$}) {
        return 'pflash0';
    } elsif ($qdev_id =~ m{^/machine/(?:system|virt)\.flash1$}) {
        return 'efidisk0';
    }

    return $qdev_id; # for SCSI/SATA/IDE it's the same
}


sub get_block_info {
    my ($vmid) = @_;

    my $block_info = {};

    my $qmp_block_info = mon_cmd($vmid, "query-block");
    for my $info ($qmp_block_info->@*) {
        my $qdev_id = $info->{qdev} or next;
        my $drive_id = qdev_id_to_drive_id($qdev_id);
        $block_info->{$drive_id} = $info;
    }

    return $block_info;
}


sub resize {
    my ($vmid, $deviceid, $storecfg, $volid, $size) = @_;

    my $running = PVE::QemuServer::Helpers::vm_running_locally($vmid);

    PVE::Storage::volume_resize($storecfg, $volid, $size, $running);

    return if !$running;

    my $block_info = get_block_info($vmid);
    my $drive_id = $deviceid =~ s/^drive-//r;
    my $inserted = $block_info->{$drive_id}->{inserted}
        or die "no block node inserted for drive '$drive_id'\n";

    my $padding = (1024 - $size % 1024) % 1024;
    $size = $size + $padding;

    mon_cmd(
        $vmid,
        "block_resize",
        # Need to use the top throttle node, not the node below, because QEMU won't update the size
        # of the top node otherwise, even though it's a filter node (as of QEMU 10.0). For legacy
        # -drive, there is no top throttle node, so this also is the correct node.
        'node-name' => "$inserted->{'node-name'}",
        size => int($size),
        timeout => 60,
    );
}

1;
