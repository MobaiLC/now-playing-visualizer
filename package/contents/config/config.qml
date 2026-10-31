// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Design")
        icon: "preferences-desktop-color"
        source: "configDesign.qml"
    }
    ConfigCategory {
        name: i18n("Audio")
        icon: "audio-volume-high"
        source: "configApps.qml"
    }
}
