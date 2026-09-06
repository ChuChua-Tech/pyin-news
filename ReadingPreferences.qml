import QtQuick
import qs.Commons
import qs.Ui
import "Reading.js" as Reading

Column {
  id: page
  objectName: "pyinReadingPreferences"
  property string readingSize: "regular"
  property string previewSize: readingSize
  property bool staged: false
  property bool busy: false
  property string message: ""
  signal sizeRequested(string size)
  onReadingSizeChanged: previewSize = readingSize
  spacing: Style.spacing.md

  Text {
    width: parent.width
    text: "READING TEXT SIZE"
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }
  Flow {
    width: parent.width
    spacing: Style.spacing.sm
    Repeater {
      model: [{value:"regular",label:"Regular"},{value:"large",label:"Large"},{value:"extra-large",label:"Extra large"}]
      Button {
        required property var modelData
        text: modelData.label
        selected: page.previewSize === modelData.value
        foreground: Color.foreground
        accent: Color.accent
        fontFamily: Style.font.family
        fontSize: Style.font.caption
        bordered: true
        focusable: true
        enabled: !page.busy
        onClicked: {
          page.previewSize = modelData.value
          if (page.staged) page.sizeRequested(modelData.value)
        }
      }
    }
  }
  BorderSurface {
    width: parent.width
    implicitHeight: preview.implicitHeight + Style.spacing.lg * 2
    color: Color.background
    borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
    radius: Style.cornerRadius
    Text {
      id: preview
      objectName: "pyinReadingSizePreview"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.lg
      text: "A little room to read.\n\nFollow the story at a size that feels comfortable."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.body * Reading.sizeScale(page.previewSize))
      lineHeight: 1.5
    }
  }
  Text {
    width: parent.width
    text: "Changes article text, independently of Calm, Compact or Classic. Controls keep their size."
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Button {
    visible: !page.staged && (page.previewSize !== page.readingSize || page.busy)
    text: page.busy ? "Saving…" : "Apply text size"
    foreground: Color.foreground
    accent: Color.accent
    fontFamily: Style.font.family
    bordered: true
    focusable: true
    enabled: !page.busy
    onClicked: page.sizeRequested(page.previewSize)
  }
  Text {
    width: parent.width
    visible: !page.staged && page.message !== ""
    text: page.message
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
