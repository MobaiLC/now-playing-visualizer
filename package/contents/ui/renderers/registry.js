// SPDX-FileCopyrightText: 2026 MobaiLC
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Picks the renderer for the current config. To add a style:
//   1. write renderers/<style>.js exporting draw(f) (see bars.js),
//   2. import it below and add it to `styles`,
//   3. add the value to "bars.style" in code/schema.json.
.pragma library
.import "bars.js" as BarsStyle
.import "blocks.js" as BlocksStyle
.import "wave.js" as WaveStyle
.import "circle.js" as Circle
.import "peaks.js" as Peaks

var styles = {
    "bars": BarsStyle.draw,
    "blocks": BlocksStyle.draw,
    "wave": WaveStyle.draw
};

function draw(f) {
    const cfg = f.cfg;
    if (cfg.circle.enabled) {
        Circle.draw(f);
        if (cfg.peaks.enabled)
            Peaks.drawCircle(f);
        return;
    }
    (styles[cfg.style] || BarsStyle.draw)(f);
    if (cfg.peaks.enabled)
        (cfg.style === "wave" ? Peaks.drawWave : Peaks.draw)(f);
}
