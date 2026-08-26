import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "WindowsModel.js" as Model

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool preferNextOnOpen: false
  property var windows: []

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(22), Style.font.caption + Style.spacing.sm)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(56), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int rowGap: Style.space(4)
  property int cardWidth: Math.min(Style.space(560), Math.max(Style.space(420), panel.width - Style.gapsOut * 2))
  readonly property int visibleRows: displayModel.count === 0 ? 3 : Math.max(1, Math.min(8, displayModel.count))
  readonly property int listHeight: visibleRows * root.rowHeight + Math.max(0, visibleRows - 1) * root.rowGap

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
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
    root.activateIndex(root.selectedIndex)
    return "ok"
  }

  function focusAt(indexStr) {
    root.activateIndex(parseInt(indexStr, 10))
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

  // AppLibrary.iconSource() treats "/", "file://", and "image://" as image URLs.
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

  function rebuild() {
    var collected = Model.collectWindows(Hyprland)
    var rows = []
    for (var i = 0; i < collected.length; i++) {
      var row = collected[i]
      row.prettyName = Model.prettyApp(row.className, row.appId, desktopName(row.className, row.appId))
      if (!Model.matchesFilter(row, root.filterText)) continue
      rows.push(row)
    }
    root.windows = rows

    var keepAddress = ""
    if (!root.preferNextOnOpen && rows.length > 0 && selectedIndex >= 0 && selectedIndex < root.windows.length)
      keepAddress = String(root.windows[selectedIndex].address || "")

    displayModel.clear()
    var nextIndex = 0
    for (var j = 0; j < rows.length; j++) {
      displayModel.append(rows[j])
      if (keepAddress && String(rows[j].address) === keepAddress) nextIndex = j
    }

    if (root.preferNextOnOpen) {
      root.preferNextOnOpen = false
      nextIndex = rows.length > 1 ? 1 : 0
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (nextIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else selectedIndex = nextIndex
    cursorActive = displayModel.count > 0
    Qt.callLater(function() {
      if (displayModel.count <= 8)
        resultList.contentY = 0
      else if (displayModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.preferNextOnOpen = false
    root.disarmPointer()
    root.rebuild()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
    keyCatcher.forceActiveFocus()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
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

  function activateIndex(index) {
    if (index < 0 || index >= root.windows.length) return
    var row = root.windows[index]
    if (!row) return
    var address = String(row.address || "")
    pendingFocus.address = address
    root.dismiss()
    pendingFocus.restart()
  }

  function closeIndex(index) {
    if (index < 0 || index >= root.windows.length) return
    var row = root.windows[index]
    if (!row) return
    var address = String(row.address || "")
    var toplevel = Model.findToplevel(Hyprland, address)
    if (toplevel && toplevel.wayland) {
      try { toplevel.wayland.close() } catch (e) {}
    }
    root.dispatchClose(address)
    Qt.callLater(root.rebuild)
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
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

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      if (root.opened) root.rebuild()
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

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: innerColumn.implicitHeight + contentTopInset + contentBottomInset
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      Behavior on height {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }

      FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete || ((event.key === Qt.Key_W) && (event.modifiers & Qt.ControlModifier))) {
            root.closeIndex(root.selectedIndex)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.select((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            if (displayModel.count > 0) {
              root.disarmPointer()
              root.cursorActive = true
              root.selectedIndex = 0
              resultList.positionViewAtIndex(0, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            if (displayModel.count > 0) {
              root.disarmPointer()
              root.cursorActive = true
              root.selectedIndex = displayModel.count - 1
              resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (displayModel.count > 0)
              root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        id: innerColumn
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "IkeA"
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.filterText || "Search open windows…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }
          }
        }

        Item {
          width: parent.width
          height: root.listHeight
          implicitHeight: root.listHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowGap
            boundsBehavior: Flickable.StopAtBounds
            focus: false
            activeFocusOnTab: false
            keyNavigationEnabled: false
            highlightRangeMode: ListView.NoHighlightRange
            currentIndex: root.cursorActive ? root.selectedIndex : -1
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 120
            highlightResizeDuration: 120
            highlightMoveVelocity: -1
            highlightResizeVelocity: -1

            highlight: Rectangle {
              color: root.selectedBackground
              radius: root.cornerRadius
            }

            delegate: Item {
              id: row
              required property int index
              required property string address
              required property string title
              required property string className
              required property string appId
              required property string prettyName
              required property int workspaceId
              required property bool activated
              required property bool urgent

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property var iconRow: ({
                className: row.className,
                appId: row.appId
              })

              width: ListView.view.width
              height: root.rowHeight

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.space(12)

                Image {
                  width: Style.space(32)
                  height: Style.space(32)
                  anchors.verticalCenter: parent.verticalCenter
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  source: root.iconSource(row.iconRow)
                  asynchronous: true
                  smooth: true
                }

                Column {
                  width: parent.width - Style.space(32) - parent.spacing - workspaceLabel.width - Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: row.prettyName
                    textFormat: Text.PlainText
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight

                    Behavior on color {
                      ColorAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                  }

                  Text {
                    width: parent.width
                    text: row.title || "Untitled"
                    textFormat: Text.PlainText
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.62
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: workspaceLabel
                  anchors.verticalCenter: parent.verticalCenter
                  visible: row.workspaceId > 0
                  text: row.activated ? "Now" : ("WS " + row.workspaceId)
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Rectangle {
                visible: row.urgent
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(3)
                height: parent.height - Style.space(16)
                radius: width / 2
                color: Color.urgent
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: function(mouse) {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  keyCatcher.forceActiveFocus()
                  if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton)
                    root.closeIndex(row.index)
                  else
                    root.activateIndex(row.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰖲"
              color: root.foreground
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.filterText ? ("No matches for “" + root.filterText + "”") : "No open windows"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: "Arrows move  ·  Enter switch  ·  Delete close  ·  Esc dismiss"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
