import "Reading.js" as Reading
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

FocusScope {
  id: wizard

  property var profile: ({})
  property var catalogs: ({})
  property var sourceSummary: ({})
  property int profileRevision: 0
  property bool saving: false
  property bool existingComplete: false
  property string backendPath: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: Reading.secondaryColor(Color.foreground, Color.background, Color.muted)
  property string fontFamily: Style.font.family

  property int page: 0
  readonly property int pageCount: 8
  property string validationMessage: ""

  property bool articleImages: false
  property string readingSize: "regular"
  property string density: "calm"
  property string backgroundStyle: "plain"
  property int readingMinutes: 15
  property string country: ""
  property string region: ""
  property string city: ""
  property var languages: ["en"]
  property var mustTopics: []
  property var interestedTopics: []
  property var mutedTopics: []
  property string blockedKeywordsText: ""
  property var sourceTypes: []
  property var disabledSourceIds: []
  property var customSources: []
  property string customSourceName: ""
  property string customSourceUrl: ""
  property string viewpointMode: "open"
  property int discoveryPercent: 25
  property bool notificationsEnabled: true
  property string quietStart: "22:00"
  property string quietEnd: "07:00"
  property int notificationMax: 6
  property string aiMode: "system"
  property bool contextFraming: false
  property string systemAiModel: ""
  property string systemAiEffort: ""
  property var aiModelCatalog: ({})
  property bool aiModelsLoading: false
  signal aiModelsRequested(bool refresh)
  property string localAiUrl: "http://127.0.0.1:11434/v1"
  property string localAiModel: "llama3.2:3b"
  property bool learnFromOpens: true
  property int retentionDays: 90
  property bool markReadOnBack: true
  property var navigationItems: ["bookmarks", "history", "alerts", "refresh"]

  readonly property var topicOptions: catalogs && catalogs.topics ? catalogs.topics : []
  readonly property var languageOptions: catalogs && catalogs.languages ? catalogs.languages : []
  readonly property var sourceTypeOptions: catalogs && catalogs.source_types ? catalogs.source_types : []
  readonly property var viewpointOptions: catalogs && catalogs.viewpoints ? catalogs.viewpoints : []
  readonly property var readingOptions: catalogs && catalogs.reading ? catalogs.reading : []
  readonly property int feedStoryLimit: {
    var choice = wizard.readingOptions.find(function(item) { return Number(item.value) === wizard.readingMinutes })
    return choice ? Number(choice.story_limit) : 30
  }
  property var systemAiStatus: ({})
  readonly property var sourceOptions: sourceSummary && sourceSummary.catalog
    ? sourceSummary.catalog : []
  readonly property var effectiveSourceOptions: {
    var output = []
    var bundled = wizard.sourceOptions
    for (var i = 0; i < bundled.length; i++) {
      if (String(bundled[i].origin || "bundled") !== "profile")
        output.push(bundled[i])
    }
    var custom = wizard.customSources
    for (var j = 0; j < custom.length; j++) {
      var source = custom[j]
      output.push({
        value: String(source.id || ""),
        label: String(source.name || "Custom source"),
        description: wizard.hostForUrl(source.url) + " · custom · YOUR SOURCE",
        types: ["custom"],
        languages: source.languages || ["en"],
        regions: ["user"],
        custom: true,
        origin: "profile",
        url: String(source.url || "")
      })
    }
    return output
  }

  signal saveRequested(var profile)
  signal cancelRequested()

  function arrayFrom(value) {
    var output = []
    if (!value || typeof value.length !== "number" || typeof value === "string") return output
    for (var i = 0; i < value.length; i++) output.push(String(value[i]))
    return output
  }

  function objectArrayFrom(value) {
    var output = []
    if (!value || typeof value.length !== "number" || typeof value === "string")
      return output
    for (var i = 0; i < value.length; i++)
      if (value[i] && typeof value[i] === "object") output.push(value[i])
    return output
  }

  function hostForUrl(value) {
    return String(value || "")
      .replace(/^https?:\/\//i, "").split(/[\/?#]/)[0].replace(/^www\./i, "")
  }

  function normalizedFeedUrl(value) {
    var url = String(value || "").trim().replace(/#.*$/, "")
    return /^https?:\/\/[^\s/]+(?:\/[^\s]*)?$/i.test(url) ? url : ""
  }

  function newCustomSourceId(name) {
    var slug = String(name || "source").toLowerCase()
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 36)
    if (slug === "") slug = "source"
    return "custom-" + slug + "-" + Date.now().toString(36)
  }

  function addCustomSource() {
    var name = wizard.customSourceName.trim().replace(/\s+/g, " ")
    var url = wizard.normalizedFeedUrl(wizard.customSourceUrl)
    if (name === "") {
      wizard.validationMessage = "Give the custom source a recognizable name."
      return
    }
    if (url === "") {
      wizard.validationMessage = "Enter a complete HTTP or HTTPS RSS/Atom URL."
      return
    }
    if (wizard.customSources.length >= 50) {
      wizard.validationMessage = "Custom-source limit reached (50)."
      return
    }
    var comparable = url.toLowerCase().replace(/\/$/, "")
    for (var i = 0; i < wizard.effectiveSourceOptions.length; i++) {
      var existing = String(wizard.effectiveSourceOptions[i].url || "")
        .toLowerCase().replace(/\/$/, "")
      if (existing !== "" && existing === comparable) {
        wizard.validationMessage = "That feed URL is already in your source catalog."
        return
      }
    }
    var next = wizard.objectArrayFrom(wizard.customSources)
    next.push({
      id: wizard.newCustomSourceId(name),
      name: name.slice(0, 160),
      url: url,
      topics: [],
      languages: wizard.arrayFrom(wizard.languages).length > 0
        ? wizard.arrayFrom(wizard.languages) : ["en"],
      types: ["custom"],
      regions: ["user"],
      custom: true
    })
    wizard.customSources = next
    wizard.customSourceName = ""
    wizard.customSourceUrl = ""
    wizard.validationMessage = "Custom source added to this setup draft."
  }

  function removeCustomSource(value) {
    var sourceKey = String(value)
    var next = []
    for (var i = 0; i < wizard.customSources.length; i++)
      if (String(wizard.customSources[i].id || "") !== sourceKey)
        next.push(wizard.customSources[i])
    wizard.customSources = next
    wizard.disabledSourceIds = wizard.without(wizard.disabledSourceIds, [sourceKey])
    wizard.validationMessage = "Custom source removed from this setup draft."
  }

  function valueOr(object, key, fallback) {
    return object && object[key] !== undefined && object[key] !== null
      ? object[key] : fallback
  }

  function keywordList(value) {
    var output = []
    var pieces = String(value || "").split(/[,;\n]/)
    for (var i = 0; i < pieces.length && output.length < 50; i++) {
      var keyword = pieces[i].trim().toLowerCase().replace(/\s+/g, " ")
      if (keyword.length >= 2 && output.indexOf(keyword) === -1) output.push(keyword)
    }
    return output
  }

  function systemAiSummary() {
    return wizard.systemAiModel === "" ? "Agent default"
      : wizard.systemAiModel + (wizard.systemAiEffort ? " · " + wizard.systemAiEffort : " · agent default reasoning")
  }

  function loadProfile() {
    var value = wizard.profile || ({})
    var appearance = value.appearance || ({})
    var location = value.location || ({})
    var topics = value.topics || ({})
    var viewpoint = value.viewpoint || ({})
    var notifications = value.notifications || ({})
    var ai = value.ai || ({})
    var privacy = value.privacy || ({})
    var behavior = value.behavior || ({})
    var navigation = value.navigation || ({})
    wizard.existingComplete = Boolean(value.complete)
    wizard.articleImages = appearance.article_images === true
    wizard.readingSize = String(appearance.reading_size || "regular")
    wizard.density = String(wizard.valueOr(appearance, "density", "calm"))
    wizard.backgroundStyle = String(wizard.valueOr(appearance, "background", "plain")) === "paper"
      ? "paper" : "plain"
    wizard.readingMinutes = Number(wizard.valueOr(value, "reading_minutes", 15))
    wizard.country = String(wizard.valueOr(location, "country", ""))
    wizard.region = String(wizard.valueOr(location, "region", ""))
    wizard.city = String(wizard.valueOr(location, "city", ""))
    wizard.languages = wizard.arrayFrom(value.languages || ["en"])
    wizard.mustTopics = wizard.arrayFrom(topics.must || [])
    wizard.interestedTopics = wizard.arrayFrom(topics.interested || [])
    wizard.mutedTopics = wizard.arrayFrom(topics.muted || [])
    wizard.blockedKeywordsText = wizard.arrayFrom(value.blocked_keywords || []).join(", ")
    wizard.sourceTypes = wizard.arrayFrom(value.source_types || [])
    wizard.disabledSourceIds = wizard.arrayFrom(value.disabled_source_ids || [])
    wizard.customSources = wizard.objectArrayFrom(value.custom_sources || [])
    wizard.customSourceName = ""
    wizard.customSourceUrl = ""
    if (wizard.sourceTypes.length === 0) wizard.selectAllSources()
    wizard.viewpointMode = String(wizard.valueOr(viewpoint, "mode", "open"))
    wizard.discoveryPercent = Number(wizard.valueOr(viewpoint, "discovery_percent", 25))
    wizard.notificationsEnabled = Boolean(wizard.valueOr(notifications, "enabled", true))
    wizard.quietStart = String(wizard.valueOr(notifications, "quiet_start", "22:00"))
    wizard.quietEnd = String(wizard.valueOr(notifications, "quiet_end", "07:00"))
    wizard.notificationMax = Number(wizard.valueOr(notifications, "max_per_day", 6))
    wizard.aiMode = String(wizard.valueOr(ai, "mode", "system"))
    wizard.contextFraming = ai.context_framing === true
    wizard.systemAiModel = String(ai.system_model || "")
    wizard.systemAiEffort = String(ai.system_effort || "")
    wizard.localAiUrl = String(wizard.valueOr(ai, "local_url", "http://127.0.0.1:11434/v1"))
    wizard.localAiModel = String(wizard.valueOr(ai, "local_model", "llama3.2:3b"))
    wizard.learnFromOpens = Boolean(wizard.valueOr(privacy, "learn_from_opens", true))
    wizard.retentionDays = Number(wizard.valueOr(privacy, "retention_days", 90))
    wizard.markReadOnBack = Boolean(wizard.valueOr(behavior, "mark_read_on_back", true))
    wizard.navigationItems = wizard.arrayFrom(wizard.valueOr(
      navigation, "items", ["bookmarks", "history", "alerts", "refresh"]))
    wizard.page = 0
    wizard.validationMessage = ""
    wizard.forceActiveFocus()
  }

  function contains(values, value) {
    return wizard.arrayFrom(values).indexOf(String(value)) !== -1
  }

  function without(values, blocked) {
    var output = []
    var blockedValues = wizard.arrayFrom(blocked)
    var input = wizard.arrayFrom(values)
    for (var i = 0; i < input.length; i++)
      if (blockedValues.indexOf(input[i]) === -1) output.push(input[i])
    return output
  }

  function setMustTopics(values) {
    wizard.mustTopics = wizard.arrayFrom(values)
    wizard.interestedTopics = wizard.without(wizard.interestedTopics, wizard.mustTopics)
    wizard.mutedTopics = wizard.without(wizard.mutedTopics, wizard.mustTopics)
  }

  function setInterestedTopics(values) {
    var next = wizard.without(values, wizard.mustTopics)
    wizard.interestedTopics = wizard.without(next, wizard.mutedTopics)
  }

  function setMutedTopics(values) {
    wizard.mutedTopics = wizard.arrayFrom(values)
    wizard.mustTopics = wizard.without(wizard.mustTopics, wizard.mutedTopics)
    wizard.interestedTopics = wizard.without(wizard.interestedTopics, wizard.mutedTopics)
  }

  function selectAllSources() {
    var output = []
    for (var i = 0; i < wizard.sourceTypeOptions.length; i++)
      output.push(String(wizard.sourceTypeOptions[i].value))
    wizard.sourceTypes = output
    wizard.disabledSourceIds = []
  }

  function activeSourceEstimate() {
    var count = 0
    for (var i = 0; i < wizard.effectiveSourceOptions.length; i++) {
      var source = wizard.effectiveSourceOptions[i]
      if (wizard.contains(wizard.disabledSourceIds, source.value)) continue
      if (Boolean(source.custom)) {
        count++
        continue
      }
      var typeMatch = Boolean(source.custom)
      var types = wizard.arrayFrom(source.types || [])
      for (var t = 0; t < types.length; t++)
        if (wizard.contains(wizard.sourceTypes, types[t])) { typeMatch = true; break }
      var languageMatch = false
      var sourceLanguages = wizard.arrayFrom(source.languages || [])
      for (var l = 0; l < sourceLanguages.length; l++)
        if (wizard.contains(wizard.languages, sourceLanguages[l])) { languageMatch = true; break }
      if (typeMatch && languageMatch) count++
    }
    return count
  }

  function toggleSourceType(value) {
    var key = String(value)
    var next = wizard.arrayFrom(wizard.sourceTypes)
    var index = next.indexOf(key)
    if (index === -1) next.push(key)
    else if (next.length > 1) next.splice(index, 1)
    else {
      wizard.validationMessage = "Keep at least one source pack enabled."
      return
    }
    wizard.validationMessage = ""
    wizard.sourceTypes = next
  }

  function chooseViewpoint(value, percent) {
    wizard.viewpointMode = String(value)
    wizard.discoveryPercent = Number(percent)
  }

  function buildProfile() {
    return {
      version: 11,
      complete: true,
      appearance: {
        theme: "omarchy",
        density: wizard.density,
        article_images: wizard.articleImages,
        reading_size: wizard.readingSize,
        background: wizard.backgroundStyle,
        footer_link: wizard.valueOr(
          wizard.profile && wizard.profile.appearance
            ? wizard.profile.appearance : ({}),
          "footer_link", { label: "", url: "" })
      },
      location: {
        country: wizard.country.trim(),
        region: wizard.region.trim(),
        city: wizard.city.trim()
      },
      languages: wizard.arrayFrom(wizard.languages),
      topics: {
        must: wizard.arrayFrom(wizard.mustTopics),
        interested: wizard.arrayFrom(wizard.interestedTopics),
        muted: wizard.arrayFrom(wizard.mutedTopics)
      },
      blocked_keywords: wizard.keywordList(wizard.blockedKeywordsText),
      source_types: wizard.arrayFrom(wizard.sourceTypes),
      disabled_source_ids: wizard.arrayFrom(wizard.disabledSourceIds),
      custom_sources: wizard.objectArrayFrom(wizard.customSources),
      viewpoint: {
        mode: wizard.viewpointMode,
        discovery_percent: wizard.discoveryPercent
      },
      reading_minutes: wizard.readingMinutes,
      behavior: {
        mark_read_on_back: wizard.markReadOnBack
      },
      navigation: {
        items: wizard.arrayFrom(wizard.navigationItems)
      },
      notifications: {
        enabled: wizard.notificationsEnabled,
        quiet_start: wizard.quietStart.trim(),
        quiet_end: wizard.quietEnd.trim(),
        max_per_day: wizard.notificationMax
      },
      ai: {
        mode: wizard.aiMode,
        context_framing: wizard.contextFraming,
        system_model: wizard.systemAiModel,
        system_effort: wizard.systemAiEffort,
        local_url: wizard.localAiUrl.trim(),
        local_model: wizard.localAiModel.trim()
      },
      privacy: {
        learn_from_opens: wizard.learnFromOpens,
        retention_days: wizard.retentionDays
      }
    }
  }

  function pageTitle() {
    return [
      "READ ON YOUR TERMS",
      "WHERE AND IN WHAT LANGUAGE",
      "WHAT MATTERS TO YOU",
      "CHOOSE & INSPECT YOUR SOURCES",
      "HOW OPEN SHOULD THE FEED BE?",
      "ALERTS WITHOUT THE ATTENTION TRAP",
      "AI IS OPTIONAL",
      "YOUR FEED, EXPLAINED"
    ][wizard.page]
  }

  function nextPage() {
    wizard.validationMessage = ""
    if (wizard.page < wizard.pageCount - 1) {
      wizard.page++
      contentScroll.contentY = 0
      wizard.forceActiveFocus()
    } else if (!wizard.saving) {
      wizard.saveRequested(wizard.buildProfile())
    }
  }

  function previousPage() {
    wizard.validationMessage = ""
    if (wizard.page > 0) {
      wizard.page--
      contentScroll.contentY = 0
      wizard.forceActiveFocus()
    } else wizard.cancelRequested()
  }

  function scrollContent(amount) {
    contentScroll.contentY = Math.max(0,
      Math.min(Math.max(0, contentScroll.contentHeight - contentScroll.height),
        contentScroll.contentY + amount))
  }

  onProfileRevisionChanged: loadProfile()
  Component.onCompleted: loadProfile()

  Keys.onPressed: function(event) {
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Right) {
      wizard.nextPage(); event.accepted = true
    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Left) {
      wizard.previousPage(); event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      wizard.cancelRequested(); event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      wizard.scrollContent(Math.max(Style.space(180), contentScroll.height * 0.72))
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      wizard.scrollContent(-Math.max(Style.space(180), contentScroll.height * 0.72))
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      contentScroll.contentY = 0; event.accepted = true
    } else if (event.key === Qt.Key_End) {
      contentScroll.contentY = Math.max(0,
        contentScroll.contentHeight - contentScroll.height)
      event.accepted = true
    } else if (event.text === "j") {
      wizard.scrollContent(Style.space(70)); event.accepted = true
    } else if (event.text === "k") {
      wizard.scrollContent(-Style.space(70)); event.accepted = true
    }
  }

  Text {
    id: progressLabel
    anchors.left: parent.left
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: "SETUP  " + String(wizard.page + 1) + " / " + String(wizard.pageCount)
    color: wizard.accent
    font.family: wizard.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.8
  }

  Text {
    anchors.right: parent.right
    anchors.top: parent.top
    width: Math.max(0, parent.width - progressLabel.width - Style.spacing.md)
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: "Ctrl+← / Ctrl+→ pages  ·  j/k scroll  ·  Tab controls  ·  Esc exit"
    color: wizard.dim
    font.family: wizard.fontFamily
    font.pixelSize: Style.font.caption
  }

  Row {
    id: progressTrack
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: progressLabel.bottom
    anchors.topMargin: Style.spacing.sm
    spacing: Style.spacing.xs

    Repeater {
      model: wizard.pageCount
      Rectangle {
        required property int index
        width: (progressTrack.width - (wizard.pageCount - 1) * progressTrack.spacing) / wizard.pageCount
        height: Style.space(3)
        color: index <= wizard.page ? wizard.accent : wizard.foreground
        opacity: index <= wizard.page ? 1 : 0.12
      }
    }
  }

  Text {
    id: titleLabel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: progressTrack.bottom
    anchors.topMargin: Style.spacing.panelGap
    textFormat: Text.PlainText
    text: wizard.pageTitle()
    color: wizard.foreground
    font.family: wizard.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
    font.letterSpacing: 0.6
  }

  Flickable {
    id: contentScroll
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: titleLabel.bottom
    anchors.topMargin: Style.spacing.md
    anchors.bottom: navigation.top
    anchors.bottomMargin: Style.spacing.md
    clip: true
    contentWidth: width
    contentHeight: pageContent.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pageContent
      width: contentScroll.width
      spacing: Style.spacing.panelGap

      Column {
        visible: wizard.page === 0
        width: parent.width
        spacing: Style.spacing.panelGap

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Choose how many stories appear in your main feed. Choose a separate 5, 15, or 30 minute session in Daily Editions. The interface follows your active Omarchy theme."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          lineHeight: 1.25
          wrapMode: Text.Wrap
        }

        Row {
          width: parent.width
          spacing: Style.spacing.panelGap

          Dropdown {
            width: Math.min(Style.space(300), (parent.width - parent.spacing) / 2)
            label: "Feed size"
            value: String(wizard.readingMinutes)
            options: wizard.readingOptions
            foreground: wizard.foreground
            background: wizard.background
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onChanged: function(value) { wizard.readingMinutes = Number(value) }
          }

          Dropdown {
            width: Math.min(Style.space(300), (parent.width - parent.spacing) / 2)
            label: "Story density"
            value: wizard.density
            options: [
              { value: "calm", label: "Calm" },
              { value: "compact", label: "Compact" },
              { value: "classic", label: "Classic" }
            ]
            foreground: wizard.foreground
            background: wizard.background
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onChanged: function(value) { wizard.density = value }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: wizard.density === "classic"
            ? "Classic keeps the original roomy layout with open spacing and no separators."
            : (wizard.density === "compact"
              ? "Compact fits more stories on screen, with subtle lines between them."
              : "Calm gives each story room to breathe, with subtle lines between them.")
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Row {
          width: parent.width
          spacing: Style.spacing.panelGap

          Dropdown {
            id: backgroundChoice
            width: Math.min(Style.space(300), (parent.width - parent.spacing) / 2)
            label: "Background"
            value: wizard.backgroundStyle
            options: [
              { value: "plain", label: "Plain" },
              { value: "paper", label: "Paper" }
            ]
            foreground: wizard.foreground
            background: wizard.background
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onChanged: function(value) { wizard.backgroundStyle = value }
          }

          Text {
            width: parent.width - backgroundChoice.width - parent.spacing
            anchors.verticalCenter: backgroundChoice.verticalCenter
            textFormat: Text.PlainText
            text: wizard.backgroundStyle === "paper"
              ? "Paper adds a subtle, static grain in your current Omarchy colors."
              : "Plain uses your Omarchy background without texture."
            color: wizard.dim
            font.family: wizard.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
        }

        ReadingPreferences {
          width: parent.width
          readingSize: wizard.readingSize
          staged: true
          onSizeRequested: function(size) { wizard.readingSize = size }
        }

        Toggle {
          width: parent.width
          label: "Show article images"
          description: "Optional feed-supplied thumbnails. Loads images from publisher image hosts as you scroll and keeps a limited local cache."
          checked: wizard.articleImages
          foreground: wizard.foreground
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onClicked: wizard.articleImages = !wizard.articleImages
        }

        BorderSurface {
          width: parent.width
          height: themeText.implicitHeight + Style.spacing.huge * 2
          color: wizard.background
          borderSpec: Border.controlSpec("normal", wizard.foreground, wizard.accent)
          radius: Style.cornerRadius

          Loader {
            anchors.fill: parent
            anchors.margins: Style.spacing.hairline
            active: wizard.visible && wizard.page === 0 && wizard.backgroundStyle === "paper"
            sourceComponent: PaperBackground { ink: wizard.foreground }
          }

          Text {
            id: themeText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.spacing.rowPaddingX
            textFormat: Text.PlainText
            text: (wizard.backgroundStyle === "paper" ? "PAPER" : "PLAIN")
              + " · FOLLOW OMARCHY\nYour colors, type, and spacing update automatically when the theme changes."
            color: wizard.foreground
            font.family: wizard.fontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.25
            wrapMode: Text.Wrap
          }
        }
      }

      Column {
        visible: wizard.page === 1
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Location is optional. It is used only as a local ranking boost; it is never sent to a publisher or AI provider."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Row {
          width: parent.width
          spacing: Style.spacing.md

          TextField {
            width: (parent.width - parent.spacing * 2) / 3
            placeholderText: "Country"
            text: wizard.country
            foreground: wizard.foreground
            accent: wizard.accent
            font.family: wizard.fontFamily
            onTextChanged: wizard.country = text
          }
          TextField {
            width: (parent.width - parent.spacing * 2) / 3
            placeholderText: "Province / region"
            text: wizard.region
            foreground: wizard.foreground
            accent: wizard.accent
            font.family: wizard.fontFamily
            onTextChanged: wizard.region = text
          }
          TextField {
            width: (parent.width - parent.spacing * 2) / 3
            placeholderText: "City"
            text: wizard.city
            foreground: wizard.foreground
            accent: wizard.accent
            font.family: wizard.fontFamily
            onTextChanged: wizard.city = text
          }
        }

        Repeater {
          model: wizard.languageOptions
          Toggle {
            required property var modelData
            width: pageContent.width
            label: String(modelData.label) + "  ·  " + String(modelData.count || 0) + " sources"
            description: String(modelData.description || "")
            checked: wizard.contains(wizard.languages, modelData.value)
            foreground: wizard.foreground
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onClicked: {
              if (!checked) wizard.languages = [String(modelData.value)]
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "The profile format is language-aware. The bundled launch catalog is English today; imported OPML feeds can extend it without changing the app."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      Column {
        visible: wizard.page === 2
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Priorities are explicit and visible. Must-see topics get the strongest boost, interests get a normal boost, and muted topics are pushed down. Geographic relevance comes from the country, region, and city on the previous page."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        MultiSelect {
          width: parent.width
          label: "Must-see topics"
          triggerLabel: "Choose must-see topics"
          noSelectionText: "No must-see topics"
          placeholderText: "Find a topic…"
          values: wizard.mustTopics
          options: wizard.topicOptions
          foreground: wizard.foreground
          background: wizard.background
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onChanged: function(values) { wizard.setMustTopics(values) }
        }

        MultiSelect {
          width: parent.width
          label: "Interested"
          triggerLabel: "Choose interests"
          noSelectionText: "Balanced interests"
          placeholderText: "Find a topic…"
          values: wizard.interestedTopics
          options: wizard.topicOptions
          foreground: wizard.foreground
          background: wizard.background
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onChanged: function(values) { wizard.setInterestedTopics(values) }
        }

        MultiSelect {
          width: parent.width
          label: "Mute / reduce"
          triggerLabel: "Choose topics to reduce"
          noSelectionText: "Nothing muted"
          placeholderText: "Find a topic…"
          values: wizard.mutedTopics
          options: wizard.topicOptions
          foreground: wizard.foreground
          background: wizard.background
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onChanged: function(values) { wizard.setMutedTopics(values) }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: wizard.foreground
          opacity: 0.12
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "KEYWORD BLACKLIST"
          color: wizard.accent
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.7
        }

        TextField {
          width: parent.width
          placeholderText: "Comma-separated words or phrases…"
          text: wizard.blockedKeywordsText
          foreground: wizard.foreground
          accent: wizard.accent
          font.family: wizard.fontFamily
          onTextChanged: wizard.blockedKeywordsText = text
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Exact words and phrases are removed from the normal feed and alert notifications. Manual Search remains unfiltered so you can still find or troubleshoot a story."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      Column {
        visible: wizard.page === 3
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "The full catalog is the firehose. Packs determine which feeds are refreshed; sources can belong to more than one pack. Inspect every publisher below—these are descriptive formats, not political-bias ratings."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.spacing.md
          rowSpacing: Style.spacing.md

          Repeater {
            model: wizard.sourceTypeOptions
            Toggle {
              required property var modelData
              width: (pageContent.width - Style.spacing.md) / 2
              label: String(modelData.label) + "  ·  " + String(modelData.count || 0)
              description: String(modelData.description || "")
              checked: wizard.contains(wizard.sourceTypes, modelData.value)
              foreground: wizard.foreground
              accent: wizard.accent
              fontFamily: wizard.fontFamily
              onClicked: wizard.toggleSourceType(modelData.value)
            }
          }
        }

        Row {
          spacing: Style.spacing.md
          Button {
            text: "Enable all packs"
            iconText: "󰄬"
            focusable: true
            bordered: true
            foreground: wizard.foreground
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onClicked: wizard.selectAllSources()
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(wizard.activeSourceEstimate()) + " of "
              + String(wizard.effectiveSourceOptions.length) + " sources active"
            color: wizard.dim
            font.family: wizard.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: wizard.foreground
          opacity: 0.12
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "HIDE INDIVIDUAL SOURCES  ·  "
            + String(wizard.effectiveSourceOptions.length)
          color: wizard.accent
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.7
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Check a source to hide it; uncheck it to allow it again. Source packs still determine which other sources are active. Changes are saved only when you finish setup."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        MultiSelect {
          id: sourceCatalogPicker
          width: parent.width
          showLabel: true
          label: "Checked = hidden · " + String(wizard.disabledSourceIds.length) + " hidden"
          triggerLabel: "Choose sources to hide…"
          noSelectionText: "No individually hidden sources"
          placeholderText: "Search publisher, host, region, type, or topic…"
          emptyText: "No catalog sources"
          values: wizard.disabledSourceIds
          options: wizard.effectiveSourceOptions
          foreground: wizard.foreground
          background: wizard.background
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onChanged: function(values) { wizard.disabledSourceIds = wizard.arrayFrom(values) }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: wizard.foreground
          opacity: 0.12
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "ADD YOUR OWN RSS / ATOM SOURCE"
          color: wizard.accent
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.7
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Custom feeds are always eligible unless you hide them. They stay in this setup draft until the final page, and PYIN checks the endpoint on its next refresh."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Column {
          visible: wizard.customSources.length > 0
          width: parent.width
          spacing: Style.spacing.sm

          Repeater {
            model: wizard.customSources

            BorderSurface {
              required property var modelData
              width: pageContent.width
              height: Math.max(customSourceText.implicitHeight + Style.spacing.md * 2,
                removeCustomSourceButton.implicitHeight + Style.spacing.md * 2)
              color: "transparent"
              borderSpec: Border.controlSpec("normal", wizard.foreground, wizard.accent)
              radius: Style.cornerRadius

              Column {
                id: customSourceText
                anchors.left: parent.left
                anchors.right: removeCustomSourceButton.left
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(modelData.name || "Custom source")
                  color: wizard.foreground
                  font.family: wizard.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(modelData.url || "")
                  color: wizard.dim
                  font.family: wizard.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              Button {
                id: removeCustomSourceButton
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove"
                iconText: "󰆴"
                tooltipText: "Remove this source from the setup draft"
                focusable: true
                bordered: true
                foreground: wizard.foreground
                accent: wizard.accent
                fontFamily: wizard.fontFamily
                onClicked: wizard.removeCustomSource(String(modelData.id || ""))
              }
            }
          }
        }

        TextField {
          width: parent.width
          placeholderText: "Source name · e.g. Local newsroom"
          text: wizard.customSourceName
          foreground: wizard.foreground
          accent: wizard.accent
          font.family: wizard.fontFamily
          maximumLength: 160
          onTextChanged: wizard.customSourceName = text
        }

        TextField {
          width: parent.width
          placeholderText: "RSS or Atom URL · https://example.org/feed.xml"
          text: wizard.customSourceUrl
          foreground: wizard.foreground
          accent: wizard.accent
          font.family: wizard.fontFamily
          maximumLength: 500
          onTextChanged: wizard.customSourceUrl = text
          onAccepted: wizard.addCustomSource()
        }

        FeedProbe {
          width: parent.width
          backendPath: wizard.backendPath
          feedUrl: wizard.customSourceUrl
          foreground: wizard.foreground
          accent: wizard.accent
          dim: wizard.dim
          fontFamily: wizard.fontFamily
        }

        Button {
          text: "Add source to this setup"
          iconText: "󰐕"
          tooltipText: "Stage this feed; it is saved when setup is completed"
          focusable: true
          bordered: true
          foreground: wizard.foreground
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          enabled: wizard.customSourceName.trim() !== ""
            && wizard.customSourceUrl.trim() !== ""
          onClicked: wizard.addCustomSource()
        }
      }

      Column {
        visible: wizard.page === 4
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Instead of assigning publishers a secret left/right label, choose how much room the feed reserves for reporting outside your explicit and learned interests."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Repeater {
          model: wizard.viewpointOptions
          Button {
            required property var modelData
            width: pageContent.width
            height: Style.space(64)
            leftAlign: true
            focusable: true
            bordered: true
            selected: wizard.viewpointMode === String(modelData.value)
            text: String(modelData.label) + "  ·  " + String(modelData.discovery_percent) + "% discovery"
            tooltipText: String(modelData.description || "")
            foreground: wizard.foreground
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onClicked: wizard.chooseViewpoint(modelData.value, modelData.discovery_percent)
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Selected: " + String(wizard.discoveryPercent) + "% of a personalized feed is reserved for useful stories outside your usual mix. Search results are never padded with discovery stories."
          color: wizard.accent
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      Column {
        visible: wizard.page === 5
        width: parent.width
        spacing: Style.spacing.md

        Toggle {
          width: parent.width
          label: "Desktop notifications for subject alerts"
          description: "Matching happens locally when new feed items arrive. AI is never involved."
          checked: wizard.notificationsEnabled
          foreground: wizard.foreground
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onClicked: wizard.notificationsEnabled = !wizard.notificationsEnabled
        }

        Row {
          visible: wizard.notificationsEnabled
          width: parent.width
          spacing: Style.spacing.md

          TextField {
            width: Style.space(190)
            placeholderText: "Quiet start (22:00)"
            text: wizard.quietStart
            foreground: wizard.foreground
            accent: wizard.accent
            font.family: wizard.fontFamily
            onTextChanged: wizard.quietStart = text
          }
          TextField {
            width: Style.space(190)
            placeholderText: "Quiet end (07:00)"
            text: wizard.quietEnd
            foreground: wizard.foreground
            accent: wizard.accent
            font.family: wizard.fontFamily
            onTextChanged: wizard.quietEnd = text
          }
          Dropdown {
            width: Style.space(220)
            showLabel: false
            value: String(wizard.notificationMax)
            options: [
              { value: "3", label: "At most 3 / day" },
              { value: "6", label: "At most 6 / day" },
              { value: "12", label: "At most 12 / day" },
              { value: "24", label: "At most 24 / day" }
            ]
            foreground: wizard.foreground
            background: wizard.background
            accent: wizard.accent
            fontFamily: wizard.fontFamily
            onChanged: function(value) { wizard.notificationMax = Number(value) }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Quiet hours suppress notifications rather than saving up a stressful digest. Alert matches remain de-duplicated in the local database."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      Column {
        visible: wizard.page === 6
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Feed ranking, catalog search, RSS synopses, source filtering, and alerts are always local and model-free. AI runs only when you request a story TL;DR."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.md

          Repeater {
            model: [
              { value: "system", label: "Follow Omarchy", description: "Use Omarchy's selected Claude Code, Gemini or Grok, with its existing sign-in and model settings" },
              { value: "local", label: "Local server", description: "Use an OpenAI-compatible endpoint on this machine only" },
              { value: "off", label: "No AI", description: "Disable per-story AI TL;DR actions" }
            ]
            Button {
              required property var modelData
              width: Style.space(210)
              text: String(modelData.label)
              tooltipText: String(modelData.description)
              focusable: true
              bordered: true
              selected: wizard.aiMode === String(modelData.value)
              foreground: wizard.foreground
              accent: wizard.accent
              fontFamily: wizard.fontFamily
              onClicked: wizard.aiMode = String(modelData.value)
            }
          }
        }

        Text {
          visible: wizard.aiMode === "system"
          width: parent.width
          textFormat: Text.PlainText
          text: String(wizard.systemAiStatus.message || "Checking selected agent…")
          wrapMode: Text.Wrap
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        AiModelPicker {
          width: parent.width
          visible: wizard.aiMode === "system" && wizard.systemAiStatus.available !== false
          selectedModel: wizard.systemAiModel
          selectedEffort: wizard.systemAiEffort
          catalog: wizard.aiModelCatalog
          loading: wizard.aiModelsLoading
          saving: wizard.saving
          foreground: wizard.foreground
          background: wizard.background
          accent: wizard.accent
          dim: wizard.dim
          fontFamily: wizard.fontFamily
          onDiscoveryRequested: function(refresh) { wizard.aiModelsRequested(refresh) }
          onSelectionRequested: function(model, effort) {
            wizard.systemAiModel = model
            wizard.systemAiEffort = effort
          }
        }

        TextField {
          visible: wizard.aiMode === "local"
          width: parent.width
          placeholderText: "Local server URL"
          text: wizard.localAiUrl
          foreground: wizard.foreground
          accent: wizard.accent
          font.family: wizard.fontFamily
          onTextChanged: wizard.localAiUrl = text
        }

        TextField {
          visible: wizard.aiMode === "local"
          width: parent.width
          placeholderText: "Model name"
          text: wizard.localAiModel
          foreground: wizard.foreground
          accent: wizard.accent
          font.family: wizard.fontFamily
          onTextChanged: wizard.localAiModel = text
        }

        Toggle {
          width: parent.width
          label: "Context & framing in AI summaries"
          description: "Flag supported framing concerns, quote-context limits and evidence gaps in the supplied article. No outside sources are checked. Applies to your next TL;DR."
          checked: wizard.contextFraming
          enabled: wizard.aiMode !== "off"
          foreground: wizard.foreground
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onClicked: wizard.contextFraming = !wizard.contextFraming
        }

        Toggle {
          width: parent.width
          label: "Learn from my reading choices"
          description: "Local entities and subjects with short- and long-term memory. Opens are weak; sustained reading, saves, and Show Less matter more. No cloud profile."
          checked: wizard.learnFromOpens
          foreground: wizard.foreground
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onClicked: wizard.learnFromOpens = !wizard.learnFromOpens
        }

        Toggle {
          width: parent.width
          label: "Back marks the article read"
          description: wizard.markReadOnBack
            ? "For ordinary articles, Back or Escape marks read and returns to the feed. Daily Editions pauses; Coverage returns to its timeline."
            : "Back or Escape leaves the story available in the feed."
          checked: wizard.markReadOnBack
          foreground: wizard.foreground
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onClicked: wizard.markReadOnBack = !wizard.markReadOnBack
        }

        Dropdown {
          width: Style.space(300)
          label: "Unsaved article cache"
          value: String(wizard.retentionDays)
          options: [
            { value: "30", label: "Keep 30 days" },
            { value: "90", label: "Keep 90 days" },
            { value: "180", label: "Keep 180 days" },
            { value: "365", label: "Keep one year" }
          ]
          foreground: wizard.foreground
          background: wizard.background
          accent: wizard.accent
          fontFamily: wizard.fontFamily
          onChanged: function(value) { wizard.retentionDays = Number(value) }
        }
      }

      Column {
        visible: wizard.page === 7
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Nothing here is hidden. You can reopen this wizard from Profile, inspect every learned term, export the profile as JSON, or reset learning without deleting alerts and bookmarks."
          color: wizard.dim
          font.family: wizard.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        Repeater {
          model: [
            { label: "FEED", value: String(wizard.feedStoryLimit) + " stories · " + wizard.density + " density · " + wizard.backgroundStyle + " background · follows Omarchy" },
            { label: "PLACE", value: [wizard.city, wizard.region, wizard.country].filter(function(v) { return String(v).trim() !== "" }).join(", ") || "No location boost" },
            { label: "TOPICS", value: String(wizard.mustTopics.length) + " must-see · " + String(wizard.interestedTopics.length) + " interests · " + String(wizard.mutedTopics.length) + " muted · " + String(wizard.keywordList(wizard.blockedKeywordsText).length) + " blocked keywords" },
            { label: "SOURCES", value: String(wizard.activeSourceEstimate()) + " of " + String(wizard.effectiveSourceOptions.length) + " active · " + String(wizard.disabledSourceIds.length) + " individually hidden · " + String(wizard.customSources.length) + " custom" },
            { label: "DISCOVERY", value: String(wizard.discoveryPercent) + "% outside your usual mix" },
            { label: "ALERTS", value: wizard.notificationsEnabled ? "On · quiet " + wizard.quietStart + "–" + wizard.quietEnd + " · max " + String(wizard.notificationMax) + "/day" : "Notifications off" },
            { label: "CONTEXT & FRAMING", value: wizard.aiMode === "off" ? "Inactive · AI is disabled" : (wizard.contextFraming ? "Included in requested summaries · supplied article only" : "Off") },
            { label: "AI", value: wizard.aiMode === "system" ? "System AI · " + wizard.systemAiSummary() : (wizard.aiMode === "local" ? "Local server · " + wizard.localAiModel : "Disabled") },
            { label: "ARTICLE BACK", value: wizard.markReadOnBack ? "Mark read, hide, and return to feed" : "Return without hiding" },
            { label: "LEARNING", value: wizard.learnFromOpens ? "Local reading-choice memory enabled" : "Learned curation disabled" }
          ]

          Item {
            required property var modelData
            width: pageContent.width
            height: Math.max(reviewLabel.implicitHeight, reviewValue.implicitHeight) + Style.spacing.sm

            Text {
              id: reviewLabel
              anchors.left: parent.left
              width: Style.space(125)
              textFormat: Text.PlainText
              text: String(modelData.label)
              color: wizard.accent
              font.family: wizard.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.7
            }
            Text {
              id: reviewValue
              anchors.left: reviewLabel.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: String(modelData.value)
              color: wizard.foreground
              font.family: wizard.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }

  Item {
    id: navigation
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(backButton.implicitHeight, nextButton.implicitHeight,
      validationText.implicitHeight)

    Button {
      id: backButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: wizard.page === 0 ? (wizard.existingComplete ? "Cancel" : "Exit setup") : "Back"
      iconText: wizard.page === 0 ? "󰅖" : "󰁍"
      focusable: true
      bordered: true
      foreground: wizard.foreground
      accent: wizard.accent
      fontFamily: wizard.fontFamily
      enabled: !wizard.saving
      onClicked: wizard.previousPage()
    }

    Text {
      id: validationText
      anchors.left: backButton.right
      anchors.right: nextButton.left
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: wizard.validationMessage
      color: wizard.accent
      font.family: wizard.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }

    Button {
      id: nextButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: wizard.page === wizard.pageCount - 1
        ? (wizard.saving ? "Saving…" : "Build my feed") : "Continue"
      iconText: wizard.saving ? "󰦖" : (wizard.page === wizard.pageCount - 1 ? "󰄬" : "󰁔")
      iconSpinning: wizard.saving
      focusable: true
      bordered: true
      foreground: wizard.foreground
      accent: wizard.accent
      fontFamily: wizard.fontFamily
      enabled: !wizard.saving
      onClicked: wizard.nextPage()
    }
  }
}
