import QtQuick

// One small, static tile. The image is rerasterized only when its ink changes;
// resizing the surface repeats the same texture instead of painting a new one.
Item {
  id: paper

  required property color ink

  readonly property string grainPath: {
    var seed = 571
    var path = ""
    for (var i = 0; i < 420; i++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
      var x = (seed >>> 16) % 128
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
      var y = (seed >>> 16) % 128
      // Occasional short fibers soften the otherwise fine, irregular grain.
      var width = i % 7 === 0 ? 2 : 1
      path += "M" + x + " " + y + "h" + width + "v1h-" + width + "z"
    }
    return path
  }

  Image {
    anchors.fill: parent
    source: "data:image/svg+xml," + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">'
      + '<path fill="rgb(' + Math.round(paper.ink.r * 255) + ','
      + Math.round(paper.ink.g * 255) + ',' + Math.round(paper.ink.b * 255)
      + ')" d="' + paper.grainPath + '"/></svg>')
    sourceSize: Qt.size(128, 128)
    fillMode: Image.Tile
    horizontalAlignment: Image.AlignLeft
    verticalAlignment: Image.AlignTop
    opacity: 0.035 * paper.ink.a
    smooth: false
  }
}
