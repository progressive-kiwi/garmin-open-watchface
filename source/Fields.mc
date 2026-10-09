import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! Field slot presentation kinds.
module Slot {
    const STACKED = 0;   // label above value
    const WINDOW = 1;    // value in a framed date window
    const SUBDIAL = 2;   // ring with progress, label and value inside
    const INLINE = 3;    // "LABEL value" on one line, small
}

//! Renders data fields, gauges and status icons.
class Fields {
    //! Labels use the condensed vector face where available; TextKit falls back to system fonts.
    const LABEL_FONT = Fonts.COND_BOLD;

    var cfg as Config;
    var kit as TextKit;
    var data as DataSource;

    function initialize(config as Config, textKit as TextKit, source as DataSource) {
        cfg = config;
        kit = textKit;
        data = source;
    }

    //! Draw field `type` at (x, y). r is the screen radius used for scaling.
    //! just: 0 left, 1 center, 2 right (STACKED and INLINE only).
    function draw(dc as Dc, x as Numeric, y as Numeric, type as Number, kind as Number, r as Numeric,
                  just as Number, valueColor as Number, labelColor as Number, scale as Float) as Void {
        if (type == F.OFF) {
            return;
        }
        var val = data.value(type);
        var lbl = cfg.FieldLabels == 1 ? data.label(type) : "";
        var font = cfg.FieldFont;
        var vh = r * 0.085 * scale;
        var lh = r * 0.042 * scale;

        if (kind == Slot.WINDOW) {
            var h = r * 0.075 * scale;
            var w = kit.width(dc, val, font, h) + r * 0.08;
            var bh = h + r * 0.07;
            dc.setColor(cfg.bg, cfg.bg);
            dc.fillRoundedRectangle(x - w / 2, y - bh / 2, w, bh, 4);
            dc.setColor(cfg.fg2, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x - w / 2, y - bh / 2, w, bh, 4);
            dc.setPenWidth(1);
            kit.draw(dc, x, y, val, font, h, valueColor, 1);
            return;
        }

        if (kind == Slot.SUBDIAL) {
            var sr = r * 0.19;
            var pen = (r * 0.02).toNumber();
            if (pen < 2) {
                pen = 2;
            }
            dc.setColor(cfg.fg2, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawCircle(x, y, sr);
            var f = data.fraction(type);
            if (f != null) {
                dc.setColor(cfg.accent, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(pen);
                Geo.arc(dc, x, y, sr - pen / 2 - 1, 90, f * 360, true);
                dc.setPenWidth(1);
            }
            if (lbl.length() > 0) {
                kit.draw(dc, x, y - sr * 0.38, lbl, LABEL_FONT, lh * 0.9, labelColor, 1);
                kit.draw(dc, x, y + sr * 0.15, val, font, fit(dc, val, font, vh * 0.85, sr * 1.6), valueColor, 1);
            } else {
                kit.draw(dc, x, y, val, font, fit(dc, val, font, vh, sr * 1.6), valueColor, 1);
            }
            return;
        }

        if (kind == Slot.INLINE) {
            var h = r * 0.065 * scale;
            if (lbl.length() == 0) {
                kit.draw(dc, x, y, val, font, h, valueColor, just);
                return;
            }
            var gap = r * 0.03;
            var lw = kit.width(dc, lbl, LABEL_FONT, lh);
            var vw = kit.width(dc, val, font, h);
            var x0 = x;
            if (just == 1) {
                x0 = x - (lw + gap + vw) / 2;
            } else if (just == 2) {
                x0 = x - (lw + gap + vw);
            }
            kit.draw(dc, x0, y, lbl, LABEL_FONT, lh, labelColor, 0);
            kit.draw(dc, x0 + lw + gap, y, val, font, h, valueColor, 0);
            return;
        }

        // STACKED: label and value centered as a block around y.
        if (lbl.length() > 0) {
            var gap = r * 0.035;
            var top = y - (lh + gap + vh) / 2;
            kit.draw(dc, x, top + lh / 2, lbl, LABEL_FONT, lh, labelColor, just);
            kit.draw(dc, x, top + lh + gap + vh / 2, val, font, vh, valueColor, just);
        } else {
            kit.draw(dc, x, y, val, font, vh, valueColor, just);
        }
    }

    //! Shrink height h until text fits maxW.
    function fit(dc as Dc, text as String, font as Number, h as Numeric, maxW as Numeric) as Numeric {
        var w = kit.width(dc, text, font, h);
        if (w > maxW && w > 0) {
            return h * maxW / w;
        }
        return h;
    }

    //! Edge gauges. inset = distance from the screen edge to the arc center line.
    function drawGauges(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, inset as Numeric,
                        pen as Number, span as Number) as Void {
        var metrics = [cfg.GaugeLeft, cfg.GaugeRight];
        var gr = r - inset;
        for (var i = 0; i < 2; i++) {
            if (metrics[i] == 0) {
                continue;
            }
            var f = data.gauge(metrics[i]);
            // Left gauge grows clockwise from bottom-left; right grows counter-clockwise from bottom-right.
            var start = (i == 0) ? 180 + span / 2 : 360 - span / 2;
            var cw = (i == 0);
            dc.setPenWidth(pen);
            dc.setColor(cfg.GhostColor == cfg.bg ? cfg.fg2 : cfg.GhostColor, Graphics.COLOR_TRANSPARENT);
            Geo.arc(dc, cx, cy, gr, start, span, cw);
            if (f != null) {
                dc.setColor(cfg.accent, Graphics.COLOR_TRANSPARENT);
                Geo.arc(dc, cx, cy, gr, start, f * span, cw);
            }
        }
        dc.setPenWidth(1);
    }

    //! Row of active status icons centered at (cx, y). Returns nothing when none are active.
    function drawStatus(dc as Dc, cx as Numeric, y as Numeric, r as Numeric, color as Number) as Void {
        var ds = System.getDeviceSettings();
        var icons = [] as Array<Number>;
        if (ds.phoneConnected) {
            icons.add(0);
        }
        if (ds.notificationCount > 0) {
            icons.add(1);
        }
        if (ds.alarmCount > 0) {
            icons.add(2);
        }
        if ((ds has :doNotDisturb) && ds.doNotDisturb) {
            icons.add(3);
        }
        if (System.getSystemStats().battery < 20) {
            icons.add(4);
        }
        var n = icons.size();
        if (n == 0) {
            return;
        }
        var s = r * 0.07;
        var gap = r * 0.045;
        var x = cx - (n * s + (n - 1) * gap) / 2 + s / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((s / 9).toNumber() < 1 ? 1 : (s / 9).toNumber());
        for (var i = 0; i < n; i++) {
            icon(dc, icons[i], x, y, s, color);
            x += s + gap;
        }
        dc.setPenWidth(1);
    }

    private function icon(dc as Dc, kind as Number, x as Numeric, y as Numeric, s as Numeric, color as Number) as Void {
        var h = s / 2;
        switch (kind) {
            case 0: // Bluetooth rune
                dc.drawLine(x - h * 0.5, y - h * 0.5, x + h * 0.5, y + h * 0.5);
                dc.drawLine(x + h * 0.5, y + h * 0.5, x, y + h);
                dc.drawLine(x, y + h, x, y - h);
                dc.drawLine(x, y - h, x + h * 0.5, y - h * 0.5);
                dc.drawLine(x + h * 0.5, y - h * 0.5, x - h * 0.5, y + h * 0.5);
                break;
            case 1: // envelope
                dc.drawRectangle(x - h, y - h * 0.7, s, h * 1.4);
                dc.drawLine(x - h, y - h * 0.7, x, y + h * 0.1);
                dc.drawLine(x, y + h * 0.1, x + h, y - h * 0.7);
                break;
            case 2: // alarm bell
                dc.fillCircle(x, y - h * 0.1, h * 0.7);
                dc.fillRectangle(x - h * 0.7, y - h * 0.1, h * 1.4, h * 0.6);
                dc.fillRectangle(x - h, y + h * 0.45, s, h * 0.2);
                dc.fillCircle(x, y + h * 0.85, h * 0.18);
                break;
            case 3: // do not disturb moon
                dc.fillCircle(x, y, h * 0.85);
                dc.setColor(cfg.bg, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + h * 0.45, y - h * 0.3, h * 0.7);
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                break;
            case 4: // low battery
                dc.drawRectangle(x - h, y - h * 0.5, s * 0.9, h);
                dc.fillRectangle(x + h * 0.8, y - h * 0.2, h * 0.2, h * 0.4);
                dc.fillRectangle(x - h + 2, y - h * 0.5 + 2, h * 0.3, h - 4);
                break;
        }
    }
}
