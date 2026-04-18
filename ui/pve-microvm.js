/*
 * pve-microvm UI integration snippet
 *
 * Injected into the Proxmox web UI to:
 * 1. Add 'pve-microvm' CSS class to microvm guest icons in the resource tree
 * 2. Load the custom CSS stylesheet
 *
 * Installation:
 *   This snippet is injected via a small patch to /usr/share/pve-manager/index.html.tpl
 *   or loaded as a custom JS file.
 *
 * How it works:
 *   PVE stores VM config in its data store. We override the icon class resolver
 *   to detect microvm machine types and add our custom class.
 */
(function () {
    'use strict';

    // Load custom CSS
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/pve2/css/pve-microvm.css';
    document.head.appendChild(link);

    // Wait for PVE.Utils to be available, then patch the icon resolver
    var patchAttempts = 0;
    var patchInterval = setInterval(function () {
        patchAttempts++;
        if (patchAttempts > 100) {
            clearInterval(patchInterval);
            return;
        }

        if (!window.PVE || !PVE.Utils || !PVE.Utils.get_object_icon_class) {
            return;
        }

        clearInterval(patchInterval);

        // Save original function
        var origGetIconClass = PVE.Utils.get_object_icon_class;

        // Override to detect microvm
        PVE.Utils.get_object_icon_class = function (type, record) {
            var cls = origGetIconClass.call(this, type, record);

            // Detect microvm: check tags or machine config
            if (type === 'qemu' && record) {
                var isMicrovm = false;

                // Method 1: Check tags for "microvm"
                if (record.tags) {
                    var tags = typeof record.tags === 'string'
                        ? record.tags.split(/[;,]/)
                        : record.tags;
                    isMicrovm = tags.some(function (t) {
                        return t.trim().toLowerCase() === 'microvm';
                    });
                }

                if (isMicrovm) {
                    cls += ' pve-microvm';
                }
            }

            return cls;
        };

        console.log('pve-microvm: UI icon patch applied');
    }, 100);
})();
