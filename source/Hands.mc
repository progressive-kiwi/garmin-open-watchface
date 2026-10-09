import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Watch hand geometry and drawing. Styles match the "hands" / "shand" enums.
module Hands {
    const BATON = 0;
    const DAUPHINE = 1;
    const SWORD = 2;
    const LEAF = 3;
    const SKELETON = 4;
    const ARROW = 5;
    const NEEDLE = 6;
    const ROUNDED = 7;
    const BREGUET = 8;

    //! Hour or minute hand.
    //! @param outline Contrast color drawn around a filled hand, or null for none
    //! @param hollow Draw outline only (always-on mode)
    function draw(dc as Dc, cx as Numeric, cy as Numeric, angle as Numeric, style as Number, len as Numeric,
                  w as Numeric, tail as Numeric, color as Number, outline as Number?, hollow as Boolean) as Void {
        var pen = (w / 5).toNumber();
        if (pen < 2) {
            pen = 2;
        }

        if (style == ROUNDED) {
            var a = Geo.polar(cx, cy, -tail, angle);
            var b = Geo.polar(cx, cy, len, angle);
            if (outline != null && !hollow) {
                dc.setColor(outline, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(w.toNumber() + 3);
                dc.drawLine(a[0], a[1], b[0], b[1]);
                dc.fillCircle(b[0], b[1], w / 2 + 1.5);
                dc.fillCircle(a[0], a[1], w / 2 + 1.5);
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(hollow ? pen : w.toNumber());
            dc.drawLine(a[0], a[1], b[0], b[1]);
            if (!hollow) {
                dc.fillCircle(b[0], b[1], w / 2);
                dc.fillCircle(a[0], a[1], w / 2);
            }
            dc.setPenWidth(1);
            return;
        }

        var shapes = shapesFor(style, len, w, tail);
        for (var i = 0; i < shapes.size(); i++) {
            var pts = Geo.rotate(shapes[i], cx, cy, angle);
            var solid = !hollow && !(style == SKELETON && i == 0) && !(style == BREGUET && i == 1);
            if (solid) {
                if (outline != null) {
                    dc.setColor(outline, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(3);
                    Geo.strokePoly(dc, pts);
                }
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon(pts);
            } else {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(pen);
                Geo.strokePoly(dc, pts);
            }
        }
        dc.setPenWidth(1);
    }

    //! Hand outlines in local coordinates: x across, y outward. Multiple shapes allowed.
    function shapesFor(style as Number, l as Numeric, w as Numeric, t as Numeric) as Array<Array<Array<Numeric>>> {
        var h = w / 2.0;
        switch (style) {
            case DAUPHINE:
                return [[[-h, 0], [0, l], [h, 0], [0, -t * 0.6]]];
            case SWORD:
                return [[[-h, -t], [-h, l - w * 1.4], [0, l], [h, l - w * 1.4], [h, -t]]];
            case LEAF:
                return [[[-h * 0.25, -t], [-h * 0.85, l * 0.25], [-h * 1.1, l * 0.5], [-h * 0.8, l * 0.75],
                         [0, l], [h * 0.8, l * 0.75], [h * 1.1, l * 0.5], [h * 0.85, l * 0.25], [h * 0.25, -t]]];
            case SKELETON:
                // Hollow frame plus a filled lume insert at the tip.
                return [[[-h, -t], [-h, l - w * 1.4], [0, l], [h, l - w * 1.4], [h, -t]],
                        [[-h * 0.55, l * 0.55], [-h * 0.55, l - w * 1.5], [0, l - w * 0.5],
                         [h * 0.55, l - w * 1.5], [h * 0.55, l * 0.55]]];
            case ARROW:
                return [[[-h * 0.35, -t], [-h * 0.35, l * 0.74], [h * 0.35, l * 0.74], [h * 0.35, -t]],
                        [[-h * 1.4, l * 0.7], [0, l], [h * 1.4, l * 0.7]]];
            case NEEDLE:
                return [[[-h * 0.3 - 0.5, -t], [-h * 0.3 - 0.5, l], [h * 0.3 + 0.5, l], [h * 0.3 + 0.5, -t]]];
            case BREGUET:
                // Shaft, open moon ring, tip.
                return [[[-h * 0.4, -t], [-h * 0.4, l * 0.62], [h * 0.4, l * 0.62], [h * 0.4, -t]],
                        ring(0, l * 0.71, w * 0.75, 10),
                        [[-h * 0.45, l * 0.8], [0, l], [h * 0.45, l * 0.8]]];
        }
        return [[[-h, -t], [-h, l], [h, l], [h, -t]]];
    }

    //! Polygon approximating a circle in local coordinates.
    function ring(x as Numeric, y as Numeric, r as Numeric, n as Number) as Array<Array<Numeric>> {
        var out = new Array<Array<Numeric>>[n];
        for (var i = 0; i < n; i++) {
            var a = Math.PI * 2 * i / n;
            out[i] = [x + r * Math.cos(a), y + r * Math.sin(a)];
        }
        return out;
    }

    //! Second hand. Returns its bounding box [x, y, w, h] for partial-update clipping.
    function drawSecond(dc as Dc, cx as Numeric, cy as Numeric, angle as Numeric, style as Number, len as Numeric,
                        rUnit as Numeric, color as Number) as Array<Number> {
        var sw = (rUnit * 0.014).toNumber();
        if (sw < 2) {
            sw = 2;
        }
        var tail = rUnit * ((style == 2) ? 0.24 : 0.16);
        var a = Geo.polar(cx, cy, -tail, angle);
        var b = Geo.polar(cx, cy, len, angle);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(sw);
        dc.drawLine(a[0], a[1], b[0], b[1]);
        dc.setPenWidth(1);
        var pts = [a, b] as Array<Point2D>;
        var extra = sw;
        if (style == 1) {
            var p = Geo.polar(cx, cy, len * 0.74, angle);
            var r = rUnit * 0.04;
            dc.fillCircle(p[0], p[1], r);
            extra = r.toNumber() + 2;
        } else if (style == 2) {
            var r = rUnit * 0.05;
            var p = Geo.polar(cx, cy, -tail * 0.75, angle);
            dc.fillCircle(p[0], p[1], r);
            extra = r.toNumber() + 2;
        } else if (style == 3) {
            var tri = Geo.rotate([[-rUnit * 0.03, len - rUnit * 0.09], [0, len + 1], [rUnit * 0.03, len - rUnit * 0.09]],
                                 cx, cy, angle);
            dc.fillPolygon(tri);
            extra = (rUnit * 0.035).toNumber() + 2;
        } else if (style == 4) {
            var s = rUnit * 0.03;
            var sq = Geo.rotate([[-s, len * 0.8 - s], [-s, len * 0.8 + s], [s, len * 0.8 + s], [s, len * 0.8 - s]],
                                cx, cy, angle);
            dc.fillPolygon(sq);
            extra = (s * 1.5).toNumber() + 2;
        }
        return Geo.bounds(pts, extra + 1);
    }
}
