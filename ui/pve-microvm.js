/*
 * pve-microvm UI integration
 *
 * Adds microvm support to the Proxmox VE web interface:
 * 1. Custom icon for VMs tagged 'microvm' in the resource tree
 * 2. 'microvm' option in the machine type dropdown
 * 3. Conditional panel hiding in wizard + hardware view
 * 4. Auto-configuration for serial console, agent, kernel
 * 5. One-click clone button for microvm templates
 */
(function () {
    'use strict';

    // Load custom CSS
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/pve2/css/pve-microvm.css';
    document.head.appendChild(link);

    // Helper: detect if a VM config is microvm
    function isMicrovmConfig(conf) {
        if (!conf) return false;
        var machine = conf.machine || conf.data && conf.data.machine || '';
        return String(machine).indexOf('microvm') >= 0;
    }

    // Helper: detect if a record has the microvm tag
    function hasMicrovmTag(record) {
        if (!record || !record.tags) return false;
        var tags = typeof record.tags === 'string' ? record.tags.split(/[;,]/) : record.tags;
        return tags.some(function (t) { return t.trim().toLowerCase() === 'microvm'; });
    }

    // Fields that microvm doesn't support
    var HIDDEN_FIELDS = ['bios', 'efidisk0', 'tpmstate0', 'tablet', 'audio0'];
    var HIDDEN_HW_KEYS = [
        'bios', 'efidisk0', 'tpmstate0', 'tablet', 'audio0',
        'usb0', 'usb1', 'usb2', 'usb3', 'usb4',
        'hostpci0', 'hostpci1', 'hostpci2', 'hostpci3',
    ];

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
            if (type === 'qemu' && record && hasMicrovmTag(record)) {
                cls += ' pve-microvm';
            }
            return cls;
        };

        // ── 2. Add 'microvm' to machine type dropdown ─────────────

        if (Ext.ClassManager.get('PVE.qemu.MachineInputPanel')) {
            var origMachineInit = PVE.qemu.MachineInputPanel.prototype.initComponent;
            PVE.qemu.MachineInputPanel.prototype.initComponent = function () {
                origMachineInit.call(this);
                var combo = this.down('[name=machine]');
                if (combo && combo.store) {
                    var found = false;
                    combo.store.each(function (rec) {
                        if (rec.get('value') === 'microvm') found = true;
                    });
                    if (!found) {
                        combo.store.add({ value: 'microvm', text: 'microvm' });
                    }
                }

                // Hide vIOMMU and version when microvm is selected
                var me = this;
                var machineCombo = me.down('[name=machine]');
                if (machineCombo) {
                    machineCombo.on('change', function (field, val) {
                        var micro = (val === 'microvm');
                        ['viommu', 'version'].forEach(function (n) {
                            var f = me.down('[name=' + n + ']');
                            if (f) { f.setHidden(micro); f.setDisabled(micro); }
                        });
                    });
                }
            };
        }

        // ── 3. Create wizard: microvm-aware ────────────────────────

        if (Ext.ClassManager.get('PVE.qemu.CreateWizard')) {
            var origWizardInit = PVE.qemu.CreateWizard.prototype.initComponent;
            PVE.qemu.CreateWizard.prototype.initComponent = function () {
                origWizardInit.call(this);
                var wizard = this;

                wizard.on('afterrender', function () {
                    var machineCombo = wizard.down('[name=machine]');
                    if (!machineCombo) return;

                    machineCombo.on('change', function (field, value) {
                        var isMicrovm = (value === 'microvm');

                        // Hide unsupported fields across all wizard pages
                        HIDDEN_FIELDS.forEach(function (name) {
                            var f = wizard.down('[name=' + name + ']');
                            if (f) {
                                f.setHidden(isMicrovm);
                                f.setDisabled(isMicrovm);
                            }
                        });

                        // Hide the entire "OS" page's ISO selector (microvm uses -kernel)
                        var osPage = null;
                        wizard.items.each(function (page) {
                            if (page.title && page.title === gettext('OS')) {
                                osPage = page;
                            }
                        });

                        if (isMicrovm) {
                            // Auto-set serial console
                            var vgaField = wizard.down('[name=vga]');
                            if (vgaField) vgaField.setValue('serial0');

                            var agentField = wizard.down('[name=agent]');
                            if (agentField) agentField.setValue(1);
                        }
                    });
                });
            };
        }

        // ── 4. Hardware view: hide unsupported rows for microvm ────

        if (Ext.ClassManager.get('PVE.qemu.HardwareView')) {
            var origHWInit = PVE.qemu.HardwareView.prototype.initComponent;
            PVE.qemu.HardwareView.prototype.initComponent = function () {
                origHWInit.call(this);
                var view = this;

                // After the store loads, hide rows that don't apply to microvm
                var applyMicrovmFilter = function () {
                    var store = view.getStore();
                    if (!store) return;

                    var machineRec = store.findRecord('key', 'machine');
                    if (!machineRec) return;

                    var machineVal = machineRec.get('value') || '';
                    if (machineVal.indexOf('microvm') < 0) return;

                    // Add a microvm info banner
                    view.isMicrovm = true;

                    // Filter out unsupported hardware entries
                    store.filterBy(function (rec) {
                        var key = rec.get('key');
                        if (!key) return true;

                        // Hide USB, PCI passthrough, BIOS, EFI, TPM, audio
                        for (var i = 0; i < HIDDEN_HW_KEYS.length; i++) {
                            if (key === HIDDEN_HW_KEYS[i]) return false;
                        }
                        // Hide any usb* or hostpci*
                        if (key.match(/^usb\d+$/) || key.match(/^hostpci\d+$/)) return false;

                        return true;
                    });
                };

                view.on('afterrender', function () {
                    var store = view.getStore();
                    if (store) {
                        store.on('load', applyMicrovmFilter);
                        store.on('datachanged', applyMicrovmFilter);
                        // Try immediately in case data is already loaded
                        applyMicrovmFilter();
                    }
                });
            };

            // Patch the "Add" button menu to exclude unsupported devices
            if (PVE.qemu.HardwareView.prototype.renderToolbar) {
                var origToolbar = PVE.qemu.HardwareView.prototype.renderToolbar;
                PVE.qemu.HardwareView.prototype.renderToolbar = function () {
                    origToolbar.call(this);
                    if (this.isMicrovm) {
                        // Disable Add buttons for unsupported hardware
                        var addBtn = this.down('#addBtn') || this.down('[text=Add]');
                        if (addBtn && addBtn.menu) {
                            addBtn.menu.items.each(function (item) {
                                var t = (item.text || '').toLowerCase();
                                if (t.match(/usb|audio|pci|efi|tpm/)) {
                                    item.setDisabled(true);
                                    item.setTooltip('Not supported on microvm');
                                }
                            });
                        }
                    }
                };
            }
        }

        // ── 5. Machine edit: show kernel path for microvm ──────────

        if (Ext.ClassManager.get('PVE.qemu.MachineEdit')) {
            var origMachineEditInit = PVE.qemu.MachineEdit.prototype.initComponent;
            PVE.qemu.MachineEdit.prototype.initComponent = function () {
                origMachineEditInit.call(this);
                var me = this;

                // After render, check if microvm and show info
                me.on('afterrender', function () {
                    var machineCombo = me.down('[name=machine]');
                    if (machineCombo) {
                        var checkMicrovm = function () {
                            var val = machineCombo.getValue();
                            if (val === 'microvm') {
                                // Hide vIOMMU options
                                me.query('[name=viommu]').forEach(function (f) {
                                    f.setHidden(true);
                                    f.setDisabled(true);
                                });
                                // Hide version selector
                                var vf = me.down('[name=version]');
                                if (vf) { vf.setHidden(true); vf.setDisabled(true); }
                            }
                        };
                        machineCombo.on('change', checkMicrovm);
                        checkMicrovm();
                    }
                });
            };
        }

        // ── 6. Resource tree: one-click clone for microvm templates ─

        // Add context menu item for microvm templates
        if (Ext.ClassManager.get('PVE.tree.ResourceTree')) {
            var origTreeInit = PVE.tree.ResourceTree.prototype.initComponent;
            PVE.tree.ResourceTree.prototype.initComponent = function () {
                origTreeInit.call(this);
                var tree = this;

                tree.on('itemcontextmenu', function (treeView, record, item, index, e) {
                    if (!record || record.data.type !== 'qemu') return;
                    if (!hasMicrovmTag(record.data)) return;
                    if (!record.data.template) return;

                    e.stopEvent();

                    var vmid = record.data.vmid;
                    var node = record.data.node;

                    var menu = Ext.create('Ext.menu.Menu', {
                        items: [{
                            text: '⚡ Clone microvm',
                            iconCls: 'fa fa-bolt',
                            handler: function () {
                                // Open the clone dialog
                                var win = Ext.create('PVE.window.Clone', {
                                    nodename: node,
                                    vmid: vmid,
                                    isTemplate: true,
                                    type: 'qemu',
                                });
                                win.show();
                            },
                        }, {
                            text: 'Open Template',
                            iconCls: 'fa fa-cog',
                            handler: function () {
                                // Navigate to the VM
                                var id = 'qemu/' + vmid;
                                tree.selectById(id);
                            },
                        }],
                    });
                    menu.showAt(e.getXY());
                });
            };
        }

        console.log('pve-microvm: UI patches applied (icon, machine, wizard, hardware, clone)');
    }, 100);
})();
