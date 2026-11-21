// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Translation for the pages shared by Plasma and the standalone settings
// window. Not a .pragma library on purpose: an imported non-library script
// runs in a child of the importing file's QML context, so it sees the i18n
// functions Plasma's KLocalizedContext puts there. Outside Plasma there are
// none and the English text is used.

function fill(text, args) {
    return text.replace(/%(\d+)/g, (m, i) => i >= 1 && i <= args.length ? String(args[i - 1]) : m);
}

function tr(msgid, ...args) {
    return typeof i18n === "function" ? i18n(msgid, ...args) : fill(msgid, args);
}

function trp(singular, plural, n, ...args) {
    return typeof i18np === "function" ? i18np(singular, plural, n, ...args)
                                       : fill(Number(n) === 1 ? singular : plural, [n, ...args]);
}

function trc(context, msgid, ...args) {
    return typeof i18nc === "function" ? i18nc(context, msgid, ...args) : fill(msgid, args);
}
