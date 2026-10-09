import Toybox.Lang;
import Toybox.System;

//! Single time source, so documentation screenshots can pin the time (see tools/screenshots.py).
module Clock {
    function time() as ClockTime {
        return System.getClockTime();
    }
}
