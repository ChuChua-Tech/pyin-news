import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Column {
  id: probe
  spacing: Style.spacing.sm
  property string backendPath: ""
  property string feedUrl: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family
  property var result: ({})
  property int revision: 0
  property int requestRevision: -1
  property bool responseReceived: false
  readonly property bool checking: checkProc.running
  readonly property string previewText: {
    if (checking) return "Checking feed…"
    if (result.error) return String(result.error)
    if (!result.ok) return ""
    var title = result.title ? " · " + String(result.title) : ""
    return result.latest && result.latest.title
      ? "Feed found" + title + "\nLatest: " + String(result.latest.title)
      : "Valid feed" + title + " · no stories available yet."
  }

  function invalidate() {
    revision++
    result = ({})
    // Let the bounded check finish before reusing its Process. Editing the URL
    // or leaving this page invalidates the reply, including change-away/back.
  }
  function checkFeed() {
    if (checking || backendPath === "" || feedUrl.trim() === "") return
    revision++
    requestRevision = revision
    responseReceived = false
    result = ({})
    checkProc.command = [backendPath, "sources", "--test", feedUrl.trim()]
    checkProc.running = true
  }
  onFeedUrlChanged: invalidate()
  onVisibleChanged: if (!visible) invalidate()

  Button {
    text: probe.checking ? "Checking…" : "Test feed"
    tooltipText: "Check this URL and preview a headline without saving it"
    enabled: !probe.checking && probe.backendPath !== "" && probe.feedUrl.trim() !== ""
    focusable: true
    foreground: probe.foreground
    accent: probe.accent
    fontFamily: probe.fontFamily
    onClicked: probe.checkFeed()
  }
  Text {
    width: parent.width
    visible: text !== ""
    text: probe.previewText
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: probe.dim
    font.family: probe.fontFamily
    font.pixelSize: Style.font.caption
  }
  Process {
    id: checkProc
    stdout: StdioCollector { id: checkOutput; waitForEnd: true }
    onRunningChanged: {
      if (!running) {
        var finishedRevision = probe.requestRevision
        Qt.callLater(function() {
          if (!checkProc.running && finishedRevision === probe.revision
              && finishedRevision === probe.requestRevision && !probe.responseReceived
              && !probe.result.ok && !probe.result.error)
            probe.result = {ok: false, error: "Could not start the feed check. Please retry."}
        })
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (probe.requestRevision !== probe.revision) return
      probe.responseReceived = true
      var payload = ({})
      try { payload = JSON.parse(checkOutput.text) } catch (error) {}
      if (!payload || typeof payload !== "object") payload = ({})
      if (exitCode !== 0 || Boolean(exitStatus) || !payload.ok)
        payload = {ok: false, error: String(payload.error || "Could not check this feed. Check the URL and connection, then retry.")}
      probe.result = payload
    }
  }
}
