import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "WindowsModel.js" as Model

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property string wallpaperPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  property bool opened: false
  property string filterText: ""
  property var desks: []
  property int deskIndex: 0
  property int windowIndex: 0
  property bool preferNextOnOpen: false
  property bool caretOn: true
  // Behaviors stay off while the mill is being placed, rebuilt, or wrapped,
  // so desks do not fly in from x = 0 or sweep across every desk on a wrap.
  property bool motions: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  property color muted: Color.muted
  readonly property int cornerRadius: Math.max(Style.cornerRadius, Style.space(18))
  property string fontFamily: Style.font.menuFamily

  readonly property int cardW: Math.min(Style.space(420), Math.max(Style.space(280), Math.round(millView.width * 0.46)))
  readonly property int cardH: Math.min(Style.space(230), Math.max(Style.space(140), Math.round(millView.height * 0.48)))
  readonly property int stripH: Style.space(44)
  readonly property int spineW: Style.space(132)
  readonly property int stackDepth: {
    var gap = Style.space(8)
    var room = (millView.height - root.cardH) / 2 - Style.space(14)
    if (room < root.stripH) return 0
    return Math.min(3, Math.floor((room + gap) / (root.stripH + gap)))
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  component Glide: NumberAnimation {
    duration: Style.duration(280)
    easing.type: Easing.OutCubic
  }

  function armMotion() {
    if (root.opened && millView.width > 0) root.motions = true
  }

  function open(payloadJson) {
    root.motions = false
    root.opened = true
    root.filterText = ""
    root.deskIndex = 0
    root.windowIndex = 0
    root.preferNextOnOpen = true
    if (Hyprland.refreshToplevels) Hyprland.refreshToplevels()
    if (root.appLibrary && root.appLibrary.refreshIcons) root.appLibrary.refreshIcons()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ikekavas.ikea")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function ping() { return "ok" }

  function activateSelected() {
    root.activateCurrent()
    return "ok"
  }

  function desktopEntry(className, appId) {
    var values = DesktopEntries.applications ? (DesktopEntries.applications.values || []) : []
    var needles = [String(className || "").toLowerCase(), String(appId || "").toLowerCase()]
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      var id = String((entry && entry.id) || "").toLowerCase()
      var icon = String((entry && entry.icon) || "").toLowerCase()
      var name = String((entry && entry.name) || "").toLowerCase()
      var idTail = id.split(".").pop()
      if (!id && !icon) continue
      for (var n = 0; n < needles.length; n++) {
        var needle = needles[n]
        if (!needle) continue
        var needleTail = needle.split(".").pop()
        if (id === needle || idTail === needle || id === needleTail || idTail === needleTail)
          return entry
        if (icon === needle || icon === needleTail)
          return entry
        if (name === needle || name === needleTail)
          return entry
      }
    }
    return null
  }

  function desktopName(className, appId) {
    var entry = desktopEntry(className, appId)
    if (!entry) return ""
    return root.appLibrary ? root.appLibrary.entryName(entry) : (entry.name || "")
  }

  function isThemedIconName(value) {
    return /^[A-Za-z0-9][A-Za-z0-9._+-]{0,254}$/.test(String(value || ""))
  }

  function desktopIcon(className, appId) {
    var entry = desktopEntry(className, appId)
    if (entry && entry.icon) return String(entry.icon)
    var fallback = String(className || appId || "")
    return root.isThemedIconName(fallback) ? fallback : ""
  }

  function iconSource(row) {
    var iconName = desktopIcon(row.className, row.appId)
    if (!iconName)
      return Quickshell.iconPath("application-x-executable", true)
    if (root.appLibrary) return root.appLibrary.iconSource(iconName)
    var themed = Quickshell.iconPath(iconName, true)
    if (themed && themed.length) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function captureSource(address) {
    return Model.waylandFor(Model.findToplevel(Hyprland, address))
  }

  function decorate(row) {
    row.prettyName = Model.prettyApp(row.className, row.appId, desktopName(row.className, row.appId))
    row.icon = String(root.iconSource(row) || "")
    return row
  }

  function focusedWorkspaceId() {
    var ws = Hyprland.focusedWorkspace
    if (ws && typeof ws.id === "number") return ws.id
    return 0
  }

  function currentDesk() {
    if (root.deskIndex < 0 || root.deskIndex >= root.desks.length) return null
    return root.desks[root.deskIndex]
  }

  function currentWindow() {
    var desk = root.currentDesk()
    if (!desk) return null
    var windows = desk.windows || []
    if (root.windowIndex < 0 || root.windowIndex >= windows.length) return null
    return windows[root.windowIndex]
  }

  function findAddress(desks, address) {
    var needle = String(address || "")
    if (!needle) return null
    for (var i = 0; i < desks.length; i++) {
      var windows = desks[i].windows || []
      for (var j = 0; j < windows.length; j++) {
        if (String(windows[j].address || "") === needle)
          return { deskIndex: i, windowIndex: j }
      }
    }
    return null
  }

  function deskIndexForWorkspace(desks, id) {
    for (var i = 0; i < desks.length; i++) {
      if (!desks[i].scratch && desks[i].workspaceId === id) return i
    }
    return -1
  }

  function placeOnOpen(desks) {
    var nextDesk = 0
    var focusId = root.focusedWorkspaceId()
    var match = root.deskIndexForWorkspace(desks, focusId)
    var active = Hyprland.activeToplevel
    var activeAddress = active ? String(active.address || "") : ""
    if (match >= 0) nextDesk = match
    else {
      var found = root.findAddress(desks, activeAddress)
      if (found) nextDesk = found.deskIndex
    }
    var windows = desks[nextDesk] ? (desks[nextDesk].windows || []) : []
    var nextWindow = 0
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].activated || String(windows[i].address || "") === activeAddress)
        nextWindow = i
    }
    if (windows.length > 1) nextWindow = (nextWindow + 1) % windows.length
    return { deskIndex: nextDesk, windowIndex: nextWindow }
  }

  function rebuild() {
    var collected = Model.collectWindows(Hyprland)
    var rows = []
    for (var i = 0; i < collected.length; i++) {
      var row = root.decorate(collected[i])
      if (!Model.matchesFilter(row, root.filterText)) continue
      rows.push(row)
    }
    var nextDesks = Model.groupDesks(rows)

    var keepAddress = ""
    var keepDesk = ""
    var keepWindow = root.windowIndex
    if (!root.preferNextOnOpen) {
      var current = root.currentWindow()
      if (current) keepAddress = String(current.address || "")
      var desk = root.currentDesk()
      if (desk) keepDesk = String(desk.key || "")
    }

    var nextDesk = 0
    var nextWindow = 0
    if (nextDesks.length > 0 && root.preferNextOnOpen) {
      var placed = root.placeOnOpen(nextDesks)
      nextDesk = placed.deskIndex
      nextWindow = placed.windowIndex
    } else if (nextDesks.length > 0) {
      var kept = root.findAddress(nextDesks, keepAddress)
      if (kept) {
        nextDesk = kept.deskIndex
        nextWindow = kept.windowIndex
      } else {
        for (var d = 0; d < nextDesks.length; d++) {
          if (keepDesk && nextDesks[d].key === keepDesk) nextDesk = d
        }
        var remaining = nextDesks[nextDesk].windows || []
        nextWindow = remaining.length === 0 ? 0 : Math.min(keepWindow, remaining.length - 1)
      }
    }

    root.motions = false
    root.preferNextOnOpen = false
    root.desks = nextDesks
    root.deskIndex = nextDesk
    root.windowIndex = nextWindow
    Qt.callLater(root.centerTab)
    Qt.callLater(root.armMotion)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.preferNextOnOpen = false
    root.rebuild()
  }

  function centerTab() {
    if (!deskTabs || root.desks.length === 0) return
    deskTabs.positionViewAtIndex(root.deskIndex, ListView.Center)
  }

  function focusDesk(index) {
    if (root.desks.length === 0) return
    var n = root.desks.length
    var next = ((index % n) + n) % n
    var jump = Math.abs(next - root.deskIndex)
    // A wrap would slide a card across the whole mill. Snap, then arm again.
    if (jump > 1) root.motions = false
    else root.armMotion()
    root.deskIndex = next
    if (jump > 1) Qt.callLater(root.armMotion)
    var windows = root.desks[next].windows || []
    var win = 0
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].activated) win = i
    }
    root.windowIndex = windows.length === 0 ? 0 : win
    root.centerTab()
    keyCatcher.forceActiveFocus()
  }

  function moveDesk(delta) {
    root.focusDesk(root.deskIndex + delta)
  }

  function focusWindow(index) {
    var desk = root.currentDesk()
    if (!desk) return
    var n = (desk.windows || []).length
    if (n === 0) return
    root.windowIndex = Math.max(0, Math.min(n - 1, index))
    keyCatcher.forceActiveFocus()
  }

  function moveWindow(delta) {
    root.focusWindow(root.windowIndex + delta)
  }

  function deskMark(desk) {
    if (!desk) return ""
    if (desk.scratch) return strings.t("desk.scratchMark")
    var name = String(desk.workspaceName || "")
    if (name && name !== String(desk.workspaceId)) return name
    return String(desk.workspaceId)
  }

  function deskTab(desk) {
    if (!desk) return ""
    if (desk.scratch) return strings.t("desk.scratch")
    return root.deskMark(desk)
  }

  function deskX(dist, itemWidth) {
    var gap = Style.space(28)
    var travel = (root.cardW + root.spineW) / 2 + gap
    var signed = LayoutMirroring.enabled ? -dist : dist
    return (millView.width - itemWidth) / 2 + signed * travel
  }

  function stackY(delta, frameHeight) {
    var gap = Style.space(8)
    var mid = frameHeight / 2
    if (delta === 0) return mid - root.cardH / 2
    if (delta > 0)
      return mid + root.cardH / 2 + gap + (delta - 1) * (root.stripH + gap)
    var above = -delta
    return mid - root.cardH / 2 - gap - above * (root.stripH + gap)
  }

  function hiddenBeyond(delta, count) {
    if (delta >= root.stackDepth && delta > 0)
      return Math.max(0, count - (root.windowIndex + root.stackDepth) - 1)
    if (delta <= -root.stackDepth && delta < 0)
      return Math.max(0, root.windowIndex - root.stackDepth)
    return 0
  }

  // Ctrl+1–9 only. Reject Alt so AltGr (Ctrl+Alt) does not steal layout symbols.
  function isPickModifier(event) {
    var mods = event.modifiers
    if (mods & (Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)) return false
    return !!(mods & Qt.ControlModifier)
  }

  function pickKeyIndex(event) {
    var key = event.key
    if (key >= Qt.Key_1 && key <= Qt.Key_9)
      return key - Qt.Key_1
    var t = String(event.text || "")
    if (t.length === 1 && t >= "1" && t <= "9")
      return t.charCodeAt(0) - 49
    return -1
  }

  function isFilterTextKey(event) {
    if (!event.text || event.text.length !== 1) return false
    var code = event.text.charCodeAt(0)
    if (code < 32 || code === 127) return false
    return !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
  }

  function normalizeAddress(address) {
    var a = String(address || "").trim()
    if (!a) return ""
    if (a.indexOf("0x") !== 0 && a.indexOf("0X") !== 0) a = "0x" + a
    return a
  }

  function dispatchFocus(address) {
    var a = root.normalizeAddress(address)
    if (!a) return
    var request = 'hl.dsp.focus({ window = "address:' + a + '" })'
    Hyprland.dispatch(request)
    Quickshell.execDetached(["hyprctl", "dispatch", request])
  }

  function dispatchClose(address) {
    var a = root.normalizeAddress(address)
    if (!a) return
    var request = 'hl.dsp.window.close({ window = "address:' + a + '" })'
    Hyprland.dispatch(request)
    Quickshell.execDetached(["hyprctl", "dispatch", request])
  }

  function activateCurrent() {
    var row = root.currentWindow()
    if (!row) return
    pendingFocus.address = String(row.address || "")
    root.dismiss()
    pendingFocus.restart()
  }

  function activateAt(deskAt, windowAt) {
    root.deskIndex = deskAt
    root.windowIndex = windowAt
    root.activateCurrent()
  }

  // Ctrl+N picks the Nth window in the open desk's (filtered) stack.
  function activateIndex(index) {
    var desk = root.currentDesk()
    if (!desk) return
    var count = (desk.windows || []).length
    var section = desk.scratch ? "scratch" : "mill"
    if (Model.pickFilteredIndex(section, index, desk.scratch ? 0 : count, desk.scratch ? count : 0) < 0) return
    root.activateAt(root.deskIndex, index)
  }

  function pickLabel(index) {
    return index >= 0 && index < 9 ? "Ctrl+" + (index + 1) : ""
  }

  function closeCurrent() {
    var row = root.currentWindow()
    if (!row) return
    root.closeAddress(String(row.address || ""))
  }

  function closeAddress(address) {
    var toplevel = Model.findToplevel(Hyprland, address)
    if (toplevel && toplevel.wayland) {
      try { toplevel.wayland.close() } catch (e) {}
    }
    root.dispatchClose(address)
    Qt.callLater(root.rebuild)
  }

  Timer {
    id: pendingFocus
    interval: 16
    repeat: false
    property string address: ""
    onTriggered: {
      var a = pendingFocus.address
      pendingFocus.address = ""
      if (!a) return
      root.dispatchFocus(a)
      var toplevel = Model.findToplevel(Hyprland, a)
      if (toplevel && toplevel.wayland) {
        try { toplevel.wayland.activate() } catch (e) {}
      }
    }
  }

  Timer {
    interval: 530
    running: root.opened
    repeat: true
    onTriggered: root.caretOn = !root.caretOn
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      if (root.opened) root.rebuild()
    }
  }

  component AppPlaque: Item {
    id: plaque
    property string address: ""
    property string prettyName: ""
    property string title: ""
    property string badge: ""
    property string profileName: ""
    property string shortcutText: ""
    property url icon
    property bool selected: false
    property bool urgent: false
    property bool showShot: false

    readonly property int frameRadius: Style.space(16)
    readonly property string caption: {
      var bits = [plaque.prettyName]
      if (plaque.profileName) bits.push(plaque.profileName)
      return bits.join(" · ")
    }

    Rectangle {
      id: shot
      anchors.fill: parent
      radius: plaque.frameRadius
      color: Color.background
      clip: true
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: shotMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
      }

      Image {
        anchors.centerIn: parent
        width: Style.space(40)
        height: width
        fillMode: Image.PreserveAspectFit
        source: plaque.icon
        // image://icon/ goes through QIcon::pixmap. An asynchronous Image
        // runs that on QQuickPixmapReader, which segfaults the shell on
        // Wayland (quickshell#1028). Stay on the GUI thread.
        asynchronous: false
        opacity: 0.28
      }

      Item {
        anchors.centerIn: parent
        width: parent.width * 2
        height: parent.height * 2
        scale: 0.5
        layer.enabled: true
        layer.smooth: true

        Loader {
          anchors.fill: parent
          active: plaque.showShot && root.opened
          sourceComponent: Component {
            ScreencopyView {
              captureSource: root.captureSource(plaque.address)
              live: root.opened && plaque.showShot
              paintCursor: false
            }
          }
        }
      }
    }

    Rectangle {
      id: shotMask
      anchors.fill: shot
      radius: plaque.frameRadius
      color: "black"
      visible: false
      layer.enabled: true
    }

    Rectangle {
      anchors.fill: shot
      radius: plaque.frameRadius
      color: "transparent"
      border.width: plaque.selected ? Style.space(2) : 1
      border.color: plaque.selected
        ? root.accent
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
      z: 3
    }

    Rectangle {
      anchors.left: shot.left
      anchors.right: shot.right
      anchors.bottom: shot.bottom
      height: Math.min(shot.height * 0.38, Style.space(52))
      radius: plaque.frameRadius
      z: 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.35; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.15) }
        GradientStop { position: 1.0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82) }
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.bottomMargin: Style.space(8)
        spacing: 1

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            id: nameShortcut
            visible: plaque.shortcutText.length > 0
            text: plaque.shortcutText
            textFormat: Text.PlainText
            color: plaque.selected ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width - (nameShortcut.visible ? nameShortcut.implicitWidth + parent.spacing : 0)
            text: plaque.caption
            textFormat: Text.PlainText
            color: plaque.selected ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          visible: plaque.title.length > 0 || plaque.badge.length > 0
          text: (plaque.badge ? plaque.badge + "  ·  " : "") + (plaque.title || "")
          textFormat: Text.PlainText
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    Rectangle {
      visible: plaque.urgent
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(10)
      z: 4
      width: Style.space(8)
      height: Style.space(8)
      radius: width / 2
      color: Color.urgent
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ikea"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Image {
      anchors.fill: parent
      source: "file://" + root.wallpaperPath
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      opacity: 0.42
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 0.72
        blurMax: 48
        saturation: 0.35
      }
    }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55) }
        GradientStop { position: 0.45; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.28) }
        GradientStop { position: 1.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: hull
      width: Math.min(panel.width - Style.gapsOut * 2, Style.space(1100))
      height: Math.min(panel.height - Style.gapsOut * 2, Style.space(720))
      anchors.centerIn: parent

      Repeater {
        model: 9
        Rectangle {
          required property int index
          width: hull.width * 0.055
          height: hull.height * 0.36
          radius: width / 2
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.05 + (index % 2) * 0.02)
          anchors.horizontalCenter: hull.horizontalCenter
          anchors.verticalCenter: hull.verticalCenter
          anchors.verticalCenterOffset: -hull.height * 0.02
          transformOrigin: Item.Bottom
          rotation: index * 20 - 80
        }
      }

      Rectangle {
        id: boat
        anchors.fill: parent
        radius: Style.space(36)
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.78)
        border.width: Style.space(2)
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(10)
          radius: parent.radius
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
        }

        Repeater {
          model: 6
          Rectangle {
            required property int index
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(28)
            anchors.rightMargin: Style.space(28)
            y: Style.space(28) + index * Style.space(14)
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06 + (index % 2) * 0.03)
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onShortcutOverride: function(event) {
          if (root.isPickModifier(event) && root.pickKeyIndex(event) >= 0)
            event.accepted = true
        }
        Keys.onPressed: function(event) {
          var lateral = Util.readingKey(event)
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete || ((event.key === Qt.Key_W) && (event.modifiers & Qt.ControlModifier))) {
            root.closeCurrent()
            event.accepted = true
          } else if (root.isPickModifier(event) && root.pickKeyIndex(event) >= 0) {
            root.activateIndex(root.pickKeyIndex(event))
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.moveWindow((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (lateral === Qt.Key_Left) {
            root.moveDesk(-1)
            event.accepted = true
          } else if (lateral === Qt.Key_Right) {
            root.moveDesk(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveWindow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveWindow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.focusWindow(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            var endDesk = root.currentDesk()
            var endCount = endDesk ? (endDesk.windows || []).length : 0
            root.focusWindow(Math.max(0, endCount - 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activateCurrent()
            event.accepted = true
          } else if (root.isFilterTextKey(event)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Repeater {
          model: 9
          Item {
            required property int index
            Shortcut {
              enabled: root.opened
              context: Qt.WindowShortcut
              sequence: "Ctrl+" + (index + 1)
              autoRepeat: false
              onActivated: root.activateIndex(index)
            }
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(28)
        spacing: Style.space(14)

        Item {
          width: parent.width
          height: Style.space(78)
          z: 8

          Rectangle {
            anchors.centerIn: searchPlaque
            width: searchPlaque.width + Style.space(18)
            height: searchPlaque.height + Style.space(10)
            radius: height / 2
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            layer.enabled: true
            layer.effect: MultiEffect {
              blurEnabled: true
              blur: 0.85
              blurMax: 28
            }
          }

          Rectangle {
            id: searchPlaque
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(640))
            height: Style.space(64)
            radius: height / 2
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.88)
            border.width: Style.space(2)
            border.color: root.accent

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(26)
              anchors.rightMargin: Style.space(26)
              spacing: Style.space(14)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "IkeA"
                textFormat: Text.PlainText
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 1.8
              }

              Rectangle {
                width: 1
                height: parent.height * 0.46
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
              }

              Item {
                width: parent.width - Style.space(72) - Style.space(14) - 1 - Style.space(14)
                height: parent.height

                Text {
                  anchors.left: parent.left
                  anchors.right: caret.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.filterText || strings.t("search.placeholder")
                  textFormat: Text.PlainText
                  color: root.filterText ? root.foreground : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  elide: Text.ElideRight
                }

                Rectangle {
                  id: caret
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.right: parent.right
                  width: Style.space(3)
                  height: Style.font.heading
                  radius: 1
                  color: root.accent
                  visible: root.caretOn && root.opened
                  opacity: 0.9
                }
              }
            }
          }
        }

        ListView {
          id: deskTabs
          width: parent.width
          height: root.desks.length > 0 ? Style.space(34) : 0
          orientation: ListView.Horizontal
          layoutDirection: LayoutMirroring.enabled ? Qt.RightToLeft : Qt.LeftToRight
          model: root.desks.length
          spacing: Style.space(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          highlight: Item {}
          highlightFollowsCurrentItem: false

          delegate: Rectangle {
            id: tab
            required property int index
            readonly property var desk: (index >= 0 && index < root.desks.length) ? root.desks[index] : null
            readonly property bool selected: index === root.deskIndex
            width: tabLabel.implicitWidth + Style.space(28)
            height: Style.space(30)
            radius: Style.space(8)
            color: tab.selected
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, tab.desk && tab.desk.scratch ? 0.28 : 0.18)
              : "transparent"
            border.width: 1
            border.color: tab.selected
              ? root.accent
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, tab.desk && tab.desk.scratch ? 0.38 : 0.16)

            Behavior on color { enabled: root.motions; ColorAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            Behavior on border.color { enabled: root.motions; ColorAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

            Text {
              id: tabLabel
              anchors.centerIn: parent
              text: root.deskTab(tab.desk)
              textFormat: Text.PlainText
              color: tab.selected ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: tab.selected
              font.letterSpacing: 0.8
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.focusDesk(tab.index)
            }
          }
        }

        Item {
          id: millView
          width: parent.width
          height: Math.max(Style.space(180), parent.height - Style.space(78) - Style.space(14) - deskTabs.height - Style.space(14) - hint.height)
          clip: true
          onWidthChanged: root.armMotion()

          Repeater {
            model: root.desks.length
            delegate: Item {
              id: deskSlot
              required property int index
              readonly property int dist: index - root.deskIndex
              readonly property var desk: (index >= 0 && index < root.desks.length) ? root.desks[index] : null
              readonly property int windowCount: deskSlot.desk ? (deskSlot.desk.windows || []).length : 0
              // Targets, not the animated width and height. deskX() used to
              // read `width` while it was still moving, so x chased a new
              // destination every frame.
              readonly property int slotW: dist === 0 ? root.cardW : root.spineW
              readonly property int slotH: dist === 0 ? millView.height : Math.round(millView.height * 0.62)
              property real shown: dist === 0 ? 1 : 0
              visible: deskSlot.desk !== null && Math.abs(dist) <= 2
              width: slotW
              height: slotH
              x: root.deskX(dist, slotW)
              y: dist === 0 ? 0 : (millView.height - slotH) / 2
              z: dist === 0 ? 4 : 2
              opacity: Math.abs(dist) <= 1 ? 1 : 0

              Behavior on x { enabled: root.motions; Glide {} }
              Behavior on y { enabled: root.motions; Glide {} }
              Behavior on width { enabled: root.motions; Glide {} }
              Behavior on height { enabled: root.motions; Glide {} }
              Behavior on opacity { enabled: root.motions; Glide { duration: Style.duration(160) } }
              Behavior on shown { enabled: root.motions; Glide {} }

              Text {
                opacity: deskSlot.shown
                visible: opacity > 0.02
                anchors.centerIn: parent
                text: root.deskMark(deskSlot.desk)
                textFormat: Text.PlainText
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                font.family: root.fontFamily
                font.pixelSize: Style.space(120)
                font.bold: true
                z: 0
              }

              Repeater {
                model: (deskSlot.dist === 0 || deskSlot.shown > 0.02) ? deskSlot.windowCount : 0
                delegate: Item {
                  id: win
                  required property int index
                  // The first geometry is applied before this flips, so a new
                  // card does not grow up from y = 0.
                  property bool placed: false
                  readonly property int delta: index - root.windowIndex
                  readonly property var row: (deskSlot.desk && deskSlot.desk.windows) ? deskSlot.desk.windows[index] : null
                  readonly property int beyond: root.hiddenBeyond(win.delta, deskSlot.windowCount)
                  visible: win.row !== null && (win.delta === 0 || Math.abs(win.delta) <= root.stackDepth)
                  // The picture stays out until the plaque has arrived. It is
                  // placed against the final frame height, not the height the
                  // plaque is still animating, so it cannot drift off the desk.
                  opacity: Math.max(0, (deskSlot.shown - 0.82) / 0.18)
                  width: root.cardW
                  height: win.delta === 0 ? root.cardH : root.stripH
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: root.stackY(win.delta, deskSlot.slotH)
                  z: 8 - Math.abs(win.delta)
                  scale: win.delta === 0 ? 1 : Math.max(0.94, 1 - Math.abs(win.delta) * 0.02)

                  Component.onCompleted: win.placed = true

                  Behavior on y {
                    enabled: root.motions && win.placed && deskSlot.dist === 0 && deskSlot.shown > 0.99
                    Glide { duration: Style.duration(200) }
                  }
                  Behavior on height { enabled: root.motions && win.placed; Glide { duration: Style.duration(200) } }

                  AppPlaque {
                    anchors.fill: parent
                    visible: win.delta === 0
                    address: win.row ? win.row.address : ""
                    prettyName: win.row ? win.row.prettyName : ""
                    title: win.row ? win.row.title : ""
                    badge: win.row && win.row.activated ? strings.t("badge.now") : ""
                    profileName: win.row ? (win.row.profileName || "") : ""
                    shortcutText: root.pickLabel(win.index)
                    icon: win.row ? win.row.icon : ""
                    selected: true
                    urgent: win.row ? win.row.urgent === true : false
                    showShot: win.delta === 0 && deskSlot.shown > 0.82
                  }

                  Rectangle {
                    anchors.fill: parent
                    visible: win.delta !== 0
                    radius: Style.space(10)
                    color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82)
                    border.width: 1
                    border.color: win.row && win.row.urgent
                      ? Color.urgent
                      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

                    Item {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)

                      Image {
                        id: stripIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(22)
                        height: width
                        fillMode: Image.PreserveAspectFit
                        source: win.row ? win.row.icon : ""
                        // Same constraint as the card icon: image://icon/ must
                        // not load on QQuickPixmapReader.
                        asynchronous: false
                      }

                      Column {
                        anchors.left: stripIcon.right
                        anchors.leftMargin: Style.space(8)
                        anchors.right: parent.right
                        anchors.rightMargin: moreLabel.visible ? moreLabel.implicitWidth + Style.space(8) : 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                          width: parent.width
                          text: win.row
                            ? ((win.index < 9 ? root.pickLabel(win.index) + "  " : "")
                              + win.row.prettyName + (win.row.profileName ? " · " + win.row.profileName : ""))
                            : ""
                          textFormat: Text.PlainText
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          elide: Text.ElideRight
                        }

                        Text {
                          width: parent.width
                          visible: win.row && String(win.row.title || "").length > 0
                          text: win.row ? win.row.title : ""
                          textFormat: Text.PlainText
                          color: root.muted
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      Text {
                        id: moreLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.beyond > 0 && Math.abs(win.delta) === root.stackDepth
                        text: strings.t("peek.more").arg(Commons.I18n.formatNumber(win.beyond))
                        textFormat: Text.PlainText
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      if (!win.row) return
                      root.deskIndex = deskSlot.index
                      root.windowIndex = win.index
                      keyCatcher.forceActiveFocus()
                      if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton)
                        root.closeAddress(win.row.address)
                      else
                        root.activateAt(deskSlot.index, win.index)
                    }
                  }
                }
              }

              Rectangle {
                anchors.fill: parent
                opacity: 1 - deskSlot.shown
                visible: opacity > 0.02
                radius: Style.space(18)
                color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.62)
                border.width: 1
                border.color: deskSlot.desk && deskSlot.desk.scratch
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(16)
                  spacing: Style.space(8)

                  Text {
                    width: parent.width
                    text: root.deskMark(deskSlot.desk)
                    textFormat: Text.PlainText
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: deskSlot.desk && deskSlot.desk.scratch ? Style.font.heading : Style.font.displayLarge
                    font.bold: true
                    font.letterSpacing: deskSlot.desk && deskSlot.desk.scratch ? 1.4 : 0
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: strings.tn("desk.windows", deskSlot.windowCount).arg(Commons.I18n.formatNumber(deskSlot.windowCount))
                    textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(4)
                    Repeater {
                      model: Math.min(deskSlot.windowCount, 6)
                      Rectangle {
                        required property int index
                        width: Style.space(56)
                        height: Style.space(3)
                        radius: height / 2
                        color: root.accent
                        opacity: 0.22 + (index % 2) * 0.12
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.focusDesk(deskSlot.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: root.desks.length === 0
            width: parent.width * 0.7

            Text {
              width: parent.width
              text: "󰖲"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
            }
            Text {
              width: parent.width
              text: root.filterText
                ? strings.t("search.empty").arg(root.filterText)
                : strings.t("mill.empty")
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
            }
          }
        }

        Text {
          id: hint
          width: parent.width
          height: Style.space(22)
          text: strings.t("hint")
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.48
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
