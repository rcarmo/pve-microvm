#!/usr/bin/env python3
"""Exercise the installed transform and upstream mapping/resize routines."""
from pathlib import Path
import json
import os
import re
import shutil
import select
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
if not os.environ.get('PVE_MICROVM_RUN_DIR'):
    raise SystemExit(subprocess.run(['bash', str(ROOT / 'tools/pve-microvm-env.sh'),
                                    '--exec', 'tests', sys.executable, *sys.argv]).returncode)
os.chdir(ROOT)
patcher = (ROOT / 'tools/pve-microvm-patch').read_text()
assert 'python3 -S - "$@"' in patcher.split('patch_blockdev() {', 1)[1].split("<< 'PATCHBLOCKDEV'\n", 1)[0]
code = patcher.split("<< 'PATCHBLOCKDEV'\n", 1)[1].split('\nPATCHBLOCKDEV', 1)[0]
original = (ROOT / 'tests/fixtures/Blockdev.pm').read_text()

PERL = r'''
use strict; use warnings; use Test::More; use JSON::PP;
package PVE::QemuServer::Machine;
our $machine = 'microvm'; our $calls = 0;
sub get_current_qemu_machine { $calls++; return $machine; }
package PVE::QemuServer::Helpers;
our $running = 1;
sub vm_running_locally { return $running; }
package PVE::Storage;
our @resizes;
sub volume_resize { push @resizes, [@_]; }
package PVE::QemuServer::Blockdev;
our @commands; our $blocks;
sub mon_cmd {
    push @commands, [@_];
    return $blocks if $_[1] eq 'query-block';
    return {};
}
package main;
require $ARGV[0];
local $/; my $input = decode_json(<STDIN>);
$PVE::QemuServer::Blockdev::blocks = $input;
my $info = PVE::QemuServer::Blockdev::get_block_info(123);
is_deeply($info->{scsi0}, $input->[0], 'anonymous root backend maps to scsi0');
is_deeply($info->{scsi1}, $input->[1], 'read-only cloud-init maps separately');
is($PVE::QemuServer::Machine::calls, 1, 'machine queried once for multiple disks');
for my $disk (qw(virtio2 ide2 sata3)) {
    local $PVE::QemuServer::Blockdev::blocks = [{device=>"drive-$disk", inserted=>{'node-name'=>'disk'}}];
    ok(PVE::QemuServer::Blockdev::get_block_info(123)->{$disk}, "$disk without qdev maps by backend");
}
for my $bad ('drive-scsi0-extra', 'scsi0', 'drive-other0') {
    local $PVE::QemuServer::Blockdev::blocks = [{device=>$bad}];
    is_deeply(PVE::QemuServer::Blockdev::get_block_info(123), {}, 'unknown backend ignored');
}
for my $machine ('pc-q35-11.0+pve0', 'pc-i440fx-9.2+pve0', 'microvm-invalid') {
    local $PVE::QemuServer::Machine::machine = $machine;
    my $standard = PVE::QemuServer::Blockdev::get_block_info(123);
    ok(!exists($standard->{scsi0}), "$machine keeps upstream anonymous-qdev mapping");
    my $qdev = $input->[0]->{qdev};
    ok(exists($standard->{PVE::QemuServer::Blockdev::qdev_id_to_drive_id($qdev)}), 'original qdev key retained');
}
for my $qdev ('scsi0', '/machine/peripheral/virtio2/virtio-backend', '/machine/virt.flash1') {
    local $PVE::QemuServer::Blockdev::blocks = [{qdev=>$qdev, device=>'drive-scsi9'}];
    my $expected = PVE::QemuServer::Blockdev::qdev_id_to_drive_id($qdev);
    ok(exists(PVE::QemuServer::Blockdev::get_block_info(123)->{$expected}), 'named devices unchanged');
}
{
    local $PVE::QemuServer::Blockdev::blocks = [$input->[0], $input->[0]];
    eval { PVE::QemuServer::Blockdev::get_block_info(123); };
    like($@, qr/duplicate microvm block backend/, 'ambiguous backend refused');
}
@PVE::QemuServer::Blockdev::commands=(); @PVE::Storage::resizes=();
my $store = {storage=>'fixture'};
PVE::QemuServer::Blockdev::resize(123, 'drive-scsi0', $store, 'fixture:root', 2097153);
is_deeply(\@PVE::Storage::resizes, [[$store,'fixture:root',2097153,1]], 'storage resize arguments unchanged');
is_deeply($PVE::QemuServer::Blockdev::commands[-1],
    [123,'block_resize','node-name',$input->[0]->{inserted}->{'node-name'},size=>2098176,timeout=>60],
    'resize targets root node with upstream padding and timeout');
{
    local $PVE::QemuServer::Helpers::running = 0;
    @PVE::QemuServer::Blockdev::commands=();
    PVE::QemuServer::Blockdev::resize(123, 'drive-scsi0', $store, 'fixture:root', 3145728);
    is(scalar @PVE::QemuServer::Blockdev::commands, 0, 'stopped resize sends no QMP');
}
{
    local $PVE::QemuServer::Machine::machine = 'pc-q35-11.0+pve0';
    local $PVE::QemuServer::Blockdev::blocks = [{qdev=>'scsi0', inserted=>{'node-name'=>'throttle-top'}}];
    PVE::QemuServer::Blockdev::resize(123, 'drive-scsi0', $store, 'fixture:root', 4194304);
    is($PVE::QemuServer::Blockdev::commands[-1]->[3], 'throttle-top', 'conventional VM resizes top throttle node');
}
done_testing();
'''
fixture = [
    {'qdev': '/machine/peripheral-anon/device[0]/virtio-backend', 'device': 'drive-scsi0',
     'inserted': {'node-name': '#root', 'ro': False}},
    {'qdev': '/machine/peripheral-anon/device[1]/virtio-backend', 'device': 'drive-scsi1',
     'inserted': {'node-name': '#cloud', 'ro': True}},
]
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    path = work / 'Blockdev.pm'
    transform = re.sub(r'^path = .*$', f'path = {str(path)!r}', code, flags=re.M)
    def apply(text, check=False):
        path.write_text(text)
        result = subprocess.run([sys.executable, '-c', transform, *(['--check'] if check else [])],
                                capture_output=True, text=True)
        return result, path.read_text()
    result, untouched = apply(original, check=True)
    assert result.returncode == 0 and untouched == original, result.stderr
    result, patched = apply(original)
    assert result.returncode == 0, result.stderr
    result, twice = apply(patched)
    assert result.returncode == 0 and twice == patched
    for bad in (original.replace('sub get_block_info {', 'sub unknown {'),
                original.replace('my $qdev_id = $info->{qdev} or next;', 'my $qdev_id = incompatible();'),
                original + original, patched.replace('my $microvm;', 'my $changed;')):
        result, unchanged = apply(bad)
        assert result.returncode != 0 and unchanged == bad
    path.write_text(patched)
    subprocess.run(['perl', '-e', PERL, str(path)], input=json.dumps(fixture), text=True, check=True)
    # The unpatched upstream routine must fail against exactly the same anonymous fixture.
    path.write_text(original)
    result = subprocess.run(['perl', '-e', PERL, str(path)], input=json.dumps(fixture),
                            text=True, capture_output=True)
    assert result.returncode != 0 and 'no block node inserted' in result.stderr
    path.write_text(patched)
    if shutil.which('qemu-system-x86_64'):
        # Paused disk-only machine: no guest OS, network or real storage volume.
        for name in ('root.raw', 'cloud.raw'):
            with (work / name).open('wb') as f:
                f.truncate(1048576)
        q = subprocess.Popen(['qemu-system-x86_64', '-machine', 'microvm', '-accel', 'tcg',
            '-m', '64', '-S', '-display', 'none', '-nodefaults', '-qmp', 'stdio',
            '-drive', f'file={work}/root.raw,format=raw,if=none,id=drive-scsi0',
            '-device', 'virtio-blk-device,drive=drive-scsi0',
            '-drive', f'file={work}/cloud.raw,format=raw,if=none,id=drive-scsi1,readonly=on',
            '-device', 'virtio-blk-device,drive=drive-scsi1'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        pending = bytearray()
        def response():
            while True:
                while b'\n' not in pending:
                    ready, _, _ = select.select([q.stdout], [], [], 30)
                    if not ready:
                        raise TimeoutError('QMP response timed out')
                    chunk = os.read(q.stdout.fileno(), 65536)
                    if not chunk:
                        raise RuntimeError(q.stderr.read().decode())
                    pending.extend(chunk)
                end = pending.index(b'\n')
                obj = json.loads(pending[:end])
                del pending[:end+1]
                if 'event' not in obj:
                    return obj
        def command(name, **args):
            q.stdin.write((json.dumps({'execute': name, 'arguments': args})+'\n').encode())
            q.stdin.flush()
            obj = response()
            assert 'error' not in obj, obj
            return obj['return']
        try:
            response()
            command('qmp_capabilities')
            blocks = command('query-block')
            subprocess.run(['perl', '-e', PERL, str(path)], input=json.dumps(blocks), text=True, check=True)
            # Get the resize arguments from the actual patched upstream subroutine, not a model.
            capture = PERL[:PERL.index('package main;')] + r'''
package main; require $ARGV[0]; local $/;
$PVE::QemuServer::Blockdev::blocks=decode_json(<STDIN>);
PVE::QemuServer::Blockdev::resize(123,'drive-scsi0',{},'fixture:root',2097153);
print encode_json($PVE::QemuServer::Blockdev::commands[-1]);
'''
            args = json.loads(subprocess.check_output(['perl', '-e', capture, str(path)],
                              input=json.dumps(blocks), text=True))
            qmp_args = dict(zip(args[2::2], args[3::2]))
            # mon_cmd consumes its timeout option before forwarding QMP arguments.
            assert qmp_args.pop('timeout') == 60
            command(args[1], **qmp_args)
            after = command('query-block')
            sizes = {x['device']: x['inserted']['image']['virtual-size'] for x in after}
            assert sizes == {'drive-scsi0': 2098176, 'drive-scsi1': 1048576}, sizes
            assert (work / 'root.raw').stat().st_size == 2098176
            assert (work / 'cloud.raw').stat().st_size == 1048576
            print('QEMU live node resize passed; root grew and read-only cloud-init stayed unchanged')
        finally:
            q.terminate()
            try:
                q.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                q.kill()
                q.communicate()
    else:
        if os.environ.get('CI'):
            raise RuntimeError('QEMU is required for the CI live node resize test')
        print('SKIP: QEMU live node test (qemu-system-x86_64 unavailable)')
assert '/usr/share/perl5/PVE/QemuServer/Blockdev.pm' in (ROOT / 'debian/pve-microvm.triggers').read_text()
print('Blockdev transform refusal, dry-run, idempotency, mapping and resize passed')
