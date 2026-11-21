// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The standalone settings window's buttons as plain state, so they can be
// tested without a helper. States: idle | committing (OK sent, waiting for
// the helper) | closing (asking about unapplied changes) | error (OK got no
// answer in time). The window carries out the actions.
.pragma library

var TIMEOUT_MS = 3000;

function next(state, event, unsavedChanges) {
    switch (event) {
    case "ok":
        return { state: "committing", actions: ["send-commit", "start-timer"] };
    case "apply":
        return { state: state === "committing" ? state : "idle", actions: ["send-commit"] };
    case "ack":
        // only OK's answer quits; a late one after the timeout just clears the error
        if (state === "committing")
            return { state: "idle", actions: ["quit"] };
        return { state: state === "error" ? "idle" : state, actions: [] };
    case "timeout":
        if (state === "committing")
            return { state: "error", actions: ["show-error"] };
        return { state: state, actions: [] };
    case "cancel":
        // the helper reverts the draft when the window's connection closes
        return { state: state, actions: ["quit"] };
    case "close":
        // OK's answer is still coming: it quits, or its timeout shows the error
        if (state === "committing")
            return { state: state, actions: [] };
        return unsavedChanges ? { state: "closing", actions: ["ask"] } : { state: state, actions: ["quit"] };
    }
    return { state: state, actions: [] };
}
