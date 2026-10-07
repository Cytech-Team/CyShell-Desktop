import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.CyBar.Widgets
import qs.CyCommon.Common as DC

ShellRoot {
    id: root

    property var browser: ({
        appId: "firefox",
        title: "Mozilla Firefox",
        pid: 100
    })
    property var barConfig: ({
        widgetPadding: 12,
        fontScale: 1,
        iconScale: 1,
        spacing: 4
    })
    property var axes: [{
        isVertical: false,
        edge: "top"
    }, {
        isVertical: true,
        edge: "left"
    }]
    property var instances: []

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    function hidden(instance) {
        const item = instance.item;
        return !item.hasWindowsOnCurrentWorkspace && !item.visible && (item.width === 0 || item.height === 0);
    }

    function shown(instance) {
        const item = instance.item;
        return item.hasWindowsOnCurrentWorkspace && item.activeWindow?.appId === "firefox" && item.visible && item.width > 0 && item.height > 0;
    }

    Item {
        id: stage
        width: 900
        height: 400
    }

    Component {
        id: focusedApp
        FocusedApp {}
    }

    FloatingWindow {
        visible: true
        implicitWidth: 900
        implicitHeight: 400
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
    }

    Timer {
        interval: 25
        running: SettingsData._hasLoaded && SessionData._hasLoaded
        repeat: true
        property int step: 0
        property int waited: 0

        function advance() {
            step++;
            waited = 0;
        }

        onTriggered: {
            try {
                if (++waited > 160)
                    throw new Error("timed out in step " + step);
                switch (step) {
                case 0: {
                    if (Quickshell.screens.length === 0)
                        return;
                    root.check(CompositorService.isLabwc && CompositorService.compositor === "labwc", "fixture uses CyShell Labwc backend");
                    const created = [];
                    let y = 0;
                    for (const axis of root.axes) {
                        const item = focusedApp.createObject(stage, {
                            "axis": axis,
                            "parentScreen": Quickshell.screens[0],
                            "barThickness": 48,
                            "widgetThickness": 30,
                            "barSpacing": 4,
                            "barConfig": root.barConfig,
                            "widgetData": {},
                            "y": y
                        });
                        y += 120;
                        created.push({
                            "vertical": axis.isVertical,
                            "item": item
                        });
                    }
                    root.instances = created;
                    advance();
                    return;
                }
                case 1:
                    for (const instance of root.instances)
                        instance.item.activeWindow = null;
                    if (!root.instances.every(instance => root.hidden(instance)))
                        return;
                    root.check(CompositorService.windowOnActiveWorkspace(root.instances[0].item.screenName, root.browser, false), "Labwc generic toplevel belongs to the active workspace");
                    for (const instance of root.instances)
                        instance.item.activeWindow = root.browser;
                    advance();
                    return;
                case 2:
                    if (!root.instances.every(instance => root.shown(instance)))
                        return;
                    root.check(root.instances.some(instance => instance.vertical) && root.instances.some(instance => !instance.vertical), "horizontal and vertical FocusedApp surfaces both render");
                    for (const instance of root.instances)
                        instance.item.activeWindow = null;
                    advance();
                    return;
                case 3:
                    for (const instance of root.instances)
                        instance.item.activeWindow = null;
                    if (!root.instances.every(instance => root.hidden(instance)))
                        return;
                    console.log("FIXTURE_PASS Labwc focused app visibility");
                    stop();
                    Qt.quit();
                    return;
                }
            } catch (error) {
                console.error("FIXTURE_FAIL", error.message);
                stop();
                Qt.quit();
            }
        }
    }
}
