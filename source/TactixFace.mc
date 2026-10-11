import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Face digital/tactix: the original tactix (2014). Upright LCD time without separator, small seconds at
//! its top right, date above, battery, moon phase and one field below, and a ring of 60 dashes that
//! fills with the seconds. One display color on black (Config.tactix).
class TactixFace {
    var cfg as Config;
    var kit as TextKit;
    var fields as Fields;
    var data as DataSource;
    //! Burn-in rules apply (AMOLED): always-on digits may switch to hollow variants.
    var amoled as Boolean = false;

    //! Unlit ring dashes and the moon outline.
    const UNLIT = 0x555555;

    // Geometry of the last draw(): seconds anchor [left x, center y, height] and the ring.
    private var _sec as Array<Numeric> = [0, 0, 0];
    private var _cx as Numeric = 0;
    private var _cy as Numeric = 0;
    private var _r as Numeric = 0;
    private var _secBox as Array<Number>? = null;

    function initialize(config as Config, textKit as TextKit, f as Fields, source as DataSource) {
        cfg = config;
        kit = textKit;
        fields = f;
        data = source;
    }

    //! "0630": hours always two digits, no separator.
    private function timeText() as String {
        var parts = data.timeParts();
        var h = parts[0];
        return (h.length() < 2 ? "0" + h : h) + parts[1];
    }

    function draw(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        _cx = cx;
        _cy = cy;
        _r = r;
        _secBox = null;
        var color = cfg.fg;
        var time = timeText();
        var t = r * 0.48;
        var sh = t * 0.34;
        var tw = kit.width(dc, time, Fonts.SEGMENT, t);
        var sw = kit.width(dc, "88", Fonts.SEGMENT, sh);
        var gap = r * 0.05;
        var x0 = cx - (tw + gap + sw) / 2;
        kit.ghost = cfg.TactixGhost;
        kit.draw(dc, x0, cy, time, Fonts.SEGMENT, t, color, 0);
        kit.ghost = false;
        _sec = [x0 + tw + gap, cy - t / 2 + sh / 2, sh];
        var ampm = data.timeParts()[2];
        if (ampm.length() > 0) {
            kit.draw(dc, x0 + tw + gap, cy + t / 2 - r * 0.03, ampm, Fonts.PIXEL, r * 0.06, color, 0);
        }

        kit.draw(dc, cx, cy - r * 0.4, data.dateString(2), Fonts.PIXEL, r * 0.1, color, 1);
        drawBottom(dc, cx, cy + r * 0.42, r, color);
        if (cfg.TactixRing != 3) {
            // Seconds light up in drawSeconds; Minutes is static for the minute.
            var lit = (cfg.TactixRing == 1) ? Clock.time().min : -1;
            for (var i = 0; i < 60; i++) {
                dash(dc, i, i <= lit ? color : UNLIT);
            }
        }
        if (cfg.StatusIcons) {
            fields.drawStatus(dc, cx, cy - r * 0.62, r, color);
        }
    }

    //! Battery, moon phase and the bottom field, centered as one row.
    private function drawBottom(dc as Dc, cx as Numeric, y as Numeric, r as Numeric, color as Number) as Void {
        var bw = r * 0.17;
        var bh = r * 0.085;
        var mr = r * 0.055;
        var gap = r * 0.06;
        var vh = r * 0.1;
        var val = (cfg.TactixField == F.OFF) ? "" : data.value(cfg.TactixField);
        var vw = (val.length() > 0) ? kit.width(dc, val, Fonts.SEGMENT, vh) + gap : 0;
        var x = cx - (bw + gap + mr * 2 + vw) / 2;
        battery(dc, x, y, bw, bh, color);
        x += bw + gap;
        moon(dc, x + mr, y, mr, color);
        x += mr * 2 + gap;
        if (vw > 0) {
            kit.draw(dc, x, y, val, Fonts.SEGMENT, vh, color, 0);
        }
    }

    private function battery(dc as Dc, x as Numeric, y as Numeric, w as Numeric, h as Numeric, color as Number) as Void {
        var nub = w * 0.08;
        var bw = w - nub;
        var line = (h * 0.15).toNumber();
        if (line < 1) {
            line = 1;
        }
        var top = y - h / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, top, bw, h);
        dc.fillRectangle(x + bw, y - h * 0.25, nub, h * 0.5);
        dc.setColor(cfg.bg, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + line, top + line, bw - line * 2, h - line * 2);
        var f = data.fraction(F.BATTERY);
        if (f != null) {
            var pad = line * 2;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + pad, top + pad, (bw - pad * 2) * (f as Float), h - pad * 2);
        }
    }

    //! Lit disk with a shadow disk of the same size sliding across it: waxing lights the right side,
    //! waning the left. Clipped to the moon's box so the shadow cannot reach neighbors.
    private function moon(dc as Dc, x as Numeric, y as Numeric, mr as Numeric, color as Number) as Void {
        var p = data.moonPhase();
        var d = (p < 0.5) ? -4 * mr * p : 4 * mr * (1 - p);
        dc.setClip(x - mr - 1, y - mr - 1, mr * 2 + 3, mr * 2 + 3);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, mr);
        dc.setColor(cfg.bg, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + d, y, mr);
        dc.setColor(UNLIT, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, mr);
        dc.clearClip();
    }

    private function dashPoly(i as Number) as Array<Point2D> {
        var a = i * Math.PI / 30;
        var hw = 0.03;
        var ri = _r * 0.87;
        var ro = _r * 0.97;
        return [Geo.polar(_cx, _cy, ri, a - hw), Geo.polar(_cx, _cy, ro, a - hw),
                Geo.polar(_cx, _cy, ro, a + hw), Geo.polar(_cx, _cy, ri, a + hw)] as Array<Point2D>;
    }

    private function dash(dc as Dc, i as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(dashPoly(i));
    }

    //! Seconds digits and, with the Seconds ring, dashes 0..sec. Returns the digits' box.
    function drawSeconds(dc as Dc) as Array<Number> {
        drawSecondsDigits(dc);
        if (cfg.TactixRing == 0) {
            var sec = Clock.time().sec;
            for (var i = 0; i <= sec; i++) {
                dash(dc, i, cfg.fg);
            }
        }
        return secondsBox(dc);
    }

    function drawSecondsDigits(dc as Dc) as Void {
        kit.ghost = cfg.TactixGhost;
        kit.draw(dc, _sec[0], _sec[1], Clock.time().sec.format("%02d"), Fonts.SEGMENT, _sec[2], cfg.fg, 0);
        kit.ghost = false;
    }

    //! Partial update: light the current second's dash, clipped to it. Earlier dashes stay on screen.
    function drawSecondDash(dc as Dc) as Void {
        if (cfg.TactixRing != 0) {
            return;
        }
        var pts = dashPoly(Clock.time().sec);
        var b = Geo.bounds(pts, 1);
        dc.setClip(b[0], b[1], b[2], b[3]);
        dc.setColor(cfg.fg, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    //! Area of the seconds digits, for partial-update clipping. Cached until the next draw().
    function secondsBox(dc as Dc) as Array<Number> {
        var box = _secBox;
        if (box != null) {
            return box;
        }
        var h = _sec[2];
        var w = kit.width(dc, "88", Fonts.SEGMENT, h) + 6;
        var bh = (h * 1.6).toNumber() + 4;
        box = [(_sec[0] - 3).toNumber(), (_sec[1] - bh / 2).toNumber(), w.toNumber(), bh];
        _secBox = box;
        return box;
    }

    // -------------------------------------------------------- always-on --

    function drawAod(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as Number, style as Number) as Void {
        var font = (cfg.AodFont == 99) ? Fonts.SEGMENT : cfg.AodFont;
        if (amoled && cfg.AodOutline) {
            font = Fonts.outlineOf(font);
        }
        var time = timeText();
        var t = r * 0.34;
        var w = kit.width(dc, time, font, t);
        if (w > r * 1.4) {
            t = t * r * 1.4 / w;
        }
        kit.draw(dc, cx, cy, time, font, t, color, 1);
        if (style == 3) {
            kit.draw(dc, cx, cy + t / 2 + r * 0.16, data.dateString(2), Fonts.PIXEL, r * 0.055, color, 1);
        }
    }
}
