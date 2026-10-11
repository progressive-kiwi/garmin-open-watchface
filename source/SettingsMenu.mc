import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! On-device settings, generated from Schema: groups > settings > options.
//! Only settings of the current watch face are listed.
class SettingsRootMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => Rez.Strings.AppName});
        var groups = Schema.groups();
        for (var i = 0; i < groups.size(); i++) {
            if (SettingsUtil.rowsForFace(groups[i][1] as Array<Array>).size() > 0) {
                addItem(new WatchUi.MenuItem(groups[i][0] as ResourceId, null, i, {}));
            }
        }
    }
}

class SettingsRootDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var gi = item.getId() as Number;
        var group = Schema.groups()[gi];
        var menu = new WatchUi.Menu2({:title => group[0] as ResourceId});
        var rows = SettingsUtil.rowsForFace(group[1] as Array<Array>);
        for (var i = 0; i < rows.size(); i++) {
            var key = rows[i][0] as String;
            var title = rows[i][1] as ResourceId;
            var e = rows[i][2] as Number;
            if (e < 0) {
                menu.addItem(new WatchUi.ToggleMenuItem(title, null, key, ConfigBase.readBool(key, false), {}));
            } else {
                menu.addItem(new WatchUi.MenuItem(title, SettingsUtil.currentLabel(key, e), key, {}));
            }
        }
        WatchUi.pushView(menu, new SettingsGroupDelegate(rows), WatchUi.SLIDE_LEFT);
    }
}

class SettingsGroupDelegate extends WatchUi.Menu2InputDelegate {
    private var _rows as Array<Array>;

    function initialize(rows as Array<Array>) {
        Menu2InputDelegate.initialize();
        _rows = rows;
    }

    function onSelect(item as MenuItem) as Void {
        var key = item.getId() as String;
        if (item instanceof WatchUi.ToggleMenuItem) {
            Properties.setValue(key, (item as ToggleMenuItem).isEnabled());
            SettingsUtil.changed();
            return;
        }
        var e = -1;
        for (var i = 0; i < _rows.size(); i++) {
            if (key.equals(_rows[i][0] as String)) {
                e = _rows[i][2] as Number;
            }
        }
        if (e < 0) {
            return;
        }
        var opts = Schema.options(e);
        var cur = ConfigBase.readNum(key, 0);
        var focus = 0;
        var menu = new WatchUi.Menu2({:title => item.getLabel()});
        for (var i = 0; i < opts.size(); i++) {
            if (opts[i][0] == cur) {
                focus = i;
            }
            menu.addItem(new WatchUi.MenuItem(opts[i][1] as ResourceId, null, i, {}));
        }
        menu.setFocus(focus);
        WatchUi.pushView(menu, new SettingsOptionDelegate(key, opts, item), WatchUi.SLIDE_LEFT);
    }
}

class SettingsOptionDelegate extends WatchUi.Menu2InputDelegate {
    private var _key as String;
    private var _opts as Array<Array>;
    private var _parent as MenuItem;

    function initialize(key as String, opts as Array<Array>, parent as MenuItem) {
        Menu2InputDelegate.initialize();
        _key = key;
        _opts = opts;
        _parent = parent;
    }

    function onSelect(item as MenuItem) as Void {
        var opt = _opts[item.getId() as Number];
        Properties.setValue(_key, opt[0] as Number);
        _parent.setSubLabel(opt[1] as ResourceId);
        SettingsUtil.changed();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

module SettingsUtil {
    //! Rows whose face mask includes the current watch face (Mode).
    function rowsForFace(rows as Array<Array>) as Array<Array> {
        var bit = 1 << ConfigBase.readNum("Mode", 0);
        var out = [] as Array<Array>;
        for (var i = 0; i < rows.size(); i++) {
            if (((rows[i][3] as Number) & bit) != 0) {
                out.add(rows[i]);
            }
        }
        return out;
    }

    function currentLabel(key as String, e as Number) as ResourceId? {
        var v = ConfigBase.readNum(key, 0);
        var opts = Schema.options(e);
        for (var i = 0; i < opts.size(); i++) {
            if (opts[i][0] == v) {
                return opts[i][1] as ResourceId;
            }
        }
        return null;
    }

    function changed() as Void {
        (Application.getApp() as OpenFaceApp).onSettingsChanged();
    }
}
