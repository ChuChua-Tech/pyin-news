import QtQuick
import Quickshell.Io

// One request at a time for visible story rows. The backend enforces the saved
// opt-in and disk bounds; QML only receives local file URLs, never remote URLs.
Item {
  id: cache
  property string backendPath: ""
  property bool active: false
  property var paths: ({})
  property var clients: []
  property string fetching: ""
  property int revision: 0

  function registerClient(client) {
    clients = clients.concat([client])
    schedule()
  }
  function unregisterClient(client) {
    clients = clients.filter(function(value) { return value !== client })
  }
  function schedule() {
    if (active) pending.restart()
  }
  function pump() {
    if (!active || fetching !== "" || downloader.running) return
    for (var i = 0; i < clients.length; i++) {
      var client = clients[i]
      if (!client || !client.wantsImage) continue
      var id = String(client.articleId)
      if (Object.prototype.hasOwnProperty.call(paths, id)) continue
      fetching = id
      revision++
      downloader.command = [backendPath, "article-images", "--ids-json", JSON.stringify([id])]
      downloader.running = true
      deadline.restart()
      checkLaunch()
      return
    }
  }
  function checkLaunch() {
    var current = revision
    Qt.callLater(function() {
      if (current === cache.revision && cache.fetching !== "" && !downloader.running)
        cache.finish("")
    })
  }
  function finish(path) {
    deadline.stop()
    var id = fetching
    fetching = ""
    revision++
    if (active && id !== "") {
      var next = Object.assign({}, paths)
      if (Object.keys(next).length >= 256) next = ({})
      next[id] = String(path || "").indexOf("file://") === 0 ? String(path) : ""
      paths = next
    }
    schedule()
  }
  onActiveChanged: {
    revision++
    fetching = ""
    downloader.running = false
    deadline.stop()
    pending.stop()
    if (active) { paths = ({}); schedule() }
  }
  Timer { id: pending; interval: 60; onTriggered: cache.pump() }
  Timer {
    id: deadline
    interval: 12000
    onTriggered: { downloader.running = false; cache.finish("") }
  }
  Process {
    id: downloader
    stdout: StdioCollector { id: output; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) cache.checkLaunch()
    onExited: function(code, status) {
      var path = ""
      if (code === 0 && !Boolean(status)) {
        try {
          var payload = JSON.parse(output.text)
          if (payload.ok && payload.images) path = payload.images[cache.fetching] || ""
        } catch (error) {}
      }
      cache.finish(path)
    }
  }
}
