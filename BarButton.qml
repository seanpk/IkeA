import QtQuick
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import "WindowsModel.js" as Model

BarWidget {
  id: root
  moduleName: "ikekavas.ikea"

  readonly property int runningCount: Model.windowCount(Hyprland)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖲"
    tooltipText: "IkeA · I know every App · " + (runningCount === 1 ? "1 open window" : (runningCount + " open windows")) + " · Super+A"
    onPressed: function(b) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle ikekavas.ikea")
    }
  }
}
