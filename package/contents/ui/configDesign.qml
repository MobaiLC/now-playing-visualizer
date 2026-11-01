// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Visual editor for config.json, generated from code/schema.json: every
// option there becomes a control here, so adding an option needs no QML.
// Changes are written to "overrides" through the helper and show up live,
// both on the widget and in the preview at the top; Cancel reverts them.
KCM.SimpleKCM {
    id: page

    property var cfg_unused
    property var cfg_unusedDefault
    property string cfg_designCommit
    property string cfg_designCommitDefault

    // Plasma's dialog reads these: Apply/OK call saveConfig(), and closing
    // with unsaved changes asks first. Cancel needs nothing here: the helper
    // reverts the design when this page disconnects without a commit.
    property bool unsavedChanges: false
    property bool canUndo: false
    function saveConfig() {
        flushNow();
        helper.send({ type: "commitEdit" });
        // also goes through Plasma's config, in case our socket closes first
        cfg_designCommit = String(Date.now());
    }

    property string tab: "presets"
    // size the preset thumbnails are drawn at before scaling down
    readonly property int thumbW: 480
    readonly property int thumbH: 150
    property var presets: []

    // options arrive as an ordered list of specs, each with its "key"
    property var schema: ({ groups: [], options: [] })
    property var d: ({})
    property var pending: ({})

    // ---- data helpers -----------------------------------------------------
    function g(path, def) {
        let o = d;
        for (const k of path.split(".")) {
            if (o === undefined || o === null)
                return def;
            o = o[k];
        }
        return o === undefined ? def : o;
    }

    function s(path, value) {
        // update locally so dependent controls react at once
        const keys = path.split(".");
        let o = d;
        for (const k of keys.slice(0, -1)) {
            if (typeof o[k] !== "object" || o[k] === null)
                o[k] = {};
            o = o[k];
        }
        o[keys[keys.length - 1]] = value;
        d = Object.assign({}, d);
        pending[path] = value;
        flush.restart();
    }

    Timer {
        id: flush
        interval: 250
        onTriggered: page.flushNow()
    }
    function flushNow() {
        flush.stop();
        if (Object.keys(pending).length) {
            helper.send({ type: "setDesign", changes: pending });
            pending = {};
        }
    }
    // error code from the helper for the last change, e.g. "preset_limit"
    property string saveError: ""

    // ---- preset files ---------------------------------------------------------
    // The helper reads and writes the file (QML can't); it checks the path and
    // keeps only valid options from an imported file.
    // last reply: { op: "import" | "export", error?, name?, ignored? }
    property var fileResult: null

    function localPath(url) {
        const s = url.toString();
        return s.startsWith("file://") ? decodeURIComponent(s.slice(7)) : "";
    }
    function fileMessage(r) {
        if (!r)
            return "";
        switch (r.error || "") {
        case "": return r.op === "export"
            ? i18n("Design exported as \"%1\".", r.name)
            : (r.ignored > 0
               ? i18np("Imported as \"%2\". %1 setting in the file was not valid and was left out.",
                       "Imported as \"%2\". %1 settings in the file were not valid and were left out.", r.ignored, r.name)
               : i18n("Imported as \"%1\".", r.name));
        case "file_bad_path": return i18n("That file can't be used: pick a local file ending in .json.");
        case "file_unreadable": return i18n("The file could not be read.");
        case "file_too_big": return i18n("The file is too big to be a preset.");
        case "file_not_json": return i18n("The file is not valid JSON.");
        case "file_not_preset": return i18n("The file is not a Now Playing Visualizer preset.");
        case "file_unwritable": return i18n("The file could not be saved there.");
        case "preset_limit": return i18n("You have reached the limit of 100 saved presets. Delete one before importing.");
        default: return r.error;
        }
    }

    FileDialog {
        id: exportDialog
        title: i18n("Export design")
        fileMode: FileDialog.SaveFile
        nameFilters: [i18n("Presets (*.json)")]
        defaultSuffix: "json"
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: page.act({ type: "exportPreset", path: page.localPath(selectedFile) })
    }
    FileDialog {
        id: importDialog
        title: i18n("Import preset")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Presets (*.json)")]
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: page.act({ type: "importPreset", path: page.localPath(selectedFile) })
    }

    function act(msg) {
        flushNow();
        helper.send(msg);
    }

    // "when": every key must match; "whenNot": any match hides the option.
    function matches(key, cond) {
        const v = g(key);
        return Array.isArray(cond) ? cond.includes(v) : v === cond;
    }
    function shown(spec) {
        if (spec.hidden)
            return false;
        for (const k in (spec.when || {}))
            if (!matches(k, spec.when[k]))
                return false;
        for (const k in (spec.whenNot || {}))
            if (matches(k, spec.whenNot[k]))
                return false;
        return true;
    }

    // Flat list of section headers and options, in schema order.
    readonly property var rows: {
        let out = [];
        for (const grp of schema.groups) {
            if (grp.tab !== tab)
                continue;
            out.push({ kind: "section", group: grp.id, label: grp.label });
            for (const spec of schema.options) {
                if (spec.group === grp.id && !spec.hidden)
                    out.push({ kind: "option", group: grp.id, key: spec.key, spec: spec });
            }
        }
        return out;
    }
    function groupShown(id) {
        return schema.options.some(spec => spec.group === id && shown(spec));
    }

    function formatValue(v, spec) {
        if (spec.display === "percent")
            return Math.round(v * 100) + " %";
        const text = spec.type === "real" ? Number(v).toFixed(2) : String(v);
        return spec.unit ? `${text} ${spec.unit}` : text;
    }

    // web #RRGGBBAA <-> Qt colour
    function toQt(web) {
        if (typeof web === "string" && web.length === 9)
            return "#" + web.slice(7) + web.slice(1, 7);
        return web || "transparent";
    }
    function toWeb(c) {
        const h = x => Math.round(x * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b) + (c.a < 0.999 ? h(c.a) : "");
    }

    Helper {
        id: helper
        topics: ["config", "schema", "presets", "bars"]
        onSchemaReceived: schema => page.schema = schema
        onDesignReceived: web => {
            if (!flush.running)
                page.d = web;
        }
        onPresetsReceived: list => page.presets = list
        onPresetFileReceived: result => page.fileResult = result
        onEditStateReceived: st => {
            page.unsavedChanges = st.dirty;
            page.canUndo = st.canUndo;
            page.saveError = st.error || "";
        }
        onBarsReceived: values => {
            page.liveBars = values;
            page.liveBarsAt = Date.now();
        }
        onConnectedChanged: if (connected) send({ type: "beginEdit" })
    }

    // ---- preview data ---------------------------------------------------------
    // the real song if one is playing, otherwise a stand-in
    Loader {
        id: mpris
        source: "MprisSource.qml"
    }
    readonly property var demoMedia: ({ track: i18n("Song title"), artist: i18n("Artist"), album: i18n("Album"), artUrl: "" })
    readonly property var previewMedia: mpris.item && mpris.item.media && mpris.item.media.track ? mpris.item.media : demoMedia

    // live bars while music plays, a gentle synthetic wave otherwise
    property var liveBars: []
    property double liveBarsAt: 0
    property bool liveFresh: false
    property var demoBars: []
    property real demoPhase: 0
    Timer {
        interval: 33
        repeat: true
        running: page.visible
        onTriggered: {
            page.liveFresh = Date.now() - page.liveBarsAt < 700 && page.liveBars.some(x => x > 15);
            if (page.liveFresh)
                return;
            page.demoPhase += 0.08;
            const n = page.g("bars.count", 24);
            let v = [];
            for (let i = 0; i < n; i++)
                v.push(Math.round(220 + 520 * Math.abs(Math.sin(page.demoPhase + i * 0.45) * Math.cos(page.demoPhase * 0.6 + i * 0.13))));
            page.demoBars = v;
        }
    }
    readonly property var previewBars: liveFresh ? liveBars : demoBars

    // a fixed bar shape for thumbnails, sized to each preset's bar count
    function thumbBars(n) {
        let v = [];
        for (let i = 0; i < n; i++)
            v.push(Math.round(250 + 600 * Math.abs(Math.sin(i * 0.55) * Math.cos(i * 0.21))));
        return v;
    }

    // helper sends web colours (#RRGGBBAA); the card wants Qt's #AARRGGBB
    function toQtDeep(v) {
        // lists that crossed a signal are array-like QVariantLists, not Arrays
        if (Array.isArray(v) || (v && typeof v === "object" && typeof v.length === "number"))
            return Array.from(v, toQtDeep);
        if (v && typeof v === "object") {
            let o = {};
            for (const k in v)
                o[k] = toQtDeep(v[k]);
            return o;
        }
        return typeof v === "string" && /^#[0-9a-fA-F]{8}$/.test(v) ? toQt(v) : v;
    }

    // ---- colour dialog shared by every swatch ------------------------------
    property string colorPath: ""
    property int colorIndex: -1

    function pickColor(path, index) {
        colorPath = path;
        colorIndex = index;
        const cur = index >= 0 ? g(path, [])[index] : g(path, "#ffffff");
        colorDialog.selectedColor = toQt(cur && cur.charAt(0) === "#" ? cur : "#ffffff");
        colorDialog.open();
    }

    ColorDialog {
        id: colorDialog
        options: ColorDialog.ShowAlphaChannel
        onAccepted: {
            const web = page.toWeb(selectedColor);
            if (page.colorIndex >= 0) {
                const list = page.g(page.colorPath, []).slice();
                list[page.colorIndex] = web;
                page.s(page.colorPath, list);
            } else {
                page.s(page.colorPath, web);
            }
        }
    }

    // ---- one component per option type ---------------------------------------
    // Each is created by a Loader whose `row` holds { key, spec }.
    component Swatch: QQC2.Button {
        property string web: "#ffffff"
        implicitWidth: Kirigami.Units.gridUnit * 2
        implicitHeight: Kirigami.Units.gridUnit * 1.5
        contentItem: Rectangle {
            radius: 3
            border.width: 1
            border.color: Kirigami.Theme.textColor
            color: page.toQt(parent.web)
        }
    }

    Component {
        id: boolControl
        QQC2.Switch {
            readonly property var row: parent ? parent.row : null
            Binding on checked {
                value: row ? page.g(row.key, row.spec.default) : false
            }
            onToggled: page.s(row.key, checked)
        }
    }

    Component {
        id: spinControl
        QQC2.SpinBox {
            readonly property var row: parent ? parent.row : null
            from: row ? row.spec.min : 0
            to: row ? row.spec.max : 100
            editable: true
            textFromValue: (v, locale) => row && row.spec.unit ? `${v} ${row.spec.unit}` : String(v)
            valueFromText: (text, locale) => parseInt(text)
            Binding on value {
                value: row ? page.g(row.key, row.spec.default) : 0
            }
            onValueModified: page.s(row.key, value)
        }
    }

    Component {
        id: sliderControl
        RowLayout {
            id: sr
            readonly property var row: parent ? parent.row : null
            readonly property bool isInt: row && row.spec.type === "int"
            QQC2.Slider {
                id: sl
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                from: sr.row ? sr.row.spec.min : 0
                to: sr.row ? sr.row.spec.max : 1
                stepSize: sr.isInt ? 1 : 0.01
                onMoved: page.s(sr.row.key, sr.isInt ? Math.round(value) : Number(value.toFixed(2)))
            }
            Binding {
                target: sl
                property: "value"
                value: sr.row ? page.g(sr.row.key, sr.row.spec.default) : 0
                when: !sl.pressed
            }
            QQC2.Label {
                text: sr.row ? page.formatValue(sl.value, sr.row.spec) : ""
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            }
        }
    }

    Component {
        id: enumControl
        QQC2.ComboBox {
            id: cb
            readonly property var row: parent ? parent.row : null
            textRole: "text"
            valueRole: "value"
            model: row ? row.spec.values.map(v => ({ text: i18n(v.label), value: v.value })) : []
            Binding on currentIndex {
                value: cb.row ? cb.indexOfValue(page.g(cb.row.key, cb.row.spec.default)) : -1
            }
            onActivated: page.s(row.key, currentValue)
        }
    }

    Component {
        id: colorControl
        Swatch {
            readonly property var row: parent ? parent.row : null
            web: row ? page.g(row.key, row.spec.default) : "#ffffff"
            onClicked: page.pickColor(row.key, -1)
        }
    }

    Component {
        id: colorOrAutoControl
        RowLayout {
            id: ca
            readonly property var row: parent ? parent.row : null
            readonly property bool isAuto: row ? page.g(row.key, row.spec.default) === row.spec.auto : true
            QQC2.CheckBox {
                text: ca.row ? i18n(ca.row.spec.autoLabel) : ""
                checked: ca.isAuto
                onToggled: page.s(ca.row.key, checked ? ca.row.spec.auto : "#ffffff")
            }
            Swatch {
                visible: !ca.isAuto
                web: ca.row ? page.g(ca.row.key, "#ffffff") : "#ffffff"
                onClicked: page.pickColor(ca.row.key, -1)
            }
        }
    }

    Component {
        id: colorListControl
        RowLayout {
            id: cl
            readonly property var row: parent ? parent.row : null
            readonly property var list: row ? page.g(row.key, row.spec.default) : []
            Repeater {
                model: cl.list
                delegate: Swatch {
                    required property var modelData
                    required property int index
                    web: modelData
                    onClicked: page.pickColor(cl.row.key, index)
                }
            }
            QQC2.Button {
                icon.name: "list-add"
                QQC2.ToolTip.text: i18n("Add color")
                QQC2.ToolTip.visible: hovered
                onClicked: page.s(cl.row.key, cl.list.concat([cl.list.length ? cl.list[cl.list.length - 1] : "#ffffff"]))
            }
            QQC2.Button {
                icon.name: "list-remove"
                enabled: cl.list.length > 0
                QQC2.ToolTip.text: i18n("Remove the last one")
                QQC2.ToolTip.visible: hovered
                onClicked: page.s(cl.row.key, cl.list.slice(0, -1))
            }
        }
    }

    Component {
        id: stringControl
        QQC2.TextField {
            readonly property var row: parent ? parent.row : null
            Layout.minimumWidth: Kirigami.Units.gridUnit * 12
            text: row ? page.g(row.key, row.spec.default) : ""
            onEditingFinished: page.s(row.key, text)
        }
    }

    Component {
        id: stringListControl
        QQC2.TextField {
            readonly property var row: parent ? parent.row : null
            Layout.minimumWidth: Kirigami.Units.gridUnit * 12
            placeholderText: i18n("comma separated")
            text: row ? page.g(row.key, row.spec.default).join(", ") : ""
            onEditingFinished: page.s(row.key, text.split(",").map(x => x.trim()).filter(x => x !== ""))
        }
    }

    function componentFor(spec) {
        switch (spec.type) {
        case "bool": return boolControl;
        case "int": return spec.slider ? sliderControl : spinControl;
        case "real": return sliderControl;
        case "enum": return enumControl;
        case "color": return colorControl;
        case "colorOrAuto": return colorOrAutoControl;
        case "colorList": return colorListControl;
        case "stringList": return stringListControl;
        default: return stringControl;
        }
    }

    // ---- header: live preview, actions and tabs ------------------------------
    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
            Layout.margins: Kirigami.Units.largeSpacing
            // only once the helper has sent the config: Card needs every key
            active: page.d.panel !== undefined
            sourceComponent: Card {
                cfg: page.toQtDeep(page.d)
                media: page.previewMedia
                showProgress: true
                positionMs: 74000
                lengthMs: 196000
                barValues: page.previewBars
                // the preview's controls drive the real player too
                onAction: (name, value) => {
                    if (mpris.item)
                        mpris.item.act(name, value);
                }
            }
        }

        RowLayout {
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            QQC2.TabBar {
                id: tabBar
                Layout.fillWidth: true
                Repeater {
                    model: page.schema.tabs || []
                    delegate: QQC2.TabButton {
                        required property var modelData
                        text: i18n(modelData.label)
                        checked: page.tab === modelData.id
                        onClicked: page.tab = modelData.id
                    }
                }
            }
            QQC2.ToolButton {
                icon.name: "edit-undo"
                text: i18n("Undo")
                enabled: page.canUndo
                onClicked: page.act({ type: "undo" })
            }
            QQC2.ToolButton {
                icon.name: "edit-reset"
                text: i18n("Reset")
                QQC2.ToolTip.text: i18n("Drop your changes and use the preset as it is")
                QQC2.ToolTip.visible: hovered
                onClicked: page.act({ type: "resetDesign" })
            }
        }
    }

    // ---- presets tab ----------------------------------------------------------
    ColumnLayout {
        visible: page.tab === "presets"
        spacing: Kirigami.Units.largeSpacing

        GridLayout {
            Layout.fillWidth: true
            columns: page.width > Kirigami.Units.gridUnit * 40 ? 3 : 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing
            uniformCellWidths: true

            Repeater {
                model: page.presets
                delegate: QQC2.AbstractButton {
                    id: thumb
                    required property var modelData
                    readonly property bool current: modelData.name === page.g("presetName", "")
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    onClicked: page.act({ type: "setPreset", name: modelData.name })

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        // drawn at a real widget size, then scaled down, so the
                        // thumbnail looks like the widget instead of a squashed copy
                        Item {
                            id: thumbFrame
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * page.thumbH / page.thumbW
                            clip: true
                            Card {
                                width: page.thumbW
                                height: page.thumbH
                                scale: thumbFrame.width / page.thumbW
                                transformOrigin: Item.TopLeft
                                cfg: page.toQtDeep(thumb.modelData.config)
                                media: page.demoMedia
                                showProgress: true
                                positionMs: 74000
                                lengthMs: 196000
                                barValues: page.thumbBars(thumb.modelData.config.bars.count)
                                liveBars: false
                                interactive: false
                            }
                        }
                        RowLayout {
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: thumb.modelData.name
                                font.bold: thumb.current
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                            QQC2.ToolButton {
                                visible: thumb.modelData.user
                                icon.name: "edit-delete"
                                display: QQC2.AbstractButton.IconOnly
                                text: i18n("Delete this preset")
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                onClicked: page.act({ type: "deletePreset", name: thumb.modelData.name })
                            }
                        }
                    }
                    background: Rectangle {
                        radius: Kirigami.Units.cornerRadius
                        color: thumb.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.12) : "transparent"
                        border.width: thumb.current ? 2 : 1
                        border.color: thumb.current ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    }
                    padding: Kirigami.Units.smallSpacing
                }
            }
        }

        RowLayout {
            QQC2.Label {
                text: i18n("Save current design as:")
            }
            QQC2.TextField {
                id: presetName
                Layout.fillWidth: true
                placeholderText: i18n("preset name")
                maximumLength: 64
            }
            QQC2.Button {
                text: i18n("Save")
                icon.name: "document-save"
                enabled: presetName.text.trim() !== ""
                onClicked: {
                    page.act({ type: "savePreset", name: presetName.text.trim() });
                    presetName.text = "";
                }
            }
        }
        RowLayout {
            QQC2.Button {
                text: i18n("Import preset…")
                icon.name: "document-import"
                onClicked: {
                    page.fileResult = null;
                    importDialog.open();
                }
            }
            QQC2.Button {
                text: i18n("Export design…")
                icon.name: "document-export"
                QQC2.ToolTip.text: i18n("Saves the design as it looks now to a file you can share")
                QQC2.ToolTip.visible: hovered
                onClicked: {
                    page.fileResult = null;
                    exportDialog.selectedFile = exportDialog.currentFolder + "/" + encodeURIComponent(page.g("presetName", "design")) + ".json";
                    exportDialog.open();
                }
            }
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.fileResult !== null
            type: page.fileResult && page.fileResult.error ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
            text: page.fileMessage(page.fileResult)
            // no close button: it would break the binding above; the message
            // goes away with the next import or export
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.saveError === "preset_limit"
            type: Kirigami.MessageType.Warning
            text: i18n("You have reached the limit of 100 saved presets. Delete one, or save over an existing name.")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: i18n("Picking a preset replaces your bar settings; Undo brings them back. Nothing is kept until you press Apply or OK.")
        }
    }

    // ---- option tabs, generated from schema.json -------------------------------
    Kirigami.FormLayout {
        visible: page.tab !== "presets"

        Repeater {
            model: page.rows
            delegate: Loader {
                required property var modelData
                readonly property var row: modelData
                readonly property bool isSection: modelData.kind === "section"

                Kirigami.FormData.isSection: isSection
                Kirigami.FormData.label: isSection ? i18n(modelData.label) : i18n(modelData.spec.label) + ":"
                visible: isSection ? page.groupShown(modelData.group) : page.shown(modelData.spec)
                sourceComponent: isSection ? sectionComponent : page.componentFor(modelData.spec)
            }
        }

        QQC2.Button {
            visible: page.tab === "advanced"
            Kirigami.FormData.label: i18n("config.json:")
            text: i18n("Open config.json")
            icon.name: "document-edit"
            onClicked: Qt.openUrlExternally("file://" + StandardPaths.writableLocation(StandardPaths.ConfigLocation).toString().replace("file://", "") + "/nowplaying-viz/config.json")
        }
    }

    Component {
        id: sectionComponent
        Kirigami.Separator {}
    }
}
