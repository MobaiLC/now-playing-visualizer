// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// DesignPage's side of the one-editor rule, as plain state so it can be
// tested without a helper: { busy, applying, committed }.
.pragma library

function initial() {
    return { busy: false, applying: false, committed: false };
}

// null: send nothing. A busy page must not commitEdit: the helper accepts it
// from anyone and would save the other window's draft.
function apply(s) {
    return s.busy ? null : { busy: false, applying: true, committed: false };
}

function busyReceived(s) {
    return { busy: true, applying: false, committed: false };
}

// committed: this editState is the answer to apply()
function stateReceived(s, st) {
    const done = s.applying && !st.dirty && !st.error;
    return { busy: false, applying: s.applying && !done, committed: done };
}
