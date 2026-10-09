import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Analog dial, layouts and hands.
class AnalogFace {
    var cfg as Config;
    var kit as TextKit;
    var fields as Fields;

    private const ROMAN = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"];

    function initialize(config as Config, textKit as TextKit, f as Fields) {
        cfg = config;
        kit = textKit;
        fields = f;
    }

    // ----------------------------------------------------------- layout --

    //! Field slots for a layout: [dx, dy, kind] in units of the radius.
    function slots(layout as Number) as Array<Array<Numeric>> {
        switch (layout) {
            case 1: return [[0, -0.45, Slot.SUBDIAL], [0.45, 0, Slot.SUBDIAL], [0, 0.45, Slot.SUBDIAL], [-0.45, 0, Slot.SUBDIAL]];
            case 2: return [[0, -0.36, Slot.STACKED], [0, 0.36, Slot.STACKED], [0, -0.56, Slot.INLINE], [0, 0.56, Slot.INLINE]];
            case 3: return [];
            case 4: return [[0, -0.36, Slot.STACKED], [0, 0.36, Slot.STACKED]];
            case 5: return [[0.52, 0, Slot.WINDOW], [0, 0.42, Slot.STACKED]];
        }
        return [[0.52, 0, Slot.WINDOW], [0, -0.42, Slot.STACKED], [0, 0.42, Slot.STACKED]];
    }

    function ringInset(r as Numeric) as Numeric {
        switch (cfg.DialRing) {
            case 1: return r * 0.04;
            case 2: return r * 0.075;
            case 3: return r * 0.065;
        }
        return r * 0.02;
    }

    function hourTickLen(r as Numeric) as Numeric {
        return r * [0.06, 0.09, 0.13][cfg.TickLength];
    }

    // ------------------------------------------------------------- dial --

    //! Everything except hands.
    function drawDial(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        drawRing(dc, cx, cy, r);
        var ro = r - ringInset(r);
        var depth = (cfg.HourTicks != 0 || cfg.MinuteTicks != 0) ? hourTickLen(r) : 0;

        if (cfg.AnalogLayout == 4) {
            fields.drawGauges(dc, cx, cy, r, r * 0.4, (r * 0.05).toNumber(), 120);
        } else {
            fields.drawGauges(dc, cx, cy, ro, depth + r * 0.05, (r * 0.03).toNumber(), 90);
        }

        drawTicks(dc, cx, cy, r, ro);
        drawNumerals(dc, cx, cy, r, ro - depth);
        if (cfg.AnalogLayout == 5) {
            drawPilotMarker(dc, cx, cy, r, ro);
        }

        var s = slots(cfg.AnalogLayout);
        var types = [cfg.Field1, cfg.Field2, cfg.Field3, cfg.Field4];
        for (var i = 0; i < s.size(); i++) {
            fields.draw(dc, cx + s[i][0] * r, cy + s[i][1] * r, types[i], s[i][2] as Number, r, 1,
                        cfg.cField, cfg.cLabel, 1.0);
        }

        if (cfg.StatusIcons) {
            var six = cfg.Numerals == 1 || cfg.Numerals == 2 || cfg.Numerals == 3 || cfg.Numerals == 4;
            fields.drawStatus(dc, cx, cy + (six ? r * 0.2 : r * 0.66), r, cfg.fg2);
        }
    }

    private function drawRing(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        if (cfg.DialRing == 0) {
            return;
        }
        dc.setColor(cfg.fg2, Graphics.COLOR_TRANSPARENT);
        if (cfg.DialRing == 1) {
            dc.setPenWidth(2);
            dc.drawCircle(cx, cy, r - 3);
        } else if (cfg.DialRing == 2) {
            var pen = (r * 0.055).toNumber();
            dc.setPenWidth(pen);
            dc.drawCircle(cx, cy, r - pen / 2);
        } else {
            dc.setPenWidth(1);
            dc.drawCircle(cx, cy, r - 2);
            dc.drawCircle(cx, cy, r - r * 0.05);
        }
        dc.setPenWidth(1);
    }

    private function drawTicks(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, ro as Numeric) as Void {
        var hl = hourTickLen(r);
        var ml = r * [0.03, 0.045, 0.06][cfg.TickLength];
        var mstyle = cfg.MinuteTicks;

        if (mstyle == 3) {
            dc.setColor(cfg.cMinuteTick, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawCircle(cx, cy, ro);
            dc.drawCircle(cx, cy, ro - ml);
        }
        for (var i = 0; i < 60; i++) {
            var a = i * Math.PI / 30;
            if (i % 5 == 0) {
                if (cfg.HourTicks == 0 || (cfg.AnalogLayout == 5 && i == 0)) {
                    continue;
                }
                var q = cfg.QuarterEmphasis && i % 15 == 0;
                hourTick(dc, cfg.HourTicks, cx, cy, ro, q ? hl * 1.35 : hl, r * (q ? 0.05 : 0.032), a,
                         cfg.cHourTick);
            } else if (mstyle != 0) {
                dc.setColor(cfg.cMinuteTick, Graphics.COLOR_TRANSPARENT);
                if (mstyle == 2) {
                    var p = Geo.polar(cx, cy, ro - ml / 2, a);
                    var dr = r * 0.009;
                    dc.fillCircle(p[0], p[1], dr < 1 ? 1 : dr);
                } else {
                    var p0 = Geo.polar(cx, cy, ro, a);
                    var p1 = Geo.polar(cx, cy, ro - ml, a);
                    dc.setPenWidth(r > 200 ? 2 : 1);
                    dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
                    dc.setPenWidth(1);
                }
            }
        }
    }

    function hourTick(dc as Dc, style as Number, cx as Numeric, cy as Numeric, ro as Numeric, len as Numeric,
                      w as Numeric, a as Numeric, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var h = w / 2;
        switch (style) {
            case 1: { // line
                var pen = (w * 0.45).toNumber();
                dc.setPenWidth(pen < 2 ? 2 : pen);
                var p0 = Geo.polar(cx, cy, ro, a);
                var p1 = Geo.polar(cx, cy, ro - len, a);
                dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
                dc.setPenWidth(1);
                break;
            }
            case 3: { // dot
                var p = Geo.polar(cx, cy, ro - len / 2, a);
                dc.fillCircle(p[0], p[1], w * 0.6);
                break;
            }
            case 4: // triangle pointing inward
                dc.fillPolygon(Geo.rotate([[-h * 1.2, ro], [h * 1.2, ro], [0, ro - len]], cx, cy, a));
                break;
            case 5: { // double line
                var pen = (w * 0.3).toNumber();
                dc.setPenWidth(pen < 1 ? 1 : pen);
                for (var k = -1; k <= 1; k += 2) {
                    var pts = Geo.rotate([[k * h * 0.8, ro], [k * h * 0.8, ro - len]], cx, cy, a);
                    dc.drawLine(pts[0][0], pts[0][1], pts[1][0], pts[1][1]);
                }
                dc.setPenWidth(1);
                break;
            }
            case 6: // diamond
                dc.fillPolygon(Geo.rotate([[0, ro], [h * 1.1, ro - len / 2], [0, ro - len], [-h * 1.1, ro - len / 2]],
                                          cx, cy, a));
                break;
            default: // bar
                dc.fillPolygon(Geo.rotate([[-h, ro], [h, ro], [h, ro - len], [-h, ro - len]], cx, cy, a));
        }
    }

    private function drawNumerals(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, inner as Numeric) as Void {
        var mode = cfg.Numerals;
        if (mode == 0) {
            return;
        }
        var roman = (mode == 3 || mode == 4);
        var nh = r * [0.1, 0.13, 0.17][cfg.NumeralSize] * (roman ? 0.8 : 1.0);
        var rn = inner - r * 0.03 - nh * 0.75;
        for (var i = 0; i < 12; i++) {
            var quarter = (i % 3 == 0);
            if ((mode == 1 || mode == 3) && !quarter) {
                continue;
            }
            if (mode == 5 && i != 0) {
                continue;
            }
            if (cfg.AnalogLayout == 5 && i == 0) {
                continue;
            }
            // Leave room for the 3 o'clock date window and chronograph subdials.
            if (i == 3 && (cfg.AnalogLayout == 0 || cfg.AnalogLayout == 5) && cfg.Field1 != F.OFF) {
                continue;
            }
            var txt = roman ? ROMAN[i] : (i == 0 ? "12" : i.toString());
            var a = i * Math.PI / 6;
            var rr = rn;
            if (i % 6 != 0) {
                // Wide numerals at 3 and 9 sit further in.
                rr = rn - (kit.width(dc, txt, cfg.NumeralFont, nh) / 2 - nh * 0.35) * Math.sin(a).abs();
            }
            var p = Geo.polar(cx, cy, rr, a);
            kit.draw(dc, p[0], p[1], txt, cfg.NumeralFont, nh, cfg.cNumeral, 1);
        }
    }

    private function drawPilotMarker(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, ro as Numeric) as Void {
        var len = r * 0.14;
        var w = r * 0.09;
        dc.setColor(cfg.cHourTick, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - w, cy - ro], [cx + w, cy - ro], [cx, cy - ro + len]]);
        dc.fillCircle(cx - w * 1.6, cy - ro + r * 0.03, r * 0.018);
        dc.fillCircle(cx + w * 1.6, cy - ro + r * 0.03, r * 0.018);
    }

    // ------------------------------------------------------------ hands --

    function handAngles() as Array<Numeric> {
        var c = Clock.time();
        var hour = ((c.hour % 12) * 60 + c.min + c.sec / 60.0) / 720.0 * Math.PI * 2;
        var min = (c.min + c.sec / 60.0) / 60.0 * Math.PI * 2;
        var sec = c.sec / 60.0 * Math.PI * 2;
        return [hour.toFloat(), min.toFloat(), sec.toFloat()];
    }

    //! Hour and minute hands.
    function drawHands(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, aodColor as Number?) as Void {
        var ang = handAngles();
        var aod = aodColor != null;
        var size = aod ? 0 : cfg.HandSize;
        var hl = r * [0.45, 0.52, 0.58][cfg.HandLength];
        var ml = r * [0.70, 0.80, 0.88][cfg.HandLength];
        var hw = r * [0.045, 0.065, 0.09][size];
        var mw = r * [0.035, 0.05, 0.07][size];
        var outline = (cfg.HandOutline && !aod) ? cfg.bg : null;
        var hollow = aod && cfg.AodOutline;
        Hands.draw(dc, cx, cy, ang[0], cfg.HourHand, hl, hw, r * 0.1, (aodColor != null) ? aodColor : cfg.cHourHand, outline, hollow);
        Hands.draw(dc, cx, cy, ang[1], cfg.MinuteHand, ml, mw, r * 0.1, (aodColor != null) ? aodColor : cfg.cMinuteHand, outline, hollow);
    }

    //! Second hand plus center cap. Returns the dirty box.
    function drawSecond(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Array<Number> {
        var a = handAngles()[2];
        var len = r * [0.78, 0.86, 0.92][cfg.HandLength];
        var box = Hands.drawSecond(dc, cx, cy, a, cfg.SecondHand, len, r, cfg.cSecondHand);
        drawCap(dc, cx, cy, r, cfg.cSecondHand);
        return Geo.union(box, secondCapBox(cx, cy, r));
    }

    //! Box the second hand at its current angle will cover (for clipping before drawing).
    function secondBox(cx as Numeric, cy as Numeric, r as Numeric) as Array<Number> {
        var a = handAngles()[2];
        var len = r * [0.78, 0.86, 0.92][cfg.HandLength];
        var pts = [Geo.polar(cx, cy, -r * 0.25, a), Geo.polar(cx, cy, len + 2, a)] as Array<Point2D>;
        return Geo.union(Geo.bounds(pts, (r * 0.07).toNumber() + 2), secondCapBox(cx, cy, r));
    }

    private function secondCapBox(cx as Numeric, cy as Numeric, r as Numeric) as Array<Number> {
        var c = (r * 0.07).toNumber() + 2;
        return [cx.toNumber() - c, cy.toNumber() - c, c * 2 + 1, c * 2 + 1];
    }

    function drawCap(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as Number) as Void {
        switch (cfg.CenterCap) {
            case 1:
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r * 0.035);
                break;
            case 2:
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r * 0.045);
                dc.setColor(cfg.bg, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r * 0.02);
                break;
            case 3:
                dc.setColor(cfg.cMinuteHand, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r * 0.065);
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r * 0.03);
                break;
        }
    }

    // -------------------------------------------------------- always-on --

    function drawAod(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as Number, style as Number,
                     data as DataSource) as Void {
        if (style != 4) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var ro = r - r * 0.06;
            var step = (cfg.AodMarkers == 2) ? 1 : 3;
            if (cfg.AodMarkers != 0) {
                for (var i = 0; i < 12; i += step) {
                    var a = i * Math.PI / 6;
                    if (i % 3 == 0) {
                        var p0 = Geo.polar(cx, cy, ro, a);
                        var p1 = Geo.polar(cx, cy, ro - r * 0.07, a);
                        dc.setPenWidth(2);
                        dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
                        dc.setPenWidth(1);
                    } else {
                        var p = Geo.polar(cx, cy, ro - r * 0.02, a);
                        dc.fillCircle(p[0], p[1], 2);
                    }
                }
            }
            if (style == 3) {
                kit.draw(dc, cx, cy + r * 0.45, data.dateString(cfg.DateFormat), Fonts.COND_BOLD, r * 0.055, color, 1);
            }
        }
        drawHands(dc, cx, cy, r, color);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r * 0.025);
    }
}
