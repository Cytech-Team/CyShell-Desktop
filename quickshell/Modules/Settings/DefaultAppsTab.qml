import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root
    readonly property var log: Log.scoped("DefaultAppsTab")
    property var parentModal: null
    property int appBrowserCategory: -1

    readonly property var appCategory: ({
            WebBrowser: 0,
            FileManager: 1,
            TextEditor: 2,
            ImageViewer: 3,
            VideoPlayer: 4,
            MusicPlayer: 5,
            PDFReader: 6,
            Mail: 7,
            Terminal: 8,
            Calendar: 9,
            Maps: 10
        })

    property string currentWebBrowserAppId: ""
    property string currentFileManagerAppId: ""
    property string currentTextEditorAppId: ""
    property string currentImageViewerAppId: ""
    property string currentVideoPlayerAppId: ""
    property string currentMusicPlayerAppId: ""
    property string currentPDFReaderAppId: ""
    property string currentMailAppId: ""
    property string currentTerminalAppId: ""
    property string currentCalendarAppId: ""
    property string currentMapsAppId: ""

    property var categoryModels: ({})

    // A curated list of MIME types for each category.
    // The first one is used for fetching the apps list and current default,
    // the rest are for setting the default app.
    readonly property var mimeMapping: ({
            [root.appCategory.WebBrowser]: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml"],
            [root.appCategory.FileManager]: ["inode/directory", "x-scheme-handler/file", "x-scheme-handler/sftp"],
            [root.appCategory.TextEditor]: ["text/plain", "text/markdown", "application/x-zerosize", "text/x-c++src", "text/x-csrc", "text/x-python", "text/x-shellscript", "application/json"],
            [root.appCategory.ImageViewer]: ["image/png", "image/jpeg", "image/gif", "image/bmp", "image/webp", "image/avif", "image/svg+xml"],
            [root.appCategory.VideoPlayer]: ["video/mp4", "video/x-matroska", "video/webm", "video/avi", "video/mpeg", "video/quicktime", "video/x-msvideo"],
            [root.appCategory.MusicPlayer]: ["audio/mpeg", "audio/x-flac", "audio/wav", "audio/ogg", "audio/aac", "audio/webm"],
            [root.appCategory.PDFReader]: ["application/pdf", "application/x-ext-pdf", "application/x-bzpdf", "application/x-gzpdf", "application/vnd.comicbook-rar", "application/vnd.comicbook+zip"],
            [root.appCategory.Mail]: ["x-scheme-handler/mailto"],
            [root.appCategory.Calendar]: ["x-scheme-handler/calendar"],
            [root.appCategory.Maps]: ["x-scheme-handler/geo"],
            [root.appCategory.Terminal]: ["terminal"] // Special
        })

    function propertyName(type) {
        const names = Object.keys(root.appCategory);
        return "current" + names[type] + "AppId";
    }

    function loadAppSearchCategory(categoryName) {
        const apps = AppSearchService.getVisibleApplications() || [];
        return apps.filter(app => {
            const categories = app.categories || [];
            return categories.includes(categoryName);
        });
    }

    function getAppDisplayName(appId) {
        if (appId === root.cyShellChooserId || appId === "cyshell-open") {
            return root.cyShellChooserLabel;
        }
        let entry = DesktopEntries.heuristicLookup(appId);
        if (entry && entry.name) {
            return entry.name;
        }
        const withoutSuffix = appId.replace(/\.desktop$/, "");
        if (withoutSuffix !== appId) {
            entry = DesktopEntries.heuristicLookup(withoutSuffix);
            if (entry && entry.name) {
                return entry.name;
            }
        }
        return appId;
    }

    readonly property string cyShellChooserId: "cyshell-open.desktop"
    readonly property string cyShellChooserLabel: I18n.tr("CyShell chooser")

    function withCyShellChooser(entries) {
        const filtered = (entries || []).filter(e => e.value !== root.cyShellChooserId && e.value !== "cyshell-open");
        return [
            {
                text: root.cyShellChooserLabel,
                value: root.cyShellChooserId
            }
        ].concat(filtered);
    }

    function loadCategoryModel(categoryKey, categorySearchName) {
        const apps = loadAppSearchCategory(categorySearchName);
        const appIds = apps.map(app => app.id || app.execString || "").filter(id => id);
        let models = Object.assign({}, root.categoryModels);
        const entries = appIds.map(id => ({
                    text: root.getAppDisplayName(id),
                    value: categoryKey === root.appCategory.Terminal
                        ? root.normalizeTerminalDesktopId(id)
                        : id
                }));
        models[categoryKey] = categoryKey === root.appCategory.Terminal ? entries : root.withCyShellChooser(entries);
        root.categoryModels = models;
    }

    function ensureCategoryHasApp(category, appId) {
        if (!appId)
            return;
        const normalizedId = category === root.appCategory.Terminal
            ? root.normalizeTerminalDesktopId(appId)
            : appId;
        const models = Object.assign({}, root.categoryModels);
        const current = (models[category] || []).slice();
        if (!current.some(opt => opt.value === normalizedId)) {
            current.push({
                text: root.getAppDisplayName(normalizedId),
                value: normalizedId
            });
            current.sort((a, b) => String(a.text || "").localeCompare(String(b.text || "")));
            models[category] = current;
            root.categoryModels = models;
        }
    }

    function setCategoryDefault(category, appId) {
        if (!appId)
            return;
        const normalizedId = category === root.appCategory.Terminal
            ? root.normalizeTerminalDesktopId(appId)
            : appId;
        root.ensureCategoryHasApp(category, normalizedId);
        root[root.propertyName(category)] = normalizedId;
        if (category === root.appCategory.Terminal)
            root.setDefaultTerminal(normalizedId);
        else
            DesktopService.setDefaultAppForMimes(root.mimeMapping[category], normalizedId, category.toString());
    }

    function chooseOtherApp(category) {
        root.appBrowserCategory = category;
        appBrowserPopup.appsModel = (AppSearchService.applications || []).filter(app =>
            app && (app.id || app.execString || app.exec)
        );
        appBrowserPopup.show();
    }

    function refreshCategoryModels(reloadDefaults) {
        // AppSearchService follows DesktopEntries, so this is triggered whenever
        // a .desktop entry is installed, removed, or changed. Rebuild the local
        // per-category models so Default apps updates without reopening Settings.
        root.categoryModels = {};
        const categories = Object.values(root.appCategory);

        categories.forEach(category => {
            switch (category) {
            case root.appCategory.Terminal:
                // Terminals don't have a MIME type
                loadCategoryModel(root.appCategory.Terminal, "TerminalEmulator");
                if (reloadDefaults)
                    getDefaultTerminal();
                break;
            case root.appCategory.WebBrowser:
                // When using the MIME type, stuff like cyshell-run shows up.
                // It's probably better to use the category.
                loadCategoryModel(root.appCategory.WebBrowser, "WebBrowser");
                if (reloadDefaults)
                    DesktopService.getDefaultApp(mimeMapping[category][0], category.toString());
                break;
            case root.appCategory.FileManager:
                // Use categories for file managers instead,
                // you don't want Kate as your file manager just because it can open folders
                loadCategoryModel(root.appCategory.FileManager, "FileManager");
                if (reloadDefaults)
                    DesktopService.getDefaultApp(mimeMapping[category][0], category.toString());
                DesktopService.getHandlersForMimeType(mimeMapping[category][0], category.toString());
                break;
            default:
                const mimeType = mimeMapping[category][0];
                if (reloadDefaults)
                    DesktopService.getDefaultApp(mimeType, category.toString());
                DesktopService.getAppsForMimeType(mimeType, category.toString());
                break;
            }
        });
    }

    Component.onCompleted: root.refreshCategoryModels(true)

    Timer {
        id: applicationsRefreshTimer
        interval: 250
        repeat: false
        onTriggered: root.refreshCategoryModels(false)
    }

    Connections {
        target: AppSearchService
        function onApplicationsChanged() {
            // Package managers can emit several desktop-entry changes in one
            // transaction; debounce them into one refresh.
            applicationsRefreshTimer.restart();
        }
    }

    function normalizeTerminalDesktopId(terminalId) {
        const id = String(terminalId || "").trim();
        if (!id)
            return "";
        return id.endsWith(".desktop") ? id : id + ".desktop";
    }

    function getDefaultTerminal() {
        // xdg-terminals.list is the freedesktop terminal preference file. If it
        // is missing, detect an installed terminal once and persist it so every
        // CyShell entry point uses the same default.
        xdgGetDefaultTerminal.createObject(root, { running: true });
    }

    function setDefaultTerminal(terminalId) {
        const normalized = normalizeTerminalDesktopId(terminalId);
        if (!normalized)
            return;
        currentTerminalAppId = normalized;
        xdgSetDefaultTerminal.createObject(root, {
            terminalId: normalized,
            running: true
        });
    }

    Component {
        id: xdgSetDefaultTerminal
        Process {
            property string terminalId: ""
            property string configPath: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
            command: ["sh", "-c", `mkdir -p "${configPath}" && printf '%s\\n' "${terminalId}" > "${configPath}/xdg-terminals.list"`]
            onExited: (exitCode, exitStatus) => {
                if (exitCode != 0)
                    log.error("Failed to write xdg-terminals.list, exit code:", exitCode);
                destroy();
            }
        }
    }

    Component {
        id: xdgGetDefaultTerminal
        Process {
            property string configPath: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")

            command: ["sh", "-c", `
                cfg="${configPath}/xdg-terminals.list"
                if [ -s "$cfg" ]; then
                    sed -n '/^[[:space:]]*#/d; /^[[:space:]]*$/d; 1p' "$cfg"
                    exit 0
                fi

                mkdir -p "${configPath}"
                for id in qterminal.desktop org.kde.konsole.desktop kitty.desktop foot.desktop Alacritty.desktop com.mitchellh.ghostty.desktop org.wezfurlong.wezterm.desktop; do
                    if [ -f "$HOME/.local/share/applications/$id" ] || [ -f "/usr/share/applications/$id" ]; then
                        printf '%s\\n' "$id" | tee "$cfg"
                        exit 0
                    fi
                done

                for dir in "$HOME/.local/share/applications" /usr/share/applications; do
                    [ -d "$dir" ] || continue
                    for file in "$dir"/*.desktop; do
                        [ -f "$file" ] || continue
                        if grep -qE '^Categories=.*TerminalEmulator' "$file"; then
                            basename "$file" | tee "$cfg"
                            exit 0
                        fi
                    done
                done
            `]
            stdout: StdioCollector {
                onStreamFinished: {
                    const defaultTerminal = root.normalizeTerminalDesktopId(text.trim().split(/\\r?\\n/)[0] || "");
                    if (defaultTerminal)
                        root.currentTerminalAppId = defaultTerminal;
                    else
                        log.warn("No installed terminal could be detected");
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    if (text.trim().length > 0) {
                        log.error("Error getting default terminal:", text);
                    }
                }
            }
            onExited: (exitCode, exitStatus) => {
                destroy();
            }
        }
    }

    Connections {
        target: DesktopService

        function onGetAppsForMimeResult(mimeType, appIds, callbackId) {
            let categoryIndex = parseInt(callbackId);
            let models = Object.assign({}, root.categoryModels);

            const entries = (appIds || []).map(id => ({
                        text: root.getAppDisplayName(id),
                        value: id
                    }));

            models[categoryIndex] = root.withCyShellChooser(entries);
            root.categoryModels = models;
        }

        function onGetHandlersForMimeResult(mimeType, apps, callbackId) {
            const categoryIndex = parseInt(callbackId);
            let models = Object.assign({}, root.categoryModels);
            const existing = models[categoryIndex] || root.withCyShellChooser([]);
            const known = new Set(existing.map(opt => opt.value));
            const extra = (apps || []).filter(app => app.id && !known.has(app.id)).map(app => ({
                        text: app.name || root.getAppDisplayName(app.id),
                        value: app.id
                    }));
            if (extra.length === 0) {
                return;
            }
            models[categoryIndex] = existing.concat(extra);
            root.categoryModels = models;
        }

        function onGetDefaultAppResult(mimeType, desktopFileId, callbackId) {
            if (!desktopFileId) {
                log.info("No default app found for MIME type:", mimeType);
                return;
            }
            root[propertyName(parseInt(callbackId))] = desktopFileId;
        }
    }

    component AppSelector: SettingsRow {
        id: selector
        property int category: -1
        property string text: ""
        property string description: ""
        readonly property var selectorModel: root.categoryModels[category] || []
        readonly property string selectedId: root[root.propertyName(category)] || ""
        readonly property string otherOptionLabel: I18n.tr("Other…")

        title: text
        subtitle: description
        enabled: true

        CyDropdown {
            id: appDropdown
            width: Math.min(316, Math.max(160, selector.width * 0.46))
            options: selector.selectorModel.map(opt => opt.text).concat([selector.otherOptionLabel])
            emptyText: I18n.tr("Unset", "Unset")
            currentValue: selector.selectedId ? root.getAppDisplayName(selector.selectedId) : ""

            onValueChanged: value => {
                if (value === selector.otherOptionLabel) {
                    root.chooseOtherApp(selector.category);
                    return;
                }

                const found = selector.selectorModel.find(opt => opt.text === value);
                if (found && found.value !== selector.selectedId)
                    root.setCategoryDefault(selector.category, found.value);
            }
        }
    }

    AppBrowserPopup {
        id: appBrowserPopup
        parentModal: root.parentModal

        onAppSelected: appId => {
            if (root.appBrowserCategory >= 0)
                root.setCategoryDefault(root.appBrowserCategory, appId);
        }
    }

    // Dropdowns

    SettingsPage {
        id: mainColumn

        SettingsCard {
            settingKey: "defaultAppsInternet"
            tags: ["browser", "mail", "email", "web"]
            title: I18n.tr("Internet", "Internet")
            iconName: "public"

            AppSelector {
                text: I18n.tr("Web browser")
                description: I18n.tr("Opens web links and HTML pages")
                tags: ["web", "browser", "internet", "links", "html"]
                category: root.appCategory.WebBrowser
            }

            AppSelector {
                text: I18n.tr("Mail", "Mail")
                description: I18n.tr("Opens email links")
                category: root.appCategory.Mail
                tags: ["mail", "email", "mailto"]
            }

            AppSelector {
                text: I18n.tr("Maps", "Maps")
                description: I18n.tr("Opens location links")
                category: root.appCategory.Maps
                tags: ["maps", "geo", "location"]
            }
        }

        SettingsCard {
            settingKey: "defaultAppsUtilities"
            tags: ["file", "manager", "terminal", "editor"]
            title: I18n.tr("Utilities", "Utilities")
            iconName: "terminal"

            AppSelector {
                text: I18n.tr("File manager")
                description: I18n.tr("Opens folders and file locations")
                tags: ["file", "manager", "directory", "sftp"]
                category: root.appCategory.FileManager
            }
            AppSelector {
                text: I18n.tr("Terminal", "Terminal")
                description: I18n.tr("Used when CyShell launches command-line tools")
                category: root.appCategory.Terminal
                tags: ["terminal", "console", "xdg-terminal-exec"]
            }
            AppSelector {
                text: I18n.tr("Calendar", "Calendar")
                description: I18n.tr("Opens calendar links")
                category: root.appCategory.Calendar
                tags: ["calendar", "events"]
            }
        }

        SettingsCard {
            settingKey: "defaultAppsDocuments"
            tags: ["pdf", "text", "reader", "office"]
            title: I18n.tr("Documents", "Documents")
            iconName: "edit_document"

            AppSelector {
                text: I18n.tr("Text editor")
                description: I18n.tr("Opens text, code, and Markdown files")
                category: root.appCategory.TextEditor
                tags: ["text", "editor"]
            }
            AppSelector {
                text: I18n.tr("PDF reader")
                description: I18n.tr("Opens PDF documents and comic archives")
                category: root.appCategory.PDFReader
                tags: ["pdf", "reader"]
            }
        }

        SettingsCard {
            settingKey: "defaultAppsMultimedia"
            tags: ["image", "video", "music", "viewer", "player"]
            title: I18n.tr("Multimedia", "Multimedia")
            iconName: "movie"
            AppSelector {
                text: I18n.tr("Image viewer")
                description: I18n.tr("Opens common image formats")
                category: root.appCategory.ImageViewer
                tags: ["image", "viewer"]
            }
            AppSelector {
                text: I18n.tr("Video player")
                description: I18n.tr("Opens video files")
                category: root.appCategory.VideoPlayer
                tags: ["video", "player"]
            }
            AppSelector {
                text: I18n.tr("Music player")
                description: I18n.tr("Opens audio files")
                category: root.appCategory.MusicPlayer
                tags: ["music", "player", "audio"]
            }
        }
    }
}
