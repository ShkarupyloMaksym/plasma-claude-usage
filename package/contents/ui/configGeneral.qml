import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showSession: showSession.checked
    property alias cfg_showWeekly: showWeekly.checked
    property alias cfg_showResets: showResets.checked
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_displayStyle: displayStyle.currentIndex
    property alias cfg_barWidth: barWidth.value
    property alias cfg_warnAt: warnAt.value
    property alias cfg_criticalAt: criticalAt.value
    property alias cfg_autoCheck: autoCheck.checked
    property alias cfg_maxAgeMinutes: maxAge.value
    property alias cfg_intervalSeconds: interval.value
    property alias cfg_checkModel: checkModel.editText
    property alias cfg_claudePath: claudePath.text
    property alias cfg_pythonPath: pythonPath.text
    property alias cfg_openUrl: openUrl.text

    Kirigami.FormLayout {
        // --- Panel ---
        QQC2.CheckBox { id: showSession; Kirigami.FormData.label: i18n("Show:"); text: i18n("Session (5 h)") }
        QQC2.CheckBox { id: showWeekly; text: i18n("Weekly (7 days)") }
        QQC2.CheckBox { id: showLabels; text: i18n("Labels (S / W)") }
        QQC2.CheckBox { id: showResets; text: i18n("Reset times") }
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
        RowLayout {
            Kirigami.FormData.label: i18n("Colour from:")
            QQC2.SpinBox { id: warnAt; from: 1; to: 100; textFromValue: (v) => v + " %"; valueFromText: (t) => parseInt(t) }
            QQC2.Label { text: i18n("warning,") }
            QQC2.SpinBox { id: criticalAt; from: 1; to: 100; textFromValue: (v) => v + " %"; valueFromText: (t) => parseInt(t) }
            QQC2.Label { text: i18n("critical") }
        }

        Item { Kirigami.FormData.isSection: true }

        // --- Updates ---
        QQC2.CheckBox {
            id: autoCheck
            Kirigami.FormData.label: i18n("Updates:")
            text: i18n("Ask Claude Code for fresh numbers when they get old")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: i18n("One tiny call (no tools, a one-word reply; about $0.0006 with Haiku) that only fetches your limits. Off: the widget only shows what /usage in a terminal last reported.")
        }
        QQC2.SpinBox {
            id: maxAge
            Kirigami.FormData.label: i18n("…when older than (min):")
            from: 1; to: 1440
            enabled: autoCheck.checked
        }
        QQC2.ComboBox {
            id: checkModel
            Kirigami.FormData.label: i18n("Model for the check:")
            editable: true
            model: ["haiku", "sonnet", "opus"]
            enabled: autoCheck.checked
        }
        QQC2.SpinBox { id: interval; Kirigami.FormData.label: i18n("Re-read every (s):"); from: 15; to: 3600; stepSize: 15 }

        Item { Kirigami.FormData.isSection: true }

        // --- Paths ---
        QQC2.TextField { id: claudePath; Kirigami.FormData.label: i18n("Claude Code:"); placeholderText: "claude" }
        QQC2.TextField { id: pythonPath; Kirigami.FormData.label: i18n("Python 3:"); placeholderText: "python3" }
        QQC2.TextField {
            id: openUrl
            Kirigami.FormData.label: i18n("\"Open\" goes to:")
            placeholderText: "https://claude.ai/settings/usage"
        }
    }
}
