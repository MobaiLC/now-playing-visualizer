// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kcmutils as KCM

// Plasma's Audio settings page; the content is AudioPage.qml, shared with the
// standalone settings window.
KCM.SimpleKCM {
    property var cfg_unused
    property var cfg_unusedDefault

    AudioPage {}
}
