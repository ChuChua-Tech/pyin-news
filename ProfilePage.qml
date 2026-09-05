import QtQuick
import qs.Commons
import qs.Ui

Flickable {
  id: page

  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: Color.muted
  property string fontFamily: Style.font.family

  property var navigationItems: ["bookmarks", "history", "alerts", "refresh"]
  property int alertCount: 0
  property int bookmarkCount: 0
  property int historyCount: 0
  property int readCount: 0
  property string topicSummary: "No explicit topic selections."
  property string setupSummaryText: ""
  property string setupDetailsText: ""
  property string sourceMixText: ""
  property string aiProvider: "system"
  property string aiSummary: ""
  property string systemAiPreset: "balanced"
  property var systemAiOptions: []
  property bool articleBackMarksRead: true
  property string footerLinkLabel: ""
  property string footerLinkUrl: ""
  property string footerLinkDraftLabel: ""
  property string footerLinkDraftUrl: ""
  property string footerLinkMessage: ""
  property var interestNodes: []
  property var learnedTerms: []
  property var recentDismissals: []
  property var counts: ({})
  property var storage: ({})
  property var exposure: ({})
  property var updateData: ({})
  property string showLessTermText: "None"
  property string showLessSourceText: "None"
  property bool profileBusy: false
  property bool navigationBusy: false
  property bool behaviorBusy: false
  property bool footerLinkBusy: false
  property bool aiPresetBusy: false
  property bool interestBusy: false
  property bool transferBusy: false
  property bool resetBusy: false
  property bool updateBusy: false
  property bool updateLaunching: false
  property bool confirmReset: false
  property bool confirmUpdate: false

  property bool customizeExpanded: false
  property bool choicesExpanded: false
  property bool learningExpanded: false
  property bool dataExpanded: false
  property bool updatesExpanded: false
  property bool setupDetailsExpanded: false
  property bool showLessExpanded: false

  signal destinationRequested(string destination)
  signal setupPageRequested(int page)
  signal setupRequested()
  signal navigationRequested(string item, bool enabled)
  signal backBehaviorRequested(bool enabled)
  signal footerLinkRequested(string label, string url)
  signal aiPresetRequested(string preset)
  signal interestRemoveRequested(string term, string scope)
  signal exportRequested()
  signal importRequested()
  signal resetRequested()
  signal updateCheckRequested()
  signal updateInstallRequested()

  function menuItemEnabled(item) {
    return page.navigationItems.indexOf(String(item)) !== -1
  }

  function resetSections() {
    page.customizeExpanded = false
    page.choicesExpanded = false
    page.learningExpanded = false
    page.dataExpanded = false
    page.updatesExpanded = false
    page.setupDetailsExpanded = false
    page.showLessExpanded = false
    page.confirmUpdate = false
    page.syncFooterLinkDraft()
    page.footerLinkMessage = ""
    page.contentY = 0
  }

  function syncFooterLinkDraft() {
    page.footerLinkDraftLabel = page.footerLinkLabel
    page.footerLinkDraftUrl = page.footerLinkUrl
  }

  function saveFooterLink() {
    var label = page.footerLinkDraftLabel.trim().replace(/\s+/g, " ")
    var url = page.footerLinkDraftUrl.trim()
    if (label === "" && url === "") {
      page.footerLinkRequested("", "")
      return
    }
    if (label === "") {
      page.footerLinkMessage = "Enter a short label for the footer link."
      return
    }
    if (!/^https?:\/\/[^\s/]+(?:\/[^\s]*)?$/i.test(url)) {
      page.footerLinkMessage = "Enter a complete HTTP or HTTPS URL."
      return
    }
    page.footerLinkRequested(label.slice(0, 48), url)
  }

  function scrollBy(direction) {
    page.contentY = Math.max(0,
      Math.min(Math.max(0, page.contentHeight - page.height),
        page.contentY + direction * Style.space(70)))
  }

  clip: true
  contentWidth: width
  contentHeight: profileColumn.implicitHeight
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: profileColumn
    width: page.width
    spacing: Style.spacing.panelGap

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "MY CURATION PROFILE"
      color: page.accent
      font.family: page.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
      font.letterSpacing: 0.8
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "A clear view of what PYIN remembers, what you chose, and what can change your feed. Everything here stays on this device; ranking does not use AI."
      color: page.dim
      font.family: page.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    BorderSurface {
      width: parent.width
      height: quickAccessColumn.implicitHeight + Style.spacing.lg * 2
      color: "transparent"
      borderSpec: Border.controlSpec("normal", page.foreground, page.accent)
      radius: Style.cornerRadius

      Column {
        id: quickAccessColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.lg
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "LIBRARY & CONTROLS"
          color: page.accent
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.7
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm

          Button {
            text: "History · " + String(page.historyCount)
            iconText: "󰋚"
            tooltipText: "Stories you opened"
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            onClicked: page.destinationRequested("history")
          }

          Button {
            text: "Read Later · " + String(page.bookmarkCount)
            iconText: "󰃀"
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            onClicked: page.destinationRequested("bookmarks")
          }

          Button {
            text: "Hidden · " + String(page.readCount)
            iconText: "󰄬"
            tooltipText: "Marked-read and Show Less stories"
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            onClicked: page.destinationRequested("read")
          }

          Button {
            text: "Alerts · " + String(page.alertCount)
            iconText: "󰂚"
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            onClicked: page.destinationRequested("alerts")
          }

          Button {
            text: "Edit setup"
            iconText: "󰒓"
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            onClicked: page.setupRequested()
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(page.counts.explicit_interest_nodes || 0) + " explicit interests  ·  "
            + String(page.counts.active_learned_terms || 0) + " learned subjects  ·  "
            + String(page.counts.learning_signals || 0) + " reading signals"
          color: page.dim
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }

    Button {
      width: parent.width
      text: "CUSTOMIZE  ·  MENU, FOOTER, READING & AI"
      iconText: page.customizeExpanded ? "󰅀" : "󰅂"
      foreground: page.accent
      accent: page.accent
      fontFamily: page.fontFamily
      fontSize: Style.font.caption
      leftAlign: true
      focusable: true
      horizontalPadding: 0
      tooltipText: page.customizeExpanded ? "Collapse Customize" : "Customize how PYIN works"
      onClicked: page.customizeExpanded = !page.customizeExpanded
    }

    Column {
      visible: page.customizeExpanded
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "MAIN MENU"
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Feed, Profile, and Help always stay available. Choose which optional destinations appear in the same top menu on every page."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: [
            { value: "bookmarks", label: "Read Later", icon: "󰃀" },
            { value: "history", label: "History", icon: "󰋚" },
            { value: "alerts", label: "Alerts", icon: "󰂚" },
            { value: "refresh", label: "Freshness", icon: "↓" }
          ]

          Button {
            required property var modelData
            text: String(modelData.label)
            iconText: String(modelData.icon)
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            selected: page.menuItemEnabled(String(modelData.value))
            enabled: !page.navigationBusy
            tooltipText: selected ? "Shown in the main menu" : "Hidden from the main menu"
            onClicked: page.navigationRequested(String(modelData.value), !selected)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: page.foreground
        opacity: 0.12
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "OPTIONAL FOOTER LINK"
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "The footer is unbranded by default. Add one link of your own; its label appears at the bottom right on every page."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      TextField {
        width: parent.width
        placeholderText: "Link label · e.g. My website"
        text: page.footerLinkDraftLabel
        foreground: page.foreground
        accent: page.accent
        font.family: page.fontFamily
        maximumLength: 48
        enabled: !page.footerLinkBusy
        onTextChanged: page.footerLinkDraftLabel = text
      }

      TextField {
        width: parent.width
        placeholderText: "URL · https://example.com"
        text: page.footerLinkDraftUrl
        foreground: page.foreground
        accent: page.accent
        font.family: page.fontFamily
        maximumLength: 500
        enabled: !page.footerLinkBusy
        onTextChanged: page.footerLinkDraftUrl = text
        onAccepted: page.saveFooterLink()
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm

        Button {
          text: page.footerLinkBusy ? "Saving…" : "Save footer link"
          iconText: page.footerLinkBusy ? "󰦖" : "󰄬"
          iconSpinning: page.footerLinkBusy
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          enabled: !page.footerLinkBusy
          onClicked: page.saveFooterLink()
        }

        Button {
          visible: page.footerLinkLabel !== "" || page.footerLinkDraftLabel !== ""
            || page.footerLinkDraftUrl !== ""
          text: "Clear"
          iconText: "󰆴"
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          enabled: !page.footerLinkBusy
          onClicked: {
            page.footerLinkDraftLabel = ""
            page.footerLinkDraftUrl = ""
            page.saveFooterLink()
          }
        }
      }

      Text {
        visible: page.footerLinkMessage !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: page.footerLinkMessage
        color: page.accent
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: page.foreground
        opacity: 0.12
      }

      Toggle {
        width: parent.width
        label: "Back marks an article read"
        description: page.articleBackMarksRead
          ? "On · Back or Escape hides the finished story and returns to its list."
          : "Off · Back or Escape returns without hiding the story."
        checked: page.articleBackMarksRead
        foreground: page.foreground
        accent: page.accent
        fontFamily: page.fontFamily
        enabled: !page.behaviorBusy
        onClicked: page.backBehaviorRequested(!page.articleBackMarksRead)
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: page.foreground
        opacity: 0.12
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "AI TL;DR SPEED"
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: page.aiSummary
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Flow {
        visible: page.aiProvider === "system"
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: page.systemAiOptions

          Button {
            required property var modelData
            text: String(modelData.label || "Preset")
            tooltipText: String(modelData.model_label || modelData.model || "") + " · "
              + String(modelData.effort || "low") + " reasoning · "
              + String(modelData.description || "")
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            selected: page.systemAiPreset === String(modelData.value)
            enabled: !page.aiPresetBusy
            onClicked: page.aiPresetRequested(String(modelData.value))
          }
        }
      }
    }

    Button {
      width: parent.width
      text: "YOUR CHOICES  ·  TOPICS, SOURCES & EXPLICIT INTERESTS"
      iconText: page.choicesExpanded ? "󰅀" : "󰅂"
      foreground: page.accent
      accent: page.accent
      fontFamily: page.fontFamily
      fontSize: Style.font.caption
      leftAlign: true
      focusable: true
      horizontalPadding: 0
      tooltipText: page.choicesExpanded ? "Collapse Your Choices" : "Inspect choices you made deliberately"
      onClicked: page.choicesExpanded = !page.choicesExpanded
    }

    Column {
      visible: page.choicesExpanded
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "TOPICS"
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: page.topicSummary
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Button {
        text: "Topics & keyword blacklist"
        iconText: "󰓹"
        foreground: page.foreground
        accent: page.accent
        fontFamily: page.fontFamily
        bordered: true
        focusable: true
        onClicked: page.setupPageRequested(2)
      }

      Button {
        width: parent.width
        text: "SETUP & SOURCE MIX"
        iconText: page.setupDetailsExpanded ? "󰅀" : "󰅂"
        foreground: page.foreground
        accent: page.accent
        fontFamily: page.fontFamily
        fontSize: Style.font.caption
        leftAlign: true
        focusable: true
        horizontalPadding: 0
        onClicked: page.setupDetailsExpanded = !page.setupDetailsExpanded
      }

      Column {
        visible: page.setupDetailsExpanded
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: page.setupSummaryText
          color: page.foreground
          font.family: page.fontFamily
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.25
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: page.setupDetailsText
          color: page.dim
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
          lineHeight: 1.25
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "ACTIVE CATALOG\n" + page.sourceMixText
          color: page.foreground
          font.family: page.fontFamily
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.25
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Source-format tags can overlap. They describe ownership and reporting style, not a hidden political score."
          color: page.dim
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Button {
          text: "Edit complete setup"
          iconText: "󰒓"
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          onClicked: page.setupRequested()
        }
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: page.foreground
        opacity: 0.12
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "EXPLICIT INTERESTS  ·  " + String(page.counts.explicit_interest_nodes || 0)
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: page.interestNodes.length === 0
          ? "No explicit article-level interests yet. Use A → Tune your feed on any story."
          : "These deliberate choices are stronger than inferred reading signals. Temporary choices expire automatically."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Repeater {
        model: page.interestNodes

        delegate: Item {
          required property var modelData
          width: profileColumn.width
          height: Math.max(interestRemove.implicitHeight, Style.space(38))

          Text {
            id: interestName
            anchors.left: parent.left
            anchors.right: interestMeta.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (Number(modelData.weight || 0) > 0 ? "+ " : "− ")
              + String(modelData.label || "")
            color: Number(modelData.weight || 0) > 0 ? page.accent : page.foreground
            font.family: page.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: interestMeta
            anchors.right: interestRemove.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width * 0.30, Style.space(170))
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: String(modelData.kind || "subject").toUpperCase() + " · "
              + String(modelData.expires_in || modelData.scope || "lasting")
            color: page.dim
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Button {
            id: interestRemove
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Remove"
            iconText: "󰆴"
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            bordered: true
            focusable: true
            enabled: !page.interestBusy
            onClicked: page.interestRemoveRequested(
              String(modelData.term || ""), String(modelData.scope || "lasting"))
          }
        }
      }
    }

    Button {
      width: parent.width
      text: "LEARNED CURATION  ·  MEMORY, RANKING & SHOW LESS"
      iconText: page.learningExpanded ? "󰅀" : "󰅂"
      foreground: page.accent
      accent: page.accent
      fontFamily: page.fontFamily
      fontSize: Style.font.caption
      leftAlign: true
      focusable: true
      horizontalPadding: 0
      tooltipText: page.learningExpanded ? "Collapse Learned Curation" : "See what PYIN inferred from reading"
      onClicked: page.learningExpanded = !page.learningExpanded
    }

    Column {
      visible: page.learningExpanded
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "PERSONALIZED RANKING  ·  ACTIVE"
        color: page.accent
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "One local, explainable engine combines your setup choices, reading memory, explicit interests, freshness, source diversity, and discovery. AI never chooses the feed order.\nExposure ledger: "
          + String(page.exposure.impressions || 0) + " debounced views across "
          + String(page.exposure.stories || 0) + " stories · last "
          + String(page.exposure.last_seen_age || "never")
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        lineHeight: 1.3
        wrapMode: Text.Wrap
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: page.foreground
        opacity: 0.12
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "CURATION MEMORY  ·  "
          + String(page.counts.active_learned_terms || 0) + " ACTIVE"
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        visible: page.learnedTerms.length === 0 && !page.profileBusy
        width: parent.width
        textFormat: Text.PlainText
        text: "No learned subjects yet. Opens are weak signals; sustained reading and saves teach more."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Repeater {
        model: page.learnedTerms.slice(0, 12)

        delegate: Item {
          required property var modelData
          width: profileColumn.width
          height: Style.space(28)

          Text {
            id: learnedName
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width * 0.34, Style.space(190))
            textFormat: Text.PlainText
            text: String(modelData.term || "")
            color: page.foreground
            font.family: page.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Rectangle {
            anchors.left: learnedName.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: learnedMeta.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(5)
            color: page.foreground
            opacity: 0.12

            Rectangle {
              width: parent.width * Math.max(0.03,
                Math.min(1, Number(modelData.strength || 0)))
              height: parent.height
              color: page.accent
            }
          }

          Text {
            id: learnedMeta
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(135)
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignRight
            text: String(modelData.memory || "recent").toUpperCase()
              + " · " + Number(modelData.weight || 0).toFixed(2)
            color: page.dim
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Button {
        width: parent.width
        text: "SHOW LESS  ·  " + String(page.counts.dismissed_articles || 0) + " DISMISSED"
        iconText: page.showLessExpanded ? "󰅀" : "󰅂"
        foreground: page.foreground
        accent: page.accent
        fontFamily: page.fontFamily
        fontSize: Style.font.caption
        leftAlign: true
        focusable: true
        horizontalPadding: 0
        onClicked: page.showLessExpanded = !page.showLessExpanded
      }

      Column {
        visible: page.showLessExpanded
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Backspace applies one reversible negative signal to the event's subjects and publisher. Restoring the event reverses its contribution."
          color: page.dim
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "TOPICS & WORDS\n" + page.showLessTermText
          color: page.foreground
          font.family: page.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "SOURCES\n" + page.showLessSourceText
          color: page.foreground
          font.family: page.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Repeater {
          model: page.recentDismissals

          delegate: Text {
            required property var modelData
            width: profileColumn.width
            textFormat: Text.PlainText
            text: String(modelData.source || "") + "  ·  "
              + String(modelData.dismissed_age || "now") + "  ·  "
              + String(modelData.title || "Untitled")
            color: page.dim
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
            maximumLineCount: 2
            wrapMode: Text.Wrap
            elide: Text.ElideRight
          }
        }
      }
    }

    Button {
      width: parent.width
      text: "APP & UPDATES  ·  VERSION, CHANNEL & RELEASES"
      iconText: page.updatesExpanded ? "󰅀" : "󰅂"
      foreground: page.accent
      accent: page.accent
      fontFamily: page.fontFamily
      fontSize: Style.font.caption
      leftAlign: true
      focusable: true
      horizontalPadding: 0
      tooltipText: page.updatesExpanded ? "Collapse App & Updates" : "Inspect version and check for stable updates"
      onClicked: page.updatesExpanded = !page.updatesExpanded
    }

    Column {
      visible: page.updatesExpanded
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(page.updateData.summary || "Loading update status…")
        color: page.accent
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(page.updateData.detail
          || "PYIN checks for releases only when you request it.")
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        lineHeight: 1.3
        wrapMode: Text.Wrap
      }

      Text {
        visible: String(page.updateData.current_commit || "") !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: "CHANNEL  ·  " + String(page.updateData.channel || "unknown").toUpperCase()
          + (String(page.updateData.branch || "") !== ""
            ? " / " + String(page.updateData.branch) : "")
          + "\nCOMMIT  ·  " + String(page.updateData.current_commit || "")
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        lineHeight: 1.3
        wrapMode: Text.WrapAnywhere
      }

      Text {
        property var result: page.updateData.last_result || ({})
        visible: String(result.summary || "") !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: "LAST UPDATE  ·  " + String(result.summary || "")
        color: result.ok === false ? page.foreground : page.accent
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm

        Button {
          visible: page.updateData.git_managed === true
          text: page.updateBusy ? "Checking…" : "Check for updates"
          iconText: page.updateBusy ? "󰦖" : "󰑐"
          iconSpinning: page.updateBusy
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          enabled: page.updateData.can_check === true
            && !page.updateBusy && !page.updateLaunching
          tooltipText: page.updateData.can_check === true
            ? "Compare this stable copy with the repository"
            : "Stable checks are disabled for development or modified checkouts"
          onClicked: {
            page.confirmUpdate = false
            page.updateCheckRequested()
          }
        }

        Button {
          visible: page.updateData.update_available === true || page.updateLaunching
          text: page.updateLaunching ? "Updating…"
            : (page.confirmUpdate ? "Confirm update"
              : "Install " + String(page.updateData.target_version || "update"))
          iconText: page.updateLaunching ? "󰦖" : (page.confirmUpdate ? "󰄬" : "󰁝")
          iconSpinning: page.updateLaunching
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          selected: page.confirmUpdate
          enabled: page.updateData.can_install === true
            && !page.updateBusy && !page.updateLaunching
          tooltipText: page.confirmUpdate
            ? "Install through Omarchy and reload PYIN"
            : "Review the confirmation before installing"
          onClicked: {
            if (!page.confirmUpdate) page.confirmUpdate = true
            else page.updateInstallRequested()
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "No silent installs. Update checks are manual, installation requires confirmation, and Omarchy validates the replacement before keeping it. Your profile, history, alerts, sources, and saved stories live outside the plugin folder and remain untouched."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    Button {
      width: parent.width
      text: "DATA & PRIVACY  ·  LOCAL STORAGE, EXPORT & RESET"
      iconText: page.dataExpanded ? "󰅀" : "󰅂"
      foreground: page.accent
      accent: page.accent
      fontFamily: page.fontFamily
      fontSize: Style.font.caption
      leftAlign: true
      focusable: true
      horizontalPadding: 0
      tooltipText: page.dataExpanded ? "Collapse Data & Privacy" : "Inspect and manage locally stored data"
      onClicked: page.dataExpanded = !page.dataExpanded
    }

    Column {
      visible: page.dataExpanded
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(page.counts.opened_articles || 0) + " viewed stories · "
          + String(page.counts.bookmarks || 0) + " saved · "
          + String(page.counts.learning_signals || 0) + " learning signals · "
          + String(page.counts.explicit_interest_nodes || 0) + " explicit interests · "
          + String(page.counts.impressions || 0) + " debounced views · "
          + String(page.counts.read_articles || 0) + " hidden groups · "
          + String(page.counts.alerts || 0) + " alerts · "
          + String(page.counts.cached_articles || 0) + " cached articles"
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Local database: " + String(page.storage.database || "")
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WrapAnywhere
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm

        Button {
          text: "Export profile"
          iconText: page.transferBusy ? "󰦖" : "󰈇"
          iconSpinning: page.transferBusy
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          enabled: !page.transferBusy
          onClicked: page.exportRequested()
        }

        Button {
          text: "Import profile"
          iconText: page.transferBusy ? "󰦖" : "󰋺"
          iconSpinning: page.transferBusy
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          enabled: !page.transferBusy
          tooltipText: "Reads ~/Downloads/chuchua-news-profile.json"
          onClicked: page.importRequested()
        }

        Button {
          text: page.confirmReset ? "Confirm reset" : "Reset learned history"
          iconText: page.resetBusy ? "󰦖" : "󰆴"
          iconSpinning: page.resetBusy
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          bordered: true
          focusable: true
          enabled: !page.profileBusy && !page.resetBusy
          onClicked: page.resetRequested()
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: page.confirmReset
          ? "Press Confirm reset again to erase inferred reading, Show Less, viewed-history, and exposure data. Explicit topics, menu choices, saved stories, alerts, and source settings remain."
          : "Reset affects inferred and viewed-history data only. Explicit choices and library items remain."
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    Item { width: 1; height: Style.spacing.md }
  }
}
