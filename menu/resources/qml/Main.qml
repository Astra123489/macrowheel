import QtQuick 2.15
import QtQuick.Window 2.15
import Qt.labs.platform 1.1 as Platform

// Root application object for Macro Wheel Menu.
//
// Owns:
//   - the transparent, frameless, always-on-top overlay window (the wheel)
//   - the system tray icon and its menu
//
// Qt.labs.platform is used instead of QSystemTrayIcon so the Menu does not
// depend on QtWidgets.
Window {
    id: overlay
    width: 720
    height: 720
    visible: false
    color: "transparent"
    title: qsTr("Macro Wheel")
    flags: Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint
         | Qt.NoDropShadowWindowHint
         | Qt.Tool

    // ---------------------------------------------------------------------
    // Wheel surface
    // ---------------------------------------------------------------------
    WheelCanvas {
        id: wheel
        visible: overlay.visible
    }

    function openWheelAtCursor() {
        var p = Qt.point(Qt.cursor().pos.x, Qt.cursor().pos.y)
        overlay.x = Math.round(p.x - overlay.width / 2)
        overlay.y = Math.round(p.y - overlay.height / 2)
        overlay.visible = true
        overlay.requestActivate()
    }

    function closeWheel() {
        overlay.visible = false
    }

    // Press-and-hold global hotkey: press opens, release commits the slice
    // under the pointer. Classic radial menu (spec section 9).
    Connections {
        target: globalHotkey
        function onActivated() { overlay.openWheelAtCursor() }
        function onReleased() {
            // commit() executes the slice under the last known pointer
            // position and returns true when the wheel should close.
            if (wheel.commit()) {
                overlay.closeWheel()
            }
        }
        function onErrorOccurred(message) {
            tray.showMessage(qsTr("Macro Wheel"), message)
        }
    }

    // A wheel interaction that executed or cancelled closes the overlay.
    Connections {
        target: wheelGeometry
        function onCommandTriggered(command) { overlay.closeWheel() }
    }

    // Resolve must be reachable before the wheel may open (spec 21.3).
    Connections {
        target: resolveConnection
        function onConnectionStatusChanged(connected) {
            if (!connected) overlay.closeWheel()
        }
    }

    // ---------------------------------------------------------------------
    // Tray
    // ---------------------------------------------------------------------
    Platform.SystemTrayIcon {
        id: tray
        visible: true
        icon.source: "qrc:/icons/tray.svg"
        // Qt.labs.platform uses the lowercase property name.
        tooltip: qsTr("Macro Wheel — %1").arg(trayIcon.statusText)

        menu: Platform.Menu {
            Platform.MenuItem {
                text: trayIcon.statusText
                enabled: false
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: qsTr("Cycle Profile")
                onTriggered: trayIcon.requestProfileCycle()
            }
            Platform.MenuItem {
                text: qsTr("Open Scripts Folder")
                onTriggered: trayIcon.requestOpenConfigFolder()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: qsTr("Check for Updates… (v%1)").arg(trayIcon.version)
                onTriggered: trayIcon.requestCheckForUpdates()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: qsTr("Quit Macro Wheel")
                onTriggered: trayIcon.requestQuit()
            }
        }

        onActivated: function(reason) {
            if (reason === Platform.SystemTrayIcon.Trigger) {
                trayIcon.requestProfileCycle()
            }
        }
    }

    Connections {
        target: trayIcon
        function onNotificationRequested(title, message) {
            tray.showMessage(title, message)
        }
    }
}