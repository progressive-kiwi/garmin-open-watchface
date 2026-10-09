import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Geometry helpers. Angles are radians, clockwise from 12 o'clock.
module Geo {

    //! Transform hand-local points (x across, y outward along the hand) to screen space.
    function rotate(pts as Array<Array<Numeric>>, cx as Numeric, cy as Numeric, angle as Numeric) as Array<Point2D> {
        var s = Math.sin(angle);
        var c = Math.cos(angle);
        var n = pts.size();
        var out = new Array<Point2D>[n];
        for (var i = 0; i < n; i++) {
            var x = pts[i][0];
            var y = pts[i][1];
            out[i] = [cx + x * c + y * s, cy + x * s - y * c];
        }
        return out;
    }

    //! Point at distance r from the center along angle.
    function polar(cx as Numeric, cy as Numeric, r as Numeric, angle as Numeric) as Point2D {
        return [cx + r * Math.sin(angle), cy - r * Math.cos(angle)];
    }

    function strokePoly(dc as Dc, pts as Array<Point2D>) as Void {
        var n = pts.size();
        for (var i = 0; i < n; i++) {
            var a = pts[i];
            var b = pts[(i + 1) % n];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }

    //! Axis-aligned bounding box [x, y, w, h] of points, padded.
    function bounds(pts as Array<Point2D>, pad as Number) as Array<Number> {
        var x0 = 99999.0;
        var y0 = 99999.0;
        var x1 = -99999.0;
        var y1 = -99999.0;
        for (var i = 0; i < pts.size(); i++) {
            var p = pts[i];
            if (p[0] < x0) { x0 = p[0]; }
            if (p[0] > x1) { x1 = p[0]; }
            if (p[1] < y0) { y0 = p[1]; }
            if (p[1] > y1) { y1 = p[1]; }
        }
        var x = x0.toNumber() - pad;
        var y = y0.toNumber() - pad;
        return [x, y, x1.toNumber() + pad - x + 1, y1.toNumber() + pad - y + 1];
    }

    function union(a as Array<Number>?, b as Array<Number>) as Array<Number> {
        if (a == null) {
            return b;
        }
        var x = (a[0] < b[0]) ? a[0] : b[0];
        var y = (a[1] < b[1]) ? a[1] : b[1];
        var xr = (a[0] + a[2] > b[0] + b[2]) ? a[0] + a[2] : b[0] + b[2];
        var yb = (a[1] + a[3] > b[1] + b[3]) ? a[1] + a[3] : b[1] + b[3];
        return [x, y, xr - x, yb - y];
    }

    //! Arc in screen degrees for a gauge fraction; skips zero-length arcs.
    function arc(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, startDeg as Numeric, spanDeg as Numeric,
                 clockwise as Boolean) as Void {
        if (spanDeg < 1) {
            return;
        }
        var end = clockwise ? startDeg - spanDeg : startDeg + spanDeg;
        dc.drawArc(cx, cy, r, clockwise ? Graphics.ARC_CLOCKWISE : Graphics.ARC_COUNTER_CLOCKWISE,
                   startDeg, end);
    }
}
