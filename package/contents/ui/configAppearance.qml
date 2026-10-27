import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    property alias cfg_showSession: showSession.checked
    property alias cfg_showWeekly: showWeekly.checked
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_showResets: showResets.checked
    property alias cfg_showRemaining: showRemaining.checked
    property alias cfg_showPace: showPace.checked
    property alias cfg_displayStyle: displayStyle.currentIndex
    property alias cfg_barWidth: barWidth.value
    property alias cfg_warnAt: warnAt.value
    property alias cfg_criticalAt: criticalAt.value
    property string cfg_normalColor
    property string cfg_warnColor
    property string cfg_criticalColor

    // A colour setting: the theme's colour unless the user picks one.
    component ColorSetting: RowLayout {
        id: setting
        property string value
        property color themeColor
        signal picked(string v)
        KQuickControls.ColorButton {
            color: setting.value ? setting.value : setting.themeColor
            onAccepted: (c) => setting.picked(c.toString())
        }
        QQC2.Button {
            text: i18n("Theme")
            icon.name: "edit-undo"
            enabled: !!setting.value
            onClicked: setting.picked("")
        }
    }

    Kirigami.FormLayout {
        QQC2.CheckBox { id: showSession; Kirigami.FormData.label: i18n("Show:"); text: i18n("Session (5 h)") }
        QQC2.CheckBox { id: showWeekly; text: i18n("Weekly (7 days)") }
        QQC2.CheckBox { id: showLabels; text: i18n("Labels (S / W)") }
        QQC2.CheckBox { id: showResets; text: i18n("Time until reset") }
        QQC2.CheckBox { id: showPace; text: i18n("Pace marker (where an even pace would be)") }
        QQC2.CheckBox { id: showRemaining; text: i18n("Percent remaining instead of used") }

        QQC2.ComboBox {
            id: displayStyle
            Kirigami.FormData.label: i18n("Style:")
            model: [i18n("Bar and percent"), i18n("Percent only"), i18n("Bar only")]
        }
        QQC2.SpinBox {
            id: barWidth
            Kirigami.FormData.label: i18n("Bar width (px):")
            from: 12; to: 200; stepSize: 4
            enabled: displayStyle.currentIndex !== 1
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            Kirigami.FormData.label: i18n("Warning from:")
            QQC2.SpinBox { id: warnAt; from: 1; to: 100 }
            QQC2.Label { text: i18n("% used") }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Critical from:")
            QQC2.SpinBox { id: criticalAt; from: 1; to: 100 }
            QQC2.Label { text: i18n("% used") }
        }
        ColorSetting {
            Kirigami.FormData.label: i18n("Normal colour:")
            value: cfg_normalColor
            themeColor: Kirigami.Theme.positiveTextColor
            onPicked: (v) => cfg_normalColor = v
        }
        ColorSetting {
            Kirigami.FormData.label: i18n("Warning colour:")
            value: cfg_warnColor
            themeColor: Kirigami.Theme.neutralTextColor
            onPicked: (v) => cfg_warnColor = v
        }
        ColorSetting {
            Kirigami.FormData.label: i18n("Critical colour:")
            value: cfg_criticalColor
            themeColor: Kirigami.Theme.negativeTextColor
            onPicked: (v) => cfg_criticalColor = v
        }
    }
}
