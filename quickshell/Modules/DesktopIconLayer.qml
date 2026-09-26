import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

Variants {
    id: root

    // Desktop files belong to one desktop, not duplicated on every output.
    // Keep them on the first active output for now; multi-output placement can
    // be persisted later in SessionData.
    model: Quickshell.screens.length > 0 ? [Quickshell.screens[0]] : []

    PanelWindow {
        id: desktopWindow
        required property var modelData

        screen: modelData
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        WlrLayershell.namespace: "cyshell:desktop-icons"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Only the icon strip receives pointer input. The rest of the desktop
        // remains available to labwc and other CyShell desktop surfaces.
        mask: Region { item: iconSurface }

        Item {
            id: iconSurface
            x: 8
            y: 42
            width: Math.min(620, desktopWindow.width)
            height: Math.max(0, desktopWindow.height - 50)

            function isImage(name) {
                const n = String(name || "").toLowerCase();
                return /\.(png|jpe?g|webp|gif|bmp|svg|avif)$/.test(n);
            }

            function launch(path, url, name, isDir) {
                if (isDir) {
                    Quickshell.execDetached(["nemo", path]);
                    return;
                }
                if (String(name).toLowerCase().endsWith(".desktop")) {
                    Quickshell.execDetached(["gio", "launch", path]);
                    return;
                }
                Quickshell.execDetached(["xdg-open", path]);
            }

            FolderListModel {
                id: desktopModel
                folder: "file://" + Quickshell.env("HOME") + "/Desktop"
                showDirsFirst: true
                showDotAndDotDot: false
                showHidden: false
                showFiles: true
                showDirs: true
                caseSensitive: false
                sortField: FolderListModel.Name
            }

            GridView {
                id: grid
                anchors.fill: parent
                clip: true
                model: desktopModel
                cellWidth: 104
                cellHeight: 104
                flow: GridView.FlowTopToBottom

                delegate: Item {
                    required property string fileName
                    required property string filePath
                    required property url fileUrl
                    required property bool fileIsDir

                    readonly property bool isDesktopEntry: !fileIsDir && String(fileName).toLowerCase().endsWith(".desktop")
                    property string desktopName: ""
                    property string desktopIcon: ""

                    width: grid.cellWidth
                    height: grid.cellHeight

                    function parseDesktopEntry(text) {
                        if (!isDesktopEntry)
                            return;
                        const lines = String(text || "").split(/\r?\n/);
                        let inMain = false;
                        for (const raw of lines) {
                            const line = raw.trim();
                            if (line.startsWith("[")) {
                                inMain = line === "[Desktop Entry]";
                                continue;
                            }
                            if (!inMain)
                                continue;
                            if (!desktopName && line.startsWith("Name="))
                                desktopName = line.substring(5);
                            else if (!desktopIcon && line.startsWith("Icon="))
                                desktopIcon = line.substring(5);
                            if (desktopName && desktopIcon)
                                break;
                        }
                    }

                    FileView {
                        id: desktopEntryView
                        path: parent.isDesktopEntry ? parent.filePath : ""
                        watchChanges: parent.isDesktopEntry
                        onLoaded: parent.parseDesktopEntry(text())
                        onTextChanged: parent.parseDesktopEntry(text())
                    }

                    Rectangle {
                        id: selectionBg
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 8
                        color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                    }

                    Image {
                        id: icon
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: 54
                        height: 54
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        source: fileIsDir
                            ? Quickshell.iconPath("folder")
                            : iconSurface.isImage(fileName)
                                ? fileUrl
                                : isDesktopEntry && desktopIcon
                                    ? Quickshell.iconPath(desktopIcon)
                                    : Quickshell.iconPath("text-x-generic")
                    }

                    Text {
                        anchors.top: icon.bottom
                        anchors.topMargin: 5
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        text: isDesktopEntry && desktopName ? desktopName : fileName.replace(/\.desktop$/i, "")
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignTop
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.85)
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onDoubleClicked: iconSurface.launch(filePath, fileUrl, fileName, fileIsDir)
                    }
                }
            }
        }
    }
}
