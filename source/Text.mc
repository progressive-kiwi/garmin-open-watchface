import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Font families. Values match the "fonts" enum in tools/gen_settings.py.
module Fonts {
    const SYSTEM = 0;
    const COND_BOLD = 1;
    const ROBOTO = 2;
    const BLACK = 3;
    const BIONIC = 4;
    const SERIF = 5;
    const ITALIC = 6;
    const QUARTZ = 7;          // slanted 7-segment, filled
    const QUARTZ_OUTLINE = 8;  // slanted 7-segment, hollow
    const QUARTZ_THIN = 9;     // slanted 7-segment, stroked
    const DOT = 10;            // 5x7 dot matrix, round dots
    const PIXEL = 11;          // 5x7 dot matrix, square blocks
    const DOT_FINE = 12;       // 5x7 dot matrix, small dots
    const SEGMENT = 13;        // upright 7-segment, filled

    function isSegment(f as Number) as Boolean {
        return f == QUARTZ || f == QUARTZ_OUTLINE || f == QUARTZ_THIN || f == SEGMENT;
    }

    function isDot(f as Number) as Boolean {
        return f == DOT || f == PIXEL || f == DOT_FINE;
    }

    function isProcedural(f as Number) as Boolean {
        return isSegment(f) || isDot(f);
    }

    //! Low-pixel variant of a family, used in always-on mode.
    function outlineOf(f as Number) as Number {
        if (f == QUARTZ || f == SEGMENT) {
            return QUARTZ_OUTLINE;
        }
        if (f == DOT || f == PIXEL) {
            return DOT_FINE;
        }
        return f;
    }
}

//! Draws text in any font family at an arbitrary visual height.
//! Coordinates: (x, y) is the anchor; y is the vertical center of the glyphs.
//! Justification: 0 = left, 1 = center, 2 = right.
class TextKit {
    var ghost as Boolean = false;
    var ghostColor as Number = 0x555555;

    private var _vectorCache as Dictionary<Number, VectorFont or Null> = {};

    // 7-segment bitmasks (bit 0 = a ... bit 6 = g) for "0123456789".
    private const SEG_DIGITS = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F];
    // Letters representable on seven segments.
    private const SEG_LETTERS = "ABCDEFGHIJLNOPRSTUY";
    private const SEG_LETTER_MASKS = [0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71, 0x3D, 0x76, 0x30, 0x1E,
                                      0x38, 0x54, 0x3F, 0x73, 0x50, 0x6D, 0x78, 0x3E, 0x6E];

    // 5x7 dot-matrix glyphs: 7 rows per glyph, 5 bits per row (bit 4 = left column).
    private const DOT_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-%/+";
    private const DOT_ROWS = [
        0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E, // 0
        0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E, // 1
        0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F, // 2
        0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E, // 3
        0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02, // 4
        0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E, // 5
        0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E, // 6
        0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08, // 7
        0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E, // 8
        0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C, // 9
        0x0E, 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, // A
        0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E, // B
        0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E, // C
        0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C, // D
        0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F, // E
        0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10, // F
        0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F, // G
        0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11, // H
        0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, // I
        0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C, // J
        0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11, // K
        0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F, // L
        0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11, // M
        0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, // N
        0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, // O
        0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10, // P
        0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D, // Q
        0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11, // R
        0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E, // S
        0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, // T
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, // U
        0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04, // V
        0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A, // W
        0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11, // X
        0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, // Y
        0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F, // Z
        0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00, // -
        0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03, // %
        0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10, // /
        0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00  // +
    ];

    function initialize() {
    }

    //! Drop cached vector fonts (e.g. after a settings change).
    function reset() as Void {
        _vectorCache = {};
    }

    // ------------------------------------------------------------ public --

    function draw(dc as Dc, x as Numeric, y as Numeric, text as String, family as Number,
                  h as Numeric, color as Number, just as Number) as Void {
        if (text.length() == 0) {
            return;
        }
        if (Fonts.isSegment(family) && !segSupports(text)) {
            family = Fonts.DOT;
        }
        if (Fonts.isProcedural(family)) {
            var w = width(dc, text, family, h);
            var x0 = x;
            if (just == 1) {
                x0 = x - w / 2.0;
            } else if (just == 2) {
                x0 = x - w;
            }
            if (Fonts.isSegment(family)) {
                drawSegments(dc, x0, y - h / 2.0, text, family, h, color);
            } else {
                drawDots(dc, x0, y - h / 2.0, text, family, h, color);
            }
            return;
        }
        var font = fontFor(text, family, h);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var j = Graphics.TEXT_JUSTIFY_LEFT;
        if (just == 1) {
            j = Graphics.TEXT_JUSTIFY_CENTER;
        } else if (just == 2) {
            j = Graphics.TEXT_JUSTIFY_RIGHT;
        }
        dc.drawText(x, y, font, text, j | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function width(dc as Dc, text as String, family as Number, h as Numeric) as Number {
        if (Fonts.isSegment(family) && !segSupports(text)) {
            family = Fonts.DOT;
        }
        if (Fonts.isSegment(family)) {
            var w = 0.0;
            var chars = text.toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                w += segAdvance(chars[i], h);
            }
            return (w - h * 0.14).toNumber();
        }
        if (Fonts.isDot(family)) {
            var c = h / 7.0;
            var cols = 0;
            var chars = text.toUpper().toCharArray();
            for (var i = 0; i < chars.size(); i++) {
                cols += dotCols(chars[i]) + 1;
            }
            return ((cols - 1) * c).toNumber();
        }
        return dc.getTextWidthInPixels(text, fontFor(text, family, h));
    }

    // ----------------------------------------------------- system/vector --

    function fontFor(text as String, family as Number, h as Numeric) as FontType {
        if (family != Fonts.SYSTEM && (Graphics has :getVectorFont)) {
            var size = (h * 1.38 + 0.5).toNumber();
            var key = family * 1000 + size;
            if (!_vectorCache.hasKey(key)) {
                var vf = null;
                try {
                    vf = Graphics.getVectorFont({:face => faces(family), :size => size});
                } catch (e) {
                    vf = null;
                }
                _vectorCache[key] = vf;
            }
            var cached = _vectorCache[key];
            if (cached != null) {
                return cached;
            }
        }
        return systemFont(text, h);
    }

    private function faces(family as Number) as Array<String> {
        switch (family) {
            case Fonts.ROBOTO:
                return ["RobotoRegular", "RobotoCondensedRegular", "YantramanavRegular"];
            case Fonts.BLACK:
                return ["RobotoBlack", "RobotoCondensedBold", "BionicBold"];
            case Fonts.BIONIC:
                return ["BionicBold", "BionicSemiBold", "RobotoCondensedBold"];
            case Fonts.SERIF:
                return ["PridiSemiBoldGarmin", "PridiRegularGarmin", "PridiRegular"];
            case Fonts.ITALIC:
                return ["RobotoCondensedRegularItalic", "RobotoItalic", "RobotoCondensedRegular"];
        }
        return ["RobotoCondensedBold", "BionicBold", "RobotoRegular"];
    }

    //! Largest built-in font whose digit height fits h.
    private function systemFont(text as String, h as Numeric) as FontDefinition {
        var numeric = true;
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (!((c >= '0' && c <= '9') || c == ':')) {
                numeric = false;
                break;
            }
        }
        var list = numeric
            ? [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM,
               Graphics.FONT_NUMBER_MILD, Graphics.FONT_SMALL, Graphics.FONT_XTINY]
            : [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY,
               Graphics.FONT_XTINY];
        var ratio = numeric ? 0.62 : 0.66;
        for (var i = 0; i < list.size(); i++) {
            if (Graphics.getFontHeight(list[i]) * ratio <= h * 1.12) {
                return list[i] as FontDefinition;
            }
        }
        return list[list.size() - 1] as FontDefinition;
    }

    // ---------------------------------------------------------- segments --

    private function segMask(c as Char) as Number {
        if (c >= '0' && c <= '9') {
            return SEG_DIGITS[c.toNumber() - 48];
        }
        if (c == '-') {
            return 0x40;
        }
        var i = SEG_LETTERS.find(c.toString().toUpper());
        if (i != null) {
            return SEG_LETTER_MASKS[i];
        }
        return 0;
    }

    private function segSupports(text as String) as Boolean {
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c != ' ' && c != ':' && c != '.' && c != '-' && segMask(c) == 0) {
                return false;
            }
        }
        return true;
    }

    private function segAdvance(c as Char, h as Numeric) as Numeric {
        var sp = h * 0.14;
        if (c == ':' || c == '.') {
            return h * 0.13 * 1.4 + sp;
        }
        if (c == ' ') {
            return h * 0.3 + sp;
        }
        return h * 0.52 + sp;
    }

    private function drawSegments(dc as Dc, x as Numeric, top as Numeric, text as String, family as Number,
                                  h as Numeric, color as Number) as Void {
        var slant = (family == Fonts.SEGMENT) ? 0.0 : 0.09;
        var t = h * ((family == Fonts.QUARTZ_THIN) ? 0.07 : 0.13);
        if (t < 2) {
            t = 2.0;
        }
        var w = h * 0.52;
        var midY = top + h / 2.0;
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c == ':' || c == '.') {
                var dw = h * 0.13 * 1.4;
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                var ys = (c == ':') ? [top + h * 0.3, top + h * 0.7] : [top + h - dw / 2];
                for (var k = 0; k < ys.size(); k++) {
                    var cx = x + dw / 2 + (midY - ys[k]) * slant;
                    if (family == Fonts.QUARTZ_OUTLINE) {
                        dc.setPenWidth(1);
                        dc.drawRectangle(cx - dw / 2, ys[k] - dw / 2, dw, dw);
                    } else {
                        dc.fillRectangle(cx - dw / 2, ys[k] - dw / 2, dw, dw);
                    }
                }
            } else if (c != ' ') {
                drawSegDigit(dc, x, top, w, h, t, segMask(c), family, slant, color);
            }
            x += segAdvance(c, h);
        }
        dc.setPenWidth(1);
    }

    private function drawSegDigit(dc as Dc, x as Numeric, top as Numeric, w as Numeric, h as Numeric, t as Numeric,
                                  mask as Number, family as Number, slant as Numeric, color as Number) as Void {
        var g = t * 0.3;
        var l = x + t / 2;
        var r = x + w - t / 2;
        var tp = top + t / 2;
        var m = top + h / 2.0;
        var b = top + h - t / 2;
        var segs = [
            [l + g, tp, r - g, tp], [r, tp + g, r, m - g], [r, m + g, r, b - g],
            [l + g, b, r - g, b], [l, m + g, l, b - g], [l, tp + g, l, m - g], [l + g, m, r - g, m]
        ];
        for (var pass = 0; pass < 2; pass++) {
            if (pass == 0 && !ghost) {
                continue;
            }
            dc.setColor(pass == 0 ? ghostColor : color, Graphics.COLOR_TRANSPARENT);
            for (var s = 0; s < 7; s++) {
                var lit = (mask & (1 << s)) != 0;
                if ((pass == 0 && lit) || (pass == 1 && !lit)) {
                    continue;
                }
                var sg = segs[s];
                if (family == Fonts.QUARTZ_THIN) {
                    dc.setPenWidth(t.toNumber());
                    dc.drawLine(sg[0] + (m - sg[1]) * slant, sg[1], sg[2] + (m - sg[3]) * slant, sg[3]);
                } else {
                    var pts = segPoly(sg[0], sg[1], sg[2], sg[3], t, m, slant);
                    if (family == Fonts.QUARTZ_OUTLINE) {
                        dc.setPenWidth(1);
                        Geo.strokePoly(dc, pts);
                    } else {
                        dc.fillPolygon(pts);
                    }
                }
            }
        }
    }

    //! Hexagonal segment between two points with thickness t, slanted around midY.
    private function segPoly(x0 as Numeric, y0 as Numeric, x1 as Numeric, y1 as Numeric, t as Numeric,
                             midY as Numeric, slant as Numeric) as Array<Point2D> {
        var len = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
        if (len < 1) {
            len = 1.0;
        }
        var dx = (x1 - x0) / len;
        var dy = (y1 - y0) / len;
        var hw = t / 2;
        var nx = -dy * hw;
        var ny = dx * hw;
        var ax = dx * hw;
        var ay = dy * hw;
        var raw = [
            [x0, y0], [x0 + ax + nx, y0 + ay + ny], [x1 - ax + nx, y1 - ay + ny],
            [x1, y1], [x1 - ax - nx, y1 - ay - ny], [x0 + ax - nx, y0 + ay - ny]
        ];
        var out = new Array<Point2D>[6];
        for (var i = 0; i < 6; i++) {
            out[i] = [raw[i][0] + (midY - raw[i][1]) * slant, raw[i][1]];
        }
        return out;
    }

    // --------------------------------------------------------------- dots --

    private function dotCols(c as Char) as Number {
        if (c == ':' || c == '.') {
            return 1;
        }
        if (c == ' ') {
            return 2;
        }
        return 5;
    }

    private function drawDots(dc as Dc, x as Numeric, top as Numeric, text as String, family as Number,
                              h as Numeric, color as Number) as Void {
        var c = h / 7.0;
        var rad = c * ((family == Fonts.DOT_FINE) ? 0.26 : 0.38);
        if (rad < 1) {
            rad = 1.0;
        }
        var sq = c * 0.84;
        if (sq < 1) {
            sq = 1.0;
        }
        // Unlit dots at half the ghost intensity: dense matrices read poorly otherwise.
        var dim = (ghostColor >> 1) & 0x7F7F7F;
        var chars = text.toUpper().toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i];
            var cols = dotCols(ch);
            if (ch == ':' || ch == '.') {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                var rows = (ch == ':') ? [2, 4] : [6];
                for (var k = 0; k < rows.size(); k++) {
                    dot(dc, x, top + rows[k] * c, c, rad, sq, family);
                }
            } else if (ch != ' ') {
                var gi = DOT_CHARS.find(ch.toString());
                for (var pass = 0; pass < 2; pass++) {
                    if (pass == 0 && !ghost) {
                        continue;
                    }
                    dc.setColor(pass == 0 ? dim : color, Graphics.COLOR_TRANSPARENT);
                    for (var row = 0; row < 7; row++) {
                        var bits = (gi == null) ? 0 : DOT_ROWS[gi * 7 + row];
                        for (var col = 0; col < 5; col++) {
                            var lit = (bits & (0x10 >> col)) != 0;
                            if (lit == (pass == 1)) {
                                dot(dc, x + col * c, top + row * c, c, rad, sq, family);
                            }
                        }
                    }
                }
            }
            x += (cols + 1) * c;
        }
    }

    private function dot(dc as Dc, x as Numeric, y as Numeric, c as Numeric, rad as Numeric, sq as Numeric,
                         family as Number) as Void {
        if (family == Fonts.PIXEL) {
            dc.fillRectangle(x, y, sq, sq);
        } else {
            dc.fillCircle(x + c / 2, y + c / 2, rad);
        }
    }
}
