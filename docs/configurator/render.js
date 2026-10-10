// Open Face preview renderer: a JavaScript port of source/*.mc for the web configurator.
// Keep in step with the Monkey C sources; structure and constants mirror them one to one.
"use strict";

const OF = (() => {
  // ------------------------------------------------------------------ Dc --
  // Minimal Toybox.Graphics.Dc on top of a 2D canvas. Angles for drawArc follow Garmin:
  // degrees, 0 = 3 o'clock, counter-clockwise positive.
  class Dc {
    constructor(ctx, size) {
      this.c = ctx;
      this.size = size;
      this.pen = 1;
      ctx.lineCap = "butt";
      ctx.lineJoin = "miter";
    }
    static hex(n) { return "#" + (n >>> 0 & 0xFFFFFF).toString(16).padStart(6, "0"); }
    setColor(n) { const h = Dc.hex(n); this.c.fillStyle = h; this.c.strokeStyle = h; }
    setPenWidth(w) { this.pen = Math.max(1, Math.floor(w)); this.c.lineWidth = this.pen; }
    clear(bg) { this.c.fillStyle = Dc.hex(bg); this.c.fillRect(0, 0, this.size, this.size); }
    drawLine(x0, y0, x1, y1) { const c = this.c; c.beginPath(); c.moveTo(x0, y0); c.lineTo(x1, y1); c.stroke(); }
    fillPolygon(pts) {
      const c = this.c; c.beginPath(); c.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) c.lineTo(pts[i][0], pts[i][1]);
      c.closePath(); c.fill();
    }
    fillCircle(x, y, r) { const c = this.c; c.beginPath(); c.arc(x, y, Math.max(0.5, r), 0, Math.PI * 2); c.fill(); }
    drawCircle(x, y, r) { const c = this.c; c.beginPath(); c.arc(x, y, Math.max(0.5, r), 0, Math.PI * 2); c.stroke(); }
    drawArc(x, y, r, clockwise, start, end) {
      const c = this.c; c.beginPath();
      c.arc(x, y, r, -start * Math.PI / 180, -end * Math.PI / 180, !clockwise);
      c.stroke();
    }
    fillRectangle(x, y, w, h) { this.c.fillRect(x, y, w, h); }
    drawRectangle(x, y, w, h) { this.c.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1); }
    fillRoundedRectangle(x, y, w, h, r) { const c = this.c; c.beginPath(); c.roundRect(x, y, w, h, r); c.fill(); }
    drawRoundedRectangle(x, y, w, h, r) { const c = this.c; c.beginPath(); c.roundRect(x, y, w, h, r); c.stroke(); }
  }

  // ----------------------------------------------------------------- Geo --
  const Geo = {
    rotate(pts, cx, cy, a) {
      const s = Math.sin(a), c = Math.cos(a);
      return pts.map(([x, y]) => [cx + x * c + y * s, cy + x * s - y * c]);
    },
    polar(cx, cy, r, a) { return [cx + r * Math.sin(a), cy - r * Math.cos(a)]; },
    strokePoly(dc, pts) {
      for (let i = 0; i < pts.length; i++) {
        const a = pts[i], b = pts[(i + 1) % pts.length];
        dc.drawLine(a[0], a[1], b[0], b[1]);
      }
    },
    arc(dc, cx, cy, r, start, span, cw) {
      if (span < 1) return;
      dc.drawArc(cx, cy, r, cw, start, cw ? start - span : start + span);
    },
  };

  // --------------------------------------------------------------- Fonts --
  const Fonts = {
    SYSTEM: 0, COND_BOLD: 1, ROBOTO: 2, BLACK: 3, BIONIC: 4, SERIF: 5, ITALIC: 6,
    QUARTZ: 7, QUARTZ_OUTLINE: 8, QUARTZ_THIN: 9, DOT: 10, PIXEL: 11, DOT_FINE: 12, SEGMENT: 13,
    isSegment(f) { return f === 7 || f === 8 || f === 9 || f === 13; },
    isDot(f) { return f === 10 || f === 11 || f === 12; },
    isProcedural(f) { return this.isSegment(f) || this.isDot(f); },
    outlineOf(f) { return (f === 7 || f === 13) ? 8 : (f === 10 || f === 11) ? 12 : f; },
  };
  // Web stand-ins for the device faces (Bionic is proprietary; Roboto Condensed is closest).
  const CSS_FONT = {
    0: ["500", "normal", "Roboto"], 1: ["700", "normal", "Roboto Condensed"], 2: ["400", "normal", "Roboto"],
    3: ["900", "normal", "Roboto"], 4: ["700", "normal", "Roboto Condensed"], 5: ["600", "normal", "Pridi"],
    6: ["400", "italic", "Roboto Condensed"],
  };

  const SEG_DIGITS = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F];
  const SEG_LETTERS = "ABCDEFGHIJLNOPRSTUY";
  const SEG_LETTER_MASKS = [0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71, 0x3D, 0x76, 0x30, 0x1E,
    0x38, 0x54, 0x3F, 0x73, 0x50, 0x6D, 0x78, 0x3E, 0x6E];
  const DOT_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-%/+";
  const DOT_ROWS = [
    0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E, 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E,
    0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F, 0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E,
    0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02, 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E,
    0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E, 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08,
    0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E, 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C,
    0x0E, 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E,
    0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E, 0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C,
    0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F, 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10,
    0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F, 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11,
    0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C,
    0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F,
    0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11, 0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11,
    0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10,
    0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D, 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11,
    0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E, 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04,
    0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A, 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F,
    0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00, 0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03,
    0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10, 0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00,
  ];

  class TextKit {
    constructor() { this.ghost = false; this.ghostColor = 0x555555; this.bgColor = 0; this.mip = false; }

    cssFont(family, h) {
      const [w, st, face] = CSS_FONT[family] || CSS_FONT[0];
      return `${st} ${w} ${Math.round(h * 1.38)}px "${face}"`;
    }

    draw(dc, x, y, text, family, h, color, just) {
      if (!text.length) return;
      if (Fonts.isSegment(family) && !this.segSupports(text)) family = Fonts.DOT;
      if (Fonts.isProcedural(family)) {
        const w = this.width(dc, text, family, h);
        let x0 = x;
        if (just === 1) x0 = x - w / 2; else if (just === 2) x0 = x - w;
        if (Fonts.isSegment(family)) this.drawSegments(dc, x0, y - h / 2, text, family, h, color);
        else this.drawDots(dc, x0, y - h / 2, text, family, h, color);
        return;
      }
      const c = dc.c;
      c.font = this.cssFont(family, h);
      c.textAlign = just === 1 ? "center" : just === 2 ? "right" : "left";
      c.textBaseline = "alphabetic";
      const m = c.measureText(text);
      dc.setColor(color);
      // Center the glyph ink vertically, like TEXT_JUSTIFY_VCENTER on digits.
      const asc = m.actualBoundingBoxAscent, desc = m.actualBoundingBoxDescent;
      c.fillText(text, x, y + (asc - desc) / 2);
    }

    width(dc, text, family, h) {
      if (Fonts.isSegment(family) && !this.segSupports(text)) family = Fonts.DOT;
      if (Fonts.isSegment(family)) {
        let w = 0;
        for (const ch of text) w += this.segAdvance(ch, h);
        return Math.floor(w - h * 0.14);
      }
      if (Fonts.isDot(family)) {
        const c = h / 7;
        let cols = 0;
        for (const ch of text.toUpperCase()) cols += this.dotCols(ch) + 1;
        return Math.floor((cols - 1) * c);
      }
      dc.c.font = this.cssFont(family, h);
      return dc.c.measureText(text).width;
    }

    segMask(ch) {
      if (ch >= "0" && ch <= "9") return SEG_DIGITS[ch.charCodeAt(0) - 48];
      if (ch === "-") return 0x40;
      const i = SEG_LETTERS.indexOf(ch.toUpperCase());
      return i >= 0 ? SEG_LETTER_MASKS[i] : 0;
    }
    segSupports(text) {
      for (const ch of text) if (ch !== " " && ch !== ":" && ch !== "." && ch !== "-" && this.segMask(ch) === 0) return false;
      return true;
    }
    segAdvance(ch, h) {
      const sp = h * 0.14;
      if (ch === ":" || ch === ".") return h * 0.13 * 1.4 + sp;
      if (ch === " ") return h * 0.3 + sp;
      return h * 0.52 + sp;
    }

    drawSegments(dc, x, top, text, family, h, color) {
      const slant = family === Fonts.SEGMENT ? 0 : 0.09;
      let t = h * (family === Fonts.QUARTZ_THIN ? 0.07 : 0.13);
      if (t < 2) t = 2;
      const w = h * 0.52, midY = top + h / 2;
      for (const ch of text) {
        if (ch === ":" || ch === ".") {
          const dw = h * 0.13 * 1.4;
          dc.setColor(color);
          const ys = ch === ":" ? [top + h * 0.3, top + h * 0.7] : [top + h - dw / 2];
          for (const yy of ys) {
            const cx = x + dw / 2 + (midY - yy) * slant;
            if (family === Fonts.QUARTZ_OUTLINE) { dc.setPenWidth(1); dc.drawRectangle(cx - dw / 2, yy - dw / 2, dw, dw); }
            else dc.fillRectangle(cx - dw / 2, yy - dw / 2, dw, dw);
          }
        } else if (ch !== " ") {
          this.drawSegDigit(dc, x, top, w, h, t, this.segMask(ch), family, slant, color);
        }
        x += this.segAdvance(ch, h);
      }
      dc.setPenWidth(1);
    }

    drawSegDigit(dc, x, top, w, h, t, mask, family, slant, color) {
      const g = t * 0.3, l = x + t / 2, r = x + w - t / 2, tp = top + t / 2, m = top + h / 2, b = top + h - t / 2;
      const segs = [[l + g, tp, r - g, tp], [r, tp + g, r, m - g], [r, m + g, r, b - g], [l + g, b, r - g, b],
        [l, m + g, l, b - g], [l, tp + g, l, m - g], [l + g, m, r - g, m]];
      for (let pass = 0; pass < 2; pass++) {
        if (pass === 0 && !this.ghost) continue;
        dc.setColor(pass === 0 ? this.ghostColor : color);
        for (let s = 0; s < 7; s++) {
          const lit = (mask & (1 << s)) !== 0;
          if ((pass === 0 && lit) || (pass === 1 && !lit)) continue;
          const sg = segs[s];
          if (family === Fonts.QUARTZ_THIN) {
            dc.setPenWidth(t);
            dc.drawLine(sg[0] + (m - sg[1]) * slant, sg[1], sg[2] + (m - sg[3]) * slant, sg[3]);
          } else {
            const pts = this.segPoly(sg[0], sg[1], sg[2], sg[3], t, m, slant);
            if (family === Fonts.QUARTZ_OUTLINE) { dc.setPenWidth(1); Geo.strokePoly(dc, pts); }
            else dc.fillPolygon(pts);
          }
        }
      }
    }

    segPoly(x0, y0, x1, y1, t, midY, slant) {
      let len = Math.hypot(x1 - x0, y1 - y0);
      if (len < 1) len = 1;
      const dx = (x1 - x0) / len, dy = (y1 - y0) / len, hw = t / 2;
      const nx = -dy * hw, ny = dx * hw, ax = dx * hw, ay = dy * hw;
      const raw = [[x0, y0], [x0 + ax + nx, y0 + ay + ny], [x1 - ax + nx, y1 - ay + ny], [x1, y1],
        [x1 - ax - nx, y1 - ay - ny], [x0 + ax - nx, y0 + ay - ny]];
      return raw.map(([px, py]) => [px + (midY - py) * slant, py]);
    }

    dotCols(ch) { return (ch === ":" || ch === ".") ? 1 : ch === " " ? 2 : 5; }

    drawDots(dc, x, top, text, family, h, color) {
      const c = h / 7;
      const rad = Math.max(1, c * (family === Fonts.DOT_FINE ? 0.26 : 0.38));
      const sq = Math.max(1, c * 0.84);
      const dim = this.mip ? this.ghostColor : mix(this.bgColor, this.ghostColor, 1, 2, false);
      for (const ch of text.toUpperCase()) {
        const cols = this.dotCols(ch);
        if (ch === ":" || ch === ".") {
          dc.setColor(color);
          for (const row of (ch === ":" ? [2, 4] : [6])) this.dot(dc, x, top + row * c, c, rad, sq, family);
        } else if (ch !== " ") {
          const gi = DOT_CHARS.indexOf(ch);
          for (let pass = 0; pass < 2; pass++) {
            if (pass === 0 && !this.ghost) continue;
            dc.setColor(pass === 0 ? dim : color);
            for (let row = 0; row < 7; row++) {
              const bits = gi < 0 ? 0 : DOT_ROWS[gi * 7 + row];
              for (let col = 0; col < 5; col++) {
                const lit = (bits & (0x10 >> col)) !== 0;
                if (lit === (pass === 1)) this.dot(dc, x + col * c, top + row * c, c, rad, sq, family);
              }
            }
          }
        }
        x += (cols + 1) * c;
      }
    }

    dot(dc, x, y, c, rad, sq, family) {
      if (family === Fonts.PIXEL) dc.fillRectangle(x, y, sq, sq);
      else dc.fillCircle(x + c / 2, y + c / 2, rad);
    }
  }

  // ------------------------------------------------------------- Colors --
  function mix(a, b, num, den, snap) {
    let out = 0;
    for (let shift = 16; shift >= 0; shift -= 8) {
      const ca = (a >> shift) & 0xFF, cb = (b >> shift) & 0xFF;
      let c = ca + Math.trunc((cb - ca) * num / den);
      if (snap) c = Math.trunc((c + 42) / 85) * 85;
      out |= Math.min(255, c) << shift;
    }
    return out;
  }

  //! Port of Config.load() / fade().
  function resolve(v, themes) {
    const cfg = Object.assign({}, v);
    const pick = (x, auto) => (x < 0 ? auto : x);
    if (v.Theme > 0 && v.Theme < themes.length) {
      [cfg.bg, cfg.fg, cfg.fg2, cfg.accent] = themes[v.Theme];
    } else {
      cfg.bg = v.BgColor; cfg.fg = v.PrimaryColor; cfg.fg2 = v.SecondaryColor; cfg.accent = v.AccentColor;
    }
    cfg.cHourHand = pick(v.HourHandColor, cfg.fg);
    cfg.cMinuteHand = pick(v.MinuteHandColor, cfg.fg);
    cfg.cSecondHand = pick(v.SecondHandColor, cfg.accent);
    cfg.cHourTick = pick(v.HourTickColor, cfg.fg);
    cfg.cMinuteTick = pick(v.MinuteTickColor, cfg.fg2);
    cfg.cNumeral = pick(v.NumeralColor, cfg.fg);
    cfg.cHourDigits = pick(v.HourDigitColor, cfg.fg);
    cfg.cMinuteDigits = pick(v.MinuteDigitColor, (v.Mode === 1 && v.DigitalLayout === 1) ? cfg.accent : cfg.fg);
    cfg.cField = pick(v.FieldColor, cfg.fg);
    cfg.cLabel = pick(v.LabelColor, cfg.fg2);
    cfg.ghost = pick(v.GhostColor, mix(cfg.bg, cfg.fg, 1, 3, true));
    return cfg;
  }

  function fade(cfg, pct, snap) {
    for (const k of ["fg", "fg2", "accent", "cHourHand", "cMinuteHand", "cSecondHand", "cHourTick", "cMinuteTick",
      "cNumeral", "cHourDigits", "cMinuteDigits", "cField", "cLabel", "ghost"]) {
      cfg[k] = mix(cfg[k], cfg.bg, pct, 100, snap);
    }
    cfg.AodColor = mix(cfg.AodColor, 0, pct, 100, false);
  }

  // --------------------------------------------------------------- Data --
  const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
  const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
  const pad = (n) => String(n).padStart(2, "0");

  //! Sample data standing in for sensors.
  class DataSource {
    constructor(cfg, clock, use24h) { this.cfg = cfg; this.clock = clock; this.use24h = use24h; }
    label(t) {
      return ({3: "BAT", 4: "BAT", 5: "STEPS", 6: "HR", 7: "KCAL", 8: "KM", 9: "FLOORS", 10: "ACTIVE", 11: "BODY",
        12: "STRESS", 13: "MSG", 14: "ALT", 15: "TEMP", 16: "SUN", 17: "WEEK", 20: "BRPM", 21: "RECOV", 22: "DAY"})[t] || "";
    }
    value(t) {
      const c = this.clock;
      switch (t) {
        case 1: return this.dateString(this.cfg.DateFormat);
        case 2: return DAYS[c.date.getDay()] + " " + c.date.getDate();
        case 3: return "76%"; case 4: return "9D"; case 5: return "8432"; case 6: return "62";
        case 7: return "1840"; case 8: return "6.4"; case 9: return "8"; case 10: return "145";
        case 11: return "68"; case 12: return "24"; case 13: return "3"; case 14: return "312";
        case 15: return "18°"; case 16: return this.use24h ? "19:02" : "7:02";
        case 17: return String(isoWeek(c.date));
        case 18: { const p = this.timeParts(); return p[0] + ":" + p[1]; }
        case 19: return pad(c.sec);
        case 20: return "14"; case 21: return "18H";
        case 22: return Math.floor((c.hour * 60 + c.min) * 100 / 1440) + "%";
      }
      return "";
    }
    fraction(t) {
      const c = this.clock;
      return ({3: 0.76, 5: 0.84, 9: 0.8, 10: 0.97, 11: 0.68, 12: 0.24, 6: 22 / 150, 19: c.sec / 60,
        22: (c.hour * 60 + c.min) / 1440})[t] ?? null;
    }
    //! Gauge metric -> field type (DataSource.gauge).
    gauge(m) { const t = [0, 3, 5, 11, 12, 10, 9, 19, 6, 22][m]; return t ? this.fraction(t) : null; }
    timeParts() {
      let h = this.clock.hour, ampm = "";
      if (!this.use24h) { ampm = h < 12 ? "AM" : "PM"; h = h % 12; if (h === 0) h = 12; }
      return [this.cfg.LeadingZero ? pad(h) : String(h), pad(this.clock.min), ampm];
    }
    dateString(fmt) {
      const d = this.clock.date, day = d.getDate(), mon = d.getMonth() + 1, dow = DAYS[d.getDay()], mn = MONTHS[mon - 1];
      switch (fmt) {
        case 1: return day + " " + mn;
        case 2: return dow + " " + day + " " + mn;
        case 3: return d.getFullYear() + "-" + pad(mon) + "-" + pad(day);
        case 4: return pad(day) + "." + pad(mon);
        case 5: return pad(mon) + "/" + pad(day);
      }
      return dow + " " + day;
    }
  }

  function isoWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const day = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - day);
    const y0 = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    return Math.ceil(((d - y0) / 86400000 + 1) / 7);
  }

  // -------------------------------------------------------------- Hands --
  function handShapes(style, l, w, t) {
    const h = w / 2;
    switch (style) {
      case 1: return [[[-h, 0], [0, l], [h, 0], [0, -t * 0.6]]];
      case 2: return [[[-h, -t], [-h, l - w * 1.4], [0, l], [h, l - w * 1.4], [h, -t]]];
      case 3: return [[[-h * 0.25, -t], [-h * 0.85, l * 0.25], [-h * 1.1, l * 0.5], [-h * 0.8, l * 0.75],
        [0, l], [h * 0.8, l * 0.75], [h * 1.1, l * 0.5], [h * 0.85, l * 0.25], [h * 0.25, -t]]];
      case 4: return [[[-h, -t], [-h, l - w * 1.4], [0, l], [h, l - w * 1.4], [h, -t]],
        [[-h * 0.55, l * 0.55], [-h * 0.55, l - w * 1.5], [0, l - w * 0.5], [h * 0.55, l - w * 1.5], [h * 0.55, l * 0.55]]];
      case 5: return [[[-h * 0.35, -t], [-h * 0.35, l * 0.74], [h * 0.35, l * 0.74], [h * 0.35, -t]],
        [[-h * 1.4, l * 0.7], [0, l], [h * 1.4, l * 0.7]]];
      case 6: return [[[-h * 0.3 - 0.5, -t], [-h * 0.3 - 0.5, l], [h * 0.3 + 0.5, l], [h * 0.3 + 0.5, -t]]];
      case 8: return [[[-h * 0.4, -t], [-h * 0.4, l * 0.62], [h * 0.4, l * 0.62], [h * 0.4, -t]],
        ring(0, l * 0.71, w * 0.75, 10), [[-h * 0.45, l * 0.8], [0, l], [h * 0.45, l * 0.8]]];
    }
    return [[[-h, -t], [-h, l], [h, l], [h, -t]]];
  }

  function ring(x, y, r, n) {
    const out = [];
    for (let i = 0; i < n; i++) { const a = Math.PI * 2 * i / n; out.push([x + r * Math.cos(a), y + r * Math.sin(a)]); }
    return out;
  }

  function drawHand(dc, cx, cy, angle, style, len, w, tail, color, outline, hollow) {
    const pen = Math.max(2, Math.floor(w / 5));
    if (style === 7) {
      const a = Geo.polar(cx, cy, -tail, angle), b = Geo.polar(cx, cy, len, angle);
      if (outline !== null && !hollow) {
        dc.setColor(outline); dc.setPenWidth(Math.floor(w) + 3);
        dc.drawLine(a[0], a[1], b[0], b[1]);
        dc.fillCircle(b[0], b[1], w / 2 + 1.5); dc.fillCircle(a[0], a[1], w / 2 + 1.5);
      }
      dc.setColor(color); dc.setPenWidth(hollow ? pen : Math.floor(w));
      dc.drawLine(a[0], a[1], b[0], b[1]);
      if (!hollow) { dc.fillCircle(b[0], b[1], w / 2); dc.fillCircle(a[0], a[1], w / 2); }
      dc.setPenWidth(1);
      return;
    }
    const shapes = handShapes(style, len, w, tail);
    shapes.forEach((shape, i) => {
      const pts = Geo.rotate(shape, cx, cy, angle);
      const solid = !hollow && !(style === 4 && i === 0) && !(style === 8 && i === 1);
      if (solid) {
        if (outline !== null) { dc.setColor(outline); dc.setPenWidth(3); Geo.strokePoly(dc, pts); }
        dc.setColor(color); dc.fillPolygon(pts);
      } else {
        dc.setColor(color); dc.setPenWidth(pen); Geo.strokePoly(dc, pts);
      }
    });
    dc.setPenWidth(1);
  }

  function drawSecondHand(dc, cx, cy, angle, style, len, r, color) {
    const sw = Math.max(2, Math.floor(r * 0.014));
    const tail = r * (style === 2 ? 0.24 : 0.16);
    const a = Geo.polar(cx, cy, -tail, angle), b = Geo.polar(cx, cy, len, angle);
    dc.setColor(color); dc.setPenWidth(sw); dc.drawLine(a[0], a[1], b[0], b[1]); dc.setPenWidth(1);
    if (style === 1) { const p = Geo.polar(cx, cy, len * 0.74, angle); dc.fillCircle(p[0], p[1], r * 0.04); }
    else if (style === 2) { const p = Geo.polar(cx, cy, -tail * 0.75, angle); dc.fillCircle(p[0], p[1], r * 0.05); }
    else if (style === 3) dc.fillPolygon(Geo.rotate([[-r * 0.03, len - r * 0.09], [0, len + 1], [r * 0.03, len - r * 0.09]], cx, cy, angle));
    else if (style === 4) {
      const s = r * 0.03;
      dc.fillPolygon(Geo.rotate([[-s, len * 0.8 - s], [-s, len * 0.8 + s], [s, len * 0.8 + s], [s, len * 0.8 - s]], cx, cy, angle));
    }
  }

  // ------------------------------------------------------------- Fields --
  const Slot = { STACKED: 0, WINDOW: 1, SUBDIAL: 2, INLINE: 3 };
  const LABEL_FONT = Fonts.COND_BOLD;

  class Fields {
    constructor(cfg, kit, data) { this.cfg = cfg; this.kit = kit; this.data = data; }

    draw(dc, x, y, type, kind, r, just, valueColor, labelColor, scale) {
      if (!type) return;
      const cfg = this.cfg, kit = this.kit;
      const val = this.data.value(type);
      const lbl = cfg.FieldLabels === 1 ? this.data.label(type) : "";
      const font = cfg.FieldFont, vh = r * 0.085 * scale, lh = r * 0.042 * scale;
      if (kind === Slot.WINDOW) {
        const h = r * 0.075 * scale, w = kit.width(dc, val, font, h) + r * 0.08, bh = h + r * 0.07;
        dc.setColor(cfg.bg); dc.fillRoundedRectangle(x - w / 2, y - bh / 2, w, bh, 4);
        dc.setColor(cfg.fg2); dc.setPenWidth(2); dc.drawRoundedRectangle(x - w / 2, y - bh / 2, w, bh, 4); dc.setPenWidth(1);
        kit.draw(dc, x, y, val, font, h, valueColor, 1);
        return;
      }
      if (kind === Slot.SUBDIAL) {
        const sr = r * 0.19, pen = Math.max(2, Math.floor(r * 0.02));
        dc.setColor(cfg.fg2); dc.setPenWidth(1); dc.drawCircle(x, y, sr);
        const f = this.data.fraction(type);
        if (f !== null) { dc.setColor(cfg.accent); dc.setPenWidth(pen); Geo.arc(dc, x, y, sr - pen / 2 - 1, 90, f * 360, true); dc.setPenWidth(1); }
        if (lbl) {
          kit.draw(dc, x, y - sr * 0.38, lbl, LABEL_FONT, lh * 0.9, labelColor, 1);
          kit.draw(dc, x, y + sr * 0.15, val, font, this.fit(dc, val, font, vh * 0.85, sr * 1.6), valueColor, 1);
        } else kit.draw(dc, x, y, val, font, this.fit(dc, val, font, vh, sr * 1.6), valueColor, 1);
        return;
      }
      if (kind === Slot.INLINE) {
        const h = r * 0.065 * scale;
        if (!lbl) { kit.draw(dc, x, y, val, font, h, valueColor, just); return; }
        const gap = r * 0.03, lw = kit.width(dc, lbl, LABEL_FONT, lh), vw = kit.width(dc, val, font, h);
        let x0 = x;
        if (just === 1) x0 = x - (lw + gap + vw) / 2; else if (just === 2) x0 = x - (lw + gap + vw);
        kit.draw(dc, x0, y, lbl, LABEL_FONT, lh, labelColor, 0);
        kit.draw(dc, x0 + lw + gap, y, val, font, h, valueColor, 0);
        return;
      }
      if (lbl) {
        const gap = r * 0.035, top = y - (lh + gap + vh) / 2;
        kit.draw(dc, x, top + lh / 2, lbl, LABEL_FONT, lh, labelColor, just);
        kit.draw(dc, x, top + lh + gap + vh / 2, val, font, vh, valueColor, just);
      } else kit.draw(dc, x, y, val, font, vh, valueColor, just);
    }

    fit(dc, text, font, h, maxW) {
      const w = this.kit.width(dc, text, font, h);
      return (w > maxW && w > 0) ? h * maxW / w : h;
    }

    drawGauges(dc, cx, cy, r, inset, pen, span) {
      const metrics = [this.cfg.GaugeLeft, this.cfg.GaugeRight], gr = r - inset;
      for (let i = 0; i < 2; i++) {
        if (!metrics[i]) continue;
        const f = this.data.gauge(metrics[i]);
        const start = i === 0 ? 180 + span / 2 : 360 - span / 2, cw = i === 0;
        dc.setPenWidth(pen); dc.setColor(this.cfg.ghost); Geo.arc(dc, cx, cy, gr, start, span, cw);
        if (f !== null) { dc.setColor(this.cfg.accent); Geo.arc(dc, cx, cy, gr, start, f * span, cw); }
      }
      dc.setPenWidth(1);
    }

    //! Sample state: phone connected, 3 notifications.
    drawStatus(dc, cx, y, r, color) {
      const icons = [0, 1], n = icons.length, s = r * 0.07, gap = r * 0.045;
      let x = cx - (n * s + (n - 1) * gap) / 2 + s / 2;
      dc.setColor(color); dc.setPenWidth(Math.max(1, Math.floor(s / 9)));
      for (const k of icons) {
        const h = s / 2;
        if (k === 0) {
          dc.drawLine(x - h * 0.5, y - h * 0.5, x + h * 0.5, y + h * 0.5); dc.drawLine(x + h * 0.5, y + h * 0.5, x, y + h);
          dc.drawLine(x, y + h, x, y - h); dc.drawLine(x, y - h, x + h * 0.5, y - h * 0.5);
          dc.drawLine(x + h * 0.5, y - h * 0.5, x - h * 0.5, y + h * 0.5);
        } else {
          dc.drawRectangle(x - h, y - h * 0.7, s, h * 1.4);
          dc.drawLine(x - h, y - h * 0.7, x, y + h * 0.1); dc.drawLine(x, y + h * 0.1, x + h, y - h * 0.7);
        }
        x += s + gap;
      }
      dc.setPenWidth(1);
    }
  }

  // -------------------------------------------------------------- Analog --
  const ROMAN = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"];

  class AnalogFace {
    constructor(cfg, kit, fields, clock, amoled) { Object.assign(this, {cfg, kit, fields, clock, amoled}); }

    slots(layout) {
      switch (layout) {
        case 1: return [[0, -0.45, 2], [0.45, 0, 2], [0, 0.45, 2], [-0.45, 0, 2]];
        case 2: return [[0, -0.36, 0], [0, 0.36, 0], [0, -0.56, 3], [0, 0.56, 3]];
        case 3: return [];
        case 4: return [[0, -0.36, 0], [0, 0.36, 0]];
        case 5: return [[0.52, 0, 1], [0, 0.42, 0]];
      }
      return [[0.52, 0, 1], [0, -0.42, 0], [0, 0.42, 0]];
    }
    ringInset(r) { return r * ([0.02, 0.04, 0.075, 0.065][this.cfg.DialRing] ?? 0.02); }
    hourTickLen(r) { return r * [0.06, 0.09, 0.13][this.cfg.TickLength]; }

    drawDial(dc, cx, cy, r) {
      const cfg = this.cfg;
      this.drawRing(dc, cx, cy, r);
      const ro = r - this.ringInset(r);
      const depth = (cfg.HourTicks || cfg.MinuteTicks) ? this.hourTickLen(r) : 0;
      if (cfg.AnalogLayout === 4) this.fields.drawGauges(dc, cx, cy, r, r * 0.4, Math.floor(r * 0.05), 120);
      else this.fields.drawGauges(dc, cx, cy, ro, depth + r * 0.05, Math.floor(r * 0.03), 90);
      this.drawTicks(dc, cx, cy, r, ro);
      this.drawNumerals(dc, cx, cy, r, ro - depth);
      if (cfg.AnalogLayout === 5) this.drawPilotMarker(dc, cx, cy, r, ro);
      const s = this.slots(cfg.AnalogLayout), types = [cfg.Field1, cfg.Field2, cfg.Field3, cfg.Field4];
      s.forEach((sl, i) => this.fields.draw(dc, cx + sl[0] * r, cy + sl[1] * r, types[i], sl[2], r, 1, cfg.cField, cfg.cLabel, 1));
      if (cfg.StatusIcons) {
        const six = cfg.Numerals >= 1 && cfg.Numerals <= 4;
        this.fields.drawStatus(dc, cx, cy + (six ? r * 0.2 : r * 0.66), r, cfg.fg2);
      }
    }

    drawRing(dc, cx, cy, r) {
      const cfg = this.cfg;
      if (!cfg.DialRing) return;
      dc.setColor(cfg.fg2);
      if (cfg.DialRing === 1) { dc.setPenWidth(2); dc.drawCircle(cx, cy, r - 3); }
      else if (cfg.DialRing === 2) { const pen = Math.floor(r * 0.055); dc.setPenWidth(pen); dc.drawCircle(cx, cy, r - pen / 2); }
      else { dc.setPenWidth(1); dc.drawCircle(cx, cy, r - 2); dc.drawCircle(cx, cy, r - r * 0.05); }
      dc.setPenWidth(1);
    }

    drawTicks(dc, cx, cy, r, ro) {
      const cfg = this.cfg, hl = this.hourTickLen(r), ml = r * [0.03, 0.045, 0.06][cfg.TickLength], ms = cfg.MinuteTicks;
      if (ms === 3) { dc.setColor(cfg.cMinuteTick); dc.setPenWidth(1); dc.drawCircle(cx, cy, ro); dc.drawCircle(cx, cy, ro - ml); }
      for (let i = 0; i < 60; i++) {
        const a = i * Math.PI / 30;
        if (i % 5 === 0) {
          if (!cfg.HourTicks || (cfg.AnalogLayout === 5 && i === 0)) continue;
          const q = cfg.QuarterEmphasis && i % 15 === 0;
          this.hourTick(dc, cfg.HourTicks, cx, cy, ro, q ? hl * 1.35 : hl, r * (q ? 0.05 : 0.032), a, cfg.cHourTick);
        } else if (ms) {
          dc.setColor(cfg.cMinuteTick);
          if (ms === 2) { const p = Geo.polar(cx, cy, ro - ml / 2, a); dc.fillCircle(p[0], p[1], Math.max(1, r * 0.009)); }
          else {
            const p0 = Geo.polar(cx, cy, ro, a), p1 = Geo.polar(cx, cy, ro - ml, a);
            dc.setPenWidth(r > 200 ? 2 : 1); dc.drawLine(p0[0], p0[1], p1[0], p1[1]); dc.setPenWidth(1);
          }
        }
      }
    }

    hourTick(dc, style, cx, cy, ro, len, w, a, color) {
      dc.setColor(color);
      const h = w / 2;
      switch (style) {
        case 1: { dc.setPenWidth(Math.max(2, Math.floor(w * 0.45))); const p0 = Geo.polar(cx, cy, ro, a), p1 = Geo.polar(cx, cy, ro - len, a);
          dc.drawLine(p0[0], p0[1], p1[0], p1[1]); dc.setPenWidth(1); break; }
        case 3: { const p = Geo.polar(cx, cy, ro - len / 2, a); dc.fillCircle(p[0], p[1], w * 0.6); break; }
        case 4: dc.fillPolygon(Geo.rotate([[-h * 1.2, ro], [h * 1.2, ro], [0, ro - len]], cx, cy, a)); break;
        case 5: { dc.setPenWidth(Math.max(1, Math.floor(w * 0.3)));
          for (const k of [-1, 1]) { const p = Geo.rotate([[k * h * 0.8, ro], [k * h * 0.8, ro - len]], cx, cy, a); dc.drawLine(p[0][0], p[0][1], p[1][0], p[1][1]); }
          dc.setPenWidth(1); break; }
        case 6: dc.fillPolygon(Geo.rotate([[0, ro], [h * 1.1, ro - len / 2], [0, ro - len], [-h * 1.1, ro - len / 2]], cx, cy, a)); break;
        default: dc.fillPolygon(Geo.rotate([[-h, ro], [h, ro], [h, ro - len], [-h, ro - len]], cx, cy, a));
      }
    }

    drawNumerals(dc, cx, cy, r, inner) {
      const cfg = this.cfg, mode = cfg.Numerals;
      if (!mode) return;
      const roman = mode === 3 || mode === 4;
      const nh = r * [0.1, 0.13, 0.17][cfg.NumeralSize] * (roman ? 0.8 : 1);
      const rn = inner - r * 0.03 - nh * 0.75;
      for (let i = 0; i < 12; i++) {
        if ((mode === 1 || mode === 3) && i % 3 !== 0) continue;
        if (mode === 5 && i !== 0) continue;
        if (cfg.AnalogLayout === 5 && i === 0) continue;
        if (i === 3 && (cfg.AnalogLayout === 0 || cfg.AnalogLayout === 5) && cfg.Field1 !== 0) continue;
        const txt = roman ? ROMAN[i] : (i === 0 ? "12" : String(i));
        const a = i * Math.PI / 6;
        let rr = rn;
        if (i % 6 !== 0) rr = rn - (this.kit.width(dc, txt, cfg.NumeralFont, nh) / 2 - nh * 0.35) * Math.abs(Math.sin(a));
        const p = Geo.polar(cx, cy, rr, a);
        this.kit.draw(dc, p[0], p[1], txt, cfg.NumeralFont, nh, cfg.cNumeral, 1);
      }
    }

    drawPilotMarker(dc, cx, cy, r, ro) {
      const len = r * 0.14, w = r * 0.09;
      dc.setColor(this.cfg.cHourTick);
      dc.fillPolygon([[cx - w, cy - ro], [cx + w, cy - ro], [cx, cy - ro + len]]);
      dc.fillCircle(cx - w * 1.6, cy - ro + r * 0.03, r * 0.018);
      dc.fillCircle(cx + w * 1.6, cy - ro + r * 0.03, r * 0.018);
    }

    angles() {
      const c = this.clock;
      return [((c.hour % 12) * 60 + c.min + c.sec / 60) / 720 * Math.PI * 2, (c.min + c.sec / 60) / 60 * Math.PI * 2, c.sec / 60 * Math.PI * 2];
    }

    drawHands(dc, cx, cy, r, aodColor) {
      const cfg = this.cfg, ang = this.angles(), aod = aodColor !== null;
      const size = (aod && this.amoled) ? 0 : cfg.HandSize;
      const hl = r * [0.45, 0.52, 0.58][cfg.HandLength], ml = r * [0.70, 0.80, 0.88][cfg.HandLength];
      const hw = r * [0.045, 0.065, 0.09][size], mw = r * [0.035, 0.05, 0.07][size];
      const outline = (cfg.HandOutline && !aod) ? cfg.bg : null;
      const hollow = aod && this.amoled && cfg.AodOutline;
      drawHand(dc, cx, cy, ang[0], cfg.HourHand, hl, hw, r * 0.1, aod ? aodColor : cfg.cHourHand, outline, hollow);
      drawHand(dc, cx, cy, ang[1], cfg.MinuteHand, ml, mw, r * 0.1, aod ? aodColor : cfg.cMinuteHand, outline, hollow);
    }

    drawSecond(dc, cx, cy, r) {
      const len = r * [0.78, 0.86, 0.92][this.cfg.HandLength];
      drawSecondHand(dc, cx, cy, this.angles()[2], this.cfg.SecondHand, len, r, this.cfg.cSecondHand);
      this.drawCap(dc, cx, cy, r, this.cfg.cSecondHand);
    }

    drawCap(dc, cx, cy, r, color) {
      const cfg = this.cfg;
      if (cfg.CenterCap === 1) { dc.setColor(color); dc.fillCircle(cx, cy, r * 0.035); }
      else if (cfg.CenterCap === 2) { dc.setColor(color); dc.fillCircle(cx, cy, r * 0.045); dc.setColor(cfg.bg); dc.fillCircle(cx, cy, r * 0.02); }
      else if (cfg.CenterCap === 3) { dc.setColor(cfg.cMinuteHand); dc.fillCircle(cx, cy, r * 0.065); dc.setColor(color); dc.fillCircle(cx, cy, r * 0.03); }
    }

    drawAod(dc, cx, cy, r, color, style, data) {
      const cfg = this.cfg;
      if (style !== 4) {
        dc.setColor(color);
        const ro = r - r * 0.06, step = cfg.AodMarkers === 2 ? 1 : 3;
        if (cfg.AodMarkers) {
          for (let i = 0; i < 12; i += step) {
            const a = i * Math.PI / 6;
            if (i % 3 === 0) { const p0 = Geo.polar(cx, cy, ro, a), p1 = Geo.polar(cx, cy, ro - r * 0.07, a); dc.setPenWidth(2); dc.drawLine(p0[0], p0[1], p1[0], p1[1]); dc.setPenWidth(1); }
            else { const p = Geo.polar(cx, cy, ro - r * 0.02, a); dc.fillCircle(p[0], p[1], 2); }
          }
        }
        if (style === 3) this.kit.draw(dc, cx, cy + r * 0.45, data.dateString(cfg.DateFormat), Fonts.COND_BOLD, r * 0.055, color, 1);
      }
      this.drawHands(dc, cx, cy, r, color);
      dc.setColor(color); dc.fillCircle(cx, cy, r * 0.025);
    }
  }

  // ------------------------------------------------------------- Digital --
  class DigitalFace {
    constructor(cfg, kit, fields, data, amoled) { Object.assign(this, {cfg, kit, fields, data, amoled}); this.secAnchor = [0, 0, 0, 0]; }

    timeHeight(r) { return r * [0.30, 0.38, 0.46, 0.56][this.cfg.TimeSize]; }
    sep() { return [":", "", " "][this.cfg.Separator]; }
    timeWidth(dc, p, font, h) { return this.kit.width(dc, p[0] + this.sep() + p[1], font, h); }
    fitTime(dc, p, font, h, maxW) { const w = this.timeWidth(dc, p, font, h); return w > maxW ? h * maxW / w : h; }

    drawTime(dc, x, y, p, font, h, just, hc, mc, sc, ghost) {
      const kit = this.kit, s = this.sep(), full = kit.width(dc, p[0] + s + p[1], font, h);
      let x0 = x;
      if (just === 1) x0 = x - full / 2; else if (just === 2) x0 = x - full;
      const wh = kit.width(dc, p[0], font, h), whs = kit.width(dc, p[0] + s, font, h), wm = kit.width(dc, p[1], font, h);
      kit.ghost = ghost;
      kit.draw(dc, x0, y, p[0], font, h, hc, 0);
      if (s.length && s !== " ") { const sw = kit.width(dc, s, font, h); kit.draw(dc, x0 + wh + (whs - wh - sw) / 2, y, s, font, h, sc, 0); }
      kit.draw(dc, x0 + full - wm, y, p[1], font, h, mc, 0);
      kit.ghost = false;
      return x0 + full;
    }

    ampm(dc, x, y, r, s) { if (s) this.kit.draw(dc, x, y, s, Fonts.COND_BOLD, r * 0.045, this.cfg.fg2, 0); }

    draw(dc, cx, cy, r) {
      const cfg = this.cfg, kit = this.kit, F = this.fields, p = this.data.timeParts(), font = cfg.TimeFont;
      let t = this.timeHeight(r);
      const hc = cfg.cHourDigits, mc = cfg.cMinuteDigits, sc = cfg.fg2, ty = [cfg.Field1, cfg.Field2, cfg.Field3, cfg.Field4];
      const vc = cfg.cField, lc = cfg.cLabel, room = cfg.SecondsMode ? r * 0.25 : 0;
      let iconsY = cy - r * 0.74;
      F.drawGauges(dc, cx, cy, r, r * 0.05, Math.floor(r * 0.03), 100);
      switch (cfg.DigitalLayout) {
        case 1: {
          t *= 0.95;
          const hy = cy - t * 0.62, my = cy + t * 0.62;
          kit.ghost = cfg.Ghost;
          kit.draw(dc, cx, hy, p[0].length < 2 ? "0" + p[0] : p[0], font, t, hc, 1);
          kit.draw(dc, cx, my, p[1], font, t, mc, 1);
          kit.ghost = false;
          this.secAnchor = [cx + kit.width(dc, p[1], font, t) / 2 + r * 0.04, my + t * 0.3, t * 0.32, 0];
          this.ampm(dc, cx + kit.width(dc, p[0], font, t) / 2 + r * 0.04, hy - t * 0.3, r, p[2]);
          F.draw(dc, cx - r * 0.74, cy, ty[0], 0, r, 1, vc, lc, 0.85);
          F.draw(dc, cx + r * 0.74, cy, ty[1], 0, r, 1, vc, lc, 0.85);
          F.draw(dc, cx, cy + r * 0.84, ty[2], 3, r, 1, vc, lc, 1);
          iconsY = cy - r * 0.86;
          break;
        }
        case 2: {
          t = this.fitTime(dc, p, font, t * 1.3, r * 1.7);
          this.drawTime(dc, cx, cy, p, font, t, 1, hc, mc, sc, cfg.Ghost);
          this.secAnchor = [cx, cy + t / 2 + r * 0.3, r * 0.1, 1];
          this.ampm(dc, cx + this.timeWidth(dc, p, font, t) / 2 - r * 0.05, cy - t / 2 - r * 0.06, r, p[2]);
          F.draw(dc, cx, cy - t / 2 - r * 0.17, ty[0], 3, r, 1, vc, lc, 1.1);
          F.draw(dc, cx, cy + t / 2 + r * 0.15, ty[1], 3, r, 1, vc, lc, 1.1);
          iconsY = cy - r * 0.8;
          break;
        }
        case 3: {
          t = this.fitTime(dc, p, font, t * 0.9, r * 1.45 - room);
          const y = cy - r * 0.1, right = this.drawTime(dc, cx, y, p, font, t, 1, hc, mc, sc, cfg.Ghost);
          this.secAnchor = [right + r * 0.03, y + t * 0.32, t * 0.3, 0];
          this.ampm(dc, right + r * 0.03, y - t * 0.32, r, p[2]);
          F.draw(dc, cx, y - t / 2 - r * 0.13, ty[0], 3, r, 1, vc, lc, 1);
          F.draw(dc, cx - r * 0.36, cy + r * 0.36, ty[1], 0, r, 1, vc, lc, 1);
          F.draw(dc, cx + r * 0.36, cy + r * 0.36, ty[2], 0, r, 1, vc, lc, 1);
          F.draw(dc, cx, cy + r * 0.7, ty[3], 0, r, 1, vc, lc, 0.9);
          iconsY = cy - r * 0.78;
          break;
        }
        case 4: {
          t = this.fitTime(dc, p, font, t, r * 1.6 - room);
          const right = this.drawTime(dc, cx, cy, p, font, t, 1, hc, mc, sc, cfg.Ghost);
          this.secAnchor = [right + r * 0.03, cy + t * 0.32, t * 0.3, 0];
          this.ampm(dc, right + r * 0.03, cy - t * 0.32, r, p[2]);
          F.draw(dc, cx, cy + t / 2 + r * 0.16, ty[0], 3, r, 1, vc, lc, 1);
          iconsY = cy - t / 2 - r * 0.2;
          break;
        }
        case 5: {
          t *= 0.8;
          const x = cx + r * 0.08, hy = cy - t * 0.62, my = cy + t * 0.62;
          kit.ghost = cfg.Ghost;
          kit.draw(dc, x, hy, p[0], font, t, hc, 2);
          kit.draw(dc, x, my, p[1], font, t, mc, 2);
          kit.ghost = false;
          this.secAnchor = [x, my + t / 2 + r * 0.14, t * 0.3, 2];
          this.ampm(dc, x - kit.width(dc, p[0], font, t) - r * 0.04, hy - t * 0.3, r, p[2]);
          dc.setColor(cfg.accent); dc.setPenWidth(2); dc.drawLine(x + r * 0.08, cy - t * 1.1, x + r * 0.08, cy + t * 1.1); dc.setPenWidth(1);
          const fx = x + r * 0.16;
          F.draw(dc, fx, cy - r * 0.3, ty[0], 0, r, 0, vc, lc, 0.85);
          F.draw(dc, fx, cy, ty[1], 0, r, 0, vc, lc, 0.85);
          F.draw(dc, fx, cy + r * 0.3, ty[2], 0, r, 0, vc, lc, 0.85);
          F.draw(dc, cx, cy + r * 0.8, ty[3], 3, r, 1, vc, lc, 1);
          iconsY = cy - r * 0.8;
          break;
        }
        default: {
          t = this.fitTime(dc, p, font, t, r * 1.55 - room);
          const right = this.drawTime(dc, cx, cy, p, font, t, 1, hc, mc, sc, cfg.Ghost);
          this.secAnchor = [right + r * 0.03, cy + t * 0.32, t * 0.3, 0];
          this.ampm(dc, right + r * 0.03, cy - t * 0.32, r, p[2]);
          F.draw(dc, cx, cy - t / 2 - r * 0.15, ty[0], 3, r, 1, vc, lc, 1.15);
          F.draw(dc, cx - r * 0.34, cy + t / 2 + r * 0.2, ty[1], 0, r, 1, vc, lc, 1);
          F.draw(dc, cx + r * 0.34, cy + t / 2 + r * 0.2, ty[2], 0, r, 1, vc, lc, 1);
          F.draw(dc, cx, cy + r * 0.76, ty[3], 3, r, 1, vc, lc, 1);
          iconsY = cy - t / 2 - r * 0.33;
        }
      }
      if (cfg.StatusIcons) F.drawStatus(dc, cx, iconsY, r, cfg.fg2);
    }

    drawSeconds(dc) {
      const a = this.secAnchor;
      this.kit.draw(dc, a[0], a[1], String(this.data.clock.sec).padStart(2, "0"), this.cfg.TimeFont, a[2], this.cfg.accent, a[3]);
    }

    drawAod(dc, cx, cy, r, color, style) {
      const cfg = this.cfg, p = this.data.timeParts();
      let font = cfg.AodFont === 99 ? cfg.TimeFont : cfg.AodFont;
      if (this.amoled && cfg.AodOutline) font = Fonts.outlineOf(font);
      const t = this.fitTime(dc, p, font, r * 0.34, r * 1.4);
      this.drawTime(dc, cx, cy, p, font, t, 1, color, color, color, false);
      if (style === 3) this.kit.draw(dc, cx, cy + t / 2 + r * 0.16, this.data.dateString(cfg.DateFormat), Fonts.COND_BOLD, r * 0.055, color, 1);
    }
  }

  // ---------------------------------------------------------------- View --
  //! Port of FaceView.onUpdate for one frame.
  //! opts: {size, amoled, state: "awake"|"low"|"night-awake"|"night-low", clock: {hour,min,sec,date}, use24h, themes}
  function render(ctx, values, opts) {
    const {size, amoled, state, clock, use24h, themes} = opts;
    const awake = state === "awake" || state === "night-awake";
    const night = state.startsWith("night");
    const cfg = resolve(values, themes);
    if (night && cfg.NightTrigger) fade(cfg, cfg.NightFade, !amoled);
    const dc = new Dc(ctx, size);
    const kit = new TextKit();
    kit.ghostColor = cfg.ghost; kit.bgColor = cfg.bg; kit.mip = !amoled;
    const data = new DataSource(cfg, clock, use24h);
    const fields = new Fields(cfg, kit, data);
    const analog = new AnalogFace(cfg, kit, fields, clock, amoled);
    const digital = new DigitalFace(cfg, kit, fields, data, amoled);
    const cx = size / 2, cy = size / 2, r = size / 2;

    if (!awake) {
      let style = cfg.AodStyle;
      if (amoled && (style === 0 || style === 1)) style = 3;
      if (amoled || style >= 2) {
        const bg = amoled ? 0 : cfg.bg, color = amoled ? cfg.AodColor : cfg.fg;
        dc.clear(bg);
        if (cfg.Mode === 0) analog.drawAod(dc, cx, cy, r, color, style, data);
        else digital.drawAod(dc, cx, cy, r, color, style);
        return;
      }
    }
    dc.clear(cfg.bg);
    if (cfg.Mode === 0) { analog.drawDial(dc, cx, cy, r); analog.drawHands(dc, cx, cy, r, null); }
    else digital.draw(dc, cx, cy, r);
    const showSec = (cfg.SecondsMode === 1 && awake) || (cfg.SecondsMode === 2 && (awake || !amoled));
    if (cfg.Mode === 0) { if (showSec) analog.drawSecond(dc, cx, cy, r); else analog.drawCap(dc, cx, cy, r, cfg.cMinuteHand); }
    else if (showSec) digital.drawSeconds(dc);
  }

  //! Approximate share of lit pixels (AMOLED burn-in budget is 10 %).
  function litShare(ctx, size) {
    const d = ctx.getImageData(0, 0, size, size).data;
    let lit = 0, total = 0;
    const r2 = (size / 2) * (size / 2);
    for (let y = 0; y < size; y += 2) for (let x = 0; x < size; x += 2) {
      const dx = x - size / 2, dy = y - size / 2;
      if (dx * dx + dy * dy > r2) continue;
      total++;
      const i = (y * size + x) * 4;
      if (d[i] + d[i + 1] + d[i + 2] > 24) lit++;
    }
    return total ? lit / total : 0;
  }

  return {render, litShare, mix, Dc};
})();
