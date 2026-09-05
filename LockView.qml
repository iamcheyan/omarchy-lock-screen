import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: false
  property bool loadBackground: false
  property string passwordText: ""
  property bool showPassword: false
  property bool passwordVisible: false
  property bool hibernateAvailable: false

  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryAvailable: !!(batteryDevice && batteryDevice.isPresent)
  readonly property int batteryPercent: batteryAvailable ? Math.round((batteryDevice.percentage || 0) * 100) : 0
  readonly property bool batteryCharging: batteryAvailable && !UPower.onBattery
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wiredNetwork: findNetworkDevice(DeviceType.Wired)
  readonly property var wifiNetworkDevice: findNetworkDevice(DeviceType.Wifi)
  readonly property var connectedWifi: findConnectedWifi()
  readonly property bool networkAvailable: !!((wiredNetwork && wiredNetwork.connected) || connectedWifi)
  readonly property string networkLabel: wiredNetwork && wiredNetwork.connected
    ? "Ethernet"
    : (connectedWifi && connectedWifi.ssid ? String(connectedWifi.ssid) : "Wi-Fi")
  readonly property var avatarCandidates: [
    "file:///var/lib/AccountsService/icons/" + (Quickshell.env("USER") || ""),
    "file://" + (Quickshell.env("HOME") || "") + "/.face",
    "file://" + (Quickshell.env("HOME") || "") + "/.face.icon"
  ]
  property int avatarIndex: 0
  property bool avatarLoaded: false
  readonly property string avatarSource: avatarIndex < avatarCandidates.length
    ? avatarCandidates[avatarIndex] : ""

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  property string timeText: Qt.formatDateTime(new Date(), "HH:mm")
  property string dateText: Qt.formatDateTime(new Date(), "dddd, MMMM d")

  focus: inputEnabled
  onInputEnabledChanged: if (inputEnabled) forceActiveFocus()

  function findNetworkDevice(type) {
    var fallback = null
    var devices = root.networkDevices || []
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function findConnectedWifi() {
    var networks = root.wifiNetworkDevice && root.wifiNetworkDevice.networks
      ? root.wifiNetworkDevice.networks.values : []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.timeText = Qt.formatDateTime(new Date(), "HH:mm")
      root.dateText = Qt.formatDateTime(new Date(), "dddd, MMMM d")
    }
  }

  Process {
    id: hibernateCheck
    command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanHibernate"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.hibernateAvailable = String(text || "").includes("\"yes\"")
    }
  }

  Keys.onPressed: event => {
    root.wakeRequested()
    if (event.key === Qt.Key_Space && !root.passwordVisible) {
      root.passwordVisible = true
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      root.passwordTextEdited("")
      root.clearFailureRequested()
      root.passwordVisible = false
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!root.passwordVisible) {
        root.passwordVisible = true
        root.forceActiveFocus()
      } else {
        root.submitPassword(root.passwordText)
      }
      event.accepted = true
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onPressed: {
      root.wakeRequested()
      root.passwordVisible = true
      root.forceActiveFocus()
    }
  }

  Image {
    id: background
    anchors.fill: parent
    source: root.loadBackground && root.backgroundPath.length > 0
      ? root.backgroundPath + "?v=" + root.backgroundVersion
      : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
    visible: false
  }

  MultiEffect {
    anchors.fill: parent
    source: background
    blurEnabled: true
    blur: 1.0
    blurMax: 48
    saturation: -0.05
  }

  Rectangle {
    anchors.fill: parent
    color: "#000000"
    opacity: 0.30
  }

  Column {
    anchors.top: parent.top
    anchors.topMargin: Math.max(48, parent.height * 0.07)
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.dateText
      color: "#a0ffffff"
      font.pixelSize: 15
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.timeText
      color: "#f5ffffff"
      font.pixelSize: Math.min(96, Math.max(68, root.height * 0.11))
      font.weight: Font.Light
    }
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: Math.max(8, parent.height * 0.02)
    width: Math.min(320, parent.width - 64)
    spacing: 10

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 76
      height: 76

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#1affffff"
        border.width: 1
        border.color: "#38ffffff"
      }

      Item {
        id: avatarLayer
        anchors.fill: parent
        anchors.margins: 1
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: avatarMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: avatarImage
          anchors.fill: parent
          source: root.avatarSource
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
          visible: root.avatarLoaded
          onStatusChanged: {
            if (status === Image.Ready) {
              root.avatarLoaded = true
            } else if (status === Image.Error || status === Image.Null) {
              root.avatarLoaded = false
              if (root.avatarIndex + 1 < root.avatarCandidates.length)
                root.avatarIndex += 1
            }
          }
          onSourceChanged: root.avatarLoaded = false
        }

        Item {
          id: avatarMask
          anchors.fill: parent
          visible: false
          layer.enabled: true

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "white"
          }
        }
      }

      Text {
        anchors.centerIn: parent
        text: "󰀄"
        color: "#e0ffffff"
        font.pixelSize: 34
        font.family: Style.font.family
        visible: !root.avatarLoaded
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Quickshell.env("USER") || ""
      color: "#e0ffffff"
      font.pixelSize: 16
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: !root.passwordVisible
      text: root.fingerprintConfigured ? "Click or press Space · fingerprint ready" : "Click or press Space"
      color: "#80ffffff"
      font.pixelSize: 13
    }

    Rectangle {
      id: passwordCard
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(236, parent.width)
      height: 34
      visible: root.inputEnabled && root.passwordVisible
      radius: height / 2
      color: "#70000000"
      border.width: 1
      border.color: root.failureMessage.length > 0 ? "#b8ff7770" : "#38ffffff"

      TextInput {
        id: passwordInput
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: submitLabel.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        color: "#f5ffffff"
        font.pixelSize: 13
        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        text: root.passwordText
        enabled: root.inputEnabled && !root.authenticatingPassword
        focus: root.inputEnabled && root.passwordVisible
        activeFocusOnPress: false
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        onTextChanged: {
          if (root.passwordText !== text) root.passwordTextEdited(text)
        }
        onAccepted: root.submitPassword(text)
        Keys.onPressed: root.wakeRequested()
      }

      Text {
        id: submitLabel
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.authenticatingPassword ? "…" : "󰜴"
        color: "#eaffffff"
        font.pixelSize: 19
        font.family: Style.font.family
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          enabled: root.inputEnabled && !root.authenticatingPassword
          onClicked: root.submitPassword(root.passwordText)
        }
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: passwordInput.text.length === 0 && root.failureMessage.length === 0
        text: "Enter Password"
        color: "#70ffffff"
        font.pixelSize: 13
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.failureMessage.length > 0
      text: root.failureMessage
      color: "#e8aaa0"
      font.pixelSize: 12
    }
  }

  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: Math.max(28, parent.width * 0.03)
    anchors.bottomMargin: Math.max(22, parent.height * 0.04)
    visible: root.fingerprintConfigured
    text: "◉  Fingerprint"
    color: "#b8ffffff"
    font.pixelSize: 12
  }

  Row {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: Math.max(28, parent.width * 0.03)
    anchors.bottomMargin: Math.max(22, parent.height * 0.04)
    spacing: 8

    LockCornerButton {
      visible: root.batteryAvailable
      icon: root.batteryCharging ? "󰂄" : "󰁹"
      label: root.batteryPercent + "%"
      showLabel: true
    }

    LockCornerButton {
      visible: root.fingerprintConfigured
      icon: "󰈷"
      label: "Fingerprint"
      showLabel: false
    }

    LockCornerButton {
      visible: root.networkAvailable
      icon: "󰖩"
      label: root.networkLabel
      showLabel: true
    }

    LockCornerButton {
      icon: "󰄀"
      tooltip: "Screenshot"
      onClicked: Quickshell.execDetached(["omarchy-capture-screenshot", "fullscreen", "save"])
    }
  }

  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Math.max(28, parent.width * 0.03)
    anchors.bottomMargin: Math.max(22, parent.height * 0.04)
    spacing: 6

    LockCornerButton {
      icon: "󰒲"
      tooltip: "Sleep"
      onClicked: Quickshell.execDetached(["omarchy-system-sleep-lock"])
    }

    LockCornerButton {
      visible: root.hibernateAvailable
      icon: "󰤄"
      tooltip: "Hibernate"
      onClicked: Quickshell.execDetached(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Hibernate", "b", "true"])
    }

    LockCornerButton {
      icon: "󰜉"
      tooltip: "Restart"
      onClicked: Quickshell.execDetached(["omarchy-system-reboot"])
    }

    LockCornerButton {
      icon: "󰐥"
      tooltip: "Shut Down"
      onClicked: Quickshell.execDetached(["omarchy-system-shutdown"])
    }
  }

  component LockCornerButton: Item {
    id: action
    property string icon: ""
    property string label: ""
    property string tooltip: ""
    property bool showLabel: false
    signal clicked()

    implicitWidth: showLabel ? 68 : 36
    implicitHeight: 36

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: actionMouse.containsMouse ? "#24ffffff" : "#38000000"
      border.width: 1
      border.color: "#18ffffff"
    }

    Row {
      anchors.centerIn: parent
      spacing: 5

      Text {
        text: action.icon
        color: "#e0ffffff"
        font.pixelSize: 17
        font.family: Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: action.showLabel
        text: action.label
        color: "#cfffffff"
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.top
      anchors.bottomMargin: 8
      visible: actionMouse.containsMouse && !action.showLabel && action.tooltip.length > 0
      text: action.tooltip
      color: "#cfffffff"
      font.pixelSize: 11
    }
  }
}
