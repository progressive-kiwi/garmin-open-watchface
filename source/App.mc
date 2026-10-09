import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class OpenFaceApp extends Application.AppBase {
    private var _view as FaceView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new FaceView();
        _view = view;
        return [view, new FaceDelegate(view)];
    }

    //! On-device settings (Watch Face > Customize).
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var menu = new SettingsRootMenu();
        return [menu, new SettingsRootDelegate()];
    }

    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.reload();
        }
        WatchUi.requestUpdate();
    }
}
