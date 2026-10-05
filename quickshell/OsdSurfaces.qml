pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.OSD
import qs.Services

Item {
    id: root

    property bool surfacesLoaded: false
    property int pendingResumeReloads: 0

    readonly property var dankIslandScreens: Quickshell.screens.filter(screen => SettingsData.dankIslandCoversScreen(screen))
    readonly property var legacySystemLevelOsdScreens: withoutCyIslandScreens(SettingsData.getFilteredScreens("osd"))

    function withoutCyIslandScreens(screens) {
        if (!SettingsData.dankIslandEnabled)
            return screens;
        return screens.filter(screen => root.dankIslandScreens.indexOf(screen) === -1);
    }

    function recreate() {
        OSDManager.currentOSDsByScreen = ({});
        surfacesLoaded = false;
        reloadTimer.restart();
    }

    Timer {
        id: resumeTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.recreate();
            root.pendingResumeReloads--;
            if (root.pendingResumeReloads <= 0) {
                root.pendingResumeReloads = 0;
                interval = 400;
                return;
            }
            interval = 1400;
            restart();
        }
    }

    Timer {
        id: reloadTimer
        interval: 120
        repeat: false
        onTriggered: root.surfacesLoaded = true
    }

    Timer {
        id: startupTimer
        interval: 1000
        repeat: false
        onTriggered: root.surfacesLoaded = true
    }

    Component.onCompleted: startupTimer.start()

    Connections {
        target: SessionService
        function onSessionResumed() {
            root.pendingResumeReloads = 2;
            resumeTimer.interval = 400;
            resumeTimer.restart();
        }
    }

    Loader {
        active: root.surfacesLoaded
        asynchronous: false

        sourceComponent: Component {
            Item {
                Variants {
                    model: root.legacySystemLevelOsdScreens
                    delegate: VolumeOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: MediaVolumeOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: MediaPlaybackOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: MicVolumeOSD {}
                }

                Variants {
                    model: root.legacySystemLevelOsdScreens
                    delegate: BrightnessOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: IdleInhibitorOSD {}
                }

                Variants {
                    model: SettingsData.osdPowerProfileEnabled ? SettingsData.getFilteredScreens("osd") : []
                    delegate: PowerProfileOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: CapsLockOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: LanguageOSD {}
                }

                Variants {
                    model: SettingsData.getFilteredScreens("osd")
                    delegate: AudioOutputOSD {}
                }

                Variants {
                    model: SettingsData.osdWorkspaceEnabled ? SettingsData.getFilteredScreens("osd") : []
                    delegate: WorkspaceOSD {}
                }
            }
        }
    }
}
