import "Reading.js" as Reading
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: page

  property var coverage: ({})
  property bool busy: false
  property string visitError: ""
  property bool compact: false
  property bool separators: true
  property int selectedIndex: -1
  property var articles: []
  property string displayedEventId: ""
  property int modelRevision: 0
  property bool restorePending: false
  property real restorePosition: 0

  onCoverageChanged: {
    var sameEvent = articles.length > 0 && displayedEventId === String(coverage.event_id || "")
    var position = restorePending ? restorePosition : timeline.contentY
    var selectedId = selectedIndex >= 0 && selectedIndex < articles.length
      ? String(articles[selectedIndex].id) : ""
    displayedEventId = String(coverage.event_id || "")
    articles = coverage.articles || []
    modelRevision++
    var revision = modelRevision
    restorePending = sameEvent && articles.length > 0
    restorePosition = position
    if (!restorePending) { resetPosition(); return }
    var selected = articles.findIndex(function(article) { return String(article.id) === selectedId })
    selectedIndex = selected >= 0 ? selected : Math.min(selectedIndex, articles.length - 1)
    // Replacing a JS-array model resets ListView's content position. Wait for
    // its delegates to settle before restoring the reader's place, including
    // metadata acknowledgements arriving while a synopsis covers this page.
    Qt.callLater(function() {
      if (revision !== page.modelRevision) return
      timeline.forceLayout()
      timeline.contentY = page.restorePosition
      timeline.returnToBounds()
      page.restorePending = false
    })
  }

  signal articleRequested(var article)
  signal retryRequested()

  function resetPosition() {
    selectedIndex = -1
    timeline.positionViewAtBeginning()
  }

  function moveCursor(delta) {
    if (articles.length === 0) return
    selectedIndex = Math.max(0, Math.min(articles.length - 1, selectedIndex + delta))
    timeline.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function openSelected() {
    if (articles.length > 0) articleRequested(articles[Math.max(0, selectedIndex)])
  }

  function publicationTime(timestamp) {
    return Qt.formatDateTime(new Date(Number(timestamp) * 1000), "ddd, MMM d · h:mm AP")
  }

  ListView {
    id: timeline
    anchors.fill: parent
    clip: true
    model: page.articles
    spacing: page.compact ? Style.spacing.sm : Style.spacing.lg
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true

    header: Column {
      width: timeline.width
      spacing: Style.spacing.lg

      Text {
        text: "COVERAGE"
        textFormat: Text.PlainText
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.4
        font.bold: true
      }

      Text {
        width: parent.width
        text: page.busy ? "Gathering cached coverage…"
          : (page.coverage.ok === false ? "Coverage unavailable"
            : String(page.coverage.title || "Event coverage"))
        textFormat: Text.PlainText
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        visible: page.coverage.ok === true && !page.busy
        text: String(page.coverage.article_count || 0) + " reports  ·  "
          + String(page.coverage.source_count || 0) + " publishers"
          + (Number(page.coverage.new_count || 0) > 0
            ? "  ·  " + String(page.coverage.new_count) + " new" : "")
        textFormat: Text.PlainText
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        text: page.coverage.ok === false ? String(page.coverage.error || "Try opening the event again.")
          : (page.busy ? "Reading your local news cache."
            : (page.articles.length === 0
              ? "No coverage matches your current sources and filters."
              : (page.coverage.first_visit
                ? "First visit. Coverage arriving after this visit will be marked new."
                : (Number(page.coverage.new_count || 0) > 0
                  ? "New marks reporting added since your previous visit."
                  : "You're up to date with the cached coverage."))))
        textFormat: Text.PlainText
        color: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        visible: page.visitError !== ""
        text: page.visitError
        textFormat: Text.PlainText
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Button {
        visible: page.coverage.ok === false
        text: "Try again"
        enabled: !page.busy
        focusable: true
        bordered: true
        onClicked: page.retryRequested()
      }

      Text {
        width: parent.width
        visible: page.coverage.ok === true && page.articles.length > 0
        text: "EARLIEST → LATEST  ·  TIMES SHOWN IN YOUR TIME ZONE"
        textFormat: Text.PlainText
        color: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Item { width: 1; height: Style.spacing.sm }
    }

    delegate: BorderSurface {
      id: report
      required property var modelData
      required property int index
      readonly property bool selected: page.selectedIndex === index || activeFocus
      width: timeline.width
      height: reportText.implicitHeight + (page.compact ? Style.spacing.md : Style.spacing.lg) * 2
      color: Style.controlFill(selected, reportMouse.containsMouse, Color.foreground, Color.accent)
      borderSpec: selected ? Border.controlSpec("focus", Color.foreground, Color.accent) : Border.none()
      radius: Style.cornerRadius
      activeFocusOnTab: true
      onActiveFocusChanged: {
        if (activeFocus) {
          page.selectedIndex = index
          timeline.positionViewAtIndex(index, ListView.Contain)
        }
      }
      Keys.onReturnPressed: page.articleRequested(modelData)
      Keys.onEnterPressed: page.articleRequested(modelData)
      Keys.onSpacePressed: page.articleRequested(modelData)

      Column {
        id: reportText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.topMargin: page.compact ? Style.spacing.md : Style.spacing.lg
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          text: (modelData.is_new ? "NEW  ·  " : "") + String(modelData.source)
            + (modelData.read ? "  ·  Read" : "")
          textFormat: Text.PlainText
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: Boolean(modelData.is_new)
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          text: page.publicationTime(modelData.published_ts)
          textFormat: Text.PlainText
          color: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          text: String(modelData.title)
          textFormat: Text.PlainText
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          visible: !page.compact && String(modelData.summary || "") !== ""
          text: String(modelData.summary || "")
          textFormat: Text.PlainText
          color: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }

      Rectangle {
        anchors.left: reportText.left
        anchors.right: reportText.right
        anchors.bottom: parent.bottom
        height: Style.spacing.hairline
        visible: page.separators && report.index < page.articles.length - 1
        color: Color.foreground
        opacity: 0.16
      }

      MouseArea {
        id: reportMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          page.selectedIndex = report.index
          page.articleRequested(report.modelData)
        }
      }
    }

    footer: Text {
      width: timeline.width
      topPadding: Style.spacing.lg
      bottomPadding: Style.spacing.lg
      visible: page.coverage.ok === true
      text: "Matched locally by headline and publication date; matches can be imperfect. "
        + "Coverage follows your sources and filters. Read reports remain for context; dismissed reports stay hidden. "
        + "This visit doesn't mark articles read."
      textFormat: Text.PlainText
      color: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
  }
}
