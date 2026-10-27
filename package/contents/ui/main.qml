import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Claude plan usage on the Plasma panel: session (5-hour) and weekly limits, like /usage.
// Data comes from the bundled contents/code/claude_usage.py (Python 3, standard library), which
// reads Claude Code's /usage reports and, if allowed, asks Claude Code for fresh numbers.
PlasmoidItem {
    id: root

    property var usage: null
    property string error: ""
    property bool busy: false
    readonly property var cfg: Plasmoid.configuration
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("../code/claude_usage.py").toString().replace(/^file:\/\//, ""))

    readonly property var shown: {
        const w = usage && usage.windows ? usage.windows : {};
        const out = [];
        if (cfg.showSession && w.five_hour) out.push({ label: i18n("Session"), short: i18nc("short for session", "S"), w: w.five_hour });
        if (cfg.showWeekly && w.seven_day) out.push({ label: i18n("Weekly"), short: i18nc("short for weekly", "W"), w: w.seven_day });
        return out;
    }

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function expand(p) {
        // "~/x" → "$HOME"'/x' (the shell expands $HOME; the rest stays quoted)
        p = String(p).trim();
        return p.startsWith("~/") ? "\"$HOME\"" + q(p.slice(1)) : q(p);
    }
    function command(mode) {
        let c = expand(cfg.pythonPath || "python3") + " " + q(script)
            + " --claude " + expand(cfg.claudePath || "claude")
            + " --model " + q(cfg.checkModel || "haiku")
            + " --max-age " + Math.max(60, cfg.maxAgeMinutes * 60);
        if (mode === "force") c += " --refresh";
        else if (mode === "auto") c += " --auto";
        return c + " #" + Date.now(); // a unique source, so the engine runs it again
    }
    function refresh(mode) {
        busy = true;
        exec.connectSource(command(mode));
    }

    function color(p) {
        if (p >= cfg.criticalAt) return Kirigami.Theme.negativeTextColor;
        if (p >= cfg.warnAt) return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.highlightColor;
    }
    function resets(ts, short) {
        if (!ts) return "";
        const mins = Math.round((ts * 1000 - Date.now()) / 60000);
        if (mins <= 0) return i18n("reset");
        if (mins < 60) return short ? i18nc("minutes, short", "%1m", mins) : i18n("resets in %1 min", mins);
        if (mins < 1440) {
            const h = Math.floor(mins / 60), m = mins % 60;
            return short ? h + "h" + (m < 10 ? "0" : "") + m : i18n("resets in %1 h %2 min", h, m);
        }
        const d = new Date(ts * 1000);
        return short ? Qt.formatDate(d, "ddd") : i18n("resets %1", Qt.formatDateTime(d, "ddd hh:mm"));
    }
    function ago(s) {
        if (s === undefined || s === null) return "";
        if (s < 90) return i18n("just now");
        if (s < 3600) return i18n("%1 min ago", Math.round(s / 60));
        if (s < 172800) return i18n("%1 h ago", Math.round(s / 3600));
        return i18n("%1 d ago", Math.round(s / 86400));
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            root.busy = false;
            const out = String(data["stdout"] || "").trim();
            if (data["exit code"] !== 0 || !out) {
                const err = String(data["stderr"] || "").trim().split("\n").pop();
                root.error = err || i18n("Could not run the usage script (is Python 3 installed?)");
                return;
            }
            try {
                root.usage = JSON.parse(out);
                root.error = root.usage.error || "";
            } catch (e) {
                root.error = i18n("Unexpected output from the usage script");
            }
        }
    }

    Timer {
        interval: Math.max(15, root.cfg.intervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(root.cfg.autoCheck ? "auto" : "no")
    }

    Plasmoid.icon: "speedometer"
    toolTipMainText: i18n("Claude usage")
    toolTipSubText: {
        if (!usage || !usage.windows) return error || i18n("No data yet");
        const lines = [];
        if (usage.windows.five_hour) lines.push(i18n("Session %1% · %2", Math.round(usage.windows.five_hour.pct), resets(usage.windows.five_hour.resets_at, false)));
        if (usage.windows.seven_day) lines.push(i18n("Weekly %1% · %2", Math.round(usage.windows.seven_day.pct), resets(usage.windows.seven_day.resets_at, false)));
        lines.push(i18n("updated %1", ago(usage.age_seconds)));
        if (error) lines.push(error);
        return lines.join("\n");
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Check now")
            icon.name: "view-refresh"
            onTriggered: root.refresh("force")
        },
        PlasmaCore.Action {
            text: i18n("Open usage page")
            icon.name: "internet-web-browser"
            enabled: !!root.cfg.openUrl
            onTriggered: Qt.openUrlExternally(root.cfg.openUrl)
        }
    ]

    // On the panel: "S ▬▬ 39%  W ▬ 11%".
    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                visible: root.shown.length === 0
                source: root.error ? "dialog-warning" : "speedometer"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            Repeater {
                model: root.shown
                delegate: RowLayout {
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        visible: root.cfg.showLabels
                        text: modelData.short
                        opacity: 0.7
                        font.pixelSize: compact.height * 0.38
                    }
                    Rectangle {
                        visible: root.cfg.displayStyle !== 1
                        Layout.preferredWidth: root.cfg.barWidth
                        Layout.preferredHeight: Math.max(4, compact.height * 0.18)
                        radius: height / 2
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(100, modelData.w.pct)) / 100
                            height: parent.height
                            radius: parent.radius
                            color: root.color(modelData.w.pct)
                        }
                    }
                    PlasmaComponents3.Label {
                        visible: root.cfg.displayStyle !== 2
                        text: Math.round(modelData.w.pct) + "%"
                        color: root.color(modelData.w.pct)
                        font.bold: true
                        font.pixelSize: compact.height * 0.38
                    }
                    PlasmaComponents3.Label {
                        visible: root.cfg.showResets
                        text: root.resets(modelData.w.resets_at, true)
                        opacity: 0.6
                        font.pixelSize: compact.height * 0.32
                    }
                }
            }
        }
    }

    // The popup: both windows in full, reset times, refresh, open the usage page.
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: implicitHeight
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading { text: i18n("Claude plan usage"); level: 4 }

        Repeater {
            model: [{ label: i18n("Session (5 h)"), w: root.usage && root.usage.windows ? root.usage.windows.five_hour : null },
                    { label: i18n("Weekly (7 days)"), w: root.usage && root.usage.windows ? root.usage.windows.seven_day : null }]
            delegate: ColumnLayout {
                required property var modelData
                visible: !!modelData.w
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label { text: modelData.label; Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        text: modelData.w ? Math.round(modelData.w.pct) + "%" : ""
                        color: modelData.w ? root.color(modelData.w.pct) : Kirigami.Theme.textColor
                        font.bold: true
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    Rectangle {
                        width: modelData.w ? parent.width * Math.max(0, Math.min(100, modelData.w.pct)) / 100 : 0
                        height: parent.height
                        radius: parent.radius
                        color: modelData.w ? root.color(modelData.w.pct) : "transparent"
                    }
                }
                PlasmaComponents3.Label {
                    text: modelData.w ? root.resets(modelData.w.resets_at, false) : ""
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        PlasmaComponents3.Label {
            visible: !root.usage || !root.usage.windows
            text: i18n("No data yet. Run /usage in Claude Code, or press Check now.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        PlasmaComponents3.Label {
            visible: !!root.error
            text: root.error
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
        }
        PlasmaComponents3.Label {
            visible: !!root.usage && root.usage.age_seconds !== undefined
            text: root.usage ? i18n("updated %1 · %2", root.ago(root.usage.age_seconds), root.usage.source) : ""
            opacity: 0.6
            font: Kirigami.Theme.smallFont
        }
        RowLayout {
            PlasmaComponents3.Button {
                text: root.busy ? i18n("Checking…") : i18n("Check now")
                icon.name: "view-refresh"
                enabled: !root.busy
                onClicked: root.refresh("force")
            }
            PlasmaComponents3.Button {
                visible: !!root.cfg.openUrl
                text: i18n("Open usage page")
                icon.name: "internet-web-browser"
                onClicked: Qt.openUrlExternally(root.cfg.openUrl)
            }
        }
    }
}
