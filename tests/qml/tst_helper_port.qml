// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest

// Which port Helper.qml connects to: --port first, then Launcher.qml. The
// launcher is a stub and no port used here has a helper on it.
TestCase {
    name: "HelperPort"

    function make(args) {
        const c = Qt.createComponent("../../package/contents/ui/Helper.qml");
        verify(c.status === Component.Ready, c.errorString());
        const h = createTemporaryObject(c, this, {
            commandLine: args,
            launcherSource: Qt.resolvedUrl("StubLauncher.qml"),
        });
        verify(h);
        return h;
    }

    // the stub, inside Helper's Loader
    function stubOf(h) {
        for (const c of h.children)
            if (c.item && c.item.readPortCalls !== undefined)
                return c.item;
        return null;
    }

    function test_valid_port_wins() {
        const h = make(["qml", "settings.qml", "--", "--port", "50123"]);
        compare(h.url, "ws://127.0.0.1:50123");
        verify(h.socketActive);
        const stub = stubOf(h);
        verify(stub);
        // past the 3 s port timeout and a few 1.5 s retries
        wait(5000);
        compare(h.url, "ws://127.0.0.1:50123");
        compare(stub.readPortCalls, 0);
        compare(stub.launchCalls, 0);
    }

    function test_equals_form() {
        const h = make(["qml", "--port=50124"]);
        compare(h.url, "ws://127.0.0.1:50124");
        compare(stubOf(h).readPortCalls, 0);
    }

    function test_bad_port_connects_nowhere_data() {
        return [
            { tag: "abc", args: ["qml", "--port", "abc"] },
            { tag: "no value", args: ["qml", "--port"] },
            { tag: "zero", args: ["qml", "--port=0"] },
        ];
    }
    function test_bad_port_connects_nowhere(data) {
        ignoreWarning(/--port .* not connecting/);
        const h = make(data.args);
        const stub = stubOf(h);
        wait(5000);
        verify(!h.socketActive);
        compare(stub.readPortCalls, 0);
        compare(stub.launchCalls, 0);
    }

    function test_without_port_uses_launcher() {
        const h = make(["qml", "settings.qml"]);
        const stub = stubOf(h);
        verify(stub);
        compare(stub.readPortCalls, 1);
        compare(h.url, "ws://127.0.0.1:50199");
    }
}
