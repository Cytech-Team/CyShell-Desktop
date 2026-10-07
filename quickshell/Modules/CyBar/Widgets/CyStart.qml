import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import qs.Modals.CyLauncherV2

PluginComponent {
    id: root

    layerNamespacePlugin: "cyshell-cystart"

    // Match the original Noctalia CyStart panel profile.
    popoutWidth: 760
    popoutHeight: 660
    popoutKeyboardFocus: CompositorService.useHyprlandFocusGrab ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    readonly property string backendPath: Quickshell.env("HOME") + "/.local/share/cytech/cystart/backend.py"

    property var apps: []
    property var pinnedIds: []
    property var pinnedApps: []
    property var recommendedApps: []
    property var allAppsSorted: []
    property var categories: []
    property string allSectionMode: "category"
    property bool pinnedExpanded: true
    property bool loading: true
    property string loadError: ""
    property int selectedIndex: 0
    property var actionApp: null

    function iconSource(app) {
        if (!app)
            return "";
        if (app.icon_path && app.icon_path.length > 0)
            return String(app.icon_path).startsWith("/") ? Paths.toFileUrl(String(app.icon_path)) : String(app.icon_path);
        const named = app.icon || "application-x-executable";
        return Quickshell.iconPath(named, true) || Quickshell.iconPath("application-x-executable", true) || "";
    }

    function isPinned(appId) {
        return root.pinnedIds.indexOf(appId) >= 0;
    }

    function dockAppId(app) {
        if (!app || !app.id)
            return "";

        let appId = String(app.id);
        if (Array.isArray(app.launch_args) && app.launch_args.length > 0 && appId.startsWith("launcher-")) {
            const safe = appId.replace(/[^A-Za-z0-9_-]/g, "-").replace(/^-+|-+$/g, "");
            appId = "cytech-cyshell-launcher-" + safe;
        }
        return Paths.moddedAppId(appId);
    }

    function isDockPinned(app) {
        const appId = root.dockAppId(app);
        return appId.length > 0 && (SessionData.barPinnedApps || []).indexOf(appId) >= 0;
    }

    function toggleDockPin(app) {
        const appId = root.dockAppId(app);
        if (!appId)
            return;

        if (root.isDockPinned(app)) {
            SessionData.removeBarPinnedApp(appId);
        } else {
            if (Array.isArray(app.launch_args) && app.launch_args.length > 0)
                Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.local/share/cytech/cyshell-bridge/sync_launchers.py"]);
            SessionData.addBarPinnedApp(appId);
        }
    }

    function desktopEntryFor(app) {
        if (!app || !app.id)
            return null;
        let appId = String(app.id);
        if (appId.endsWith(".desktop"))
            appId = appId.slice(0, -8);
        appId = Paths.moddedAppId(appId);
        return DesktopEntries.heuristicLookup(appId);
    }

    function desktopActionsFor(app) {
        const entry = root.desktopEntryFor(app);
        return entry && entry.actions ? entry.actions : [];
    }

    function showAppActions(app) {
        if (app && app.id)
            root.actionApp = app;
    }

    function launchDesktopActionFor(app, action) {
        const entry = root.desktopEntryFor(app);
        if (!entry || !action)
            return;
        root.closePopout();
        SessionService.launchDesktopAction(entry, action);
    }

    function launchAsAdmin(app) {
        if (!app)
            return;

        let command = [];
        if (Array.isArray(app.launch_args) && app.launch_args.length > 0) {
            command = app.launch_args.slice();
        } else {
            const entry = root.desktopEntryFor(app);
            if (entry && entry.command)
                command = Array.from(entry.command);
        }

        if (command.length === 0)
            return;

        const args = ["pkexec", "env"];
        const envNames = [
            "WAYLAND_DISPLAY",
            "DISPLAY",
            "XDG_RUNTIME_DIR",
            "DBUS_SESSION_BUS_ADDRESS",
            "XAUTHORITY",
            "XDG_CURRENT_DESKTOP",
            "XDG_SESSION_TYPE"
        ];
        for (let i = 0; i < envNames.length; ++i) {
            const value = Quickshell.env(envNames[i]);
            if (value)
                args.push(envNames[i] + "=" + value);
        }
        for (let i = 0; i < command.length; ++i)
            args.push(String(command[i]));

        root.closePopout();
        SessionService.launchDetachedApp(args, Quickshell.env("HOME"), {});
    }

    function categoryInfo(categoryId) {
        const id = String(categoryId || "");
        for (let i = 0; i < root.categories.length; ++i) {
            if (String(root.categories[i].id) === id)
                return root.categories[i];
        }
        return null;
    }

    function categoryApps(categoryId) {
        const cat = root.categoryInfo(categoryId);
        return cat && Array.isArray(cat.apps) ? cat.apps : [];
    }

    function categoryTitle(categoryId) {
        const cat = root.categoryInfo(categoryId);
        return cat ? String(cat.title || cat.id) : String(categoryId || "All apps");
    }

    function appPreviewFromLauncherItem(item) {
        if (!item || item.type !== "app")
            return null;

        const data = item.data && typeof item.data === "object" ? item.data : {};
        return {
            id: data.id || item.id || "",
            name: item.name || data.name || "",
            generic: data.genericName || data.generic || item.subtitle || "",
            comment: data.comment || data.description || item.subtitle || "",
            icon: item.icon || data.icon || "",
            iconType: item.iconType || data.iconType || "image",
            icon_path: data.icon_path || data.iconPath || "",
            categories: data.categories || item.categories || [],
            provider: item.source || data.provider || data.source || "",
            source: item.source || data.source || "",
            install_path: data.filename || data.filePath || data.install_path || ""
        };
    }

    function appDescription(app) {
        if (!app)
            return "";
        const entry = root.desktopEntryFor(app);
        return String(app.comment || app.description || entry?.comment || "").trim();
    }

    function appGenericName(app) {
        if (!app)
            return "";
        const entry = root.desktopEntryFor(app);
        return String(app.generic || app.genericName || entry?.genericName || "").trim();
    }

    function launcherItemIconValue(item) {
        if (!item)
            return "";
        const value = String(item.icon || item.iconFull || "");
        switch (String(item.iconType || "image")) {
        case "material":
        case "nerd":
            return "material:" + (value || "apps");
        case "unicode":
            return "unicode:" + value;
        case "composite":
            return String(item.iconFull || "");
        default:
            return value;
        }
    }

    function rebuildDerived() {
        const map = {};
        for (let i = 0; i < root.apps.length; ++i)
            map[root.apps[i].id] = root.apps[i];

        const pins = [];
        for (let i = 0; i < root.pinnedIds.length; ++i) {
            const app = map[root.pinnedIds[i]];
            if (app)
                pins.push(app);
        }

        if (pins.length === 0) {
            const fallback = root.apps.slice().sort((a, b) => {
                const au = Number(a.usage || 0);
                const bu = Number(b.usage || 0);
                if (au !== bu)
                    return bu - au;
                return String(a.name || "").localeCompare(String(b.name || ""));
            });
            for (let i = 0; i < Math.min(16, fallback.length); ++i)
                pins.push(fallback[i]);
        }
        root.pinnedApps = pins.slice(0, 32);

        const rec = root.apps.filter(app =>
            Number(app.recent_rank ?? 99999) < 99999 || Number(app.usage || 0) > 0
        );
        rec.sort((a, b) => {
            const ar = Number(a.recent_rank ?? 99999);
            const br = Number(b.recent_rank ?? 99999);
            if (ar !== br)
                return ar - br;
            const au = Number(a.usage || 0);
            const bu = Number(b.usage || 0);
            if (au !== bu)
                return bu - au;
            return String(a.name || "").localeCompare(String(b.name || ""));
        });
        root.recommendedApps = rec.slice(0, 6);

        const ordered = root.apps.slice();
        ordered.sort((a, b) => String(a.name || "").toLowerCase().localeCompare(String(b.name || "").toLowerCase()));
        root.allAppsSorted = ordered;

        // Same XDG category model used by the original Noctalia CyStart.
        const defs = [
            ["Network", "Network"], ["Development", "Development"],
            ["Game", "Games"], ["AudioVideo", "Audio & Video"],
            ["Graphics", "Graphics"], ["Office", "Office"],
            ["Education", "Education"], ["Science", "Science"],
            ["Settings", "Settings"], ["System", "System"],
            ["Utility", "Utilities"]
        ];
        const cats = defs.map(d => ({ id: d[0], title: d[1], apps: [] }));
        const other = { id: "Other", title: "Other", apps: [] };
        for (let i = 0; i < ordered.length; ++i) {
            const app = ordered[i];
            const tags = String(app.categories || "").split(";").filter(Boolean);
            let target = null;
            for (let j = 0; j < cats.length && !target; ++j)
                if (tags.indexOf(cats[j].id) >= 0) target = cats[j];
            (target || other).apps.push(app);
        }
        root.categories = cats.filter(c => c.apps.length > 0);
        if (other.apps.length > 0) root.categories.push(other);
    }

    function consumePayload(raw) {
        try {
            const payload = JSON.parse(raw);
            root.apps = Array.isArray(payload.apps) ? payload.apps : [];
            root.pinnedIds = Array.isArray(payload.pinned_ids) ? payload.pinned_ids : [];
            root.allSectionMode = payload.all_mode === "grid" ? "grid" : "category";
            root.pinnedExpanded = payload.pinned_expanded !== false;
            root.loadError = "";
            root.rebuildDerived();
        } catch (e) {
            root.loadError = "Could not parse CyStart app index: " + e;
        }
        root.loading = false;
    }

    function refresh() {
        if (appLoader.running)
            return;
        root.loading = true;
        root.loadError = "";
        appLoader.running = true;
    }

    function searchApps(query) {
        const q = String(query || "").trim().toLowerCase();
        if (!q)
            return [];

        const scored = [];
        for (let i = 0; i < root.apps.length; ++i) {
            const app = root.apps[i];
            const name = String(app.name || "").toLowerCase();
            const generic = String(app.generic || "").toLowerCase();
            const comment = String(app.comment || "").toLowerCase();
            const provider = String(app.provider || "").toLowerCase();
            let score = 999;

            if (name === q)
                score = 0;
            else if (name.startsWith(q))
                score = 1;
            else if (name.indexOf(q) >= 0)
                score = 2;
            else if (generic.indexOf(q) >= 0)
                score = 3;
            else if (comment.indexOf(q) >= 0)
                score = 4;
            else if (provider.indexOf(q) >= 0)
                score = 5;

            if (score < 999) {
                scored.push({
                    app: app,
                    score: score,
                    usage: Number(app.usage || 0),
                    recent: Number(app.recent_rank ?? 99999)
                });
            }
        }

        scored.sort((a, b) => {
            if (a.score !== b.score)
                return a.score - b.score;
            if (a.recent !== b.recent)
                return a.recent - b.recent;
            if (a.usage !== b.usage)
                return b.usage - a.usage;
            return String(a.app.name || "").localeCompare(String(b.app.name || ""));
        });

        return scored.slice(0, 50).map(row => row.app);
    }

    function launchApp(app) {
        if (!app || !app.id)
            return;

        root.closePopout();
        const entry = root.desktopEntryFor(app);
        if (entry) {
            SessionService.launchDesktopEntry(entry);
            AppUsageHistoryData.addAppUsage(entry);
            return;
        }

        // CyStart also indexes custom launchers/games that are not desktop
        // entries. Keep the shared backend as a fallback; it launches those in
        // their own systemd app scope as well.
        Quickshell.execDetached(["python3", root.backendPath, "launch", String(app.id)]);
    }

    function togglePin(app) {
        if (!app || !app.id)
            return;
        Quickshell.execDetached(["python3", root.backendPath, "toggle-pin", String(app.id)]);
        pinRefreshTimer.restart();
    }

    function reorderPinned(appId, targetIndex) {
        if (!appId || targetIndex < 0)
            return;
        Quickshell.execDetached(["python3", root.backendPath, "reorder-pin", String(appId), String(targetIndex)]);
        pinRefreshTimer.restart();
    }


    function setAllMode(mode) {
        if (mode !== "category" && mode !== "grid")
            return;
        root.allSectionMode = mode;
        Quickshell.execDetached(["python3", root.backendPath, "set-all-mode", mode]);
    }

    function setPinnedExpanded(expanded) {
        root.pinnedExpanded = expanded;
        Quickshell.execDetached(["python3", root.backendPath, "set-pinned-expanded", expanded ? "true" : "false"]);
    }

    function openDevices() {
        root.closePopout();
        Quickshell.execDetached(["cyshell", "ipc", "call", "control-center", "toggle"]);
    }

    function openUserSettings() {
        root.closePopout();
        Quickshell.execDetached(["cyshell", "ipc", "call", "settings", "openWith", "users"]);
    }

    function lockSession() {
        root.closePopout();
        Quickshell.execDetached(["cyshell", "ipc", "call", "lock", "lock"]);
    }

    function signOut() {
        root.closePopout();
        SessionService.logout();
    }

    function suspendSession() {
        root.closePopout();
        SessionService.suspend();
    }

    function rebootSystem() {
        root.closePopout();
        SessionService.reboot();
    }

    function powerOffSystem() {
        root.closePopout();
        SessionService.poweroff();
    }

    function webSearch(query) {
        const q = String(query || "").trim();
        if (!q)
            return;
        root.closePopout();
        SessionService.launchDetachedApp(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(q)], Quickshell.env("HOME"), {});
    }

    function openSettings() {
        root.closePopout();
        Quickshell.execDetached(["cyshell", "ipc", "call", "settings", "toggle"]);
    }

    function openPowerMenu() {
        root.closePopout();
        Quickshell.execDetached(["cyshell", "ipc", "call", "powermenu", "toggle"]);
    }

    function openPath(path) {
        root.closePopout();
        SessionService.launchDetachedApp(["xdg-open", path], Quickshell.env("HOME"), {});
    }

    function openAppLocation(app) {
        if (!app)
            return;
        let path = String(app.install_path || app.source || "");
        if (!path)
            return;
        if (path.indexOf("/") >= 0 && !path.endsWith("/")) {
            const slash = path.lastIndexOf("/");
            if (slash > 0)
                path = path.slice(0, slash);
        }
        root.openPath(path);
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: pinRefreshTimer
        interval: 220
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: appLoader
        command: ["python3", root.backendPath, "dump"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.consumePayload(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg.length > 0)
                    root.loadError = msg;
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                if (!root.loadError)
                    root.loadError = "CyStart backend exited with code " + exitCode;
            }
        }
    }

    IpcHandler {
        target: "cyStart"

        function toggle(): string {
            // IPC targets are duplicated across per-screen widget instances.
            // Route the shortcut through BarWidgetService so the popout opens
            // from the best compositor-derived screen.
            const opened = BarWidgetService.triggerWidgetPopout("cyStart");
            return opened ? "toggled" : "unavailable";
        }

        function toggleFor(screenName: string): string {
            const target = String(screenName || "").trim();
            if (!target)
                return toggle();
            CompositorService.noteScreenInteraction(target);
            const opened = BarWidgetService.triggerWidgetPopout("cyStart", {
                screenName: target,
                kind: "bar"
            });
            return opened ? ("toggled:" + target) : ("unavailable:" + target);
        }

        function close(): string {
            root.closePopout();
            return "closed";
        }

        function refresh(): string {
            root.refresh();
            return "refreshing";
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: 26
            implicitHeight: 32

            SystemLogo {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: Theme.spacingXS / 2
                width: 22
                height: 22
            }
        }
    }

    verticalBarPill: horizontalBarPill

    popoutContent: Component {
        Item {
            id: menu
            implicitWidth: root.popoutWidth - Theme.spacingS * 2
            implicitHeight: root.popoutHeight - Theme.spacingS * 2

            property var parentPopout: null
            property bool allAppsMode: false
            property string categoryFilter: ""
            property bool accountOpen: false
            property bool powerOpen: false
            property var previewApp: null
            property var previewItem: null
            property bool showAllAppsInSearch: false
            property bool searchModeExplicit: false
            property var shownApps: categoryFilter.length > 0 ? root.categoryApps(categoryFilter) : root.allAppsSorted
            readonly property bool searchActive: searchField.text.trim().length > 0
            readonly property bool searchViewActive: searchActive || showAllAppsInSearch
            property bool searchSessionStarted: false

            Controller {
                id: unifiedSearchController
                active: menu.parentPopout?.shouldBeVisible === true
                viewModeContext: "spotlight"
                forceLinearNavigation: true
                sortSearchResultsAlphabetically: true
                onItemExecuted: root.closePopout()
                onSelectedItemChanged: {
                    if (menu.searchViewActive) {
                        menu.previewItem = selectedItem;
                        menu.previewApp = root.appPreviewFromLauncherItem(selectedItem);
                        unifiedContextMenu.prepareForInline(selectedItem);
                    }
                }
                onSearchQueryRequested: query => {
                    searchField.text = String(query || "");
                    searchField.cursorPosition = searchField.text.length;
                    searchField.forceActiveFocus();
                }
            }

            LauncherContextMenu {
                id: unifiedContextMenu
                parent: menu
                controller: unifiedSearchController
                searchField: searchField
                parentHandler: menu
                allowEditActions: false
            }

            Timer {
                id: searchFocusTimer
                interval: 80
                repeat: false
                onTriggered: {
                    if (menu.parentPopout && menu.parentPopout.shouldBeVisible) {
                        searchField.forceActiveFocus();
                    }
                }
            }

            Connections {
                target: menu.parentPopout
                function onShouldBeVisibleChanged() {
                    if (menu.parentPopout && menu.parentPopout.shouldBeVisible) {
                        menu.allAppsMode = false;
                        menu.categoryFilter = "";
                        menu.accountOpen = false;
                        menu.powerOpen = false;
                        menu.showAllAppsInSearch = false;
                        menu.searchModeExplicit = false;
                        menu.previewApp = null;
                        menu.previewItem = null;
                        root.selectedIndex = 0;
                        menu.searchSessionStarted = false;
                        searchField.text = "";
                        Qt.callLater(() => {
                            searchField.forceActiveFocus();
                            searchFocusTimer.restart();
                        });
                    } else {
                        searchFocusTimer.stop();
                        menu.showAllAppsInSearch = false;
                        menu.searchModeExplicit = false;
                        menu.searchSessionStarted = false;
                        unifiedContextMenu.hide();
                        unifiedSearchController.reset();
                        searchField.text = "";
                        menu.accountOpen = false;
                        menu.powerOpen = false;
                        menu.previewApp = null;
                        menu.previewItem = null;
                        root.actionApp = null;
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Rectangle {
                    id: searchShell
                    width: parent.width
                    height: 44
                    radius: 10
                    color: Theme.withAlpha(Theme.surfaceVariant, 0.16)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.12)

                    CyTextField {
                    id: searchField
                    anchors.left: parent.left
                    anchors.right: deviceButton.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 4
                    leftIconName: "search"
                    leftIconSize: Theme.iconSize
                    leftIconColor: Theme.surfaceVariantText
                    leftIconFocusedColor: Theme.primary
                    showClearButton: false
                    backgroundColor: Theme.withAlpha(Theme.surface, 0)
                    normalBorderColor: Theme.withAlpha(Theme.outline, 0)
                    focusedBorderColor: Theme.withAlpha(Theme.primary, 0)
                    borderWidth: 0
                    focusedBorderWidth: 0
                    cornerRadius: 0
                    textColor: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    placeholderText: "Search for apps, settings, and documents"
                    hidePlaceholderOnFocus: false
                    ignoreUpDownKeys: true
                    activeFocusOnTab: true

                    onTextChanged: {
                        root.selectedIndex = 0;
                        unifiedActionPanel.hide();
                        unifiedContextMenu.hide();
                        const query = text.trim();
                        if (query.length > 0) {
                            const wasBrowsingAllApps = menu.showAllAppsInSearch;
                            menu.showAllAppsInSearch = false;
                            menu.previewApp = null;
                            menu.previewItem = null;
                            if (!menu.searchSessionStarted) {
                                menu.searchSessionStarted = true;
                                const mode = menu.searchModeExplicit
                                    ? unifiedSearchController.searchMode
                                    : (wasBrowsingAllApps ? "all" : (unifiedSearchController.searchMode || "all"));
                                unifiedSearchController.openSession(text, true, mode, false);
                            } else {
                                unifiedSearchController.setSearchQuery(text);
                            }
                        } else {
                            const returnToAllApps = menu.searchSessionStarted;
                            menu.searchSessionStarted = false;
                            menu.previewApp = null;
                            menu.previewItem = null;
                            if (returnToAllApps && menu.parentPopout?.shouldBeVisible) {
                                menu.showAllAppsInSearch = true;
                                menu.searchModeExplicit = false;
                                menu.allAppsMode = false;
                                menu.categoryFilter = "";
                                unifiedSearchController.openSession("", false, "apps", true);
                            } else if (!menu.parentPopout?.shouldBeVisible) {
                                menu.showAllAppsInSearch = false;
                            }
                        }
                    }

                    Keys.onPressed: event => {
                        if (!menu.searchViewActive)
                            return;
                        const hasCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        if (event.key === Qt.Key_Down) {
                            unifiedSearchController.selectNext();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            unifiedSearchController.selectPrevious();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageDown) {
                            unifiedSearchController.selectPageDown(8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            unifiedSearchController.selectPageUp(8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab && hasCtrl) {
                            unifiedSearchController.cycleMode(false);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab && hasCtrl) {
                            unifiedSearchController.cycleMode(true);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab && unifiedActionPanel.hasActions) {
                            if (!unifiedActionPanel.expanded) {
                                unifiedActionPanel.expanded = true;
                                unifiedActionPanel.selectedActionIndex = 0;
                            } else {
                                unifiedActionPanel.cycleAction(false);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (unifiedActionPanel.expanded)
                                unifiedActionPanel.executeSelectedAction();
                            else
                                unifiedSearchController.executeSelected();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Menu || event.key === Qt.Key_F10) {
                            if (unifiedSearchController.selectedItem?.type === "app") {
                                menu.previewItem = unifiedSearchController.selectedItem;
                                menu.previewApp = root.appPreviewFromLauncherItem(unifiedSearchController.selectedItem);
                                unifiedContextMenu.prepareForInline(unifiedSearchController.selectedItem);
                            } else if (unifiedContextMenu.hasContextMenuActions(unifiedSearchController.selectedItem)) {
                                const pos = unifiedResults.getSelectedItemPosition();
                                const local = menu.mapFromItem(null, pos.x, pos.y);
                                unifiedContextMenu.show(local.x, local.y, unifiedSearchController.selectedItem, true);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            searchField.text = "";
                            event.accepted = true;
                        }
                    }
                    }

                    Rectangle {
                        id: deviceButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 6
                        width: 32
                        height: 32
                        radius: 9
                        color: deviceMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                        CyIcon { anchors.centerIn: parent; name: "smartphone"; size: 18; color: Theme.surfaceVariantText }
                        MouseArea {
                            id: deviceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openDevices()
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: parent.height - searchShell.height - footer.height - 20

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.loading
                        visible: root.loading
                    }

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Theme.spacingL * 2, 540)
                        spacing: Theme.spacingM
                        visible: !root.loading && root.loadError.length > 0

                        CyIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "error"
                            size: 34
                            color: Theme.primary
                        }

                        StyledText {
                            width: parent.width
                            text: root.loadError
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }

                    Item {
                        id: unifiedSearchPane
                        anchors.fill: parent
                        visible: !root.loading && root.loadError.length === 0 && menu.searchViewActive

                        Column {
                            anchors.fill: parent
                            spacing: 8

                            Row {
                                id: modeRow
                                spacing: 6
                                height: 32

                                Repeater {
                                    model: [
                                        { id: "all", label: "All", icon: "search" },
                                        { id: "apps", label: "Apps", icon: "apps" },
                                        { id: "files", label: "Files", icon: "folder" },
                                        { id: "plugins", label: "More", icon: "extension" }
                                    ]

                                    delegate: Rectangle {
                                        required property var modelData
                                        width: modeLabel.implicitWidth + 28
                                        height: 30
                                        radius: 9
                                        color: unifiedSearchController.searchMode === modelData.id
                                            ? Theme.withAlpha(Theme.primary, 0.16)
                                            : (modeMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent")
                                        border.width: unifiedSearchController.searchMode === modelData.id ? 1 : 0
                                        border.color: Theme.withAlpha(Theme.primary, 0.28)

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 5
                                            CyIcon { name: modelData.icon; size: 15; color: unifiedSearchController.searchMode === modelData.id ? Theme.primary : Theme.surfaceVariantText }
                                            StyledText { id: modeLabel; text: modelData.label; font.pixelSize: 11; color: Theme.surfaceText }
                                        }

                                        MouseArea {
                                            id: modeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                unifiedActionPanel.hide();
                                                menu.searchModeExplicit = true;
                                                unifiedSearchController.setMode(modelData.id);
                                                searchField.forceActiveFocus();
                                            }
                                        }
                                    }
                                }

                                Item { width: 1; height: 1; Layout.fillWidth: true }
                            }

                            Item {
                                width: parent.width
                                height: parent.height - modeRow.height - Theme.spacingS

                                Row {
                                    id: searchContentRow
                                    anchors.fill: parent
                                    readonly property bool showAppPreview: menu.previewItem?.type === "app"
                                    spacing: showAppPreview ? Theme.spacingM : 0

                                    Item {
                                        id: searchResultsColumn
                                        width: searchContentRow.showAppPreview
                                            ? Math.round((searchContentRow.width - searchContentRow.spacing * 2 - previewDivider.width) * 0.48)
                                            : searchContentRow.width
                                        height: parent.height

                                        ResultsList {
                                            id: unifiedResults
                                            anchors.fill: parent
                                            controller: unifiedSearchController
                                            clickSelectsOnly: false
                                            focusReturnTarget: searchField
                                            keyForwardTargets: [searchField]
                                            onItemHovered: item => {
                                                menu.previewItem = item;
                                                menu.previewApp = root.appPreviewFromLauncherItem(item);
                                                unifiedContextMenu.prepareForInline(item);
                                            }
                                            onItemRightClicked: (index, item, mouseX, mouseY) => {
                                                unifiedSearchController.selectedFlatIndex = index;
                                                unifiedSearchController.updateSelectedItem();
                                                if (item?.type === "app")
                                                    return;
                                                if (!unifiedContextMenu.hasContextMenuActions(item))
                                                    return;
                                                const pos = unifiedResults.mapToItem(menu, mouseX, mouseY);
                                                unifiedContextMenu.show(pos.x, pos.y, item, false);
                                            }
                                        }

                                        BusyIndicator {
                                            anchors.centerIn: parent
                                            running: unifiedSearchController.isSearching && unifiedSearchController.flatModel.length === 0
                                            visible: running
                                        }
                                    }

                                    Rectangle {
                                        id: previewDivider
                                        width: searchContentRow.showAppPreview ? Theme.outlineWidth : 0
                                        height: parent.height
                                        color: Theme.outlineMedium
                                        visible: searchContentRow.showAppPreview
                                    }

                                    Rectangle {
                                        id: appPreviewPane
                                        width: searchContentRow.showAppPreview
                                            ? parent.width - searchResultsColumn.width - previewDivider.width - searchContentRow.spacing * 2
                                            : 0
                                        height: parent.height
                                        radius: Theme.cornerRadiusL
                                        color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(menu))
                                        visible: searchContentRow.showAppPreview

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingM
                                            spacing: Theme.spacingM

                                            Column {
                                                width: parent.width
                                                spacing: Theme.spacingXS
                                                visible: menu.previewItem !== null

                                                Item {
                                                    width: parent.width
                                                    height: Theme.listItemTwoLineHeight + Theme.spacingS

                                                    AppIconRenderer {
                                                        anchors.centerIn: parent
                                                        width: Theme.listItemTwoLineHeight
                                                        height: Theme.listItemTwoLineHeight
                                                        iconSize: Theme.listItemTwoLineHeight
                                                        iconValue: root.launcherItemIconValue(menu.previewItem)
                                                        fallbackText: String(menu.previewItem?.name || "?").charAt(0).toUpperCase()
                                                        fallbackBackgroundColor: Theme.primaryContainer
                                                        fallbackTextColor: Theme.onPrimaryContainer
                                                        iconColor: Theme.surfaceText
                                                        fallbackRadius: Theme.cornerRadiusL
                                                    }
                                                }

                                                StyledText {
                                                    width: parent.width
                                                    text: menu.previewItem?.name || ""
                                                    color: Theme.surfaceText
                                                    font.pixelSize: Theme.fontSizeLarge
                                                    font.weight: Theme.fontWeightMedium
                                                    horizontalAlignment: Text.AlignHCenter
                                                    wrapMode: Text.Wrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    width: parent.width
                                                    text: menu.previewItem?.type === "app" ? I18n.tr("App") : (menu.previewItem?.type || "")
                                                    color: Theme.surfaceVariantText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                StyledText {
                                                    width: parent.width
                                                    text: {
                                                        if (!menu.previewItem)
                                                            return "";
                                                        const app = menu.previewApp;
                                                        return root.appGenericName(app) || root.appDescription(app) || String(menu.previewItem.subtitle || "");
                                                    }
                                                    color: Theme.surfaceVariantText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    horizontalAlignment: Text.AlignHCenter
                                                    wrapMode: Text.Wrap
                                                    maximumLineCount: 3
                                                    elide: Text.ElideRight
                                                    visible: text.length > 0
                                                }
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: Theme.outlineWidth
                                                color: Theme.outlineMedium
                                            }

                                                Column {
                                                    width: parent.width
                                                    spacing: Theme.spacingXS

                                                Repeater {
                                                    model: unifiedContextMenu.menuItems

                                                    delegate: Item {
                                                        required property var modelData
                                                        required property int index
                                                        width: parent.width
                                                        height: modelData?.type === "separator" ? Theme.spacingXS * 2 + Theme.outlineWidth : Theme.buttonHeightS
                                                        visible: menu.previewItem?.type === "app"

                                                        Rectangle {
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            height: Theme.outlineWidth
                                                            color: Theme.outlineMedium
                                                            visible: modelData?.type === "separator"
                                                        }

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: Theme.cornerRadiusM
                                                            color: previewActionMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                                            visible: modelData?.type === "item"

                                                            Row {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: Theme.spacingS
                                                                anchors.rightMargin: Theme.spacingS
                                                                spacing: Theme.spacingS

                                                                CyIcon {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    name: modelData?.icon || "open_in_new"
                                                                    size: Theme.iconSizeSmall
                                                                    color: modelData?.isDestructive ? Theme.error : Theme.surfaceVariantText
                                                                }

                                                                StyledText {
                                                                    width: parent.width - Theme.iconSizeSmall - Theme.spacingS
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: modelData?.text || ""
                                                                    color: modelData?.isDestructive ? Theme.error : Theme.surfaceText
                                                                    font.pixelSize: Theme.fontSizeSmall
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: previewActionMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            enabled: modelData?.type === "item"
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                const action = modelData?.action;
                                                                if (typeof action === "function")
                                                                    action();
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ActionPanel {
                            id: unifiedActionPanel
                            width: 0
                            height: 0
                            visible: false
                            selectedItem: menu.previewItem?.type === "app" ? menu.previewItem : null
                            controller: unifiedSearchController
                        }
                    }

                    Item {
                        id: allAppsPage
                        anchors.fill: parent
                        visible: !root.loading && root.loadError.length === 0
                            && !menu.searchViewActive && menu.allAppsMode

                        RowLayout {
                            id: pageHeader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 38
                            spacing: 8

                            Rectangle {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: 9
                                color: backMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                CyIcon {
                                    anchors.centerIn: parent
                                    name: "arrow_back"
                                    size: 18
                                    color: Theme.surfaceText
                                }
                                MouseArea {
                                    id: backMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        menu.allAppsMode = false;
                                        menu.categoryFilter = "";
                                        searchField.text = "";
                                        root.selectedIndex = 0;
                                        Qt.callLater(() => {
                                            homeFlick.contentY = 0;
                                            searchField.forceActiveFocus();
                                        });
                                    }
                                }
                            }

                            StyledText {
                                text: menu.categoryFilter.length > 0
                                    ? root.categoryTitle(menu.categoryFilter)
                                    : "All apps"
                                color: Theme.surfaceText
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: menu.shownApps.length + " apps"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 11
                            }
                        }

                        ListView {
                            id: allAppsList
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: pageHeader.bottom
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 8
                            clip: true
                            spacing: 3
                            model: menu.shownApps

                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                property var app: modelData
                                width: allAppsList.width
                                height: 44
                                radius: 10
                                color: appRowMouse.containsMouse
                                    ? Theme.withAlpha(Theme.surfaceVariant, 0.22)
                                    : Theme.withAlpha(Theme.surface, 0.01)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 10

                                    Item {
                                        width: 30
                                        height: 30
                                        anchors.verticalCenter: parent.verticalCenter
                                        IconImage {
                                            anchors.fill: parent
                                            source: root.iconSource(app)
                                            visible: source.toString().length > 0
                                        }
                                        CyIcon {
                                            anchors.centerIn: parent
                                            visible: root.iconSource(app).length === 0
                                            name: "apps"
                                            size: 23
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 48
                                        spacing: 1
                                        StyledText {
                                            width: parent.width
                                            text: app.name || app.id
                                            color: Theme.surfaceText
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            width: parent.width
                                            text: app.generic || app.comment || ""
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: appRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton)
                                            root.showAppActions(app);
                                        else
                                            root.launchApp(app);
                                    }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                visible: menu.shownApps.length === 0
                                spacing: 8
                                CyIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: "search"
                                    size: 26
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No apps found"
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }

                    Flickable {
                        id: homeFlick
                        anchors.fill: parent
                        visible: !root.loading && root.loadError.length === 0
                            && !menu.searchViewActive && !menu.allAppsMode
                        clip: true
                        contentWidth: width
                        contentHeight: homeColumn.implicitHeight + 12

                        Column {
                            id: homeColumn
                            x: 8
                            y: 6
                            width: homeFlick.width - 16
                            spacing: 12

                            Column {
                                width: parent.width
                                spacing: 6

                                RowLayout {
                                    width: parent.width
                                    height: 28

                                    StyledText {
                                        text: "Pinned"
                                        color: Theme.surfaceText
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        implicitWidth: 86
                                        implicitHeight: 28
                                        radius: 10
                                        color: pinnedToggleMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.surface, 0.01)
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root.pinnedExpanded ? "Show less" : "Show all"
                                                color: Theme.surfaceText
                                                font.pixelSize: 11
                                            }
                                            CyIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: "chevron_right"
                                                size: 14
                                                color: Theme.surfaceVariantText
                                            }
                                        }
                                        MouseArea {
                                            id: pinnedToggleMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setPinnedExpanded(!root.pinnedExpanded)
                                        }
                                    }
                                }

                                GridLayout {
                                    id: pinnedLayout
                                    width: parent.width
                                    columns: 8
                                    columnSpacing: 12
                                    rowSpacing: 6

                                    Repeater {
                                        model: root.pinnedApps.slice(0, root.pinnedExpanded ? Math.min(32, root.pinnedApps.length) : Math.min(8, root.pinnedApps.length))

                                        delegate: Rectangle {
                                            id: pinCard
                                            required property var modelData
                                            required property int index
                                            property var app: modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 78
                                            Drag.active: pinDragHandler.active
                                            Drag.source: pinCard
                                            Drag.keys: ["cystart-pinned-app"]
                                            Drag.hotSpot.x: width / 2
                                            Drag.hotSpot.y: height / 2
                                            radius: 12
                                            color: pinMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : Theme.withAlpha(Theme.surface, 0.01)
                                            border.width: 1
                                            border.color: pinMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.34) : Theme.withAlpha(Theme.surface, 0.01)

                                            Column {
                                                anchors.centerIn: parent
                                                width: parent.width - 8
                                                spacing: 6

                                                Item {
                                                    width: 30
                                                    height: 30
                                                    anchors.horizontalCenter: parent.horizontalCenter

                                                    IconImage {
                                                        anchors.fill: parent
                                                        source: root.iconSource(app)
                                                        visible: source.toString().length > 0
                                                    }
                                                    CyIcon {
                                                        anchors.centerIn: parent
                                                        visible: root.iconSource(app).length === 0
                                                        name: "apps"
                                                        size: 24
                                                        color: Theme.surfaceVariantText
                                                    }
                                                }

                                                StyledText {
                                                    width: parent.width
                                                    text: app.name || app.id
                                                    color: Theme.surfaceText
                                                    font.pixelSize: 11
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            DropArea {
                                                anchors.fill: parent
                                                keys: ["cystart-pinned-app"]
                                                onDropped: drop => {
                                                    if (drop.source && drop.source.app)
                                                        root.reorderPinned(drop.source.app.id, pinCard.index);
                                                }
                                            }

                                            DragHandler {
                                                id: pinDragHandler
                                                target: null
                                                acceptedButtons: Qt.LeftButton
                                            }

                                            MouseArea {
                                                id: pinMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton)
                                                        root.showAppActions(app);
                                                    else
                                                        root.launchApp(app);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 6
                                visible: root.recommendedApps.length > 0

                                RowLayout {
                                    width: parent.width
                                    height: 28
                                    StyledText {
                                        text: "Recommended"
                                        color: Theme.surfaceText
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                }

                                GridLayout {
                                    id: recommendedLayout
                                    width: parent.width
                                    columns: 3
                                    columnSpacing: 12
                                    rowSpacing: 6

                                    Repeater {
                                        model: root.recommendedApps.slice(0, 6)

                                        delegate: Rectangle {
                                            required property var modelData
                                            property var app: modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 44
                                            radius: 12
                                            color: recMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceVariant, 0.10)
                                            border.width: 1
                                            border.color: recMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.42) : Theme.withAlpha(Theme.surface, 0.01)

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                anchors.topMargin: 4
                                                anchors.bottomMargin: 4
                                                spacing: 7

                                                Item {
                                                    width: 28
                                                    height: 28
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    IconImage {
                                                        anchors.fill: parent
                                                        source: root.iconSource(app)
                                                        visible: source.toString().length > 0
                                                    }
                                                    CyIcon {
                                                        anchors.centerIn: parent
                                                        visible: root.iconSource(app).length === 0
                                                        name: "apps"
                                                        size: 22
                                                        color: Theme.surfaceVariantText
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 41
                                                    spacing: 1
                                                    StyledText {
                                                        width: parent.width
                                                        text: app.name || app.id
                                                        color: Theme.surfaceText
                                                        font.pixelSize: 12
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        width: parent.width
                                                        text: Number(app.usage || 0) > 1 ? String(app.usage) + " launches" : "Recently used"
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: recMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton)
                                                        root.showAppActions(app);
                                                    else
                                                        root.launchApp(app);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 7

                                RowLayout {
                                    width: parent.width
                                    height: 32
                                    spacing: 6

                                    StyledText {
                                        text: "All"
                                        color: Theme.surfaceText
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    StyledText {
                                        text: root.apps.length + " apps"
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: 9
                                    }
                                    Rectangle {
                                        implicitWidth: 86
                                        implicitHeight: 28
                                        radius: 9
                                        color: root.allSectionMode === "category" ? Theme.withAlpha(Theme.primary, 0.12)
                                            : categoryModeMouse.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surface, 0.01)
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            CyIcon { anchors.verticalCenter: parent.verticalCenter; name: "category"; size: 15; color: root.allSectionMode === "category" ? Theme.surfaceText : Theme.surfaceVariantText }
                                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Category"; font.pixelSize: 11; color: root.allSectionMode === "category" ? Theme.surfaceText : Theme.surfaceVariantText }
                                        }
                                        MouseArea {
                                            id: categoryModeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setAllMode("category")
                                        }
                                    }
                                    Rectangle {
                                        implicitWidth: 58
                                        implicitHeight: 28
                                        radius: 9
                                        color: root.allSectionMode === "grid" ? Theme.withAlpha(Theme.primary, 0.12)
                                            : gridModeMouse.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surface, 0.01)
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            CyIcon { anchors.verticalCenter: parent.verticalCenter; name: "grid_view"; size: 15; color: root.allSectionMode === "grid" ? Theme.surfaceText : Theme.surfaceVariantText }
                                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Grid"; font.pixelSize: 11; color: root.allSectionMode === "grid" ? Theme.surfaceText : Theme.surfaceVariantText }
                                        }
                                        MouseArea {
                                            id: gridModeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setAllMode("grid")
                                        }
                                    }
                                }

                                GridLayout {
                                    id: categoryLayout
                                    width: parent.width
                                    visible: root.allSectionMode === "category"
                                    columns: 3
                                    columnSpacing: 12
                                    rowSpacing: 7

                                    Repeater {
                                        model: root.categories

                                        delegate: Rectangle {
                                            required property var modelData
                                            property var category: modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 76
                                            radius: 13
                                            color: categoryMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : Theme.withAlpha(Theme.surfaceVariant, 0.12)
                                            border.width: 1
                                            border.color: categoryMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.34) : Theme.withAlpha(Theme.outline, 0.08)

                                            Column {
                                                anchors.fill: parent
                                                anchors.leftMargin: 9
                                                anchors.rightMargin: 9
                                                anchors.topMargin: 6
                                                anchors.bottomMargin: 6
                                                spacing: 4

                                                RowLayout {
                                                    width: parent.width
                                                    height: 24
                                                    Column {
                                                        Layout.fillWidth: true
                                                        spacing: 0
                                                        StyledText {
                                                            width: parent.width
                                                            text: category.title
                                                            color: Theme.surfaceText
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                        }
                                                        StyledText {
                                                            width: parent.width
                                                            text: category.apps.length + " apps"
                                                            color: Theme.surfaceVariantText
                                                            font.pixelSize: 9
                                                        }
                                                    }
                                                    CyIcon {
                                                        name: "chevron_right"
                                                        size: 12
                                                        color: Theme.surfaceVariantText
                                                    }
                                                }

                                                Row {
                                                    spacing: 5
                                                    Repeater {
                                                        model: category.apps.slice(0, 3)
                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            width: 28
                                                            height: 28
                                                            radius: 9
                                                            color: Theme.withAlpha(Theme.surface, 0.08)
                                                            IconImage {
                                                                anchors.centerIn: parent
                                                                width: 22
                                                                height: 22
                                                                source: root.iconSource(modelData)
                                                                visible: source.toString().length > 0
                                                            }
                                                            CyIcon {
                                                                anchors.centerIn: parent
                                                                visible: root.iconSource(modelData).length === 0
                                                                name: "apps"
                                                                size: 17
                                                                color: Theme.surfaceVariantText
                                                            }
                                                        }
                                                    }
                                                    Rectangle {
                                                        visible: category.apps.length > 3
                                                        width: visible ? 28 : 0
                                                        height: 28
                                                        radius: 9
                                                        color: Theme.withAlpha(Theme.surfaceVariant, 0.24)
                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: "+" + Math.max(0, category.apps.length - 3)
                                                            font.pixelSize: 9
                                                            font.weight: Font.DemiBold
                                                            color: Theme.surfaceText
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: categoryMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    menu.categoryFilter = String(category.id);
                                                    menu.allAppsMode = true;
                                                    root.selectedIndex = 0;
                                                }
                                            }
                                        }
                                    }
                                }

                                GridLayout {
                                    id: allGridHome
                                    width: parent.width
                                    visible: root.allSectionMode === "grid"
                                    columns: 6
                                    columnSpacing: 10
                                    rowSpacing: 7

                                    Repeater {
                                        model: root.allAppsSorted
                                        delegate: Rectangle {
                                            required property var modelData
                                            property var app: modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 78
                                            radius: 11
                                            color: homeGridMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.surface, 0.01)

                                            Column {
                                                anchors.centerIn: parent
                                                width: parent.width - 8
                                                spacing: 5
                                                Item {
                                                    width: 34; height: 34
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    IconImage {
                                                        anchors.fill: parent
                                                        source: root.iconSource(app)
                                                        visible: source.toString().length > 0
                                                    }
                                                    CyIcon {
                                                        anchors.centerIn: parent
                                                        visible: root.iconSource(app).length === 0
                                                        name: "apps"; size: 28
                                                        color: Theme.surfaceVariantText
                                                    }
                                                }
                                                StyledText {
                                                    width: parent.width
                                                    text: app.name || app.id
                                                    font.pixelSize: 11
                                                    color: Theme.surfaceText
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            MouseArea {
                                                id: homeGridMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) root.showAppActions(app);
                                                    else root.launchApp(app);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: footer
                    width: parent.width
                    height: (menu.accountOpen || menu.powerOpen) ? 118 : 54
                    radius: 16
                    color: Theme.withAlpha(Theme.surfaceVariant, 0.28)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.08)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        visible: !menu.accountOpen && !menu.powerOpen

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: 12
                            color: accountCompactMouse.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surface, 0.01)

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                CyCircularImage {
                                    width: 34; height: 34
                                    imageSource: {
                                        if (!PortalService.profileImage) return "";
                                        return PortalService.profileImage.startsWith("/") ? "file://" + PortalService.profileImage : PortalService.profileImage;
                                    }
                                    fallbackIcon: "person"
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    StyledText {
                                        text: UserInfoService.fullName || UserInfoService.username || Quickshell.env("USER") || "User"
                                        color: Theme.surfaceText
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        text: "@" + (UserInfoService.username || Quickshell.env("USER") || "user")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: 8
                                    }
                                }
                            }
                            MouseArea {
                                id: accountCompactMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { menu.accountOpen = true; menu.powerOpen = false; }
                            }
                        }

                        Rectangle {
                            implicitWidth: 36; implicitHeight: 32; radius: Theme.cornerRadius
                            color: docsMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            CyIcon { anchors.centerIn: parent; name: "folder"; size: 20; color: Theme.surfaceText }
                            MouseArea { id: docsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPath(Quickshell.env("HOME") + "/Documents") }
                        }
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 32; radius: Theme.cornerRadius
                            color: downloadsMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            CyIcon { anchors.centerIn: parent; name: "download"; size: 20; color: Theme.surfaceText }
                            MouseArea { id: downloadsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPath(Quickshell.env("HOME") + "/Downloads") }
                        }
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 32; radius: Theme.cornerRadius
                            color: settingsMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            CyIcon { anchors.centerIn: parent; name: "settings"; size: 20; color: Theme.surfaceText }
                            MouseArea { id: settingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSettings() }
                        }
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 32; radius: Theme.cornerRadius
                            color: powerMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            CyIcon { anchors.centerIn: parent; name: "power_settings_new"; size: 20; color: Theme.surfaceText }
                            MouseArea {
                                id: powerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { menu.powerOpen = true; menu.accountOpen = false; }
                            }
                        }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        visible: menu.accountOpen

                        RowLayout {
                            width: parent.width
                            height: 46
                            spacing: 10
                            CyCircularImage {
                                width: 42; height: 42
                                imageSource: {
                                    if (!PortalService.profileImage) return "";
                                    return PortalService.profileImage.startsWith("/") ? "file://" + PortalService.profileImage : PortalService.profileImage;
                                }
                                fallbackIcon: "person"
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText { text: UserInfoService.fullName || UserInfoService.username || Quickshell.env("USER") || "User"; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.surfaceText }
                                StyledText { text: "@" + (UserInfoService.username || Quickshell.env("USER") || "user"); font.pixelSize: 9; color: Theme.surfaceVariantText }
                            }
                            Rectangle {
                                implicitWidth: 32; implicitHeight: 32; radius: 9
                                color: accountCloseMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                CyIcon { anchors.centerIn: parent; name: "close"; size: 18; color: Theme.surfaceText }
                                MouseArea { id: accountCloseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.accountOpen = false }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            height: 38
                            spacing: 6
                            Rectangle {
                                implicitWidth: 118; implicitHeight: 34; radius: 10
                                color: changePictureMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "photo"; size: 17; color: Theme.surfaceText } StyledText { text: "Change picture"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: changePictureMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUserSettings() }
                            }
                            Rectangle {
                                implicitWidth: 124; implicitHeight: 34; radius: 10
                                color: accountSettingsMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "settings"; size: 17; color: Theme.surfaceText } StyledText { text: "Account settings"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: accountSettingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openUserSettings() }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 66; implicitHeight: 34; radius: 10
                                color: accountLockMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "lock"; size: 17; color: Theme.surfaceText } StyledText { text: "Lock"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: accountLockMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.lockSession() }
                            }
                            Rectangle {
                                implicitWidth: 82; implicitHeight: 34; radius: 10
                                color: signOutMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "logout"; size: 17; color: Theme.surfaceText } StyledText { text: "Sign out"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: signOutMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.signOut() }
                            }
                        }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        visible: menu.powerOpen

                        RowLayout {
                            width: parent.width
                            height: 46
                            spacing: 10
                            CyCircularImage {
                                width: 42; height: 42
                                imageSource: {
                                    if (!PortalService.profileImage) return "";
                                    return PortalService.profileImage.startsWith("/") ? "file://" + PortalService.profileImage : PortalService.profileImage;
                                }
                                fallbackIcon: "person"
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText { text: UserInfoService.fullName || UserInfoService.username || Quickshell.env("USER") || "User"; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.surfaceText }
                                StyledText { text: "@" + (UserInfoService.username || Quickshell.env("USER") || "user"); font.pixelSize: 9; color: Theme.surfaceVariantText }
                            }
                            Rectangle {
                                implicitWidth: 32; implicitHeight: 32; radius: 9
                                color: powerCloseMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                CyIcon { anchors.centerIn: parent; name: "close"; size: 18; color: Theme.surfaceText }
                                MouseArea { id: powerCloseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.powerOpen = false }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            height: 38
                            spacing: 6
                            Rectangle {
                                implicitWidth: 72; implicitHeight: 34; radius: 10
                                color: powerLockMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "lock"; size: 17; color: Theme.surfaceText } StyledText { text: "Lock"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: powerLockMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.lockSession() }
                            }
                            Rectangle {
                                implicitWidth: 76; implicitHeight: 34; radius: 10
                                color: sleepMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "bedtime"; size: 17; color: Theme.surfaceText } StyledText { text: "Sleep"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: sleepMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.suspendSession() }
                            }
                            Rectangle {
                                implicitWidth: 82; implicitHeight: 34; radius: 10
                                color: powerLogoutMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "logout"; size: 17; color: Theme.surfaceText } StyledText { text: I18n.tr("Log out"); font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: powerLogoutMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.signOut() }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 84; implicitHeight: 34; radius: 10
                                color: restartMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "restart_alt"; size: 17; color: Theme.surfaceText } StyledText { text: "Restart"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: restartMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rebootSystem() }
                            }
                            Rectangle {
                                implicitWidth: 106; implicitHeight: 34; radius: 10
                                color: shutdownMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                Row { anchors.centerIn: parent; spacing: 5; CyIcon { name: "power_settings_new"; size: 17; color: Theme.surfaceText } StyledText { text: "Shut down"; font.pixelSize: 11; color: Theme.surfaceText } }
                                MouseArea { id: shutdownMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.powerOffSystem() }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: appActionsOverlay
                anchors.fill: parent
                visible: root.actionApp !== null
                color: "#66000000"
                z: 1000

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.actionApp = null
                }

                Rectangle {
                    id: appActionsCard
                    anchors.centerIn: parent
                    width: 320
                    height: Math.min(500, 272 + root.desktopActionsFor(root.actionApp).length * 36)
                    radius: Theme.cornerRadius * 1.3
                    color: Theme.surfaceContainerHigh
                    border.width: 1
                    border.color: Theme.outline

                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: 4

                        Row {
                            width: parent.width
                            height: 40
                            spacing: Theme.spacingM

                            Item {
                                width: 34
                                height: 34
                                anchors.verticalCenter: parent.verticalCenter

                                IconImage {
                                    anchors.fill: parent
                                    source: root.iconSource(root.actionApp)
                                    visible: root.actionApp !== null && source.toString().length > 0
                                }

                                CyIcon {
                                    anchors.centerIn: parent
                                    visible: root.actionApp === null || root.iconSource(root.actionApp).length === 0
                                    name: "apps"
                                    size: 26
                                    color: Theme.surfaceVariantText
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 56
                                spacing: 2

                                StyledText {
                                    width: parent.width
                                    text: root.actionApp ? (root.actionApp.name || root.actionApp.id) : ""
                                    elide: Text.ElideRight
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.actionApp ? (root.actionApp.generic || root.actionApp.provider || root.actionApp.launcher || "Application") : ""
                                    elide: Text.ElideRight
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: Theme.cornerRadius
                            color: startPinMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                CyIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: root.actionApp && root.isPinned(root.actionApp.id) ? "keep_off" : "keep"
                                    size: 18
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.actionApp && root.isPinned(root.actionApp.id) ? "Unpin from Start" : "Pin to Start"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: startPinMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.actionApp)
                                        root.togglePin(root.actionApp);
                                    root.actionApp = null;
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: Theme.cornerRadius
                            color: taskbarPinMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                CyIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: root.actionApp && root.isDockPinned(root.actionApp) ? "remove_from_queue" : "add_to_queue"
                                    size: 18
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.actionApp && root.isDockPinned(root.actionApp) ? "Unpin from Taskbar" : "Pin to Taskbar"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: taskbarPinMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.actionApp)
                                        root.toggleDockPin(root.actionApp);
                                    root.actionApp = null;
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: Theme.cornerRadius
                            color: adminMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                CyIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "admin_panel_settings"
                                    size: 18
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Run as administrator"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: adminMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const app = root.actionApp;
                                    root.actionApp = null;
                                    if (app)
                                        root.launchAsAdmin(app);
                                }
                            }
                        }

                        Repeater {
                            model: root.desktopActionsFor(root.actionApp)

                            delegate: Rectangle {
                                required property var modelData
                                width: appActionsCard.width - Theme.spacingL * 2
                                height: 36
                                radius: Theme.cornerRadius
                                color: appDesktopActionMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingM

                                    CyIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.icon && modelData.icon !== "" ? modelData.icon : "play_arrow"
                                        size: 18
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 52
                                        text: modelData.name || "App action"
                                        elide: Text.ElideRight
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                MouseArea {
                                    id: appDesktopActionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const app = root.actionApp;
                                        root.actionApp = null;
                                        if (app)
                                            root.launchDesktopActionFor(app, modelData);
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: Theme.cornerRadius
                            color: openLocationMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            visible: root.actionApp && String(root.actionApp.source || root.actionApp.install_path || "").length > 0

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM
                                CyIcon { anchors.verticalCenter: parent.verticalCenter; name: "folder_open"; size: 18; color: Theme.surfaceText }
                                StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Open file location"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeSmall }
                            }
                            MouseArea {
                                id: openLocationMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const app = root.actionApp;
                                    root.actionApp = null;
                                    if (app) root.openAppLocation(app);
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: Theme.cornerRadius
                            color: openAppMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                CyIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "open_in_new"
                                    size: 18
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Open"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: openAppMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const app = root.actionApp;
                                    root.actionApp = null;
                                    if (app)
                                        root.launchApp(app);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
