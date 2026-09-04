import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family
  property string feedbackCategory: "Idea"
  property string feedbackMessage: ""
  property string feedbackStatus: ""

  signal openWebsiteRequested()
  signal openStoryRequested()
  signal openLanguageRequested()
  signal feedbackRequested(string category, string message)
  signal keyboardRequested()

  function reset() {
    aboutScroll.contentY = 0
  }

  function scrollBy(delta) {
    aboutScroll.contentY = Math.max(0,
      Math.min(Math.max(0, aboutScroll.contentHeight - aboutScroll.height),
        aboutScroll.contentY + delta * Style.space(70)))
  }

  function submitFeedback() {
    var message = root.feedbackMessage.trim()
    if (message.length < 5) {
      root.feedbackStatus = "Write a little more before opening the email draft."
      return
    }
    root.feedbackStatus = "Preparing a private email draft…"
    root.feedbackRequested(root.feedbackCategory, message)
  }

  function feedbackDraftOpened(opened) {
    root.feedbackStatus = opened
      ? "Draft opened in your email app. Review it there, then press Send."
      : "No email app accepted the draft. Write to pyin-news-feedback@chuchua.tech."
  }

  component AboutSection: Column {
    property string heading: ""
    property string copy: ""
    width: parent ? parent.width : 0
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: parent.heading
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.1
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: parent.copy
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      lineHeight: 1.3
      wrapMode: Text.Wrap
    }
  }

  Flickable {
    id: aboutScroll
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: aboutColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: aboutColumn
      width: aboutScroll.width
      spacing: Style.spacing.panelGap

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "PYIN / NEWS / CHUCHUA.TECH"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.4
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "News for now.\nOn your terms."
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
        lineHeight: 0.98
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Get the news. Keep your time."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.italic: true
        wrapMode: Text.Wrap
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.normalBorderWidth)
        color: root.accent
        opacity: 0.42
      }

      AboutSection {
        heading: "WHY PYIN"
        copy: "pyin means “now” in Secwepemctsín. We chose it because news should help you understand what matters now—without trapping you in an endless social timeline. The name also roots the project in the language and community where chuchua.tech was created."
      }

      AboutSection {
        heading: "WHY WE CREATED IT"
        copy: "Every social platform is built to turn one headline into another hour: bot-filled replies, rage bait, trash posting, arguments, popularity contests, and an opaque global platform deciding what deserves attention. PYIN is just the news. Choose the sources and subjects that matter, reach the end, and get on with your day."
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "THE PROMISE"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.1
        }

        Repeater {
          model: [
            "NO SOCIAL FEED  //  reporting instead of replies and popularity contests",
            "FINITE BY DESIGN  //  reach the end, close the app, and keep your time",
            "VISIBLE CURATION  //  inspect and change the profile shaping your feed",
            "LOCAL BY DEFAULT  //  reading signals and preferences remain on this device",
            "AI ONLY ON REQUEST  //  source-bounded summaries, never automatic rewriting",
            "NO FALSE NEUTRALITY  //  publishers stay visible and you control the mix"
          ]

          delegate: Text {
            required property string modelData
            width: aboutColumn.width
            textFormat: Text.PlainText
            text: "› " + modelData
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.25
            wrapMode: Text.Wrap
          }
        }
      }

      AboutSection {
        heading: "WHO CHUCHUA.TECH ARE"
        copy: "chuchua.tech is a 100% Indigenous-owned partnership based in Chuchua, British Columbia, and proud members of the Simpcw band. We build technology and digital experiences with purpose: strengthening communities, supporting data sovereignty, and making powerful tools genuinely useful to people."
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "PYIN does not sell attention, require a PYIN account, or hide how its feed works. Optional AI uses the provider you choose; the local curation profile remains inspectable from Profile."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        lineHeight: 1.25
        wrapMode: Text.Wrap
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.md

        Button {
          text: "Visit chuchua.tech"
          iconText: "󰖟"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openWebsiteRequested()
        }

        Button {
          text: "Our founding story"
          iconText: "󰈙"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openStoryRequested()
        }

        Button {
          text: "Language reference"
          iconText: "󰗊"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openLanguageRequested()
        }
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.normalBorderWidth)
        color: root.accent
        opacity: 0.32
      }

      Column {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "SEND FEEDBACK"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.1
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Ideas, rough edges, and source suggestions are welcome. PYIN opens a pre-addressed draft in your email app so nothing is sent until you review it."
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.25
          wrapMode: Text.Wrap
        }

        Row {
          id: feedbackCategoryRow
          width: parent.width
          spacing: Style.spacing.sm
          property real buttonWidth: (width - spacing * 2) / 3

          Repeater {
            model: ["Idea", "Problem", "Source"]

            delegate: Button {
              required property string modelData
              width: feedbackCategoryRow.buttonWidth
              text: modelData
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              selected: root.feedbackCategory === modelData
              onClicked: {
                root.feedbackCategory = modelData
                root.feedbackStatus = ""
              }
            }
          }
        }

        BorderSurface {
          width: parent.width
          height: Style.space(132)
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: Border.controlSpec(feedbackEditor.activeFocus
            ? "focus" : "normal", root.foreground, root.accent)

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.spacing.lg
            visible: feedbackEditor.text.length === 0 && !feedbackEditor.activeFocus
            textFormat: Text.PlainText
            text: "Tell us what would make PYIN better…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Flickable {
            id: feedbackEditorScroll
            anchors.fill: parent
            anchors.margins: Style.spacing.lg
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, feedbackEditor.implicitHeight)

            TextEdit {
              id: feedbackEditor
              width: feedbackEditorScroll.width
              text: root.feedbackMessage
              textFormat: TextEdit.PlainText
              color: root.foreground
              selectionColor: root.accent
              selectedTextColor: root.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              onTextChanged: {
                if (text.length > 4000) {
                  var position = cursorPosition
                  text = text.slice(0, 4000)
                  cursorPosition = Math.min(position, 4000)
                  return
                }
                root.feedbackMessage = text
                if (root.feedbackStatus !== "") root.feedbackStatus = ""
              }

              Keys.onPressed: function(event) {
                if ((event.modifiers & Qt.ControlModifier)
                    && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.submitFeedback()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.keyboardRequested()
                  event.accepted = true
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignRight
          text: String(root.feedbackMessage.length) + "/4000  ·  Ctrl+Enter opens draft"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.spacing.md

          Button {
            text: "Open email draft"
            iconText: "󰇮"
            tooltipText: "Addressed to pyin-news-feedback@chuchua.tech · Ctrl+Enter"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            selected: root.feedbackMessage.trim().length >= 5
            enabled: root.feedbackMessage.trim().length >= 5
            onClicked: root.submitFeedback()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "pyin-news-feedback@chuchua.tech"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: root.feedbackStatus !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.feedbackStatus
          color: root.feedbackStatus.indexOf("No email") === 0
            ? root.foreground : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "BUILT IN CHUCHUA, BC  //  FOR OMARCHY  //  2026"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 0.6
        wrapMode: Text.Wrap
      }

      Item { width: 1; height: Style.spacing.md }
    }
  }
}
