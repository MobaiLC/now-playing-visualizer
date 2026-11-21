// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/edit.js" as Edit

// DesignPage's edit ownership. The page itself can't be loaded here: its
// helper connection would reach whatever runs on the default port.
TestCase {
    name: "Edit"

    function test_apply_then_clean_state_commits() {
        let s = Edit.apply(Edit.initial());
        verify(s !== null);
        compare(Edit.stateReceived(s, { dirty: true }).committed, false);
        s = Edit.stateReceived(s, { dirty: false });
        compare(s.committed, true);
        compare(s.applying, false);
    }
    function test_apply_while_busy_sends_nothing() {
        let s = Edit.busyReceived(Edit.initial());
        compare(Edit.apply(s), null);
        // takeover: beginEdit's clean editState is not this page's commit
        s = Edit.stateReceived(s, { dirty: false });
        compare(s.busy, false);
        compare(s.committed, false);
    }
    function test_busy_drops_pending_apply() {
        let s = Edit.busyReceived(Edit.apply(Edit.initial()));
        compare(s.applying, false);
        compare(Edit.stateReceived(s, { dirty: false }).committed, false);
    }
    function test_error_is_not_a_commit() {
        const s = Edit.stateReceived(Edit.apply(Edit.initial()), { dirty: false, error: "config_unreadable" });
        compare(s.committed, false);
    }
}
