import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
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
  property string focusSection: "mill"
  property int millIndex: 0
  property int scratchIndex: 0
  property bool cursorActive: false
  property bool preferNextOnOpen: false
  property bool caretOn: true

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  property color muted: Color.muted
  readonly property int cornerRadius: Math.max(Style.cornerRadius, Style.space(18))
  property string fontFamily: Style.font.menuFamily

  readonly property int millMaxW: Style.space(340)
  readonly property int millMaxH: Style.space(200)
  readonly property int scratchMaxW: Style.space(220)
  readonly property int scratchMaxH: Style.space(124)

  function fitCardW(aspect, maxW, maxH) {
    var ar = Number(aspect)
    if (!isFinite(ar) || ar <= 0) ar = 1.6
    var w = maxW
    var h = w / ar
    if (h > maxH) w = maxH * ar
    return Math.round(w)
  }

  function fitCardH(aspect, maxW, maxH) {
    var w = fitCardW(aspect, maxW, maxH)
    var ar = Number(aspect)
    if (!isFinite(ar) || ar <= 0) ar = 1.6
    return Math.round(w / ar)
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.millIndex = 0
    root.scratchIndex = 0
    root.focusSection = "mill"
    root.cursorActive = true
    root.preferNextOnOpen = true
    root.disarmPointer()
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
    return row
  }

  function fillModel(model, rows) {
    model.clear()
    for (var i = 0; i < rows.length; i++) model.append(rows[i])
  }

  function rebuild() {
    var collected = Model.collectWindows(Hyprland)
    var mill = []
    var scratch = []
    for (var i = 0; i < collected.length; i++) {
      var row = decorate(collected[i])
      if (!Model.matchesFilter(row, root.filterText)) continue
      if (row.scratchpad) scratch.push(row)
      else mill.push(row)
    }

    var keepMill = ""
    var keepScratch = ""
    if (!root.preferNextOnOpen) {
      if (millModel.count > 0 && millIndex >= 0 && millIndex < millModel.count)
        keepMill = String(millModel.get(millIndex).address || "")
      if (scratchModel.count > 0 && scratchIndex >= 0 && scratchIndex < scratchModel.count)
        keepScratch = String(scratchModel.get(scratchIndex).address || "")
    }

    fillModel(millModel, mill)
    fillModel(scratchModel, scratch)

    var nextMill = 0
    var nextScratch = 0
    for (var j = 0; j < mill.length; j++) {
      if (keepMill && String(mill[j].address) === keepMill) nextMill = j
    }
    for (var k = 0; k < scratch.length; k++) {
      if (keepScratch && String(scratch[k].address) === keepScratch) nextScratch = k
    }

    if (root.preferNextOnOpen) {
      root.preferNextOnOpen = false
      nextMill = mill.length > 1 ? 1 : 0
    }

    millIndex = mill.length === 0 ? 0 : Math.min(nextMill, mill.length - 1)
    scratchIndex = scratch.length === 0 ? 0 : Math.min(nextScratch, scratch.length - 1)

    if (focusSection === "mill" && mill.length === 0 && scratch.length > 0)
      focusSection = "scratch"
    else if (focusSection === "scratch" && scratch.length === 0 && mill.length > 0)
      focusSection = "mill"

    cursorActive = mill.length + scratch.length > 0
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.preferNextOnOpen = false
    root.disarmPointer()
    root.rebuild()
  }

  function millDist(index) {
    var n = millModel.count
    if (n <= 1) return index - millIndex
    var d = index - millIndex
    var half = Math.floor(n / 2)
    if (d > half) d -= n
    if (d < -half) d += n
    return d
  }

  function select(delta) {
    root.disarmPointer()
    root.cursorActive = true
    if (root.focusSection === "scratch") {
      if (scratchModel.count === 0) return
      scratchIndex = (scratchIndex + delta + scratchModel.count) % scratchModel.count
    } else {
      if (millModel.count === 0) return
      millIndex = (millIndex + delta + millModel.count) % millModel.count
    }
    keyCatcher.forceActiveFocus()
  }

  function moveSection(dir) {
    if (dir > 0 && focusSection === "mill" && scratchModel.count > 0)
      focusSection = "scratch"
    else if (dir < 0 && focusSection === "scratch" && millModel.count > 0)
      focusSection = "mill"
    keyCatcher.forceActiveFocus()
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

  function disarmPointer() {
    pointerGate.reset()
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

  function currentRow() {
    if (focusSection === "scratch") {
      if (scratchIndex < 0 || scratchIndex >= scratchModel.count) return null
      return scratchModel.get(scratchIndex)
    }
    if (millIndex < 0 || millIndex >= millModel.count) return null
    return millModel.get(millIndex)
  }

  function activateCurrent() {
    var row = currentRow()
    if (!row) return
    pendingFocus.address = String(row.address || "")
    root.dismiss()
    pendingFocus.restart()
  }

  function activateMill(index) {
    focusSection = "mill"
    millIndex = index
    activateCurrent()
  }

  function activateScratch(index) {
    focusSection = "scratch"
    scratchIndex = index
    activateCurrent()
  }

  function activateIndex(index) {
    var section = root.focusSection === "scratch" ? "scratch" : "mill"
    if (Model.pickFilteredIndex(section, index, millModel.count, scratchModel.count) < 0) return
    if (section === "scratch") root.activateScratch(index)
    else root.activateMill(index)
  }

  function closeCurrent() {
    var row = currentRow()
    if (!row) return
    closeAddress(String(row.address || ""))
  }

  function closeAddress(address) {
    var toplevel = Model.findToplevel(Hyprland, address)
    if (toplevel && toplevel.wayland) {
      try { toplevel.wayland.close() } catch (e) {}
    }
    root.dispatchClose(address)
    Qt.callLater(root.rebuild)
  }

  ListModel { id: millModel }
  ListModel { id: scratchModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: hull
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
    property bool compact: false

    readonly property int frameRadius: Style.space(plaque.compact ? 12 : 16)
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
        width: plaque.compact ? Style.space(28) : Style.space(40)
        height: width
        fillMode: Image.PreserveAspectFit
        source: plaque.icon
        asynchronous: true
        opacity: 0.28
      }

      Item {
        anchors.centerIn: parent
        width: parent.width * 2
        height: parent.height * 2
        scale: 0.5
        layer.enabled: true
        layer.smooth: true

        ScreencopyView {
          anchors.fill: parent
          captureSource: root.captureSource(plaque.address)
          live: root.opened
          paintCursor: false
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
      height: Math.min(shot.height * 0.38, Style.space(plaque.compact ? 40 : 52))
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
            font.pixelSize: plaque.compact ? Style.font.caption : Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width - (nameShortcut.visible ? nameShortcut.implicitWidth + parent.spacing : 0)
            text: plaque.caption
            textFormat: Text.PlainText
            color: plaque.selected ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: plaque.compact ? Style.font.caption : Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          visible: plaque.title.length > 0 || plaque.badge.length > 0
          text: plaque.compact
            ? plaque.badge
            : ((plaque.badge ? plaque.badge + "  ·  " : "") + (plaque.title || "Untitled"))
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

      // Mill / paddle-wheel silhouette in theme colors
      Repeater {
        model: 9
        Rectangle {
          required property int index
          width: hull.width * 0.08
          height: hull.height * 0.42
          radius: width / 2
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.07 + (index % 2) * 0.03)
          anchors.horizontalCenter: hull.horizontalCenter
          anchors.verticalCenter: hull.verticalCenter
          anchors.verticalCenterOffset: -hull.height * 0.06
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

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: parent.height * 0.28
          radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.35; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10) }
            GradientStop { position: 1.0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.92) }
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
            root.select((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.focusSection === "scratch") root.moveSection(-1)
            else root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.focusSection === "mill" && scratchModel.count > 0) root.moveSection(1)
            else root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.disarmPointer()
            root.cursorActive = true
            if (root.focusSection === "scratch") root.scratchIndex = 0
            else root.millIndex = 0
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.disarmPointer()
            root.cursorActive = true
            if (root.focusSection === "scratch") root.scratchIndex = Math.max(0, scratchModel.count - 1)
            else root.millIndex = Math.max(0, millModel.count - 1)
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
        spacing: Style.space(18)

        Item {
          width: parent.width
          height: Style.space(92)
          z: 8

          Rectangle {
            id: searchGlow
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(640)) + Style.space(18)
            height: parent.height + Style.space(10)
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
            height: Style.space(78)
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
                  text: root.filterText || "Search the mill…"
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

        Item {
          width: parent.width
          height: parent.height - Style.space(92) - Style.space(18) - scratchDock.height - Style.space(18) - hint.height

          Item {
            id: millView
            anchors.fill: parent
            visible: millModel.count > 0
            clip: false

            Repeater {
              model: millModel
              delegate: Item {
                id: millDelegate
                required property int index
                required property string address
                required property string title
                required property string className
                required property string appId
                required property string prettyName
                required property int workspaceId
                required property bool activated
                required property bool urgent
                required property string profileName
                required property real aspectRatio

                readonly property int dist: root.millDist(index)
                readonly property real absDist: Math.abs(dist)
                visible: absDist <= 2
                width: root.fitCardW(aspectRatio, root.millMaxW, root.millMaxH)
                height: root.fitCardH(aspectRatio, root.millMaxW, root.millMaxH)
                x: millView.width / 2 - width / 2 + dist * (width * 0.62 + Style.space(28))
                y: millView.height / 2 - height / 2 + Style.space(20) + absDist * absDist * Style.space(16)
                z: 20 - absDist
                scale: 1.06 - absDist * 0.2
                opacity: 1 - absDist * 0.26
                property real blurAmt: absDist * 0.42

                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                layer.enabled: millDelegate.blurAmt > 0.12
                layer.smooth: true
                layer.effect: MultiEffect {
                  blurEnabled: true
                  blur: millDelegate.blurAmt
                  blurMax: 20
                }

                AppPlaque {
                  anchors.fill: parent
                  address: millDelegate.address
                  prettyName: millDelegate.prettyName
                  title: millDelegate.title
                  badge: millDelegate.activated ? "Now" : ("WS " + millDelegate.workspaceId)
                  profileName: millDelegate.profileName
                  icon: root.iconSource({ className: millDelegate.className, appId: millDelegate.appId })
                  selected: root.focusSection === "mill" && millDelegate.index === root.millIndex
                  urgent: millDelegate.urgent
                  shortcutText: root.focusSection === "mill" && millDelegate.index < 9
                    ? ("Ctrl+" + (millDelegate.index + 1))
                    : ""
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    root.focusSection = "mill"
                    root.millIndex = millDelegate.index
                    keyCatcher.forceActiveFocus()
                    if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton)
                      root.closeAddress(millDelegate.address)
                    else
                      root.activateMill(millDelegate.index)
                  }
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: millModel.count === 0
            width: parent.width * 0.7

            Text {
              width: parent.width
              text: "󰖲"
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
            }
            Text {
              width: parent.width
              text: root.filterText ? ("No mill matches for “" + root.filterText + "”") : "No open windows on the mill"
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

        Item {
          id: scratchDock
          width: parent.width
          visible: scratchModel.count > 0
          height: visible ? scratchFrame.implicitHeight : 0

          Rectangle {
            id: scratchFrame
            width: parent.width
            implicitHeight: scratchCol.implicitHeight + Style.space(24)
            radius: Style.space(22)
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.focusSection === "scratch" ? 0.7 : 0.28)

            Column {
              id: scratchCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(14)
              spacing: Style.space(8)

              Row {
                spacing: Style.space(10)
                Text {
                  text: "Scratchpad"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
                Text {
                  text: scratchModel.count === 1 ? "1 window below the waterline" : (scratchModel.count + " windows below the waterline")
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Flow {
                id: scratchFlow
                width: parent.width
                spacing: Style.space(10)

                Repeater {
                  model: scratchModel
                  delegate: Item {
                    id: scratchDelegate
                    required property int index
                    required property string address
                    required property string title
                    required property string className
                    required property string appId
                    required property string prettyName
                    required property string profileName
                    required property bool urgent
                    required property real aspectRatio

                    width: root.fitCardW(aspectRatio, root.scratchMaxW, root.scratchMaxH)
                    height: root.fitCardH(aspectRatio, root.scratchMaxW, root.scratchMaxH)
                    opacity: root.focusSection === "scratch" && index === root.scratchIndex ? 1 : 0.86
                    scale: root.focusSection === "scratch" && index === root.scratchIndex ? 1.03 : 0.98

                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    AppPlaque {
                      anchors.fill: parent
                      address: scratchDelegate.address
                      prettyName: scratchDelegate.prettyName
                      title: scratchDelegate.title
                      badge: "Scratch"
                      profileName: scratchDelegate.profileName
                      icon: root.iconSource({ className: scratchDelegate.className, appId: scratchDelegate.appId })
                      selected: root.focusSection === "scratch" && scratchDelegate.index === root.scratchIndex
                      urgent: scratchDelegate.urgent
                      compact: true
                      shortcutText: root.focusSection === "scratch" && scratchDelegate.index < 9
                        ? ("Ctrl+" + (scratchDelegate.index + 1))
                        : ""
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        root.focusSection = "scratch"
                        root.scratchIndex = scratchDelegate.index
                        keyCatcher.forceActiveFocus()
                        if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton)
                          root.closeAddress(scratchDelegate.address)
                        else
                          root.activateScratch(scratchDelegate.index)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          id: hint
          width: parent.width
          height: Style.space(22)
          text: "Ctrl+1–9 pick  ·  ← → mill  ·  ↓ scratchpad  ·  Enter switch  ·  Delete close  ·  Esc dismiss"
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
