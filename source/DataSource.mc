import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

//! Field types. Values match the "fields" enum in tools/gen_settings.py.
module F {
    const OFF = 0;
    const DATE = 1;
    const WEEKDAY = 2;
    const BATTERY = 3;
    const BATTERY_DAYS = 4;
    const STEPS = 5;
    const HEART = 6;
    const CALORIES = 7;
    const DISTANCE = 8;
    const FLOORS = 9;
    const ACTIVE = 10;
    const BODY_BATTERY = 11;
    const STRESS = 12;
    const NOTIFICATIONS = 13;
    const ALTITUDE = 14;
    const TEMPERATURE = 15;
    const SUN = 16;
    const WEEK = 17;
    const TIME = 18;
    const SECONDS = 19;
    const RESPIRATION = 20;
    const RECOVERY = 21;
    const DAY_PROGRESS = 22;
}

//! Reads sensor and system data. Every getter is defensive: unsupported data yields "--".
//! Values are cached until invalidate(), which the view calls once per minute and on wrist raise,
//! so each sensor is queried at most once per refresh however many slots show it.
class DataSource {
    var cfg as Config;

    private var _values as Dictionary<Number, String> = {};
    private var _fractions as Dictionary<Number, Float or Null> = {};
    private var _am as ActivityMonitor.Info? = null;

    private const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    private const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

    function initialize(config as Config) {
        cfg = config;
    }

    function label(type as Number) as String {
        switch (type) {
            case F.BATTERY: case F.BATTERY_DAYS: return "BAT";
            case F.STEPS: return "STEPS";
            case F.HEART: return "HR";
            case F.CALORIES: return "KCAL";
            case F.DISTANCE:
                return System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE ? "MI" : "KM";
            case F.FLOORS: return "FLOORS";
            case F.ACTIVE: return "ACTIVE";
            case F.BODY_BATTERY: return "BODY";
            case F.STRESS: return "STRESS";
            case F.NOTIFICATIONS: return "MSG";
            case F.ALTITUDE: return "ALT";
            case F.TEMPERATURE: return "TEMP";
            case F.SUN: return "SUN";
            case F.WEEK: return "WEEK";
            case F.RESPIRATION: return "BRPM";
            case F.RECOVERY: return "RECOV";
            case F.DAY_PROGRESS: return "DAY";
        }
        return "";
    }

    function invalidate() as Void {
        _values = {};
        _fractions = {};
        _am = null;
    }

    private function info() as ActivityMonitor.Info {
        var am = _am;
        if (am == null) {
            am = ActivityMonitor.getInfo();
            _am = am;
        }
        return am;
    }

    function value(type as Number) as String {
        var v = _values[type];
        if (v != null) {
            return v;
        }
        try {
            v = valueUnsafe(type);
        } catch (e) {
            v = "--";
        }
        if (type != F.SECONDS) {
            _values[type] = v;
        }
        return v;
    }

    private function valueUnsafe(type as Number) as String {
        var am = info();
        switch (type) {
            case F.DATE:
                return dateString(cfg.DateFormat);
            case F.WEEKDAY: {
                var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
                return DAYS[(d.day_of_week as Number) - 1] + " " + d.day.toString();
            }
            case F.BATTERY:
                return (System.getSystemStats().battery + 0.5).toNumber().toString() + "%";
            case F.BATTERY_DAYS: {
                var s = System.getSystemStats();
                if (s has :batteryInDays) {
                    return (s.batteryInDays + 0.5).toNumber().toString() + "D";
                }
                return "--";
            }
            case F.STEPS:
                return num(am.steps);
            case F.HEART:
                return num(heartRate());
            case F.CALORIES:
                return num(am.calories);
            case F.DISTANCE: {
                var cm = am.distance;
                if (cm == null) {
                    return "--";
                }
                var div = System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE ? 160934.4 : 100000.0;
                return (cm / div).format("%.1f");
            }
            case F.FLOORS:
                return num(am.floorsClimbed);
            case F.ACTIVE: {
                var a = am.activeMinutesWeek;
                return (a == null) ? "--" : a.total.toString();
            }
            case F.BODY_BATTERY:
                return num(history(0));
            case F.STRESS:
                return num(history(1));
            case F.NOTIFICATIONS:
                return System.getDeviceSettings().notificationCount.toString();
            case F.ALTITUDE: {
                var alt = Activity.getActivityInfo().altitude;
                if (alt == null) {
                    alt = history(2);
                }
                if (alt == null) {
                    return "--";
                }
                if (System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE) {
                    alt = alt * 3.28084;
                }
                return alt.toNumber().toString();
            }
            case F.TEMPERATURE: {
                var w = Weather.getCurrentConditions();
                if (w == null || w.temperature == null) {
                    return "--";
                }
                var t = w.temperature as Numeric;
                if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                    t = t * 9 / 5.0 + 32;
                }
                return t.toNumber().toString() + "°";
            }
            case F.SUN:
                return sunEvent();
            case F.WEEK:
                return isoWeek().toString();
            case F.TIME:
                return timeString();
            case F.SECONDS:
                return Clock.time().sec.format("%02d");
            case F.RESPIRATION:
                return (am has :respirationRate) ? num(am.respirationRate) : "--";
            case F.RECOVERY:
                return (am has :timeToRecovery) ? num(am.timeToRecovery) + "H" : "--";
            case F.DAY_PROGRESS: {
                var c = Clock.time();
                return ((c.hour * 60 + c.min) * 100 / 1440).toString() + "%";
            }
        }
        return "";
    }

    //! Goal completion 0..1, or null if the type has no goal.
    function fraction(type as Number) as Float? {
        if (type != F.SECONDS && _fractions.hasKey(type)) {
            return _fractions[type];
        }
        var f = fractionUnsafe(type);
        _fractions[type] = f;
        return f;
    }

    private function fractionUnsafe(type as Number) as Float? {
        try {
            var am = info();
            switch (type) {
                case F.BATTERY:
                    return System.getSystemStats().battery / 100.0;
                case F.STEPS:
                    return ratio(am.steps, am.stepGoal);
                case F.FLOORS:
                    return ratio(am.floorsClimbed, am.floorsClimbedGoal);
                case F.ACTIVE: {
                    var a = am.activeMinutesWeek;
                    return (a == null) ? null : ratio(a.total, am.activeMinutesWeekGoal);
                }
                case F.BODY_BATTERY: {
                    var v = history(0);
                    return (v == null) ? null : ratio(v, 100);
                }
                case F.STRESS: {
                    var v = history(1);
                    return (v == null) ? null : ratio(v, 100);
                }
                case F.HEART: {
                    var hr = heartRate();
                    return (hr == null) ? null : ratio(hr - 40, 150);
                }
                case F.SECONDS:
                    return Clock.time().sec / 60.0;
                case F.DAY_PROGRESS: {
                    var c = Clock.time();
                    return (c.hour * 60 + c.min) / 1440.0;
                }
            }
        } catch (e) {
            return null;
        }
        return null;
    }

    //! Gauge metric (the "gauges" enum) mapped onto field fractions.
    function gauge(metric as Number) as Float? {
        switch (metric) {
            case 1: return fraction(F.BATTERY);
            case 2: return fraction(F.STEPS);
            case 3: return fraction(F.BODY_BATTERY);
            case 4: return fraction(F.STRESS);
            case 5: return fraction(F.ACTIVE);
            case 6: return fraction(F.FLOORS);
            case 7: return fraction(F.SECONDS);
            case 8: return fraction(F.HEART);
            case 9: return fraction(F.DAY_PROGRESS);
        }
        return null;
    }

    // ------------------------------------------------------------ time --

    //! [hours, minutes, ampm] strings for the current time.
    function timeParts() as Array<String> {
        var c = Clock.time();
        var h = c.hour;
        var ampm = "";
        if (!cfg.use24h) {
            ampm = (h < 12) ? "AM" : "PM";
            h = h % 12;
            if (h == 0) {
                h = 12;
            }
        }
        var hs = cfg.LeadingZero ? h.format("%02d") : h.toString();
        return [hs, c.min.format("%02d"), ampm];
    }

    function timeString() as String {
        var p = timeParts();
        return p[0] + ":" + p[1];
    }

    function dateString(fmt as Number) as String {
        var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var day = d.day as Number;
        var mon = d.month as Number;
        var dow = DAYS[(d.day_of_week as Number) - 1];
        var mname = MONTHS[mon - 1];
        switch (fmt) {
            case 1: return day.toString() + " " + mname;
            case 2: return dow + " " + day.toString() + " " + mname;
            case 3: return (d.year as Number).toString() + "-" + mon.format("%02d") + "-" + day.format("%02d");
            case 4: return day.format("%02d") + "." + mon.format("%02d");
            case 5: return mon.format("%02d") + "/" + day.format("%02d");
        }
        return dow + " " + day.toString();
    }

    // --------------------------------------------------------- helpers --

    private function num(v as Numeric?) as String {
        return (v == null) ? "--" : v.toNumber().toString();
    }

    private function ratio(v as Numeric?, goal as Numeric?) as Float? {
        if (v == null || goal == null || goal <= 0) {
            return null;
        }
        var r = v.toFloat() / goal;
        if (r > 1.0) {
            r = 1.0f;
        } else if (r < 0.0) {
            r = 0.0f;
        }
        return r.toFloat();
    }

    private function heartRate() as Number? {
        var hr = Activity.getActivityInfo().currentHeartRate;
        if (hr == null && (ActivityMonitor has :getHeartRateHistory)) {
            var s = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (s != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = s.heartRate;
            }
        }
        return hr;
    }

    //! Latest sample: 0 body battery, 1 stress, 2 elevation.
    private function history(kind as Number) as Numeric? {
        if (!(Toybox has :SensorHistory)) {
            return null;
        }
        var it = null;
        if (kind == 0 && (SensorHistory has :getBodyBatteryHistory)) {
            it = SensorHistory.getBodyBatteryHistory({:period => 1});
        } else if (kind == 1 && (SensorHistory has :getStressHistory)) {
            it = SensorHistory.getStressHistory({:period => 1});
        } else if (kind == 2 && (SensorHistory has :getElevationHistory)) {
            it = SensorHistory.getElevationHistory({:period => 1});
        }
        if (it == null) {
            return null;
        }
        var s = it.next();
        return (s == null) ? null : s.data;
    }

    private function sunEvent() as String {
        var w = Weather.getCurrentConditions();
        if (w == null || !(Weather has :getSunrise)) {
            return "--";
        }
        var loc = (w as Weather.CurrentConditions).observationLocationPosition;
        if (loc == null) {
            return "--";
        }
        var now = Time.now();
        var rise = Weather.getSunrise(loc, now);
        var set = Weather.getSunset(loc, now);
        var next = null;
        if (rise != null && now.lessThan(rise)) {
            next = rise;
        } else if (set != null && now.lessThan(set)) {
            next = set;
        } else {
            next = Weather.getSunrise(loc, now.add(new Time.Duration(86400)));
        }
        if (next == null) {
            return "--";
        }
        var i = Gregorian.info(next, Time.FORMAT_SHORT);
        var h = i.hour as Number;
        if (!cfg.use24h) {
            h = h % 12;
            if (h == 0) {
                h = 12;
            }
        }
        return h.toString() + ":" + (i.min as Number).format("%02d");
    }

    //! ISO-8601 week number.
    private function isoWeek() as Number {
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dow = ((now.day_of_week as Number) + 5) % 7; // Monday = 0
        var jan1 = Gregorian.moment({:year => now.year as Number, :month => 1, :day => 1, :hour => 12});
        var today = Gregorian.moment({:year => now.year as Number, :month => now.month as Number, :day => now.day as Number, :hour => 12});
        var doy = (today.value() - jan1.value()) / 86400; // 0-based
        var week = (doy - dow + 10) / 7;
        if (week < 1) {
            return 52;
        }
        if (week == 53) {
            var jan1Dow = (dow - doy % 7 + 7) % 7;
            if (jan1Dow != 3 && !(jan1Dow == 2 && isLeap(now.year as Number))) {
                return 1;
            }
        }
        return week;
    }

    private function isLeap(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    }
}
