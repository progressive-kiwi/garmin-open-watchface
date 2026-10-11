import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

//! Main watch face view: chooses analog/digital, awake/always-on, and drives partial updates.
//!
//! Compute budget: everything except the seconds is drawn into an off-screen buffer once per minute
//! (or after a settings, sleep/wake or night-dimming change). Every other frame only copies the buffer
//! and draws the second hand or seconds digits.
//!
//! MIP displays have no always-on or night look: the full face is shown at all times, and sleep only
//! stops the per-second redraw (seconds then continue through partial updates if enabled).
class FaceView extends WatchUi.WatchFace {
    var cfg as Config;
    var kit as TextKit;
    var data as DataSource;
    var fields as Fields;
    var analog as AnalogFace;
    var digital as DigitalFace;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _partialOk as Boolean = false;
    private var _buffer as BufferedBitmapReference or BufferedBitmap or Null = null;
    private var _lastBox as Array<Number>? = null;
    private var _night as Boolean = false;
    //! Buffer content is stale: rebuild on the next onUpdate.
    private var _dirty as Boolean = true;
    //! Minute of day the buffer was built for.
    private var _minute as Number = -1;
    //! Some content changes every second (seconds field or gauge), so the buffer is rebuilt each frame.
    private var _perSecond as Boolean = false;
    private var _w as Number = 0;
    private var _h as Number = 0;

    function initialize() {
        WatchFace.initialize();
        cfg = new Config();
        cfg.load();
        kit = new TextKit();
        data = new DataSource(cfg);
        fields = new Fields(cfg, kit, data);
        analog = new AnalogFace(cfg, kit, fields);
        digital = new DigitalFace(cfg, kit, fields, data);
        var ds = System.getDeviceSettings();
        _burnIn = (ds has :requiresBurnInProtection) && ds.requiresBurnInProtection;
        _partialOk = (WatchUi.WatchFace has :onPartialUpdate) && !_burnIn;
        applySettings();
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        setupBuffer();
    }

    //! Re-read properties. Called on start and whenever settings change.
    function reload() as Void {
        loadConfig();
        data.invalidate();
        // Re-evaluate night dimming with the new settings on the next frame.
        _minute = -1;
        WatchUi.requestUpdate();
    }

    private function loadConfig() as Void {
        cfg.load();
        if (_night) {
            cfg.fade(cfg.NightFade);
        }
        applySettings();
    }

    //! Night dimming condition (AMOLED only). Connect IQ exposes no focus-mode API; the Sleep focus
    //! turns on Do Not Disturb, and the profile carries the user's bedtime and wake time.
    private function nightActive() as Boolean {
        var t = cfg.NightTrigger;
        if (t == 0 || !_burnIn) {
            return false;
        }
        if (t == 1 || t == 3) {
            var ds = System.getDeviceSettings();
            if ((ds has :doNotDisturb) && ds.doNotDisturb) {
                return true;
            }
            var am = ActivityMonitor.getInfo();
            if ((am has :isSleepMode) && am.isSleepMode == true) {
                return true;
            }
        }
        if (t == 2 || t == 3) {
            var p = UserProfile.getProfile();
            var sleep = p.sleepTime;
            var wake = p.wakeTime;
            if (sleep != null && wake != null) {
                var c = Clock.time();
                var now = c.hour * 3600 + c.min * 60;
                var s = sleep.value();
                var w = wake.value();
                return (s > w) ? (now >= s || now < w) : (now >= s && now < w);
            }
        }
        return false;
    }

    private function applySettings() as Void {
        _dirty = true;
        _perSecond = cfg.Field1 == F.SECONDS || cfg.Field2 == F.SECONDS || cfg.Field3 == F.SECONDS
            || cfg.Field4 == F.SECONDS || cfg.GaugeLeft == 7 || cfg.GaugeRight == 7;
        kit.reset();
        kit.ghostColor = cfg.ghost;
        kit.bgColor = cfg.bg;
        kit.mip = !_burnIn;
        analog.amoled = _burnIn;
        digital.amoled = _burnIn;
    }

    //! Off-screen copy of the face without seconds. Lives in the graphics pool, not the app heap.
    //! Without it (allocation failed) every frame is drawn directly.
    private function setupBuffer() as Void {
        _buffer = null;
        _lastBox = null;
        _dirty = true;
        if (_w == 0) {
            return;
        }
        try {
            if (Graphics has :createBufferedBitmap) {
                _buffer = Graphics.createBufferedBitmap({:width => _w, :height => _h});
            } else {
                _buffer = new Graphics.BufferedBitmap({:width => _w, :height => _h});
            }
        } catch (e) {
            _buffer = null;
        }
    }

    private function bufferDc() as Dc? {
        var b = _buffer;
        if (b == null) {
            return null;
        }
        if (b instanceof Graphics.BufferedBitmapReference) {
            var bb = b.get();
            if (bb == null) {
                // The system reclaimed the pool memory; the content is gone.
                _dirty = true;
                return null;
            }
            return (bb as BufferedBitmap).getDc();
        }
        return (b as BufferedBitmap).getDc();
    }

    // ---------------------------------------------------------- drawing --

    function onUpdate(dc as Dc) as Void {
        dc.clearClip();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var cx = _w / 2;
        var cy = _h / 2;
        var r = (_w < _h ? _w : _h) / 2;

        // Per-minute work: fresh sensor data, night dimming check, buffer rebuild.
        var c = Clock.time();
        var minute = c.hour * 60 + c.min;
        if (minute != _minute) {
            _minute = minute;
            _dirty = true;
            data.invalidate();
            var night = nightActive();
            if (night != _night) {
                _night = night;
                loadConfig();
            }
        }

        if (!_awake && _burnIn) {
            // AMOLED: never draw the full face while sleeping.
            var style = cfg.AodStyle;
            if (style == 0 || style == 1) {
                style = 3;
            }
            drawAod(dc, cx, cy, r, style);
            return;
        }

        var bdc = bufferDc();
        if (bdc != null) {
            if (_dirty || _perSecond) {
                if (bdc has :setAntiAlias) {
                    bdc.setAntiAlias(true);
                }
                drawBase(bdc, cx, cy, r);
                _dirty = false;
            }
            dc.drawBitmap(0, 0, _buffer as BufferedBitmapReference or BufferedBitmap);
        } else {
            drawBase(dc, cx, cy, r);
        }

        var showSec = (cfg.SecondsMode == 1 && _awake) || (cfg.SecondsMode == 2 && (_awake || (bdc != null && _partialOk)));
        if (cfg.Mode == 0) {
            if (showSec) {
                _lastBox = analog.drawSecond(dc, cx, cy, r);
            } else {
                analog.drawCap(dc, cx, cy, r, cfg.cMinuteHand);
            }
        } else if (showSec) {
            _lastBox = digital.drawSeconds(dc);
        }
    }

    private function drawBase(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric) as Void {
        dc.setColor(cfg.bg, cfg.bg);
        dc.clear();
        dc.fillRectangle(0, 0, _w, _h);
        if (cfg.Mode == 0) {
            analog.drawDial(dc, cx, cy, r);
            analog.drawHands(dc, cx, cy, r, null);
        } else {
            digital.draw(dc, cx, cy, r);
        }
    }

    //! AMOLED always-on face: black background and the dim AOD color (burn-in).
    private function drawAod(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, style as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (cfg.AodShift) {
            // Move the whole face a few pixels every minute to spread pixel wear.
            var shifts = [[0, 0], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];
            var s = shifts[Clock.time().min % 9];
            var d = r / 60;
            cx += s[0] * d;
            cy += s[1] * d;
        }
        kit.ghost = false;
        if (cfg.Mode == 0) {
            analog.drawAod(dc, cx, cy, r, cfg.AodColor, style, data);
        } else {
            digital.drawAod(dc, cx, cy, r, cfg.AodColor, style);
        }
    }

    //! MIP seconds while the watch sleeps: restore the previous second's area from the buffer, then draw the new one.
    function onPartialUpdate(dc as Dc) as Void {
        if (_awake || !_partialOk || _buffer == null || _dirty || cfg.SecondsMode != 2) {
            return;
        }
        var cx = _w / 2;
        var cy = _h / 2;
        var r = (_w < _h ? _w : _h) / 2;
        var buf = _buffer as BufferedBitmapReference or BufferedBitmap;
        if (_lastBox != null) {
            var b = _lastBox as Array<Number>;
            dc.setClip(b[0], b[1], b[2], b[3]);
            dc.drawBitmap(0, 0, buf);
        }
        var box = (cfg.Mode == 0) ? analog.secondBox(cx, cy, r) : digital.secondsBox(dc);
        dc.setClip(box[0], box[1], box[2], box[3]);
        dc.drawBitmap(0, 0, buf);
        if (cfg.Mode == 0) {
            analog.drawSecond(dc, cx, cy, r);
        } else {
            digital.drawSeconds(dc);
        }
        _lastBox = box;
        dc.clearClip();
    }

    function onEnterSleep() as Void {
        _awake = false;
        _dirty = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        // Wrist raise: refresh data immediately instead of at the next minute.
        _awake = true;
        _dirty = true;
        data.invalidate();
        WatchUi.requestUpdate();
    }

    function onPowerBudgetExceeded() as Void {
        _partialOk = false;
    }
}

//! Handles power budget notifications for partial updates.
class FaceDelegate extends WatchUi.WatchFaceDelegate {
    private var _view as FaceView;

    function initialize(view as FaceView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPowerBudgetExceeded(info as WatchFacePowerInfo) as Void {
        _view.onPowerBudgetExceeded();
    }
}
