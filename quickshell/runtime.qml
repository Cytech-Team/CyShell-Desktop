//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma AppId com.cytechteam.cyshell.runtime

import QtQuick
import Quickshell
import qs.Common
import qs.CyCommon.Common as DC
import qs.Services

ShellRoot {
    id: root

    readonly property var settingsOwner: SettingsData
    readonly property var themeOwner: Theme
    readonly property var pluginOwner: PluginService
    readonly property var sessionOwner: SessionData

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;

        // Force construction of the non-visual owners. Visible UI roles are
        // clients and may restart independently without respawning daemon work.
        void Theme.currentTheme;
        void PluginService.availablePluginsList;
    }
}
