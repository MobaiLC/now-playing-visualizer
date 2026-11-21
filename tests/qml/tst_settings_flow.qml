// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/settings/flow.js" as Flow

// The standalone settings window's Cancel / Apply / OK / close logic.
TestCase {
    name: "SettingsFlow"

    function test_ok_waits_for_ack() {
        const s = Flow.next("idle", "ok", true);
        compare(s.state, "committing");
        compare(s.actions, ["send-commit", "start-timer"]);
        const a = Flow.next(s.state, "ack", false);
        compare(a.actions, ["quit"]);
    }

    function test_ok_times_out_without_ack() {
        const s = Flow.next(Flow.next("idle", "ok", true).state, "timeout", true);
        compare(s.state, "error");
        verify(s.actions.includes("show-error"));
        verify(!s.actions.includes("quit"));
    }

    function test_late_ack_after_timeout_does_not_quit() {
        const s = Flow.next("error", "ack", false);
        compare(s.state, "idle");
        verify(!s.actions.includes("quit"));
    }

    function test_timeout_outside_ok_is_ignored() {
        compare(Flow.next("idle", "timeout", true), { state: "idle", actions: [] });
    }

    function test_cancel_quits() {
        compare(Flow.next("idle", "cancel", true).actions, ["quit"]);
        compare(Flow.next("error", "cancel", true).actions, ["quit"]);
    }

    function test_close_with_changes_asks() {
        const s = Flow.next("idle", "close", true);
        compare(s.state, "closing");
        compare(s.actions, ["ask"]);
    }

    function test_close_without_changes_quits() {
        compare(Flow.next("idle", "close", false).actions, ["quit"]);
    }

    function test_close_during_ok_keeps_waiting() {
        const s = Flow.next("committing", "close", true);
        compare(s, { state: "committing", actions: [] });
        compare(Flow.next(s.state, "ack", false).actions, ["quit"]);
        verify(Flow.next(s.state, "timeout", true).actions.includes("show-error"));
    }

    function test_apply_stays_open() {
        const s = Flow.next("idle", "apply", true);
        compare(s.state, "idle");
        compare(s.actions, ["send-commit"]);
        // the answer to Apply doesn't close the window
        compare(Flow.next(s.state, "ack", false).actions, []);
    }
}
