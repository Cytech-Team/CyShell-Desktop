import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Settings
import qs.Modules.Settings.DisplayConfig
import qs.CyCommon.Common as DC

ShellRoot {
    id: root

    property var tab: null
    property bool failed: false

    Component {
        id: tabComponent
        DisplayConfigTab {}
    }

    PanelWindow {
        color: "transparent"
        implicitWidth: 900
        implicitHeight: 1600
        anchors {
            top: true
            left: true
        }

        Item {
            id: stage
            anchors.fill: parent
        }
    }

    function collectText(item, out) {
        if (!item || !item.visible)
            return out;
        if (item.text !== undefined && typeof item.text === "string" && item.text.length > 0)
            out.push(item.text);
        for (const child of item.children || [])
            collectText(child, out);
        return out;
    }

    function check(condition, label) {
        if (condition)
            return;
        failed = true;
        console.log("FIXTURE_FAIL " + label);
    }

    function has(texts, value) {
        check(texts.includes(value), "missing text '" + value + "'");
    }

    function finish() {
        console.log(failed ? "FIXTURE_FAIL see above" : "FIXTURE_PASS");
        Qt.quit();
    }

    Timer {
        interval: 800
        running: true
        repeat: true
        property int step: 0

        onTriggered: {
            if (step++ === 0) {
                Quickshell.watchFiles = false;
                DC.Style.theme = Theme;
                DC.Style.settings = SettingsData;
                DC.I18n.backend = I18n;

                WlrOutputService.wlrOutputAvailable = true;
                WlrOutputService.outputs = [
                    {
                        name: "eDP-1",
                        description: "Laptop panel",
                        make: "Chimei Innolux",
                        model: "0x15E7",
                        serialNumber: "",
                        physicalWidth: 340,
                        physicalHeight: 190,
                        enabled: true,
                        x: 0,
                        y: 0,
                        transform: 0,
                        scale: 1,
                        currentMode: { id: 1, width: 1920, height: 1080, refresh: 60001, preferred: true },
                        modes: [
                            { id: 1, width: 1920, height: 1080, refresh: 60001, preferred: true }
                        ],
                        adaptiveSync: 0,
                        adaptiveSyncSupported: false
                    },
                    {
                        name: "HDMI-A-1",
                        description: "LG 27GL850",
                        make: "LG Electronics",
                        model: "27GL850",
                        serialNumber: "TEST",
                        physicalWidth: 700,
                        physicalHeight: 390,
                        enabled: true,
                        x: 1920,
                        y: 0,
                        transform: 0,
                        scale: 1,
                        currentMode: { id: 2, width: 2560, height: 1440, refresh: 99946, preferred: true },
                        modes: [
                            { id: 2, width: 2560, height: 1440, refresh: 99946, preferred: true },
                            { id: 3, width: 2560, height: 1440, refresh: 59951, preferred: false },
                            { id: 4, width: 1920, height: 1080, refresh: 120000, preferred: false }
                        ],
                        adaptiveSync: 0,
                        adaptiveSyncSupported: true
                    }
                ];
                WlrOutputService.stateChanged();

                root.tab = tabComponent.createObject(stage, {
                    width: stage.width,
                    height: stage.height
                });
                if (!root.tab) {
                    console.log("FIXTURE_FAIL failed to instantiate DisplayConfigTab");
                    Qt.quit();
                }
                return;
            }

            if (step === 2) {
                const texts = collectText(root.tab, []);
                has(texts, "Display layout");
                has(texts, "Main display");
                has(texts, "Resolution");
                has(texts, "Refresh rate");
                has(texts, "Scale");
                has(texts, "Position");
                has(texts, "Orientation");
                has(texts, "Variable refresh rate (VRR)");

                DisplayConfigState.setPendingChange("HDMI-A-1", "scale", 1.25);
                return;
            }

            if (step === 3) {
                const texts = collectText(root.tab, []);
                has(texts, "Unsaved display changes");
                has(texts, "Apply changes");
                DisplayConfigState.discardChanges();
                stop();
                finish();
            }
        }
    }
}
