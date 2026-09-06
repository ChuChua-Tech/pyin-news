import QtQuick
import qs.Commons

Item {
  id: thumb
  property var imageCache: null
  property string articleId: ""
  property string imageHint: ""
  property bool inViewport: false
  property bool compact: false
  property bool reading: false
  property bool decodeFailed: false
  onArticleIdChanged: decodeFailed = false
  onLocalPathChanged: decodeFailed = false
  property real availableWidth: 0
  readonly property bool imageReady: picture.status === Image.Ready && picture.source.toString() !== ""
  readonly property bool wantsImage: imageCache && imageCache.active
    && inViewport && articleId !== "" && imageHint !== ""
  readonly property var localPath: imageCache ? imageCache.paths[articleId] : undefined
  readonly property bool reserved: imageCache && imageCache.active && imageHint !== ""
    && localPath !== "" && !decodeFailed
  width: reserved ? (reading ? Math.min(availableWidth, Style.space(480))
    : Style.space(compact ? 64 : 88)) : 0
  height: reserved ? (reading ? Math.min(width * 9 / 16, Style.space(compact ? 180 : 240))
    : Style.space(compact ? 48 : 66)) : 0
  visible: reserved
  clip: true
  onWantsImageChanged: if (imageCache) imageCache.schedule()
  Component.onCompleted: if (imageCache) imageCache.registerClient(thumb)
  Component.onDestruction: if (imageCache) imageCache.unregisterClient(thumb)

  Rectangle {
    anchors.fill: parent
    color: thumb.reading ? Qt.alpha(Color.foreground, 0.025) : "transparent"
  }
  Image {
    id: picture
    anchors.fill: parent
    source: thumb.wantsImage && thumb.localPath ? thumb.localPath : ""
    asynchronous: true
    cache: false
    sourceSize: thumb.reading ? Qt.size(960, 640) : Qt.size(176, 132)
    fillMode: thumb.reading ? Image.PreserveAspectFit : Image.PreserveAspectCrop
    smooth: true
    onStatusChanged: if (status === Image.Error) thumb.decodeFailed = true
  }
  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: Style.spacing.hairline
    border.color: Qt.alpha(Color.foreground, 0.12)
  }
}
