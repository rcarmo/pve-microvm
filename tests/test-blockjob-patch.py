#!/usr/bin/env python3
"""Execute the installed BlockJob transform and mirror dispatch without PVE."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
if not os.environ.get('PVE_MICROVM_RUN_DIR'):
    raise SystemExit(subprocess.run(['bash', str(ROOT / 'tools/pve-microvm-env.sh'),
                                    '--exec', 'tests', sys.executable, *sys.argv]).returncode)
os.chdir(ROOT)
patcher = (ROOT / 'tools/pve-microvm-patch').read_text()
code = patcher.split("<< 'PATCHBLOCKJOB'\n", 1)[1].split('\nPATCHBLOCKJOB', 1)[0]
original = '''package PVE::QemuServer::BlockJob;
use strict;
use warnings;
sub mirror {
    my ($source, $dest, $jobs, $completion, $options) = @_;
    my $machine_type = PVE::QemuServer::Machine::get_current_qemu_machine($source->{vmid});
    if (PVE::QemuServer::Machine::is_machine_version_at_least($machine_type, 10, 0)) {
        blockdev_mirror($source, $dest, $jobs, $completion, $options);
    } else {
        my $drive_id = PVE::QemuServer::Drive::get_drive_id($source->{drive});
        qemu_drive_mirror(
            $source->{vmid}, $drive_id, $dest->{volid}, $dest->{vmid},
            $dest->{'zero-initialized'}, $jobs, $completion,
            $options->{'guest-agent'}, $options->{bwlimit}, $source->{bitmap},
        );
    }
}
1;
'''
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'BlockJob.pm'
    transform = re.sub(r'^path = .*$', f'path = {str(path)!r}', code, flags=re.M)
    def apply(text, check=False):
        path.write_text(text)
        result = subprocess.run(['python3', '-c', transform, *(['--check'] if check else [])],
                                capture_output=True, text=True)
        return result, path.read_text()
    result, untouched = apply(original, check=True)
    assert result.returncode == 0 and untouched == original
    result, patched = apply(original)
    assert result.returncode == 0
    result, twice = apply(patched)
    assert result.returncode == 0 and twice == patched
    manual = original.replace('if (PVE::', "if ($machine_type ne 'microvm' && PVE::", 1)
    result, normalised = apply(manual)
    assert result.returncode == 0 and normalised == patched
    for bad in (original.replace('sub mirror {', 'sub another {'),
                original.replace('10, 0', '11, 0'),
                original.replace('        qemu_drive_mirror(', '        incompatible_mirror('),
                original + original):
        result, unchanged = apply(bad)
        assert result.returncode != 0 and unchanged == bad
    # Run the actual patched mirror subroutine with version-parser and mirror stubs.
    # The parser dies for any unversioned machine; only exact microvm may bypass it.
    path.write_text(patched)
    perl = '''
use strict; use warnings; use Test::More;
package PVE::QemuServer::Machine;
our $machine; our $calls = 0;
sub get_current_qemu_machine { return $machine; }
sub is_machine_version_at_least {
    $calls++;
    die "unable to parse machine version" unless $_[0] =~ /-(\\d+)\\.(\\d+)/;
    return $1 >= 10;
}
package PVE::QemuServer::Drive;
sub get_drive_id { return "drive-$_[0]"; }
package PVE::QemuServer::BlockJob;
our @drive_args; our @block_args;
sub blockdev_mirror { @block_args = @_; }
sub qemu_drive_mirror { @drive_args = @_; }
package main;
require $ARGV[0];
my $source = {vmid=>123, drive=>'scsi0', bitmap=>'bitmap'};
my $dest = {vmid=>124, volid=>'local-lvm:vm-124-disk-0', 'zero-initialized'=>1};
my $jobs = {}; my $options = {'guest-agent'=>1, bwlimit=>17};
for my $case (['microvm',0,'drive'], ['pc-i440fx-9.2+pve0',1,'drive'],
              ['pc-q35-10.0+pve0',1,'block'], ['virt-10.0',1,'block']) {
    $PVE::QemuServer::Machine::machine = $case->[0];
    $PVE::QemuServer::Machine::calls = 0;
    @PVE::QemuServer::BlockJob::drive_args=(); @PVE::QemuServer::BlockJob::block_args=();
    PVE::QemuServer::BlockJob::mirror($source,$dest,$jobs,'complete',$options);
    Test::More::is($PVE::QemuServer::Machine::calls,$case->[1],"$case->[0] version parser calls");
    if ($case->[2] eq 'drive') {
        Test::More::is_deeply(\\@PVE::QemuServer::BlockJob::drive_args,
            [123,'drive-scsi0','local-lvm:vm-124-disk-0',124,1,$jobs,'complete',1,17,'bitmap'],
            "$case->[0] preserves drive mirror arguments");
    } else {
        Test::More::is_deeply(\\@PVE::QemuServer::BlockJob::block_args,
            [$source,$dest,$jobs,'complete',$options], "$case->[0] retains blockdev mirror");
    }
}
for my $bad ('microvm-invalid','unversioned') {
    $PVE::QemuServer::Machine::machine=$bad;
    eval { PVE::QemuServer::BlockJob::mirror($source,$dest,$jobs,'complete',$options); };
    Test::More::like($@,qr/unable to parse machine version/,"$bad still fails version validation");
}
Test::More::done_testing();
'''
    subprocess.run(['perl', '-e', perl, str(path)], check=True)

assert '/usr/share/perl5/PVE/QemuServer/BlockJob.pm' in (ROOT / 'debian/pve-microvm.triggers').read_text()
print('BlockJob layout refusal, dry-run, idempotency and mirror dispatch passed')

# Execute apply/reapply/rollback against an isolated filesystem. Exercise both
# pristine installs and upgrades where Machine/QS are already stamped.
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    upstream = root / 'usr/share/perl5/PVE/QemuServer'
    upstream.mkdir(parents=True)
    source = root / 'usr/share/pve-microvm'
    (source / 'ui').mkdir(parents=True)
    manager = root / 'usr/share/pve-manager'
    (manager / 'css').mkdir(parents=True)
    (manager / 'js').mkdir()
    (manager / 'index.html.tpl').write_text('<html>\n<head>\n</head>\n</html>\n')
    (source / 'MicroVM.pm').write_text('# deployed module\n')
    for asset in ('pve-microvm.js', 'pve-microvm.css'):
        (source / 'ui' / asset).write_text('fixture\n')
    machine = ("my $pattern = qr/(virt(?:-\\d+(\\.\\d+)+)?(\\+pve\\d+)?)/;\n"
               "sub machine_base_type {\n    return 'virt' if $machine_type =~ m/^virt/;\n}\n"
               "my $flags = {\n    virt => {},\n};\n"
               "sub get_vm_machine {\n    if ($machine !~ m/\\+pve\\d+?(?:\\.pxe)?$/) {\n    }\n}\n")
    qs = 'use PVE::QemuServer::Machine;\nsub config_to_command {\n}\n'
    machine_path = upstream / 'Machine.pm'
    qs_path = upstream.parent / 'QemuServer.pm'
    block_path = upstream / 'BlockJob.pm'
    hook = root / 'patch'
    hook.write_text(patcher.replace('/usr/share/', str(root / 'usr/share') + '/'))
    for kind in ('fresh', 'legacy'):
        machine_path.write_text(machine)
        qs_path.write_text(qs)
        block_path.write_text(original)
        (source / '.applied').unlink(missing_ok=True)
        backup = source / 'backup'
        if backup.exists():
            import shutil
            shutil.rmtree(backup)
        if kind == 'legacy':
            # Match a 0.3.28 stamped installation, without creating a modern
            # manifest that would bless its historical backups.
            functions = hook.read_text().split('cmd_apply() {')[0]
            subprocess.run(['bash', '-c', functions + '\npatch_machine\npatch_qemu_server'],
                           check=True, capture_output=True)
            (source / '.applied').write_text('legacy')
            backup.mkdir()
            (backup / 'Machine.pm.orig').write_text('stale')
            (backup / 'QemuServer.pm.orig').write_text('stale')
        subprocess.run(['bash', str(hook), 'apply'], check=True, capture_output=True)
        assert "pve-microvm: unversioned microvm uses -drive" in block_path.read_text()
        assert (backup / 'BlockJob.pm.orig').read_text() == original
        subprocess.run(['sha256sum', '-c', str(backup / 'blockjob.sha256')], check=True,
                       capture_output=True)
        once = [p.read_text() for p in (machine_path, qs_path, block_path)]
        manifest = (backup / 'blockjob.sha256').read_text()
        subprocess.run(['bash', str(hook), 'apply'], check=True, capture_output=True)
        assert once == [p.read_text() for p in (machine_path, qs_path, block_path)]
        assert manifest == (backup / 'blockjob.sha256').read_text()
        # File-trigger replacement of just BlockJob must leave the stamped
        # fast path and reapply safely, pairing the new pristine original.
        replacement = original.replace('use warnings;', 'use warnings;\n# upstream update')
        block_path.write_text(replacement)
        subprocess.run(['bash', str(hook), 'apply'], check=True, capture_output=True)
        assert (backup / 'BlockJob.pm.orig').read_text() == replacement
        assert 'upstream update' in block_path.read_text()
        if kind == 'legacy':
            assert not (backup / 'patched.sha256').exists()
            prior = machine_path.read_text()
            result = subprocess.run(['bash', str(hook), 'revert'], capture_output=True)
            assert result.returncode != 0 and machine_path.read_text() == prior
        else:
            # A changed backup/live file must refuse restoration before any
            # upstream files or deployed module are removed.
            block_path.write_text(block_path.read_text() + '# admin change\n')
            prior = machine_path.read_text()
            result = subprocess.run(['bash', str(hook), 'revert'], capture_output=True)
            assert result.returncode != 0 and machine_path.read_text() == prior
            block_path.write_text(block_path.read_text().removesuffix('# admin change\n'))
            subprocess.run(['bash', str(hook), 'revert'], check=True, capture_output=True)
            assert block_path.read_text() == replacement
            assert machine_path.read_text() == machine and qs_path.read_text() == qs
print('BlockJob fresh/legacy upgrade, stamped apply, replacement and verified rollback passed')
