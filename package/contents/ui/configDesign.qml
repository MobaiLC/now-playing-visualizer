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
// Changes are written to "overrides" through the helper and show up live.
KCM.SimpleKCM {
    id: page

    property var cfg_unused
    property var cfg_unusedDefault

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
        onTriggered: {
            helper.send({ type: "setDesign", changes: page.pending });
            page.pending = {};
        }
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
        topics: ["config", "schema"]
        onSchemaReceived: schema => page.schema = schema
        onDesignReceived: web => {
            if (!flush.running)
                page.d = web;
        }
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

    // ---- form ---------------------------------------------------------------
    Kirigami.FormLayout {

        // Presets are handled by hand: they are actions, not options.
        RowLayout {
            Kirigami.FormData.label: i18n("Preset:")
            QQC2.ComboBox {
                id: presetBox
                model: page.g("presetList", [])
                Binding on currentIndex {
                    value: presetBox.find(page.g("presetName", "lookas"))
                }
                onActivated: helper.send({ type: "setPreset", name: currentText })
            }
            QQC2.Button {
                text: i18n("Reset")
                icon.name: "edit-undo"
                QQC2.ToolTip.text: i18n("Drop your changes and use the preset as it is")
                QQC2.ToolTip.visible: hovered
                onClicked: helper.send({ type: "resetDesign" })
            }
            QQC2.Button {
                visible: page.g("userPresets", []).includes(page.g("presetName", ""))
                icon.name: "edit-delete"
                QQC2.ToolTip.text: i18n("Delete this preset")
                QQC2.ToolTip.visible: hovered
                onClicked: helper.send({ type: "deletePreset", name: page.g("presetName", "") })
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Save as:")
            QQC2.TextField {
                id: presetName
                placeholderText: i18n("preset name")
            }
            QQC2.Button {
                text: i18n("Save")
                icon.name: "document-save"
                enabled: presetName.text.trim() !== ""
                onClicked: {
                    helper.send({ type: "savePreset", name: presetName.text.trim() });
                    presetName.text = "";
                }
            }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: i18n("Changes apply instantly. Switching presets discards your bar settings.")
        }

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
            Kirigami.FormData.label: i18n("Advanced:")
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
