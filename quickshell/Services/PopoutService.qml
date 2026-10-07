pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Singleton {
    id: root

    property var controlCenterPopout: null
    property var controlCenterLoader: null
    property var notificationCenterPopout: null
    property var notificationCenterLoader: null
    property var calendarPopout: null
    property var calendarPopoutLoader: null
    property var appDrawerPopout: null
    property var appDrawerLoader: null
    property var processListPopout: null
    property var processListPopoutLoader: null
    property var dankDashPopout: null
    property var dankDashPopoutLoader: null
    property var batteryPopout: null
    property var batteryPopoutLoader: null
    property var vpnPopout: null
    property var vpnPopoutLoader: null
    property var colorPickerPopout: null
    property var colorPickerPopoutLoader: null
    property var systemUpdatePopout: null
    property var systemUpdateLoader: null
    property var clipboardHistoryPopout: null
    property var clipboardHistoryPopoutLoader: null

    property var settingsModal: null
    property var settingsModalLoader: null
    readonly property string uiRole: Quickshell.env("CYSHELL_UI_ROLE") || ""
    readonly property bool transientUiOwner: uiRole === "" || uiRole === "shell"
    readonly property bool externalNotificationCenterOwner: Quickshell.env("CYSHELL_EXTERNAL_PANEL") === "1" && uiRole !== "panel"
    readonly property bool externalSettingsProcess: uiRole !== "settings" && (uiRole.length > 0 || Quickshell.env("CYSHELL_EXTERNAL_SETTINGS") === "1")

    function forwardNotificationCenterRequest(action, payload) {
        if (!externalNotificationCenterOwner)
            return false;
        Quickshell.execDetached(["cyshell", "ipc", "call", "panel", "notificationCenter", String(action), String(payload || "")]);
        return true;
    }

    function routeNotificationCenterRequest(action, x, y, width, section, screen, triggerSource, tab, mode, islandActivity, barPosition, barThickness, barSpacing, barConfig) {
        return forwardNotificationCenterRequest(action, transientUiPayload(x, y, width, section, screen, triggerSource, tab, mode, islandActivity, barPosition, barThickness, barSpacing, barConfig));
    }

    function _externalSettingsCall(method, args) {
        if (!externalSettingsProcess)
            return false;
        const command = ["cyshell", "settings", method];
        for (const arg of (args || []))
            command.push(String(arg));
        Quickshell.execDetached(command);
        return true;
    }

    function _externalShellCall(target, method, args) {
        if (transientUiOwner)
            return false;
        const command = ["cyshell", "ipc", "call", target, method];
        for (const arg of (args || []))
            command.push(String(arg));
        Quickshell.execDetached(command);
        return true;
    }

    function transientUiPayload(x, y, width, section, screen, triggerSource, tab, mode, islandActivity, barPosition, barThickness, barSpacing, barConfig) {
        const anchorX = Number(x);
        const anchorY = Number(y);
        const anchorWidth = Number(width);
        const edge = Number(barPosition);
        const thickness = Number(barThickness);
        const spacing = Number(barSpacing);
        const hasAnchor = screen?.name
            && Number.isFinite(anchorX)
            && Number.isFinite(anchorY)
            && Number.isFinite(anchorWidth)
            && anchorWidth > 0;
        return JSON.stringify({
            kind: "cyshell-transient-ui-anchor",
            x: hasAnchor ? anchorX : null,
            y: hasAnchor ? anchorY : null,
            width: hasAnchor ? anchorWidth : null,
            section: String(section || "center"),
            screen: String(screen?.name || ""),
            triggerSource: String(triggerSource || ""),
            tab: String(tab || ""),
            mode: mode === "hover" ? "hover" : "click",
            islandActivity: String(islandActivity || ""),
            barPosition: Number.isFinite(edge) ? edge : null,
            barThickness: Number.isFinite(thickness) ? thickness : null,
            barSpacing: Number.isFinite(spacing) ? spacing : null,
            barConfig: barConfig || null
        });
    }

    function _resolveDirectCallerAnchor(x, y, width, section, screen) {
        const expectedX = Number(x);
        const expectedY = Number(y);
        const expectedWidth = Number(width);
        const targetScreenName = String(screen?.name || "");
        const targetSection = String(section || "center");
        if (!targetScreenName || !Number.isFinite(expectedX) || !Number.isFinite(expectedY) || !Number.isFinite(expectedWidth) || expectedWidth <= 0)
            return { anchor: null, matchCount: 0 };

        const matches = [];
        for (const registration of Object.values(BarWidgetService.widgetRegistry || {})) {
            if (registration?.screenName !== targetScreenName || !BarWidgetService.registrationActive(registration))
                continue;
            const item = registration.item;
            if (typeof item?.pillAnchor !== "function")
                continue;

            let anchor = null;
            try {
                anchor = item.pillAnchor();
            } catch (error) {
                continue;
            }
            const trigger = anchor?.trigger;
            if (anchor?.screen?.name !== targetScreenName || String(anchor.section || item.section || "center") !== targetSection)
                continue;
            if (!Number.isFinite(anchor.position) || !Number.isFinite(anchor.thickness) || !Number.isFinite(anchor.spacing) || !anchor.config || typeof anchor.config !== "object")
                continue;
            if (!Number.isFinite(Number(trigger?.x)) || !Number.isFinite(Number(trigger?.y)) || !Number.isFinite(Number(trigger?.width)))
                continue;
            if (Math.abs(Number(trigger?.x) - expectedX) > 0.5 || Math.abs(Number(trigger?.y) - expectedY) > 0.5 || Math.abs(Number(trigger?.width) - expectedWidth) > 0.5)
                continue;
            matches.push(anchor);
        }

        return { anchor: matches.length === 1 ? matches[0] : null, matchCount: matches.length };
    }

    function _directCallerBarConfig(config) {
        if (!config || typeof config !== "object")
            return null;
        const anchoredConfig = Object.assign({}, config);
        // The caller already supplied the final trigger geometry. Prevent
        // CyPopout from replacing it with a natural/expanded anchor after IPC
        // or after this direct helper has selected the exact caller bar.
        anchoredConfig.widgetExpansion = "none";
        return anchoredConfig;
    }

    function _setDirectCallerPosition(popout, x, y, width, section, screen) {
        const expectedX = Number(x);
        const expectedY = Number(y);
        const expectedWidth = Number(width);
        const hasCallerGeometry = !!screen?.name && Number.isFinite(expectedX) && Number.isFinite(expectedY) && Number.isFinite(expectedWidth) && expectedWidth > 0;
        const resolved = _resolveDirectCallerAnchor(x, y, width, section, screen);
        if (hasCallerGeometry && !resolved.anchor)
            return false;
        if (resolved.anchor) {
            setPosition(popout, x, y, width, section, screen, resolved.anchor.position, resolved.anchor.thickness, resolved.anchor.spacing, _directCallerBarConfig(resolved.anchor.config));
            return true;
        }
        const fallback = screen ? BarWidgetService.naturalPopoutAnchor(screen, null, section || "center") : null;
        if (!fallback?.trigger)
            return false;
        setPosition(popout, fallback.trigger.x, fallback.trigger.y, fallback.trigger.width, fallback.section || section || "center", screen, fallback.position, fallback.thickness, fallback.spacing, _directCallerBarConfig(fallback.config));
        return true;
    }

    function _externalAnchoredTransientUiCall(surface, action, x, y, width, section, screen, triggerSource, tab, mode, islandActivity) {
        const expectedX = Number(x);
        const expectedY = Number(y);
        const expectedWidth = Number(width);
        const hasCallerGeometry = !!screen?.name && Number.isFinite(expectedX) && Number.isFinite(expectedY) && Number.isFinite(expectedWidth) && expectedWidth > 0;
        const resolved = _resolveDirectCallerAnchor(x, y, width, section, screen);
        if (hasCallerGeometry && !resolved.anchor)
            return false;
        const callerBar = resolved.anchor;
        const remoteBarConfig = _directCallerBarConfig(callerBar?.config);
        const payload = transientUiPayload(
            hasCallerGeometry ? x : null,
            hasCallerGeometry ? y : null,
            hasCallerGeometry ? width : null,
            section,
            screen,
            triggerSource,
            tab,
            mode,
            islandActivity,
            callerBar?.position,
            callerBar?.thickness,
            callerBar?.spacing,
            remoteBarConfig
        );
        return _externalShellCall("transient-ui", "invoke", [surface, action, payload]);
    }
    property var clipboardHistoryModal: null
    property var dankLauncherV2Modal: null
    property var dankLauncherV2ModalLoader: null
    property var dankIslandRouter: null
    property var spotlightBarModal: null
    property var spotlightBarModalLoader: null
    property var powerMenuModal: null
    property var powerMenuModalLoader: null
    property var powerMenuPopout: null
    property var powerMenuPopoutLoader: null
    property var durationPopout: null
    property var durationPopoutLoader: null
    property var processListModal: null
    property var processListModalLoader: null
    property var agentAssistantModal: null
    property var agentAssistantModalLoader: null
    property var agentApprovalModal: null
    property var agentApprovalModalLoader: null
    property var colorPickerModal: null
    property var notificationModal: null
    property var wifiPasswordModal: null
    property var wifiPasswordModalLoader: null
    property var wifiQRCodeModal: null
    property var wifiQRCodeModalLoader: null
    property var qrGeneratorModal: null
    property var qrGeneratorModalLoader: null
    property var polkitAuthModal: null
    property var polkitAuthModalLoader: null
    property var bluetoothPairingModal: null
    property var bluetoothPairingModalLoader: null
    property var networkInfoModal: null
    property var powerProfileModal: null
    property var powerProfileModalLoader: null

    property var notepadSlideouts: []

    property string pendingThemeInstall: ""
    property string pendingPluginInstall: ""

    // Deferred unload: keep popouts warm while the session is active and reclaim them on lock/monitors-off.
    property var _pendingUnloads: ({})

    Connections {
        target: SessionService
        function onSessionLocked() {
            root._flushPendingUnloads();
        }
    }

    Connections {
        target: IdleService
        function onMonitorsOffChanged() {
            if (IdleService.monitorsOff)
                root._flushPendingUnloads();
        }
    }

    function _scheduleUnload(key) {
        _pendingUnloads[key] = true;
    }

    function _flushPendingUnloads() {
        const keys = Object.keys(_pendingUnloads);
        _pendingUnloads = ({});
        for (let i = 0; i < keys.length; i++) {
            const unload = _deferredUnloaders[keys[i]];
            if (unload)
                unload();
        }
    }

    function _popoutStillPresented(popout) {
        return !!popout && (popout.shouldBeVisible === true || popout.isClosing === true);
    }

    function _unloadPopoutNow(popoutName, loaderName) {
        const loader = root[loaderName];
        if (!loader)
            return;
        if (_popoutStillPresented(root[popoutName]))
            return;
        root[popoutName] = null;
        loader.active = false;
    }

    readonly property var _deferredUnloaders: ({
            "dankDash": () => _unloadPopoutNow("dankDashPopout", "dankDashPopoutLoader"),
            "controlCenter": () => _unloadPopoutNow("controlCenterPopout", "controlCenterLoader"),
            "notificationCenter": () => _unloadPopoutNow("notificationCenterPopout", "notificationCenterLoader"),
            "calendar": () => _unloadPopoutNow("calendarPopout", "calendarPopoutLoader"),
            "appDrawer": () => _unloadPopoutNow("appDrawerPopout", "appDrawerLoader"),
            "processList": () => _unloadPopoutNow("processListPopout", "processListPopoutLoader"),
            "battery": () => _unloadPopoutNow("batteryPopout", "batteryPopoutLoader"),
            "vpn": () => _unloadPopoutNow("vpnPopout", "vpnPopoutLoader"),
            "colorPicker": () => _unloadPopoutNow("colorPickerPopout", "colorPickerPopoutLoader"),
            "powerMenuPopout": () => _unloadPopoutNow("powerMenuPopout", "powerMenuPopoutLoader"),
            "duration": () => _unloadPopoutNow("durationPopout", "durationPopoutLoader"),
            "systemUpdate": () => _unloadPopoutNow("systemUpdatePopout", "systemUpdateLoader"),
            "clipboardHistory": () => _unloadPopoutNow("clipboardHistoryPopout", "clipboardHistoryPopoutLoader"),
            "settings": () => unloadSettingsNow()
        })

    function setPosition(popout, x, y, width, section, screen, barPosition, barThickness, barSpacing, barConfig) {
        if (popout && popout.setTriggerPosition && arguments.length >= 6) {
            if (screen && "triggerScreen" in popout)
                popout.triggerScreen = screen;
            if (arguments.length >= 7)
                popout.setTriggerPosition(x, y, width, section, screen, barPosition, barThickness, barSpacing, barConfig);
            else
                popout.setTriggerPosition(x, y, width, section, screen);
        }
    }

    function _withLazyPopout(popoutName, loaderName, action) {
        const current = root[popoutName];
        if (current) {
            action(current);
            return true;
        }
        const loader = root[loaderName];
        if (!loader)
            return false;
        loader.active = true;
        Qt.callLater(() => {
            const loaded = root[popoutName] ?? loader.item;
            if (loaded)
                action(loaded);
        });
        return true;
    }

    function invokeRemoteWidgetPopout(surface, action, triggerSource, x, y, width, section, screen, mode, tab, islandActivity, barPosition, barThickness, barSpacing, barConfig) {
        let popoutName;
        let loaderName;
        if (surface === "controlCenter") {
            popoutName = "controlCenterPopout";
            loaderName = "controlCenterLoader";
            triggerSource = triggerSource || "controlCenter";
            islandActivity = "controlcenter";
        } else if (surface === "notificationCenter") {
            popoutName = "notificationCenterPopout";
            loaderName = "notificationCenterLoader";
            triggerSource = triggerSource || "notifications";
            islandActivity = "notificationcenter";
        } else if (surface === "calendar") {
            popoutName = "calendarPopout";
            loaderName = "calendarPopoutLoader";
            triggerSource = triggerSource || "calendar";
        } else if (surface === "battery") {
            popoutName = "batteryPopout";
            loaderName = "batteryPopoutLoader";
            triggerSource = triggerSource || "battery";
        } else if (surface === "vpn") {
            popoutName = "vpnPopout";
            loaderName = "vpnPopoutLoader";
            triggerSource = triggerSource || "vpn";
        } else if (surface === "systemUpdate") {
            popoutName = "systemUpdatePopout";
            loaderName = "systemUpdateLoader";
            triggerSource = triggerSource || "systemUpdate";
        } else if (surface === "duration") {
            if (triggerSource !== "dndDuration" && triggerSource !== "idleInhibit")
                return false;
            popoutName = "durationPopout";
            loaderName = "durationPopoutLoader";
        } else if (surface === "colorPicker") {
            popoutName = "colorPickerPopout";
            loaderName = "colorPickerPopoutLoader";
            triggerSource = "colorPicker";
        } else if (surface === "dash") {
            popoutName = "dankDashPopout";
            loaderName = "dankDashPopoutLoader";
            triggerSource = triggerSource || `dash-${tab || "home"}`;
        } else {
            return false;
        }

        const routedIslandActivity = surface === "dash" ? "" : islandActivity;
        if (action === "close") {
            if (routedIslandActivity && closeIslandActivity(routedIslandActivity))
                return true;
            if (surface === "dash") {
                closeCyDash();
                return true;
            }
            root[popoutName]?.close();
            return true;
        }
        if ((action !== "open" && action !== "toggle") || !screen)
            return false;

        if (routedIslandActivity && routeToIsland(routedIslandActivity, screen, action === "toggle", section, barConfig?.id))
            return true;

        return _withLazyPopout(popoutName, loaderName, popout => {
            setPosition(popout, x, y, width, section, screen, barPosition, barThickness, barSpacing, barConfig);
            if (surface === "dash") {
                popout.requestTab(tab || "home");
                if (action === "toggle" && popout.dashVisible) {
                    popout.dashVisible = false;
                    return;
                }
                popout.dashVisible = true;
            }
            if (typeof popout.prepareForTrigger === "function")
                popout.prepareForTrigger(triggerSource, mode);
            if (action === "open" && mode === "hover")
                PopoutManager.requestHoverPopout(popout, undefined, triggerSource);
            else if (action === "open")
                popout.open();
            else
                PopoutManager.requestPopout(popout, undefined, triggerSource);
        });
    }

    function _islandOwnsSharedTrigger(screen) {
        const target = screen ?? dankIslandRouter?.focusedIslandScreen?.() ?? null;
        if (dankIslandRouter?.hasHostForScreen?.(target) !== true)
            return false;
        return SettingsData.dankIslandIsSoleBarForScreen(target);
    }

    readonly property bool islandControlCenterOpen: dankIslandRouter?.controlCenterOpen ?? false

    function routeToIsland(activityId, screen, shouldToggle, section, barId) {
        if (barId && dankIslandRouter?.hasHostForScreen(screen, barId) !== true)
            return false;
        if (!barId && !_islandOwnsSharedTrigger(screen))
            return false;
        if (shouldToggle === true)
            return dankIslandRouter.toggleActivity(activityId, screen ?? null, section || "", barId) === true;
        return dankIslandRouter.openActivity(activityId, screen ?? null, section || "", barId) === true;
    }

    function closeIslandActivity(activityId) {
        return dankIslandRouter?.closeActivity?.(activityId) === true;
    }

    function openControlCenter(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("controlCenter", "open", x, y, width, section, screen, "controlCenter", "", "click", "controlcenter"))
            return;
        const callerBarId = _resolveDirectCallerAnchor(x, y, width, section, screen).anchor?.config?.id;
        if (routeToIsland("controlcenter", screen, false, section, callerBarId))
            return;
        _withLazyPopout("controlCenterPopout", "controlCenterLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.open();
        });
    }

    function closeControlCenter() {
        if (_externalShellCall("transient-ui", "invoke", ["controlCenter", "close", ""]))
            return;
        if (closeIslandActivity("controlcenter"))
            return;
        controlCenterPopout?.close();
    }

    function unloadControlCenter() {
        _scheduleUnload("controlCenter");
    }

    function toggleControlCenter(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("controlCenter", "toggle", x, y, width, section, screen, "controlCenter", "", "click", "controlcenter"))
            return;
        const callerBarId = _resolveDirectCallerAnchor(x, y, width, section, screen).anchor?.config?.id;
        if (routeToIsland("controlcenter", screen, true, section, callerBarId))
            return;
        _withLazyPopout("controlCenterPopout", "controlCenterLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.toggle();
        });
    }

    function openNotificationCenter(x, y, width, section, screen) {
        if (routeNotificationCenterRequest("open", x, y, width, section, screen, "notifications", "", "click", "notificationcenter"))
            return;
        if (uiRole !== "panel" && _externalAnchoredTransientUiCall("notificationCenter", "open", x, y, width, section, screen, "notifications", "", "click", "notificationcenter"))
            return;
        const callerBarId = _resolveDirectCallerAnchor(x, y, width, section, screen).anchor?.config?.id;
        if (routeToIsland("notificationcenter", screen, false, section, callerBarId))
            return;
        _withLazyPopout("notificationCenterPopout", "notificationCenterLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.open();
        });
    }

    function closeNotificationCenter() {
        if (forwardNotificationCenterRequest("close", ""))
            return;
        if (uiRole === "panel") {
            notificationCenterPopout?.close();
            return;
        }
        if (_externalShellCall("transient-ui", "invoke", ["notificationCenter", "close", ""]))
            return;
        if (closeIslandActivity("notificationcenter"))
            return;
        notificationCenterPopout?.close();
    }

    function unloadNotificationCenter() {
        _scheduleUnload("notificationCenter");
    }

    function toggleNotificationCenter(x, y, width, section, screen) {
        if (routeNotificationCenterRequest("toggle", x, y, width, section, screen, "notifications", "", "click", "notificationcenter"))
            return;
        if (uiRole !== "panel" && _externalAnchoredTransientUiCall("notificationCenter", "toggle", x, y, width, section, screen, "notifications", "", "click", "notificationcenter"))
            return;
        const callerBarId = _resolveDirectCallerAnchor(x, y, width, section, screen).anchor?.config?.id;
        if (routeToIsland("notificationcenter", screen, true, section, callerBarId))
            return;
        _withLazyPopout("notificationCenterPopout", "notificationCenterLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.toggle();
        });
    }

    function openCalendar(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("calendar", "open", x, y, width, section, screen, "calendar", "", "click", ""))
            return;
        _withLazyPopout("calendarPopout", "calendarPopoutLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.open();
        });
    }

    function closeCalendar() {
        if (_externalShellCall("transient-ui", "invoke", ["calendar", "close", ""]))
            return;
        calendarPopout?.close();
        _scheduleUnload("calendar");
    }

    function unloadCalendar() {
        _scheduleUnload("calendar");
    }

    function toggleCalendar(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("calendar", "toggle", x, y, width, section, screen, "calendar", "", "click", ""))
            return;
        _withLazyPopout("calendarPopout", "calendarPopoutLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.toggle();
        });
    }

    function openAppDrawer(x, y, width, section, screen) {
        if (appDrawerPopout) {
            setPosition(appDrawerPopout, x, y, width, section, screen);
            appDrawerPopout.open();
        }
    }

    function closeAppDrawer() {
        appDrawerPopout?.close();
    }

    function unloadAppDrawer() {
        _scheduleUnload("appDrawer");
    }

    function toggleAppDrawer(x, y, width, section, screen) {
        if (appDrawerPopout) {
            setPosition(appDrawerPopout, x, y, width, section, screen);
            appDrawerPopout.toggle();
        }
    }

    function openProcessList(x, y, width, section, screen) {
        if (processListPopout) {
            setPosition(processListPopout, x, y, width, section, screen);
            processListPopout.open();
        }
    }

    function closeProcessList() {
        processListPopout?.close();
    }

    function unloadProcessListPopout() {
        _scheduleUnload("processList");
    }

    function toggleProcessList(x, y, width, section, screen) {
        if (processListPopout) {
            setPosition(processListPopout, x, y, width, section, screen);
            processListPopout.toggle();
        }
    }

    property bool _dankDashWantsOpen: false
    property bool _dankDashWantsToggle: false
    property bool _dankDashWantsEdit: false
    property var _dankDashPendingTab: 0
    property real _dankDashPendingX: 0
    property real _dankDashPendingY: 0
    property real _dankDashPendingWidth: 0
    property string _dankDashPendingSection: ""
    property var _dankDashPendingScreen: null
    property bool _dankDashHasPosition: false

    function _storeCyDashPosition(x, y, width, section, screen, hasPos) {
        _dankDashPendingX = x;
        _dankDashPendingY = y;
        _dankDashPendingWidth = width;
        _dankDashPendingSection = section;
        _dankDashPendingScreen = screen;
        _dankDashHasPosition = hasPos;
    }

    function openCyDash(tab, x, y, width, section, screen) {
        if (_externalShellCall("dash", "open", [tab || "home"]))
            return;
        _dankDashWantsEdit = false;
        _dankDashPendingTab = tab || 0;
        if (dankDashPopout) {
            if (arguments.length >= 6)
                setPosition(dankDashPopout, x, y, width, section, screen);
            dankDashPopout.requestTab(_dankDashPendingTab);
            dankDashPopout.dashVisible = true;
            return;
        }
        if (!dankDashPopoutLoader)
            return;
        _storeCyDashPosition(x, y, width, section, screen, arguments.length >= 6);
        _dankDashWantsOpen = true;
        _dankDashWantsToggle = false;
        dankDashPopoutLoader.active = true;
    }

    function closeCyDash() {
        if (_externalShellCall("dash", "close", []))
            return;
        _dankDashWantsEdit = false;
        if (dankDashPopout)
            dankDashPopout.dashVisible = false;
    }

    function toggleCyDash(tab, x, y, width, section, screen) {
        if (_externalShellCall("dash", "toggle", [tab || "home"]))
            return;
        _dankDashWantsEdit = false;
        _dankDashPendingTab = tab || 0;
        if (dankDashPopout) {
            if (arguments.length >= 6)
                setPosition(dankDashPopout, x, y, width, section, screen);
            if (dankDashPopout.dashVisible) {
                dankDashPopout.dashVisible = false;
            } else {
                dankDashPopout.requestTab(_dankDashPendingTab);
                dankDashPopout.dashVisible = true;
            }
            return;
        }
        if (!dankDashPopoutLoader)
            return;
        _storeCyDashPosition(x, y, width, section, screen, arguments.length >= 6);
        _dankDashWantsToggle = true;
        _dankDashWantsOpen = false;
        dankDashPopoutLoader.active = true;
    }

    function _onCyDashPopoutLoaded() {
        if (!dankDashPopout)
            return;

        if (_dankDashWantsEdit) {
            _showCyDashEditor();
            return;
        }

        if (_dankDashHasPosition)
            setPosition(dankDashPopout, _dankDashPendingX, _dankDashPendingY, _dankDashPendingWidth, _dankDashPendingSection, _dankDashPendingScreen);

        if (_dankDashWantsOpen) {
            _dankDashWantsOpen = false;
            dankDashPopout.requestTab(_dankDashPendingTab);
            dankDashPopout.dashVisible = true;
            return;
        }
        if (_dankDashWantsToggle) {
            _dankDashWantsToggle = false;
            if (dankDashPopout.dashVisible) {
                dankDashPopout.dashVisible = false;
            } else {
                dankDashPopout.requestTab(_dankDashPendingTab);
                dankDashPopout.dashVisible = true;
            }
        }
    }

    function openCyDashEditor(tab, screen) {
        const target = screen ?? Quickshell.screens.find(candidate => candidate.name === CompositorService.getFocusedScreenName()) ?? Quickshell.screens[0];
        if (!target || (!dankDashPopout && !dankDashPopoutLoader))
            return;
        closeSettings();
        _dankDashPendingTab = tab;
        _dankDashPendingScreen = target;
        _dankDashHasPosition = false;
        _dankDashWantsOpen = false;
        _dankDashWantsToggle = false;
        _dankDashWantsEdit = true;
        if (dankDashPopout) {
            _showCyDashEditor();
            return;
        }
        dankDashPopoutLoader.active = true;
    }

    function _showCyDashEditor() {
        _dankDashWantsEdit = false;
        const target = _dankDashPendingScreen;
        const anchor = BarWidgetService.naturalPopoutAnchor(target, null, "center");
        dankDashPopout.setTriggerPosition(anchor.trigger.x, anchor.trigger.y, anchor.trigger.width, anchor.section, target, anchor.position, anchor.thickness, anchor.spacing, anchor.config);
        dankDashPopout.requestTab(_dankDashPendingTab);
        dankDashPopout.editMode = true;
        dankDashPopout.dashVisible = true;
    }

    function openBattery(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("battery", "open", x, y, width, section, screen, "battery", "", "click"))
            return;
        _withLazyPopout("batteryPopout", "batteryPopoutLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.open();
        });
    }

    function closeBattery() {
        if (_externalShellCall("transient-ui", "invoke", ["battery", "close", ""]))
            return;
        batteryPopout?.close();
    }

    function unloadBattery() {
        _scheduleUnload("battery");
    }

    function toggleBattery(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("battery", "toggle", x, y, width, section, screen, "battery", "", "click"))
            return;
        _withLazyPopout("batteryPopout", "batteryPopoutLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.toggle();
        });
    }

    function openVpn(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("vpn", "open", x, y, width, section, screen, "vpn", "", "click"))
            return;
        _withLazyPopout("vpnPopout", "vpnPopoutLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.open();
        });
    }

    function closeVpn() {
        if (_externalShellCall("transient-ui", "invoke", ["vpn", "close", ""]))
            return;
        vpnPopout?.close();
    }

    function unloadVpn() {
        _scheduleUnload("vpn");
    }

    function toggleVpn(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("vpn", "toggle", x, y, width, section, screen, "vpn", "", "click"))
            return;
        _withLazyPopout("vpnPopout", "vpnPopoutLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.toggle();
        });
    }

    function openSystemUpdate(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("systemUpdate", "open", x, y, width, section, screen, "systemUpdate", "", "click"))
            return;
        _withLazyPopout("systemUpdatePopout", "systemUpdateLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.open();
        });
    }

    function closeSystemUpdate() {
        if (_externalShellCall("transient-ui", "invoke", ["systemUpdate", "close", ""]))
            return;
        systemUpdatePopout?.close();
    }

    function unloadSystemUpdate() {
        _scheduleUnload("systemUpdate");
    }

    function toggleSystemUpdate(x, y, width, section, screen) {
        if (_externalAnchoredTransientUiCall("systemUpdate", "toggle", x, y, width, section, screen, "systemUpdate", "", "click"))
            return;
        _withLazyPopout("systemUpdatePopout", "systemUpdateLoader", popout => {
            if (!_setDirectCallerPosition(popout, x, y, width, section, screen))
                return;
            popout.toggle();
        });
    }

    property bool _settingsWantsOpen: false
    property bool _settingsWantsToggle: false

    property string _settingsPendingTab: ""
    property int _settingsPendingTabIndex: -1

    property double _settingsShownAt: 0

    function _settingsWindowDead() {
        if (!settingsModal?.visible)
            return false;
        // toplevel registration is async; a freshly shown window looks dead
        if (Date.now() - _settingsShownAt < 2000)
            return false;
        const settingsTitle = I18n.tr("Settings", "settings window title");
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (toplevel.title === "Settings" || toplevel.title === settingsTitle)
                return false;
        }
        return true;
    }

    function _rebuildDeadSettings() {
        settingsModal.visible = false;
        settingsModal = null;
        settingsModalLoader.active = false;
        _settingsWantsOpen = true;
        _settingsWantsToggle = false;
        Qt.callLater(() => {
            if (settingsModalLoader)
                settingsModalLoader.activeAsync = true;
        });
    }

    function openSettings() {
        if (_externalSettingsCall("open"))
            return;
        if (settingsModal) {
            if (_settingsWindowDead()) {
                _rebuildDeadSettings();
                return;
            }
            settingsModal.show();
        } else if (settingsModalLoader) {
            _settingsWantsOpen = true;
            _settingsWantsToggle = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    property var _settingsReturnOrigin: null
    property var _settingsReturnReopen: null

    Connections {
        target: root.settingsModal
        function onClosingModal() {
            root._restoreSettingsOrigin();
        }
        function onVisibleChanged() {
            if (root.settingsModal?.visible)
                root._settingsShownAt = Date.now();
        }
    }

    function _restoreSettingsOrigin() {
        const origin = _settingsReturnOrigin;
        const reopen = _settingsReturnReopen;
        _settingsReturnOrigin = null;
        _settingsReturnReopen = null;
        if (!origin || !reopen)
            return;
        reopen();
    }

    function openSettingsWithTab(tabName: string, returnOrigin, reopen) {
        if (!returnOrigin && !reopen && _externalSettingsCall("openWithTab", [tabName]))
            return;
        _settingsReturnOrigin = returnOrigin ?? null;
        _settingsReturnReopen = reopen ?? null;
        if (settingsModal) {
            if (_settingsWindowDead()) {
                _settingsPendingTab = tabName;
                _rebuildDeadSettings();
                return;
            }
            settingsModal.showWithTabName(tabName);
            return;
        }
        if (settingsModalLoader) {
            _settingsPendingTab = tabName;
            _settingsWantsOpen = true;
            _settingsWantsToggle = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function openSettingsWithTabIndex(tabIndex: int) {
        if (_externalSettingsCall("openWithTabIndex", [tabIndex]))
            return;
        if (settingsModal) {
            if (_settingsWindowDead()) {
                _settingsPendingTabIndex = tabIndex;
                _rebuildDeadSettings();
                return;
            }
            settingsModal.showWithTab(tabIndex);
            return;
        }
        if (settingsModalLoader) {
            _settingsPendingTabIndex = tabIndex;
            _settingsWantsOpen = true;
            _settingsWantsToggle = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function closeSettings() {
        if (_externalSettingsCall("close"))
            return;
        settingsModal?.hide();
    }

    function toggleSettings() {
        if (_externalSettingsCall("toggle"))
            return;
        if (settingsModal) {
            settingsModal.toggle();
        } else if (settingsModalLoader) {
            _settingsWantsToggle = true;
            _settingsWantsOpen = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function toggleSettingsWithTab(tabName: string) {
        if (_externalSettingsCall("toggleWithTab", [tabName]))
            return;
        if (settingsModal) {
            settingsModal.setPageName(tabName);
            settingsModal.toggle();
            return;
        }
        if (settingsModalLoader) {
            _settingsPendingTab = tabName;
            _settingsWantsToggle = true;
            _settingsWantsOpen = false;
            settingsModalLoader.activeAsync = true;
        }
    }

    function focusOrToggleSettings() {
        if (_externalSettingsCall("focusOrToggle"))
            return;
        if (settingsModal?.visible) {
            const settingsTitle = I18n.tr("Settings", "settings window title");
            for (const toplevel of ToplevelManager.toplevels.values) {
                if (toplevel.title !== "Settings" && toplevel.title !== settingsTitle)
                    continue;
                if (toplevel.activated) {
                    settingsModal.hide();
                    return;
                }
                CompositorService.activateToplevel(toplevel);
                return;
            }
        }
        openSettings();
    }

    function focusOrToggleSettingsWithTab(tabName: string) {
        if (_externalSettingsCall("focusOrToggleWithTab", [tabName]))
            return;
        if (settingsModal?.visible) {
            const settingsTitle = I18n.tr("Settings", "settings window title");
            for (const toplevel of ToplevelManager.toplevels.values) {
                if (toplevel.title !== "Settings" && toplevel.title !== settingsTitle)
                    continue;
                if (toplevel.activated) {
                    settingsModal.hide();
                    return;
                }
                settingsModal.setPageName(tabName);
                CompositorService.activateToplevel(toplevel);
                return;
            }
        }
        openSettingsWithTab(tabName);
    }

    function unloadSettingsNow() {
        if (!settingsModalLoader)
            return;
        if (settingsModal && settingsModal.visible)
            return;
        delete _pendingUnloads["settings"];
        settingsModal = null;
        settingsModalLoader.active = false;
    }

    function _onSettingsModalLoaded() {
        if (_settingsWantsOpen) {
            _settingsWantsOpen = false;
            if (_settingsPendingTabIndex >= 0) {
                settingsModal?.showWithTab(_settingsPendingTabIndex);
                _settingsPendingTabIndex = -1;
            } else if (_settingsPendingTab) {
                settingsModal?.showWithTabName(_settingsPendingTab);
                _settingsPendingTab = "";
            } else {
                settingsModal?.show();
            }
            return;
        }
        if (_settingsWantsToggle) {
            _settingsWantsToggle = false;
            if (_settingsPendingTabIndex >= 0) {
                settingsModal?.setTabIndex(_settingsPendingTabIndex);
                _settingsPendingTabIndex = -1;
            } else if (_settingsPendingTab) {
                settingsModal?.setPageName(_settingsPendingTab);
                _settingsPendingTab = "";
            }
            settingsModal?.toggle();
        }
    }

    function openClipboardHistory() {
        clipboardHistoryModal?.show();
    }

    function closeClipboardHistory() {
        clipboardHistoryModal?.hide();
    }

    function unloadClipboardHistoryPopout() {
        _scheduleUnload("clipboardHistory");
    }

    function unloadLayoutPopout() {
        _scheduleUnload("layout");
    }

    property bool _dankLauncherV2WantsOpen: false
    property bool _dankLauncherV2WantsToggle: false
    property string _dankLauncherV2PendingQuery: ""
    property string _dankLauncherV2PendingMode: ""
    property bool _dankLauncherV2TriggerUsesOverlayLayer: false
    property bool _dankLauncherV2EdgeHoverManaged: false

    function _setCyLauncherV2TriggerUsesOverlayLayer(value) {
        _dankLauncherV2TriggerUsesOverlayLayer = value === true;
        // Disable edge-hover by default on every open/toggle path unless explicitly enabled.
        _setCyLauncherV2EdgeHoverManaged(false);
        if (dankLauncherV2Modal)
            dankLauncherV2Modal.triggerUsesOverlayLayer = _dankLauncherV2TriggerUsesOverlayLayer;
    }

    // Set edgeHoverManaged to enable hover retraction for edge-hover triggered launcher sessions.
    function _setCyLauncherV2EdgeHoverManaged(value) {
        _dankLauncherV2EdgeHoverManaged = value === true;
        if (dankLauncherV2Modal)
            dankLauncherV2Modal.edgeHoverManaged = _dankLauncherV2EdgeHoverManaged;
    }

    function openCyLauncherV2(triggerUsesOverlayLayer, edgeHoverManaged) {
        _setCyLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        _setCyLauncherV2EdgeHoverManaged(edgeHoverManaged);
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.show();
        } else if (dankLauncherV2ModalLoader) {
            _dankLauncherV2WantsOpen = true;
            _dankLauncherV2WantsToggle = false;
            dankLauncherV2ModalLoader.active = true;
        }
    }

    function openCyLauncherV2WithQuery(query: string, triggerUsesOverlayLayer) {
        _setCyLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.showWithQuery(query);
        } else if (dankLauncherV2ModalLoader) {
            _dankLauncherV2PendingQuery = query;
            _dankLauncherV2WantsOpen = true;
            _dankLauncherV2WantsToggle = false;
            dankLauncherV2ModalLoader.active = true;
        }
    }

    function openCyLauncherV2WithMode(mode: string, triggerUsesOverlayLayer) {
        _setCyLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.showWithMode(mode);
        } else if (dankLauncherV2ModalLoader) {
            _dankLauncherV2PendingMode = mode;
            _dankLauncherV2WantsOpen = true;
            _dankLauncherV2WantsToggle = false;
            dankLauncherV2ModalLoader.active = true;
        }
    }

    function closeCyLauncherV2() {
        dankLauncherV2Modal?.hide();
    }

    function unloadCyLauncherV2() {
        if (dankLauncherV2ModalLoader) {
            dankLauncherV2Modal = null;
            dankLauncherV2ModalLoader.active = false;
        }
    }

    function toggleCyLauncherV2(triggerUsesOverlayLayer) {
        _setCyLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.toggle();
        } else if (dankLauncherV2ModalLoader) {
            _dankLauncherV2WantsToggle = true;
            _dankLauncherV2WantsOpen = false;
            dankLauncherV2ModalLoader.active = true;
        }
    }

    function toggleCyLauncherV2WithMode(mode: string, triggerUsesOverlayLayer) {
        _setCyLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.toggleWithMode(mode);
        } else if (dankLauncherV2ModalLoader) {
            _dankLauncherV2PendingMode = mode;
            _dankLauncherV2WantsToggle = true;
            _dankLauncherV2WantsOpen = false;
            dankLauncherV2ModalLoader.active = true;
        }
    }

    function toggleCyLauncherV2WithQuery(query: string, triggerUsesOverlayLayer) {
        _setCyLauncherV2TriggerUsesOverlayLayer(triggerUsesOverlayLayer);
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.toggleWithQuery(query);
        } else if (dankLauncherV2ModalLoader) {
            _dankLauncherV2PendingQuery = query;
            _dankLauncherV2WantsOpen = true;
            _dankLauncherV2WantsToggle = false;
            dankLauncherV2ModalLoader.active = true;
        }
    }

    function _onCyLauncherV2ModalLoaded() {
        if (dankLauncherV2Modal) {
            dankLauncherV2Modal.triggerUsesOverlayLayer = _dankLauncherV2TriggerUsesOverlayLayer;
            dankLauncherV2Modal.edgeHoverManaged = _dankLauncherV2EdgeHoverManaged;
        }
        if (_dankLauncherV2WantsOpen) {
            _dankLauncherV2WantsOpen = false;
            if (_dankLauncherV2PendingQuery) {
                dankLauncherV2Modal?.showWithQuery(_dankLauncherV2PendingQuery);
                _dankLauncherV2PendingQuery = "";
            } else if (_dankLauncherV2PendingMode) {
                dankLauncherV2Modal?.showWithMode(_dankLauncherV2PendingMode);
                _dankLauncherV2PendingMode = "";
            } else {
                dankLauncherV2Modal?.show();
            }
            return;
        }
        if (_dankLauncherV2WantsToggle) {
            _dankLauncherV2WantsToggle = false;
            if (_dankLauncherV2PendingMode) {
                dankLauncherV2Modal?.toggleWithMode(_dankLauncherV2PendingMode);
                _dankLauncherV2PendingMode = "";
            } else {
                dankLauncherV2Modal?.toggle();
            }
        }
    }

    property bool _spotlightBarWantsOpen: false
    property bool _spotlightBarWantsToggle: false
    property string _spotlightBarPendingQuery: ""
    property string _spotlightBarPendingMode: ""

    function openSpotlightBar() {
        if (spotlightBarModal) {
            spotlightBarModal.show();
        } else if (spotlightBarModalLoader) {
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function openSpotlightBarWithQuery(query: string) {
        if (spotlightBarModal) {
            spotlightBarModal.showWithQuery(query);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingQuery = query;
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function openSpotlightBarWithMode(mode: string) {
        if (spotlightBarModal) {
            spotlightBarModal.showWithMode(mode);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingMode = mode;
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function closeSpotlightBar() {
        spotlightBarModal?.hide();
    }

    function toggleSpotlightBar() {
        if (spotlightBarModal) {
            spotlightBarModal.toggle();
        } else if (spotlightBarModalLoader) {
            _spotlightBarWantsToggle = true;
            _spotlightBarWantsOpen = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function toggleSpotlightBarWithMode(mode: string) {
        if (spotlightBarModal) {
            spotlightBarModal.toggleWithMode(mode);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingMode = mode;
            _spotlightBarWantsToggle = true;
            _spotlightBarWantsOpen = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function toggleSpotlightBarWithQuery(query: string) {
        if (spotlightBarModal) {
            spotlightBarModal.toggleWithQuery(query);
        } else if (spotlightBarModalLoader) {
            _spotlightBarPendingQuery = query;
            _spotlightBarWantsOpen = true;
            _spotlightBarWantsToggle = false;
            spotlightBarModalLoader.active = true;
        }
    }

    function _onSpotlightBarModalLoaded() {
        if (_spotlightBarWantsOpen) {
            _spotlightBarWantsOpen = false;
            if (_spotlightBarPendingQuery) {
                spotlightBarModal?.showWithQuery(_spotlightBarPendingQuery);
                _spotlightBarPendingQuery = "";
            } else if (_spotlightBarPendingMode) {
                spotlightBarModal?.showWithMode(_spotlightBarPendingMode);
                _spotlightBarPendingMode = "";
            } else {
                spotlightBarModal?.show();
            }
            return;
        }
        if (_spotlightBarWantsToggle) {
            _spotlightBarWantsToggle = false;
            if (_spotlightBarPendingMode) {
                spotlightBarModal?.toggleWithMode(_spotlightBarPendingMode);
                _spotlightBarPendingMode = "";
            } else {
                spotlightBarModal?.toggle();
            }
        }
    }

    function openPowerMenu() {
        powerMenuModal?.openCentered();
    }

    function closePowerMenu() {
        powerMenuModal?.close();
    }

    function togglePowerMenu() {
        if (powerMenuModal) {
            if (powerMenuModal.shouldBeVisible) {
                powerMenuModal.close();
            } else {
                powerMenuModal.openCentered();
            }
        }
    }

    function openPowerProfileModal() {
        if (powerProfileModal) {
            powerProfileModal.openCentered();
        } else if (powerProfileModalLoader) {
            powerProfileModalLoader.active = true;
            Qt.callLater(() => powerProfileModal?.openCentered());
        }
    }

    function closePowerProfileModal() {
        powerProfileModal?.close();
    }

    function togglePowerProfileModal() {
        if (powerProfileModal) {
            if (powerProfileModal.shouldBeVisible) {
                powerProfileModal.close();
            } else {
                powerProfileModal.openCentered();
            }
        } else if (powerProfileModalLoader) {
            powerProfileModalLoader.active = true;
            Qt.callLater(() => {
                if (powerProfileModal) {
                    if (powerProfileModal.shouldBeVisible) {
                        powerProfileModal.close();
                    } else {
                        powerProfileModal.openCentered();
                    }
                }
            });
        }
    }


    function showAgentApproval() {
        if (_externalShellCall("agent-control", "reviewPermissions"))
            return;
        if (agentApprovalModal) {
            agentApprovalModal.show();
        } else if (agentApprovalModalLoader) {
            agentApprovalModalLoader.active = true;
            Qt.callLater(() => agentApprovalModal?.show());
        }
    }

    function hideAgentApproval() {
        agentApprovalModal?.hide();
    }

    function unloadAgentApproval() {
        if (!agentApprovalModalLoader || agentApprovalModal?.visible)
            return;
        agentApprovalModal = null;
        agentApprovalModalLoader.active = false;
    }

    function showAgentAssistant() {
        if (_externalShellCall("assistant", "open"))
            return;
        if (agentAssistantModal) {
            agentAssistantModal.show();
        } else if (agentAssistantModalLoader) {
            agentAssistantModalLoader.active = true;
            Qt.callLater(() => agentAssistantModal?.show());
        }
    }

    function hideAgentAssistant() {
        agentAssistantModal?.hide();
    }

    function toggleAgentAssistant() {
        if (_externalShellCall("assistant", "toggle"))
            return;
        if (agentAssistantModal) {
            agentAssistantModal.toggle();
        } else if (agentAssistantModalLoader) {
            agentAssistantModalLoader.active = true;
            Qt.callLater(() => agentAssistantModal?.show());
        }
    }

    function focusOrToggleAgentAssistant() {
        if (agentAssistantModal) {
            agentAssistantModal.focusOrToggle();
        } else {
            showAgentAssistant();
        }
    }

    function unloadAgentAssistant() {
        if (!agentAssistantModalLoader || agentAssistantModal?.visible)
            return;
        agentAssistantModal = null;
        agentAssistantModalLoader.active = false;
    }

    function showProcessListModal() {
        if (processListModal) {
            processListModal.show();
        } else if (processListModalLoader) {
            processListModalLoader.active = true;
            Qt.callLater(() => processListModal?.show());
        }
    }

    function hideProcessListModal() {
        processListModal?.hide();
    }

    function unloadProcessListModal() {
        if (processListModalLoader) {
            processListModal = null;
            processListModalLoader.active = false;
        }
    }

    function toggleProcessListModal() {
        if (processListModal) {
            processListModal.toggle();
        } else if (processListModalLoader) {
            processListModalLoader.active = true;
            Qt.callLater(() => processListModal?.show());
        }
    }

    function showColorPicker() {
        colorPickerModal?.show();
    }

    function hideColorPicker() {
        colorPickerModal?.close();
    }

    function unloadColorPicker() {
        _scheduleUnload("colorPicker");
    }

    function unloadPowerMenuPopout() {
        _scheduleUnload("powerMenuPopout");
    }

    function unloadDurationPopout() {
        _scheduleUnload("duration");
    }

    function ensureBluetoothPairingModal() {
        if (bluetoothPairingModal)
            return bluetoothPairingModal;
        if (!bluetoothPairingModalLoader)
            return null;
        bluetoothPairingModalLoader.active = true;
        return bluetoothPairingModalLoader.item;
    }

    function showNotificationModal() {
        notificationModal?.show();
    }

    function hideNotificationModal() {
        notificationModal?.close();
    }

    function showWifiPasswordModal(ssid) {
        if (wifiPasswordModalLoader)
            wifiPasswordModalLoader.active = true;
        if (wifiPasswordModal) {
            wifiPasswordModal.show(ssid);
        } else {
            Qt.callLater(() => wifiPasswordModal?.show(ssid));
        }
    }

    function showWifiQRCodeModal(ssid) {
        if (wifiQRCodeModalLoader)
            wifiQRCodeModalLoader.active = true;
        if (wifiQRCodeModal)
            wifiQRCodeModal.show(ssid);
    }

    function showQRGeneratorModal(initialText) {
        if (qrGeneratorModalLoader)
            qrGeneratorModalLoader.active = true;
        if (qrGeneratorModal)
            qrGeneratorModal.show(initialText || "");
    }

    function showHiddenNetworkModal() {
        if (wifiPasswordModalLoader)
            wifiPasswordModalLoader.active = true;
        if (wifiPasswordModal) {
            wifiPasswordModal.showHidden();
        } else {
            Qt.callLater(() => wifiPasswordModal?.showHidden());
        }
    }

    function hideWifiPasswordModal() {
        wifiPasswordModal?.hide();
    }

    function showNetworkInfoModal() {
        networkInfoModal?.show();
    }

    function hideNetworkInfoModal() {
        networkInfoModal?.close();
    }

    function closeNotepadSlideouts() {
        for (var i = 0; i < notepadSlideouts.length; i++) {
            if (notepadSlideouts[i] && notepadSlideouts[i].isVisible)
                notepadSlideouts[i].hide();
        }
    }

    function notepadSlideoutForFocusedScreen() {
        if (!notepadSlideouts || notepadSlideouts.length === 0)
            return null;
        const focused = BarWidgetService.getFocusedScreenName();
        if (focused) {
            for (var i = 0; i < notepadSlideouts.length; i++) {
                if (notepadSlideouts[i]?.modelData?.name === focused)
                    return notepadSlideouts[i];
            }
        }
        return notepadSlideouts[0];
    }

    // Remembered presentation wins over the configured default until the user
    // changes the default in settings (handled below).
    readonly property string notepadResolvedMode: SessionData.notepadLastMode || SettingsData.notepadDefaultMode

    function openNotepadSlideout() {
        SessionData.setNotepadLastMode("slideout");
        notepadPopout?.hide();
        if (notepadSlideouts.length > 0) {
            notepadSlideoutForFocusedScreen()?.show();
        }
    }

    // Keep the notepad in a single presentation for default modes
    Connections {
        target: SettingsData
        function onNotepadDefaultModeChanged() {
            SessionData.setNotepadLastMode(SettingsData.notepadDefaultMode);
            if (SettingsData.notepadDefaultMode === "popout") {
                var hadSlideout = false;
                for (var i = 0; i < root.notepadSlideouts.length; i++) {
                    if (root.notepadSlideouts[i] && root.notepadSlideouts[i].isVisible) {
                        hadSlideout = true;
                        root.notepadSlideouts[i].hide();
                    }
                }
                if (hadSlideout)
                    root.openNotepadPopout();
            } else if (root.notepadPopout && root.notepadPopout.visible) {
                root.notepadPopout.hide();
                root.openNotepadSlideout();
            }
        }
    }

    function openNotepad() {
        if (_externalShellCall("notepad", "open"))
            return;
        if (notepadResolvedMode === "popout") {
            openNotepadPopout();
            return;
        }
        openNotepadSlideout();
    }

    function closeNotepad() {
        if (_externalShellCall("notepad", "close"))
            return;
        if (notepadResolvedMode === "popout") {
            notepadPopout?.hide();
            return;
        }
        if (notepadSlideouts.length > 0) {
            notepadSlideoutForFocusedScreen()?.hide();
        }
    }

    function toggleNotepad() {
        if (_externalShellCall("notepad", "toggle"))
            return;
        if (notepadResolvedMode === "popout") {
            toggleNotepadPopout();
            return;
        }
        if (notepadSlideouts.length > 0) {
            notepadSlideoutForFocusedScreen()?.toggle();
        }
    }

    property var notepadPopout: null
    property var notepadPopoutLoader: null
    property bool _notepadPopoutWantsOpen: false
    property string _notepadPendingOpenFilePath: ""

    function openNotepadPopout() {
        if (_externalShellCall("notepad", "open"))
            return;
        SessionData.setNotepadLastMode("popout");
        closeNotepadSlideouts();
        if (notepadPopout) {
            notepadPopout.show();
        } else if (notepadPopoutLoader) {
            _notepadPopoutWantsOpen = true;
            notepadPopoutLoader.active = true;
        }
    }

    function openNotepadPopoutWithFile(path) {
        if (_externalShellCall("notepad", "openFile", [path]))
            return;
        closeNotepadSlideouts();
        if (notepadPopout) {
            notepadPopout.show();
            notepadPopout.notepad?.openExternalFile(path);
        } else if (notepadPopoutLoader) {
            _notepadPendingOpenFilePath = path;
            _notepadPopoutWantsOpen = true;
            notepadPopoutLoader.active = true;
        }
    }

    function _onNotepadPopoutLoaded() {
        if (_notepadPopoutWantsOpen && notepadPopout) {
            _notepadPopoutWantsOpen = false;
            notepadPopout.show();
            if (_notepadPendingOpenFilePath) {
                const pendingPath = _notepadPendingOpenFilePath;
                _notepadPendingOpenFilePath = "";
                notepadPopout.notepad?.openExternalFile(pendingPath);
            }
        }
    }

    function toggleNotepadPopout() {
        if (_externalShellCall("notepad", "toggle"))
            return;
        if (notepadPopout) {
            if (!notepadPopout.visible)
                closeNotepadSlideouts();
            notepadPopout.toggle();
        } else {
            openNotepadPopout();
        }
    }
}
