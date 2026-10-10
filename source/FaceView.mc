import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

//! Main watch face view: chooses analog/digital, awake/low-power, and drives partial updates.
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
        setupBuffer();
        WatchUi.requestUpdate();
    }

    private function loadConfig() as Void {
        cfg.load();
        if (_night) {
            cfg.fade(cfg.NightFade, !_burnIn);
        }
        applySettings();
    }

    //! Night dimming condition. Connect IQ exposes no focus-mode API; the Sleep focus turns on
    //! Do Not Disturb, and the profile carries the user's bedtime and wake time.
    private function nightActive() as Boolean {
        var t = cfg.NightTrigger;
        if (t == 0) {
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
        kit.reset();
        kit.ghostColor = cfg.ghost;
        kit.bgColor = cfg.bg;
        kit.mip = !_burnIn;
        analog.amoled = _burnIn;
        digital.amoled = _burnIn;
    }

    //! Seconds while sleeping (MIP only) need an off-screen copy of the face to erase the previous second.
    private function useBuffer() as Boolean {
        return _partialOk && cfg.SecondsMode == 2;
    }

    private function setupBuffer() as Void {
        _buffer = null;
        _lastBox = null;
        if (!useBuffer() || _w == 0) {
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
            return (bb == null) ? null : (bb as BufferedBitmap).getDc();
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

        var night = nightActive();
        if (night != _night) {
            _night = night;
            loadConfig();
        }

        if (!_awake) {
            var style = cfg.AodStyle;
            if (_burnIn) {
                // AMOLED: never draw the full face while sleeping.
                if (style == 0 || style == 1) {
                    style = 3;
                }
                drawAod(dc, cx, cy, r, style);
                return;
            }
            if (style >= 2) {
                drawAod(dc, cx, cy, r, style);
                return;
            }
        }

        var bdc = bufferDc();
        if (bdc != null) {
            if (bdc has :setAntiAlias) {
                bdc.setAntiAlias(true);
            }
            drawBase(bdc, cx, cy, r);
            dc.drawBitmap(0, 0, _buffer as BufferedBitmapReference or BufferedBitmap);
        } else {
            drawBase(dc, cx, cy, r);
        }

        var showSec = (cfg.SecondsMode == 1 && _awake) || (cfg.SecondsMode == 2 && (_awake || bdc != null));
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

    private function drawAod(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, style as Number) as Void {
        // AMOLED: black background and the dim AOD color (burn-in). MIP: lit pixels cost nothing,
        // so keep the theme (white backgrounds included).
        var bg = _burnIn ? Graphics.COLOR_BLACK : cfg.bg;
        var color = _burnIn ? cfg.AodColor : cfg.fg;
        dc.setColor(bg, bg);
        dc.clear();
        if (_burnIn && cfg.AodShift) {
            // Move the whole face a few pixels every minute to spread pixel wear.
            var shifts = [[0, 0], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];
            var s = shifts[Clock.time().min % 9];
            var d = r / 60;
            cx += s[0] * d;
            cy += s[1] * d;
        }
        kit.ghost = false;
        if (cfg.Mode == 0) {
            analog.drawAod(dc, cx, cy, r, color, style, data);
        } else {
            digital.drawAod(dc, cx, cy, r, color, style);
        }
    }

    //! MIP low-power seconds: restore the previous second's area from the buffer, then draw the new one.
    function onPartialUpdate(dc as Dc) as Void {
        if (_awake || _buffer == null || cfg.SecondsMode != 2 || cfg.AodStyle >= 2) {
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
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    function onPowerBudgetExceeded() as Void {
        _partialOk = false;
        setupBuffer();
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
