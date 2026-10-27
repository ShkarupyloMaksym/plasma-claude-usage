import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_autoCheck: autoCheck.checked
    property alias cfg_maxAgeMinutes: maxAge.value
    property alias cfg_staleMinutes: stale.value
    property alias cfg_intervalSeconds: interval.value
    property alias cfg_notifyReset: notifyReset.checked
    property alias cfg_notifyThresholds: notifyThresholds.checked
    property alias cfg_claudePath: claudePath.text
    property alias cfg_pythonPath: pythonPath.text
    property alias cfg_openUrl: openUrl.text

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: autoCheck
            Kirigami.FormData.label: i18n("Updates:")
            text: i18n("Ask Claude Code for /usage when the numbers get old")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: i18n("Runs \"claude -p /usage\" in an empty folder. Claude Code answers it locally, without a model call, so it doesn't use any of your plan. Off: only what /usage in a terminal last reported.")
        }
        QQC2.SpinBox {
            id: maxAge
            Kirigami.FormData.label: i18n("…when older than (min):")
            from: 1; to: 1440
            enabled: autoCheck.checked
        }
        QQC2.SpinBox {
            id: stale
            Kirigami.FormData.label: i18n("Dim when older than (min):")
            from: 1; to: 10080
        }
        QQC2.SpinBox { id: interval; Kirigami.FormData.label: i18n("Re-read every (s):"); from: 15; to: 3600; stepSize: 15 }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox { id: notifyReset; Kirigami.FormData.label: i18n("Notify:"); text: i18n("When a limit resets") }
        QQC2.CheckBox { id: notifyThresholds; text: i18n("When usage crosses the warning and critical levels") }

        Item { Kirigami.FormData.isSection: true }

        QQC2.TextField { id: claudePath; Kirigami.FormData.label: i18n("Claude Code:"); placeholderText: "claude" }
        QQC2.TextField { id: pythonPath; Kirigami.FormData.label: i18n("Python 3:"); placeholderText: "python3" }
        QQC2.TextField {
            id: openUrl
            Kirigami.FormData.label: i18n("\"Open\" goes to:")
            placeholderText: "https://claude.ai/settings/usage"
        }
    }
}
