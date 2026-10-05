import QtQuick
import QtQuick.Effects
import qs.Common
import qs.CyCommon.Common as CyCommon
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: aboutTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool isLabwc: true
    readonly property string compositorName: "labwc"
    readonly property string compositorLogo: "/assets/labwc.png"
    readonly property string compositorUrl: "https://labwc.github.io/"
    readonly property string compositorTooltip: I18n.tr("LabWC website")

    readonly property string ircUrl: "https://web.libera.chat/gamja/?channels=#labwc"
    readonly property string ircTooltip: I18n.tr("LabWC IRC channel")
    readonly property bool showMatrix: false
    readonly property bool showCompositorDiscord: false
    readonly property bool showReddit: false
    readonly property bool showIrc: true
    property var deviceInformation: ({})
    property var deviceInformationRequestId: 0
    property int deviceInformationGeneration: 0
    property bool deviceInformationLoading: false
    property bool deviceInformationFailed: false

    function deviceValue(value) {
        if (value === undefined || value === null || String(value).trim() === "")
            return I18n.tr("Unavailable");
        return String(value);
    }

    function deviceMemoryValue() {
        const totalKb = Number(deviceInformation.memory?.total || 0);
        if (totalKb <= 0)
            return I18n.tr("Unavailable");

        const gib = totalKb / (1024 * 1024);
        return `${gib >= 10 ? gib.toFixed(0) : gib.toFixed(1)} GiB`;
    }

    function deviceGraphicsValue() {
        const graphicsDevices = deviceInformation.gpu?.gpus || [];
        const names = graphicsDevices.map(device => device.fullName || device.displayName || device.name).filter(Boolean);
        return names.length > 0 ? names.join(" · ") : I18n.tr("Unavailable");
    }

    function loadDeviceInformation() {
        if (!visible || deviceInformationLoading)
            return;

        if (!DgopService.dgopAvailable) {
            deviceInformationFailed = true;
            return;
        }

        deviceInformationFailed = false;
        deviceInformationLoading = true;
        const generation = ++deviceInformationGeneration;
        deviceInformationRequestId = CyShellService.sendRequest("dgop.meta", {
            modules: ["hardware", "memory", "gpu"]
        }, response => {
            if (generation !== deviceInformationGeneration)
                return;

            deviceInformationRequestId = 0;
            deviceInformationLoading = false;
            if (!response.result) {
                deviceInformationFailed = true;
                return;
            }

            deviceInformation = response.result;
        }, 10000) || 0;
    }

    function cancelDeviceInformationRequest() {
        deviceInformationGeneration++;
        if (deviceInformationRequestId > 0)
            CyShellService.cancelRequest(deviceInformationRequestId);
        deviceInformationRequestId = 0;
        deviceInformationLoading = false;
    }

    Component.onCompleted: loadDeviceInformation()
    Component.onDestruction: cancelDeviceInformationRequest()
    onVisibleChanged: {
        if (visible)
            loadDeviceInformation();
        else
            cancelDeviceInformationRequest();
    }


    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width

            SettingsRow {
                body: Column {
                    id: asciiSection
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: parent.width < 350 ? Theme.spacingM : Theme.spacingL

                        property bool compactLogo: parent.width < 400
                        property bool hideLogo: parent.width < 280

                        Image {
                            id: logoImage

                            visible: !parent.hideLogo
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.compactLogo ? 88 : 128
                            height: width
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            source: "file://" + Theme.shellDir + "/assets/cyshell.png"
                            layer.enabled: false
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "CyShell Desktop"
                            font.pixelSize: parent.compactLogo ? 32 : 48
                            font.weight: Theme.fontWeightMedium
                            font.family: CyCommon.Fonts.sans
                            color: Theme.surfaceText
                            antialiasing: true
                        }
                    }

                    StyledText {
                        text: {
                            if (!ShellVersionService.shellVersion && !CyShellService.cliVersion)
                                return "cyshell";

                            let version = ShellVersionService.shellVersion || "";
                            let cliVersion = CyShellService.cliVersion || "";

                            // Debian/Ubuntu/OpenSUSE git format: 1.0.3+git2264.c5c5ce84
                            let match = version.match(/^([\d.]+)\+git(\d+)\./);
                            if (match) {
                                return `CyShell (git) v${match[1]}-${match[2]}`;
                            }

                            // Fedora COPR git format: 0.0.git.2267.d430cae9
                            match = version.match(/^[\d.]+\.git\.(\d+)\./);
                            if (match) {
                                function extractBaseVersion(value) {
                                    if (!value)
                                        return "";
                                    let baseMatch = value.match(/(\d+\.\d+\.\d+)/);
                                    if (baseMatch)
                                        return baseMatch[1];
                                    baseMatch = value.match(/(\d+\.\d+)/);
                                    if (baseMatch)
                                        return baseMatch[1];
                                    return "";
                                }

                                let baseVersion = extractBaseVersion(cliVersion);
                                if (!baseVersion)
                                    baseVersion = extractBaseVersion(ShellVersionService.semverVersion);
                                if (baseVersion) {
                                    return `CyShell (git) v${baseVersion}-${match[1]}`;
                                }
                                return `CyShell (git) v${match[1]}`;
                            }

                            // Stable release format: 1.0.3
                            match = version.match(/^([\d.]+)$/);
                            if (match) {
                                return `CyShell v${match[1]}`;
                            }

                            if (!version && cliVersion) {
                                match = cliVersion.match(/^([\d.]+)\+git(\d+)\./);
                                if (match) {
                                    return `CyShell (git) v${match[1]}-${match[2]}`;
                                }
                                match = cliVersion.match(/^([\d.]+)$/);
                                if (match) {
                                    return `CyShell v${match[1]}`;
                                }
                                return `CyShell ${cliVersion}`;
                            }

                            return `CyShell ${version}`;
                        }
                        font.pixelSize: Theme.fontSizeXLarge
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    StyledText {
                        visible: ShellVersionService.shellCodename.length > 0
                        text: `"${ShellVersionService.shellCodename}"`
                        font.pixelSize: Theme.fontSizeMedium
                        font.italic: true
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Row {
                        id: resourceButtonsRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingS

                        property bool compactMode: parent.width < 450

                        CyButton {
                            id: docsButton
                            tooltipText: resourceButtonsRow.compactMode ? I18n.tr("Docs") + " - CyShell" : "CyShell architecture & docs"
                            text: resourceButtonsRow.compactMode ? "" : I18n.tr("Docs")
                            iconName: "menu_book"
                            iconSize: 18
                            backgroundColor: Theme.chipSurface
                            textColor: Theme.surfaceText
                            onClicked: Qt.openUrlExternally("https://github.com/Cytech-Team/CyShell-Desktop/blob/cyshell-dev/CYSHELL.md")
                        }

                        CyButton {
                            id: overviewButton
                            tooltipText: resourceButtonsRow.compactMode ? I18n.tr("README") : I18n.tr("Project overview")
                            text: resourceButtonsRow.compactMode ? "" : I18n.tr("README")
                            iconName: "description"
                            iconSize: 18
                            backgroundColor: Theme.chipSurface
                            textColor: Theme.surfaceText
                            onClicked: Qt.openUrlExternally("https://github.com/Cytech-Team/CyShell-Desktop/blob/cyshell-dev/README.md")
                        }

                        CyButton {
                            id: githubButton
                            tooltipText: resourceButtonsRow.compactMode ? "GitHub - CyShell" : "github.com/Cytech-Team/CyShell-Desktop"
                            text: resourceButtonsRow.compactMode ? "" : "GitHub"
                            iconName: "code"
                            iconSize: 18
                            backgroundColor: Theme.chipSurface
                            textColor: Theme.surfaceText
                            onClicked: Qt.openUrlExternally("https://github.com/Cytech-Team/CyShell-Desktop")
                        }

                        CyButton {
                            id: kofiButton
                            visible: false
                            tooltipText: resourceButtonsRow.compactMode ? "Ko-fi" + " - ko-fi.com/danklinux" : "ko-fi.com/danklinux"
                            text: resourceButtonsRow.compactMode ? "" : "Ko-fi"
                            iconName: "favorite"
                            iconSize: 18
                            backgroundColor: Theme.primaryHover
                            textColor: Theme.primary
                            onClicked: Qt.openUrlExternally("https://ko-fi.com/danklinux")
                        }
                    }

                    Row {
                        id: communityIcons
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingXS

                        CyActionButton {
                            tooltipText: compositorTooltip
                            tooltipSide: "top"
                            onClicked: {
                                if (compositorUrl === "")
                                    return;
                                Qt.openUrlExternally(compositorUrl);
                            }

                            Image {
                                anchors.centerIn: parent
                                width: Theme.iconSize
                                height: Theme.iconSize
                                source: Qt.resolvedUrl(".").toString().replace("file://", "").replace("/Modules/Settings/", "") + compositorLogo
                                sourceSize: Qt.size(24, 24)
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        CyActionButton {
                            visible: showMatrix
                            tooltipText: I18n.tr("niri Matrix chat")
                            tooltipSide: "top"
                            onClicked: Qt.openUrlExternally("https://matrix.to/#/#niri:matrix.org")

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingXXS
                                source: Qt.resolvedUrl(".").toString().replace("file://", "").replace("/Modules/Settings/", "") + "/assets/matrix-logo-white.svg"
                                sourceSize: Qt.size(28, 18)
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: true

                                layer.effect: MultiEffect {
                                    colorization: 1
                                    colorizationColor: Theme.surfaceText
                                }
                            }
                        }

                        CyActionButton {
                            visible: showIrc
                            iconName: "forum"
                            iconSize: Theme.iconSizeMedium
                            iconColor: Theme.surfaceText
                            tooltipText: ircTooltip
                            tooltipSide: "top"
                            onClicked: Qt.openUrlExternally(ircUrl)
                        }

                        CyActionButton {
                            visible: false
                            tooltipText: dmsDiscordTooltip
                            tooltipSide: "top"
                            onClicked: Qt.openUrlExternally(dmsDiscordUrl)

                            Image {
                                anchors.centerIn: parent
                                width: Theme.iconSizeMedium
                                height: Theme.iconSizeMedium
                                source: Qt.resolvedUrl(".").toString().replace("file://", "").replace("/Modules/Settings/", "") + "/assets/discord.svg"
                                sourceSize: Qt.size(20, 20)
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        CyActionButton {
                            visible: showCompositorDiscord
                            tooltipText: compositorDiscordTooltip
                            tooltipSide: "top"
                            onClicked: Qt.openUrlExternally(compositorDiscordUrl)

                            Image {
                                anchors.centerIn: parent
                                width: Theme.iconSizeMedium
                                height: Theme.iconSizeMedium
                                source: Qt.resolvedUrl(".").toString().replace("file://", "").replace("/Modules/Settings/", "") + "/assets/discord.svg"
                                sourceSize: Qt.size(20, 20)
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        CyActionButton {
                            visible: showReddit
                            tooltipText: redditTooltip
                            tooltipSide: "top"
                            onClicked: Qt.openUrlExternally(redditUrl)

                            Image {
                                anchors.centerIn: parent
                                width: Theme.iconSizeMedium
                                height: Theme.iconSizeMedium
                                source: Qt.resolvedUrl(".").toString().replace("file://", "").replace("/Modules/Settings/", "") + "/assets/reddit.svg"
                                sourceSize: Qt.size(20, 20)
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "info"
            title: I18n.tr("About")

            SettingsRow {
                body: StyledText {
                    text: I18n.tr('CyShell Desktop is an agent-native Wayland desktop shell by Cytech Team Development, built around semantic desktop APIs, safe automation, the embedded CyCom runtime, and the CyShell Greeter.<br/><br/>CyShell uses a blue-first visual identity, is optimized for Labwc, and is built with %1 and %2.', 'about page blurb, %1 is a Quickshell link and %2 is a Go link').arg(`<a href="https://quickshell.org" style="text-decoration:none; color:${Theme.primary};">Quickshell</a>`).arg(`<a href="https://go.dev" style="text-decoration:none; color:${Theme.primary};">Go</a>`)
                    textFormat: Text.RichText
                    font.pixelSize: Theme.fontSizeMedium
                    linkColor: Theme.primary
                    onLinkActivated: url => Qt.openUrlExternally(url)
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.WordWrap

                    HoverHandler {
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "computer"
            title: I18n.tr("Device information")

            SettingsRow {
                title: I18n.tr("System details")
                subtitle: aboutTab.deviceInformationLoading ? I18n.tr("Loading…") : (aboutTab.deviceInformationFailed ? I18n.tr("Could not load device information") : I18n.tr("Provided by CyShell Core"))

                CyActionButton {
                    iconName: "refresh"
                    tooltipText: I18n.tr("Refresh device information")
                    Accessible.name: tooltipText
                    enabled: !aboutTab.deviceInformationLoading && DgopService.dgopAvailable
                    onClicked: aboutTab.loadDeviceInformation()
                }
            }

            SettingsRow {
                title: I18n.tr("Computer")
                subtitle: aboutTab.deviceValue(aboutTab.deviceInformation.hardware?.hostname)
            }

            SettingsRow {
                title: I18n.tr("Operating system")
                subtitle: aboutTab.deviceValue(aboutTab.deviceInformation.hardware?.distro)
            }

            SettingsRow {
                title: I18n.tr("Kernel and architecture")
                subtitle: [aboutTab.deviceInformation.hardware?.kernel, aboutTab.deviceInformation.hardware?.arch].filter(Boolean).join(" · ") || I18n.tr("Unavailable")
            }

            SettingsRow {
                title: I18n.tr("Processor")
                subtitle: {
                    const cpu = aboutTab.deviceInformation.hardware?.cpu || {};
                    const model = cpu.model || "";
                    const count = Number(cpu.count || 0);
                    const details = [];
                    if (model)
                        details.push(model);
                    if (count > 0)
                        details.push(I18n.tr("%1 cores", "Processor core count").arg(count));
                    return details.length > 0 ? details.join(" · ") : I18n.tr("Unavailable");
                }
            }

            SettingsRow {
                title: I18n.tr("Memory")
                subtitle: aboutTab.deviceMemoryValue()
            }

            SettingsRow {
                title: I18n.tr("Graphics")
                subtitle: aboutTab.deviceGraphicsValue()
            }

            SettingsRow {
                title: I18n.tr("Motherboard")
                subtitle: aboutTab.deviceValue(aboutTab.deviceInformation.hardware?.bios?.motherboard)
            }

            SettingsRow {
                title: I18n.tr("Firmware")
                subtitle: {
                    const bios = aboutTab.deviceInformation.hardware?.bios || {};
                    return [bios.vendor, bios.version].filter(Boolean).join(" · ") || I18n.tr("Unavailable");
                }
            }
        }

        SettingsCard {
            visible: CyShellService.isConnected
            width: parent.width
            iconName: "dns"
            title: I18n.tr("CyShell Core", "noun, settings label for the backend service in use")

            SettingsRow {
                title: I18n.tr("Version")
                trailingBadge: CyShellService.cliVersion || "—"
            }

            SettingsRow {
                title: I18n.tr("API", "about page card title, application programming interface version")
                trailingBadge: `v${CyShellService.apiVersion}`
            }

            SettingsRow {
                title: I18n.tr("Status")
                trailingBadge: I18n.tr("Connected")

                CyBadge {
                    color: Theme.success
                }
            }

            SettingsRow {
                visible: CyShellService.capabilities.length > 0
                title: I18n.tr("Capabilities")
                body: Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: CyShellService.capabilities

                        CyBadge {
                            text: modelData
                            color: Theme.primaryHover
                            textColor: Theme.primary
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "build"
            title: I18n.tr("Tools", "about page card title for welcome and system check")

            SettingsNavRow {
                iconName: "waving_hand"
                title: I18n.tr("Show welcome")
                onClicked: FirstLaunchService.showWelcome()
            }

            SettingsNavRow {
                iconName: "vital_signs"
                title: I18n.tr("System check")
                onClicked: FirstLaunchService.showDoctor()
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: `<a href="https://github.com/Cytech-Team/CyShell-Desktop/blob/cyshell-dev/LICENSE" style="text-decoration:none; color:${Theme.surfaceVariantText};">${I18n.tr('MIT License')}</a>`
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            textFormat: Text.RichText
            wrapMode: Text.NoWrap
            onLinkActivated: url => Qt.openUrlExternally(url)

            HoverHandler {
                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }
}
