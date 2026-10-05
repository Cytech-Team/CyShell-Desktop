pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.Widgets

Item {
    id: root

    readonly property var supportedProfiles: {
        const profiles = PowerProfileWatcher.availableProfiles;
        const performanceSupported = typeof PowerProfiles !== "undefined" && PowerProfiles.hasPerformanceProfile;
        return profiles.filter(profile => profile !== PowerProfile.Performance || performanceSupported);
    }

    function profileLabel(profile) {
        return Theme.getPowerProfileLabel(profile);
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            title: I18n.tr("Power Mode")
            settingKey: "powerProfileCard"
            tags: ["power profile", "power profiles", "power saver", "balanced", "performance"]

            SettingsRow {
                settingKey: "currentPowerProfile"
                title: I18n.tr("Power profile")
                subtitle: root.profileLabel(PowerProfileWatcher.currentProfile)
            }

            SettingsButtonGroupRow {
                text: I18n.tr("Power profile")
                description: PowerProfileWatcher.available ? I18n.tr("Choose a power profile") : I18n.tr("power-profiles-daemon not available")
                settingKey: "powerProfileSelection"
                tags: ["power profile", "power profiles", "power saver", "balanced", "performance mode"]
                model: root.supportedProfiles.map(profile => root.profileLabel(profile))
                currentIndex: root.supportedProfiles.indexOf(PowerProfileWatcher.currentProfile)
                enabled: PowerProfileWatcher.available
                onSelectionChanged: (index, selected) => {
                    if (!selected || !PowerProfileWatcher.available)
                        return;
                    if (!PowerProfileWatcher.applyProfile(root.supportedProfiles[index]))
                        ToastService.showError(I18n.tr("Failed to set power profile"));
                }
            }

            SettingsRow {
                visible: !PowerProfileWatcher.available
                settingKey: "powerProfileUnavailable"
                title: I18n.tr("power-profiles-daemon not available")
            }
        }
    }
}
