import QtQuick
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "WindowsModel.js" as Model

BarWidget {
  id: root
  moduleName: "ikekavas.ikea"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property int runningCount: Model.windowCount(Hyprland)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖲"
    tooltipText: strings.tn("bar.tooltip", root.runningCount).arg(Commons.I18n.formatNumber(root.runningCount))
    onPressed: function(b) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle ikekavas.ikea")
    }
  }
}
