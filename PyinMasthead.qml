import QtQuick
import qs.Commons

Item {
  id: root

  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family
  property bool animate: true
  property bool active: true
  property bool autoAnimate: true
  property bool loading: false
  property real cellWidth: Style.space(21)
  property real cellHeight: Style.space(25)
  property real cellSpacing: Style.space(3)
  property real glyphSize: Style.font.body
  property string destinationWord: "PYIN"
  property int nextLetter: 0
  property bool flipping: false
  property bool showingNews: false
  readonly property bool hovered: hitArea.containsMouse

  signal clicked()

  implicitWidth: flapRow.implicitWidth
  implicitHeight: flapRow.implicitHeight

  function forceWord(word) {
    var value = String(word || "PYIN").slice(0, 4)
    for (var i = 0; i < 4; i++) {
      var cell = flapRepeater.itemAt(i)
      if (cell) cell.setGlyph(value.charAt(i))
    }
    showingNews = value === "NEWS"
    destinationWord = value
    flipping = false
  }

  function schedule(initial) {
    idleTimer.stop()
    if (!root.active || !root.animate || !root.autoAnimate
        || root.loading || root.flipping) return
    idleTimer.interval = initial ? 9000 : 50000 + Math.floor(Math.random() * 40000)
    idleTimer.restart()
  }

  function flipTo(word) {
    if (!root.active || root.flipping) return
    root.destinationWord = String(word || "PYIN").slice(0, 4)
    root.nextLetter = 0
    root.flipping = true
    root.flipNext()
  }

  function flipNext() {
    var cell = flapRepeater.itemAt(root.nextLetter)
    if (cell) cell.flipTo(root.destinationWord.charAt(root.nextLetter))
    root.nextLetter++
    if (root.nextLetter < 4) cascadeTimer.restart()
    else settleTimer.restart()
  }

  function replay() {
    if (!root.active) return
    idleTimer.stop()
    returnTimer.stop()
    if (!root.animate) {
      root.forceWord("PYIN")
      return
    }
    if (!root.flipping) root.flipTo(root.showingNews ? "PYIN" : "NEWS")
  }

  onActiveChanged: {
    if (!active) {
      idleTimer.stop()
      returnTimer.stop()
      loadingLeadTimer.stop()
      loadingHoldTimer.stop()
      cascadeTimer.stop()
      settleTimer.stop()
      forceWord("PYIN")
    } else if (loading && animate) {
      forceWord("PYIN")
      loadingLeadTimer.restart()
    } else {
      forceWord("PYIN")
      schedule(true)
    }
  }

  onAutoAnimateChanged: {
    if (autoAnimate && !loading) schedule(false)
    else idleTimer.stop()
  }

  onAnimateChanged: {
    if (!animate) {
      idleTimer.stop()
      returnTimer.stop()
      loadingLeadTimer.stop()
      loadingHoldTimer.stop()
      forceWord("PYIN")
    } else if (active && loading) {
      forceWord("PYIN")
      loadingLeadTimer.restart()
    } else if (active) {
      schedule(true)
    }
  }

  onLoadingChanged: {
    idleTimer.stop()
    returnTimer.stop()
    loadingLeadTimer.stop()
    loadingHoldTimer.stop()
    cascadeTimer.stop()
    settleTimer.stop()
    forceWord("PYIN")
    if (loading && active && animate) loadingLeadTimer.restart()
    else if (active) schedule(false)
  }

  Component.onCompleted: {
    forceWord("PYIN")
    if (loading && active && animate) loadingLeadTimer.restart()
    else schedule(true)
  }

  Timer {
    id: idleTimer
    repeat: false
    onTriggered: root.flipTo("NEWS")
  }

  Timer {
    id: cascadeTimer
    interval: 82
    repeat: false
    onTriggered: root.flipNext()
  }

  Timer {
    id: settleTimer
    interval: 360
    repeat: false
    onTriggered: {
      root.showingNews = root.destinationWord === "NEWS"
      root.flipping = false
      if (root.loading) loadingHoldTimer.restart()
      else if (root.showingNews) returnTimer.restart()
      else root.schedule(false)
    }
  }

  Timer {
    id: loadingLeadTimer
    interval: 140
    repeat: false
    onTriggered: root.flipTo("NEWS")
  }

  Timer {
    id: loadingHoldTimer
    interval: 320
    repeat: false
    onTriggered: root.flipTo(root.showingNews ? "PYIN" : "NEWS")
  }

  Timer {
    id: returnTimer
    interval: 1650
    repeat: false
    onTriggered: root.flipTo("PYIN")
  }

  Row {
    id: flapRow
    spacing: root.cellSpacing

    Repeater {
      id: flapRepeater
      model: 4

      delegate: Item {
        id: cell
        required property int index
        property string glyph: "PYIN".charAt(index)
        property string pendingGlyph: glyph

        width: root.cellWidth
        height: root.cellHeight

        function setGlyph(value) {
          flipAnimation.stop()
          glyph = String(value || " ")
          pendingGlyph = glyph
          flipScale.yScale = 1
        }

        function flipTo(value) {
          pendingGlyph = String(value || " ")
          flipAnimation.restart()
        }

        Rectangle {
          anchors.fill: parent
          radius: Math.max(1, Style.cornerRadius / 2)
          color: root.background
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: root.hovered ? root.accent : root.dim
          opacity: root.hovered ? 1 : 0.88

          Behavior on border.color { ColorAnimation { duration: 120 } }
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Item {
          id: face
          anchors.fill: parent
          transform: Scale {
            id: flipScale
            origin.x: face.width / 2
            origin.y: face.height / 2
            yScale: 1
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height / 2
            radius: Math.max(1, Style.cornerRadius / 2)
            color: root.accent
            opacity: 0.07
          }

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: cell.glyph
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: root.glyphSize
            font.bold: true
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(1, Style.normalBorderWidth)
            color: root.background
            opacity: 0.9
          }
        }

        SequentialAnimation {
          id: flipAnimation

          NumberAnimation {
            target: flipScale
            property: "yScale"
            from: 1
            to: 0.035
            duration: 92
            easing.type: Easing.InQuad
          }
          ScriptAction { script: cell.glyph = cell.pendingGlyph }
          NumberAnimation {
            target: flipScale
            property: "yScale"
            from: 0.035
            to: 1
            duration: 142
            easing.type: Easing.OutBack
          }
        }
      }
    }
  }

  MouseArea {
    id: hitArea
    anchors.fill: parent
    anchors.margins: -Style.spacing.xs
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
