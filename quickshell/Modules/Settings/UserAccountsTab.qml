import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null

    spacing: Theme.spacingL

    SettingsCard {
        title: I18n.tr("User account", "user account settings card title")
        settingKey: "userProfile"
        tags: ["user", "account", "profile", "avatar", "image"]

        SettingsRow {
            title: UserInfoService.fullName || UserInfoService.username
            subtitle: I18n.tr("Signed in as %1", "user account profile subtitle").arg(UserInfoService.username)
            settingKey: "profileImage"
            tags: ["user", "account", "profile", "avatar", "image"]

            leading: CyCircularImage {
                width: SettingsMetrics.avatarSize
                height: width
                imageSource: PortalService.profileImage
                fallbackIcon: "person"
            }

            CyActionButton {
                iconName: "edit"
                tooltipText: I18n.tr("Select Profile Image", "profile image file browser title")
                onClicked: root.parentModal?.openProfileBrowser()
            }

            CyActionButton {
                iconName: "close"
                Accessible.name: I18n.tr("Clear")
                enabled: PortalService.profileImage !== ""
                onClicked: PortalService.setProfileImage("")
            }
        }
    }
}
