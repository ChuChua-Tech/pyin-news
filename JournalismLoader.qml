import QtQuick
import qs.Commons

Item {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family
  property string phaseText: ""
  property int stage: 0
  property int effectProgress: 0
  property int noiseFrame: 0
  property int spinnerFrame: 0
  property bool cursorVisible: true

  readonly property var stages: [
    "RECEIVING SOURCE COPY",
    "TRACING ATTRIBUTION",
    "FLAGGING UNCERTAINTY",
    "EDITING SOURCE-BOUND TL;DR"
  ]
  readonly property var spinnerGlyphs: ["◢", "◣", "◤", "◥"]
  readonly property string blockLogo:
      "▄████▄   █▄   ▄█  ███████  █▄    █\n"
    + "██  ██   ██   ██     █     ██▄   █\n"
    + "██  ██   ▀██ ██▀     █     ███▄  █\n"
    + "█████▀     ███       █     █ ██▄ █\n"
    + "██          █        █     █  ████\n"
    + "██          █        █     █   ███\n"
    + "▀▀          ▀      ▀▀▀▀▀▀  ▀    ▀"

  implicitHeight: Style.space(224)

  function resetAnimation() {
    stage = 0
    effectProgress = 0
    noiseFrame = 0
    spinnerFrame = 0
    cursorVisible = true
  }

  function animatedLogo() {
    var source = root.blockLogo
    var noise = ["░", "▒", "▓", "▀", "▄", "█"]
    var output = ""
    var row = 0
    var column = 0
    for (var i = 0; i < source.length; i++) {
      var glyph = source.charAt(i)
      if (glyph === "\n") {
        output += glyph
        row++
        column = 0
        continue
      }
      if (glyph === " ") {
        output += " "
        column++
        continue
      }
      var threshold = (row * 31 + column * 17 + (column % 3) * 11) % 101
      if (threshold <= root.effectProgress) output += glyph
      else if (threshold <= root.effectProgress + 22)
        output += noise[(row * 7 + column * 3 + root.noiseFrame) % noise.length]
      else output += " "
      column++
    }
    return output
  }

  function barText() {
    var cells = 22
    var filled = Math.max(0, Math.min(cells,
      Math.floor(root.effectProgress * cells / 100)))
    var text = ""
    for (var i = 0; i < cells; i++) text += i < filled ? "█" : "░"
    return text
  }

  onVisibleChanged: if (visible) resetAnimation()

  Timer {
    interval: 48
    repeat: true
    running: root.visible
    onTriggered: {
      root.noiseFrame++
      root.spinnerFrame = (root.spinnerFrame + 1) % root.spinnerGlyphs.length
      if (root.effectProgress < 100)
        root.effectProgress = Math.min(100, root.effectProgress + 4)
    }
  }

  Timer {
    interval: 430
    repeat: true
    running: root.visible
    onTriggered: root.cursorVisible = !root.cursorVisible
  }

  Timer {
    interval: 2250
    repeat: true
    running: root.visible
    onTriggered: {
      root.stage = (root.stage + 1) % root.stages.length
      root.effectProgress = 76
    }
  }

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(520))
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      text: "PYIN NEWS  //  SOURCE DESK"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.6
    }

    Item {
      id: logoFrame
      width: parent.width
      height: Math.max(logoGhost.implicitHeight, Style.space(114))
      clip: true

      Text {
        id: logoGhost
        anchors.centerIn: parent
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: root.blockLogo
        color: root.accent
        opacity: 0.075
        font.family: root.fontFamily
        font.pixelSize: Math.max(Style.space(9),
          Math.min(Style.space(15), logoFrame.width / 29))
        font.bold: true
        lineHeight: 0.9
      }

      Text {
        id: decodedLogo
        anchors.centerIn: parent
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: root.animatedLogo()
        color: root.accent
        opacity: 0.94
        font.family: root.fontFamily
        font.pixelSize: logoGhost.font.pixelSize
        font.bold: true
        lineHeight: logoGhost.lineHeight

        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: root.visible && root.effectProgress >= 100
          NumberAnimation { to: 0.72; duration: 760; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 760; easing.type: Easing.InOutSine }
        }
      }

      Rectangle {
        id: scanLine
        y: (parent.height - logoGhost.implicitHeight) / 2
        width: Math.max(1, Style.normalBorderWidth)
        height: logoGhost.implicitHeight
        color: root.foreground
        opacity: 0.48

        SequentialAnimation on x {
          loops: Animation.Infinite
          running: root.visible
          NumberAnimation {
            from: 0
            to: Math.max(0, logoFrame.width - scanLine.width)
            duration: 1450
            easing.type: Easing.InOutQuad
          }
          PauseAnimation { duration: 260 }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      text: root.spinnerGlyphs[root.spinnerFrame] + "  "
        + (root.phaseText || String(root.stages[root.stage] || ""))
        + (root.cursorVisible ? "  █" : "   ")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 0.75
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      text: root.barText()
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.6
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      text: "ONE SOURCE IN  //  ATTRIBUTION KEPT  //  UNCERTAINTY SHOWN"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.4
      wrapMode: Text.Wrap
    }
  }
}
