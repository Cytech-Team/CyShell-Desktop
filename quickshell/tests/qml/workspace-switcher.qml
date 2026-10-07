import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.CyBar.Widgets
import qs.Modules.OSD
import qs.CyCommon.Common as DC

ShellRoot {
    id: root

    property var switcher: null
    property var osd: null
    property string output: ""

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    function pills() {
        const found = [];
        function visit(item) {
            if (!item)
                return;
            if (item.isPlaceholder !== undefined && item.isActive !== undefined)
                found.push(item);
            for (const child of item.children || [])
                visit(child);
        }
        visit(root.switcher);
        return found;
    }

    function texts(item) {
        if (!item || !item.visible)
            return [];
        if (typeof item.text === "string")
            return [item.text];
        return (item.children || []).reduce((result, child) => result.concat(texts(child)), []);
    }

    function state(activeId) {
        return {
            "available": true,
            "groups": [{
                "objectId": "group-1",
                "outputs": [root.output]
            }],
            "workspaces": [{
                "objectId": "ws-1",
                "groupId": "group-1",
                "id": "1",
                "name": "alpha",
                "active": activeId === "1",
                "urgent": false,
                "hidden": false
            }, {
                "objectId": "ws-2",
                "groupId": "group-1",
                "id": "2",
                "name": "web",
                "active": activeId === "2",
                "urgent": false,
                "hidden": false
            }, {
                "objectId": "ws-hidden",
                "groupId": "group-1",
                "id": "hidden",
                "name": "hidden",
                "active": false,
                "urgent": false,
                "hidden": true
            }]
        };
    }

    Component {
        id: switcherComponent
        WorkspaceSwitcher {}
    }

    Component {
        id: osdComponent
        WorkspaceOSD {}
    }

    FloatingWindow {
        visible: true
        implicitWidth: 600
        implicitHeight: 200

        Item {
            id: stage
            anchors.fill: parent
        }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
    }

    Timer {
        id: checks
        interval: 25
        repeat: true
        running: SettingsData._hasLoaded && SessionData._hasLoaded
        property int step: 0
        property int waited: 0

        function advance() {
            step++;
            waited = 0;
        }

        onTriggered: {
            try {
                if (++waited > 200)
                    throw new Error("timed out in step " + step);
                switch (step) {
                case 0:
                    if (Quickshell.screens.length === 0)
                        return;
                    root.check(CompositorService.isLabwc && CompositorService.compositor === "labwc", "fixture uses CyShell Labwc backend");
                    root.output = Quickshell.screens[0].name;
                    SettingsData.osdWorkspaceEnabled = true;
                    ExtWorkspaceService.applyState(root.state("1"));
                    root.switcher = switcherComponent.createObject(stage, {
                        "axis": {
                            "isVertical": false,
                            "edge": "top"
                        },
                        "screenName": root.output,
                        "parentScreen": Quickshell.screens[0],
                        "widgetThickness": 30,
                        "barThickness": 40,
                        "barConfig": {
                            "id": "fixture",
                            "widgetStyle": "pills"
                        },
                        "widgetData": {
                            "id": "workspaceSwitcher",
                            "showWorkspaceIndex": true,
                            "showWorkspaceName": true,
                            "showWorkspacePadding": true,
                            "workspacePaddingCount": 3
                        }
                    });
                    root.osd = osdComponent.createObject(root, {
                        "screen": Quickshell.screens[0],
                        "modelData": Quickshell.screens[0]
                    });
                    root.check(root.switcher && root.osd, "Labwc workspace surfaces instantiate");
                    advance();
                    return;
                case 1: {
                    const visiblePills = root.pills();
                    if (visiblePills.length !== 3)
                        return;
                    root.check(CompositorService.hasWorkspaceIpc, "Labwc ext-workspace backend is available");
                    root.check(root.switcher.workspaceList.length === 3, "two Labwc workspaces plus one padding placeholder");
                    root.check(root.switcher.currentWorkspace === "1", "first Labwc workspace is current");
                    root.check(visiblePills.map(pill => pill.isActive).join() === "true,false,false", "first Labwc workspace pill is active");
                    root.check(visiblePills.map(pill => pill.isPlaceholder).join() === "false,false,true", "third pill is padding only");
                    const labels = visiblePills.map(pill => root.texts(pill).join("|"));
                    root.check(labels[0].includes("alpha") && labels[1].includes("web") && labels[2].includes("3"), "Labwc workspace labels render names and padding: " + labels.join(","));
                    root.check(root.osd.activeWorkspace?.id === "1" && root.osd.activeWorkspace?.name === "alpha", "OSD reads active Labwc workspace");
                    ExtWorkspaceService.applyState(root.state("2"));
                    advance();
                    return;
                }
                case 2: {
                    const visiblePills = root.pills();
                    if (root.switcher.currentWorkspace !== "2" || visiblePills.length !== 3 || !visiblePills[1].isActive)
                        return;
                    root.check(visiblePills.map(pill => pill.isActive).join() === "false,true,false", "Labwc active workspace update reaches pills");
                    root.check(root.osd.activeWorkspace?.id === "2" && root.osd.activeWorkspace?.name === "web", "OSD follows Labwc workspace update");
                    root.check(ExtWorkspaceService.workspacesForOutput(root.output).length === 2, "hidden workspace is excluded from the output projection");
                    console.log("FIXTURE_PASS Labwc workspace switcher and OSD");
                    stop();
                    Qt.quit();
                    return;
                }
                }
            } catch (error) {
                console.error("FIXTURE_FAIL", error.message);
                stop();
                Qt.quit();
            }
        }
    }
}
