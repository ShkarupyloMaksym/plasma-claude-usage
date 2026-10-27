import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Claude plan usage on the Plasma panel: session (5-hour), weekly and any other limits, like /usage.
// Data comes from the bundled contents/code/claude_usage.py (Python 3, standard library), which asks
// Claude Code for /usage headless (answered locally: no model call, no cost).
PlasmoidItem {
    id: root

    property var usage: null
    property string error: ""
    property bool busy: false
    property real now: Date.now()          // ticks, so countdowns and staleness update between reads
    property var previous: ({})            // last seen pct / resets_at per window, for notifications
    readonly property var cfg: Plasmoid.configuration
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("../code/claude_usage.py").toString().replace(/^file:\/\//, ""))
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real ageSeconds: usage && usage.at ? Math.max(0, now / 1000 - usage.at) : -1
    readonly property bool stale: ageSeconds > cfg.staleMinutes * 60

    // Window lengths, for the pace marker.
    readonly property var lengths: ({ five_hour: 5 * 3600, seven_day: 7 * 86400 })

    readonly property var windows: {
        const w = usage && usage.windows ? usage.windows : {};
        const out = [];
        for (const key of Object.keys(w)) {
            const label = key === "five_hour" ? i18n("Session (5 h)") : key === "seven_day" ? i18n("Weekly (7 days)")
                        : (w[key].label || key.replace(/_/g, " "));
            const short = key === "five_hour" ? i18nc("short for session", "S") : key === "seven_day" ? i18nc("short for weekly", "W") : "";
            out.push({ key: key, label: label, short: short, w: w[key] });
        }
        const order = (k) => k === "five_hour" ? 0 : k === "seven_day" ? 1 : 2;
        return out.sort((a, b) => order(a.key) - order(b.key));
    }
    readonly property var compactWindows: windows.filter((x) =>
        (x.key === "five_hour" && cfg.showSession) || (x.key === "seven_day" && cfg.showWeekly))
    readonly property real worst: windows.reduce((m, x) => Math.max(m, x.w.pct), 0)
    // What a row shows for the instant between a count change and its new data.
    readonly property var emptyWindow: ({ key: "", label: "", short: "", w: { pct: 0, resets_at: 0 } })

    // --- colours: from a theme reference that never inherits, so the colours don't change when
    // Plasma switches the colour set of the applet's surroundings (selected / expanded / panel).
    Item {
        id: themeRef
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
    }
    function color(p) {
        if (p >= cfg.criticalAt) return cfg.criticalColor || themeRef.Kirigami.Theme.negativeTextColor;
        if (p >= cfg.warnAt) return cfg.warnColor || themeRef.Kirigami.Theme.neutralTextColor;
        return cfg.normalColor || themeRef.Kirigami.Theme.positiveTextColor;
    }

    // --- helpers ---------------------------------------------------------------------------------
    function shown(p) { return Math.round(cfg.showRemaining ? 100 - p : p); }
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function expand(p) {
        // "~/x" → "$HOME"'/x' (the shell expands $HOME; the rest stays quoted)
        p = String(p).trim();
        return p.startsWith("~/") ? "\"$HOME\"" + q(p.slice(1)) : q(p);
    }
    function command(mode) {
        let c = expand(cfg.pythonPath || "python3") + " " + q(script)
            + " --claude " + expand(cfg.claudePath || "claude")
            + " --max-age " + Math.max(60, cfg.maxAgeMinutes * 60);
        if (mode === "force") c += " --refresh";
        else if (mode === "auto") c += " --auto";
        return c + " #" + Date.now(); // a unique source, so the engine runs it again
    }
    function refresh(mode) {
        busy = true;
        exec.connectSource(command(mode));
    }
    function span(seconds, short) {
        const mins = Math.max(0, Math.round(seconds / 60));
        if (mins < 60) return short ? i18nc("minutes, short", "%1m", mins) : i18np("%1 min", "%1 min", mins);
        if (mins < 1440) {
            const h = Math.floor(mins / 60), m = mins % 60;
            return short ? h + "h" + (m < 10 ? "0" : "") + m : i18n("%1 h %2 min", h, m);
        }
        const d = Math.floor(mins / 1440), h = Math.floor((mins % 1440) / 60);
        return short ? d + "d" : i18n("%1 d %2 h", d, h);
    }
    function resets(ts, short) {
        if (!ts) return "";
        const left = ts - now / 1000;
        if (left <= 0) return i18n("reset");
        if (short) return left < 86400 ? span(left, true) : Qt.formatDate(new Date(ts * 1000), "ddd");
        return left < 86400 ? i18n("resets in %1", span(left, false))
                            : i18n("resets %1", Qt.formatDateTime(new Date(ts * 1000), "ddd hh:mm"));
    }
    // Where an even pace would be now (0..1), or -1 if unknown.
    function paceFraction(key, w) {
        const len = lengths[key] || (key.startsWith("weekly") ? lengths.seven_day : 0);
        if (!len || !w.resets_at) return -1;
        return Math.max(0, Math.min(1, 1 - (w.resets_at - now / 1000) / len));
    }
    function paceText(key, w) {
        const f = paceFraction(key, w);
        if (f < 0.05 || w.pct <= 0) return "";
        const len = lengths[key] || lengths.seven_day;
        const elapsed = f * len, rate = w.pct / elapsed;      // percent per second so far
        const projected = w.pct / f;
        if (projected <= 100) return i18n("At this pace: about %1% by the reset", Math.round(projected));
        return i18n("At this pace you reach 100% in about %1, before the reset", span((100 - w.pct) / rate, false));
    }
    function ago(s) {
        if (s < 0) return "";
        if (s < 90) return i18n("just now");
        return i18n("%1 ago", span(s, false));
    }

    // --- data --------------------------------------------------------------------------------------
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
                const u = JSON.parse(out);
                root.notifyChanges(u);
                root.usage = u;
                root.error = u.error || "";
            } catch (e) {
                root.error = i18n("Unexpected output from the usage script");
            }
        }
    }

    function notifyChanges(u) {
        const ws = u && u.windows ? u.windows : {};
        const prev = previous, next = {};
        for (const key of Object.keys(ws)) {
            const w = ws[key], p = prev[key];
            next[key] = { pct: w.pct, resets_at: w.resets_at };
            if (!p || !notifierLoader.item) continue;          // first reading: nothing to compare with
            const name = key === "five_hour" ? i18n("Session") : key === "seven_day" ? i18n("Weekly") : (w.label || key);
            if (cfg.notifyReset && w.resets_at && p.resets_at && w.resets_at > p.resets_at + 60 && p.pct >= 1) {
                notifierLoader.item.send(i18n("Claude: %1 limit reset", name), i18n("Now at %1% used.", Math.round(w.pct)), "view-refresh", false);
            } else if (cfg.notifyThresholds && p.pct < cfg.criticalAt && w.pct >= cfg.criticalAt) {
                notifierLoader.item.send(i18n("Claude: %1 at %2%", name, Math.round(w.pct)), resets(w.resets_at, false), "dialog-warning", true);
            } else if (cfg.notifyThresholds && p.pct < cfg.warnAt && w.pct >= cfg.warnAt) {
                notifierLoader.item.send(i18n("Claude: %1 at %2%", name, Math.round(w.pct)), resets(w.resets_at, false), "dialog-information", false);
            }
        }
        previous = next;
    }

    Loader {
        id: notifierLoader
        source: "Notifier.qml"   // fails quietly if org.kde.notification isn't installed
    }

    Timer {
        interval: Math.max(15, root.cfg.intervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(root.cfg.autoCheck ? "auto" : "no")
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // --- Plasma integration ----------------------------------------------------------------------
    Plasmoid.icon: "speedometer"
    // In the system tray: hidden in the overflow only while there is nothing to show; asks for
    // attention at the critical level.
    Plasmoid.status: !usage || !usage.windows ? PlasmaCore.Types.PassiveStatus
                   : worst >= cfg.criticalAt ? PlasmaCore.Types.NeedsAttentionStatus
                   : PlasmaCore.Types.ActiveStatus
    // On the desktop with enough room, show the full view instead of the compact one.
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 8

    toolTipMainText: i18n("Claude usage")
    toolTipSubText: {
        if (!usage || !usage.windows) return error || i18n("No data yet");
        const lines = windows.map((x) => i18n("%1: %2% %3 · %4", x.label, shown(x.w.pct),
                                             cfg.showRemaining ? i18n("left") : i18n("used"), resets(x.w.resets_at, false)));
        lines.push(stale ? i18n("updated %1 (old)", ago(ageSeconds)) : i18n("updated %1", ago(ageSeconds)));
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

    // --- the bar used in both views -------------------------------------------------------------
    component UsageBar: Rectangle {
        id: bar
        property string key
        property var w
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, bar.w ? bar.w.pct : 0)) / 100
            height: parent.height
            radius: parent.radius
            color: bar.w ? root.color(bar.w.pct) : "transparent"
        }
        Rectangle {   // pace marker: where an even pace would be by now
            readonly property real f: bar.w && root.cfg.showPace ? root.paceFraction(bar.key, bar.w) : -1
            visible: f >= 0
            x: Math.round(f * (parent.width - width))
            width: Math.max(1, Math.round(parent.height / 3))
            height: parent.height + 2
            anchors.verticalCenter: parent.verticalCenter
            color: Kirigami.Theme.textColor
            opacity: 0.6
        }
    }

    // --- on the panel ------------------------------------------------------------------------------
    compactRepresentation: MouseArea {
        id: compact
        readonly property real fontPx: root.vertical ? Kirigami.Theme.smallFont.pixelSize : compact.height * 0.38
        Layout.minimumWidth: root.vertical ? -1 : grid.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: root.vertical ? grid.implicitHeight + Kirigami.Units.smallSpacing * 2 : -1
        Layout.preferredHeight: Layout.minimumHeight
        hoverEnabled: true
        opacity: root.stale ? 0.55 : 1
        onClicked: root.expanded = !root.expanded

        activeFocusOnTab: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Select) {
                root.expanded = !root.expanded;
                event.accepted = true;
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: i18n("Claude usage")
        Accessible.description: root.toolTipSubText

        GridLayout {
            id: grid
            anchors.centerIn: parent
            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                visible: root.compactWindows.length === 0
                source: root.error ? "dialog-warning" : "speedometer"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignHCenter
            }
            Repeater {
                // A count, not the array: rows are recreated only when the number of limits changes,
                // never on a data refresh. Recreating items inside a layout while the popup opened
                // crashed plasmashell (QGridLayoutEngine touched a deleted item).
                model: root.compactWindows.length
                delegate: RowLayout {
                    required property int index
                    readonly property var modelData: root.compactWindows[index] || root.emptyWindow
                    spacing: Kirigami.Units.smallSpacing
                    Layout.alignment: Qt.AlignHCenter
                    PlasmaComponents3.Label {
                        visible: root.cfg.showLabels && !!modelData.short
                        text: modelData.short
                        opacity: 0.7
                        font.pixelSize: compact.fontPx
                    }
                    UsageBar {
                        visible: root.cfg.displayStyle !== 1 && !root.vertical
                        key: modelData.key
                        w: modelData.w
                        Layout.preferredWidth: root.cfg.barWidth
                        Layout.preferredHeight: Math.max(4, compact.height * 0.18)
                    }
                    PlasmaComponents3.Label {
                        visible: root.cfg.displayStyle !== 2 || root.vertical
                        text: root.shown(modelData.w.pct) + "%"
                        color: root.color(modelData.w.pct)
                        font.bold: true
                        font.pixelSize: compact.fontPx
                    }
                    PlasmaComponents3.Label {
                        visible: root.cfg.showResets && !root.vertical
                        text: root.resets(modelData.w.resets_at, true)
                        opacity: 0.6
                        font.pixelSize: compact.fontPx * 0.85
                    }
                }
            }
        }
    }

    // --- the popup (and the desktop view) -----------------------------------------------------------
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: implicitHeight
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading { text: i18n("Claude plan usage"); level: 4 }

        Repeater {
            model: root.windows.length   // a count, see the compact view
            delegate: ColumnLayout {
                required property int index
                readonly property var modelData: root.windows[index] || root.emptyWindow
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label { text: modelData.label; Layout.fillWidth: true; elide: Text.ElideRight }
                    PlasmaComponents3.Label {
                        text: root.cfg.showRemaining ? i18n("%1% left", root.shown(modelData.w.pct)) : i18n("%1% used", root.shown(modelData.w.pct))
                        color: root.color(modelData.w.pct)
                        font.bold: true
                    }
                }
                UsageBar {
                    key: modelData.key
                    w: modelData.w
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
                }
                PlasmaComponents3.Label {
                    text: [root.resets(modelData.w.resets_at, false), root.cfg.showPace ? root.paceText(modelData.key, modelData.w) : ""]
                          .filter((s) => !!s).join(" · ")
                    opacity: 0.7
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        PlasmaComponents3.Label {
            visible: root.windows.length === 0
            text: i18n("No data yet. Run /usage in Claude Code, or press Check now.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        PlasmaComponents3.Label {
            visible: !!root.error
            text: root.error
            color: themeRef.Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
        }
        PlasmaComponents3.Label {
            visible: root.ageSeconds >= 0
            text: i18n("updated %1 · %2", root.ago(root.ageSeconds), root.usage ? root.usage.source : "")
            color: root.stale ? themeRef.Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            opacity: root.stale ? 1 : 0.6
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
