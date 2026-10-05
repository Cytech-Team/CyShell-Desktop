import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

Variants {
    id: root

    readonly property var desktopScreens: {
        void Quickshell.screens;
        const screens = Quickshell.screens || [];
        const physical = screens.filter(screen => screen?.name && !String(screen.name).startsWith("HEADLESS-"));
        return physical.length > 0 ? physical : screens;
    }

    property bool dragActive: false
    property string dragPath: ""
    property string dragSourceScreen: ""
    property string dragTargetScreen: ""
    property real dragGlobalX: 0
    property real dragGlobalY: 0
    property real dragGrabX: 0
    property real dragGrabY: 0
    property real dragSourceX: 0
    property real dragSourceY: 0
    property var dragIconSource: ""
    property string dragLabel: ""
    property var dragItems: []

    signal gridDropRequested(var items, string anchorPath, string sourceScreen, string targetScreen, real targetX, real targetY)

    readonly property bool gridLayout: String(SettingsData.desktopIconLayoutMode || "grid") !== "free"
    readonly property int gridMargin: 8

    model: root.desktopScreens

    function clone(value) {
        return JSON.parse(JSON.stringify(value || {}));
    }

    function debugState() {
        const out = [];
        for (const instance of (root.instances || [])) {
            if (instance?.debugState)
                out.push(instance.debugState());
        }
        return out;
    }

    function screenByName(name) {
        return (desktopScreens || []).find(screen => screen?.name === name) || null;
    }

    function primaryScreenName() {
        const primary = CompositorService.getPrimaryScreen();
        if (primary && screenByName(primary.name))
            return primary.name;
        return desktopScreens?.[0]?.name || "";
    }

    function screenOrigin(name) {
        const screen = screenByName(name);
        if (screen)
            return Qt.point(screen.x ?? 0, screen.y ?? 0);

        const output = WlrOutputService.getOutput(name);
        return Qt.point(output?.x ?? 0, output?.y ?? 0);
    }

    function effectiveScreenName(path) {
        void SettingsData.desktopIconPositions;
        void root.desktopScreens;
        const saved = SettingsData.desktopIconPositions?.[String(path)];
        const savedScreen = String(saved?.screen || "");
        if (savedScreen && screenByName(savedScreen))
            return savedScreen;
        return primaryScreenName();
    }

    function targetScreenForGlobalPoint(globalX, globalY) {
        let nearest = null;
        let nearestDistance = Number.POSITIVE_INFINITY;

        for (const screen of (desktopScreens || [])) {
            const origin = screenOrigin(screen.name);
            const left = origin.x;
            const top = origin.y;
            const right = left + screen.width;
            const bottom = top + screen.height;

            if (globalX >= left && globalX < right && globalY >= top && globalY < bottom)
                return screen;

            const dx = globalX < left ? left - globalX : globalX > right ? globalX - right : 0;
            const dy = globalY < top ? top - globalY : globalY > bottom ? globalY - bottom : 0;
            const distance = dx * dx + dy * dy;
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearest = screen;
            }
        }

        return nearest;
    }

    function gridPointFor(screenName, x, y, itemWidth, itemHeight) {
        const screen = screenByName(screenName);
        if (!screen)
            return Qt.point(x, y);

        const width = Math.max(1, itemWidth);
        const height = Math.max(1, itemHeight);
        const columns = Math.max(1, Math.floor(Math.max(width, screen.width - gridMargin * 2) / width));
        const rows = Math.max(1, Math.floor(Math.max(height, screen.height - gridMargin * 2) / height));
        const column = Math.max(0, Math.min(columns - 1, Math.round((x - gridMargin) / width)));
        const row = Math.max(0, Math.min(rows - 1, Math.round((y - gridMargin) / height)));
        return Qt.point(
            Math.round(gridMargin + column * width),
            Math.round(gridMargin + row * height)
        );
    }

    function saveIconPosition(path, screenName, x, y, itemWidth, itemHeight) {
        const screen = screenByName(screenName);
        if (!screen)
            return;

        const point = gridLayout
            ? gridPointFor(screenName, x, y, itemWidth, itemHeight)
            : Qt.point(x, y);
        const next = clone(SettingsData.desktopIconPositions);
        next[String(path)] = {
            screen: screenName,
            x: Math.round(Math.max(0, Math.min(Math.max(0, screen.width - itemWidth), point.x))),
            y: Math.round(Math.max(0, Math.min(Math.max(0, screen.height - itemHeight), point.y)))
        };
        SettingsData.set("desktopIconPositions", next);
        SettingsData.saveSettings();
    }

    function isDraggingPath(path) {
        return (dragItems || []).some(item => String(item.path) === String(path));
    }

    function beginIconDrag(path, sourceScreen, sourceX, sourceY, globalX, globalY, grabX, grabY, iconSource, label, items) {
        dragPath = String(path);
        dragSourceScreen = sourceScreen;
        dragGlobalX = globalX;
        dragGlobalY = globalY;
        dragGrabX = grabX;
        dragGrabY = grabY;
        dragSourceX = sourceX;
        dragSourceY = sourceY;
        dragIconSource = iconSource;
        dragLabel = label;
        dragItems = Array.isArray(items) && items.length > 0 ? items : [{
            path: String(path),
            sourceX: sourceX,
            sourceY: sourceY,
            sourceColumn: 0,
            sourceRow: 0
        }];
        const target = targetScreenForGlobalPoint(globalX, globalY);
        dragTargetScreen = target?.name || sourceScreen;
        dragActive = true;
    }

    function updateIconDrag(globalX, globalY) {
        if (!dragActive)
            return;
        dragGlobalX = globalX;
        dragGlobalY = globalY;
        const target = targetScreenForGlobalPoint(globalX, globalY);
        if (target)
            dragTargetScreen = target.name;
    }

    function finishIconDrag(itemWidth, itemHeight) {
        if (!dragActive)
            return;

        const targetName = dragTargetScreen || dragSourceScreen;
        const origin = screenOrigin(targetName);
        const pointerX = dragGlobalX - origin.x;
        const pointerY = dragGlobalY - origin.y;
        if (gridLayout) {
            // Grid placement follows the cell under the release point. Using
            // the icon's top-left here made the destination depend on where
            // inside the icon the drag started.
            gridDropRequested(dragItems, dragPath, dragSourceScreen, targetName, pointerX, pointerY);
        } else {
            const anchor = (dragItems || []).find(item => String(item.path) === dragPath)
                || { sourceX: dragSourceX, sourceY: dragSourceY };
            const targetAnchorX = pointerX - dragGrabX;
            const targetAnchorY = pointerY - dragGrabY;
            const screen = screenByName(targetName);
            if (!screen) {
                cancelIconDrag();
                return;
            }
            const next = clone(SettingsData.desktopIconPositions);
            for (const item of (dragItems || [])) {
                const x = targetAnchorX + Number(item.sourceX || 0) - Number(anchor.sourceX || 0);
                const y = targetAnchorY + Number(item.sourceY || 0) - Number(anchor.sourceY || 0);
                next[String(item.path)] = {
                    screen: targetName,
                    x: Math.round(Math.max(0, Math.min(Math.max(0, screen.width - itemWidth), x))),
                    y: Math.round(Math.max(0, Math.min(Math.max(0, screen.height - itemHeight), y)))
                };
            }
            SettingsData.set("desktopIconPositions", next);
            SettingsData.saveSettings();
        }
        cancelIconDrag();
    }

    function cancelIconDrag() {
        dragActive = false;
        dragPath = "";
        dragSourceScreen = "";
        dragTargetScreen = "";
        dragSourceX = 0;
        dragSourceY = 0;
        dragIconSource = "";
        dragLabel = "";
        dragItems = [];
    }

    PanelWindow {
        id: desktopWindow
        required property var modelData
        readonly property string screenName: modelData?.name || ""

        screen: modelData
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        WlrLayershell.namespace: "cyshell:desktop-icons"
        // Wallpaper maps only after its image loads; a separate layer keeps
        // that late surface behind the desktop hit target and icons.
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // CyShell owns pointer interaction on the uncovered desktop. Normal app
        // windows and Bottom-layer desktop widgets remain interactive above it.
        mask: Region { item: desktopSurface }

        property var selectedPaths: ({})
        property int lastSelectedIndex: -1

        function debugState() {
            const icons = [];
            for (let i = 0; i < desktopModel.count; i++) {
                const item = iconRepeater.itemAt(i);
                if (!item || !item.visible)
                    continue;
                icons.push({
                    name: item.fileName,
                    path: item.filePath,
                    x: item.x,
                    y: item.y,
                    width: item.width,
                    height: item.height,
                    selected: item.selected
                });
            }
            return {
                screen: screenName,
                originX: Number(modelData?.x ?? 0),
                originY: Number(modelData?.y ?? 0),
                selected: Object.keys(selectedPaths || {}),
                icons
            };
        }
        property string contextTargetPath: ""
        property var contextTargetItem: null

        Connections {
            target: root
            function onGridDropRequested(items, anchorPath, sourceScreen, targetScreen, targetX, targetY) {
                if (String(targetScreen) !== desktopWindow.screenName)
                    return;
                desktopSurface.commitGridDrop(items, anchorPath, sourceScreen, targetX, targetY);
            }
        }

        function clone(value) {
            return JSON.parse(JSON.stringify(value || {}));
        }

        function isSelected(path) {
            return !!selectedPaths[String(path)];
        }

        function clearSelection() {
            selectedPaths = ({});
            lastSelectedIndex = -1;
        }

        function selectOnly(path, index) {
            const next = {};
            next[String(path)] = true;
            selectedPaths = next;
            lastSelectedIndex = index;
        }

        function toggleSelection(path, index) {
            const key = String(path);
            const next = clone(selectedPaths);
            if (next[key])
                delete next[key];
            else
                next[key] = true;
            selectedPaths = next;
            lastSelectedIndex = index;
        }

        function selectRange(toIndex) {
            if (lastSelectedIndex < 0) {
                const item = iconRepeater.itemAt(toIndex);
                if (item)
                    selectOnly(item.filePath, toIndex);
                return;
            }

            const next = {};
            const start = Math.min(lastSelectedIndex, toIndex);
            const end = Math.max(lastSelectedIndex, toIndex);
            for (let i = start; i <= end; i++) {
                const item = iconRepeater.itemAt(i);
                if (item?.visible)
                    next[String(item.filePath)] = true;
            }
            selectedPaths = next;
        }

        function selectFromClick(path, index, modifiers) {
            desktopSurface.forceActiveFocus();
            const ctrl = !!(modifiers & Qt.ControlModifier);
            const shift = !!(modifiers & Qt.ShiftModifier);

            if (shift) {
                selectRange(index);
                return;
            }
            if (ctrl) {
                toggleSelection(path, index);
                return;
            }
            selectOnly(path, index);
        }

        function selectAll() {
            const next = {};
            for (let i = 0; i < iconRepeater.count; i++) {
                const item = iconRepeater.itemAt(i);
                if (item?.visible)
                    next[String(item.filePath)] = true;
            }
            selectedPaths = next;
            if (iconRepeater.count > 0)
                lastSelectedIndex = iconRepeater.count - 1;
        }

        function selectedItems() {
            const result = [];
            for (let i = 0; i < iconRepeater.count; i++) {
                const item = iconRepeater.itemAt(i);
                if (item?.visible && isSelected(item.filePath))
                    result.push(item);
            }
            return result;
        }

        function selectedCount() {
            return Object.keys(selectedPaths || {}).length;
        }

        function openSelected() {
            const items = selectedItems();
            for (const item of items)
                desktopSurface.launch(item.filePath, item.fileUrl, item.fileName, item.fileIsDir);
        }

        function trashSelected() {
            const items = selectedItems();
            if (items.length === 0)
                return;
            for (const item of items)
                Quickshell.execDetached(["gio", "trash", item.filePath]);
            clearSelection();
        }

        function renameSelected() {
            const items = selectedItems();
            if (items.length === 1)
                items[0].beginRename();
        }

        function desktopDirectory() {
            return Quickshell.env("HOME") + "/Desktop";
        }

        function openDesktopDirectory() {
            Quickshell.execDetached(["nemo", desktopDirectory()]);
        }

        function openTerminalHere() {
            const script = [
                'dir="$HOME/Desktop"',
                'cfg="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"',
                'id=""',
                'if [ -s "$cfg" ]; then id=$(sed -n \'/^[[:space:]]*#/d; /^[[:space:]]*$/d; 1p\' "$cfg"); fi',
                'if [ -z "$id" ]; then',
                '  for candidate in qterminal.desktop org.kde.konsole.desktop kitty.desktop foot.desktop Alacritty.desktop com.mitchellh.ghostty.desktop org.wezfurlong.wezterm.desktop; do',
                '    if [ -f "$HOME/.local/share/applications/$candidate" ] || [ -f "/usr/share/applications/$candidate" ]; then id="$candidate"; break; fi',
                '  done',
                'fi',
                'base="${id%.desktop}"',
                'case "$base" in',
                '  qterminal|qterminal-drop) exec qterminal --workdir "$dir" ;;',
                '  org.kde.konsole|konsole) exec konsole --workdir "$dir" ;;',
                '  kitty) exec kitty --directory "$dir" ;;',
                '  foot|footclient) exec "$base" --working-directory="$dir" ;;',
                '  Alacritty|alacritty) exec alacritty --working-directory "$dir" ;;',
                '  com.mitchellh.ghostty|ghostty) exec ghostty --working-directory="$dir" ;;',
                '  org.wezfurlong.wezterm|wezterm) exec wezterm start --cwd "$dir" ;;',
                '  "") exec qterminal --workdir "$dir" ;;',
                '  *) cd "$dir"; if command -v gtk-launch >/dev/null 2>&1; then exec gtk-launch "$base"; fi; exec gio launch "$id" ;;',
                'esac'
            ].join("\n");
            Quickshell.execDetached(["bash", "-lc", script]);
        }

        function resetIconPositions() {
            SettingsData.set("desktopIconPositions", {});
            SettingsData.saveSettings();
        }

        function createNewFolder() {
            const script = [
                "base=\"$HOME/Desktop/New Folder\"",
                "path=\"$base\"",
                "n=2",
                "while [ -e \"$path\" ]; do path=\"$base $n\"; n=$((n+1)); done",
                "mkdir -p -- \"$path\""
            ].join("; ");
            Proc.runCommand("desktop-new-folder", ["bash", "-lc", script], (output, code) => {
                if (code !== 0)
                    ToastService.showError(I18n.tr("Desktop"), I18n.tr("Failed to create folder"));
            }, 0, 5000);
        }

        function openIconContextMenu(item, point) {
            if (!isSelected(item.filePath))
                selectOnly(item.filePath, item.index);

            contextTargetPath = item.filePath;
            contextTargetItem = item;
            iconContextMenu.open(modelData, point.x, point.y, false);
        }

        function iconMenuItems() {
            const count = selectedCount();
            return [
                {
                    type: "item",
                    text: count > 1 ? I18n.tr("Open selected") : I18n.tr("Open"),
                    icon: "open_in_new",
                    action: () => openSelected()
                },
                {
                    type: "separator"
                },
                {
                    type: "item",
                    text: I18n.tr("Rename"),
                    icon: "edit",
                    action: () => renameSelected()
                },
                {
                    type: "item",
                    text: I18n.tr("Open Desktop folder"),
                    icon: "folder_open",
                    action: () => openDesktopDirectory()
                },
                {
                    type: "separator"
                },
                {
                    type: "item",
                    text: count > 1 ? I18n.tr("Move selected to Trash") : I18n.tr("Move to Trash"),
                    icon: "delete",
                    isDestructive: true,
                    action: () => trashSelected()
                }
            ];
        }

        function desktopMenuItems() {
            return [
                {
                    type: "item",
                    text: I18n.tr("View"),
                    icon: "view_module",
                    action: () => PopoutService.openSettingsWithTab("desktop")
                },
                {
                    type: "item",
                    text: I18n.tr("Refresh"),
                    icon: "refresh",
                    action: () => desktopSurface.refreshDesktop()
                },
                {
                    type: "item",
                    text: I18n.tr("Open in Terminal"),
                    icon: "terminal",
                    action: () => openTerminalHere()
                },
                {
                    type: "separator"
                },
                {
                    type: "item",
                    text: I18n.tr("New folder"),
                    icon: "create_new_folder",
                    action: () => createNewFolder()
                },
                {
                    type: "item",
                    text: I18n.tr("Open Desktop folder"),
                    icon: "folder_open",
                    action: () => openDesktopDirectory()
                },
                {
                    type: "separator"
                },
                {
                    type: "item",
                    text: I18n.tr("Display settings"),
                    icon: "display_settings",
                    action: () => PopoutService.openSettingsWithTab("display_config")
                },
                {
                    type: "item",
                    text: I18n.tr("Personalize"),
                    icon: "palette",
                    action: () => PopoutService.openSettingsWithTab("personalization")
                }
            ];
        }

        Item {
            id: desktopSurface
            anchors.fill: parent
            focus: true

            readonly property int cellWidth: 104
            readonly property int cellHeight: 104
            readonly property int desktopMargin: 8

            property bool marqueeActive: false
            property point marqueeStart: Qt.point(0, 0)
            property point marqueeCurrent: Qt.point(0, 0)
            property var marqueeBaseSelection: ({})

            function isImage(name) {
                const n = String(name || "").toLowerCase();
                return /\.(png|jpe?g|webp|gif|bmp|svg|avif)$/.test(n);
            }

            function refreshDesktop() {
                const currentFolder = desktopModel.folder;
                desktopModel.folder = "";
                Qt.callLater(() => desktopModel.folder = currentFolder);
            }

            function launch(path, url, name, isDir) {
                if (isDir) {
                    Quickshell.execDetached(["nemo", path]);
                    return;
                }
                if (String(name).toLowerCase().endsWith(".desktop")) {
                    const entryId = String(name).replace(/\.desktop$/i, "");
                    const desktopEntry = DesktopEntries.byId(entryId) || DesktopEntries.heuristicLookup(entryId);
                    if (desktopEntry) {
                        SessionService.launchDesktopEntry(desktopEntry);
                        return;
                    }
                    Quickshell.execDetached(["gio", "launch", path]);
                    return;
                }
                Quickshell.execDetached(["xdg-open", path]);
            }

            function gridRows() {
                const usableHeight = Math.max(cellHeight, height - desktopMargin * 2);
                return Math.max(1, Math.floor(usableHeight / cellHeight));
            }

            function gridColumns() {
                const usableWidth = Math.max(cellWidth, width - desktopMargin * 2);
                return Math.max(1, Math.floor(usableWidth / cellWidth));
            }

            function gridCapacity() {
                return Math.max(1, gridRows() * gridColumns());
            }

            function pointForGridSlot(slot) {
                const rows = gridRows();
                const safe = Math.max(0, Math.min(gridCapacity() - 1, Number(slot) || 0));
                return Qt.point(
                    desktopMargin + Math.floor(safe / rows) * cellWidth,
                    desktopMargin + (safe % rows) * cellHeight
                );
            }

            function gridSlotForPoint(x, y) {
                const rows = gridRows();
                const column = Math.max(0, Math.min(gridColumns() - 1, Math.round((x - desktopMargin) / cellWidth)));
                const row = Math.max(0, Math.min(rows - 1, Math.round((y - desktopMargin) / cellHeight)));
                return column * rows + row;
            }

            function gridDropSlotForPoint(x, y) {
                const rows = gridRows();
                const column = Math.max(0, Math.min(gridColumns() - 1, Math.floor((x - desktopMargin) / cellWidth)));
                const row = Math.max(0, Math.min(rows - 1, Math.floor((y - desktopMargin) / cellHeight)));
                return column * rows + row;
            }

            function gridColumnForSlot(slot) {
                return Math.floor(Math.max(0, Number(slot) || 0) / gridRows());
            }

            function gridRowForSlot(slot) {
                return Math.max(0, Number(slot) || 0) % gridRows();
            }

            function defaultPosition(index) {
                const rows = gridRows();
                return Qt.point(
                    desktopMargin + Math.floor(index / rows) * cellWidth,
                    desktopMargin + (index % rows) * cellHeight
                );
            }

            function modelPathAt(index) {
                if (index < 0 || index >= desktopModel.count)
                    return "";
                return String(desktopModel.get(index, "filePath") || "");
            }

            function nextAvailableGridSlot(desired, occupied) {
                const capacity = gridCapacity();
                const start = Math.max(0, Math.min(capacity - 1, desired));
                for (let offset = 0; offset < capacity; offset++) {
                    const slot = (start + offset) % capacity;
                    if (!occupied[slot])
                        return slot;
                }
                return start;
            }

            function resolvedGridSlot(path, modelIndex) {
                const occupied = {};
                let ordinal = 0;
                const limit = Math.min(modelIndex, desktopModel.count - 1);

                for (let i = 0; i <= limit; i++) {
                    const candidate = modelPathAt(i);
                    if (!candidate || root.effectiveScreenName(candidate) !== desktopWindow.screenName)
                        continue;

                    const saved = SettingsData.desktopIconPositions?.[candidate];
                    let desired = ordinal;
                    if (saved && String(saved.screen || desktopWindow.screenName) === desktopWindow.screenName)
                        desired = gridSlotForPoint(Number(saved.x || 0), Number(saved.y || 0));

                    const slot = nextAvailableGridSlot(desired, occupied);
                    occupied[slot] = true;
                    if (candidate === String(path))
                        return slot;
                    ordinal++;
                }

                return nextAvailableGridSlot(ordinal, occupied);
            }

            function positionFor(path, index, itemWidth, itemHeight) {
                void SettingsData.desktopIconPositions;
                void SettingsData.desktopIconLayoutMode;

                if (root.gridLayout)
                    return pointForGridSlot(resolvedGridSlot(path, index));

                const saved = SettingsData.desktopIconPositions?.[String(path)];
                const fallback = defaultPosition(index);
                const rawX = saved?.x ?? fallback.x;
                const rawY = saved?.y ?? fallback.y;
                return Qt.point(
                    Math.max(0, Math.min(Math.max(0, width - itemWidth), rawX)),
                    Math.max(0, Math.min(Math.max(0, height - itemHeight), rawY))
                );
            }

            function savePosition(path, x, y) {
                root.saveIconPosition(path, desktopWindow.screenName, x, y, cellWidth, cellHeight);
            }

            function commitGridDrop(items, anchorPath, sourceScreen, targetX, targetY) {
                const movingItems = (items || []).filter(item => item?.path);
                if (movingItems.length === 0)
                    return;

                const anchorKey = String(anchorPath);
                const anchor = movingItems.find(item => String(item.path) === anchorKey) || movingItems[0];
                const movingPaths = {};
                for (const item of movingItems)
                    movingPaths[String(item.path)] = true;

                const targetAnchorSlot = gridDropSlotForPoint(targetX, targetY);
                const targetAnchorColumn = gridColumnForSlot(targetAnchorSlot);
                const targetAnchorRow = gridRowForSlot(targetAnchorSlot);
                const sourceCoordinates = movingItems.map(item => {
                    const fallbackSlot = gridSlotForPoint(Number(item.sourceX || 0), Number(item.sourceY || 0));
                    return {
                        item,
                        column: Number.isFinite(Number(item.sourceColumn)) ? Number(item.sourceColumn) : gridColumnForSlot(fallbackSlot),
                        row: Number.isFinite(Number(item.sourceRow)) ? Number(item.sourceRow) : gridRowForSlot(fallbackSlot)
                    };
                });
                const anchorSource = sourceCoordinates.find(entry => String(entry.item.path) === String(anchor.path)) || sourceCoordinates[0];
                const offsets = sourceCoordinates.map(entry => ({
                    entry,
                    column: entry.column - anchorSource.column,
                    row: entry.row - anchorSource.row
                }));

                const minColumnOffset = Math.min(...offsets.map(entry => entry.column));
                const maxColumnOffset = Math.max(...offsets.map(entry => entry.column));
                const minRowOffset = Math.min(...offsets.map(entry => entry.row));
                const maxRowOffset = Math.max(...offsets.map(entry => entry.row));
                const minAnchorColumn = Math.max(0, -minColumnOffset);
                const maxAnchorColumn = Math.min(gridColumns() - 1, gridColumns() - 1 - maxColumnOffset);
                const minAnchorRow = Math.max(0, -minRowOffset);
                const maxAnchorRow = Math.min(gridRows() - 1, gridRows() - 1 - maxRowOffset);
                const placedAnchorColumn = maxAnchorColumn >= minAnchorColumn
                    ? Math.max(minAnchorColumn, Math.min(maxAnchorColumn, targetAnchorColumn))
                    : Math.max(0, Math.min(gridColumns() - 1, targetAnchorColumn));
                const placedAnchorRow = maxAnchorRow >= minAnchorRow
                    ? Math.max(minAnchorRow, Math.min(maxAnchorRow, targetAnchorRow))
                    : Math.max(0, Math.min(gridRows() - 1, targetAnchorRow));

                const placements = offsets.map(offset => {
                    const column = Math.max(0, Math.min(gridColumns() - 1, placedAnchorColumn + offset.column));
                    const row = Math.max(0, Math.min(gridRows() - 1, placedAnchorRow + offset.row));
                    return {
                        path: String(offset.entry.item.path),
                        slot: column * gridRows() + row
                    };
                });
                const targetSlots = {};
                for (const placement of placements)
                    targetSlots[placement.slot] = true;

                const occupiedBySlot = {};
                for (let i = 0; i < desktopModel.count; i++) {
                    const candidate = modelPathAt(i);
                    if (!candidate || movingPaths[candidate] || root.effectiveScreenName(candidate) !== desktopWindow.screenName)
                        continue;
                    occupiedBySlot[resolvedGridSlot(candidate, i)] = candidate;
                }

                const displaced = [];
                for (const placement of placements) {
                    const occupant = occupiedBySlot[placement.slot];
                    if (occupant && displaced.indexOf(occupant) < 0)
                        displaced.push(occupant);
                }

                const replacements = [];
                const sourceSlots = {};
                if (String(sourceScreen) === desktopWindow.screenName) {
                    for (const entry of sourceCoordinates) {
                        const slot = entry.column * gridRows() + entry.row;
                        sourceSlots[slot] = true;
                    }
                    for (const slotText of Object.keys(sourceSlots)) {
                        const slot = Number(slotText);
                        if (!targetSlots[slot])
                            replacements.push(slot);
                    }
                }

                const reserved = {};
                for (const slot of Object.keys(occupiedBySlot))
                    reserved[slot] = true;
                for (const slot of Object.keys(targetSlots))
                    reserved[slot] = true;
                for (const slot of replacements)
                    reserved[slot] = false;

                for (let i = replacements.length; i < displaced.length; i++) {
                    const slot = nextAvailableGridSlot(i === 0 ? targetAnchorSlot : replacements[i - 1] + 1, reserved);
                    replacements.push(slot);
                    reserved[slot] = true;
                }

                const next = root.clone(SettingsData.desktopIconPositions);
                for (const placement of placements) {
                    const point = pointForGridSlot(placement.slot);
                    next[placement.path] = {
                        screen: desktopWindow.screenName,
                        x: Math.round(point.x),
                        y: Math.round(point.y)
                    };
                }

                for (let i = 0; i < displaced.length; i++) {
                    const point = pointForGridSlot(replacements[i]);
                    next[displaced[i]] = {
                        screen: desktopWindow.screenName,
                        x: Math.round(point.x),
                        y: Math.round(point.y)
                    };
                }

                SettingsData.set("desktopIconPositions", next);
                SettingsData.saveSettings();
            }

            function migratePosition(oldPath, newPath) {
                const next = desktopWindow.clone(SettingsData.desktopIconPositions);
                if (next[String(oldPath)] !== undefined) {
                    next[String(newPath)] = next[String(oldPath)];
                    delete next[String(oldPath)];
                    SettingsData.set("desktopIconPositions", next);
                    SettingsData.saveSettings();
                }
            }

            function marqueeRect() {
                const x1 = Math.min(marqueeStart.x, marqueeCurrent.x);
                const y1 = Math.min(marqueeStart.y, marqueeCurrent.y);
                const x2 = Math.max(marqueeStart.x, marqueeCurrent.x);
                const y2 = Math.max(marqueeStart.y, marqueeCurrent.y);
                return {
                    x: x1,
                    y: y1,
                    width: x2 - x1,
                    height: y2 - y1
                };
            }

            function updateMarqueeSelection() {
                const rect = marqueeRect();
                const next = desktopWindow.clone(marqueeBaseSelection);

                for (let i = 0; i < iconRepeater.count; i++) {
                    const item = iconRepeater.itemAt(i);
                    if (!item?.visible)
                        continue;
                    const intersects = rect.x < item.x + item.width
                        && rect.x + rect.width > item.x
                        && rect.y < item.y + item.height
                        && rect.y + rect.height > item.y;
                    const key = String(item.filePath);
                    if (intersects)
                        next[key] = true;
                    else if (!marqueeBaseSelection[key])
                        delete next[key];
                }

                desktopWindow.selectedPaths = next;
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

            MouseArea {
                id: desktopMouse
                anchors.fill: parent
                z: 0
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton)
                        return;

                    desktopSurface.forceActiveFocus();
                    const keepExisting = !!(mouse.modifiers & Qt.ControlModifier);
                    desktopSurface.marqueeBaseSelection = keepExisting
                        ? desktopWindow.clone(desktopWindow.selectedPaths)
                        : ({});
                    if (!keepExisting)
                        desktopWindow.clearSelection();

                    desktopSurface.marqueeStart = Qt.point(mouse.x, mouse.y);
                    desktopSurface.marqueeCurrent = desktopSurface.marqueeStart;
                    desktopSurface.marqueeActive = true;
                }

                onPositionChanged: mouse => {
                    if (!desktopSurface.marqueeActive || !(mouse.buttons & Qt.LeftButton))
                        return;
                    desktopSurface.marqueeCurrent = Qt.point(mouse.x, mouse.y);
                    desktopSurface.updateMarqueeSelection();
                }

                onReleased: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        desktopSurface.marqueeCurrent = Qt.point(mouse.x, mouse.y);
                        desktopSurface.updateMarqueeSelection();
                        desktopSurface.marqueeActive = false;
                    }
                }

                onClicked: mouse => {
                    if (mouse.button !== Qt.RightButton)
                        return;
                    desktopWindow.clearSelection();
                    desktopContextMenu.open(desktopWindow.modelData, mouse.x, mouse.y, false);
                }
            }

            Rectangle {
                id: marquee
                z: 2000
                visible: desktopSurface.marqueeActive
                readonly property var rect: desktopSurface.marqueeRect()
                x: rect.x
                y: rect.y
                width: rect.width
                height: rect.height
                radius: 3
                color: Theme.withAlpha(Theme.primary, 0.18)
                border.color: Theme.withAlpha(Theme.primary, 0.85)
                border.width: 1
            }

            Repeater {
                id: iconRepeater
                model: desktopModel

                delegate: Item {
                    id: iconItem

                    required property int index
                    required property string fileName
                    required property string filePath
                    required property url fileUrl
                    required property bool fileIsDir

                    readonly property bool isDesktopEntry: !fileIsDir && String(fileName).toLowerCase().endsWith(".desktop")
                    readonly property bool selected: desktopWindow.isSelected(filePath)
                    readonly property bool assignedToThisScreen: root.effectiveScreenName(filePath) === desktopWindow.screenName
                    readonly property point storedPosition: desktopSurface.positionFor(filePath, index, width, height)
                    readonly property var dragPreviewSource: icon.source
                    readonly property string dragPreviewLabel: iconLabel.text
                    property string desktopName: ""
                    property string desktopIcon: ""
                    property bool dragging: false
                    property bool renaming: false

                    width: desktopSurface.cellWidth
                    height: desktopSurface.cellHeight
                    x: storedPosition.x
                    y: storedPosition.y
                    visible: assignedToThisScreen
                    enabled: visible
                    opacity: root.dragActive && root.isDraggingPath(filePath) ? 0 : 1
                    z: dragging || renaming ? 1000 : selected ? 20 : 10

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

                    function beginRename() {
                        renaming = true;
                        renameInput.text = fileName;
                        Qt.callLater(() => {
                            renameInput.forceActiveFocus();
                            const dot = fileName.lastIndexOf(".");
                            renameInput.select(0, dot > 0 ? dot : fileName.length);
                        });
                    }

                    function commitRename() {
                        const nextName = renameInput.text.trim();
                        renaming = false;

                        if (!nextName || nextName === fileName)
                            return;
                        if (nextName.includes("/")) {
                            ToastService.showError(I18n.tr("Rename"), I18n.tr("File names cannot contain '/'"));
                            return;
                        }

                        const slash = filePath.lastIndexOf("/");
                        const dir = slash >= 0 ? filePath.substring(0, slash) : desktopWindow.desktopDirectory();
                        const nextPath = dir + "/" + nextName;
                        const oldPath = filePath;

                        Proc.runCommand("desktop-icon-rename", ["mv", "--", oldPath, nextPath], (output, code) => {
                            if (code !== 0) {
                                ToastService.showError(I18n.tr("Rename"), I18n.tr("Failed to rename item"));
                                return;
                            }
                            desktopSurface.migratePosition(oldPath, nextPath);
                            desktopWindow.clearSelection();
                        }, 0, 5000);
                    }

                    FileView {
                        id: desktopEntryView
                        path: iconItem.isDesktopEntry ? iconItem.filePath : ""
                        watchChanges: iconItem.isDesktopEntry
                        onLoaded: iconItem.parseDesktopEntry(text())
                        onTextChanged: iconItem.parseDesktopEntry(text())
                    }

                    Rectangle {
                        id: selectionBg
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 8
                        color: {
                            if (iconItem.selected)
                                return Theme.selectedContainer;
                            if (iconMouse.containsMouse)
                                return Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover);
                            return "transparent";
                        }
                        border.color: iconItem.selected ? Theme.primary : "transparent"
                        border.width: iconItem.selected ? 1 : 0

                        Behavior on color {
                            ColorAnimation {
                                duration: SettingsData.reduceMotion ? 0 : Theme.shortDuration
                            }
                        }
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
                            : desktopSurface.isImage(fileName)
                                ? fileUrl
                                : isDesktopEntry && desktopIcon
                                    ? Quickshell.iconPath(desktopIcon)
                                    : Quickshell.iconPath("text-x-generic")
                    }

                    Text {
                        id: iconLabel
                        anchors.top: icon.bottom
                        anchors.topMargin: 5
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        visible: !iconItem.renaming
                        text: isDesktopEntry && desktopName ? desktopName : fileName.replace(/\.desktop$/i, "")
                        color: iconItem.selected ? Theme.onSelectedContainer : "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignTop
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        font.pixelSize: 12
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.85)
                    }

                    Rectangle {
                        anchors.top: icon.bottom
                        anchors.topMargin: 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 8
                        height: 30
                        radius: 4
                        visible: iconItem.renaming
                        color: Theme.floatingWindowFieldColor
                        border.color: Theme.primary
                        border.width: 1
                        z: 30

                        TextInput {
                            id: renameInput
                            anchors.fill: parent
                            anchors.margins: 4
                            color: Theme.surfaceText
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.onPrimary
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            selectByMouse: true
                            clip: true

                            Keys.onReturnPressed: iconItem.commitRename()
                            Keys.onEnterPressed: iconItem.commitRename()
                            Keys.onEscapePressed: iconItem.renaming = false
                            onActiveFocusChanged: {
                                if (!activeFocus && iconItem.renaming)
                                    iconItem.commitRename();
                            }
                        }
                    }

                    MouseArea {
                        id: iconMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true

                        property point pressSurfacePoint: Qt.point(0, 0)
                        property point pressGrabPoint: Qt.point(0, 0)
                        property bool dragStarted: false

                        function surfacePoint(mouse) {
                            return iconItem.mapToItem(desktopSurface, mouse.x, mouse.y);
                        }

                        function globalPoint(mouse) {
                            const local = surfacePoint(mouse);
                            const origin = root.screenOrigin(desktopWindow.screenName);
                            return Qt.point(origin.x + local.x, origin.y + local.y);
                        }

                        onPressed: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                const alreadySelected = desktopWindow.isSelected(iconItem.filePath);
                                const hasSelectionModifier = !!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier));
                                if (alreadySelected && !hasSelectionModifier)
                                    desktopSurface.forceActiveFocus();
                                else
                                    desktopWindow.selectFromClick(iconItem.filePath, iconItem.index, mouse.modifiers);
                                pressSurfacePoint = surfacePoint(mouse);
                                pressGrabPoint = Qt.point(mouse.x, mouse.y);
                                dragStarted = false;
                            } else if (mouse.button === Qt.RightButton) {
                                if (!desktopWindow.isSelected(iconItem.filePath))
                                    desktopWindow.selectOnly(iconItem.filePath, iconItem.index);
                            }
                        }

                        onPositionChanged: mouse => {
                            if (mouse.button === Qt.RightButton || !(mouse.buttons & Qt.LeftButton) || iconItem.renaming)
                                return;

                            const local = surfacePoint(mouse);
                            if (!dragStarted) {
                                const dx = local.x - pressSurfacePoint.x;
                                const dy = local.y - pressSurfacePoint.y;
                                if (Math.sqrt(dx * dx + dy * dy) < 10)
                                    return;

                                const global = globalPoint(mouse);
                                const selectedIcons = desktopWindow.isSelected(iconItem.filePath)
                                    ? desktopWindow.selectedItems()
                                    : [iconItem];
                                const rows = desktopSurface.gridRows();
                                const movingItems = selectedIcons.map(item => {
                                    const slot = desktopSurface.gridSlotForPoint(item.x, item.y);
                                    return {
                                        path: String(item.filePath),
                                        sourceX: Number(item.x),
                                        sourceY: Number(item.y),
                                        sourceColumn: Math.floor(slot / rows),
                                        sourceRow: slot % rows
                                    };
                                });
                                root.beginIconDrag(
                                    iconItem.filePath,
                                    desktopWindow.screenName,
                                    iconItem.x,
                                    iconItem.y,
                                    global.x,
                                    global.y,
                                    pressGrabPoint.x,
                                    pressGrabPoint.y,
                                    iconItem.dragPreviewSource,
                                    iconItem.dragPreviewLabel,
                                    movingItems
                                );
                                dragStarted = true;
                                iconItem.dragging = true;
                            }

                            const global = globalPoint(mouse);
                            root.updateIconDrag(global.x, global.y);
                        }

                        onReleased: mouse => {
                            if (mouse.button !== Qt.LeftButton)
                                return;

                            if (dragStarted) {
                                const global = globalPoint(mouse);
                                root.updateIconDrag(global.x, global.y);
                                root.finishIconDrag(iconItem.width, iconItem.height);
                            }

                            dragStarted = false;
                            iconItem.dragging = false;
                        }

                        onCanceled: {
                            if (dragStarted)
                                root.cancelIconDrag();
                            dragStarted = false;
                            iconItem.dragging = false;
                        }

                        onDoubleClicked: mouse => {
                            if (mouse.button === Qt.LeftButton && !iconItem.renaming && !dragStarted)
                                desktopSurface.launch(iconItem.filePath, iconItem.fileUrl, iconItem.fileName, iconItem.fileIsDir);
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                // Selection already happens once onPressed so drag starts
                                // from a selected item immediately. Do not select again here:
                                // Ctrl-click would otherwise toggle twice and look broken.
                                mouse.accepted = true;
                                return;
                            }
                            if (mouse.button !== Qt.RightButton)
                                return;
                            mouse.accepted = true;
                            const point = iconItem.mapToItem(desktopSurface, mouse.x, mouse.y);
                            desktopWindow.openIconContextMenu(iconItem, point);
                        }
                    }
                }
            }

            Item {
                id: dragGhost
                visible: root.dragActive && root.dragTargetScreen === desktopWindow.screenName
                width: desktopSurface.cellWidth
                height: desktopSurface.cellHeight
                z: 3000
                opacity: 0.92

                readonly property point outputOrigin: root.screenOrigin(desktopWindow.screenName)

                readonly property real rawX: Math.max(
                    0,
                    Math.min(
                        Math.max(0, desktopSurface.width - width),
                        root.dragGlobalX - outputOrigin.x - root.dragGrabX
                    )
                )
                readonly property real rawY: Math.max(
                    0,
                    Math.min(
                        Math.max(0, desktopSurface.height - height),
                        root.dragGlobalY - outputOrigin.y - root.dragGrabY
                    )
                )
                // Even in Grid mode the drag ghost follows the pointer freely.
                // Snapping (and collision swap) happens only when the button is released.
                readonly property point previewPoint: Qt.point(rawX, rawY)

                x: previewPoint.x
                y: previewPoint.y

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 8
                    color: Theme.selectedContainer
                    border.color: Theme.primary
                    border.width: 1
                }

                Image {
                    id: dragGhostIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    width: 54
                    height: 54
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    source: root.dragIconSource
                }

                Rectangle {
                    visible: root.dragItems.length > 1
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 5
                    anchors.topMargin: 5
                    width: 24
                    height: 20
                    radius: 10
                    color: Theme.primary
                    border.color: Theme.surface
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: String(root.dragItems.length)
                        color: Theme.onPrimary
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                Text {
                    anchors.top: dragGhostIcon.bottom
                    anchors.topMargin: 5
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    text: root.dragLabel
                    color: Theme.onSelectedContainer
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignTop
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.85)
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                    desktopWindow.selectAll();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Delete) {
                    desktopWindow.trashSelected();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_F2) {
                    desktopWindow.renameSelected();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    desktopWindow.openSelected();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    desktopWindow.clearSelection();
                    event.accepted = true;
                }
            }
        }

        CyContextMenu {
            id: iconContextMenu
            layerNamespace: "cyshell:desktop-icon-context-menu"
            keyboardNavigable: true
            menuItems: desktopWindow.iconMenuItems()
        }

        CyContextMenu {
            id: desktopContextMenu
            layerNamespace: "cyshell:desktop-context-menu"
            keyboardNavigable: true
            menuItems: desktopWindow.desktopMenuItems()
        }
    }
}
