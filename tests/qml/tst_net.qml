// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/net.js" as Net

// What Helper.qml accepts from NPV_PORT and from whatever listens on the port.
TestCase {
    name: "Net"

    function test_port_data() {
        return [
            { tag: "empty", text: "", port: 47811 },
            { tag: "default", text: "47811", port: 47811 },
            { tag: "custom", text: "47899", port: 47899 },
            { tag: "lowest", text: "1024", port: 1024 },
            { tag: "highest", text: "65535", port: 65535 },
            { tag: "privileged", text: "80", port: 47811 },
            { tag: "too big", text: "65536", port: 47811 },
            { tag: "zero", text: "0", port: 47811 },
            { tag: "spaces", text: " 47899", port: 47811 },
            { tag: "sign", text: "+47899", port: 47811 },
            { tag: "negative", text: "-1", port: 47811 },
            { tag: "decimal", text: "47899.5", port: 47811 },
            { tag: "hex", text: "0xbb1b", port: 47811 },
            { tag: "exponent", text: "4e4", port: 47811 },
            { tag: "six digits", text: "047899", port: 47811 },
            { tag: "non-ASCII digits", text: "٤٧٨٩٩", port: 47811 },
            { tag: "shell", text: "47899; rm -rf ~", port: 47811 },
            { tag: "url", text: "47899/evil", port: 47811 },
            { tag: "newline", text: "47899\n", port: 47811 },
        ];
    }
    function test_port(data) {
        compare(Net.parsePort(data.text), data.port);
    }

    function test_port_must_be_text() {
        compare(Net.parsePort(undefined), 47811);
        compare(Net.parsePort(47899), 47811);
    }

    function test_url_is_always_loopback() {
        compare(Net.helperUrl(Net.parsePort("47899")), "ws://127.0.0.1:47899");
        compare(Net.helperUrl(Net.parsePort("evil.example:80")), "ws://127.0.0.1:47811");
    }

    function test_bars() {
        compare(Net.parseBars("B12;340;1000;0"), [12, 340, 1000, 0]);
        compare(Net.parseBars("B"), [0]);
    }

    function test_bad_bar_values_become_0_or_1000() {
        compare(Net.parseBars("Bx;-5;NaN;;1e9;Infinity;500"), [0, 0, 0, 0, 1000, 1000, 500]);
    }

    function test_bars_are_capped() {
        const frame = "B" + new Array(10000).fill("1").join(";");
        compare(Net.parseBars(frame).length, Net.MAX_BARS);
    }

    function test_messages() {
        compare(Net.parseMessage('{"type":"config","data":{}}').type, "config");
        compare(Net.parseMessage("not json"), null);
        compare(Net.parseMessage("null"), null);
        compare(Net.parseMessage("42"), null);
        compare(Net.parseMessage('"config"'), null);
        compare(Net.parseMessage('[{"type":"config"}]'), null);
        compare(Net.parseMessage("{}"), null);
        compare(Net.parseMessage('{"type":7}'), null);
    }
}
