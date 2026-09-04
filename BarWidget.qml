import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tech.chuchua.news"

  readonly property string backendPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news"

  function openWindow() {
    if (!bar || !bar.shell) return
    var payload = JSON.stringify({ settings: root.settings || ({}) })
    if (typeof bar.shell.toggle === "function")
      bar.shell.toggle(root.moduleName, payload)
    else if (typeof bar.shell.summon === "function")
      bar.shell.summon(root.moduleName, payload)
  }

  function refresh() {
    Quickshell.execDetached([root.backendPath, "refresh"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰎕"
    slotSize: Style.bar.iconSlot
    tooltipText: "PYIN News"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openWindow()
      else root.refresh()
    }
  }
}
