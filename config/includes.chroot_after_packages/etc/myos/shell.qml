// MyOS shell v2: shelf, launcher, quick settings.
// Reads user settings from ~/.config/myos/settings.json (written by the Settings app).
// A copy of the previous stable shell is in /etc/myos/stable/shell.qml
// (Super+Shift+R switches to it if something goes wrong).

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

ShellRoot {
    id: root

    // ===== state =====
    property bool launcherOpen: false
    property bool panelOpen: false
    property string query: ""
    property string layoutLabel: "EN"
    property int batteryPct: -1
    property bool batteryCharging: false
    property string lastSettings: ""
    property bool wifiOn: true
    property bool btOn: false
    property bool wifiOpen: false
    property var wifiList: []
    property var savedNets: []
    property string wifiSelected: ""
    property bool wifiSelectedSecure: false
    property string wifiMsg: ""

    // ===== user settings (defaults; overridden by settings.json) =====
    property bool dark: false
    property color accent: "#4C7BDE"
    property bool onBottom: true
    property int iconSize: 30
    property real shelfOpacity: 1.0
    readonly property var defaultPinned: [
        { n: "Terminal",    id: "foot",       icons: ["utilities-terminal", "terminal"],        cmd: ["foot"] },
        { n: "Files",       id: "thunar",     icons: ["system-file-manager", "thunar"],         cmd: ["thunar"] },
        { n: "Browser",     id: "firefox",    icons: ["firefox-esr", "firefox", "web-browser"], cmd: ["firefox-esr"] },
        { n: "Text Editor", id: "mousepad",   icons: ["accessories-text-editor", "mousepad"],   cmd: ["mousepad"] },
        { n: "Settings",    id: "quickshell", icons: ["preferences-system"],                    cmd: ["qs", "-p", "/etc/myos/settings"] }
    ]
    property var pinned: defaultPinned

    // ===== derived colors =====
    readonly property int shelfH: iconSize + 22
    readonly property color cPanel: dark ? "#2A2F40" : "#FFFFFF"
    readonly property color cShelf: Qt.alpha(dark ? "#222634" : "#F4F6FB", shelfOpacity)
    readonly property color cText: dark ? "#EEF0F6" : "#1F2433"
    readonly property color cMuted: dark ? "#A6ADC2" : "#666677"
    readonly property color cField: dark ? "#363C52" : "#EEF1F8"
    readonly property color cChip: dark ? "#41485F" : "#E3E9F6"

    readonly property bool isHypr: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? true : false

    // ===== helpers =====
    function launch(cmd) {
        var a = []
        for (var i = 0; i < cmd.length; i++) a.push(cmd[i])
        if (isHypr) Quickshell.execDetached(["hyprctl", "dispatch", "exec", a.join(" ")])
        else Quickshell.execDetached(a)
    }
    function launchEntry(e) {
        if (e.command && e.command.length > 0) launch(e.command)
        else e.execute()
    }
    function closeActive() {
        Quickshell.execDetached(isHypr ? ["hyprctl", "dispatch", "killactive"] : ["swaymsg", "kill"])
    }
    function maximizeActive() {
        Quickshell.execDetached(isHypr ? ["hyprctl", "dispatch", "fullscreen", "1"] : ["swaymsg", "fullscreen", "toggle"])
    }
    function floatActive() {
        Quickshell.execDetached(isHypr ? ["hyprctl", "dispatch", "togglefloating"] : ["swaymsg", "floating", "toggle"])
    }
    function switchKeyboard() {
        Quickshell.execDetached(isHypr
            ? ["hyprctl", "switchxkblayout", "all", "next"]
            : ["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"])
    }
    function exitSession() {
        Quickshell.execDetached(isHypr ? ["hyprctl", "dispatch", "exit"] : ["swaymsg", "exit"])
    }
    function ico(names) {
        for (var i = 0; i < names.length; i++) {
            var p = Quickshell.iconPath(names[i], true)
            if (p !== "") return p
        }
        return Quickshell.iconPath("application-x-executable")
    }
    function isRunning(id) {
        var t = ToplevelManager.toplevels.values
        var k = (id || "").toLowerCase()
        if (k === "") return false
        for (var i = 0; i < t.length; i++) {
            var a = (t[i].appId || "").toLowerCase()
            if (a !== "" && (a.indexOf(k) >= 0 || k.indexOf(a) >= 0)) return true
        }
        return false
    }

    // ===== settings file =====
    function applySettings(text) {
        if (text === lastSettings) return
        lastSettings = text
        var s
        try { s = JSON.parse(text) } catch (e) { return }
        if (s.dark !== undefined) dark = s.dark
        if (s.accent) accent = s.accent
        if (s.shelfPos) onBottom = (s.shelfPos !== "top")
        if (s.iconSize) iconSize = s.iconSize
        if (s.shelfOpacity !== undefined) shelfOpacity = s.shelfOpacity
        if (s.pinned && s.pinned.length) pinned = s.pinned
        if (!isHypr) return
        var kw = function (k, v) { Quickshell.execDetached(["hyprctl", "keyword", k, String(v)]) }
        if (s.rounding !== undefined) kw("decoration:rounding", s.rounding)
        if (s.gaps !== undefined) { kw("general:gaps_in", Math.round(s.gaps / 2)); kw("general:gaps_out", s.gaps) }
        if (s.shadows !== undefined) kw("decoration:shadow:enabled", s.shadows ? 1 : 0)
        if (s.animations !== undefined) kw("animations:enabled", s.animations ? 1 : 0)
        if (s.blur !== undefined) kw("decoration:blur:enabled", s.blur ? 1 : 0)
        if (s.accent) kw("general:col.active_border", "rgba(" + String(s.accent).replace("#", "") + "ff)")
        if (s.monitor && s.monitor.name) kw("monitor", s.monitor.name + "," + s.monitor.mode + ",auto," + s.monitor.scale)
    }
    function saveSetting(key, value) {
        var s = {}
        try { s = JSON.parse(lastSettings) } catch (e) { s = {} }
        s[key] = value
        cfg.setText(JSON.stringify(s, null, 2))
    }

    FileView {
        id: cfg
        path: Quickshell.env("HOME") + "/.config/myos/settings.json"
        onLoaded: root.applySettings(cfg.text())
    }
    // check the settings file every 2 seconds (simple and reliable)
    Timer { interval: 2000; running: true; repeat: true; onTriggered: cfg.reload() }

    Component.onCompleted: {
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/myos\"; [ -f \"$HOME/.config/myos/settings.json\" ] || echo '{}' > \"$HOME/.config/myos/settings.json\""])
    }

    // ===== battery (laptops only) =====
    Process {
        id: batProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1; cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n")
                if (l[0] !== "") {
                    root.batteryPct = parseInt(l[0])
                    root.batteryCharging = (l[1] === "Charging")
                } else {
                    root.batteryPct = -1
                }
            }
        }
    }
    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { batProc.running = false; batProc.running = true }
    }

    // ===== keyboard layout indicator =====
    Process {
        id: kbProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var k = JSON.parse(text).keyboards
                    var m = ""
                    for (var i = 0; i < k.length; i++) { if (k[i].main) m = k[i].active_keymap }
                    if (m === "" && k.length > 0) m = k[k.length - 1].active_keymap
                    root.layoutLabel = (m.indexOf("Arab") >= 0) ? "AR" : "EN"
                } catch (e) { }
            }
        }
    }
    Timer {
        interval: 1500; running: root.isHypr; repeat: true
        onTriggered: { kbProc.running = false; kbProc.running = true }
    }

    // ===== Wi-Fi and Bluetooth =====
    function toggleWifi() {
        wifiOn = !wifiOn
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "on" : "off"])
    }
    function toggleBt() {
        btOn = !btOn
        Quickshell.execDetached(["sh", "-c", btOn ? "rfkill unblock bluetooth; bluetoothctl power on" : "bluetoothctl power off"])
    }
    function isSaved(ssid) {
        for (var i = 0; i < savedNets.length; i++) { if (savedNets[i] === ssid) return true }
        return false
    }
    function refreshWifi() {
        wifiScan.running = false; wifiScan.running = true
        savedProc.running = false; savedProc.running = true
    }
    function openWifi() {
        panelOpen = false
        launcherOpen = false
        wifiSelected = ""
        wifiMsg = ""
        wifiOpen = true
        Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"])
        refreshWifi()
    }
    function parseWifi(text) {
        var t = text.replace(/\\:/g, "\u0001")
        var lines = t.split("\n")
        var seen = {}
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var p = lines[i].split(":")
            if (p.length < 4) continue
            var ssid = p.slice(1, p.length - 2).join(":").replace(/\u0001/g, ":")
            if (ssid === "" || seen[ssid]) continue
            seen[ssid] = true
            var sec = p[p.length - 1]
            out.push({ ssid: ssid, inuse: p[0] === "*", signal: parseInt(p[p.length - 2]), secure: sec !== "" && sec !== "--" })
        }
        out.sort(function (a, b) { return (b.inuse ? 1000 : 0) + b.signal - ((a.inuse ? 1000 : 0) + a.signal) })
        wifiList = out
    }
    function connectWifi(ssid, pw) {
        var cmd = ["nmcli", "dev", "wifi", "connect", ssid]
        if (pw.length > 0) cmd = cmd.concat(["password", pw])
        wifiConn.command = cmd
        wifiMsg = "Connecting to " + ssid + "..."
        wifiConn.running = false
        wifiConn.running = true
    }

    Process {
        id: wifiState
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: root.wifiOn = (text.trim() === "enabled") }
    }
    Process {
        id: btState
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.btOn = (text.trim() === "on") }
    }
    Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            wifiState.running = false; wifiState.running = true
            btState.running = false; btState.running = true
        }
    }
    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector { onStreamFinished: root.parseWifi(text) }
    }
    Process {
        id: savedProc
        command: ["nmcli", "-t", "-f", "NAME", "connection", "show"]
        stdout: StdioCollector { onStreamFinished: root.savedNets = text.split("\n") }
    }
    Process {
        id: wifiConn
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length) root.wifiMsg = text.trim()
                root.refreshWifi()
            }
        }
        stderr: StdioCollector { onStreamFinished: { if (text.trim().length) root.wifiMsg = text.trim() } }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    ScriptModel {
        id: appModel
        values: DesktopEntries.applications.values
            .filter(function (e) {
                return !e.noDisplay && e.name.toLowerCase().indexOf(root.query.toLowerCase()) >= 0
            })
            .sort(function (a, b) { return a.name.localeCompare(b.name) })
    }

    // ===== reusable pieces =====
    component QBtn: Rectangle {
        id: b
        property string label
        property string iconName
        property color tint: "#EEF1F8"
        property color fg: "#1F2433"
        signal clicked()
        height: 44
        radius: 22
        color: ma.containsMouse ? Qt.darker(tint, 1.08) : tint
        Row {
            anchors.centerIn: parent
            spacing: 8
            IconImage {
                implicitSize: 18
                source: Quickshell.iconPath(b.iconName, "application-x-executable")
            }
            Text { text: b.label; color: b.fg; font.pixelSize: 13 }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    component QSlider: Item {
        id: sl
        property real value: 0.5
        property color accent: "#4C7BDE"
        property color track: "#DCE3F2"
        signal moved(real v)
        height: 26
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: sl.track
            Rectangle { width: parent.width * sl.value; height: parent.height; radius: 3; color: sl.accent }
        }
        Rectangle {
            x: (sl.width - width) * sl.value
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 9
            color: sl.accent
        }
        MouseArea {
            anchors.fill: parent
            function setFrom(mx) { sl.value = Math.max(0, Math.min(1, mx / sl.width)) }
            onPressed: (m) => setFrom(m.x)
            onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
            onReleased: sl.moved(sl.value)
        }
    }

    // Small drawn icons whose color we can change (wifi, bluetooth, theme)
    component Glyph: Canvas {
        id: gl
        property string kind: "wifi"
        property color tone: "#1F2433"
        width: 22; height: 22
        onToneChanged: requestPaint()
        onKindChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = tone
            ctx.fillStyle = tone
            ctx.lineWidth = 2.2
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            var w = width, h = height
            if (kind === "wifi") {
                var cx = w / 2, cy = h * 0.88
                var rs = [h * 0.32, h * 0.58, h * 0.84]
                for (var i = 0; i < rs.length; i++) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, rs[i], -Math.PI * 0.82, -Math.PI * 0.18, false)
                    ctx.stroke()
                }
                ctx.beginPath()
                ctx.arc(cx, cy - 1, 1.8, 0, Math.PI * 2, false)
                ctx.fill()
            } else if (kind === "bt") {
                ctx.beginPath()
                ctx.moveTo(w * 0.28, h * 0.30)
                ctx.lineTo(w * 0.72, h * 0.70)
                ctx.lineTo(w * 0.50, h * 0.92)
                ctx.lineTo(w * 0.50, h * 0.08)
                ctx.lineTo(w * 0.72, h * 0.30)
                ctx.lineTo(w * 0.28, h * 0.70)
                ctx.stroke()
            } else if (kind === "theme") {
                ctx.beginPath()
                ctx.arc(w / 2, h / 2, h * 0.38, 0, Math.PI * 2, false)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(w / 2, h / 2, h * 0.38, -Math.PI / 2, Math.PI / 2, false)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    // Quick-settings tile: click toggles; the arrow (optional) opens a list
    component QTile: Rectangle {
        id: t
        property string label
        property string sub
        property string glyph
        property string glyphText
        property bool active: false
        property bool hasArrow: false
        property color accent: "#4C7BDE"
        property color offBg: "#EEF1F8"
        property color offFg: "#1F2433"
        property color subFg: "#666677"
        signal toggled()
        signal arrowClicked()
        height: 58
        radius: 29
        color: active ? Qt.alpha(accent, 0.20) : offBg
        Behavior on color { ColorAnimation { duration: 140 } }

        MouseArea { anchors.fill: parent; onClicked: t.toggled() }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Glyph {
                visible: t.glyph !== ""
                kind: t.glyph
                tone: t.active ? t.accent : t.offFg
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: t.glyphText !== ""
                text: t.glyphText
                font.pixelSize: 15
                font.bold: true
                color: t.active ? t.accent : t.offFg
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: t.label; font.pixelSize: 13; color: t.active ? t.accent : t.offFg }
                Text { text: t.sub; font.pixelSize: 11; color: t.active ? t.accent : t.subFg }
            }
        }
        Item {
            visible: t.hasArrow
            anchors.right: parent.right
            width: 40
            height: parent.height
            Text { anchors.centerIn: parent; text: "\u203A"; font.pixelSize: 26; color: t.active ? t.accent : t.offFg }
            MouseArea { anchors.fill: parent; onClicked: t.arrowClicked() }
        }
    }

    // =====================  SHELF  =====================
    PanelWindow {
        anchors { bottom: root.onBottom; top: !root.onBottom; left: true; right: true }
        margins { bottom: 12; top: 12; left: 14; right: 14 }
        implicitHeight: root.shelfH
        exclusiveZone: root.shelfH + 12
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.cShelf

            // Launcher ring
            Rectangle {
                width: 22; height: 22; radius: 11
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: 3
                border.color: root.accent
                scale: ringMa.containsMouse ? 1.12 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
                Rectangle {
                    x: 15; y: -4
                    width: 9; height: 9; radius: 4.5
                    color: "#8A6AD8"
                    border.width: 2
                    border.color: root.cShelf
                }
                MouseArea {
                    id: ringMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.panelOpen = false
                        root.wifiOpen = false
                        root.launcherOpen = !root.launcherOpen
                    }
                }
            }

            // Pinned apps (centered)
            Row {
                anchors.centerIn: parent
                spacing: 12
                Repeater {
                    model: root.pinned
                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: root.iconSize + 6; height: root.iconSize + 6
                        scale: appMa.containsMouse ? 1.12 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: root.iconSize
                            source: root.ico(cell.modelData.icons)
                        }
                        Rectangle {
                            visible: root.isRunning(cell.modelData.id)
                            width: 14; height: 3; radius: 1.5
                            color: root.accent
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -5
                        }
                        MouseArea {
                            id: appMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.launch(cell.modelData.cmd)
                        }
                    }
                }
            }

            // Window buttons for the active window: float, maximize, close
            Row {
                visible: ToplevelManager.activeToplevel ? true : false
                anchors.right: tray.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Repeater {
                    model: [
                        { c: "#F0B84A", act: "float" },
                        { c: "#5BBF7A", act: "max" },
                        { c: "#E86B6B", act: "close" }
                    ]
                    delegate: Rectangle {
                        id: wb
                        required property var modelData
                        width: 16; height: 16; radius: 8
                        color: modelData.c
                        scale: wbMa.containsMouse ? 1.25 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        MouseArea {
                            id: wbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (wb.modelData.act === "max") root.maximizeActive()
                                else if (wb.modelData.act === "float") root.floatActive()
                                else root.closeActive()
                            }
                        }
                    }
                }
            }

            // System tray: language, battery, network, sound, time
            Rectangle {
                id: tray
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: trayRow.width + 28
                height: 34
                radius: 17
                color: trayMa.containsMouse ? Qt.darker(root.cChip, 1.05) : root.cChip
                Row {
                    id: trayRow
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.isHypr
                        text: root.layoutLabel
                        color: root.cText
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.batteryPct >= 0
                        text: (root.batteryCharging ? "+" : "") + root.batteryPct + "%"
                        color: root.cText
                        font.pixelSize: 12
                    }
                    IconImage {
                        implicitSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath("network-wireless-symbolic", "network-wireless")
                    }
                    IconImage {
                        implicitSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath("audio-volume-high-symbolic", "audio-volume-high")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatTime(clock.date, "hh:mm")
                        color: root.cText
                        font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: trayMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.launcherOpen = false
                        root.wifiOpen = false
                        root.panelOpen = !root.panelOpen
                    }
                }
            }
        }
    }

    // =====================  BACKDROP (click outside closes popups)  =====================
    PanelWindow {
        visible: root.launcherOpen || root.panelOpen || root.wifiOpen
        anchors { top: true; bottom: true; left: true; right: true }
        margins {
            bottom: root.onBottom ? root.shelfH + 24 : 0
            top: root.onBottom ? 0 : root.shelfH + 24
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                root.launcherOpen = false
                root.panelOpen = false
                root.wifiOpen = false
            }
        }
    }

    // =====================  LAUNCHER  =====================
    PanelWindow {
        id: launcher
        WlrLayershell.layer: WlrLayer.Overlay
        visible: root.launcherOpen
        focusable: true
        anchors { bottom: root.onBottom; top: !root.onBottom; left: true }
        margins {
            bottom: root.shelfH + 24
            top: root.shelfH + 24
            left: 14
        }
        implicitWidth: 400
        implicitHeight: 460
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        onVisibleChanged: {
            if (visible) {
                openAnim.restart()
                search.text = ""
                root.query = ""
                search.forceActiveFocus()
            }
        }

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 170 }
            NumberAnimation { target: card; property: "scale"; from: 0.93; to: 1; duration: 170; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 24
            color: root.cPanel
            transformOrigin: root.onBottom ? Item.BottomLeft : Item.TopLeft

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 21
                    color: root.cField

                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 14
                        color: root.cText
                        clip: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.launcherOpen = false
                        Keys.onReturnPressed: {
                            if (appModel.values.length > 0) {
                                root.launchEntry(appModel.values[0])
                                root.launcherOpen = false
                            }
                        }
                        Text {
                            visible: search.text.length === 0
                            text: "Search apps"
                            color: root.cMuted
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                GridView {
                    id: grid
                    width: parent.width
                    height: parent.height - 54
                    cellWidth: width / 4
                    cellHeight: 92
                    clip: true
                    model: appModel

                    delegate: Item {
                        id: gcell
                        required property var modelData
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 14
                            color: gma.containsMouse ? root.cField : "transparent"
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitSize: 44
                                source: Quickshell.iconPath(gcell.modelData.icon, "application-x-executable")
                            }
                            Text {
                                width: grid.cellWidth - 10
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: gcell.modelData.name
                                font.pixelSize: 12
                                color: root.cText
                            }
                        }
                        MouseArea {
                            id: gma
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.launchEntry(gcell.modelData)
                                root.launcherOpen = false
                            }
                        }
                    }
                }
            }
        }
    }

    // =====================  QUICK SETTINGS  =====================
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Overlay
        visible: root.panelOpen
        anchors { bottom: root.onBottom; top: !root.onBottom; right: true }
        margins {
            bottom: root.shelfH + 24
            top: root.shelfH + 24
            right: 14
        }
        implicitWidth: 300
        implicitHeight: 440
        onVisibleChanged: if (visible) panelAnim.restart()
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        ParallelAnimation {
            id: panelAnim
            NumberAnimation { target: pcard; property: "opacity"; from: 0; to: 1; duration: 170 }
            NumberAnimation { target: pcard; property: "scale"; from: 0.93; to: 1; duration: 170; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: pcard
            anchors.fill: parent
            radius: 24
            color: root.cPanel
            transformOrigin: root.onBottom ? Item.BottomRight : Item.TopRight

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 9

                Text {
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                    color: root.cText
                    font.pixelSize: 15
                    font.bold: true
                }

                Grid {
                    width: parent.width
                    columns: 2
                    spacing: 8
                    QTile {
                        width: (parent.width - 8) / 2
                        label: "Wi-Fi"; sub: root.wifiOn ? "On" : "Off"
                        glyph: "wifi"; active: root.wifiOn; hasArrow: true
                        accent: root.accent; offBg: root.cField; offFg: root.cText; subFg: root.cMuted
                        onToggled: root.toggleWifi()
                        onArrowClicked: root.openWifi()
                    }
                    QTile {
                        width: (parent.width - 8) / 2
                        label: "Bluetooth"; sub: root.btOn ? "On" : "Off"
                        glyph: "bt"; active: root.btOn
                        accent: root.accent; offBg: root.cField; offFg: root.cText; subFg: root.cMuted
                        onToggled: root.toggleBt()
                    }
                    QTile {
                        width: (parent.width - 8) / 2
                        label: "Dark mode"; sub: root.dark ? "On" : "Off"
                        glyph: "theme"; active: root.dark
                        accent: root.accent; offBg: root.cField; offFg: root.cText; subFg: root.cMuted
                        onToggled: root.saveSetting("dark", !root.dark)
                    }
                    QTile {
                        width: (parent.width - 8) / 2
                        label: "Language"; sub: "Tap to switch"
                        glyphText: root.layoutLabel; active: false
                        accent: root.accent; offBg: root.cField; offFg: root.cText; subFg: root.cMuted
                        onToggled: root.switchKeyboard()
                    }
                }

                Text { text: "Volume"; color: root.cMuted; font.pixelSize: 12 }
                QSlider {
                    width: parent.width
                    accent: root.accent
                    track: root.cChip
                    value: 0.5
                    onMoved: (v) => Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)])
                }
                Text { text: "Brightness"; color: root.cMuted; font.pixelSize: 12 }
                QSlider {
                    width: parent.width
                    accent: root.accent
                    track: root.cChip
                    value: 0.7
                    onMoved: (v) => Quickshell.execDetached(["brightnessctl", "set", Math.max(5, Math.round(v * 100)) + "%"])
                }

                QBtn {
                    width: parent.width
                    tint: root.cField; fg: root.cText
                    label: "All settings"
                    iconName: "preferences-system"
                    onClicked: {
                        root.launch(["qs", "-p", "/etc/myos/settings"])
                        root.panelOpen = false
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    QBtn {
                        width: (parent.width - 16) / 3
                        tint: root.cField; fg: root.cText
                        label: "Exit"
                        iconName: "system-log-out"
                        onClicked: root.exitSession()
                    }
                    QBtn {
                        width: (parent.width - 16) / 3
                        tint: root.cField; fg: root.cText
                        label: "Restart"
                        iconName: "system-reboot"
                        onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                    QBtn {
                        width: (parent.width - 16) / 3
                        tint: "#F7D9D9"; fg: "#7A2020"
                        label: "Off"
                        iconName: "system-shutdown"
                        onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }
        }
    }

    // =====================  WI-FI LIST  =====================
    PanelWindow {
        id: wifiWin
        WlrLayershell.layer: WlrLayer.Overlay
        visible: root.wifiOpen
        focusable: true
        anchors { bottom: root.onBottom; top: !root.onBottom; right: true }
        margins {
            bottom: root.shelfH + 24
            top: root.shelfH + 24
            right: 14
        }
        implicitWidth: 330
        implicitHeight: 470
        onVisibleChanged: if (visible) wifiAnim.restart()
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        ParallelAnimation {
            id: wifiAnim
            NumberAnimation { target: wcard; property: "opacity"; from: 0; to: 1; duration: 170 }
            NumberAnimation { target: wcard; property: "scale"; from: 0.93; to: 1; duration: 170; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: wcard
            anchors.fill: parent
            radius: 24
            color: root.cPanel
            transformOrigin: root.onBottom ? Item.BottomRight : Item.TopRight

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                // header: back arrow, title, on/off switch
                Item {
                    width: parent.width
                    height: 38
                    Rectangle {
                        id: backBtn
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34; radius: 17
                        color: backMa.containsMouse ? root.cChip : root.cField
                        Text { anchors.centerIn: parent; text: "\u2039"; font.pixelSize: 24; color: root.cText }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.wifiOpen = false; root.panelOpen = true }
                        }
                    }
                    Text {
                        anchors.left: backBtn.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wi-Fi"
                        font.pixelSize: 18
                        font.bold: true
                        color: root.cText
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48; height: 28; radius: 14
                        color: root.wifiOn ? root.accent : root.cChip
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            y: 3
                            x: root.wifiOn ? 23 : 3
                            color: "#FFFFFF"
                            Behavior on x { NumberAnimation { duration: 140 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.toggleWifi() }
                    }
                }

                // networks
                ListView {
                    id: wlist
                    width: parent.width
                    height: 270
                    clip: true
                    model: root.wifiList
                    delegate: Rectangle {
                        id: wrow
                        required property var modelData
                        width: ListView.view.width
                        height: 46
                        radius: 14
                        color: root.wifiSelected === modelData.ssid ? root.cChip : (wma.containsMouse ? root.cField : "transparent")
                        Glyph {
                            id: wg
                            kind: "wifi"
                            width: 20; height: 20
                            tone: wrow.modelData.inuse ? root.accent : root.cMuted
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            anchors.left: wg.right
                            anchors.leftMargin: 12
                            anchors.right: info.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: wrow.modelData.ssid
                            elide: Text.ElideRight
                            font.pixelSize: 14
                            color: root.cText
                        }
                        Text {
                            id: info
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: wrow.modelData.inuse ? "Connected" : (wrow.modelData.secure ? "Secured" : "Open")
                            font.pixelSize: 11
                            color: wrow.modelData.inuse ? root.accent : root.cMuted
                        }
                        MouseArea {
                            id: wma
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.wifiSelected = wrow.modelData.ssid
                                root.wifiSelectedSecure = wrow.modelData.secure
                                if (wrow.modelData.inuse) return
                                if (!wrow.modelData.secure || root.isSaved(wrow.modelData.ssid)) root.connectWifi(wrow.modelData.ssid, "")
                            }
                        }
                    }
                }

                Text {
                    visible: root.wifiList.length === 0
                    text: root.wifiOn ? "Looking for networks..." : "Wi-Fi is off"
                    font.pixelSize: 13
                    color: root.cMuted
                }

                // password (only for a secured network that is not saved yet)
                Row {
                    visible: root.wifiSelected !== "" && root.wifiSelectedSecure && !root.isSaved(root.wifiSelected)
                    spacing: 8
                    Rectangle {
                        width: parent.width - 100
                        height: 38; radius: 19
                        color: root.cField
                        TextInput {
                            id: wpw
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            font.pixelSize: 13
                            color: root.cText
                            clip: true
                            Keys.onReturnPressed: root.connectWifi(root.wifiSelected, wpw.text)
                            Text {
                                visible: wpw.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password"
                                font.pixelSize: 12
                                color: root.cMuted
                            }
                        }
                    }
                    Rectangle {
                        width: 92; height: 38; radius: 19
                        color: root.accent
                        Text { anchors.centerIn: parent; text: "Connect"; font.pixelSize: 13; color: "#FFFFFF" }
                        MouseArea { anchors.fill: parent; onClicked: root.connectWifi(root.wifiSelected, wpw.text) }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.wifiMsg
                    font.pixelSize: 12
                    color: root.cMuted
                }
            }
        }
    }
}
