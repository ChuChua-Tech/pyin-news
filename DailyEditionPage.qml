import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: page
  property var edition: null
  property bool busy: false
  property string errorText: ""
  property bool compact: false
  property bool separators: true
  property int minutes: 15
  property bool choosing: false
  property int selectedIndex: 0
  readonly property var articles: edition ? edition.articles || [] : []
  readonly property bool finished: edition !== null && Number(edition.remaining) === 0
  readonly property bool showChoices: !edition || (finished && choosing)
  signal startRequested(int minutes)
  signal articleRequested(var article)
  signal retryRequested()

  onEditionChanged: {
    choosing = false
    if (edition && [5, 15, 30].indexOf(Number(edition.minutes)) !== -1)
      minutes = Number(edition.minutes)
    // Derived array bindings settle after the edition property notification.
    Qt.callLater(function() {
      var cursor = page.edition ? String(page.edition.cursor_id || "") : ""
      var found = page.articles.findIndex(function(a) { return String(a.id) === cursor })
      var next = page.articles.findIndex(function(a) { return a.edition_status === "pending" })
      page.selectedIndex = found >= 0 ? found : Math.max(0, next)
      stories.positionViewAtBeginning()
    })
  }

  function moveCursor(delta) {
    if (articles.length === 0) return
    selectedIndex = Math.max(0, Math.min(articles.length - 1, selectedIndex + delta))
    stories.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function openSelected() {
    if (!busy && articles.length > 0) articleRequested(articles[selectedIndex])
  }

  function resume() {
    var cursor = edition ? String(edition.cursor_id || "") : ""
    var article = articles.find(function(a) { return String(a.id) === cursor && a.edition_status === "pending" })
      || articles.find(function(a) { return a.edition_status === "pending" })
    if (article && !busy) articleRequested(article)
  }

  ListView {
    id: stories
    anchors.fill: parent
    clip: true
    model: page.articles
    spacing: page.compact ? Style.spacing.sm : Style.spacing.lg
    boundsBehavior: Flickable.StopAtBounds
    header: Column {
      width: stories.width
      spacing: Style.spacing.lg
      Text {
        text: "DAILY EDITIONS"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.4
        font.bold: true
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: page.finished ? (page.articles.length ? "You’ve finished your edition." : "A quiet moment. You’re caught up.")
          : (page.edition ? "A little news. A clear finish." : "How much time do you have?")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.Wrap
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: page.finished ? "You can leave it here. New reporting will wait in your feed."
          : (page.edition ? "These stories stay fixed as feeds refresh. Done or Skip moves you forward; Back keeps your place."
            : "A fixed selection, saved progress, and an ending. Reading times estimate the synopses; original articles take longer.")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }
      Column {
        visible: page.edition !== null
        width: parent.width
        spacing: Style.spacing.sm
        Text {
          width: parent.width
          text: page.edition ? String(page.edition.completed) + " of " + String(page.edition.total)
            + " stories complete · " + String(page.edition.minutes) + " min edition"
            + (page.edition.created_ts ? " · " + Qt.formatDateTime(new Date(page.edition.created_ts * 1000), "MMM d") : "") : ""
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
        Rectangle {
          width: parent.width
          height: Style.space(3)
          radius: height / 2
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
          Rectangle {
            width: parent.width * (page.finished ? 1 : (page.edition && page.edition.total ? page.edition.completed / page.edition.total : 0))
            height: parent.height
            radius: parent.radius
            color: Color.accent
          }
        }
      }
      Button {
        visible: page.edition !== null && !page.finished
        text: page.edition && page.edition.completed ? "Resume edition" : "Start reading"
        tooltipText: "Return to your next unfinished story"
        foreground: Color.foreground
        accent: Color.accent
        fontFamily: Style.font.family
        bordered: true
        focusable: true
        enabled: !page.busy
        onClicked: page.resume()
      }
      Button {
        visible: page.finished && !page.choosing
        text: "Make another edition"
        foreground: Color.muted
        accent: Color.accent
        fontFamily: Style.font.family
        focusable: true
        enabled: !page.busy
        onClicked: page.choosing = true
      }
      Column {
        visible: page.showChoices
        width: parent.width
        spacing: Style.spacing.md
        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          Repeater {
            model: [5, 15, 30]
            Button {
              required property int modelData
              text: String(modelData) + " min"
              selected: page.minutes === modelData
              foreground: Color.foreground
              accent: Color.accent
              fontFamily: Style.font.family
              bordered: true
              focusable: true
              enabled: !page.busy
              onClicked: page.minutes = modelData
            }
          }
        }
        Button {
          text: page.busy ? "Preparing…" : "Make my edition"
          foreground: Color.foreground
          accent: Color.accent
          fontFamily: Style.font.family
          bordered: true
          focusable: true
          enabled: !page.busy
          onClicked: page.startRequested(page.minutes)
        }
        Text {
          width: parent.width
          text: "Quiet days can be shorter. Nothing refills this edition."
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
      Text {
        visible: page.errorText !== ""
        width: parent.width
        text: page.errorText
        textFormat: Text.PlainText
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }
      Button {
        visible: page.errorText !== ""
        text: "Retry"
        foreground: Color.foreground
        accent: Color.accent
        fontFamily: Style.font.family
        focusable: true
        enabled: !page.busy
        onClicked: page.retryRequested()
      }
      Item { width: 1; height: Style.spacing.sm }
    }
    delegate: Item {
      id: card
      required property var modelData
      required property int index
      width: stories.width
      height: copy.implicitHeight + Style.spacing.lg * 2
      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, page.selectedIndex === card.index ? 0.08 : 0)
      }
      Column {
        id: copy
        x: Style.spacing.md
        y: Style.spacing.md
        width: Math.max(0, parent.width - x * 2)
        spacing: Style.spacing.sm
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(card.index + 1).padStart(2, "0") + "  ·  " + String(card.modelData.section)
            + (card.modelData.edition_status === "pending" ? "" : (card.modelData.edition_status === "skipped" ? "  ·  Skipped" : "  ·  Done"))
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: card.modelData.title
          color: Color.foreground
          opacity: card.modelData.edition_status === "pending" ? 1 : 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.Wrap
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: card.modelData.source + " · " + Math.ceil(card.modelData.reading_seconds / 60) + " min"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.max(1, Style.spacing.hairline)
        color: Color.accent
        opacity: 0.14
        visible: page.separators && card.index < page.articles.length - 1
      }
      MouseArea {
        anchors.fill: parent
        enabled: !page.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.selectedIndex = card.index; page.openSelected() }
      }
    }
  }
}
