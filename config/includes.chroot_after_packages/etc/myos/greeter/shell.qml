// Hala OS login screen: lock screen (clock) and login (avatar, greeting, password).
// Runs inside greetd with Quickshell.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import QtQuick

ShellRoot {
    id: g

    property bool unlocked: false
    property bool busy: false
    property bool isLive: false
    property var users: []
    property int userIndex: 0
    property string errorText: ""
    property string layoutLabel: "EN"

    readonly property string userName: users.length > 0 ? users[userIndex].name : ""
    readonly property string shownName: users.length > 0 ? (users[userIndex].real !== "" ? users[userIndex].real : users[userIndex].name) : ""

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ----- users on this computer -----
    Process {
        running: true
        command: ["sh", "-c", "awk -F: '$3>=1000 && $3<60000 {print $1\":\"$5}' /etc/passwd; [ -d /run/live ] && echo LIVE"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i] === "LIVE") { g.isLive = true; continue }
                    if (lines[i] === "") continue
                    var p = lines[i].split(":")
                    out.push({ name: p[0], real: (p[1] || "").split(",")[0] })
                }
                g.users = out
            }
        }
    }

    // ----- keyboard layout label -----
    Process {
        id: kb
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var k = JSON.parse(text).keyboards
                    var m = ""
                    for (var i = 0; i < k.length; i++) { if (k[i].main) m = k[i].active_keymap }
                    if (m === "" && k.length > 0) m = k[k.length - 1].active_keymap
                    g.layoutLabel = (m.indexOf("Arab") >= 0) ? "AR" : "EN"
                } catch (e) { }
            }
        }
    }
    Timer { interval: 1200; running: true; repeat: true; onTriggered: { kb.running = false; kb.running = true } }

    // ----- login logic -----
    function tryLogin() {
        if (busy || userName === "") return
        busy = true
        errorText = ""
        Greetd.createSession(userName)
    }
    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) Greetd.respond(pw.text)
        }
        function onAuthFailure(message) {
            g.busy = false
            g.errorText = "Wrong password. Try again."
            pw.text = ""
            shake.restart()
            pw.forceActiveFocus()
        }
        function onReadyToLaunch() {
            Greetd.launch(["sh", "/etc/myos/session.sh"])
        }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "#DCE7F7"

        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true

            Image {
                anchors.fill: parent
                source: "file:///usr/share/backgrounds/myos/wallpaper.png"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            // any key or click on the lock screen opens the login page
            Keys.onPressed: { if (!g.unlocked) { g.unlocked = true; pw.forceActiveFocus() } }

            // ===== lock screen =====
            Item {
                id: lock
                width: parent.width
                height: parent.height
                opacity: g.unlocked ? 0 : 1
                y: g.unlocked ? -height * 0.15 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 260 } }
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.26
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(clock.date, "hh:mm")
                        font.pixelSize: 110
                        color: "#1F2433"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(clock.date, "dddd, d MMMM")
                        font.pixelSize: 24
                        color: "#3B4560"
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 48
                    text: "Click or press any key"
                    font.pixelSize: 15
                    color: "#55607A"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { g.unlocked = true; pw.forceActiveFocus() }
                }
            }

            // ===== login page =====
            Item {
                id: login
                anchors.fill: parent
                opacity: g.unlocked ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 260 } }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.2
                    spacing: 14

                    // avatar with the Hala ring
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 140; height: 140
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 7
                            border.color: "#4C7BDE"
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 112; height: 112; radius: 56
                            color: "#F4F6FB"
                            Text {
                                anchors.centerIn: parent
                                text: g.shownName.length > 0 ? g.shownName.charAt(0).toUpperCase() : "H"
                                font.pixelSize: 56
                                color: "#4C7BDE"
                            }
                        }
                        Rectangle {
                            x: 104; y: 8
                            width: 26; height: 26; radius: 13
                            color: "#8A6AD8"
                            border.width: 5
                            border.color: "#DCE7F7"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (g.users.length > 1) g.userIndex = (g.userIndex + 1) % g.users.length }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "هلا"
                        font.pixelSize: 30
                        color: "#1F2433"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: g.shownName
                        font.pixelSize: 20
                        color: "#3B4560"
                    }

                    // password field
                    Rectangle {
                        id: pwBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 320; height: 48; radius: 24
                        color: "#FFFFFF"
                        transform: Translate { id: shakeT }

                        SequentialAnimation {
                            id: shake
                            NumberAnimation { target: shakeT; property: "x"; to: -12; duration: 50 }
                            NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
                            NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 60 }
                            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
                        }

                        TextInput {
                            id: pw
                            anchors.left: parent.left
                            anchors.right: go.left
                            anchors.leftMargin: 20
                            anchors.rightMargin: 8
                            height: parent.height
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            font.pixelSize: 17
                            color: "#1F2433"
                            clip: true
                            enabled: !g.busy
                            Keys.onReturnPressed: g.tryLogin()
                            Keys.onEnterPressed: g.tryLogin()
                            Text {
                                visible: pw.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password"
                                font.pixelSize: 15
                                color: "#8A91A8"
                            }
                        }
                        Rectangle {
                            id: go
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34; radius: 17
                            color: g.busy ? "#9BB3EA" : "#4C7BDE"
                            Text { anchors.centerIn: parent; text: "→"; font.pixelSize: 18; color: "white" }
                            MouseArea { anchors.fill: parent; onClicked: g.tryLogin() }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: g.errorText !== ""
                        text: g.errorText
                        font.pixelSize: 14
                        color: "#B3261E"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: g.isLive
                        text: "Live session: the password is  live"
                        font.pixelSize: 13
                        color: "#55607A"
                    }
                }

                // language (bottom left)
                Rectangle {
                    anchors.left: parent.left; anchors.leftMargin: 28
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 28
                    width: 52; height: 34; radius: 17
                    color: "#E3E9F6"
                    Text { anchors.centerIn: parent; text: g.layoutLabel; font.pixelSize: 13; font.bold: true; color: "#1F2433" }
                    MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]) }
                }

                // restart and shut down (bottom right)
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 28
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 28
                    spacing: 10
                    Rectangle {
                        width: 84; height: 34; radius: 17; color: "#E3E9F6"
                        Text { anchors.centerIn: parent; text: "Restart"; font.pixelSize: 13; color: "#1F2433" }
                        MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                    }
                    Rectangle {
                        width: 84; height: 34; radius: 17; color: "#F7D9D9"
                        Text { anchors.centerIn: parent; text: "Shut down"; font.pixelSize: 13; color: "#7A2020" }
                        MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
                    }
                }
            }
        }
    }
}
