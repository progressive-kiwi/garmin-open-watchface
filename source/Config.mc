import Toybox.Lang;
import Toybox.System;

//! Settings with theme colors resolved.
class Config extends ConfigBase {
    // Theme table: [background, primary, secondary, accent]. Index = Theme value.
    private const THEMES = [
        [0x000000, 0xFFFFFF, 0xAAAAAA, 0xFF5500], // 0 custom (overwritten)
        [0x000000, 0xFFFFFF, 0xAAAAAA, 0xFF0000], // 1 classic
        [0x000000, 0xFFFFFF, 0xAAAAAA, 0xFF5500], // 2 racing
        [0x000055, 0xFFFFFF, 0x55AAAA, 0x00FFFF], // 3 ocean
        [0x000000, 0xFFFFAA, 0x00AA55, 0xAAFF00], // 4 forest
        [0x000000, 0xFFAA00, 0xAA5500, 0xFFFFAA], // 5 gold
        [0x000000, 0xFFFFFF, 0x55AAAA, 0x00AAFF], // 6 ice
        [0x000000, 0x00FFFF, 0xAA00FF, 0xFF00FF], // 7 neon
        [0xFFFFFF, 0x000000, 0x555555, 0xFF0000], // 8 paper
        [0x000000, 0xAAAAAA, 0x555555, 0xFFFFFF], // 9 stealth
        [0x000000, 0x00FF00, 0x00AA00, 0xFFAA00]  // 10 tactical
    ];

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

    var use24h as Boolean = true;

    function initialize() {
        ConfigBase.initialize();
    }

    function load() as Void {
        loadProperties();
        if (Theme > 0 && Theme < THEMES.size()) {
            var t = THEMES[Theme];
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

        if (HourFormat == 1) {
            use24h = false;
        } else if (HourFormat == 2) {
            use24h = true;
        } else {
            use24h = System.getDeviceSettings().is24Hour;
        }
    }

    private function pick(v as Number, auto as Number) as Number {
        return (v < 0) ? auto : v;
    }
}
