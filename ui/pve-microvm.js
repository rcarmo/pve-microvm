/*
 * pve-microvm UI integration
 *
 * Adds microvm support to the Proxmox VE web interface:
 * 1. Custom ⚡ bolt icon for VMs tagged 'microvm' in the resource tree
 * 2. 'microvm' option in the machine type dropdown
 * 3. Conditional panel hiding in wizard + hardware view
 * 4. Auto-configuration for serial console and agent
 * 5. One-click clone button for microvm templates
 * 6. Summary panel microvm badge
 * 7. Config tab filtering (hide irrelevant tabs)
 * 8. Microvm chip in title bar
 * 9. Context menu additions
 */
(function () {
    'use strict';

    // Load custom CSS
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/pve2/css/pve-microvm.css';
    document.head.appendChild(link);

    // ── Helpers ─────────────────────────────────────────────────────

    function isMicrovmConfig(conf) {
        if (!conf) return false;
        var machine = conf.machine || (conf.data && conf.data.machine) || '';
        return String(machine).indexOf('microvm') >= 0;
    }

    function hasMicrovmTag(record) {
        if (!record) return false;
        var tags = record.tags || '';
        if (typeof tags === 'string') tags = tags.split(/[;,]/);
        return tags.some(function (t) { return t.trim().toLowerCase() === 'microvm'; });
    }

    function isMicrovmRecord(record) {
        if (!record) return false;
        var data = record.data || record;
        return hasMicrovmTag(data) || isMicrovmConfig(data);
    }

    // Fields that microvm doesn't support
    var HIDDEN_FIELDS = ['bios', 'efidisk0', 'tpmstate0', 'tablet', 'audio0'];
    var HIDDEN_HW_KEYS = [
        'bios', 'efidisk0', 'tpmstate0', 'tablet', 'audio0',
        'usb0', 'usb1', 'usb2', 'usb3', 'usb4',
        'hostpci0', 'hostpci1', 'hostpci2', 'hostpci3',
    ];
    // Config tabs to hide for microvm
    var HIDDEN_TAB_XTYPES = [
        'pveFirewallRules',    // microvm uses bridge-level firewall
        'pveFirewallOptions',
    ];

    // ── Wait for PVE framework ──────────────────────────────────────

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
        applyPatches();
    }, 100);

    function applyPatches() {

        // ── 1. Custom icon for microvm-tagged VMs ───────────────────

        var origGetIconClass = PVE.Utils.get_object_icon_class;
        PVE.Utils.get_object_icon_class = function (type, record) {
            var cls = origGetIconClass.call(this, type, record);
            if (type === 'qemu' && record && hasMicrovmTag(record)) {
                cls += ' pve-microvm';
            }
            return cls;
        };

        // ── 2. Machine type dropdown ────────────────────────────────

        if (Ext.ClassManager.get('PVE.qemu.MachineInputPanel')) {
            var origMachineInit = PVE.qemu.MachineInputPanel.prototype.initComponent;
            PVE.qemu.MachineInputPanel.prototype.initComponent = function () {
                origMachineInit.call(this);
                var me = this;
                var combo = me.down('[name=machine]');
                if (combo && combo.store) {
                    var found = false;
                    combo.store.each(function (rec) {
                        if (rec.get('value') === 'microvm') found = true;
                    });
                    if (!found) {
                        combo.store.add({ value: 'microvm', text: 'microvm ⚡' });
                    }
                }

                // Hide vIOMMU and version when microvm is selected
                if (combo) {
                    combo.on('change', function (field, val) {
                        var micro = (val === 'microvm');
                        ['viommu', 'version'].forEach(function (n) {
                            var f = me.down('[name=' + n + ']');
                            if (f) { f.setHidden(micro); f.setDisabled(micro); }
                        });
                    });
                }
            };
        }

        // ── 3. Create wizard: microvm-aware ─────────────────────────

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

                        // Hide unsupported fields
                        HIDDEN_FIELDS.forEach(function (name) {
                            var f = wizard.down('[name=' + name + ']');
                            if (f) {
                                f.setHidden(isMicrovm);
                                f.setDisabled(isMicrovm);
                            }
                        });

                        // Hide display type selector
                        var vgaCombo = wizard.down('[name=vga]');
                        if (vgaCombo && isMicrovm) {
                            vgaCombo.setValue('serial0');
                        }

                        if (isMicrovm) {
                            // Auto-set serial console
                            var serialField = wizard.down('[name=serial0]');
                            if (serialField) serialField.setValue('socket');

                            // Auto-enable agent
                            var agentField = wizard.down('[name=agent]');
                            if (agentField) agentField.setValue(1);

                            // Set a sensible memory default for microvm
                            var memField = wizard.down('[name=memory]');
                            if (memField && (!memField.getValue() || memField.getValue() >= 2048)) {
                                memField.setValue(256);
                            }
                        }
                    });
                });
            };
        }

        // ── 4. Hardware view: hide unsupported rows ─────────────────

        if (Ext.ClassManager.get('PVE.qemu.HardwareView')) {
            var origHWInit = PVE.qemu.HardwareView.prototype.initComponent;
            PVE.qemu.HardwareView.prototype.initComponent = function () {
                origHWInit.call(this);
                var view = this;

                var applyMicrovmFilter = function () {
                    var store = view.getStore();
                    if (!store) return;

                    var machineRec = store.findRecord('key', 'machine');
                    if (!machineRec) return;

                    var machineVal = machineRec.get('value') || '';
                    if (machineVal.indexOf('microvm') < 0) return;

                    view.isMicrovm = true;

                    // Hide unsupported rows via CSS rather than store.filterBy
                    // (filterBy breaks Remove button and other store operations)
                    var gridView = view.getView();
                    if (gridView) {
                        store.each(function (rec) {
                            var key = rec.get('key');
                            if (!key) return;
                            var hide = false;
                            for (var i = 0; i < HIDDEN_HW_KEYS.length; i++) {
                                if (key === HIDDEN_HW_KEYS[i]) { hide = true; break; }
                            }
                            if (key.match(/^usb\d+$/) || key.match(/^hostpci\d+$/)) hide = true;
                            if (hide) {
                                var rowNode = gridView.getNode(rec);
                                if (rowNode) rowNode.style.display = 'none';
                            }
                        });
                    }

                    // Add info banner if not already present
                    if (!view._microvmBannerAdded) {
                        view._microvmBannerAdded = true;
                        var banner = document.createElement('div');
                        banner.className = 'pve-microvm-banner';
                        banner.innerHTML = '<i class="fa fa-bolt"></i> microvm — some hardware options are hidden (no USB, PCI passthrough, BIOS, EFI, TPM, audio)';
                        var el = view.getEl();
                        if (el && el.dom) {
                            el.dom.insertBefore(banner, el.dom.firstChild);
                        }
                    }
                };

                view.on('afterrender', function () {
                    var store = view.getStore();
                    if (store) {
                        store.on('load', applyMicrovmFilter);
                        store.on('datachanged', applyMicrovmFilter);
                        applyMicrovmFilter();
                    }
                });
            };

            // Disable unsupported items in the Add button menu
            if (PVE.qemu.HardwareView.prototype.renderToolbar) {
                var origToolbar = PVE.qemu.HardwareView.prototype.renderToolbar;
                PVE.qemu.HardwareView.prototype.renderToolbar = function () {
                    origToolbar.call(this);
                    if (this.isMicrovm) {
                        var addBtn = this.down('#addBtn') || this.down('[text=Add]');
                        if (addBtn && addBtn.menu) {
                            addBtn.menu.items.each(function (item) {
                                var t = (item.text || '').toLowerCase();
                                if (t.match(/usb|audio|pci|efi|tpm/)) {
                                    item.addCls('pve-microvm-disabled');
                                    item.setDisabled(true);
                                    item.setTooltip('Not supported on microvm');
                                }
                            });
                        }
                    }
                };
            }
        }

        // ── 5. Machine edit dialog ──────────────────────────────────

        if (Ext.ClassManager.get('PVE.qemu.MachineEdit')) {
            var origMachineEditInit = PVE.qemu.MachineEdit.prototype.initComponent;
            PVE.qemu.MachineEdit.prototype.initComponent = function () {
                origMachineEditInit.call(this);
                var me = this;

                me.on('afterrender', function () {
                    var machineCombo = me.down('[name=machine]');
                    if (machineCombo) {
                        var checkMicrovm = function () {
                            var val = machineCombo.getValue();
                            if (val === 'microvm') {
                                me.query('[name=viommu]').forEach(function (f) {
                                    f.setHidden(true);
                                    f.setDisabled(true);
                                });
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

        // ── 6. Config panel: microvm chip in title + tab filtering ──

        if (Ext.ClassManager.get('PVE.qemu.Config')) {
            var origConfigInit = PVE.qemu.Config.prototype.initComponent;
            PVE.qemu.Config.prototype.initComponent = function () {
                origConfigInit.call(this);
                var config = this;

                config.on('afterrender', function () {
                    // Fetch VM config to check if microvm
                    var vmid = config.pveSelNode && config.pveSelNode.data && config.pveSelNode.data.vmid;
                    var node = config.pveSelNode && config.pveSelNode.data && config.pveSelNode.data.node;
                    if (!vmid || !node) return;

                    Proxmox.Utils.API2Request({
                        url: '/nodes/' + node + '/qemu/' + vmid + '/config',
                        method: 'GET',
                        success: function (response) {
                            var conf = response.result && response.result.data;
                            if (!conf) return;
                            if (!isMicrovmConfig(conf)) return;

                            // Switch Console tab from noVNC to xterm.js for microvm
                            var consoleTab = config.down('#console');
                            if (consoleTab) {
                                // The pveNoVncConsole widget supports xtermjs mode
                                // Replace with a new instance that uses xterm.js
                                var tabPanel = consoleTab.ownerCt;
                                var tabIdx = tabPanel ? tabPanel.items.indexOf(consoleTab) : -1;
                                if (tabPanel && tabIdx >= 0) {
                                    tabPanel.remove(consoleTab, true);
                                    tabPanel.insert(tabIdx, {
                                        title: gettext('Console'),
                                        itemId: 'console',
                                        iconCls: 'fa fa-bolt',
                                        xtype: 'pveNoVncConsole',
                                        vmid: vmid,
                                        consoleType: 'kvm',
                                        nodename: node,
                                        xtermjs: true,
                                    });
                                }
                            }

                            // Add microvm chip to the title
                            var titleCmp = config.down('title') || config.getHeader();
                            if (titleCmp && titleCmp.getEl) {
                                var el = titleCmp.getEl();
                                if (el && el.dom && !el.dom.querySelector('.pve-microvm-chip')) {
                                    var chip = document.createElement('span');
                                    chip.className = 'pve-microvm-chip';
                                    chip.innerHTML = '⚡ microvm';
                                    el.dom.appendChild(chip);
                                }
                            }

                            // Update the status bar text if available
                            var statusBar = config.down('[xtype=pveGuestStatusBar]') ||
                                           config.down('[cls~=pve-guest-status-bar]');
                            if (statusBar && statusBar.getEl) {
                                var sEl = statusBar.getEl();
                                if (sEl && sEl.dom && !sEl.dom.querySelector('.pve-microvm-chip')) {
                                    var sChip = document.createElement('span');
                                    sChip.className = 'pve-microvm-chip';
                                    sChip.innerHTML = '⚡ microvm';
                                    sEl.dom.appendChild(sChip);
                                }
                            }
                        },
                    });
                });
            };
        }

        // ── 7. Summary panel: show microvm info ─────────────────────

        if (Ext.ClassManager.get('PVE.qemu.Summary') || Ext.ClassManager.get('Proxmox.panel.GuestStatusView')) {
            // Patch the guest summary to show microvm info
            var patchSummary = function (cls) {
                if (!cls) return;
                var origInit = cls.prototype.initComponent;
                cls.prototype.initComponent = function () {
                    origInit.call(this);
                    var summary = this;

                    summary.on('afterrender', function () {
                        // Find a parent config panel to check machine type
                        var configPanel = summary.up('PVE\\.qemu\\.Config') || summary.up('[hstateid=kvmtab]');
                        if (!configPanel || !configPanel.pveSelNode) return;

                        var data = configPanel.pveSelNode.data;
                        if (!hasMicrovmTag(data)) return;

                        // Add microvm info
                        var el = summary.getEl();
                        if (el && el.dom && !el.dom.querySelector('.pve-microvm-banner')) {
                            var banner = document.createElement('div');
                            banner.className = 'pve-microvm-banner';
                            banner.innerHTML = '<i class="fa fa-bolt"></i> QEMU microvm — lightweight KVM-isolated VM with direct kernel boot';
                            el.dom.insertBefore(banner, el.dom.firstChild);
                        }
                    });
                };
            };
            patchSummary(Ext.ClassManager.get('PVE.qemu.Summary'));
        }

        // ── 8. Options panel: mark unsupported options ──────────────

        if (Ext.ClassManager.get('PVE.qemu.Options')) {
            var origOptionsInit = PVE.qemu.Options.prototype.initComponent;
            PVE.qemu.Options.prototype.initComponent = function () {
                origOptionsInit.call(this);
                var options = this;

                options.on('afterrender', function () {
                    var store = options.getStore();
                    if (!store) return;

                    store.on('load', function () {
                        // Check if microvm
                        var machineRec = store.findRecord('key', 'machine');
                        if (!machineRec) return;
                        var machineVal = machineRec.get('value') || '';
                        if (machineVal.indexOf('microvm') < 0) return;

                        // Grey out unsupported options
                        var unsupported = ['bios', 'tablet', 'hotplug'];
                        store.each(function (rec) {
                            var key = rec.get('key');
                            if (unsupported.indexOf(key) >= 0) {
                                rec.set('value', rec.get('value') + ' (n/a for microvm)');
                            }
                        });
                    });
                });
            };
        }

        // ── 9. Context menu: clone + terminal for microvm ───────────

        if (Ext.ClassManager.get('PVE.qemu.CmdMenu')) {
            var origCmdMenuInit = PVE.qemu.CmdMenu.prototype.initComponent;
            PVE.qemu.CmdMenu.prototype.initComponent = function () {
                origCmdMenuInit.call(this);
                var menu = this;
                var info = menu.pveSelNode && menu.pveSelNode.data;
                if (!info || !hasMicrovmTag(info)) return;

                // Add separator and microvm-specific items
                menu.add({ xtype: 'menuseparator' });

                // Quick terminal (serial console)
                if (info.status === 'running') {
                    menu.add({
                        text: '⚡ Serial Console',
                        iconCls: 'fa fa-terminal',
                        handler: function () {
                            var url = '/nodes/' + info.node + '/qemu/' + info.vmid + '/termproxy';
                            PVE.Utils.openDefaultConsoleWindow({
                                vmid: info.vmid,
                                nodename: info.node,
                                vmname: info.name,
                                type: 'kvm',
                                xtermjs: true,
                            }, 'html5', url);
                        },
                    });
                }

                // One-click clone for templates
                if (info.template) {
                    menu.add({
                        text: '⚡ Clone microvm',
                        iconCls: 'fa fa-bolt',
                        handler: function () {
                            var win = Ext.create('PVE.window.Clone', {
                                nodename: info.node,
                                vmid: info.vmid,
                                isTemplate: true,
                                type: 'qemu',
                            });
                            win.show();
                        },
                    });
                }
            };
        }

        // ── 10. Resource tree: right-click clone for templates ──────

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
                                tree.selectById('qemu/' + vmid);
                            },
                        }],
                    });
                    menu.showAt(e.getXY());
                });
            };
        }

        // ── 11. Console: force xterm.js for microvm VMs ────────────

        // Patch openDefaultConsoleWindow to detect microvm and force xterm.js
        var origOpenDefault = PVE.Utils.openDefaultConsoleWindow;
        PVE.Utils.openDefaultConsoleWindow = function (consoles, consoleType, vmid, nodename, vmname, cmd) {
            if (consoleType === 'kvm' && vmid) {
                // Check if this VM is a microvm by looking at the resource store
                var rstore = PVE.data && PVE.data.ResourceStore;
                if (rstore) {
                    var rec = rstore.findRecord('vmid', vmid);
                    if (rec && hasMicrovmTag(rec.data)) {
                        // Force xterm.js for microvm (serial console)
                        PVE.Utils.openConsoleWindow('xtermjs', consoleType, vmid, nodename, vmname, cmd);
                        return;
                    }
                }
                // Also check via the resource tree
                var trees = Ext.ComponentQuery.query('pveResourceTree');
                if (trees && trees.length > 0) {
                    var store = trees[0].getStore();
                    if (store) {
                        var node = store.findNode('vmid', vmid);
                        if (node && hasMicrovmTag(node.data)) {
                            PVE.Utils.openConsoleWindow('xtermjs', consoleType, vmid, nodename, vmname, cmd);
                            return;
                        }
                    }
                }
            }
            return origOpenDefault.call(this, consoles, consoleType, vmid, nodename, vmname, cmd);
        };

        // Also patch the ConsoleButton handler directly for microvm VMs
        if (Ext.ClassManager.get('PVE.button.ConsoleButton')) {
            var origConsoleHandler = PVE.button.ConsoleButton.prototype.handler;
            PVE.button.ConsoleButton.prototype.handler = function () {
                var me = this;
                if (me.consoleType === 'kvm' && me.vmid) {
                    // Check resource store for microvm tag
                    var rstore = PVE.data && PVE.data.ResourceStore;
                    if (rstore) {
                        var rec = rstore.findRecord('vmid', me.vmid);
                        if (rec && hasMicrovmTag(rec.data)) {
                            Proxmox.Utils.openXtermJsViewer('kvm', me.vmid, me.nodename, me.consoleName, me.cmd);
                            return;
                        }
                    }
                }
                return origConsoleHandler.call(me);
            };
        }

        // ── 12. "Create µVM" dialog and button ─────────────────

        // Common OCI images for the dropdown
        var OCI_IMAGES = [
            ['alpine:3.21', 'Alpine 3.21 (3 MB)'],
            ['debian:trixie-slim', 'Debian Trixie Slim (28 MB)'],
            ['ubuntu:24.04', 'Ubuntu 24.04 (28 MB)'],
            ['fedora:41', 'Fedora 41 (57 MB)'],
            ['rockylinux:9-minimal', 'Rocky Linux 9 Minimal (44 MB)'],
            ['almalinux:9-minimal', 'Alma Linux 9 Minimal (34 MB)'],
            ['amazonlinux:2023', 'Amazon Linux 2023 (52 MB)'],
            ['oraclelinux:9-slim', 'Oracle Linux 9 Slim (45 MB)'],
            ['redhat/ubi9-minimal', 'Red Hat UBI 9 Minimal (38 MB)'],
            ['redhat/ubi9-micro', 'Red Hat UBI 9 Micro (6 MB)'],
            ['photon:5.0', 'VMware Photon 5.0 (15 MB)'],
            ['mcr.microsoft.com/azurelinux/base/core:3.0', 'Azure Linux 3.0 (30 MB)'],
            ['openwrt', 'OpenWrt 25.12.2 (13 MB, router OS, q35)'],
            ['opnsense', 'OPNsense 25.1 (500 MB, FreeBSD firewall, q35)'],
            ['9front', '9Front / Plan 9 (239 MB, q35)'],
            ['osv', 'OSv unikernel (2.5 MB, q35)'],
            ['smolbsd', 'SmolBSD (20 MB, NetBSD, 307ms boot)'],
        ];

        var PROFILES = [
            ['minimal', 'Minimal (shell only, no services)'],
            ['standard', 'Standard (SSH + guest agent, no Docker)'],
            ['full', 'Full (SSH + agent + Docker)'],
        ];

        function openMicrovmDialog(nodename) {
            // Get next VMID
            Proxmox.Utils.API2Request({
                url: '/cluster/nextid',
                method: 'GET',
                success: function (response) {
                    var nextid = response.result.data;
                    showMicrovmDialog(nodename, nextid);
                },
                failure: function () {
                    showMicrovmDialog(nodename, 100);
                },
            });
        }

        function showMicrovmDialog(nodename, defaultVmid) {
            // Get default node from selection if not provided
            if (!nodename) {
                var trees = Ext.ComponentQuery.query('pveResourceTree');
                if (trees && trees.length > 0) {
                    var sel = trees[0].getSelection();
                    if (sel && sel.length > 0) {
                        nodename = sel[0].data.node || sel[0].data.text;
                    }
                }
            }

            var win = Ext.create('Ext.window.Window', {
                title: '\u26a1 Create \u00b5VM',
                width: 520,
                modal: true,
                bodyPadding: 15,
                layout: 'anchor',
                defaults: { anchor: '100%', labelWidth: 120 },
                items: [
                    {
                        xtype: 'displayfield',
                        value: '<div style="background:#f59e0b;color:white;padding:8px 12px;border-radius:4px;margin-bottom:10px">' +
                               '<i class="fa fa-bolt"></i> Create a microvm from an OCI container image</div>',
                    },
                    {
                        xtype: 'pveNodeSelector',
                        name: 'node',
                        fieldLabel: 'Node',
                        value: nodename,
                        allowBlank: false,
                    },
                    {
                        xtype: 'numberfield',
                        name: 'vmid',
                        fieldLabel: 'VM ID',
                        value: defaultVmid,
                        minValue: 100,
                        maxValue: 999999999,
                        allowBlank: false,
                    },
                    {
                        xtype: 'textfield',
                        name: 'name',
                        fieldLabel: 'Name',
                        value: 'microvm',
                        allowBlank: false,
                        vtype: 'DnsName',
                    },
                    {
                        xtype: 'combobox',
                        name: 'image',
                        fieldLabel: 'OCI Image',
                        store: OCI_IMAGES,
                        queryMode: 'local',
                        editable: true,
                        forceSelection: false,
                        value: 'debian:trixie-slim',
                        emptyText: 'e.g. alpine:3.21 or myregistry.io/myimage:tag',
                        allowBlank: false,
                    },
                    {
                        xtype: 'pveStorageSelector',
                        name: 'storage',
                        fieldLabel: 'Storage',
                        nodename: nodename,
                        storageContent: 'images',
                        value: 'local-lvm',
                        allowBlank: false,
                    },
                    {
                        xtype: 'numberfield',
                        name: 'memory',
                        fieldLabel: 'Memory (MB)',
                        value: 256,
                        minValue: 64,
                        maxValue: 65536,
                        step: 64,
                        allowBlank: false,
                    },
                    {
                        xtype: 'textfield',
                        name: 'disksize',
                        fieldLabel: 'Disk Size',
                        value: '2G',
                        emptyText: 'e.g. 1G, 2G, 512M',
                        allowBlank: false,
                    },
                    {
                        xtype: 'combobox',
                        name: 'profile',
                        fieldLabel: 'Profile',
                        store: PROFILES,
                        queryMode: 'local',
                        editable: false,
                        value: 'standard',
                        allowBlank: false,
                    },
                    {
                        xtype: 'numberfield',
                        name: 'cores',
                        fieldLabel: 'CPU Cores',
                        value: 1,
                        minValue: 1,
                        maxValue: 128,
                        allowBlank: false,
                    },
                ],
                buttons: [
                    {
                        text: 'Create',
                        iconCls: 'fa fa-bolt',
                        formBind: true,
                        handler: function () {
                            var form = win.down('form') || win;
                            var values = {};
                            win.query('field').forEach(function (f) {
                                if (f.name && f.getValue) values[f.name] = f.getValue();
                            });

                            var node = values.node;
                            var vmid = values.vmid;
                            var name = values.name;
                            var image = values.image;
                            var storage = values.storage;
                            var memory = values.memory;
                            var disksize = values.disksize;
                            var profile = values.profile;
                            var cores = values.cores;

                            if (!node || !vmid || !image) {
                                Ext.Msg.alert('Error', 'Please fill in all required fields.');
                                return;
                            }

                            // Build the template command
                            var cmd = 'pve-microvm-template' +
                                ' --image ' + image +
                                ' --vmid ' + vmid +
                                ' --name ' + name +
                                ' --storage ' + storage +
                                ' --memory ' + memory +
                                ' --disk-size ' + disksize +
                                ' --profile ' + profile +
                                ' --cores ' + cores;

                            win.close();

                            // Open an xterm.js shell to run the command
                            // Use the node shell with a custom command
                            var url = Ext.Object.toQueryString({
                                console: 'shell',
                                xtermjs: 1,
                                node: node,
                                cmd: cmd,
                            });
                            var termWin = window.open('?' + url, '_blank',
                                'toolbar=no,location=no,status=no,menubar=no,resizable=yes,width=800,height=500');

                            // Also show the command for manual use
                            Ext.Msg.show({
                                title: '\u26a1 Creating \u00b5VM ' + vmid,
                                msg: '<p>A terminal window is opening to build your microvm.</p>' +
                                     '<p>If the terminal does not open, run this on the node:</p>' +
                                     '<pre style="background:#1a1a2e;color:#e0e0e0;padding:10px;border-radius:4px;margin-top:8px;' +
                                     'font-size:12px;overflow-x:auto;white-space:pre-wrap">' + Ext.htmlEncode(cmd) + '</pre>',
                                buttons: Ext.Msg.OK,
                                icon: Ext.Msg.INFO,
                            });
                        },
                    },
                    {
                        text: 'Cancel',
                        handler: function () { win.close(); },
                    },
                ],
            });

            // Update storage selector when node changes
            win.down('[name=node]').on('change', function (field, newNode) {
                var storageSel = win.down('[name=storage]');
                if (storageSel && storageSel.setNodename) {
                    storageSel.setNodename(newNode);
                }
            });

            win.show();
        }

        // Add the header toolbar button
        var addCreateButton = function () {
            var viewport = Ext.ComponentQuery.query('viewport')[0];
            if (!viewport) return false;

            // Find the Create VM button in the header toolbar
            var createVMBtn = null;
            var allButtons = viewport.query('button');
            for (var i = 0; i < allButtons.length; i++) {
                var btn = allButtons[i];
                if (btn.text && btn.text === gettext('Create VM') && btn.iconCls && btn.iconCls.indexOf('fa-desktop') >= 0) {
                    createVMBtn = btn;
                    break;
                }
            }
            if (!createVMBtn) return false;

            // Don't add twice
            if (viewport.down('#createMicrovmBtn')) return true;

            var parent = createVMBtn.ownerCt;
            if (!parent) return false;

            var caps = Ext.state.Manager.get('GuiCap') || {};
            var vmCaps = caps.vms || {};

            var createMicrovmBtn = Ext.createWidget('button', {
                itemId: 'createMicrovmBtn',
                pack: 'end',
                margin: '3 5 0 0',
                baseCls: 'x-btn',
                iconCls: 'fa fa-bolt pve-microvm-btn',
                text: 'Create \u00b5VM',
                disabled: !vmCaps['VM.Allocate'],
                handler: function () {
                    openMicrovmDialog();
                },
            });

            // Insert after Create VM button
            var idx = parent.items.indexOf(createVMBtn);
            if (idx >= 0) {
                parent.insert(idx + 1, createMicrovmBtn);
            } else {
                parent.add(createMicrovmBtn);
            }

            // Track capability changes
            Ext.state.Manager.on('statechange', function (sp, key, value) {
                if (key === 'GuiCap' && value) {
                    createMicrovmBtn.setDisabled(!(value.vms || {})['VM.Allocate']);
                }
            });

            return true;
        };

        // Retry until viewport is ready
        var btnAttempts = 0;
        var btnInterval = setInterval(function () {
            btnAttempts++;
            if (btnAttempts > 100 || addCreateButton()) {
                clearInterval(btnInterval);
            }
        }, 200);

        // ── 13. "Create µVM" in node context menu ───────────────────

        if (Ext.ClassManager.get('PVE.node.CmdMenu')) {
            var origNodeCmdInit = PVE.node.CmdMenu.prototype.initComponent;
            PVE.node.CmdMenu.prototype.initComponent = function () {
                origNodeCmdInit.call(this);
                var menu = this;
                var nodename = menu.nodename;

                // Find the Create VM item and insert after it
                var createVMItem = null;
                var createVMIdx = -1;
                menu.items.each(function (item, idx) {
                    if (item.itemId === 'createvm') {
                        createVMItem = item;
                        createVMIdx = idx;
                    }
                });

                if (createVMIdx >= 0) {
                    menu.insert(createVMIdx + 1, {
                        text: 'Create \u00b5VM',
                        itemId: 'createmicrovm',
                        iconCls: 'fa fa-bolt',
                        handler: function () {
                            openMicrovmDialog(nodename);
                        },
                    });
                }
            };
        }

        console.log('pve-microvm: UI patches applied (icon, machine, wizard, hardware, summary, options, console, clone, create-button)');
    }
})();
