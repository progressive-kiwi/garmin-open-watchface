import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! Digital layouts.
class DigitalFace {
    var cfg as Config;
    var kit as TextKit;
    var fields as Fields;
    var data as DataSource;
    //! Burn-in rules apply (AMOLED): always-on digits may switch to hollow variants.
    var amoled as Boolean = false;

    //! Where seconds go for the current layout: [x, y, h, just]. Set by draw().
    var secAnchor as Array<Numeric> = [0, 0, 0, 0];

    //! Pre-rendered seconds digits for procedural fonts (7-segment, dot matrix): drawing them takes
    //! dozens of polygons or circles, a cached digit is one bitmap copy. Lives in the graphics pool.
    private var _glyphs as Array<BufferedBitmapReference or BufferedBitmap or Null> = new Array<BufferedBitmapReference or BufferedBitmap or Null>[10];
    private var _glyphKey as String = "";
    private var _secBox as Array<Number>? = null;

    function initialize(config as Config, textKit as TextKit, f as Fields, source as DataSource) {
        cfg = config;
        kit = textKit;
        fields = f;
        data = source;
    }

    function timeHeight(r as Numeric) as Numeric {
        return r * [0.30, 0.38, 0.46, 0.56][cfg.TimeSize];
    }

    private function sep() as String {
        return [":", "", " "][cfg.Separator];
    }

    //! Width of "H:MM" at height h.
    function timeWidth(dc as Dc, parts as Array<String>, font as Number, h as Numeric) as Number {
        return kit.width(dc, parts[0] + sep() + parts[1], font, h);
    }

    //! Two-tone "H:MM". just: 0 left, 1 center, 2 right. Returns the right edge x.
    function drawTime(dc as Dc, x as Numeric, y as Numeric, parts as Array<String>, font as Number, h as Numeric,
                      just as Number, hourColor as Number, minColor as Number, sepColor as Number,
                      ghost as Boolean) as Numeric {
        var s = sep();
        var full = kit.width(dc, parts[0] + s + parts[1], font, h);
        var x0 = x;
        if (just == 1) {
            x0 = x - full / 2.0;
        } else if (just == 2) {
            x0 = x - full;
        }
        // Measure prefixes so procedural fonts keep their own spacing.
        var wh = kit.width(dc, parts[0], font, h);
        var whs = kit.width(dc, parts[0] + s, font, h);
        var wm = kit.width(dc, parts[1], font, h);
        kit.ghost = ghost;
        kit.draw(dc, x0, y, parts[0], font, h, hourColor, 0);
        if (s.length() > 0 && !s.equals(" ")) {
            var sw = kit.width(dc, s, font, h);
            kit.draw(dc, x0 + wh + (whs - wh - sw) / 2.0, y, s, font, h, sepColor, 0);
        }
        kit.draw(dc, x0 + full - wm, y, parts[1], font, h, minColor, 0);
        kit.ghost = false;
        return x0 + full;
    }

    //! Shrink h so the time fits maxW.
    private function fitTime(dc as Dc, parts as Array<String>, font as Number, h as Numeric, maxW as Numeric) as Numeric {
        var w = timeWidth(dc, parts, font, h);
        return (w > maxW) ? h * maxW / w : h;
    }

    function draw(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        _secBox = null;
        var parts = data.timeParts();
        var font = cfg.TimeFont;
        var t = timeHeight(r);
        var hc = cfg.cHourDigits;
        var mc = cfg.cMinuteDigits;
        var sc = cfg.fg2;
        var types = [cfg.Field1, cfg.Field2, cfg.Field3, cfg.Field4];
        var vc = cfg.cField;
        var lc = cfg.cLabel;
        var iconsY = cy - r * 0.74;
        // Seconds hang to the right of the time; keep room for them.
        var room = (cfg.SecondsMode != 0) ? r * 0.25 : 0;

        fields.drawGauges(dc, cx, cy, r, r * 0.05, (r * 0.03).toNumber(), 100);

        switch (cfg.DigitalLayout) {
            case 1: { // stacked hours over minutes
                t = t * 0.95;
                var hy = cy - t * 0.62;
                var my = cy + t * 0.62;
                kit.ghost = cfg.Ghost;
                kit.draw(dc, cx, hy, parts[0].length() < 2 ? "0" + parts[0] : parts[0], font, t, hc, 1);
                kit.draw(dc, cx, my, parts[1], font, t, mc, 1);
                kit.ghost = false;
                var mw = kit.width(dc, parts[1], font, t);
                secAnchor = [cx + mw / 2 + r * 0.04, my + t * 0.3, t * 0.32, 0];
                ampm(dc, cx + kit.width(dc, parts[0], font, t) / 2 + r * 0.04, hy - t * 0.3, r, parts[2]);
                fields.draw(dc, cx - r * 0.74, cy, types[0], Slot.STACKED, r, 1, vc, lc, 0.85);
                fields.draw(dc, cx + r * 0.74, cy, types[1], Slot.STACKED, r, 1, vc, lc, 0.85);
                fields.draw(dc, cx, cy + r * 0.84, types[2], Slot.INLINE, r, 1, vc, lc, 1.0);
                iconsY = cy - r * 0.86;
                break;
            }
            case 2: { // big
                t = fitTime(dc, parts, font, t * 1.3, r * 1.7);
                drawTime(dc, cx, cy, parts, font, t, 1, hc, mc, sc, cfg.Ghost);
                secAnchor = [cx, cy + t / 2 + r * 0.3, r * 0.1, 1];
                ampm(dc, cx + timeWidth(dc, parts, font, t) / 2 - r * 0.05, cy - t / 2 - r * 0.06, r, parts[2]);
                fields.draw(dc, cx, cy - t / 2 - r * 0.17, types[0], Slot.INLINE, r, 1, vc, lc, 1.1);
                fields.draw(dc, cx, cy + t / 2 + r * 0.15, types[1], Slot.INLINE, r, 1, vc, lc, 1.1);
                iconsY = cy - r * 0.8;
                break;
            }
            case 3: { // sport: time up, three fields below
                t = fitTime(dc, parts, font, t * 0.9, r * 1.45 - room);
                var ty = cy - r * 0.1;
                var right = drawTime(dc, cx, ty, parts, font, t, 1, hc, mc, sc, cfg.Ghost);
                secAnchor = [right + r * 0.03, ty + t * 0.32, t * 0.3, 0];
                ampm(dc, right + r * 0.03, ty - t * 0.32, r, parts[2]);
                fields.draw(dc, cx, ty - t / 2 - r * 0.13, types[0], Slot.INLINE, r, 1, vc, lc, 1.0);
                fields.draw(dc, cx - r * 0.36, cy + r * 0.36, types[1], Slot.STACKED, r, 1, vc, lc, 1.0);
                fields.draw(dc, cx + r * 0.36, cy + r * 0.36, types[2], Slot.STACKED, r, 1, vc, lc, 1.0);
                fields.draw(dc, cx, cy + r * 0.7, types[3], Slot.STACKED, r, 1, vc, lc, 0.9);
                iconsY = cy - r * 0.78;
                break;
            }
            case 4: { // minimal
                t = fitTime(dc, parts, font, t, r * 1.6 - room);
                var right = drawTime(dc, cx, cy, parts, font, t, 1, hc, mc, sc, cfg.Ghost);
                secAnchor = [right + r * 0.03, cy + t * 0.32, t * 0.3, 0];
                ampm(dc, right + r * 0.03, cy - t * 0.32, r, parts[2]);
                fields.draw(dc, cx, cy + t / 2 + r * 0.16, types[0], Slot.INLINE, r, 1, vc, lc, 1.0);
                iconsY = cy - t / 2 - r * 0.2;
                break;
            }
            case 5: { // side: stacked time left, field column right
                t = t * 0.8;
                var x = cx + r * 0.08;
                var hy = cy - t * 0.62;
                var my = cy + t * 0.62;
                kit.ghost = cfg.Ghost;
                kit.draw(dc, x, hy, parts[0], font, t, hc, 2);
                kit.draw(dc, x, my, parts[1], font, t, mc, 2);
                kit.ghost = false;
                secAnchor = [x, my + t / 2 + r * 0.14, t * 0.3, 2];
                ampm(dc, x - kit.width(dc, parts[0], font, t) - r * 0.04, hy - t * 0.3, r, parts[2]);
                dc.setColor(cfg.accent, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawLine(x + r * 0.08, cy - t * 1.1, x + r * 0.08, cy + t * 1.1);
                dc.setPenWidth(1);
                var fx = x + r * 0.16;
                fields.draw(dc, fx, cy - r * 0.3, types[0], Slot.STACKED, r, 0, vc, lc, 0.85);
                fields.draw(dc, fx, cy, types[1], Slot.STACKED, r, 0, vc, lc, 0.85);
                fields.draw(dc, fx, cy + r * 0.3, types[2], Slot.STACKED, r, 0, vc, lc, 0.85);
                fields.draw(dc, cx, cy + r * 0.8, types[3], Slot.INLINE, r, 1, vc, lc, 1.0);
                iconsY = cy - r * 0.8;
                break;
            }
            default: { // classic
                t = fitTime(dc, parts, font, t, r * 1.55 - room);
                var right = drawTime(dc, cx, cy, parts, font, t, 1, hc, mc, sc, cfg.Ghost);
                secAnchor = [right + r * 0.03, cy + t * 0.32, t * 0.3, 0];
                ampm(dc, right + r * 0.03, cy - t * 0.32, r, parts[2]);
                fields.draw(dc, cx, cy - t / 2 - r * 0.15, types[0], Slot.INLINE, r, 1, vc, lc, 1.15);
                fields.draw(dc, cx - r * 0.34, cy + t / 2 + r * 0.2, types[1], Slot.STACKED, r, 1, vc, lc, 1.0);
                fields.draw(dc, cx + r * 0.34, cy + t / 2 + r * 0.2, types[2], Slot.STACKED, r, 1, vc, lc, 1.0);
                fields.draw(dc, cx, cy + r * 0.76, types[3], Slot.INLINE, r, 1, vc, lc, 1.0);
                iconsY = cy - t / 2 - r * 0.33;
            }
        }
        if (cfg.StatusIcons) {
            fields.drawStatus(dc, cx, iconsY, r, cfg.fg2);
        }
    }

    private function ampm(dc as Dc, x as Numeric, y as Numeric, r as Numeric, s as String) as Void {
        if (s.length() > 0) {
            kit.draw(dc, x, y, s, Fonts.COND_BOLD, r * 0.045, cfg.fg2, 0);
        }
    }

    //! Seconds at the anchor computed by the last draw(). Returns its box for partial updates.
    function drawSeconds(dc as Dc) as Array<Number> {
        var sec = Clock.time().sec;
        var a = secAnchor;
        var font = cfg.TimeFont;
        if (!Fonts.isProcedural(font) || !drawCachedSeconds(dc, sec, font, a)) {
            kit.draw(dc, a[0], a[1], sec.format("%02d"), font, a[2], cfg.accent, a[3] as Number);
        }
        return secondsBox(dc);
    }

    private function drawCachedSeconds(dc as Dc, sec as Number, font as Number, a as Array<Numeric>) as Boolean {
        var h = a[2];
        var key = font.toString() + "/" + h.toNumber() + "/" + cfg.accent + "/" + cfg.bg;
        if (!key.equals(_glyphKey)) {
            _glyphs = new Array<BufferedBitmapReference or BufferedBitmap or Null>[10];
            _glyphKey = key;
        }
        var pad = (h * 0.12).toNumber() + 2;
        var one = kit.width(dc, "8", font, h);
        var total = kit.width(dc, "88", font, h);
        var adv = total - one;
        var just = a[3] as Number;
        var x0 = a[0];
        if (just == 1) {
            x0 = a[0] - total / 2.0;
        } else if (just == 2) {
            x0 = a[0] - total;
        }
        var y = a[1] - h / 2 - pad;
        for (var i = 0; i < 2; i++) {
            var bmp = glyph(i == 0 ? sec / 10 : sec % 10, font, h, pad, one + pad * 2, h.toNumber() + pad * 2);
            if (bmp == null) {
                return false;
            }
            dc.drawBitmap(x0 + i * adv - pad, y, bmp);
        }
        return true;
    }

    private function glyph(d as Number, font as Number, h as Numeric, pad as Number, w as Number,
                           gh as Number) as BufferedBitmapReference or BufferedBitmap or Null {
        var b = _glyphs[d];
        if (b instanceof Graphics.BufferedBitmapReference && b.get() == null) {
            b = null;
        }
        if (b == null) {
            try {
                b = Graphics.createBufferedBitmap({:width => w, :height => gh});
            } catch (e) {
                return null;
            }
            var bb = b.get();
            if (bb == null) {
                return null;
            }
            var gdc = (bb as BufferedBitmap).getDc();
            if (gdc has :setAntiAlias) {
                gdc.setAntiAlias(true);
            }
            gdc.setColor(cfg.bg, cfg.bg);
            gdc.clear();
            kit.draw(gdc, pad, pad + h / 2.0, d.toString(), font, h, cfg.accent, 0);
            _glyphs[d] = b;
        }
        return b;
    }

    //! Area the seconds occupy, for partial-update clipping. Cached until the next layout pass.
    function secondsBox(dc as Dc) as Array<Number> {
        var box = _secBox;
        if (box != null) {
            return box;
        }
        var a = secAnchor;
        var font = cfg.TimeFont;
        var w = kit.width(dc, "88", font, a[2]) + 6;
        var h = (a[2] * 1.6).toNumber() + 4;
        var just = a[3] as Number;
        var x = a[0] - 3;
        if (just == 1) {
            x = a[0] - w / 2;
        } else if (just == 2) {
            x = a[0] - w + 3;
        }
        box = [x.toNumber(), (a[1] - h / 2).toNumber(), w.toNumber(), h];
        _secBox = box;
        return box;
    }

    // -------------------------------------------------------- always-on --

    function drawAod(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as Number, style as Number) as Void {
        var parts = data.timeParts();
        var font = (cfg.AodFont == 99) ? cfg.TimeFont : cfg.AodFont;
        if (amoled && cfg.AodOutline) {
            font = Fonts.outlineOf(font);
        }
        var t = fitTime(dc, parts, font, r * 0.34, r * 1.4);
        drawTime(dc, cx, cy, parts, font, t, 1, color, color, color, false);
        if (style == 3) {
            kit.draw(dc, cx, cy + t / 2 + r * 0.16, data.dateString(cfg.DateFormat), Fonts.COND_BOLD, r * 0.055, color, 1);
        }
    }
}
