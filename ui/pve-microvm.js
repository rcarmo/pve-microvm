/*
 * pve-microvm UI integration
 *
 * Adds microvm support to the Proxmox VE web interface:
 * 1. Custom icon for VMs tagged 'microvm' in the resource tree
 * 2. 'microvm' option in the machine type dropdown
 * 3. Conditional panel hiding when microvm is selected
 */
(function () {
    'use strict';

    // Load custom CSS
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/pve2/css/pve-microvm.css';
    document.head.appendChild(link);

    var patchAttempts = 0;
    var patchInterval = setInterval(function () {
        patchAttempts++;
        if (patchAttempts > 200) {
            clearInterval(patchInterval);
            return;
        }

        if (!window.PVE || !PVE.Utils || !PVE.Utils.get_object_icon_class) {
            return;
        }

        clearInterval(patchInterval);

        // ── 1. Custom icon for microvm-tagged VMs ──────────────────

        var origGetIconClass = PVE.Utils.get_object_icon_class;
        PVE.Utils.get_object_icon_class = function (type, record) {
            var cls = origGetIconClass.call(this, type, record);
            if (type === 'qemu' && record && record.tags) {
                var tags = typeof record.tags === 'string'
                    ? record.tags.split(/[;,]/)
                    : record.tags;
                if (tags.some(function (t) { return t.trim().toLowerCase() === 'microvm'; })) {
                    cls += ' pve-microvm';
                }
            }
            return cls;
        };

        // ── 2. Add 'microvm' to machine type dropdown ─────────────

        // Patch the MachineInputPanel to include microvm
        if (Ext.ClassManager.get('PVE.qemu.MachineInputPanel')) {
            var origMachineInit = PVE.qemu.MachineInputPanel.prototype.initComponent;
            PVE.qemu.MachineInputPanel.prototype.initComponent = function () {
                origMachineInit.call(this);
                var combo = this.down('[name=machine]');
                if (combo && combo.store) {
                    // Add microvm if not already present
                    var found = false;
                    combo.store.each(function (rec) {
                        if (rec.get('value') === 'microvm') found = true;
                    });
                    if (!found) {
                        combo.store.add({ value: 'microvm', text: 'microvm' });
                    }
                }
            };
        }

        // ── 3. Auto-configure when microvm is selected ─────────────

        // Patch the create wizard to handle microvm selection
        if (Ext.ClassManager.get('PVE.qemu.CreateWizard')) {
            var origWizardInit = PVE.qemu.CreateWizard.prototype.initComponent;
            PVE.qemu.CreateWizard.prototype.initComponent = function () {
                origWizardInit.call(this);
                var wizard = this;

                // Listen for machine type changes in the wizard
                wizard.on('afterrender', function () {
                    var machineCombo = wizard.down('[name=machine]');
                    if (machineCombo) {
                        machineCombo.on('change', function (field, value) {
                            var isMicrovm = (value === 'microvm');

                            // Hide unsupported fields
                            var hideFields = ['bios', 'efidisk0', 'tpmstate0'];
                            hideFields.forEach(function (name) {
                                var f = wizard.down('[name=' + name + ']');
                                if (f) {
                                    f.setHidden(isMicrovm);
                                    f.setDisabled(isMicrovm);
                                }
                            });

                            // Auto-set serial console and vga
                            if (isMicrovm) {
                                var vgaField = wizard.down('[name=vga]');
                                if (vgaField) vgaField.setValue('serial0');

                                var serialField = wizard.down('[name=serial0]');
                                if (serialField) serialField.setValue('socket');
                            }
                        });
                    }
                });
            };
        }

        // ── 4. Patch Hardware view to show microvm info ────────────

        // When viewing a microvm VM's hardware, show a note
        if (Ext.ClassManager.get('PVE.qemu.HardwareView')) {
            var origHWInit = PVE.qemu.HardwareView.prototype.initComponent;
            PVE.qemu.HardwareView.prototype.initComponent = function () {
                origHWInit.call(this);
                var view = this;
                view.on('afterrender', function () {
                    // Check if this is a microvm
                    var machineRec = view.getStore && view.getStore().findRecord &&
                        view.getStore().findRecord('key', 'machine');
                    if (machineRec) {
                        var machineVal = machineRec.get('value') || '';
                        if (machineVal.indexOf('microvm') >= 0) {
                            // Could add a toolbar note here
                            console.log('pve-microvm: microvm hardware view');
                        }
                    }
                });
            };
        }

        // ── 5. Override console button for microvm ──────────────────

        // The vga=serial0 config already handles this via PVE's native
        // console type detection. No additional patching needed.

        console.log('pve-microvm: UI patches applied (icon, machine dropdown, wizard)');
    }, 100);
})();
