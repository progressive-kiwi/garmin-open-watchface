import Toybox.Lang;
import Toybox.System;

//! Settings with theme colors resolved.
class Config extends ConfigBase {

    var bg as Number = 0x000000;
    var fg as Number = 0xFFFFFF;
    var fg2 as Number = 0xAAAAAA;
    var accent as Number = 0xFF5500;

    var cHourHand as Number = 0xFFFFFF;
    var cMinuteHand as Number = 0xFFFFFF;
    var cSecondHand as Number = 0xFF5500;
    var cHourTick as Number = 0xFFFFFF;
    var cMinuteTick as Number = 0xAAAAAA;
    var cNumeral as Number = 0xFFFFFF;
    var cHourDigits as Number = 0xFFFFFF;
    var cMinuteDigits as Number = 0xFFFFFF;
    var cField as Number = 0xFFFFFF;
    var cLabel as Number = 0xAAAAAA;
    //! Unlit segments/dots and gauge tracks: a third of the way from background to primary.
    var ghost as Number = 0x555555;

    var use24h as Boolean = true;

    function initialize() {
        ConfigBase.initialize();
    }

    function load() as Void {
        loadProperties();
        if (Theme > 0 && Theme < Themes.TABLE.size()) {
            var t = Themes.TABLE[Theme];
            bg = t[0];
            fg = t[1];
            fg2 = t[2];
            accent = t[3];
        } else {
            bg = BgColor;
            fg = PrimaryColor;
            fg2 = SecondaryColor;
            accent = AccentColor;
        }
        cHourHand = pick(HourHandColor, fg);
        cMinuteHand = pick(MinuteHandColor, fg);
        cSecondHand = pick(SecondHandColor, accent);
        cHourTick = pick(HourTickColor, fg);
        cMinuteTick = pick(MinuteTickColor, fg2);
        cNumeral = pick(NumeralColor, fg);
        cHourDigits = pick(HourDigitColor, fg);
        cMinuteDigits = pick(MinuteDigitColor, (Mode == 1 && DigitalLayout == 1) ? accent : fg);
        cField = pick(FieldColor, fg);
        cLabel = pick(LabelColor, fg2);
        ghost = pick(GhostColor, mix(bg, fg, 1, 3, true));

        if (HourFormat == 1) {
            use24h = false;
        } else if (HourFormat == 2) {
            use24h = true;
        } else {
            use24h = System.getDeviceSettings().is24Hour;
        }
    }

    //! Night dimming: move every color pct % toward the background (AOD color toward black).
    function fade(pct as Number, snap as Boolean) as Void {
        fg = mix(fg, bg, pct, 100, snap);
        fg2 = mix(fg2, bg, pct, 100, snap);
        accent = mix(accent, bg, pct, 100, snap);
        cHourHand = mix(cHourHand, bg, pct, 100, snap);
        cMinuteHand = mix(cMinuteHand, bg, pct, 100, snap);
        cSecondHand = mix(cSecondHand, bg, pct, 100, snap);
        cHourTick = mix(cHourTick, bg, pct, 100, snap);
        cMinuteTick = mix(cMinuteTick, bg, pct, 100, snap);
        cNumeral = mix(cNumeral, bg, pct, 100, snap);
        cHourDigits = mix(cHourDigits, bg, pct, 100, snap);
        cMinuteDigits = mix(cMinuteDigits, bg, pct, 100, snap);
        cField = mix(cField, bg, pct, 100, snap);
        cLabel = mix(cLabel, bg, pct, 100, snap);
        ghost = mix(ghost, bg, pct, 100, snap);
        AodColor = mix(AodColor, 0x000000, pct, 100, false);
    }

    //! Blend a toward b by num/den. With snap, each channel is rounded to the 64-color MIP levels
    //! (00, 55, AA, FF) so the result renders the same on MIP and AMOLED.
    static function mix(a as Number, b as Number, num as Number, den as Number, snap as Boolean) as Number {
        var out = 0;
        for (var shift = 16; shift >= 0; shift -= 8) {
            var ca = (a >> shift) & 0xFF;
            var cb = (b >> shift) & 0xFF;
            var c = ca + (cb - ca) * num / den;
            if (snap) {
                c = ((c + 42) / 85) * 85;
            }
            out |= (c > 255 ? 255 : c) << shift;
        }
        return out;
    }

    private function pick(v as Number, auto as Number) as Number {
        return (v < 0) ? auto : v;
    }
}
