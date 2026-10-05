import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null
    property date now: systemClock.date
    property string timeText: now.toLocaleTimeString(I18n.locale(), SettingsData.getEffectiveTimeFormat())
    property string dateText: now.toLocaleDateString(I18n.locale(), SettingsData.getEffectiveDateFormat(Locale.ShortFormat))

    SystemClock {
        id: systemClock
        precision: SettingsData.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Connections {
        target: SessionService
        function onSessionResumed() {
            systemClock.enabled = false;
            systemClock.enabled = true;
        }
    }

    pillClickAction: (x, y, width, section, screen) => popoutService?.toggleNotificationCenter(x, y, width, section, screen)

    horizontalBarPill: Component {
        Column {
            spacing: 0
            StyledText {
                width: 68
                text: root.timeText
                font.pixelSize: 11
                font.weight: Font.Medium
                color: Theme.widgetTextColor
                horizontalAlignment: Text.AlignHCenter
            }
            StyledText {
                width: 68
                text: root.dateText
                font.pixelSize: 10
                font.weight: Font.Medium
                color: Theme.widgetTextColor
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    verticalBarPill: Component {
        StyledText { text: root.timeText; color: Theme.widgetTextColor }
    }
}
