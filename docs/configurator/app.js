// Open Face web configurator: pick a screen type and device, change settings, preview, export.
"use strict";

(async () => {
  const root = document.getElementById("of-config");
  const base = root.dataset.base || "configurator/";
  const [schema, devices] = await Promise.all([
    fetch(base + "schema.json").then((r) => r.json()),
    fetch(base + "devices.json").then((r) => r.json()),
  ]);

  const settings = schema.groups.flatMap((g) => g.settings.map((s) => ({...s, group: g.id})));
  const byKey = Object.fromEntries(settings.map((s) => [s.key, s]));
  const defaults = Object.fromEntries(settings.map((s) => [s.key, s.default]));
  const amoledOnly = new Set(schema.amoledOnly);
  // Watch faces (Mode values): Analog and Digital categories, each face with its own settings.
  const faces = schema.faces;
  const faceSettings = Object.fromEntries(faces.map((f) => [f.value, new Set(f.settings)]));
  const categories = [...new Set(faces.map((f) => f.category))];
  const hour12 = (new Intl.DateTimeFormat(undefined, {hour: "numeric"}).resolvedOptions().hourCycle || "h23").startsWith("h1");

  // Fields shown per layout (AnalogFace.slots / DigitalFace.draw).
  const ANALOG_SLOTS = [3, 4, 4, 0, 2, 2];
  const DIGITAL_SLOTS = [4, 3, 2, 4, 1, 4];
  const PROCEDURAL = new Set([7, 8, 9, 10, 11, 12, 13]);

  const state = {
    screen: null,
    device: null,
    values: {...defaults},
    preview: "awake",
    live: false,
    backlight: false,
    open: new Set(["General", "Analog", "Digital", "Tactix"]),
  };

  // ------------------------------------------------------------ helpers --
  const $ = (sel, el = root) => el.querySelector(sel);
  const h = (tag, attrs = {}, ...kids) => {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (k === "class") el.className = v;
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (v !== false && v !== null && v !== undefined) el.setAttribute(k, v === true ? "" : v);
    }
    for (const kid of kids.flat()) if (kid !== null && kid !== undefined) el.append(kid);
    return el;
  };
  const hex = (n) => "#" + (n >>> 0 & 0xFFFFFF).toString(16).padStart(6, "0").toUpperCase();
  const options = (s) => (s.kind === "bool" ? null : schema.enums[s.kind]);
  const labelOf = (s, v) => {
    if (s.kind === "bool") return v ? "On" : "Off";
    const o = options(s).find(([val]) => val === v);
    return o ? o[1] : String(v);
  };

  // Which settings apply to the current screen and choices.
  function relevant(s) {
    const v = state.values, k = s.key;
    // The face itself is picked in step 1.
    if (k === "Mode" || !faceSettings[v.Mode]?.has(k)) return false;
    if (state.screen === "mip" && amoledOnly.has(k)) return false;
    if (s.group === "Analog" || s.group === "Dial") {
      if (v.Mode !== 0) return false;
      if (["NumeralFont", "NumeralSize", "NumeralColor"].includes(k) && v.Numerals === 0) return false;
      if ((k === "SecondHand" || k === "SecondHandColor") && v.SecondsMode === 0) return false;
      return true;
    }
    if (s.group === "Digital") {
      if (v.Mode !== 1) return false;
      if ((k === "Ghost" || k === "GhostColor") && !PROCEDURAL.has(v.TimeFont)) return false;
      if (k === "GhostColor" && !v.Ghost) return false;
      return true;
    }
    if (["BgColor", "PrimaryColor", "SecondaryColor", "AccentColor"].includes(k)) return v.Theme === 0;
    if (k === "AodFont") return v.Mode === 1;
    if (k === "AodMarkers") return v.Mode === 0;
    if (k === "NightFade") return v.NightTrigger !== 0;
    return true;
  }

  function fieldNote(k) {
    const m = /^Field(\d)$/.exec(k);
    if (!m) return "";
    const v = state.values;
    const n = v.Mode === 0 ? ANALOG_SLOTS[v.AnalogLayout] : DIGITAL_SLOTS[v.DigitalLayout];
    return Number(m[1]) > n ? "not shown in this layout" : "";
  }

  function optionDisabled(s, val) {
    return s.key === "SecondsMode" && val === 2 && state.screen === "amoled";
  }

  // ----------------------------------------------------------- step 1 --
  function renderStep1() {
    const pick = (screen) => {
      state.screen = screen;
      const list = devices.filter((d) => d.display === screen);
      const pref = screen === "amoled" ? "fr970" : "fenix8solar47mm";
      state.device = (list.find((d) => d.id === pref) || list[0]).id;
      if (screen === "amoled" && state.values.SecondsMode === 2) state.values.SecondsMode = 1;
      if (screen === "mip") state.preview = "awake";
      update();
    };
    const card = (screen, title, text) => h("button", {
      type: "button", class: "of-screen" + (state.screen === screen ? " active" : ""), onclick: () => pick(screen),
      "aria-pressed": state.screen === screen ? "true" : "false",
    }, h("strong", {}, title), h("span", {}, text));
    const list = devices.filter((d) => d.display === state.screen);
    const sel = h("select", {class: "form-select", "aria-label": "Device", disabled: !state.screen,
      onchange: (e) => { state.device = e.target.value; update(); }},
      list.map((d) => h("option", {value: d.id, selected: d.id === state.device}, `${d.name} · ${d.size}×${d.size}`)));
    $("#of-step1").replaceChildren(
      h("div", {class: "of-screens"},
        card("amoled", "AMOLED", "Forerunner 165/265/570/965/970, fēnix 8/9/E, epix Pro, Venu, vívoactive 5/6. Always-on uses a burn-in-safe face."),
        card("mip", "MIP (memory-in-pixel)", "fēnix 7 Pro / 8 Solar / 9 Pro Solar, enduro 3, Forerunner 255/955. Full face at all times, any background, seconds every second.")),
      h("label", {class: "of-device"}, h("span", {}, "Device"), sel),
      state.screen ? renderFaces() : null);
  }

  function renderFaces() {
    const pick = (f) => { state.values.Mode = f.value; update(); };
    return h("div", {class: "of-faces"},
      h("span", {class: "of-faces-title"}, "Watch face"),
      categories.map((cat) => h("div", {class: "of-category", role: "group", "aria-label": cat},
        h("strong", {}, cat),
        h("div", {class: "of-category-faces"}, faces.filter((f) => f.category === cat).map((f) => {
          const active = state.values.Mode === f.value;
          return h("button", {
            type: "button", class: "of-face" + (active ? " active" : ""), "aria-pressed": active ? "true" : "false",
            title: f.description, onclick: () => pick(f),
          }, h("span", {}, f.name), h("code", {}, f.id));
        })))));
  }

  // ----------------------------------------------------------- step 2 --
  function control(s) {
    const v = state.values[s.key];
    const set = (val) => { state.values[s.key] = val; update(); };
    if (s.kind === "bool") {
      return h("div", {class: "form-check form-switch"},
        h("input", {class: "form-check-input", type: "checkbox", role: "switch", id: "of-" + s.key, checked: v,
          onchange: (e) => set(e.target.checked)}));
    }
    if (s.kind === "palette" || s.kind === "palauto") {
      const opts = options(s);
      return h("div", {class: "of-swatches", role: "radiogroup", "aria-label": s.title},
        opts.map(([val, label]) => h("button", {
          type: "button", role: "radio", "aria-checked": val === v ? "true" : "false", title: label,
          class: "of-swatch" + (val === v ? " active" : "") + (val < 0 ? " auto" : ""),
          style: val < 0 ? "" : `background:${hex(val)}`, onclick: () => set(val),
        }, val < 0 ? "Auto" : "")));
    }
    return h("select", {class: "form-select form-select-sm", id: "of-" + s.key, onchange: (e) => set(Number(e.target.value))},
      options(s).map(([val, label]) => h("option", {value: val, selected: val === v, disabled: optionDisabled(s, val)}, label)));
  }

  function renderStep2() {
    const groups = schema.groups.map((g) => {
      const rows = g.settings.map((s) => byKey[s.key]).filter(relevant).map((s) => {
        const changed = state.values[s.key] !== s.default;
        const note = fieldNote(s.key);
        return h("div", {class: "of-row" + (changed ? " changed" : "") + (note ? " muted" : "")},
          h("label", {for: "of-" + s.key}, s.title, note ? h("small", {}, note) : null),
          control(s));
      });
      if (!rows.length) return null;
      return h("details", {class: "of-group", open: state.open.has(g.id), ontoggle: (e) => {
        e.target.open ? state.open.add(g.id) : state.open.delete(g.id);
      }}, h("summary", {}, h("span", {}, g.title), h("small", {}, g.description)), rows);
    });
    $("#of-settings").replaceChildren(...groups.filter(Boolean));
  }

  // ----------------------------------------------------------- preview --
  const canvas = h("canvas", {class: "of-canvas", role: "img", "aria-label": "Watch face preview"});
  function clock() {
    const d = new Date();
    if (state.live) return {hour: d.getHours(), min: d.getMinutes(), sec: d.getSeconds(), date: d};
    return {hour: 10, min: 9, sec: 36, date: d};
  }

  const use24h = () => state.values.HourFormat === 2 || (state.values.HourFormat === 0 && !hour12);

  // MIP look: reflective transflective panel. Calibrated by eye against fēnix 8 Solar photos:
  // black reads as dark slate, white as light gray, colors lose about a third of their saturation.
  const MIP_TONE = {
    off: {black: [40, 44, 50], white: [200, 204, 206], sat: 0.62},
    light: {black: [46, 54, 66], white: [222, 230, 238], sat: 0.7},
  };

  //! Quantize to the 64-color MIP palette, then apply the panel's tone response.
  function mipFilter(img, backlight) {
    const t = backlight ? MIP_TONE.light : MIP_TONE.off;
    const d = img.data;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i + 3] === 0) continue;
      let r = Math.round(d[i] / 85) * 85, g = Math.round(d[i + 1] / 85) * 85, b = Math.round(d[i + 2] / 85) * 85;
      const l = 0.299 * r + 0.587 * g + 0.114 * b;
      r = l + (r - l) * t.sat; g = l + (g - l) * t.sat; b = l + (b - l) * t.sat;
      d[i] = t.black[0] + r / 255 * (t.white[0] - t.black[0]);
      d[i + 1] = t.black[1] + g / 255 * (t.white[1] - t.black[1]);
      d[i + 2] = t.black[2] + b / 255 * (t.white[2] - t.black[2]);
    }
    return img;
  }

  function draw() {
    if (!state.screen) return;
    const dev = devices.find((d) => d.id === state.device);
    const size = dev.size;
    const mip = state.screen === "mip";
    const css = Math.min(340, root.clientWidth - 32);
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(css * dpr);
    canvas.height = Math.round(css * dpr);
    canvas.style.width = css + "px";
    canvas.style.height = css + "px";
    const ctx = canvas.getContext("2d");
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const opts = {size, amoled: !mip, state: state.preview, clock: clock(), use24h: use24h(), themes: schema.themes};
    canvas.parentElement.classList.toggle("mip", mip);

    if (!mip) {
      ctx.scale(canvas.width / size, canvas.height / size);
      ctx.save();
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
      ctx.clip();
      OF.render(ctx, state.values, opts);
      ctx.restore();
    } else {
      // Render at the panel's native resolution, filter, then upscale without smoothing so
      // individual MIP pixels stay visible.
      const off = document.createElement("canvas");
      off.width = off.height = size;
      const octx = off.getContext("2d");
      OF.render(octx, state.values, opts);
      octx.putImageData(mipFilter(octx.getImageData(0, 0, size, size), state.backlight), 0, 0);
      const k = canvas.width / size;
      ctx.save();
      ctx.beginPath();
      ctx.arc(canvas.width / 2, canvas.height / 2, canvas.width / 2, 0, Math.PI * 2);
      ctx.clip();
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(off, 0, 0, canvas.width, canvas.height);
      // Pixel grid, visible once a panel pixel spans at least 3 screen pixels.
      if (k >= 3) {
        ctx.strokeStyle = "rgba(0, 0, 0, 0.13)";
        ctx.lineWidth = Math.max(1, Math.floor(k / 4));
        ctx.beginPath();
        for (let i = 1; i < size; i++) {
          const p = Math.round(i * k) + 0.5;
          ctx.moveTo(p, 0); ctx.lineTo(p, canvas.height);
          ctx.moveTo(0, p); ctx.lineTo(canvas.width, p);
        }
        ctx.stroke();
      }
      // Glare of the reflective layer and the glass.
      const g = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
      g.addColorStop(0, "rgba(255, 255, 255, 0.10)");
      g.addColorStop(0.45, "rgba(255, 255, 255, 0.02)");
      g.addColorStop(1, "rgba(0, 0, 0, 0.10)");
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.restore();
    }

    // Burn-in budget readout for AMOLED always-on.
    const info = $("#of-lit");
    if (state.screen === "amoled" && state.preview.endsWith("low")) {
      const off = document.createElement("canvas");
      off.width = off.height = size;
      const octx = off.getContext("2d");
      OF.render(octx, state.values, {size, amoled: true, state: state.preview, clock: clock(), use24h: use24h(), themes: schema.themes});
      const pct = OF.litShare(octx, size) * 100;
      info.textContent = `≈ ${pct.toFixed(1)} % of pixels lit (AMOLED limit: 10 %)`;
      info.className = "of-lit " + (pct > 10 ? "bad" : "ok");
    } else {
      info.textContent = "";
    }
  }

  function renderPreviewControls() {
    // MIP shows the same face at all times: nothing to switch between.
    const tabs = state.screen === "amoled" ? [["awake", "Awake"], ["low", "Always-on"],
      ["night-awake", "Night"], ["night-low", "Night, asleep"]] : [];
    $("#of-tabs").replaceChildren(...tabs.map(([id, label]) => h("button", {
      type: "button", class: "btn btn-sm " + (state.preview === id ? "btn-primary" : "btn-outline-secondary"),
      "aria-pressed": state.preview === id ? "true" : "false", onclick: () => { state.preview = id; update(); },
    }, label)));
    const nightOff = state.preview.startsWith("night") && !state.values.NightTrigger;
    $("#of-note").textContent = nightOff ? "Night dimming is off: set Night → Night dimming to preview the fade." : "";
  }

  // ------------------------------------------------------------ export --
  function changes() {
    return settings.filter((s) => state.values[s.key] !== s.default);
  }

  function shareLink() {
    const diff = Object.fromEntries(changes().map((s) => [s.key, state.values[s.key]]));
    const payload = btoa(JSON.stringify({s: state.screen, d: state.device, v: diff}));
    return location.origin + location.pathname + "#c=" + payload;
  }

  function presetJson() {
    return JSON.stringify({
      device: state.device, screen: state.screen,
      values: Object.fromEntries(changes().map((s) => [s.key, state.values[s.key]])),
    }, null, 2) + "\n";
  }

  function renderSummary() {
    const ch = changes();
    const titleOf = Object.fromEntries(schema.groups.map((g) => [g.id, g.title]));
    const table = ch.length
      ? h("table", {class: "table table-sm of-changes"},
        h("thead", {}, h("tr", {}, h("th", {}, "Group"), h("th", {}, "Setting"), h("th", {}, "Value"))),
        h("tbody", {}, ch.map((s) => h("tr", {}, h("td", {}, titleOf[s.group]), h("td", {}, s.title),
          h("td", {}, (s.kind === "palette" || s.kind === "palauto") && state.values[s.key] >= 0
            ? h("span", {class: "of-chip", style: `background:${hex(state.values[s.key])}`}) : null,
          labelOf(s, state.values[s.key]))))))
      : h("p", {class: "text-muted"}, "All settings at their defaults.");
    const btn = (label, fn, cls = "btn-outline-secondary") => h("button", {type: "button", class: "btn btn-sm " + cls, onclick: fn}, label);
    const status = h("span", {class: "of-status", role: "status"});
    const flash = (t) => { status.textContent = t; setTimeout(() => { status.textContent = ""; }, 2500); };
    $("#of-summary").replaceChildren(
      h("p", {}, `${ch.length} change${ch.length === 1 ? "" : "s"} from the defaults. Apply them in the Garmin Connect app `
        + "(Device → Watch Faces → Open Face → Settings) or on the watch (Watch Face → Open Face → Customize)."),
      table,
      h("div", {class: "of-actions"},
        btn("Copy share link", async () => {
          const url = shareLink();
          history.replaceState(null, "", url);
          try { await navigator.clipboard.writeText(url); flash("Link copied"); } catch { flash("Link is in the address bar"); }
        }, "btn-primary"),
        btn("Download preset", () => {
          const a = h("a", {href: URL.createObjectURL(new Blob([presetJson()], {type: "application/json"})), download: "openface-preset.json"});
          a.click();
          URL.revokeObjectURL(a.href);
        }),
        btn("Reset to defaults", () => { state.values = {...defaults}; history.replaceState(null, "", location.pathname); update(); }),
        status),
      h("p", {class: "small text-muted"},
        "Side-loaded builds cannot be configured from Garmin Connect. To bake a preset into a build: ",
        h("code", {}, "python3 tools/apply_preset.py openface-preset.json"), " then ",
        h("code", {}, "tools/build.sh \"$SDK\" developer_key.der build prg"), "."));
  }

  // ------------------------------------------------------------ wiring --
  function update() {
    root.classList.toggle("ready", !!state.screen);
    renderStep1();
    if (!state.screen) return;
    renderStep2();
    renderPreviewControls();
    renderSummary();
    draw();
  }

  function loadHash() {
    const m = /#c=([A-Za-z0-9+/=]+)/.exec(location.hash);
    if (!m) return;
    try {
      const p = JSON.parse(atob(m[1]));
      if (p.s === "amoled" || p.s === "mip") state.screen = p.s;
      if (devices.some((d) => d.id === p.d)) state.device = p.d;
      for (const [k, v] of Object.entries(p.v || {})) {
        const s = byKey[k];
        if (!s) continue;
        if (s.kind === "bool" ? typeof v === "boolean" : options(s).some(([val]) => val === v)) state.values[k] = v;
      }
    } catch (e) {
      console.warn("Ignoring malformed configuration link", e);
    }
  }

  root.replaceChildren(
    h("section", {class: "of-step"}, h("h2", {}, "1 · Screen type"), h("div", {id: "of-step1"})),
    h("div", {class: "of-main"},
      h("section", {class: "of-step of-left"}, h("h2", {}, "2 · Settings"), h("div", {id: "of-settings"})),
      h("div", {class: "of-right"},
        h("div", {class: "of-preview"},
          h("div", {class: "of-watch"}, canvas),
          h("div", {id: "of-tabs", class: "of-tabs"}),
          h("label", {class: "form-check of-live of-backlight"},
            h("input", {class: "form-check-input", type: "checkbox", onchange: (e) => { state.backlight = e.target.checked; draw(); }}),
            h("span", {class: "form-check-label"}, "Backlight (MIP)")),
          h("label", {class: "form-check of-live"},
            h("input", {class: "form-check-input", type: "checkbox", onchange: (e) => { state.live = e.target.checked; draw(); }}),
            h("span", {class: "form-check-label"}, "Live time (otherwise 10:09:36)")),
          h("p", {id: "of-lit", class: "of-lit"}),
          h("p", {id: "of-note", class: "of-note"})),
        h("section", {class: "of-step"}, h("h2", {}, "3 · Apply"), h("div", {id: "of-summary"})))));

  loadHash();
  if (state.screen && !state.device) state.device = devices.find((d) => d.display === state.screen).id;
  update();
  document.fonts.ready.then(draw);
  window.addEventListener("resize", draw);
  setInterval(() => { if (state.live) draw(); }, 1000);
})();
