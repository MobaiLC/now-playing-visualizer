// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kcmutils as KCM

// Plasma's Design settings page; the content is DesignPage.qml, shared with
// the standalone settings window.
KCM.SimpleKCM {
    id: kcm

    property var cfg_unused
    property var cfg_unusedDefault
    property string cfg_designCommit
    property string cfg_designCommitDefault

    // Plasma's dialog reads these: Apply/OK call saveConfig(), and closing
    // with unsaved changes asks first.
    readonly property bool unsavedChanges: design.unsavedChanges
    function saveConfig() {
        // read-only while another window edits: a commit would save its draft
        if (design.busy)
            return;
        design.apply();
        // also goes through Plasma's config, in case our socket closes first
        cfg_designCommit = String(Date.now());
    }

    header: design.header

    DesignPage {
        id: design
    }
}
