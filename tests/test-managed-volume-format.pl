#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    for my $module (qw(
        PVE::QemuServer::Helpers PVE::QemuServer::Machine
        PVE::QemuServer::Drive PVE::QemuServer::Network
        PVE::QemuServer::Agent PVE::Storage PVE::Tools
    )) {
        $INC{join('/', split(/::/, $module)) . '.pm'} = 1;
    }

    package PVE::Tools;
    sub import { }

    package PVE::Storage;
    our %formats;
    sub import { }
    sub parse_volname {
        my ($storecfg, $volid) = @_;
        die "mock parse failure" if $volid eq 'broken:vm-100-disk-0';
        return ('images', $volid, 100, undef, undef, 0, $formats{$volid});
    }

    for my $module (qw(
        PVE::QemuServer::Helpers PVE::QemuServer::Machine
        PVE::QemuServer::Drive PVE::QemuServer::Network PVE::QemuServer::Agent
    )) {
        no strict 'refs';
        *{"${module}::import"} = sub { };
    }
}

require './tools/MicroVM.pm';

$PVE::Storage::formats{'local-lvm:vm-100-disk-0'} = 'raw';
$PVE::Storage::formats{'local:100/base-100-disk-0.qcow2/101/vm-101-disk-0.qcow2'} = 'qcow2';
$PVE::Storage::formats{'rbd:vm-100-disk-0'} = 'raw';

is(
    PVE::QemuServer::MicroVM::_managed_volume_format(
        {}, 'local-lvm:vm-100-disk-0', undef, 0,
    ),
    'raw',
    'LVM-thin volume remains raw',
);

is(
    PVE::QemuServer::MicroVM::_managed_volume_format(
        {}, 'local:100/base-100-disk-0.qcow2/101/vm-101-disk-0.qcow2', undef, 0,
    ),
    'qcow2',
    'file-backed linked clone is detected as qcow2',
);

is(
    PVE::QemuServer::MicroVM::_managed_volume_format(
        {}, 'rbd:vm-100-disk-0', undef, 1,
    ),
    'rbd',
    'RBD path uses rbd format',
);

is(
    PVE::QemuServer::MicroVM::_managed_volume_format(
        {}, 'local:vm-100-disk-0', 'vmdk', 0,
    ),
    'vmdk',
    'explicit drive format has priority',
);

$PVE::Storage::formats{'unknown:vm-100-disk-0'} = undef;
eval {
    PVE::QemuServer::MicroVM::_managed_volume_format(
        {}, 'unknown:vm-100-disk-0', undef, 0,
    );
};
like($@, qr/unable to detect disk format/, 'missing format fails closed');

eval {
    PVE::QemuServer::MicroVM::_managed_volume_format(
        {}, 'broken:vm-100-disk-0', undef, 0,
    );
};
like($@, qr/mock parse failure/, 'storage parser errors are not swallowed');

done_testing();
