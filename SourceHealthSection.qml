import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: section

  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family
  property var health: ({})
  property bool busy: false
  property bool refreshing: false
  property bool expanded: false
  readonly property var counts: health.counts || ({})
  readonly property var failures: (health.sources || []).filter(function(source) {
    return source.status === "failing"
  })

  signal statusRequested()
  signal refreshRequested()

  spacing: Style.spacing.lg

  Button {
    width: parent.width
    text: "SOURCE HEALTH"
      + (Number(section.counts.failing || 0) > 0
        ? "  ·  " + String(section.counts.failing) + " NEED ATTENTION" : "")
    iconText: section.expanded ? "󰅀" : "󰅂"
    foreground: section.accent
    accent: section.accent
    fontFamily: section.fontFamily
    fontSize: Style.font.caption
    leftAlign: true
    focusable: true
    horizontalPadding: 0
    onClicked: {
      section.expanded = !section.expanded
      if (section.expanded) section.statusRequested()
    }
  }

  Column {
    visible: section.expanded
    width: parent.width
    spacing: Style.spacing.lg

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: section.refreshing ? "Checking active feeds… saved results update when finished."
        : (section.busy ? "Loading saved feed status…"
          : (section.health.ok === false ? String(section.health.error || "Could not load feed status")
            : (section.health.ok ? String(section.counts.healthy || 0) + " healthy  ·  "
              + String(section.counts.failing || 0) + " failing  ·  "
              + String(section.counts.unchecked || 0) + " not checked"
              : "Inspect the most recent check of each active feed.")))
      color: section.foreground
      font.family: section.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "A failed feed keeps its cached stories within your retention window. "
        + "These results stay on this device."
      color: section.dim
      font.family: section.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.sm

      Button {
        text: "Reload status"
        foreground: section.foreground
        accent: section.accent
        fontFamily: section.fontFamily
        bordered: true
        focusable: true
        enabled: !section.busy && !section.refreshing
        tooltipText: "Read saved results without contacting publishers"
        onClicked: section.statusRequested()
      }

      Button {
        text: section.refreshing ? "Refreshing feeds…" : "Refresh feeds"
        foreground: section.foreground
        accent: section.accent
        fontFamily: section.fontFamily
        bordered: true
        focusable: true
        enabled: !section.refreshing
        tooltipText: "Check your active RSS and Atom feeds now"
        onClicked: section.refreshRequested()
      }
    }

    Text {
      visible: section.health.ok === true && !section.busy && section.failures.length === 0
      width: parent.width
      textFormat: Text.PlainText
      text: Number(section.counts.total || 0) === 0 ? "No active feeds selected."
        : (Number(section.counts.unchecked || 0) > 0
          ? "No recorded failures. Refresh feeds to check sources without a saved result."
          : "All active feeds passed their last check.")
      color: section.dim
      font.family: section.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    Repeater {
      model: section.expanded ? section.failures : []

      BorderSurface {
        required property var modelData
        width: parent.width
        height: details.implicitHeight + Style.spacing.lg * 2
        color: Style.controlFill(false, false, section.foreground, section.accent)
        borderSpec: Border.controlSpec("normal", section.foreground, section.accent)
        radius: Style.cornerRadius

        Column {
          id: details
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: Style.spacing.rowPaddingX
          anchors.rightMargin: Style.spacing.rowPaddingX
          anchors.topMargin: Style.spacing.lg
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData.name || "Feed")
            color: section.foreground
            font.family: section.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            wrapMode: Text.Wrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData.last_error || "The last check failed.")
            color: section.dim
            font.family: section.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WrapAnywhere
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Last checked: " + String(modelData.last_checked_age || "never")
              + "  ·  Last success: " + String(modelData.last_success_age || "never")
              + "\n" + String(modelData.consecutive_failures || 1) + " consecutive failed checks"
            color: section.dim
            font.family: section.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
