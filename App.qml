import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var settings: ({})
  property bool opened: false
  property bool closingFromHost: false

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "tech.chuchua.news"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/tech.chuchua.news"
  readonly property string backendPath: pluginDir + "/bin/chuchua-news"
  readonly property string fontFamily: Style.font.family
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color dim: Color.muted

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property int refreshMinutes: Math.max(5,
    parseInt(setting("refreshMinutes", 30), 10) || 30)
  readonly property int maxArticles: Math.max(10, Math.min(100,
    parseInt(setting("maxArticles", 30), 10) || 30))
  readonly property string interests: String(setting("interests", "") || "")
  property var setupData: ({})
  property int setupRevision: 0
  property bool setupReturningToProfile: false
  readonly property var setupProfile: setupData && setupData.profile
    ? setupData.profile : ({})
  readonly property bool setupComplete: Boolean(setupProfile.complete)
  readonly property var setupAppearance: setupProfile && setupProfile.appearance
    ? setupProfile.appearance : ({})
  readonly property bool paperBackground: String(root.setupAppearance.background) === "paper"
  readonly property var footerLink: setupAppearance && setupAppearance.footer_link
    ? setupAppearance.footer_link : ({})
  readonly property string footerLinkLabel: String(footerLink.label || "").trim()
  readonly property string footerLinkUrl: String(footerLink.url || "").trim()
  readonly property bool footerLinkVisible: footerLinkLabel !== ""
    && /^https?:\/\//i.test(footerLinkUrl)
  readonly property var setupAi: setupProfile && setupProfile.ai
    ? setupProfile.ai : ({})
  readonly property var setupBehavior: setupProfile && setupProfile.behavior
    ? setupProfile.behavior : ({})
  readonly property var setupNavigation: setupProfile && setupProfile.navigation
    ? setupProfile.navigation : ({})
  readonly property var navigationItems: setupNavigation && setupNavigation.items
    ? setupNavigation.items : ["bookmarks", "history", "alerts", "refresh"]
  readonly property bool articleBackMarksRead:
    setupBehavior.mark_read_on_back !== false
  readonly property string aiProvider:
    root.setupComplete ? String(setupAi.mode || "system")
      : (String(setting("aiProvider", "System AI")) === "Local server" ? "local" : "system")
  readonly property var systemAiStatus: setupData.system_ai_status || ({})
  readonly property string systemAiModel: String(setupAi.system_model || "")
  readonly property string systemAiEffort: String(setupAi.system_effort || "")
  readonly property string systemAiModelLabel: systemAiModel || "Agent default"
  readonly property string systemAiSummary: root.systemAiModel === ""
    ? "Uses your configured model and reasoning. Each request generates a fresh summary."
    : root.systemAiModel + " · " + (root.systemAiEffort || "agent default")
      + " reasoning. Used only by PYIN; fresh summary per request."
  property var aiModelCatalog: ({})
  property int aiModelRequestRevision: 0
  property int aiModelCatalogRevision: 0
  property string aiModelRequestAgent: ""
  readonly property string systemAiAgentKey: String(systemAiStatus.agent || "") + ":" + String(systemAiStatus.available)
  onSystemAiAgentKeyChanged: {
    root.aiModelCatalogRevision++
    root.aiModelCatalog = ({})
  }
  readonly property string localAiUrl:
    root.setupComplete ? String(setupAi.local_url || "http://127.0.0.1:11434/v1")
      : String(setting("localAiUrl", "http://127.0.0.1:11434/v1"))
  readonly property string localAiModel:
    root.setupComplete ? String(setupAi.local_model || "llama3.2:3b")
      : String(setting("localAiModel", "llama3.2:3b"))
  readonly property bool aiEnabled: aiProvider !== "off"
  readonly property string aiLabel: aiProvider === "local"
    ? "Local · " + localAiModel : (aiProvider === "off" ? "AI disabled"
      : (root.systemAiStatus.available === false ? "System AI unavailable"
        : "System AI · " + root.systemAiModelLabel))
  readonly property int feedLimit: root.setupComplete && setupData.story_limit
    ? Number(setupData.story_limit) : root.maxArticles
  readonly property bool compactDensity: Boolean(root.setupComplete
    && String(root.setupAppearance.density) === "compact")
  readonly property bool storySeparators: String(root.setupAppearance.density) !== "classic"
  readonly property int storyRowHeight: compactDensity ? Style.space(88) : Style.space(112)
  readonly property int libraryStoryRowHeight: compactDensity ? Style.space(76) : Style.space(94)

  component StorySeparator: Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    height: Style.spacing.hairline
    color: root.foreground
    opacity: 0.16
  }

  readonly property bool animateLogo: root.setting("animateLogo", true) !== false
    && String(root.setting("animateLogo", true)).toLowerCase() !== "false"

  property var articles: []
  property var feedStats: ({})
  property var searchResults: []
  property var searchStats: ({})
  property string searchQuery: ""
  property var selectedTopics: []
  property var topicOptions: []
  property var alerts: []
  property var bookmarks: []
  property var historyArticles: []
  property var readArticles: []
  property int alertCount: 0
  property int bookmarkCount: 0
  property int historyCount: 0
  property int readCount: 0
  property var profileData: ({})
  property var sourceHealthData: ({})
  property bool pendingSourceHealthLoad: false
  property var applicationUpdateData: ({})
  property bool applicationUpdateCheckRemote: false
  property bool applicationUpdateLaunching: false
  property int applicationUpdateStartedTs: 0
  property int applicationUpdatePolls: 0
  property var learnedArticles: ({})
  property var readingQueue: []
  property var activeReadingEvent: null
  readonly property bool readingEventsBusy: root.activeReadingEvent !== null
    || root.readingQueue.length > 0
  property int historyRevision: 0
  property int activeHistoryRevision: 0
  property int activeBootstrapHistoryRevision: 0
  property int activeProfileHistoryRevision: 0
  property bool pendingHistoryLoad: false
  property string readingArticleId: ""
  property real readingElapsedMs: 0
  property bool readingClockRunning: false
  property bool readingEngagementRecorded: false
  property int selectedIndex: 0
  property int savedIndex: 0
  property int historyIndex: 0
  property int readIndex: 0
  property bool cursorActive: false
  property bool savedCursorActive: false
  property bool historyCursorActive: false
  property bool readCursorActive: false
  property string viewMode: "feed"
  property string returnViewMode: "feed"
  property string aboutReturnViewMode: "feed"
  property string aboutReturnStatus: ""
  property string resultTitle: ""
  property string resultText: ""
  property string resultUrl: ""
  property string resultProvider: ""
  property string resultKind: ""
  property string aiReceivedText: ""
  property string aiStreamPhase: ""
  property bool aiHasOutput: false
  property bool aiBackendDone: false
  property bool aiPresenting: false
  property bool aiCached: false
  property bool aiStreamFailed: false
  property bool aiCancelled: false
  property bool aiCursorVisible: true
  property int aiStreamSequence: 0
  readonly property bool aiBusy: aiProc.running || root.aiPresenting || root.aiCancelled
  property string statusText: "Starting…"
  property int refreshScanFrame: 0
  property string refreshOutcomeText: ""
  property string refreshOutcomeDetail: ""
  readonly property var refreshScanFrames: ["▰▱▱", "▱▰▱", "▱▱▰", "▱▰▱"]
  readonly property string refreshAgeLabel: {
    var age = String(root.feedStats.last_refresh_age || "never").trim()
    if (age === "" || age === "never") return "NEVER"
    if (age === "now") return "NOW"
    return age.toUpperCase()
  }
  readonly property string refreshChipText: refreshProc.running
    ? String(root.refreshScanFrames[root.refreshScanFrame] || "▰▱▱")
    : (root.refreshOutcomeText !== "" ? root.refreshOutcomeText : root.refreshAgeLabel)
  readonly property string refreshChipTooltip: refreshProc.running
    ? "Checking active RSS sources…"
    : (root.refreshOutcomeDetail !== ""
      ? root.refreshOutcomeDetail + " · press R to check again"
      : (root.refreshAgeLabel === "NEVER"
        ? "Check active RSS sources for new stories · R"
        : "Sources checked " + root.refreshAgeLabel.toLowerCase()
          + " ago · press R to check now"))
  property bool pendingLoad: false
  property bool pendingFeedOrderPreservation: false
  property bool activeFeedOrderPreservation: false
  property string pendingFeedLoadReason: ""
  property string activeFeedLoadReason: ""
  property string lastFeedApplyReason: ""
  property bool lastFeedOrderPreserved: false
  property var lastFeedBeforeIds: []
  property var lastFeedAfterIds: []
  property bool activeRefreshOrderPreservation: false
  property int stableFeedAppendCount: 0
  property int feedMutationRevision: 0
  property int activeFeedLoadRevision: 0
  property int activeBootstrapRevision: 0
  property var optimisticHiddenIds: ({})
  property var visualHideIds: []
  property bool visualHideFromSearch: false
  property var deferredReadMutationPayload: null
  property bool deferredReadMutationShowLess: false
  property var readMutationContext: ({})
  property var dismissMutationContext: ({})
  property bool pendingTopicSave: false
  property string aiAction: ""
  property string activeArticleId: ""
  property var activeArticle: null
  property string pendingDeepLinkArticleId: ""
  property string pendingDeepLinkView: ""
  property string activeDeepLinkArticleId: ""
  property bool confirmProfileReset: false
  property string profileTransferAction: ""
  property bool actionHudExpanded: false
  property string actionHudPage: "main"
  property int actionHudIndex: 0
  property var actionHudArticle: null
  property string tuneDirection: "more"
  property string tuneDuration: "temporary"
  property bool whySectionExpanded: false
  property var editionData: null
  property string editionError: ""
  property bool editionRequestActive: false
  property int editionRequestRevision: 0
  property string editionAction: ""
  property string editionActionArticleId: ""
  property int editionNavigationRevision: 0
  property int activeEditionNavigationRevision: 0
  property var eventData: ({})
  property var eventOrigin: null
  property bool eventArticleOpen: false
  property string eventArticleId: ""
  property int eventRevision: 0
  property int activeEventRevision: 0
  property bool eventLoadActive: false
  property bool pendingEventLoad: false
  property var eventSeenQueue: []
  property var activeEventSeen: null
  property string eventVisitError: ""
  property bool eventVisitPending: false
  property int feedbackTargetIndex: 0
  property bool pendingImpressions: false
  property string helpQuery: ""
  property string helpTab: "keys"

  onSelectedIndexChanged: root.feedbackTargetIndex = 0

  onViewModeChanged: {
    root.syncReadingEngagement()
    if (root.viewMode !== "event" && root.viewMode !== "result" && root.viewMode !== "about") {
      root.eventArticleOpen = false
      root.eventOrigin = null
      root.eventRevision++
      root.pendingEventLoad = false
      root.eventVisitPending = false
    }
    if (root.viewMode === "event") Qt.callLater(function() { root.queueEventVisit() })
    if (root.viewMode === "feed") impressionTimer.restart()
    if (!root.isArticleContext()) root.closeActionHud()
  }

  onResultKindChanged: root.syncReadingEngagement()
  onActiveArticleChanged: root.syncReadingEngagement()
  onOpenedChanged: root.syncReadingEngagement()

  readonly property var profileTopics: profileData && profileData.topics
    ? profileData.topics : []
  readonly property var profileTerms: profileData && profileData.learned_terms
    ? profileData.learned_terms : []
  readonly property var lessLikeThisTerms: profileData && profileData.less_like_this_terms
    ? profileData.less_like_this_terms : []
  readonly property var lessLikeThisSources: profileData && profileData.source_preferences
    ? profileData.source_preferences : []
  readonly property var recentSignals: profileData && profileData.recently_opened
    ? profileData.recently_opened : []
  readonly property var recentDismissals: profileData && profileData.recently_dismissed
    ? profileData.recently_dismissed : []
  readonly property var profileCounts: profileData && profileData.counts
    ? profileData.counts : ({})
  readonly property var profileStorage: profileData && profileData.storage
    ? profileData.storage : ({})
  readonly property var profileSetup: profileData && profileData.setup
    ? profileData.setup : root.setupProfile
  readonly property var profileSourceCounts: profileData && profileData.source_counts
    ? profileData.source_counts : ({})
  readonly property var profileSourceMix: profileData && profileData.source_mix
    ? profileData.source_mix : []
  readonly property var profileInterestNodes: profileData && profileData.interest_graph
    ? profileData.interest_graph : []
  readonly property var profileExposure: profileData && profileData.exposure
    ? profileData.exposure : ({})
  readonly property var helpEntries: [
    { section: "NUMBER ROW", keys: "1 / 2", action: "In Help, switch between Keys and Feed controls" },
    { section: "NUMBER ROW", keys: "-", action: "Show less news about the selected article subject" },
    { section: "NUMBER ROW", keys: "=", action: "Show more news about the selected article subject" },

    { section: "QWERTY ROW", keys: "q", action: "Close the app" },
    { section: "QWERTY ROW", keys: "e", action: "Open Coverage: cached reporting in time order, with new arrivals since your last visit" },
    { section: "QWERTY ROW", keys: "r", action: "Check active RSS sources now; the far-right freshness chip shows age, progress, and the result" },
    { section: "QWERTY ROW", keys: "t / s", action: "Create an AI TL;DR for the selected story" },
    { section: "QWERTY ROW", keys: "i / click PYIN", action: "Open the story behind the name, the app, and chuchua.tech" },
    { section: "QWERTY ROW", keys: "o", action: "Open the full article in your browser" },
    { section: "QWERTY ROW", keys: "p", action: "See the data shaping your curation profile" },

    { section: "HOME ROW", keys: "a / A", action: "Open the Article Actions HUD; choose by letter or with j/k and Enter" },
    { section: "HOME ROW", keys: "a, then u", action: "Tune the feed with a direction, exact subject or source, and duration" },
    { section: "HOME ROW", keys: "d", action: "Mark the current story read; existing cards slide up and any refill joins the bottom. Read history can restore it" },
    { section: "HOME ROW", keys: "g", action: "Open Daily Editions: a fixed 5/15/30-minute selection with saved progress. Done advances; Back pauses." },
    { section: "HOME ROW", keys: "f", action: "Follow the selected article subject as a lasting interest" },
    { section: "HOME ROW", keys: "h", action: "Open History for viewed stories and the companion Hidden list" },
    { section: "HOME ROW", keys: "j / k  or  ↓ / ↑", action: "Move through headlines without wrapping; scroll synopsis, AI results, Profile, or Help" },

    { section: "BOTTOM ROW", keys: "c", action: "Reopen setup for topics, blacklist, sources, appearance, and other choices" },
    { section: "BOTTOM ROW", keys: "v", action: "Open the Read Later list" },
    { section: "BOTTOM ROW", keys: "b  or  Esc", action: "Leave the view; article Back follows your Profile switch and can mark read + hide" },
    { section: "BOTTOM ROW", keys: "n", action: "Open subject alerts" },
    { section: "BOTTOM ROW", keys: "m", action: "Save or remove the current story from Read Later" },
    { section: "BOTTOM ROW", keys: "/", action: "Focus Search News; in Help, focus the shortcut filter" },
    { section: "BOTTOM ROW", keys: "?", action: "Show this keyboard reference" },

    { section: "NAVIGATION KEYS", keys: "Tab / Shift+Tab", action: "Move through the persistent main menu and page controls; press Enter or Space to activate the focused control" },
    { section: "NAVIGATION KEYS", keys: "Enter", action: "Open the selected story's instant RSS synopsis" },
    { section: "NAVIGATION KEYS", keys: "Backspace", action: "Dismiss the story, hide it, and teach Show Less; restoring from Read history reverses that signal" }
  ]
  readonly property var feedControlEntries: [
    { option: "MAIN MENU", effect: "Keeps the same destinations on every page. Feed, Profile, and Help stay available; optional Read Later, History, Alerts, and the far-right freshness chip can be shown or hidden in Profile → Customize." },
    { option: "REFRESH INTERVAL", effect: "Controls how often active RSS feeds are checked. Background checks preserve the cards already on screen; pressing R intentionally starts a newly ranked session." },
    { option: "DAILY EDITIONS", effect: "G opens a fixed selection with estimated synopsis reading time. Done marks read; Skip completes the slot without a negative signal. Back pauses. Refreshes never refill an edition." },
    { option: "FEED SIZE", effect: "Chooses 15, 30, or 60 stories for the main feed. Choose your reading time separately in Daily Editions. Feed size does not change story scores." },
    { option: "DENSITY", effect: "Changes how much text fits on screen. It has no ranking effect." },
    { option: "LOGO ANIMATION", effect: "Turns the occasional PYIN/NEWS split-flap animation on or off. It has no feed effect." },
    { option: "OPTIONAL FOOTER LINK", effect: "Shows one user-supplied label and HTTP/HTTPS link at the bottom right. It has no feed effect and is blank by default." },
    { option: "LOCATION", effect: "Boosts matching country, region, and city reporting; it does not exclude the rest of the world." },
    { option: "LANGUAGE", effect: "Activates catalog sources that publish in a selected language. The bundled catalog currently focuses on English." },
    { option: "MUST-SEE TOPIC", effect: "Applies the strongest setup-level positive topic boost." },
    { option: "INTERESTED TOPIC", effect: "Applies a moderate positive topic boost." },
    { option: "MUTED TOPIC", effect: "Strongly lowers matching stories but does not hard-block them." },
    { option: "KEYWORD BLACKLIST", effect: "Hard-hides exact words or phrases from ranked feeds and alert notifications. Manual Search remains unfiltered." },
    { option: "SOURCE PACK", effect: "Determines which independent, nonprofit, local, community, expert, mainstream, and other source groups are active." },
    { option: "INDIVIDUAL SOURCE", effect: "Removes that publisher from refreshes and ranked feeds when switched off." },
    { option: "CUSTOM RSS / ATOM SOURCE", effect: "Adds a user-supplied feed to the local catalog. It is eligible by default, checked during refresh, and never invokes AI." },
    { option: "OPEN-MINDED DISCOVERY", effect: "Reserves about 25% of the feed for useful reporting outside known interests." },
    { option: "BROAD DISCOVERY", effect: "Reserves about 40% of the feed for reporting outside known interests." },
    { option: "FAMILIAR-FIRST", effect: "Prioritizes chosen and learned interests while keeping an approximately 8% discovery lane." },
    { option: "OPEN SYNOPSIS", effect: "Counts as a weak interest signal when reading-choice learning is enabled." },
    { option: "AI TL;DR", effect: "Runs only on request. Requesting one is a stronger interest signal, but AI never ranks the feed." },
    { option: "READ LATER", effect: "Saves the story and contributes a reversible positive signal when learning is enabled." },
    { option: "OPEN ORIGINAL", effect: "Opens the publisher and contributes a stronger interest signal when learning is enabled." },
    { option: "MARK READ", effect: "Hides the grouped event and stays neutral for personalization. During a reading session, surviving headlines remain fixed and any replenishment enters at the bottom." },
    { option: "DISMISS & SHOW LESS", effect: "Hides the grouped event and adds reversible negative subject and publisher signals." },
    { option: "TUNE · MORE · 7 DAYS", effect: "Temporarily boosts the selected subject or source, then expires automatically." },
    { option: "TUNE · MORE · LASTING", effect: "Adds a strong positive interest that remains until removed in Profile." },
    { option: "TUNE · LESS · 7 DAYS", effect: "Temporarily suppresses the selected subject or source, then expires automatically." },
    { option: "TUNE · LESS · LASTING", effect: "Adds a lasting negative preference that remains until removed in Profile." },
    { option: "TUNE · NO SIGNAL", effect: "Removes this article's inferred open, reading, save, browser, and summary signals without saying the topic is bad." },
    { option: "SUBJECT ALERT", effect: "Notifies on matching newly fetched stories. Alerts also give matching feed stories a strong explicit boost." },
    { option: "ALERT QUIET HOURS", effect: "Suppresses desktop notifications during the chosen hours. Matching stories can still appear in the feed." },
    { option: "ALERT DAILY LIMIT", effect: "Caps desktop notifications, not matching stories or their feed scores." },
    { option: "AI PROVIDER", effect: "Chooses System AI, a loopback local server, or no AI for requested TL;DRs. It never chooses the feed order." },
    { option: "AI MODEL", effect: "Agent default follows Omarchy's selected agent and its configured model. Choose a discovered model or enter its name to override it only for PYIN. Reasoning options come from the agent. Each request generates a fresh summary; feed ranking stays local." },
    { option: "EXTRA INTEREST KEYWORDS", effect: "Adds explicit keyword boosts beyond the setup topic catalog." },
    { option: "LEARNING", effect: "When off, no new reading signals are recorded and existing inferred memory stops affecting ranking." },
    { option: "RETENTION", effect: "Controls how long ordinary cached articles and local learning history are kept. Saved stories are exempt." },
    { option: "APP UPDATES", effect: "Checks the stable Git branch only when requested. Installation requires confirmation and delegates validation, rollback, and reload to Omarchy; it never changes your local news data." },
    { option: "PERSONALIZED RANKING", effect: "One local engine combines setup choices, explicit interests, reading memory, freshness, diversity, and discovery. AI never chooses the feed order." },
    { option: "BACK ACTION", effect: "Either returns immediately and marks the article read, or returns while leaving it available. Mark Read itself stays neutral." },
    { option: "SEARCH NEWS", effect: "Searches all locally cached stories without AI, ranking personalization, blacklist filtering, or read-state filtering." },
    { option: "WHY THIS STORY", effect: "Explains the score components already used for the article. Opening it changes nothing." },
    { option: "RESET LEARNED HISTORY", effect: "Clears inferred reading and Show Less memory plus exposure records; explicit interests and hidden stories remain." },
    { option: "PROFILE EXPORT / IMPORT", effect: "Moves setup choices, custom feeds, the optional footer link, and explicit interests between devices. Reading history is not exported." }
  ]

  readonly property var visibleArticles: root.viewMode === "search"
    ? root.searchResults : root.articles
  readonly property var selectedArticle:
    visibleArticles.length > 0 && selectedIndex >= 0 && selectedIndex < visibleArticles.length
      ? visibleArticles[selectedIndex] : null
  readonly property var selectedBookmark:
    bookmarks.length > 0 && savedIndex >= 0 && savedIndex < bookmarks.length
      ? bookmarks[savedIndex] : null
  readonly property var selectedHistoryArticle:
    historyArticles.length > 0 && historyIndex >= 0 && historyIndex < historyArticles.length
      ? historyArticles[historyIndex] : null
  readonly property var selectedReadArticle:
    readArticles.length > 0 && readIndex >= 0 && readIndex < readArticles.length
      ? readArticles[readIndex] : null


  function menuItemEnabled(item) {
    return root.navigationItems.indexOf(String(item)) !== -1
  }

  function navigationContext() {
    if (root.viewMode === "event") return root.eventOrigin ? root.eventOrigin.context : "feed"
    if (root.viewMode === "result") return root.returnViewMode
    if (root.viewMode === "search") return "feed"
    if (root.viewMode === "read") return "history"
    return root.viewMode
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (payload.settings) root.settings = payload.settings
    if (payload.article_id) {
      root.pendingDeepLinkArticleId = String(payload.article_id)
      root.pendingDeepLinkView = ""
    } else if (String(payload.view || "") === "alerts") {
      root.pendingDeepLinkArticleId = ""
      root.pendingDeepLinkView = "alerts"
    }
    root.closingFromHost = false
    root.opened = true
    root.loadBootstrap()
  }

  function fulfillDeepLink() {
    if (root.pendingDeepLinkArticleId !== "") {
      if (deepLinkArticleProc.running) return
      root.activeDeepLinkArticleId = root.pendingDeepLinkArticleId
      root.pendingDeepLinkArticleId = ""
      root.statusText = "Opening alert story…"
      deepLinkArticleProc.command = [
        root.backendPath, "article", "--id", root.activeDeepLinkArticleId
      ]
      deepLinkArticleProc.running = true
      return
    }
    if (root.pendingDeepLinkView === "alerts") {
      root.pendingDeepLinkView = ""
      root.showAlerts()
    }
  }

  function loadApplicationData() {
    root.loadFeed(false, "setup-saved")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadBootstrap() {
    if (bootstrapProc.running) return
    root.statusText = "Loading your personalized news desk…"
    bootstrapProc.command = [
      root.backendPath, "bootstrap", "--interests", root.interests
    ]
    root.activeBootstrapRevision = root.feedMutationRevision
    root.activeBootstrapHistoryRevision = root.historyRevision
    bootstrapProc.running = true
  }

  function applyLibraryCounts(values, historyRevision) {
    var counts = values || ({})
    if (counts.alerts !== undefined)
      root.alertCount = Math.max(0, Number(counts.alerts || 0))
    if (counts.bookmarks !== undefined)
      root.bookmarkCount = Math.max(0, Number(counts.bookmarks || 0))
    if (historyRevision !== undefined && historyRevision === root.historyRevision) {
      if (counts.history !== undefined)
        root.historyCount = Math.max(0, Number(counts.history || 0))
      else if (counts.opened_articles !== undefined)
        root.historyCount = Math.max(0, Number(counts.opened_articles || 0))
    }
    if (counts.read !== undefined)
      root.readCount = Math.max(0, Number(counts.read || 0))
    else if (counts.read_articles !== undefined)
      root.readCount = Math.max(0, Number(counts.read_articles || 0))
  }

  function showSetup() {
    root.setupReturningToProfile = root.viewMode === "profile"
    root.viewMode = "setup"
    root.setupRevision++
    root.statusText = "Setup changes are not saved until the final page"
    Qt.callLater(function() { setupWizard.forceActiveFocus() })
  }

  function showSetupPage(page) {
    root.showSetup()
    Qt.callLater(function() {
      setupWizard.page = Math.max(0, Math.min(setupWizard.pageCount - 1, page))
      setupWizard.forceActiveFocus()
    })
  }

  function saveSetup(profile) {
    if (setupSaveProc.running) return
    root.statusText = "Saving your curation choices…"
    setupSaveProc.command = [root.backendPath, "setup", "--save-json", JSON.stringify(profile)]
    setupSaveProc.running = true
  }

  function cancelSetup() {
    if (!root.setupComplete) {
      root.requestClose()
      return
    }
    root.viewMode = root.setupReturningToProfile ? "profile" : "feed"
    root.statusText = "No setup changes were saved"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function exportProfile() {
    if (profileTransferProc.running) return
    root.profileTransferAction = "export"
    profileTransferProc.command = [
      root.backendPath, "setup", "--export",
      Quickshell.env("HOME") + "/Downloads/chuchua-news-profile.json"
    ]
    profileTransferProc.running = true
    root.statusText = "Exporting your curation profile…"
  }

  function importProfile() {
    if (profileTransferProc.running) return
    root.profileTransferAction = "import"
    profileTransferProc.command = [
      root.backendPath, "setup", "--import",
      Quickshell.env("HOME") + "/Downloads/chuchua-news-profile.json"
    ]
    profileTransferProc.running = true
    root.statusText = "Importing your curation profile…"
  }

  function close() {
    root.resetReadingEngagement("")
    root.closingFromHost = true
    root.opened = false
    root.closingFromHost = false
  }

  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  function refresh(background) {
    if (refreshProc.running) return
    var isBackground = background === true
    root.activeRefreshOrderPreservation = isBackground
    root.refreshOutcomeText = ""
    root.refreshOutcomeDetail = ""
    root.refreshScanFrame = 0
    refreshOutcomeTimer.stop()
    if (!isBackground) root.statusText = "Refreshing your active sources…"
    refreshProc.command = isBackground
      ? [root.backendPath, "refresh", "--background", "--interval-minutes",
          String(root.refreshMinutes)]
      : [root.backendPath, "refresh", "--interval-minutes",
          String(root.refreshMinutes)]
    refreshProc.running = true
  }

  function loadFeed(preserveOrder, reason) {
    // Session stability is the safe default. A caller must explicitly pass
    // false to gain permission to replace the visible ranking.
    var keepOrder = preserveOrder !== false
    var loadReason = String(reason || (keepOrder ? "session-update" : "explicit-rerank"))
    if (loadProc.running) {
      root.pendingLoad = true
      // The latest request wins. An explicit refresh or preference change can
      // still request a newly ranked order after a mutation reload was queued.
      root.pendingFeedOrderPreservation = keepOrder
      root.pendingFeedLoadReason = loadReason
      console.log("PYIN feed queued · " + loadReason + " · preserve=" + keepOrder)
      return
    }
    loadProc.command = [
      root.backendPath, "feed",
      "--limit", String(root.feedLimit),
      "--interests", root.interests
    ]
    root.activeFeedLoadRevision = root.feedMutationRevision
    root.activeFeedOrderPreservation = keepOrder
    root.activeFeedLoadReason = loadReason
    console.log("PYIN feed started · " + loadReason + " · preserve=" + keepOrder
      + " · generation=" + String(root.activeFeedLoadRevision))
    loadProc.running = true
  }

  function parsePayload(raw, fallback) {
    try { return JSON.parse(String(raw || "").trim()) }
    catch (e) { return { ok: false, error: fallback || "Invalid helper response" } }
  }

  function applyFeed(raw, preserveOrder, reason) {
    var payload = root.parsePayload(raw, "Could not read the local news cache")
    root.applyFeedPayload(payload, preserveOrder, reason)
  }

  function feedDiagnostics(unused) {
    return JSON.stringify({
      reason: root.lastFeedApplyReason,
      preserved: root.lastFeedOrderPreserved,
      appended: root.stableFeedAppendCount,
      before: root.lastFeedBeforeIds,
      after: root.lastFeedAfterIds,
      mutation_revision: root.feedMutationRevision,
      load_running: loadProc.running,
      pending_reason: root.pendingFeedLoadReason,
      view: root.viewMode,
      active_article_id: root.activeArticleId,
      pending_deep_link_id: root.pendingDeepLinkArticleId,
      active_deep_link_id: root.activeDeepLinkArticleId,
      deep_link_running: deepLinkArticleProc.running
    })
  }

  function articleIdentityIds(article) {
    var ids = []
    var seen = ({})
    function append(value) {
      var id = String(value || "")
      if (id === "" || seen[id]) return
      seen[id] = true
      ids.push(id)
    }
    if (article) append(article.id)
    var cluster = article && article.cluster_ids ? article.cluster_ids : []
    for (var i = 0; i < cluster.length; i++) append(cluster[i])
    return ids
  }

  function stableFeedMerge(current, incoming) {
    // A read/dismiss should feel like removing a card from a physical stack:
    // survivors never move relative to one another and replenishments enter at
    // the end. The next intentional refresh is free to apply a new ranking.
    var merged = []
    var represented = ({})
    function remember(article) {
      var identities = root.articleIdentityIds(article)
      for (var j = 0; j < identities.length; j++) represented[identities[j]] = true
    }
    function overlaps(article) {
      var identities = root.articleIdentityIds(article)
      for (var j = 0; j < identities.length; j++)
        if (represented[identities[j]]) return true
      return false
    }

    for (var c = 0; c < current.length; c++) {
      var currentId = String(current[c].id)
      // Keep the exact session object as well as its position. A fresh ranker
      // response may update score/reason metadata, but that should not rewrite
      // a card under the reader's eyes during a dismissal pass.
      var survivor = current[c]
      if (root.optimisticHiddenIds[currentId] || overlaps(survivor)) continue
      merged.push(survivor)
      remember(survivor)
    }

    var survivorCount = merged.length
    var targetLength = Math.max(merged.length, incoming.length)
    for (var n = 0; n < incoming.length && merged.length < targetLength; n++) {
      if (root.optimisticHiddenIds[String(incoming[n].id)] || overlaps(incoming[n]))
        continue
      merged.push(incoming[n])
      remember(incoming[n])
    }
    root.stableFeedAppendCount = Math.max(0, merged.length - survivorCount)
    return merged
  }

  function articleIndexById(values, articleId) {
    for (var i = 0; i < values.length; i++)
      if (String(values[i].id) === String(articleId)) return i
    return -1
  }

  function applyFeedPayload(payload, preserveOrder, reason) {
    if (!payload.ok) {
      root.statusText = payload.error || "Could not read the local news cache"
      return
    }
    var keepOrder = preserveOrder !== false && root.articles.length > 0
    var applyReason = String(reason || (keepOrder ? "session-update" : "explicit-rerank"))
    var beforeIds = []
    for (var beforeIndex = 0; beforeIndex < root.articles.length; beforeIndex++)
      beforeIds.push(String(root.articles[beforeIndex].id))
    var selectedId = keepOrder && root.selectedArticle
      ? String(root.selectedArticle.id) : ""
    var previousContentY = keepOrder ? headlineList.contentY : 0
    var incoming = root.withoutOptimisticHidden(payload.articles || [])
    if (!keepOrder) root.stableFeedAppendCount = 0
    root.articles = keepOrder
      ? root.stableFeedMerge(root.articles, incoming) : incoming
    root.lastFeedApplyReason = applyReason
    root.lastFeedOrderPreserved = keepOrder
    var afterIds = []
    for (var afterIndex = 0; afterIndex < root.articles.length; afterIndex++)
      afterIds.push(String(root.articles[afterIndex].id))
    root.lastFeedBeforeIds = beforeIds
    root.lastFeedAfterIds = afterIds
    console.log("PYIN feed applied · " + applyReason + " · preserve=" + keepOrder
      + " · appended=" + String(root.stableFeedAppendCount)
      + " · before=" + beforeIds.join(",") + " · after=" + afterIds.join(","))
    root.feedStats = payload.stats || ({})
    if (root.feedStats.selected_topics)
      root.selectedTopics = root.feedStats.selected_topics
    var stableSelectedIndex = selectedId === ""
      ? -1 : root.articleIndexById(root.articles, selectedId)
    root.selectedIndex = Math.max(0, Math.min(
      stableSelectedIndex >= 0 ? stableSelectedIndex : root.selectedIndex,
      root.articles.length - 1))
    var mode = root.feedStats.personalized ? "personalized" : "freshness ranked"
    var topicStatus = root.selectedTopics.length > 0
      ? " · " + root.selectedTopics.length + " topics" : " · balanced"
    var sourceStatus = root.feedStats.active_sources
      ? " · " + String(root.feedStats.active_sources) + " sources" : ""
    var readStatus = Number(root.feedStats.read_hidden || 0) > 0
      ? " · " + String(root.feedStats.read_hidden) + " read hidden" : ""
    var keywordStatus = Number(root.feedStats.keyword_hidden || 0) > 0
      ? " · " + String(root.feedStats.keyword_hidden) + " keyword blocked" : ""
    var clusterStatus = Number(root.feedStats.duplicates_collapsed || 0) > 0
      ? " · " + String(root.feedStats.duplicates_collapsed) + " repeats grouped" : ""
    var curationStatus = root.feedStats.curation_engine
      ? " · interest graph on" : ""
    var refillStatus = keepOrder && root.stableFeedAppendCount > 0
      ? " · " + String(root.stableFeedAppendCount)
        + (root.stableFeedAppendCount === 1 ? " refill added at end" : " refills added at end")
      : ""
    root.statusText = root.articles.length + " stories · " + mode + topicStatus
      + sourceStatus + clusterStatus + readStatus + keywordStatus + curationStatus
      + refillStatus + " · updated "
      + (root.feedStats.last_refresh_age || "never") + " ago"
    if (!readMutationProc.running && !dismissProc.running)
      root.optimisticHiddenIds = ({})
    Qt.callLater(function() {
      if (keepOrder) {
        headlineList.contentY = Math.max(0, Math.min(previousContentY,
          Math.max(0, headlineList.contentHeight - headlineList.height)))
      }
      impressionTimer.restart()
    })
  }

  function moveCursor(delta) {
    if ((root.viewMode !== "feed" && root.viewMode !== "search")
        || root.visibleArticles.length === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0,
      Math.min(root.visibleArticles.length - 1, root.selectedIndex + delta))
    root.feedbackTargetIndex = 0
    headlineList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function queueVisibleImpressions() {
    if (!root.measurementWindowActive() || root.viewMode !== "feed"
        || root.articles.length === 0) return
    impressionTimer.restart()
  }

  function measurementWindowActive() {
    return root.opened && window.visible && windowContent.Window.active
      && windowContent.Window.visibility !== Window.Hidden
      && windowContent.Window.visibility !== Window.Minimized
  }

  function visibleHeadlineImpressions() {
    var visible = []
    if (!headlineList.visible || headlineList.width <= 0 || headlineList.height <= 0)
      return visible
    for (var i = 0; i < headlineList.count; i++) {
      // Cached delegates can be well outside the viewport. Real geometry also
      // accounts for partial rows, spacing, density, and collapsing dismissals.
      var row = headlineList.itemAtIndex(i)
      if (!row || !row.visible || row.opacity <= 0 || row.leavingFeed
          || row.width <= 0 || row.height <= 0 || !row.modelData || !row.modelData.id)
        continue
      var bounds = row.mapToItem(headlineList, 0, 0, row.width, row.height)
      if (bounds.x < headlineList.width && bounds.x + bounds.width > 0
          && bounds.y < headlineList.height && bounds.y + bounds.height > 0)
        visible.push({ id: String(row.modelData.id), position: i + 1 })
    }
    return visible
  }

  function recordVisibleImpressions() {
    if (!root.measurementWindowActive() || root.viewMode !== "feed"
        || root.articles.length === 0) return
    if (impressionProc.running) {
      root.pendingImpressions = true
      return
    }
    var visible = root.visibleHeadlineImpressions()
    if (visible.length === 0) return
    impressionProc.command = [
      root.backendPath, "impressions", "--items-json", JSON.stringify(visible),
      "--view", "feed"
    ]
    impressionProc.running = true
  }

  function resetReadingEngagement(articleId) {
    readingEngagementTimer.stop()
    root.readingArticleId = String(articleId || "")
    root.readingElapsedMs = 0
    root.readingClockRunning = false
    root.readingEngagementRecorded = false
  }

  function syncReadingEngagement() {
    var articleId = root.viewMode === "result" && root.resultKind === "rss"
      && root.activeArticle ? String(root.activeArticle.id || "") : ""
    if (articleId !== root.readingArticleId) root.resetReadingEngagement(articleId)
    if (articleId === "" || root.readingEngagementRecorded) return

    if (!root.measurementWindowActive()) {
      if (root.readingClockRunning)
        root.readingElapsedMs += Math.max(0, readingClock.elapsedMs())
      root.readingClockRunning = false
      readingEngagementTimer.stop()
      return
    }
    if (!root.readingClockRunning) {
      readingClock.restartMs()
      root.readingClockRunning = true
    }
    var elapsed = root.readingElapsedMs + Math.max(0, readingClock.elapsedMs())
    if (elapsed >= 12000) {
      root.readingElapsedMs = 12000
      root.readingClockRunning = false
      root.readingEngagementRecorded = true
      readingEngagementTimer.stop()
      root.learnArticle(root.activeArticle, "engaged")
    } else {
      // Timer restarts discard their own elapsed time, so retain focused time
      // separately and schedule only what remains after focus returns.
      readingEngagementTimer.interval = Math.max(1, Math.ceil(12000 - elapsed))
      readingEngagementTimer.restart()
    }
  }

  function moveSavedCursor(delta) {
    if (root.viewMode !== "bookmarks" || root.bookmarks.length === 0) return
    root.savedCursorActive = true
    root.savedIndex = (root.savedIndex + delta + root.bookmarks.length)
      % root.bookmarks.length
    savedList.positionViewAtIndex(root.savedIndex, ListView.Contain)
  }

  function moveHistoryCursor(delta) {
    if (root.viewMode !== "history" || root.historyArticles.length === 0) return
    root.historyCursorActive = true
    root.historyIndex = Math.max(0,
      Math.min(root.historyArticles.length - 1, root.historyIndex + delta))
    historyList.positionViewAtIndex(root.historyIndex, ListView.Contain)
  }

  function moveReadCursor(delta) {
    if (root.viewMode !== "read" || root.readArticles.length === 0) return
    root.readCursorActive = true
    root.readIndex = Math.max(0,
      Math.min(root.readArticles.length - 1, root.readIndex + delta))
    readList.positionViewAtIndex(root.readIndex, ListView.Contain)
  }

  function learnArticle(article, signal) {
    if (!article || !article.id) return
    var signalName = String(signal || "open")
    var signalKey = String(article.id) + ":" + signalName
    if (signalName !== "open") {
      if (root.learnedArticles[signalKey]) return
      var next = ({})
      for (var key in root.learnedArticles) next[key] = true
      next[signalKey] = true
      root.learnedArticles = next
    } else {
      // A view is an event; learning remains deduplicated by the backend.
      root.historyRevision++
      root.feedMutationRevision++
    }
    root.readingQueue = root.readingQueue.concat([{
      articleId: String(article.id), signal: signalName, signalKey: signalKey
    }])
    root.startNextReadingEvent()
  }

  function startNextReadingEvent() {
    if (readingEventProc.running || root.activeReadingEvent !== null
        || profileResetProc.running || feedbackProc.running) return
    if (root.readingQueue.length === 0) {
      if (root.pendingHistoryLoad && root.viewMode === "history" && !historyProc.running)
        root.loadHistory()
      return
    }
    root.activeReadingEvent = root.readingQueue[0]
    root.readingQueue = root.readingQueue.slice(1)
    readingEventProc.command = [
      root.backendPath, "opened", "--id", root.activeReadingEvent.articleId,
      "--signal", root.activeReadingEvent.signal
    ]
    readingEventProc.running = true
  }

  function articlesWithViewState(values, payload) {
    return (values || []).map(function(article) {
      if (String(article.id) !== String(payload.article_id)) return article
      var updated = ({})
      for (var key in article) updated[key] = article[key]
      updated.opened = Number(payload.opens || 0) > 0
      updated.opens = Number(payload.opens || 0)
      updated.last_opened_ts = payload.last_opened_ts
      return updated
    })
  }

  function finishReadingEvent(payload) {
    var event = root.activeReadingEvent
    if (!event) return
    root.activeReadingEvent = null
    if (event.signal !== "open" && (!payload.ok || payload.learning_enabled === false)) {
      var next = ({})
      for (var key in root.learnedArticles)
        if (key !== event.signalKey) next[key] = true
      root.learnedArticles = next
    }
    if (!payload.ok) {
      root.statusText = payload.error || "Could not save reading history"
    } else {
      if (event.signal === "open") {
        root.historyRevision++
        root.feedMutationRevision++
        root.applyLibraryCounts(payload.counts, root.historyRevision)
        root.articles = root.articlesWithViewState(root.articles, payload)
        root.searchResults = root.articlesWithViewState(root.searchResults, payload)
        root.bookmarks = root.articlesWithViewState(root.bookmarks, payload)
        root.historyArticles = root.articlesWithViewState(root.historyArticles, payload)
        root.readArticles = root.articlesWithViewState(root.readArticles, payload)
        if (root.activeArticle)
          root.activeArticle = root.articlesWithViewState([root.activeArticle], payload)[0]
        root.patchEventArticle(payload.article_id, {
          opened: Number(payload.opens || 0) > 0,
          opens: Number(payload.opens || 0), last_opened_ts: payload.last_opened_ts
        })
        root.pendingHistoryLoad = true
      }
      if (event.signal === "open" || payload.applied) openedReload.restart()
    }
    Qt.callLater(function() { root.startNextReadingEvent() })
  }

  function openSelected() {
    root.showArticle(root.selectedArticle)
  }

  function resetAiPresentation() {
    aiPresentationTimer.stop()
    root.aiReceivedText = ""
    root.aiStreamPhase = ""
    root.aiHasOutput = false
    root.aiBackendDone = false
    root.aiPresenting = false
    root.aiCached = false
    root.aiStreamFailed = false
    root.aiCancelled = false
    root.aiCursorVisible = true
    root.aiStreamSequence = 0
  }

  function cancelAiRequest() {
    aiPresentationTimer.stop()
    root.aiPresenting = false
    root.aiBackendDone = false
    root.aiHasOutput = false
    root.aiReceivedText = ""
    root.aiStreamPhase = ""
    if (aiProc.running) {
      root.aiCancelled = true
      aiProc.running = false
    } else root.aiCancelled = false
  }

  function finishAiPresentation() {
    if (root.aiStreamFailed) return
    aiPresentationTimer.stop()
    root.resultText = root.aiReceivedText
    root.aiPresenting = false
    root.aiStreamPhase = root.aiCached ? "SAVED TL;DR READY" : "SOURCE-BOUND TL;DR READY"
    root.statusText = (root.aiCached ? "Cached summary" : "AI answer ready")
      + " · " + root.resultProvider
  }

  function revealAiText() {
    if (root.aiStreamFailed) {
      aiPresentationTimer.stop()
      return
    }
    var backlog = root.aiReceivedText.length - root.resultText.length
    if (backlog <= 0) {
      aiPresentationTimer.stop()
      if (root.aiBackendDone) root.finishAiPresentation()
      return
    }

    // Adaptive easing keeps real token streams immediate and cached summaries
    // brisk without dumping an entire paragraph into the layout at once.
    var count = backlog > 900 ? 36
      : (backlog > 420 ? 20
        : (backlog > 180 ? 11
          : (backlog > 72 ? 6 : (backlog > 24 ? 3 : 2))))
    var nextLength = Math.min(root.aiReceivedText.length,
      root.resultText.length + count)
    root.resultText = root.aiReceivedText.slice(0, nextLength)
    if (nextLength >= root.aiReceivedText.length) {
      if (root.aiBackendDone) root.finishAiPresentation()
      else aiPresentationTimer.stop()
    }
  }

  function failAiStream(message) {
    if (root.aiStreamFailed || root.aiCancelled) return
    aiPresentationTimer.stop()
    root.aiStreamFailed = true
    root.aiBackendDone = true
    root.aiPresenting = false
    root.aiHasOutput = true
    root.aiStreamPhase = "STREAM INTERRUPTED"
    var detail = String(message || "AI request failed")
    var partial = root.aiReceivedText.trim()
    root.resultText = partial
      ? partial + "\n\n[INCOMPLETE DRAFT — STREAM INTERRUPTED]\n" + detail
      : "AI ERROR\n\n" + detail
    root.statusText = "AI request failed"
  }

  function handleAiStreamLine(raw) {
    var line = String(raw || "").trim()
    if (!line || root.aiCancelled) return
    var payload
    try { payload = JSON.parse(line) }
    catch (e) { return }
    var event = String(payload.event || "")
    if (event === "meta") {
      root.aiCached = Boolean(payload.cached)
      var metaProvider = String(payload.provider || root.aiLabel)
      root.resultProvider = metaProvider
        + (payload.source_bounded ? " · source-bounded" : "")
      return
    }
    if (event === "status") {
      root.aiStreamPhase = String(payload.label || "PREPARING SOURCE-BOUND TL;DR")
      return
    }
    if (event === "delta") {
      var delta = String(payload.delta || "")
      if (!delta) return
      root.aiReceivedText += delta
      root.aiStreamSequence = Math.max(root.aiStreamSequence + 1,
        Number(payload.sequence || 0))
      root.aiStreamPhase = root.aiCached ? "REPLAYING SAVED TL;DR" : "LIVE MODEL DRAFT"
      if (!root.aiHasOutput) {
        root.aiHasOutput = true
        // Reveal the first glyph in the same event turn; the timer smooths the rest.
        root.resultText = root.aiReceivedText.slice(0, 1)
      }
      root.aiPresenting = true
      aiPresentationTimer.restart()
      return
    }
    if (event === "done") {
      root.aiCached = Boolean(payload.cached)
      root.aiBackendDone = true
      var finalText = String(payload.text || "")
      if (finalText) root.aiReceivedText = finalText
      var doneProvider = String(payload.provider || root.aiLabel)
      root.resultProvider = doneProvider
        + (payload.source_bounded ? " · source-bounded" : "")
      if (!root.aiHasOutput && root.aiReceivedText.length > 0) {
        root.aiHasOutput = true
        root.resultText = root.aiReceivedText.slice(0, 1)
      }
      root.aiStreamPhase = root.aiCached ? "REPLAYING SAVED TL;DR" : "FINISHING SOURCE DESK EDIT"
      root.aiPresenting = true
      if (root.resultText.length >= root.aiReceivedText.length)
        root.finishAiPresentation()
      else aiPresentationTimer.restart()
      return
    }
    if (event === "error") root.failAiStream(payload.error || "AI request failed")
  }

  function showEditions() {
    root.cancelAiRequest()
    root.closeActionHud()
    root.editionNavigationRevision++
    root.viewMode = "edition"
    root.statusText = "Daily Editions · a fixed selection and a clear finish"
    root.runEdition([], "load", "")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function runEdition(args, action, articleId) {
    if (root.editionRequestActive) return false
    root.editionRequestActive = true
    root.editionRequestRevision++
    var revision = root.editionRequestRevision
    root.editionError = ""
    root.editionAction = action
    root.editionActionArticleId = String(articleId || "")
    root.activeEditionNavigationRevision = root.editionNavigationRevision
    editionProc.command = [root.backendPath, "edition"].concat(args)
    editionProc.running = true
    Qt.callLater(function() { root.checkEditionLaunch(revision) })
    return true
  }

  function checkEditionLaunch(revision) {
    if (root.editionRequestActive && revision === root.editionRequestRevision && !editionProc.running) {
      root.editionRequestActive = false
      root.acceptEdition({ok: false, error: "Could not save or load your edition. Please retry."})
    }
  }

  function startEdition(minutes) {
    root.runEdition(["--create", String(minutes), "--interests", root.interests], "create", "")
  }

  function openEditionArticle(article) {
    if (!article || !root.editionData) return
    root.runEdition(["--id", String(root.editionData.id), "--open", String(article.id)], "open", article.id)
  }

  function editionReaderActive() {
    return root.viewMode === "result" && root.returnViewMode === "edition"
      && !root.eventArticleOpen && root.activeArticle !== null
      && root.editionData !== null
      && (root.editionData.articles || []).some(function(a) {
        return String(a.id) === String(root.activeArticle.id)
      })
  }

  function completeEditionStory(action) {
    if (!root.editionReaderActive() || root.aiBusy) return
    root.runEdition(["--id", String(root.editionData.id), "--" + action,
      String(root.activeArticle.id)], action, root.activeArticle.id)
  }

  function acceptEdition(payload) {
    if (!payload.ok) {
      root.editionError = String(payload.error || "Could not load your edition")
      root.statusText = root.editionError
      return
    }
    if (payload.counts) root.applyLibraryCounts(payload.counts)
    root.editionData = payload.edition || null
    var sameVisit = root.activeEditionNavigationRevision === root.editionNavigationRevision
    var items = root.editionData ? root.editionData.articles || [] : []
    if (sameVisit && root.editionAction === "open" && root.viewMode === "edition") {
      var article = items.find(function(a) { return String(a.id) === root.editionActionArticleId })
      if (article) {
        root.showArticle(article)
        resultScroll.contentY = 0
      }
    } else if (root.editionAction === "done" || root.editionAction === "skip") {
      root.loadFeed(true, "edition-progress")
      if (sameVisit && root.editionReaderActive()
          && String(root.activeArticle.id) === root.editionActionArticleId) {
        var next = items.find(function(a) { return a.edition_status === "pending" })
        if (next) { root.showArticle(next); resultScroll.contentY = 0 }
        else root.backToFeed()
      }
    }
  }

  function showArticle(article) {
    if (!article || root.aiCancelled) return
    if (root.viewMode !== "result" && root.viewMode !== "event") {
      root.eventOrigin = null
      root.eventArticleOpen = false
    }
    root.resetReadingEngagement("")
    root.resetAiPresentation()
    root.closeActionHud()
    root.whySectionExpanded = false
    root.feedbackTargetIndex = 0
    root.learnArticle(article, "open")
    if (root.viewMode !== "result" && root.viewMode !== "event")
      root.returnViewMode = root.viewMode === "edition" ? "edition"
        : root.viewMode === "bookmarks" ? "bookmarks"
        : (root.viewMode === "history" ? "history"
          : (root.viewMode === "read" ? "read"
          : (root.viewMode === "search" ? "search" : "feed"))
        )
    root.activeArticle = article
    root.activeArticleId = String(article.id)
    root.resultKind = "rss"
    root.resultTitle = String(article.title)
    root.resultUrl = String(article.url || "")
    root.resultProvider = String(article.source || "Source")
      + " · RSS synopsis · " + String(article.age || "")
      + (Number(article.coverage_count || 1) > 1
        ? " · " + String(article.coverage_count) + " sources" : "")
    root.resultText = String(article.synopsis || article.summary
      || "This feed did not include a synopsis. You can open the article or request an AI TL;DR.")
    root.statusText = "RSS synopsis · no AI used"
    root.viewMode = "result"
    root.syncReadingEngagement()
  }

  function showEventDesk() {
    if (root.aiBusy || profileResetProc.running) return
    if (root.eventArticleOpen && root.viewMode === "result") {
      root.returnToEventDesk()
      return
    }
    var article = root.currentArticle()
    if (!root.isArticleContext() || !article) return
    root.eventOrigin = {
      view: root.viewMode, context: root.navigationContext(),
      article: root.activeArticle, articleId: root.activeArticleId,
      title: root.resultTitle, text: root.resultText, url: root.resultUrl,
      provider: root.resultProvider, kind: root.resultKind,
      returnView: root.returnViewMode, scroll: resultScroll.contentY
    }
    root.closeActionHud()
    root.eventRevision++
    root.eventArticleId = String(article.id)
    root.eventData = ({})
    root.eventVisitError = ""
    root.eventVisitPending = false
    root.eventArticleOpen = false
    root.viewMode = "event"
    eventPage.resetPosition()
    root.loadEventDesk()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadEventDesk() {
    if (root.viewMode !== "event") return
    if (eventProc.running || root.eventLoadActive) {
      root.pendingEventLoad = true
      return
    }
    root.pendingEventLoad = false
    root.activeEventRevision = root.eventRevision
    root.eventLoadActive = true
    eventProc.command = [root.backendPath, "event", "--article-id", root.eventArticleId]
    eventProc.running = true
  }

  function finishEventLoad(payload) {
    if (!root.eventLoadActive) return
    root.eventLoadActive = false
    var revision = root.activeEventRevision
    if (root.viewMode === "event" && revision === root.eventRevision) {
      root.eventData = payload
      root.statusText = payload.ok ? "Coverage · cached reporting · no AI used"
        : String(payload.error || "Could not load event coverage")
      if (payload.ok && Number(payload.seen_through) > 0) {
        root.eventVisitPending = true
        Qt.callLater(function() {
          if (revision === root.eventRevision) root.queueEventVisit()
        })
      }
    }
    if (root.pendingEventLoad && root.viewMode === "event")
      Qt.callLater(function() { root.loadEventDesk() })
  }

  function startNextEventSeen() {
    if (eventSeenProc.running || root.activeEventSeen || root.eventSeenQueue.length === 0) return
    root.activeEventSeen = root.eventSeenQueue[0]
    root.eventSeenQueue = root.eventSeenQueue.slice(1)
    eventSeenProc.command = [root.backendPath, "event-seen", "--id", root.activeEventSeen.id,
      "--through", String(root.activeEventSeen.through)]
    eventSeenProc.running = true
  }

  function queueEventVisit() {
    if (!root.eventVisitPending || root.viewMode !== "event"
        || !root.measurementWindowActive() || !root.eventData.ok) return
    root.eventVisitPending = false
    root.eventSeenQueue = root.eventSeenQueue.concat([{
      id: String(root.eventData.event_id), through: Number(root.eventData.seen_through)
    }])
    root.startNextEventSeen()
  }

  function finishEventSeen(payload) {
    if (!root.activeEventSeen) return
    if (!payload.ok && root.activeEventSeen.id === String(root.eventData.event_id))
      root.eventVisitError = "Visit could not be saved. New markers may repeat next time."
    root.activeEventSeen = null
    Qt.callLater(function() { root.startNextEventSeen() })
  }

  function showEventArticle(article) {
    if (root.viewMode !== "event" || !article) return
    root.returnViewMode = root.eventOrigin ? root.eventOrigin.context : "feed"
    root.showArticle(article)
    root.eventArticleOpen = true
    resultScroll.contentY = 0
  }

  function returnToEventDesk() {
    root.cancelAiRequest()
    root.eventArticleOpen = false
    root.viewMode = "event"
    root.statusText = "Coverage · cached reporting · no AI used"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function leaveEventDesk() {
    var origin = root.eventOrigin
    root.eventRevision++
    root.pendingEventLoad = false
    root.eventVisitPending = false
    root.eventArticleOpen = false
    root.eventOrigin = null
    if (!origin) { root.showMainFeed(); return }
    root.activeArticle = origin.article
    root.activeArticleId = origin.articleId
    root.resultTitle = origin.title
    root.resultText = origin.text
    root.resultUrl = origin.url
    root.resultProvider = origin.provider
    root.resultKind = origin.kind
    root.returnViewMode = origin.returnView
    root.viewMode = origin.view
    if (origin.view === "history") root.loadHistory()
    resultScroll.contentY = origin.scroll
    root.statusText = origin.view === "result"
      ? (origin.kind === "ai" ? "Saved AI result" : "RSS synopsis · no AI used")
      : "PYIN · your news, your choices"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function patchEventArticle(articleId, changes) {
    function patch(article) {
      if (!article || String(article.id) !== String(articleId)) return article
      var updated = ({})
      for (var key in article) updated[key] = article[key]
      for (var changed in changes) updated[changed] = changes[changed]
      return updated
    }
    if (root.eventData.ok) {
      var next = ({})
      for (var key in root.eventData) next[key] = root.eventData[key]
      next.articles = (next.articles || []).map(patch).filter(function(article) {
        return !article.dismissed
      })
      next.article_count = next.articles.length
      next.new_count = next.articles.filter(function(article) { return article.is_new }).length
      var sources = ({})
      for (var i = 0; i < next.articles.length; i++) sources[String(next.articles[i].source)] = true
      next.source_count = Object.keys(sources).length
      root.eventData = next
    }
    if (root.eventOrigin && root.eventOrigin.article) {
      var origin = ({})
      for (var field in root.eventOrigin) origin[field] = root.eventOrigin[field]
      origin.article = patch(origin.article)
      root.eventOrigin = origin
    }
  }

  function openArticle() {
    var article = root.viewMode === "result"
      ? root.activeArticle
      : (root.viewMode === "bookmarks" ? root.selectedBookmark
        : (root.viewMode === "history" ? root.selectedHistoryArticle
          : (root.viewMode === "read" ? root.selectedReadArticle : root.selectedArticle)))
    var url = root.resultUrl || (article ? String(article.url || "") : "")
    if (!url) return
    if (article) root.learnArticle(article, "external")
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function summarizeSelected() {
    root.summarizeArticle(root.selectedArticle)
  }

  function summarizeArticle(article) {
    if (!article || root.aiBusy) return
    if (!root.aiEnabled) {
      root.statusText = "AI is disabled in Profile → Edit setup"
      return
    }
    if (root.aiProvider === "system" && root.systemAiStatus.available === false) {
      root.statusText = String(root.systemAiStatus.message || "System AI is unavailable")
      return
    }
    root.learnArticle(article, "summary")
    if (root.viewMode !== "result")
      root.returnViewMode = root.viewMode === "edition" ? "edition"
        : root.viewMode === "bookmarks" ? "bookmarks"
        : (root.viewMode === "history" ? "history"
          : (root.viewMode === "read" ? "read"
          : (root.viewMode === "search" ? "search" : "feed"))
        )
    root.activeArticle = article
    root.activeArticleId = String(article.id)
    root.closeActionHud()
    root.resetAiPresentation()
    root.aiPresenting = true
    root.aiStreamPhase = "PREPARING SOURCE DESK"
    root.aiAction = "summary"
    root.resultKind = "ai"
    root.resultTitle = String(article.title)
    root.resultUrl = String(article.url)
    root.resultProvider = root.aiLabel + " · source-bounded"
    root.resultText = ""
    root.viewMode = "result"
    aiProc.command = root.aiCommand("summarize",
      ["--id", String(article.id), "--stream"])
    aiProc.running = true
  }

  function searchNews() {
    var query = searchField.text.trim()
    if (query.length < 2 || searchProc.running) return
    root.searchQuery = query
    root.searchResults = []
    root.searchStats = ({})
    root.selectedIndex = 0
    root.viewMode = "search"
    root.statusText = "Searching every cached source · no AI used…"
    searchProc.command = [root.backendPath, "search", "--query", query, "--limit", "80"]
    searchProc.running = true
    keyCatcher.forceActiveFocus()
  }

  function clearSearch() {
    searchField.text = ""
    root.searchQuery = ""
    root.searchResults = []
    root.searchStats = ({})
    root.viewMode = "feed"
    root.loadFeed(true, "search-cleared")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function aiCommand(action, actionArgs) {
    var command = [root.backendPath, action]
    for (var i = 0; i < actionArgs.length; i++) command.push(actionArgs[i])
    command.push("--provider", root.aiProvider)
    command.push("--system-model", root.systemAiModel)
    command.push("--system-effort", root.systemAiEffort)
    command.push("--local-url", root.localAiUrl)
    command.push("--local-model", root.localAiModel)
    return command
  }

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function loadPreferences() {
    if (preferencesProc.running) return
    preferencesProc.command = [root.backendPath, "preferences"]
    preferencesProc.running = true
  }

  function saveTopics(values) {
    root.selectedTopics = values || []
    if (savePreferencesProc.running) {
      root.pendingTopicSave = true
      return
    }
    savePreferencesProc.command = [
      root.backendPath, "preferences", "--set-topics",
      JSON.stringify(root.selectedTopics)
    ]
    savePreferencesProc.running = true
    root.statusText = root.selectedTopics.length > 0
      ? "Updating your topic mix…" : "Switching to a balanced feed…"
  }

  function loadAlerts() {
    if (alertsProc.running) return
    alertsProc.command = [root.backendPath, "alerts"]
    alertsProc.running = true
  }

  function showAlerts() {
    root.viewMode = "alerts"
    root.loadAlerts()
    Qt.callLater(function() { alertField.forceActiveFocus() })
  }

  function loadBookmarks() {
    if (bookmarksProc.running) return
    bookmarksProc.command = [root.backendPath, "bookmarks"]
    bookmarksProc.running = true
  }

  function showBookmarks() {
    root.viewMode = "bookmarks"
    root.loadBookmarks()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadHistory() {
    if (historyProc.running || root.readingEventsBusy || profileResetProc.running) {
      root.pendingHistoryLoad = true
      return
    }
    root.pendingHistoryLoad = false
    root.activeHistoryRevision = root.historyRevision
    historyProc.command = [root.backendPath, "history", "--limit", "500"]
    historyProc.running = true
  }

  function applyHistoryPayload(payload) {
    if (root.activeHistoryRevision !== root.historyRevision
        || root.readingEventsBusy || profileResetProc.running) {
      root.pendingHistoryLoad = true
      return
    }
    if (!payload.ok) root.statusText = payload.error || "Could not load viewed history"
    else {
      root.historyArticles = payload.articles || []
      root.historyCount = payload.count !== undefined
        ? Number(payload.count) : root.historyArticles.length
      root.historyIndex = Math.max(0,
        Math.min(root.historyIndex, root.historyArticles.length - 1))
      if (root.viewMode === "history")
        root.statusText = String(root.historyCount) + " viewed stories · stored locally"
    }
  }

  function showHistory() {
    root.viewMode = "history"
    root.loadHistory()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadReadArticles() {
    if (readProc.running) return
    readProc.command = [root.backendPath, "read"]
    readProc.running = true
  }

  function showReadArticles() {
    root.viewMode = "read"
    root.loadReadArticles()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadProfile() {
    if (profileProc.running) return
    profileProc.command = [root.backendPath, "profile"]
    root.activeProfileHistoryRevision = root.historyRevision
    profileProc.running = true
  }

  function loadSourceHealth() {
    if (sourceHealthProc.running) {
      root.pendingSourceHealthLoad = true
      return
    }
    root.pendingSourceHealthLoad = false
    sourceHealthProc.command = [root.backendPath, "sources", "--health"]
    sourceHealthProc.running = true
  }

  function loadApplicationUpdateStatus(checkRemote) {
    if (updateStatusProc.running) return
    root.applicationUpdateCheckRemote = Boolean(checkRemote)
    var command = [root.backendPath, "updates"]
    if (checkRemote) command.push("--check")
    updateStatusProc.command = command
    updateStatusProc.running = true
    if (checkRemote) root.statusText = "Checking the stable PYIN release…"
  }

  function installApplicationUpdate() {
    if (root.applicationUpdateLaunching
        || !Boolean(root.applicationUpdateData.can_install)) return
    root.applicationUpdateLaunching = true
    root.applicationUpdateStartedTs = Math.floor(Date.now() / 1000)
    root.applicationUpdatePolls = 0
    profilePage.confirmUpdate = false
    root.statusText = "Updating through Omarchy · PYIN will reload when verified"
    Quickshell.execDetached([root.backendPath, "updates", "--install"])
  }

  function showProfile() {
    root.confirmProfileReset = false
    root.viewMode = "profile"
    profilePage.resetSections()
    root.loadProfile()
    root.loadApplicationUpdateStatus(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setNavigationItemEnabled(item, enabled) {
    if (navigationProc.running) return
    var key = String(item)
    var next = []
    for (var i = 0; i < root.navigationItems.length; i++) {
      var value = String(root.navigationItems[i])
      if (value !== key && next.indexOf(value) === -1) next.push(value)
    }
    if (enabled && next.indexOf(key) === -1) next.push(key)
    navigationProc.command = [
      root.backendPath, "setup", "--navigation-json", JSON.stringify(next)
    ]
    navigationProc.running = true
    root.statusText = "Saving your main-menu layout…"
  }

  function setFooterLink(label, url) {
    if (footerLinkProc.running) return
    var requested = {
      label: String(label || "").trim(),
      url: String(url || "").trim()
    }
    footerLinkProc.command = [
      root.backendPath, "setup", "--footer-link-json", JSON.stringify(requested)
    ]
    footerLinkProc.running = true
    profilePage.footerLinkMessage = requested.label === "" && requested.url === ""
      ? "Clearing footer link…" : "Saving footer link…"
    root.statusText = profilePage.footerLinkMessage
  }

  function feedbackTargetsForArticle(article) {
    var value = article || root.currentArticle()
    var sourceTargets = value && value.feedback_targets ? value.feedback_targets : []
    var targets = []
    for (var i = 0; i < sourceTargets.length; i++) targets.push(sourceTargets[i])
    var source = value ? String(value.source || "").trim() : ""
    if (source !== "") {
      var sourceKey = "source:" + source.toLowerCase()
      var found = false
      for (var j = 0; j < targets.length; j++)
        if (String(targets[j].key || "") === sourceKey) found = true
      if (!found) targets.push({
        key: sourceKey, label: source, kind: "source", weight: 0, scopes: []
      })
    }
    return targets
  }

  function activeFeedbackTarget(article) {
    var targets = root.feedbackTargetsForArticle(article)
    if (targets.length === 0)
      return { key: "", label: "this story", kind: "story", weight: 0, scopes: [] }
    var index = Math.max(0, Math.min(targets.length - 1, root.feedbackTargetIndex))
    return targets[index]
  }

  function cycleFeedbackTarget(step) {
    var article = root.actionHudArticle || root.activeArticle || root.currentArticle()
    var targets = root.feedbackTargetsForArticle(article)
    if (targets.length < 2) return
    var direction = Number(step || 1) < 0 ? -1 : 1
    root.feedbackTargetIndex = Math.max(0,
      Math.min(targets.length - 1, root.feedbackTargetIndex + direction))
    root.statusText = "Tune target · "
      + String(root.activeFeedbackTarget(article).label || "this story")
  }

  function openActionHud(article) {
    var value = article || root.currentArticle()
    if (!value || root.viewMode === "setup" || root.aiBusy) return
    root.actionHudArticle = value
    root.actionHudPage = "main"
    root.actionHudIndex = 0
    root.feedbackTargetIndex = 0
    root.tuneDirection = "more"
    root.tuneDuration = "temporary"
    root.actionHudExpanded = true
    root.statusText = "Article Actions · choose a letter or use j/k and Enter"
    Qt.callLater(function() {
      actionHudScroll.contentY = 0
      keyCatcher.forceActiveFocus()
    })
  }

  function closeActionHud() {
    root.actionHudExpanded = false
    root.actionHudPage = "main"
    root.actionHudIndex = 0
    root.actionHudArticle = null
  }

  function stepBackActionHud() {
    if (root.actionHudPage === "tune") {
      root.actionHudPage = "main"
      root.actionHudIndex = 0
      root.statusText = "Article Actions · choose a letter or use j/k and Enter"
      Qt.callLater(function() { actionHudScroll.contentY = 0 })
    } else root.closeActionHud()
  }

  function actionHudActions() {
    var article = root.actionHudArticle
    if (!article) return []
    var actions = []
    if (root.aiEnabled) actions.push({
      key: "summary", hotkey: "S", icon: root.resultKind === "ai" ? "󰓰" : "󰚩",
      label: root.viewMode === "result" && root.resultKind === "ai"
        ? "RSS synopsis" : "AI TL;DR",
      hint: root.viewMode === "result" && root.resultKind === "ai"
        ? "Return to the feed-provided synopsis."
        : "Create an on-demand, source-bounded summary."
    })
    actions.push({
      key: "bookmark", hotkey: "M",
      icon: Boolean(article.bookmarked) ? "󰆴" : "󰃀",
      label: Boolean(article.bookmarked) ? "Remove saved" : "Read later",
      hint: Boolean(article.bookmarked)
        ? "Remove this story from Read Later."
        : "Save this story without otherwise changing its feed position."
    })
    if (String(article.url || root.resultUrl || "") !== "") actions.push({
      key: "open", hotkey: "O", icon: "󰏌", label: "Open original",
      hint: "Open the publisher's page in your browser."
    })
    actions.push({
      key: "read", hotkey: "D",
      icon: Boolean(article.read) ? "󰁍" : "󰄬",
      label: Boolean(article.read) ? "Restore to feed" : "Mark read & hide",
      hint: Boolean(article.read)
        ? "Restore this event to the ranked feed."
        : "Hide this event without teaching PYIN that you dislike its subject."
    })
    actions.push({
      key: "tune", hotkey: "U", icon: "󰒕", label: "Tune your feed",
      hint: "Choose more or less, the exact subject or source, and how long."
    })
    if (!Boolean(article.read)) actions.push({
      key: "dismiss", hotkey: "X", icon: "󰅖", label: "Dismiss & show less",
      hint: "Hide this event and add a reversible Show Less signal."
    })
    return actions
  }

  function selectedActionHudItem() {
    var actions = root.actionHudActions()
    if (actions.length === 0) return ({})
    var index = Math.max(0, Math.min(actions.length - 1, root.actionHudIndex))
    return actions[index]
  }

  function moveActionHud(delta) {
    if (root.actionHudPage === "tune") {
      root.cycleFeedbackTarget(delta)
      return
    }
    var actions = root.actionHudActions()
    if (actions.length === 0) return
    root.actionHudIndex = Math.max(0,
      Math.min(actions.length - 1, root.actionHudIndex + (delta < 0 ? -1 : 1)))
  }

  function runActionHudSelection() {
    if (root.actionHudPage === "tune") {
      root.applyTuneFeedback()
      return
    }
    var item = root.selectedActionHudItem()
    if (item.key) root.runActionHudAction(String(item.key))
  }

  function handleActionHudKey(textValue) {
    var text = String(textValue || "")
    var key = text.toLowerCase()
    if (text === "?") {
      root.closeActionHud()
      root.showHelp()
      return
    }
    if (key === "b") {
      root.stepBackActionHud()
      return
    }
    if (root.actionHudPage === "tune") {
      if (text === "+" || text === "=" || key === "m")
        root.tuneDirection = "more"
      else if (text === "-" || key === "l") root.tuneDirection = "less"
      else if (text === "0" || key === "n") root.tuneDirection = "neutral"
      else if (text === "7") root.tuneDuration = "temporary"
      else if (key === "p") root.tuneDuration = "lasting"
      else if (key === "j" || text === "[") root.cycleFeedbackTarget(-1)
      else if (key === "k" || text === "]") root.cycleFeedbackTarget(1)
      return
    }
    if (key === "a") {
      root.closeActionHud()
      return
    }
    if (key === "t") key = "s"
    var actions = root.actionHudActions()
    for (var i = 0; i < actions.length; i++) {
      if (String(actions[i].hotkey || "").toLowerCase() === key) {
        root.actionHudIndex = i
        root.runActionHudAction(String(actions[i].key))
        return
      }
    }
  }

  function runActionHudAction(key) {
    var article = root.actionHudArticle
    if (!article) {
      root.closeActionHud()
      return
    }
    if (key === "tune") {
      root.actionHudPage = "tune"
      root.statusText = "Tune feed · direction, target, duration, then Enter"
      Qt.callLater(function() { actionHudScroll.contentY = 0 })
      return
    }
    root.closeActionHud()
    if (key === "summary") {
      if (root.viewMode === "result" && root.resultKind === "ai")
        root.showArticle(article)
      else root.summarizeArticle(article)
    } else if (key === "bookmark") root.toggleBookmark(article)
    else if (key === "dismiss") root.dismissArticle(article)
    else if (key === "read") root.activateReadAction(article)
    else if (key === "open") {
      if (article) root.learnArticle(article, "external")
      var url = String(article.url || root.resultUrl || "")
      if (url) Quickshell.execDetached(["omarchy-launch-browser", url])
    }
  }

  function applyTuneFeedback() {
    var article = root.actionHudArticle
    if (!article || feedbackProc.running) return
    var target = root.activeFeedbackTarget(article)
    var action = "not-interest"
    if (root.tuneDirection === "more")
      action = root.tuneDuration === "temporary" ? "temporary" : "follow"
    else if (root.tuneDirection === "less") {
      if (root.tuneDuration === "temporary") action = "snooze"
      else action = String(target.kind || "") === "source" ? "less-source" : "less"
    }
    root.closeActionHud()
    root.sendArticleFeedback(article, action)
  }

  function tuneSummary() {
    var target = root.activeFeedbackTarget(root.actionHudArticle)
    if (root.tuneDirection === "neutral")
      return "Forget this story's inferred reading signals; do not change any topic weight."
    var direction = root.tuneDirection === "more" ? "Show more" : "Show less"
    var duration = root.tuneDuration === "temporary" ? " for 7 days" : " until you remove it"
    var relation = String(target.kind || "") === "source" ? " from “" : " about “"
    return direction + relation + String(target.label || "this story") + "”" + duration + "."
  }

  function sendArticleFeedback(article, action) {
    if (!article || !article.id || feedbackProc.running) return
    var target = root.activeFeedbackTarget(article)
    var command = [
      root.backendPath, "feedback", "--id", String(article.id),
      "--action", String(action)
    ]
    if (String(target.key || "") !== "" && action !== "less-source"
        && action !== "not-interest")
      command.push("--target", String(target.key))
    feedbackProc.command = command
    feedbackProc.running = true
    root.statusText = "Saving explicit feedback locally…"
  }

  function removeInterestNode(term, scope) {
    if (interestProc.running || !term) return
    interestProc.command = [
      root.backendPath, "interests", "--remove", String(term),
      "--scope", String(scope || "lasting")
    ]
    interestProc.running = true
    root.statusText = "Removing explicit interest…"
  }

  function setArticleBackMarksRead(enabled) {
    if (behaviorProc.running) return
    behaviorProc.command = [
      root.backendPath, "setup", "--back-action", enabled ? "mark-read" : "keep"
    ]
    behaviorProc.running = true
    root.statusText = "Saving article Back behavior…"
  }

  function setSystemAiModel(model, effort) {
    if (systemAiPresetProc.running || (model === root.systemAiModel && effort === root.systemAiEffort)) return
    systemAiPresetProc.command = [root.backendPath, "setup", "--system-ai-model-json",
      JSON.stringify({model: String(model), effort: String(effort)})]
    systemAiPresetProc.running = true
    root.statusText = "Saving PYIN's model choice…"
  }

  function loadAiModels(refresh) {
    if (aiModelsProc.running || root.systemAiStatus.available === false) return
    root.aiModelRequestRevision = root.aiModelCatalogRevision
    root.aiModelRequestAgent = String(root.systemAiStatus.agent || "")
    aiModelsProc.command = [root.backendPath, "ai-models"]
    if (refresh) aiModelsProc.command.push("--refresh")
    aiModelsProc.running = true
  }

  function resetProfileLearning() {
    if (profileResetProc.running) return
    if (root.readingEventsBusy || root.activeEventSeen || root.eventSeenQueue.length > 0) {
      root.statusText = "Finishing reading history before reset…"
      return
    }
    if (!root.confirmProfileReset) {
      root.confirmProfileReset = true
      root.statusText = "Press Confirm reset to forget reading and Show Less ranking signals"
      return
    }
    root.confirmProfileReset = false
    root.historyRevision++
    root.feedMutationRevision++
    root.statusText = "Forgetting learned reading and Show Less signals…"
    profileResetProc.command = [root.backendPath, "profile", "--reset-learning"]
    profileResetProc.running = true
  }

  function profileTopicLabels() {
    if (root.profileTopics.length === 0) return "Balanced — no explicit topic boosts"
    var labels = []
    for (var i = 0; i < root.profileTopics.length; i++)
      labels.push(String(root.profileTopics[i].label || root.profileTopics[i].value))
    return labels.join(" · ")
  }

  function setupSummary() {
    var value = root.profileSetup || ({})
    var view = value.viewpoint || ({})
    var privacy = value.privacy || ({})
    var ai = value.ai || ({})
    return String(root.setupData.story_limit || 30) + " stories in feed · "
      + String(view.discovery_percent || 0) + "% discovery · "
      + String(root.profileSourceCounts.active || 0) + "/"
      + String(root.profileSourceCounts.total || 0) + " sources · "
      + (privacy.learn_from_opens === false ? "learning off" : "local learning on")
      + " · AI " + (String(ai.mode || "system") === "system"
        ? root.systemAiModelLabel
        : String(ai.mode || "system"))
  }

  function setupLocationSummary() {
    var location = root.profileSetup && root.profileSetup.location
      ? root.profileSetup.location : ({})
    var parts = []
    if (location.city) parts.push(String(location.city))
    if (location.region) parts.push(String(location.region))
    if (location.country) parts.push(String(location.country))
    return parts.length > 0 ? parts.join(", ") : "No location boost"
  }

  function setupChoiceDetails() {
    var value = root.profileSetup || ({})
    var topics = value.topics || ({})
    var sourceTypes = value.source_types || []
    var notifications = value.notifications || ({})
    function line(label, values, emptyText) {
      return label + ": " + (values && values.length > 0 ? values.join(" · ") : emptyText)
    }
    return line("Must-see", topics.must || [], "none") + "\n"
      + line("Interested", topics.interested || [], "balanced") + "\n"
      + line("Muted", topics.muted || [], "none") + "\n"
      + line("Keyword blacklist", value.blocked_keywords || [], "none") + "\n"
      + line("Source packs", sourceTypes, "all") + "\n"
      + "Notifications: " + (notifications.enabled === false ? "off" : "on · quiet "
        + String(notifications.quiet_start || "22:00") + "–"
        + String(notifications.quiet_end || "07:00") + " · max "
      + String(notifications.max_per_day || 6) + "/day")
  }

  function showLessTermSummary() {
    if (root.lessLikeThisTerms.length === 0) return "No negative topic or keyword weights."
    var labels = []
    for (var i = 0; i < Math.min(20, root.lessLikeThisTerms.length); i++) {
      var item = root.lessLikeThisTerms[i]
      labels.push(String(item.term || "") + " −" + Number(item.weight || 0).toFixed(2))
    }
    return labels.join("  ·  ")
  }

  function showLessSourceSummary() {
    if (root.lessLikeThisSources.length === 0) return "No source-level Show Less weights."
    var labels = []
    for (var i = 0; i < Math.min(12, root.lessLikeThisSources.length); i++) {
      var item = root.lessLikeThisSources[i]
      labels.push(String(item.source || "") + " −" + Number(item.weight || 0).toFixed(2))
    }
    return labels.join("  ·  ")
  }

  function sourceMixSummary() {
    var labels = []
    for (var i = 0; i < root.profileSourceMix.length; i++) {
      var item = root.profileSourceMix[i]
      if (Number(item.active || 0) > 0)
        labels.push(String(item.label) + " " + String(item.active))
    }
    return labels.join("  ·  ")
  }

  function whyBreakdown() {
    if (!root.activeArticle || !root.activeArticle.why
        || root.activeArticle.why.length === 0)
      return "This story was selected from recent reporting."
    var labels = []
    for (var i = 0; i < root.activeArticle.why.length; i++) {
      var item = root.activeArticle.why[i]
      var score = Number(item.score || 0)
      labels.push(String(item.label || "signal")
        + (Math.abs(score) < 0.005 ? "" : " " + (score > 0 ? "+" : "")
          + score.toFixed(2)))
    }
    return labels.join("  ·  ")
  }

  function currentArticle() {
    if (root.viewMode === "result") return root.activeArticle
    if (root.viewMode === "bookmarks") return root.selectedBookmark
    if (root.viewMode === "history") return root.selectedHistoryArticle
    if (root.viewMode === "read") return root.selectedReadArticle
    return root.selectedArticle
  }

  function isArticleContext() {
    return root.viewMode === "feed" || root.viewMode === "search"
      || root.viewMode === "bookmarks" || root.viewMode === "history"
      || root.viewMode === "read"
      || root.viewMode === "result"
  }

  function toggleBookmark(article) {
    if (!article || !article.id || bookmarkMutationProc.running) return
    var enabled = !Boolean(article.bookmarked)
    root.feedMutationRevision++
    bookmarkMutationProc.command = [
      root.backendPath, "bookmarks", enabled ? "--add" : "--remove", String(article.id)
    ]
    bookmarkMutationProc.running = true
    root.statusText = enabled ? "Saving for later…" : "Removing from Read Later…"
  }

  function articlesWithReadState(values, articleId, enabled) {
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (String(item.id) !== String(articleId)) result.push(item)
      else {
        var updated = ({})
        for (var key in item) updated[key] = item[key]
        updated.read = enabled
        result.push(updated)
      }
    }
    return result
  }

  function articlesWithBookmarkState(values, articleId, enabled) {
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (String(item.id) !== String(articleId)) result.push(item)
      else {
        var updated = ({})
        for (var key in item) updated[key] = item[key]
        updated.bookmarked = enabled
        result.push(updated)
      }
    }
    return result
  }

  function articleMutationIds(article) {
    var result = []
    var seen = ({})
    function append(value) {
      var id = String(value || "")
      if (id === "" || seen[id]) return
      seen[id] = true
      result.push(id)
    }
    if (article) append(article.id)
    var related = article && article.cluster_ids ? article.cluster_ids : []
    for (var i = 0; i < related.length; i++) append(related[i])
    return result
  }

  function articlesWithoutIds(values, ids) {
    var blocked = ({})
    for (var i = 0; i < ids.length; i++) blocked[String(ids[i])] = true
    var result = []
    for (var index = 0; index < values.length; index++)
      if (!blocked[String(values[index].id)]) result.push(values[index])
    return result
  }

  function withoutOptimisticHidden(values) {
    var result = []
    for (var i = 0; i < values.length; i++)
      if (!root.optimisticHiddenIds[String(values[i].id)]) result.push(values[i])
    return result
  }

  function addOptimisticHidden(ids) {
    var next = ({})
    for (var existing in root.optimisticHiddenIds)
      next[existing] = Boolean(root.optimisticHiddenIds[existing])
    for (var i = 0; i < ids.length; i++) next[String(ids[i])] = true
    root.optimisticHiddenIds = next
  }

  function removeOptimisticHidden(ids) {
    var removed = ({})
    for (var i = 0; i < ids.length; i++) removed[String(ids[i])] = true
    var next = ({})
    for (var existing in root.optimisticHiddenIds)
      if (!removed[existing]) next[existing] = true
    root.optimisticHiddenIds = next
  }

  function closeHiddenArticle() {
    if (root.eventArticleOpen) { root.returnToEventDesk(); return }
    var fromEdition = root.returnViewMode === "edition"
    if (!fromEdition) root.returnViewMode = "feed"
    root.backToFeed()
  }

  function finishVisualHide() {
    var ids = root.visualHideIds || []
    if (ids.length === 0) return
    root.articles = root.articlesWithoutIds(root.articles, ids)
    if (root.visualHideFromSearch)
      root.searchResults = root.articlesWithoutIds(root.searchResults, ids)
    root.selectedIndex = Math.max(0,
      Math.min(root.selectedIndex, root.visibleArticles.length - 1))
    if (root.viewMode === "result" && root.activeArticle
        && ids.indexOf(String(root.activeArticle.id)) !== -1)
      root.closeHiddenArticle()
    root.visualHideIds = []
    root.visualHideFromSearch = false

    if (root.deferredReadMutationPayload !== null) {
      var payload = root.deferredReadMutationPayload
      var showLess = root.deferredReadMutationShowLess
      root.deferredReadMutationPayload = null
      root.deferredReadMutationShowLess = false
      Qt.callLater(function() { root.applyReadMutation(payload, showLess) })
    }
  }

  function finishOrDeferReadMutation(payload, showLess) {
    if (hideCollapseTimer.running) {
      root.deferredReadMutationPayload = payload
      root.deferredReadMutationShowLess = showLess
      return
    }
    root.applyReadMutation(payload, showLess)
  }

  function beginOptimisticHide(article, hideFromSearch) {
    var ids = root.articleMutationIds(article)
    var context = {
      ids: ids,
      articles: root.articles,
      searchResults: root.searchResults,
      selectedIndex: root.selectedIndex
    }
    root.feedMutationRevision++
    root.addOptimisticHidden(ids)
    root.visualHideIds = ids
    root.visualHideFromSearch = hideFromSearch
    root.deferredReadMutationPayload = null
    root.deferredReadMutationShowLess = false
    if (root.viewMode === "feed" || (root.viewMode === "search" && hideFromSearch))
      hideCollapseTimer.restart()
    else
      root.finishVisualHide()
    return context
  }

  function rollbackOptimisticHide(context) {
    if (!context || !context.ids || context.ids.length === 0) return
    hideCollapseTimer.stop()
    root.visualHideIds = []
    root.visualHideFromSearch = false
    root.deferredReadMutationPayload = null
    root.deferredReadMutationShowLess = false
    root.feedMutationRevision++
    root.removeOptimisticHidden(context.ids)
    root.articles = context.articles || root.articles
    root.searchResults = context.searchResults || root.searchResults
    root.selectedIndex = Math.max(0,
      Math.min(Number(context.selectedIndex || 0), root.visibleArticles.length - 1))
    root.loadFeed(true, "mutation-rollback")
  }

  function toggleRead(article) {
    if (!article || !article.id || readMutationProc.running || dismissProc.running)
      return false
    var enabled = !Boolean(article.read)
    root.readMutationContext = enabled
      ? root.beginOptimisticHide(article, false) : ({})
    readMutationProc.command = [
      root.backendPath, "read", enabled ? "--mark" : "--restore", String(article.id),
      "--related-json", JSON.stringify(article.cluster_ids || [])
    ]
    readMutationProc.running = true
    root.statusText = enabled
      ? "Marking read and hiding from your feed…" : "Restoring story to your feed…"
    return true
  }

  function activateReadAction(article) {
    if (root.editionReaderActive()) { root.completeEditionStory("done"); return }
    if (!article) return
    root.toggleRead(article)
  }

  function dismissArticle(article) {
    if (!article || !article.id || dismissProc.running || readMutationProc.running
        || root.aiBusy) return
    if (Boolean(article.read)) {
      root.statusText = "This story is already hidden · restore it from Profile → Read first"
      return
    }
    root.dismissMutationContext = root.beginOptimisticHide(article, true)
    dismissProc.command = [
      root.backendPath, "dismiss", "--id", String(article.id),
      "--related-json", JSON.stringify(article.cluster_ids || [])
    ]
    dismissProc.running = true
    root.statusText = "Dismissing story and adding a local Show Less signal…"
  }

  function applyReadMutation(payload, showLess) {
    // Persistence is complete. Advance the generation again so every feed
    // calculation started before or during the write is now stale.
    root.feedMutationRevision++
    var articleId = String(payload.article_id || "")
    var articleIds = payload.article_ids || [articleId]
    var affected = ({})
    for (var a = 0; a < articleIds.length; a++)
      affected[String(articleIds[a])] = true
    var isRead = Boolean(payload.read)
    root.applyLibraryCounts(payload.counts)
    var closeArticle = isRead && root.viewMode === "result"
      && root.activeArticle && Boolean(affected[String(root.activeArticle.id)])
    if (payload.articles !== undefined && payload.articles !== null)
      root.readArticles = payload.articles
    else if (!isRead) {
      root.readArticles = root.articlesWithoutIds(root.readArticles, articleIds)
      // A previous failed replenishment may have left this story in the
      // optimistic mask. Restoring it must make the next feed eligible to
      // show it again.
      root.removeOptimisticHidden(articleIds)
    }
    root.readIndex = Math.max(0,
      Math.min(root.readIndex, root.readArticles.length - 1))
    for (var stateIndex = 0; stateIndex < articleIds.length; stateIndex++) {
      root.patchEventArticle(articleIds[stateIndex], { read: isRead, dismissed: Boolean(payload.dismissed) })
      root.searchResults = root.articlesWithReadState(
        root.searchResults, String(articleIds[stateIndex]), isRead)
      root.bookmarks = root.articlesWithReadState(
        root.bookmarks, String(articleIds[stateIndex]), isRead)
      root.historyArticles = root.articlesWithReadState(
        root.historyArticles, String(articleIds[stateIndex]), isRead)
    }
    if (root.activeArticle && Boolean(affected[String(root.activeArticle.id)])) {
      var updated = ({})
      for (var key in root.activeArticle) updated[key] = root.activeArticle[key]
      updated.read = isRead
      updated.dismissed = Boolean(payload.dismissed)
      root.activeArticle = updated
    }
    if (isRead) {
      var remaining = []
      for (var i = 0; i < root.articles.length; i++)
        if (!affected[String(root.articles[i].id)]) remaining.push(root.articles[i])
      root.articles = remaining
      root.selectedIndex = Math.max(0,
        Math.min(root.selectedIndex, root.visibleArticles.length - 1))
    }
    if (showLess && root.viewMode === "search") {
      var remainingSearch = []
      for (var s = 0; s < root.searchResults.length; s++)
        if (!affected[String(root.searchResults[s].id)])
          remainingSearch.push(root.searchResults[s])
      root.searchResults = remainingSearch
      root.selectedIndex = Math.max(0,
        Math.min(root.selectedIndex, root.searchResults.length - 1))
    }
    root.statusText = showLess
      ? (Boolean(payload.learning_enabled)
        ? "Dismissed · hidden now, with a reversible local Show Less signal"
        : "Dismissed · hidden now; learning is disabled")
      : (isRead
        ? "Marked read · hidden from future feed refreshes"
        : "Restored · story and any Show Less signal were restored")
    if (closeArticle) {
      root.closeHiddenArticle()
    }
    if (showLess) root.dismissMutationContext = ({})
    else root.readMutationContext = ({})
    // Refill to the configured story count without moving the surviving
    // headlines the reader is already scanning.
    root.loadFeed(true, showLess ? "dismiss-refill" : "read-refill")
    if (root.viewMode === "profile") root.loadProfile()
    if (root.viewMode === "edition" || root.editionReaderActive()) root.runEdition([], "load", "")
  }

  function filteredHelpEntries() {
    var query = root.helpQuery.trim().toLowerCase()
    var output = []
    var previousSection = ""
    for (var i = 0; i < root.helpEntries.length; i++) {
      var item = root.helpEntries[i]
      var text = (String(item.section || "") + " " + String(item.keys || "")
        + " " + String(item.action || "")).toLowerCase()
      if (query !== "" && text.indexOf(query) === -1) continue
      var section = String(item.section || "")
      output.push({
        section: section,
        keys: String(item.keys || ""),
        action: String(item.action || ""),
        showSection: section !== previousSection
      })
      previousSection = section
    }
    return output
  }

  function filteredFeedControlEntries() {
    var query = root.helpQuery.trim().toLowerCase()
    if (query === "") return root.feedControlEntries
    var output = []
    for (var i = 0; i < root.feedControlEntries.length; i++) {
      var item = root.feedControlEntries[i]
      var text = (String(item.option || "") + " "
        + String(item.effect || "")).toLowerCase()
      if (text.indexOf(query) !== -1) output.push(item)
    }
    return output
  }

  function setHelpTab(tab) {
    root.helpTab = tab === "feed" ? "feed" : "keys"
    root.helpQuery = ""
    helpScroll.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function focusHelpFilter() {
    if (root.viewMode !== "help") return
    helpFilterField.forceActiveFocus()
    helpFilterField.selectAll()
  }

  function showHelp() {
    root.helpQuery = ""
    root.helpTab = "keys"
    root.viewMode = "help"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function showAbout() {
    if (root.viewMode === "setup") return
    if (root.viewMode !== "about") {
      root.aboutReturnViewMode = root.viewMode
      root.aboutReturnStatus = root.statusText
    }
    root.viewMode = "about"
    root.statusText = "About PYIN · created by chuchua.tech"
    Qt.callLater(function() {
      aboutPage.reset()
      mastheadLogo.replay()
      keyCatcher.forceActiveFocus()
    })
  }

  function leaveAbout() {
    var destination = root.aboutReturnViewMode
    var allowed = ["edition", "feed", "search", "result", "bookmarks", "history", "read", "alerts", "profile", "help"]
    if (allowed.indexOf(destination) === -1) destination = "feed"
    root.viewMode = destination
    root.statusText = root.aboutReturnStatus || "PYIN · your news, your choices"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function addAlert() {
    var query = alertField.text.trim()
    if (!query || alertMutationProc.running) return
    root.feedMutationRevision++
    alertMutationProc.command = [root.backendPath, "alerts", "--add", query]
    alertMutationProc.running = true
    root.statusText = "Creating alert…"
  }

  function removeAlert(alertId) {
    if (alertMutationProc.running) return
    root.feedMutationRevision++
    alertMutationProc.command = [root.backendPath, "alerts", "--remove", String(alertId)]
    alertMutationProc.running = true
    root.statusText = "Removing alert…"
  }

  function backToFeed() {
    if (root.viewMode === "setup") {
      root.cancelSetup()
      return
    }
    root.cancelAiRequest()
    root.eventOrigin = null
    root.eventArticleOpen = false
    root.eventRevision++
    root.pendingEventLoad = false
    var leavingSearch = root.viewMode === "search"
    var destination = root.viewMode === "result"
      && (root.returnViewMode === "bookmarks" || root.returnViewMode === "search"
        || root.returnViewMode === "history" || root.returnViewMode === "read"
        || root.returnViewMode === "edition")
      ? root.returnViewMode : "feed"
    root.viewMode = destination
    if (destination === "history") root.loadHistory()
    if (leavingSearch) {
      searchField.text = ""
      root.searchQuery = ""
      root.searchResults = []
      root.searchStats = ({})
    }
    root.resultText = ""
    root.resultTitle = ""
    root.resultUrl = ""
    root.resultKind = ""
    root.activeArticleId = ""
    root.activeArticle = null
    root.closeActionHud()
    root.whySectionExpanded = false
    root.confirmProfileReset = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function showMainFeed() {
    if (root.viewMode === "setup") {
      root.cancelSetup()
      return
    }
    root.cancelAiRequest()
    root.eventOrigin = null
    root.eventArticleOpen = false
    root.eventRevision++
    root.pendingEventLoad = false
    searchField.text = ""
    root.searchQuery = ""
    root.searchResults = []
    root.searchStats = ({})
    root.viewMode = "feed"
    root.resultText = ""
    root.resultTitle = ""
    root.resultUrl = ""
    root.resultKind = ""
    root.activeArticleId = ""
    root.activeArticle = null
    root.closeActionHud()
    root.whySectionExpanded = false
    root.confirmProfileReset = false
    root.statusText = "PYIN · your news, your choices"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function navigateBack() {
    if (root.viewMode === "event") { root.leaveEventDesk(); return }
    if (root.viewMode === "result" && root.eventArticleOpen) {
      root.returnToEventDesk()
      return
    }
    if (root.viewMode === "about") {
      root.leaveAbout()
      return
    }
    if (root.editionReaderActive()) { root.backToFeed(); return }
    if (root.viewMode === "result" && root.articleBackMarksRead
        && root.activeArticle && !Boolean(root.activeArticle.read)) {
      var article = root.activeArticle
      // Returning should feel immediate. The local read mutation can finish
      // after the article view has already yielded back to the feed.
      root.activateReadAction(article)
      return
    }
    root.backToFeed()
  }

  function handleClose() {
    if (root.viewMode === "setup") root.cancelSetup()
    else if (root.viewMode !== "feed") root.navigateBack()
    else root.requestClose()
  }

  Process {
    id: editionProc
    stdout: StdioCollector { id: editionStdout; waitForEnd: true }
    stderr: StdioCollector { id: editionStderr; waitForEnd: true }
    onRunningChanged: {
      if (!running) {
        var revision = root.editionRequestRevision
        Qt.callLater(function() { root.checkEditionLaunch(revision) })
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.editionRequestActive = false
      var payload = root.parsePayload(editionStdout.text,
        String(editionStderr.text || "Could not load your edition"))
      if (exitCode !== 0 || Boolean(exitStatus)) payload.ok = false
      if (payload.ok && (payload.edition === undefined
          || (payload.edition !== null && !Array.isArray(payload.edition.articles))))
        payload = {ok: false, error: "Incomplete edition response. Please retry."}
      root.acceptEdition(payload)
    }
  }

  Process {
    id: bootstrapProc
    stdout: StdioCollector { id: bootstrapStdout; waitForEnd: true }
    stderr: StdioCollector { id: bootstrapStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(bootstrapStdout.text,
        String(bootstrapStderr.text || "Could not load PYIN"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not load PYIN"
        return
      }
      var setupPayload = payload.setup || ({})
      if (!setupPayload.ok) {
        root.statusText = setupPayload.error || "Could not load setup"
        return
      }
      root.setupData = setupPayload
      root.setupRevision++
      if (root.activeBootstrapRevision === root.feedMutationRevision)
        root.applyLibraryCounts(payload.counts, root.activeBootstrapHistoryRevision)
      if (!Boolean(setupPayload.profile && setupPayload.profile.complete)) {
        root.viewMode = "setup"
        root.statusText = "First run · your choices stay on this device"
        Qt.callLater(function() { setupWizard.forceActiveFocus() })
      } else {
        root.viewMode = "feed"
        if (root.activeBootstrapRevision === root.feedMutationRevision) {
          root.applyFeedPayload(payload.feed || {
            ok: false, error: "Bootstrap did not return a feed"
          }, false, "bootstrap")
        } else root.loadFeed(true, "bootstrap-stale")
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        Qt.callLater(function() { root.fulfillDeepLink() })
      }
    }
  }

  Process {
    id: deepLinkArticleProc
    stdout: StdioCollector { id: deepLinkArticleStdout; waitForEnd: true }
    stderr: StdioCollector { id: deepLinkArticleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(deepLinkArticleStdout.text,
        String(deepLinkArticleStderr.text || "Could not open that alert story"))
      root.activeDeepLinkArticleId = ""
      if (!payload.ok || !payload.article) {
        root.statusText = payload.error
          ? "Alert story unavailable · " + String(payload.error)
          : "That alert story is no longer in local storage"
      } else {
        root.returnViewMode = "feed"
        root.showArticle(payload.article)
        root.statusText = "Opened from subject alert · stored locally"
      }
      if (!bootstrapProc.running && root.pendingDeepLinkArticleId !== "")
        Qt.callLater(function() { root.fulfillDeepLink() })
    }
  }

  Process {
    id: setupSaveProc
    stdout: StdioCollector { id: setupSaveStdout; waitForEnd: true }
    stderr: StdioCollector { id: setupSaveStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(setupSaveStdout.text,
        String(setupSaveStderr.text || "Could not save setup"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not save setup"
        setupWizard.validationMessage = root.statusText
        return
      }
      root.setupData = payload
      root.setupRevision++
      var topics = payload.profile && payload.profile.topics
        ? payload.profile.topics : ({})
      root.selectedTopics = (topics.must || []).concat(topics.interested || [])
      var returnToProfile = root.setupReturningToProfile
      root.setupReturningToProfile = false
      root.viewMode = returnToProfile ? "profile" : "feed"
      root.statusText = String(payload.sources.active || 0) + " of "
        + String(payload.sources.total || 0) + " sources active · building your feed"
      root.loadApplicationData()
      if (returnToProfile) root.loadProfile()
    }
  }

  Process {
    id: behaviorProc
    stdout: StdioCollector { id: behaviorStdout; waitForEnd: true }
    stderr: StdioCollector { id: behaviorStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(behaviorStdout.text,
        String(behaviorStderr.text || "Could not save article Back behavior"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not save article Back behavior"
        return
      }
      root.setupData = payload
      root.setupRevision++
      root.statusText = root.articleBackMarksRead
        ? "Back now marks articles read and hides them"
        : "Back now leaves articles in your feed"
      if (root.viewMode === "profile") root.loadProfile()
    }
  }

  Process {
    id: aiModelsProc
    stdout: StdioCollector { id: aiModelsStdout; waitForEnd: true }
    stderr: StdioCollector { id: aiModelsStderr; waitForEnd: true }
    onRunningChanged: {
      if (!running) {
        var revision = root.aiModelRequestRevision
        Qt.callLater(function() {
          if (!aiModelsProc.running && revision === root.aiModelRequestRevision
              && root.aiModelRequestRevision === root.aiModelCatalogRevision
              && aiModelsStdout.text === "")
            root.aiModelCatalog = {ok: false, models: [], error: "Could not load models. Retry or enter a model manually."}
        })
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (root.aiModelRequestRevision !== root.aiModelCatalogRevision) return
      var payload = root.parsePayload(aiModelsStdout.text, "Could not load models. Retry or enter a model manually.")
      if (payload.agent && String(payload.agent) !== root.aiModelRequestAgent) {
        root.aiModelCatalog = {ok: false, models: [], error: "The Omarchy agent changed. Reopen Profile or Setup to update its status."}
        return
      }
      if (exitCode !== 0 || Boolean(exitStatus)) payload.ok = false
      if (!Array.isArray(payload.models)) payload.models = []
      if (!payload.ok && !payload.error) payload.error = "Could not load models. Retry or enter a model manually."
      root.aiModelCatalog = payload
    }
  }

  Process {
    id: systemAiPresetProc
    stdout: StdioCollector { id: systemAiPresetStdout; waitForEnd: true }
    stderr: StdioCollector { id: systemAiPresetStderr; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      var payload = root.parsePayload(systemAiPresetStdout.text,
        String(systemAiPresetStderr.text || "Could not change model preference"))
      if (exitCode !== 0 || Boolean(exitStatus)) payload.ok = false
      if (!payload.ok) {
        root.statusText = payload.error || "Could not change model preference"
        return
      }
      root.setupData = payload
      root.setupRevision++
      root.statusText = "AI TL;DR · " + root.systemAiModelLabel
      if (root.viewMode === "profile") root.loadProfile()
    }
  }

  Process {
    id: navigationProc
    stdout: StdioCollector { id: navigationStdout; waitForEnd: true }
    stderr: StdioCollector { id: navigationStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(navigationStdout.text,
        String(navigationStderr.text || "Could not customize the main menu"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not customize the main menu"
        return
      }
      root.setupData = payload
      root.setupRevision++
      root.statusText = "Main menu updated · saved on this device"
      root.loadProfile()
    }
  }

  Process {
    id: footerLinkProc
    stdout: StdioCollector { id: footerLinkStdout; waitForEnd: true }
    stderr: StdioCollector { id: footerLinkStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(footerLinkStdout.text,
        String(footerLinkStderr.text || "Could not save footer link"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not save footer link"
        profilePage.footerLinkMessage = root.statusText
        return
      }
      root.setupData = payload
      root.setupRevision++
      profilePage.syncFooterLinkDraft()
      profilePage.footerLinkMessage = root.footerLinkVisible
        ? "Footer link saved · local only"
        : "Footer link cleared"
      root.statusText = profilePage.footerLinkMessage
      if (root.viewMode === "profile") root.loadProfile()
    }
  }

  Process {
    id: profileTransferProc
    stdout: StdioCollector { id: profileTransferStdout; waitForEnd: true }
    stderr: StdioCollector { id: profileTransferStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(profileTransferStdout.text,
        String(profileTransferStderr.text || "Profile transfer failed"))
      if (!payload.ok) {
        root.statusText = payload.error || "Profile transfer failed"
        return
      }
      if (root.profileTransferAction === "import") {
        root.setupData = payload
        root.setupRevision++
        root.statusText = "Profile imported · explicit interests restored · local history kept"
        root.loadProfile()
        root.loadFeed(false, "profile-import")
      } else root.statusText = "Profile exported to " + String(payload.path || "Downloads")
    }
  }

  Process {
    id: refreshProc
    stdout: StdioCollector { id: refreshStdout; waitForEnd: true }
    stderr: StdioCollector { id: refreshStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(refreshStdout.text,
        String(refreshStderr.text || "Refresh failed"))
      if (!payload.ok) {
        root.statusText = payload.error || "Refresh failed"
        root.refreshOutcomeText = "!"
      }
      else if (payload.errors && payload.errors.length > 0) {
        root.statusText = payload.sources_ok + "/" + payload.sources_attempted
          + " checked · " + payload.sources_skipped + " fresh · "
          + payload.errors.length + " failed"
        root.refreshOutcomeText = "!" + String(Math.min(99, payload.errors.length))
      }
      else if (Number(payload.sources_attempted || 0) === 0) {
        root.statusText = "All sources are still fresh"
        root.refreshOutcomeText = "✓"
      }
      else {
        var matched = payload.alert_hits ? payload.alert_hits.length : 0
        root.statusText = payload.inserted + " new stories"
          + " · " + payload.sources_attempted + " checked"
          + (payload.sources_skipped > 0 ? " · " + payload.sources_skipped + " fresh" : "")
          + (matched > 0 ? " · " + matched + " alert matches" : "")
        root.refreshOutcomeText = Number(payload.inserted || 0) > 0
          ? (Number(payload.inserted) > 99 ? "99+" : "+" + String(payload.inserted))
          : "✓"
      }
      root.refreshOutcomeDetail = root.statusText
      if (root.opened && root.viewMode === "profile" && profilePage.sourceHealthExpanded)
        root.loadSourceHealth()
      refreshOutcomeTimer.restart()
      // Alert refreshes continue while PYIN is hidden, but ranking and QML
      // model rebuilding are only useful while the panel is actually open.
      if (root.opened) root.loadFeed(root.activeRefreshOrderPreservation,
        root.activeRefreshOrderPreservation ? "background-refresh" : "manual-refresh")
      root.activeRefreshOrderPreservation = false
    }
  }

  Process {
    id: loadProc
    stdout: StdioCollector { id: loadStdout; waitForEnd: true }
    stderr: StdioCollector { id: loadStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.activeFeedLoadRevision === root.feedMutationRevision)
        root.applyFeed(loadStdout.text, root.activeFeedOrderPreservation,
          root.activeFeedLoadReason)
      else {
        if (!root.pendingLoad) {
          root.pendingFeedOrderPreservation = root.activeFeedOrderPreservation
          root.pendingFeedLoadReason = root.activeFeedLoadReason + "-stale"
        }
        root.pendingLoad = true
      }
      if (root.pendingLoad) {
        var preserveOrder = root.pendingFeedOrderPreservation
        var pendingReason = root.pendingFeedLoadReason
        root.pendingLoad = false
        root.pendingFeedOrderPreservation = false
        root.pendingFeedLoadReason = ""
        Qt.callLater(function() { root.loadFeed(preserveOrder, pendingReason) })
      }
      root.activeFeedOrderPreservation = false
      root.activeFeedLoadReason = ""
    }
  }

  Process {
    id: impressionProc
    stdout: StdioCollector { id: impressionStdout; waitForEnd: true }
    stderr: StdioCollector { id: impressionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(impressionStdout.text,
        String(impressionStderr.text || "Could not update the local exposure ledger"))
      if (!payload.ok)
        root.statusText = payload.error || "Could not update the local exposure ledger"
      if (root.pendingImpressions) {
        root.pendingImpressions = false
        impressionTimer.restart()
      }
    }
  }

  Timer {
    id: impressionTimer
    interval: 450
    repeat: false
    onTriggered: root.recordVisibleImpressions()
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchStdout; waitForEnd: true }
    stderr: StdioCollector { id: searchStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(searchStdout.text,
        String(searchStderr.text || "News search failed"))
      if (!payload.ok) {
        root.searchResults = []
        root.searchStats = ({})
        root.statusText = payload.error || "News search failed"
        return
      }
      root.searchResults = payload.articles || []
      root.searchStats = payload.stats || ({})
      root.selectedIndex = 0
      root.cursorActive = false
      root.statusText = String(root.searchStats.matches || 0) + " matches across "
        + String(root.searchStats.matching_sources || 0) + " sources · all cached news · no AI"
    }
  }

  Process {
    id: preferencesProc
    stdout: StdioCollector { id: preferencesStdout; waitForEnd: true }
    stderr: StdioCollector { id: preferencesStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(preferencesStdout.text,
        String(preferencesStderr.text || "Could not load topic preferences"))
      if (!payload.ok) return
      root.selectedTopics = payload.topics || []
      root.topicOptions = payload.catalog || []
    }
  }

  Process {
    id: savePreferencesProc
    stdout: StdioCollector { id: savePreferencesStdout; waitForEnd: true }
    stderr: StdioCollector { id: savePreferencesStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(savePreferencesStdout.text,
        String(savePreferencesStderr.text || "Could not save topic preferences"))
      if (!payload.ok) root.statusText = payload.error || "Could not save topics"
      else {
        root.selectedTopics = payload.topics || []
        root.topicOptions = payload.catalog || root.topicOptions
        root.loadFeed(false, "topic-preferences")
      }
      if (root.pendingTopicSave) {
        root.pendingTopicSave = false
        Qt.callLater(function() { root.saveTopics(root.selectedTopics) })
      }
    }
  }

  Process {
    id: alertsProc
    stdout: StdioCollector { id: alertsStdout; waitForEnd: true }
    stderr: StdioCollector { id: alertsStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(alertsStdout.text,
        String(alertsStderr.text || "Could not load alerts"))
      if (!payload.ok) root.statusText = payload.error || "Could not load alerts"
      else {
        root.alerts = payload.alerts || []
        root.alertCount = payload.count !== undefined
          ? Number(payload.count) : root.alerts.length
      }
    }
  }

  Process {
    id: alertMutationProc
    stdout: StdioCollector { id: alertMutationStdout; waitForEnd: true }
    stderr: StdioCollector { id: alertMutationStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(alertMutationStdout.text,
        String(alertMutationStderr.text || "Could not update alert"))
      if (!payload.ok) root.statusText = payload.error || "Could not update alert"
      else {
        root.alerts = payload.alerts || []
        root.alertCount = payload.count !== undefined
          ? Number(payload.count) : root.alerts.length
        alertField.text = ""
        root.statusText = "Alerts watch each new feed refresh · no AI used"
        root.loadFeed(false, "alert-preferences")
      }
    }
  }

  Process {
    id: bookmarksProc
    stdout: StdioCollector { id: bookmarksStdout; waitForEnd: true }
    stderr: StdioCollector { id: bookmarksStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(bookmarksStdout.text,
        String(bookmarksStderr.text || "Could not load Read Later"))
      if (!payload.ok) root.statusText = payload.error || "Could not load Read Later"
      else {
        root.bookmarks = payload.articles || []
        root.bookmarkCount = payload.count !== undefined
          ? Number(payload.count) : root.bookmarks.length
        root.savedIndex = Math.max(0,
          Math.min(root.savedIndex, root.bookmarks.length - 1))
      }
    }
  }

  Process {
    id: readingEventProc
    stdout: StdioCollector { id: readingEventStdout; waitForEnd: true }
    stderr: StdioCollector { id: readingEventStderr; waitForEnd: true }
    onRunningChanged: {
      if (!running) {
        // Failed starts emit runningChanged without exited. Let normal exits
        // consume their acknowledgement before handling this fallback.
        var event = root.activeReadingEvent
        Qt.callLater(function() {
          if (event && root.activeReadingEvent === event && !readingEventProc.running)
            root.finishReadingEvent({ ok: false, error: "Could not start reading history helper" })
        })
      }
    }
    onExited: function(exitCode, exitStatus) {
      var payload = root.parsePayload(readingEventStdout.text,
        String(readingEventStderr.text || "Could not save reading history"))
      if (exitCode !== 0 || Boolean(exitStatus)) payload.ok = false
      root.finishReadingEvent(payload)
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector { id: historyStdout; waitForEnd: true }
    stderr: StdioCollector { id: historyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(historyStdout.text,
        String(historyStderr.text || "Could not load viewed history"))
      root.applyHistoryPayload(payload)
      Qt.callLater(function() { root.startNextReadingEvent() })
    }
  }

  Process {
    id: bookmarkMutationProc
    stdout: StdioCollector { id: bookmarkMutationStdout; waitForEnd: true }
    stderr: StdioCollector { id: bookmarkMutationStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(bookmarkMutationStdout.text,
        String(bookmarkMutationStderr.text || "Could not update Read Later"))
      if (!payload.ok) root.statusText = payload.error || "Could not update Read Later"
      else {
        root.bookmarks = payload.articles || []
        root.bookmarkCount = payload.count !== undefined
          ? Number(payload.count) : root.bookmarks.length
        root.savedIndex = Math.max(0,
          Math.min(root.savedIndex, root.bookmarks.length - 1))
        if (root.activeArticle && String(root.activeArticle.id) === String(payload.article_id)) {
          var updated = ({})
          for (var key in root.activeArticle) updated[key] = root.activeArticle[key]
          updated.bookmarked = Boolean(payload.bookmarked)
          root.activeArticle = updated
        }
        root.articles = root.articlesWithBookmarkState(
          root.articles, payload.article_id, Boolean(payload.bookmarked))
        root.searchResults = root.articlesWithBookmarkState(
          root.searchResults, payload.article_id, Boolean(payload.bookmarked))
        root.historyArticles = root.articlesWithBookmarkState(
          root.historyArticles, payload.article_id, Boolean(payload.bookmarked))
        root.readArticles = root.articlesWithBookmarkState(
          root.readArticles, payload.article_id, Boolean(payload.bookmarked))
        root.patchEventArticle(payload.article_id, { bookmarked: Boolean(payload.bookmarked) })
        root.statusText = payload.bookmarked ? "Saved to Read Later" : "Removed from Read Later"
        root.loadFeed(true, "bookmark-signal")
      }
    }
  }

  Process {
    id: readProc
    stdout: StdioCollector { id: readStdout; waitForEnd: true }
    stderr: StdioCollector { id: readStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(readStdout.text,
        String(readStderr.text || "Could not load read history"))
      if (!payload.ok) root.statusText = payload.error || "Could not load read history"
      else {
        root.readArticles = payload.articles || []
        root.readCount = payload.count !== undefined
          ? Number(payload.count) : root.readArticles.length
        root.readIndex = Math.max(0,
          Math.min(root.readIndex, root.readArticles.length - 1))
      }
    }
  }

  Process {
    id: readMutationProc
    stdout: StdioCollector { id: readMutationStdout; waitForEnd: true }
    stderr: StdioCollector { id: readMutationStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(readMutationStdout.text,
        String(readMutationStderr.text || "Could not update read state"))
      if (!payload.ok) {
        root.rollbackOptimisticHide(root.readMutationContext)
        root.readMutationContext = ({})
        root.statusText = payload.error || "Could not update read state"
        return
      }
      root.finishOrDeferReadMutation(payload, false)
    }
  }

  Process {
    id: dismissProc
    stdout: StdioCollector { id: dismissStdout; waitForEnd: true }
    stderr: StdioCollector { id: dismissStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(dismissStdout.text,
        String(dismissStderr.text || "Could not dismiss story"))
      if (!payload.ok) {
        root.rollbackOptimisticHide(root.dismissMutationContext)
        root.dismissMutationContext = ({})
        root.statusText = payload.error || "Could not dismiss story"
        return
      }
      root.finishOrDeferReadMutation(payload, true)
    }
  }

  Process {
    id: feedbackProc
    stdout: StdioCollector { id: feedbackStdout; waitForEnd: true }
    stderr: StdioCollector { id: feedbackStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(feedbackStdout.text,
        String(feedbackStderr.text || "Could not save article feedback"))
      Qt.callLater(function() { root.startNextReadingEvent() })
      if (!payload.ok) {
        root.statusText = payload.error || "Could not save article feedback"
        return
      }
      root.statusText = String(payload.label || "Feedback saved")
        + (payload.target_label ? " · " + String(payload.target_label) : "")
        + " · local only"
      root.loadFeed(true, "article-feedback")
      if (root.viewMode === "profile") root.loadProfile()
    }
  }

  Process {
    id: interestProc
    stdout: StdioCollector { id: interestStdout; waitForEnd: true }
    stderr: StdioCollector { id: interestStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(interestStdout.text,
        String(interestStderr.text || "Could not update personalization"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not update personalization"
        return
      }
      root.statusText = "Explicit interest removed"
      root.loadFeed(true, "interest-change")
      root.loadProfile()
    }
  }

  Process {
    id: eventProc
    stdout: StdioCollector { id: eventStdout; waitForEnd: true }
    stderr: StdioCollector { id: eventStderr; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      var payload = root.parsePayload(eventStdout.text,
        String(eventStderr.text || "Could not load event coverage"))
      if (exitCode !== 0 || exitStatus !== 0) payload.ok = false
      root.finishEventLoad(payload)
    }
    onRunningChanged: {
      if (!running) Qt.callLater(function() {
        if (root.eventLoadActive && !eventProc.running)
          root.finishEventLoad({ ok: false, error: "Could not open coverage. Try again." })
      })
    }
  }

  Process {
    id: eventSeenProc
    stdout: StdioCollector { id: eventSeenStdout; waitForEnd: true }
    stderr: StdioCollector { id: eventSeenStderr; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      var payload = root.parsePayload(eventSeenStdout.text,
        String(eventSeenStderr.text || "Could not save event visit"))
      if (exitCode !== 0 || exitStatus !== 0) payload.ok = false
      root.finishEventSeen(payload)
    }
    onRunningChanged: {
      if (!running) Qt.callLater(function() {
        if (root.activeEventSeen && !eventSeenProc.running)
          root.finishEventSeen({ ok: false })
      })
    }
  }

  Process {
    id: sourceHealthProc
    stdout: StdioCollector { id: sourceHealthStdout; waitForEnd: true }
    stderr: StdioCollector { id: sourceHealthStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(sourceHealthStdout.text,
        String(sourceHealthStderr.text || "Could not load source health"))
      if (exitCode !== 0) payload.ok = false
      root.sourceHealthData = payload
      if (root.pendingSourceHealthLoad)
        Qt.callLater(function() { root.loadSourceHealth() })
    }
  }

  Process {
    id: profileProc
    stdout: StdioCollector { id: profileStdout; waitForEnd: true }
    stderr: StdioCollector { id: profileStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(profileStdout.text,
        String(profileStderr.text || "Could not load your curation profile"))
      if (!payload.ok) root.statusText = payload.error || "Could not load profile"
      else {
        root.profileData = payload
        if (payload.system_ai_status)
          root.setupData = Object.assign({}, root.setupData, { system_ai_status: payload.system_ai_status })
        root.applyLibraryCounts(payload.counts, root.activeProfileHistoryRevision)
        root.statusText = "Your curation profile · stored only on this device"
      }
    }
  }

  Process {
    id: updateStatusProc
    stdout: StdioCollector { id: updateStatusStdout; waitForEnd: true }
    stderr: StdioCollector { id: updateStatusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(updateStatusStdout.text,
        String(updateStatusStderr.text || "Could not inspect app updates"))
      if (!payload.ok) {
        root.statusText = payload.error || "Could not inspect app updates"
        root.applicationUpdateCheckRemote = false
        return
      }
      root.applicationUpdateData = payload
      var lastResult = payload.last_result || ({})
      if (root.applicationUpdateLaunching
          && Number(lastResult.finished_ts || 0) >= root.applicationUpdateStartedTs) {
        root.applicationUpdateLaunching = false
        root.statusText = String(lastResult.summary || "Update finished")
      } else if (root.applicationUpdateCheckRemote) {
        root.statusText = String(payload.summary || "Update check finished")
      }
      root.applicationUpdateCheckRemote = false
    }
  }

  Process {
    id: profileResetProc
    stdout: StdioCollector { id: profileResetStdout; waitForEnd: true }
    stderr: StdioCollector { id: profileResetStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var payload = root.parsePayload(profileResetStdout.text,
        String(profileResetStderr.text || "Could not reset learned history"))
      Qt.callLater(function() { root.startNextReadingEvent() })
      if (!payload.ok) root.statusText = payload.error || "Could not reset learned history"
      else {
        root.profileData = payload
        root.historyRevision++
        root.feedMutationRevision++
        root.applyLibraryCounts(payload.counts, root.historyRevision)
        root.historyArticles = []
        root.pendingHistoryLoad = true
        root.learnedArticles = ({})
        root.statusText = "Learned reading and Show Less signals cleared · explicit choices kept"
        root.loadFeed(false, "profile-reset")
      }
    }
  }

  Process {
    id: aiProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) { root.handleAiStreamLine(data) }
    }
    stderr: StdioCollector { id: aiStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.aiCancelled) {
        root.aiCancelled = false
        return
      }
      if (!root.aiBackendDone && !root.aiStreamFailed) {
        var detail = String(aiStderr.text || "").trim()
        root.failAiStream(detail || (exitCode === 0
          ? "AI stream ended before a completed answer arrived"
          : "AI request failed"))
      }
    }
  }

  Timer {
    id: aiPresentationTimer
    interval: 22
    repeat: true
    onTriggered: root.revealAiText()
  }

  Timer {
    id: refreshScanTimer
    interval: 170
    repeat: true
    running: refreshProc.running
    onTriggered: root.refreshScanFrame =
      (root.refreshScanFrame + 1) % root.refreshScanFrames.length
    onRunningChanged: if (!running) root.refreshScanFrame = 0
  }

  Timer {
    id: refreshOutcomeTimer
    interval: 2400
    repeat: false
    onTriggered: {
      root.refreshOutcomeText = ""
      root.refreshOutcomeDetail = ""
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.applicationUpdateLaunching
    onTriggered: {
      root.applicationUpdatePolls++
      if (root.applicationUpdatePolls >= 90) {
        root.applicationUpdateLaunching = false
        root.statusText = "Update is taking longer than expected · check again from Profile"
      } else if (!updateStatusProc.running) {
        root.loadApplicationUpdateStatus(false)
      }
    }
  }

  Timer {
    id: aiCursorTimer
    interval: 390
    repeat: true
    running: root.resultKind === "ai" && root.aiBusy
    onTriggered: root.aiCursorVisible = !root.aiCursorVisible
    onRunningChanged: if (!running) root.aiCursorVisible = true
  }

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    repeat: true
    running: root.setupComplete
    triggeredOnStart: true
    onTriggered: root.refresh(true)
  }

  ElapsedTimer { id: readingClock }

  Timer {
    id: readingEngagementTimer
    interval: 12000
    repeat: false
    onTriggered: root.syncReadingEngagement()
  }

  Timer {
    id: openedReload
    interval: 350
    onTriggered: root.loadFeed(true, "opened-signal")
  }

  Timer {
    id: hideCollapseTimer
    interval: 190
    repeat: false
    onTriggered: root.finishVisualHide()
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "PYIN News"
    color: root.background
    implicitWidth: Style.space(980)
    implicitHeight: Style.space(720)
    minimumSize: Qt.size(Style.space(620), Style.space(480))

    onVisibleChanged: {
      root.syncReadingEngagement()
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    Loader {
      anchors.fill: parent
      active: root.opened && root.paperBackground && root.viewMode !== "result"
      sourceComponent: PaperBackground { ink: root.foreground }
    }

    FocusScope {
      id: windowContent
      objectName: "pyinWindowContent"
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      focus: true
      Window.onActiveChanged: {
        root.syncReadingEngagement()
        root.queueEventVisit()
        if (Window.active) root.queueVisibleImpressions()
      }
      Window.onVisibilityChanged: {
        root.syncReadingEngagement()
        root.queueEventVisit()
        root.queueVisibleImpressions()
      }

      Shortcut {
        sequence: "Backspace"
        context: Qt.WindowShortcut
        enabled: root.opened && !searchField.activeFocus && !alertField.activeFocus
          && !helpFilterField.activeFocus && root.viewMode !== "setup"
          && !root.actionHudExpanded
          && (root.viewMode === "feed" || root.viewMode === "search"
            || root.viewMode === "bookmarks" || root.viewMode === "history"
            || root.viewMode === "result")
          && root.currentArticle() !== null && !Boolean(root.currentArticle().read)
          && !root.aiBusy
        onActivated: root.dismissArticle(root.currentArticle())
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.viewMode === "setup" || searchField.activeFocus
          || alertField.activeFocus || helpFilterField.activeFocus
        onMoveRequested: function(dx, dy) {
          if (root.actionHudExpanded && (dx !== 0 || dy !== 0))
            root.moveActionHud(dx !== 0 ? dx : dy)
          else if ((root.viewMode === "feed" || root.viewMode === "search") && dy !== 0)
            root.moveCursor(dy)
          else if (root.viewMode === "bookmarks" && dy !== 0) root.moveSavedCursor(dy)
          else if (root.viewMode === "history" && dy !== 0) root.moveHistoryCursor(dy)
          else if (root.viewMode === "read" && dy !== 0) root.moveReadCursor(dy)
          else if (root.viewMode === "event" && dy !== 0) eventPage.moveCursor(dy)
          else if (root.viewMode === "edition" && dy !== 0) editionPage.moveCursor(dy)
          else if (root.viewMode === "result" && dy !== 0)
            resultScroll.contentY = Math.max(0,
              Math.min(Math.max(0, resultScroll.contentHeight - resultScroll.height),
                resultScroll.contentY + dy * Style.space(70)))
          else if (root.viewMode === "help" && dx !== 0)
            root.setHelpTab(dx > 0 ? "feed" : "keys")
          else if (root.viewMode === "help" && dy !== 0)
            helpScroll.contentY = Math.max(0,
              Math.min(Math.max(0, helpScroll.contentHeight - helpScroll.height),
                helpScroll.contentY + dy * Style.space(70)))
          else if (root.viewMode === "profile" && dy !== 0)
            profilePage.scrollBy(dy)
          else if (root.viewMode === "about" && dy !== 0)
            aboutPage.scrollBy(dy)
        }
        onActivateRequested: {
          if (root.actionHudExpanded) root.runActionHudSelection()
          else if (root.viewMode === "feed" || root.viewMode === "search") root.openSelected()
          else if (root.viewMode === "bookmarks") root.showArticle(root.selectedBookmark)
          else if (root.viewMode === "history") root.showArticle(root.selectedHistoryArticle)
          else if (root.viewMode === "read") root.showArticle(root.selectedReadArticle)
          else if (root.viewMode === "event") eventPage.openSelected()
          else if (root.viewMode === "edition") editionPage.openSelected()
        }
        onCloseRequested: {
          if (root.actionHudExpanded) root.stepBackActionHud()
          else root.handleClose()
        }
        onDeleteRequested: {
          if (root.actionHudExpanded && root.actionHudPage === "main"
              && root.actionHudArticle && !Boolean(root.actionHudArticle.read))
            root.runActionHudAction("dismiss")
          else if (root.actionHudExpanded) root.tuneDirection = "less"
        }
        onTabRequested: {
          if (root.actionHudExpanded) root.moveActionHud(1)
          else if (root.viewMode === "alerts") alertField.forceActiveFocus()
          else if (root.viewMode === "feed" || root.viewMode === "search") root.focusSearch()
        }
        onTextKey: function(t) {
          if (root.actionHudExpanded) {
            root.handleActionHudKey(t)
            return
          }
          if (t === "?") root.showHelp()
          else if ((t === "g" || t === "G") && root.setupComplete) root.showEditions()
          else if ((t === "e" || t === "E") && root.isArticleContext()) root.showEventDesk()
          else if (root.viewMode === "help" && t === "1") root.setHelpTab("keys")
          else if (root.viewMode === "help" && t === "2") root.setHelpTab("feed")
          else if ((t === "a" || t === "A") && root.isArticleContext()
                   && root.currentArticle() !== null && !root.aiBusy)
            root.openActionHud(root.currentArticle())
          else if ((t === "i" || t === "I") && root.viewMode !== "setup")
            root.showAbout()
          else if (t === "r" || t === "R") root.refresh(false)
          else if ((t === "s" || t === "S" || t === "t" || t === "T")
                   && root.isArticleContext() && root.currentArticle() !== null
                   && !root.aiBusy) {
            if (root.viewMode === "result" && root.resultKind === "ai")
              root.showArticle(root.activeArticle)
            else root.summarizeArticle(root.currentArticle())
          }
          else if ((t === "o" || t === "O")
                   && (root.viewMode === "feed" || root.viewMode === "search"
                     || root.viewMode === "bookmarks" || root.viewMode === "history"
                     || root.viewMode === "read"))
            root.openArticle()
          else if ((t === "o" || t === "O") && root.viewMode === "result" && root.resultUrl !== "")
            root.openArticle()
          else if (t === "=" && root.isArticleContext()
                   && root.currentArticle() !== null && !root.aiBusy)
            root.sendArticleFeedback(root.currentArticle(), "more")
          else if ((t === "f" || t === "F") && root.isArticleContext()
                   && root.currentArticle() !== null
                   && !root.aiBusy)
            root.sendArticleFeedback(root.currentArticle(), "follow")
          else if (t === "-" && root.isArticleContext()
                   && root.currentArticle() !== null && !root.aiBusy)
            root.sendArticleFeedback(root.currentArticle(), "less")
          else if ((t === "n" || t === "N") && root.viewMode !== "setup")
            root.showAlerts()
          else if ((t === "v" || t === "V") && root.viewMode !== "setup")
            root.showBookmarks()
          else if ((t === "h" || t === "H") && root.viewMode !== "setup")
            root.showHistory()
          else if ((t === "p" || t === "P") && root.viewMode !== "setup")
            root.showProfile()
          else if ((t === "c" || t === "C")
                   && (root.viewMode === "feed" || root.viewMode === "search"
                     || root.viewMode === "profile"))
            root.showSetup()
          else if ((t === "m" || t === "M")
                   && (root.viewMode === "feed" || root.viewMode === "search"
                     || root.viewMode === "bookmarks" || root.viewMode === "history"
                     || root.viewMode === "read"
                     || root.viewMode === "result"))
            root.toggleBookmark(root.currentArticle())
          else if ((t === "d" || t === "D")
                   && (root.viewMode === "feed" || root.viewMode === "search"
                     || root.viewMode === "bookmarks" || root.viewMode === "history"
                     || root.viewMode === "read"
                     || root.viewMode === "result"))
            root.activateReadAction(root.currentArticle())
          else if (t === "/" && root.viewMode === "help")
            root.focusHelpFilter()
          else if (t === "/"
                   && (root.viewMode === "feed" || root.viewMode === "search"))
            root.focusSearch()
          else if ((t === "b" || t === "B") && root.viewMode !== "feed")
            root.navigateBack()
          else if (t === "q" || t === "Q") root.requestClose()
        }

        Item {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(52)

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            PyinMasthead {
              id: mastheadLogo
              foreground: root.foreground
              background: root.background
              accent: root.accent
              dim: root.dim
              fontFamily: root.fontFamily
              animate: root.animateLogo
              active: root.opened
              autoAnimate: root.viewMode === "feed" || root.viewMode === "search"
              enabled: root.viewMode !== "setup"
              onClicked: {
                if (root.viewMode === "about") mastheadLogo.replay()
                else root.showAbout()
              }
            }

            Text {
              textFormat: Text.PlainText
              width: Math.max(0, header.width - (actionGroup.visible
                ? actionGroup.width + Style.spacing.lg : 0))
              elide: Text.ElideRight
              text: mastheadLogo.overworked ? mastheadLogo.prankText
                : (mastheadLogo.hovered ? "Why PYIN? Open the story."
                  : "Your news. Your choices. Less noise.")
              color: mastheadLogo.overworked ? root.accent
                : (mastheadLogo.hovered ? root.foreground : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption

              Behavior on color { ColorAnimation { duration: 120 } }
            }
          }

          BorderSurface {
            id: actionGroup
            visible: root.setupComplete && root.viewMode !== "setup"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? actionButtons.implicitWidth : 0
            height: visible ? actionButtons.implicitHeight : 0
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

            Row {
              id: actionButtons

              Button {
                visible: root.viewMode !== "feed"
                iconText: "󰁍"
                tooltipText: root.viewMode === "search"
                  ? "Clear search and return to feed"
                  : (root.viewMode === "result" && root.eventArticleOpen ? "Return to coverage"
                  : (root.viewMode === "result" && !root.editionReaderActive() && root.articleBackMarksRead
                    && root.activeArticle && !Boolean(root.activeArticle.read)
                    ? "Mark read, hide, and return to the main feed" : "Back"))
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                onClicked: root.navigateBack()
              }

              Button {
                id: mainFeedButton
                iconText: "󰎕"
                tooltipText: "Main feed"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                selected: root.navigationContext() === "feed"
                onClicked: root.showMainFeed()
              }

              Button {
                id: editionsButton
                iconText: "󰃭"
                tooltipText: "Daily Editions · G"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                selected: root.navigationContext() === "edition"
                onClicked: root.showEditions()
              }

              Item {
                id: readLaterAction
                visible: root.menuItemEnabled("bookmarks")
                implicitWidth: readLaterButton.implicitWidth + Style.space(3)
                implicitHeight: readLaterButton.implicitHeight
                width: implicitWidth
                height: implicitHeight

                Button {
                  id: readLaterButton
                  anchors.fill: parent
                  iconText: "󰃀"
                  tooltipText: "Read Later · " + String(root.bookmarkCount)
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  focusable: true
                  horizontalPadding: Style.spacing.sm
                  selected: root.navigationContext() === "bookmarks"
                  onClicked: root.showBookmarks()
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.topMargin: Style.space(1)
                  anchors.rightMargin: Style.space(1)
                  z: 2
                  width: Math.max(height, readLaterCount.implicitWidth + Style.space(5))
                  height: Style.space(14)
                  radius: height / 2
                  color: root.accent
                  border.width: Math.max(1, Style.normalBorderWidth)
                  border.color: root.background

                  Text {
                    id: readLaterCount
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.bookmarkCount > 99
                      ? "99+" : String(root.bookmarkCount)
                    color: root.background
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(8, Style.font.caption - 2)
                    font.bold: true
                  }
                }
              }

              Button {
                visible: root.menuItemEnabled("history")
                iconText: "󰋚"
                tooltipText: "History · " + String(root.historyCount)
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                selected: root.navigationContext() === "history"
                onClicked: root.showHistory()
              }

              Button {
                visible: root.menuItemEnabled("alerts")
                iconText: "󰂚"
                tooltipText: "Subject alerts · " + String(root.alertCount)
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                selected: root.navigationContext() === "alerts"
                onClicked: root.showAlerts()
              }

              Button {
                iconText: "󰀄"
                tooltipText: "Curation profile and app settings"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                selected: root.navigationContext() === "profile"
                onClicked: root.showProfile()
              }

              Button {
                iconText: "󰋗"
                tooltipText: "Keyboard and feed-control reference · ?"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: true
                horizontalPadding: Style.spacing.sm
                selected: root.navigationContext() === "help"
                onClicked: root.showHelp()
              }

              Rectangle {
                visible: root.menuItemEnabled("refresh")
                width: Style.spacing.hairline
                height: Style.space(24)
                anchors.verticalCenter: parent.verticalCenter
                color: root.foreground
                opacity: 0.16
              }

              Button {
                visible: root.menuItemEnabled("refresh")
                width: Style.space(50)
                height: mainFeedButton.implicitHeight
                text: root.refreshChipText
                tooltipText: root.refreshChipTooltip
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                focusable: true
                horizontalPadding: 0
                active: refreshProc.running || root.refreshOutcomeText !== ""
                enabled: !refreshProc.running
                onClicked: root.refresh(false)
              }
            }
          }

          Item {
            id: refreshProgressTrack
            visible: root.menuItemEnabled("refresh") && refreshProc.running
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(1, Style.normalBorderWidth)
            clip: true

            Rectangle {
              id: refreshProgressSweep
              width: Math.max(Style.space(86), refreshProgressTrack.width * 0.22)
              height: parent.height
              color: root.accent

              NumberAnimation on x {
                running: refreshProgressTrack.visible
                loops: Animation.Infinite
                from: -refreshProgressSweep.width
                to: refreshProgressTrack.width
                duration: 920
                easing.type: Easing.InOutQuad
              }
            }
          }
        }

        Item {
          id: searchRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: Style.spacing.sm
          visible: root.viewMode === "feed" || root.viewMode === "search"
          height: visible ? Math.max(searchField.implicitHeight, searchButton.implicitHeight) : 0

          TextField {
            id: searchField
            anchors.left: parent.left
            anchors.right: searchButton.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Search every cached news source…  (press /)"
            foreground: root.foreground
            font.family: root.fontFamily
            enabled: !searchProc.running

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.viewMode === "search" || searchField.text.length > 0)
                  root.clearSearch()
                else keyCatcher.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.searchNews()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                keyCatcher.forceActiveFocus()
                root.cursorActive = true
                event.accepted = true
              }
            }
          }

          Button {
            id: searchButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: searchProc.running ? "󰦖" : "󰍉"
            iconSpinning: searchProc.running
            tooltipText: "Search all cached sources · no AI"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            focusable: true
            enabled: searchField.text.trim().length >= 2 && !searchProc.running
            onClicked: root.searchNews()
          }
        }

        Item {
          id: body
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: searchRow.visible ? searchRow.bottom : header.bottom
          anchors.topMargin: Style.spacing.panelGap
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.spacing.md

          SetupWizard {
            id: setupWizard
            backendPath: root.backendPath
            systemAiStatus: root.systemAiStatus
            aiModelCatalog: root.aiModelCatalog
            aiModelsLoading: aiModelsProc.running
            onAiModelsRequested: function(refresh) { root.loadAiModels(refresh) }
            anchors.fill: parent
            visible: root.viewMode === "setup"
            profile: root.setupProfile
            catalogs: root.setupData && root.setupData.catalogs
              ? root.setupData.catalogs : ({})
            sourceSummary: root.setupData && root.setupData.sources
              ? root.setupData.sources : ({})
            profileRevision: root.setupRevision
            saving: setupSaveProc.running
            foreground: root.foreground
            background: root.background
            accent: root.accent
            dim: root.dim
            fontFamily: root.fontFamily
            onSaveRequested: function(profile) { root.saveSetup(profile) }
            onCancelRequested: root.cancelSetup()
          }

          AboutPage {
            id: aboutPage
            anchors.fill: parent
            visible: root.viewMode === "about"
            foreground: root.foreground
            background: root.background
            accent: root.accent
            dim: root.dim
            fontFamily: root.fontFamily
            onOpenWebsiteRequested: Quickshell.execDetached([
              "omarchy-launch-browser", "https://www.chuchua.tech/"
            ])
            onOpenStoryRequested: Quickshell.execDetached([
              "omarchy-launch-browser", "https://www.chuchua.tech/blog/why-we-built-chuchua.tech"
            ])
            onOpenLanguageRequested: Quickshell.execDetached([
              "omarchy-launch-browser", "https://secwepemc.net/language/reader"
            ])
            onFeedbackRequested: function(category, message) {
              var subject = "PYIN News feedback · " + String(category || "Feedback")
              var bodyText = String(message || "")
                + "\n\n—\nSent from PYIN News for Omarchy"
              var mailtoUrl = "mailto:pyin-news-feedback@chuchua.tech?subject="
                + encodeURIComponent(subject) + "&body=" + encodeURIComponent(bodyText)
              var opened = Qt.openUrlExternally(mailtoUrl)
              aboutPage.feedbackDraftOpened(opened)
              root.statusText = opened
                ? "Feedback draft opened · review it in your email app"
                : "Could not open an email app"
            }
            onKeyboardRequested: keyCatcher.forceActiveFocus()
          }

          ListView {
            id: headlineList
            anchors.fill: parent
            visible: (root.viewMode === "feed" || root.viewMode === "search")
              && root.visibleArticles.length > 0
            clip: true
            spacing: Style.spacing.sm
            model: root.visibleArticles
            currentIndex: root.selectedIndex
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: root.queueVisibleImpressions()
            onContentHeightChanged: root.queueVisibleImpressions()
            onHeightChanged: root.queueVisibleImpressions()
            onWidthChanged: root.queueVisibleImpressions()
            onVisibleChanged: root.queueVisibleImpressions()

            delegate: CursorSurface {
              required property var modelData
              required property int index
              readonly property bool leavingFeed:
                root.visualHideIds.indexOf(String(modelData.id)) !== -1
              width: headlineList.width
              height: leavingFeed ? 0 : root.storyRowHeight
              opacity: leavingFeed ? 0 : 1
              foreground: root.foreground
              accent: root.accent
              hasCursor: root.cursorActive && index === root.selectedIndex
              clip: true

              StorySeparator {
                visible: root.storySeparators && index < headlineList.count - 1
              }

              Behavior on height {
                NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
              }
              Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
              }

              Item {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                anchors.topMargin: Style.spacing.lg
                anchors.bottomMargin: Style.spacing.lg

                Row {
                  id: storyMeta
                  anchors.left: parent.left
                  anchors.top: parent.top
                  spacing: Style.spacing.controlGap

                  Text {
                    textFormat: Text.PlainText
                    text: String(modelData.source || "").toUpperCase()
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.7
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.age || ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "· " + (modelData.reason || "fresh")
                      + (Number(modelData.coverage_count || 1) > 1
                        ? " · " + String(modelData.coverage_count) + " sources" : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  id: storyTitle
                  anchors.left: parent.left
                  anchors.right: bookmarkMark.visible ? bookmarkMark.left : unreadMark.left
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: storyMeta.bottom
                  anchors.topMargin: Style.spacing.xs
                  textFormat: Text.PlainText
                  text: modelData.title || "Untitled"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: !modelData.opened
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                  elide: Text.ElideRight
                }

                Text {
                  id: bookmarkMark
                  anchors.right: unreadMark.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: storyTitle.verticalCenter
                  visible: Boolean(modelData.bookmarked)
                  textFormat: Text.PlainText
                  text: "󰃀"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: storyTitle.bottom
                  anchors.topMargin: Style.spacing.xs
                  textFormat: Text.PlainText
                  text: modelData.summary || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  maximumLineCount: 1
                  elide: Text.ElideRight
                }

                Rectangle {
                  id: unreadMark
                  anchors.right: parent.right
                  anchors.verticalCenter: storyTitle.verticalCenter
                  width: Style.spacing.md
                  height: width
                  radius: width / 2
                  color: modelData.opened ? "transparent" : root.accent
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: function(mouse) {
                  root.selectedIndex = index
                  if (mouse.button === Qt.RightButton) root.summarizeSelected()
                  else root.openSelected()
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            visible: (root.viewMode === "feed" || root.viewMode === "search")
              && root.visibleArticles.length === 0
            width: Math.min(parent.width, Style.space(440))
            spacing: Style.spacing.lg
            property bool initialFeedLoading: root.viewMode === "feed"
              && bootstrapProc.running

            Item {
              width: parent.width
              height: parent.initialFeedLoading ? Style.space(92) : Style.space(58)

              PyinMasthead {
                anchors.centerIn: parent
                visible: parent.parent.initialFeedLoading
                foreground: root.foreground
                background: root.background
                accent: root.accent
                dim: root.dim
                fontFamily: root.fontFamily
                animate: root.animateLogo
                active: visible
                autoAnimate: false
                loading: visible
                enabled: false
                cellWidth: Style.space(48)
                cellHeight: Style.space(58)
                cellSpacing: Style.space(7)
                glyphSize: Style.space(28)
              }

              Text {
                anchors.centerIn: parent
                visible: !parent.parent.initialFeedLoading
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                text: (loadProc.running || refreshProc.running || searchProc.running)
                  ? "󰦖" : "󰎕"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge

                RotationAnimator on rotation {
                  running: parent.visible
                    && (loadProc.running || refreshProc.running || searchProc.running)
                  from: 0; to: 360
                  duration: 900
                  loops: Animation.Infinite
                }
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              text: root.viewMode === "search"
                ? (searchProc.running ? "Searching every cached source…"
                  : "No matches across the local news catalog.")
                : ((bootstrapProc.running || loadProc.running || refreshProc.running)
                  ? "Building your personalized local feed…"
                  : (Number(root.feedStats.read_hidden || 0) > 0
                    ? "You're caught up. Read stories stay hidden; restore them from Profile → Read."
                    : "No cached stories yet. Press R to refresh."))
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
          }

          EventDeskPage {
            id: eventPage
            anchors.fill: parent
            visible: root.viewMode === "event"
            coverage: root.eventData
            busy: root.eventLoadActive || root.pendingEventLoad
            visitError: root.eventVisitError
            compact: root.compactDensity
            separators: root.storySeparators
            onArticleRequested: function(article) { root.showEventArticle(article) }
            onRetryRequested: root.loadEventDesk()
          }

          DailyEditionPage {
            id: editionPage
            anchors.fill: parent
            visible: root.viewMode === "edition"
            edition: root.editionData
            busy: root.editionRequestActive
            errorText: root.editionError
            compact: root.compactDensity
            separators: root.storySeparators
            onStartRequested: function(minutes) { root.startEdition(minutes) }
            onArticleRequested: function(article) { root.openEditionArticle(article) }
            onRetryRequested: root.runEdition([], "load", "")
          }

          Flickable {
            id: resultScroll
            anchors.fill: parent
            visible: root.viewMode === "result"
            clip: true
            contentWidth: width
            contentHeight: resultColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: resultColumn
              width: resultScroll.width
              spacing: Style.spacing.panelGap

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.resultTitle
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                wrapMode: Text.Wrap
              }

              Item {
                id: resultSourceRow
                width: parent.width
                visible: root.resultProvider !== "" || resultCoverageButton.visible
                height: Math.max(resultProviderText.implicitHeight,
                  resultCoverageButton.visible ? resultCoverageButton.implicitHeight : 0)

                Text {
                  id: resultProviderText
                  anchors.left: parent.left
                  anchors.right: resultCoverageButton.visible ? resultCoverageButton.left : parent.right
                  anchors.rightMargin: resultCoverageButton.visible ? Style.spacing.md : 0
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.resultProvider
                  wrapMode: Text.Wrap
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.7
                }

                Button {
                  id: resultCoverageButton
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.activeArticle !== null
                  text: "Coverage"
                  tooltipText: root.eventArticleOpen
                    ? "Back to coverage · E" : "More reporting on this story · E"
                  foreground: root.accent
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.xs
                  focusable: true
                  enabled: !root.aiBusy
                  onClicked: root.showEventDesk()
                }
              }

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.foreground
                opacity: 0.12
              }

              Row {
                id: resultActionBar
                width: parent.width
                spacing: Style.spacing.md
                property int visibleCount: resultSummaryButton.visible ? 4 : 3
                property real buttonWidth: (width - spacing * (visibleCount - 1))
                  / visibleCount

                Button {
                  id: resultSummaryButton
                  visible: root.aiEnabled && root.activeArticleId !== ""
                  width: visible ? resultActionBar.buttonWidth : 0
                  text: root.aiBusy
                    ? (root.aiHasOutput ? "Streaming…" : "Preparing…")
                    : (root.resultKind === "ai" ? "Synopsis" : "AI TL;DR")
                  iconText: root.aiBusy ? "󰦖"
                    : (root.resultKind === "ai" ? "󰓰" : "󰚩")
                  iconSpinning: root.aiBusy
                  tooltipText: root.aiBusy
                    ? "The source-bound answer is arriving live"
                    : (root.resultKind === "ai"
                    ? "Return to the feed-provided synopsis"
                    : "Create a source-bounded summary with " + root.aiLabel + " · S")
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  focusable: true
                  bordered: true
                  selected: root.resultKind === "ai" && !root.aiBusy
                  enabled: !root.aiBusy
                  onClicked: {
                    root.closeActionHud()
                    if (root.resultKind === "ai") root.showArticle(root.activeArticle)
                    else root.summarizeArticle(root.activeArticle)
                  }
                }

                Button {
                  width: resultActionBar.buttonWidth
                  text: root.activeArticle && Boolean(root.activeArticle.bookmarked)
                    ? "Saved" : "Save"
                  iconText: bookmarkMutationProc.running ? "󰦖"
                    : (root.activeArticle && Boolean(root.activeArticle.bookmarked)
                      ? "󰆴" : "󰃀")
                  iconSpinning: bookmarkMutationProc.running
                  tooltipText: root.activeArticle && Boolean(root.activeArticle.bookmarked)
                    ? "Remove from Read Later · M" : "Save to Read Later · M"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  focusable: true
                  bordered: true
                  enabled: root.activeArticle !== null && !bookmarkMutationProc.running
                  onClicked: root.toggleBookmark(root.activeArticle)
                }

                Button {
                  width: resultActionBar.buttonWidth
                  text: "Original"
                  iconText: "󰏌"
                  tooltipText: "Open the publisher's original article · O"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  focusable: true
                  bordered: true
                  enabled: root.resultUrl !== ""
                  onClicked: root.openArticle()
                }

                Button {
                  id: resultActionsButton
                  width: resultActionBar.buttonWidth
                  text: "Actions"
                  iconText: "󰍜"
                  tooltipText: "Article Actions HUD · A"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  focusable: true
                  bordered: true
                  selected: root.actionHudExpanded
                  enabled: root.activeArticle !== null && !root.aiBusy
                  onClicked: {
                    if (root.actionHudExpanded) root.closeActionHud()
                    else root.openActionHud(root.activeArticle)
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                text: root.aiEnabled
                  ? "S/T  TL;DR   ·   M  save   ·   O  original   ·   A  actions"
                  : "M  save   ·   O  original   ·   A  actions"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: 0.8
                wrapMode: Text.Wrap
              }

              Item {
                id: aiLoaderFrame
                width: parent.width
                height: root.resultKind === "ai" && root.aiBusy && !root.aiHasOutput
                  ? journalismLoader.implicitHeight : 0
                visible: height > 0
                clip: true
                opacity: root.aiHasOutput ? 0 : 1

                Behavior on height {
                  NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                  NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                }

                JournalismLoader {
                  id: journalismLoader
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  phaseText: root.aiStreamPhase
                  foreground: root.foreground
                  accent: root.accent
                  dim: root.dim
                  fontFamily: root.fontFamily
                }
              }

              BorderSurface {
                id: aiLiveSurface
                width: parent.width
                visible: root.resultKind === "ai" && root.aiHasOutput
                implicitHeight: Style.space(54)
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
                opacity: visible ? 1 : 0

                Behavior on opacity {
                  NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                Rectangle {
                  id: aiLiveDot
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.aiStreamFailed ? root.foreground : root.accent

                  SequentialAnimation on opacity {
                    running: aiLiveSurface.visible && root.aiBusy
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
                  }
                }

                Text {
                  id: aiLiveLabel
                  anchors.left: aiLiveDot.right
                  anchors.leftMargin: Style.spacing.sm
                  anchors.right: aiLiveCount.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "PYIN // " + (root.aiStreamPhase || "LIVE SOURCE DESK")
                  color: root.aiStreamFailed ? root.foreground : root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.85
                  elide: Text.ElideRight
                }

                Text {
                  id: aiLiveCount
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: {
                    var value = root.resultText.trim()
                    return (value ? value.split(/\s+/).length : 0) + " WORDS"
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.65
                }

                Rectangle {
                  id: aiStreamTrack
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.spacing.lg
                  anchors.rightMargin: Style.spacing.lg
                  anchors.bottomMargin: Math.max(1, Style.normalBorderWidth)
                  height: Math.max(1, Style.normalBorderWidth)
                  color: root.accent
                  opacity: root.aiBusy ? 0.14 : 0.5
                  clip: true

                  Rectangle {
                    id: aiStreamSweep
                    width: Math.max(Style.space(48), parent.width * 0.28)
                    height: parent.height
                    color: root.accent
                    opacity: 0.95

                    SequentialAnimation on x {
                      running: aiLiveSurface.visible && root.aiBusy
                      loops: Animation.Infinite
                      NumberAnimation {
                        from: -aiStreamSweep.width
                        to: aiStreamTrack.width
                        duration: 1120
                        easing.type: Easing.InOutQuad
                      }
                      PauseAnimation { duration: 120 }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                visible: root.resultKind !== "ai" || root.aiHasOutput
                textFormat: Text.PlainText
                text: root.resultText
                  + (root.resultKind === "ai" && root.aiBusy && root.aiHasOutput
                    ? (root.aiCursorVisible ? "█" : " ") : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                lineHeight: 1.35
                wrapMode: Text.Wrap
                opacity: visible ? 1 : 0

                Behavior on opacity {
                  NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
              }

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                visible: root.activeArticle !== null
                color: root.foreground
                opacity: 0.08
              }

              Column {
                width: parent.width
                visible: root.editionReaderActive()
                spacing: Style.spacing.md
                Text {
                  width: parent.width
                  text: root.editionData ? String(root.editionData.completed) + " of "
                    + String(root.editionData.total) + " complete · Your edition stays fixed" : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }
                Flow {
                  width: parent.width
                  spacing: Style.spacing.sm
                  Button {
                    text: root.editionData && root.editionData.remaining > 1 ? "Done & next" : "Finish edition"
                    tooltipText: "Mark read and continue · D"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    focusable: true
                    enabled: !root.editionRequestActive && !root.aiBusy
                      && root.activeArticle !== null && root.activeArticle.edition_status === "pending"
                    onClicked: root.completeEditionStory("done")
                  }
                  Button {
                    text: "Skip"
                    tooltipText: "Move on without hiding this story or teaching Show Less"
                    foreground: root.dim
                    accent: root.accent
                    fontFamily: root.fontFamily
                    focusable: true
                    enabled: !root.editionRequestActive && !root.aiBusy
                      && root.activeArticle !== null && root.activeArticle.edition_status === "pending"
                    onClicked: root.completeEditionStory("skip")
                  }
                  Button {
                    text: "Pause edition"
                    foreground: root.dim
                    accent: root.accent
                    fontFamily: root.fontFamily
                    focusable: true
                    onClicked: root.navigateBack()
                  }
                }
                Text {
                  width: parent.width
                  visible: root.editionError !== ""
                  text: root.editionError
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }
              }

              Button {
                visible: root.activeArticle !== null
                text: "Why this story?"
                iconText: root.whySectionExpanded ? "󰅀" : "󰅂"
                tooltipText: root.whySectionExpanded
                  ? "Hide local ranking details" : "Show why the local ranker selected this story"
                foreground: root.dim
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                leftAlign: true
                bordered: false
                horizontalPadding: 0
                verticalPadding: Style.spacing.xs
                onClicked: root.whySectionExpanded = !root.whySectionExpanded
              }

              Text {
                width: parent.width
                visible: root.whySectionExpanded && root.activeArticle !== null
                textFormat: Text.PlainText
                text: String(root.activeArticle && root.activeArticle.why_text
                  ? root.activeArticle.why_text : "recent reporting")
                  + "\n" + root.whyBreakdown()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                lineHeight: 1.3
                wrapMode: Text.Wrap
              }
            }
          }

          Item {
            id: bookmarksView
            anchors.fill: parent
            visible: root.viewMode === "bookmarks"

            Text {
              id: bookmarksTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              textFormat: Text.PlainText
              text: "READ LATER"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 0.8
            }

            Text {
              id: bookmarksDescription
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: bookmarksTitle.bottom
              anchors.topMargin: Style.spacing.sm
              textFormat: Text.PlainText
              text: "Saved stories stay on this device and are kept beyond the normal cache cleanup."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            ListView {
              id: savedList
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: bookmarksDescription.bottom
              anchors.topMargin: Style.spacing.panelGap
              anchors.bottom: parent.bottom
              clip: true
              spacing: Style.spacing.sm
              model: root.bookmarks
              currentIndex: root.savedIndex
              boundsBehavior: Flickable.StopAtBounds

              delegate: CursorSurface {
                required property var modelData
                required property int index
                width: savedList.width
                height: root.libraryStoryRowHeight
                foreground: root.foreground
                accent: root.accent
                hasCursor: root.savedCursorActive && index === root.savedIndex

                StorySeparator {
                  visible: root.storySeparators && index < savedList.count - 1
                }

                Text {
                  id: savedMeta
                  anchors.left: parent.left
                  anchors.right: savedRemoveButton.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: parent.top
                  anchors.topMargin: Style.spacing.lg
                  textFormat: Text.PlainText
                  text: String(modelData.source || "").toUpperCase()
                    + "  ·  " + String(modelData.age || "")
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: savedRemoveButton.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: savedMeta.bottom
                  anchors.topMargin: Style.spacing.xs
                  textFormat: Text.PlainText
                  text: modelData.title || "Untitled"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                  elide: Text.ElideRight
                }

                Button {
                  id: savedRemoveButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Remove"
                  iconText: "󰆴"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !bookmarkMutationProc.running
                  onClicked: root.toggleBookmark(modelData)
                }

                MouseArea {
                  anchors.left: parent.left
                  anchors.right: savedRemoveButton.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.savedCursorActive = true
                    root.savedIndex = index
                  }
                  onClicked: function(mouse) {
                    root.savedIndex = index
                    if (mouse.button === Qt.RightButton) root.summarizeArticle(modelData)
                    else root.showArticle(modelData)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: savedList
              visible: root.bookmarks.length === 0 && !bookmarksProc.running
              width: Math.min(savedList.width, Style.space(420))
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              text: "Nothing saved yet. Select a headline and press M, or use Save for later from its synopsis."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
          }

          Item {
            id: historyView
            anchors.fill: parent
            visible: root.viewMode === "history"

            Text {
              id: historyTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              textFormat: Text.PlainText
              text: "HISTORY"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 0.8
            }

            Text {
              id: historyDescription
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: historyTitle.bottom
              anchors.topMargin: Style.spacing.sm
              textFormat: Text.PlainText
              text: "Stories you deliberately opened, newest view first. This list stays on this device and remains visible even when learning is disabled."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            Row {
              id: historyTabs
              anchors.left: parent.left
              anchors.top: historyDescription.bottom
              anchors.topMargin: Style.spacing.lg
              spacing: Style.spacing.sm

              Button {
                text: "Viewed · " + String(root.historyCount)
                iconText: "󰋚"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                selected: true
                onClicked: root.showHistory()
              }

              Button {
                text: "Hidden · " + String(root.readCount)
                iconText: "󰄬"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                onClicked: root.showReadArticles()
              }
            }

            ListView {
              id: historyList
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: historyTabs.bottom
              anchors.topMargin: Style.spacing.panelGap
              anchors.bottom: parent.bottom
              clip: true
              spacing: Style.spacing.sm
              model: root.historyArticles
              currentIndex: root.historyIndex
              boundsBehavior: Flickable.StopAtBounds

              delegate: CursorSurface {
                required property var modelData
                required property int index
                width: historyList.width
                height: root.libraryStoryRowHeight
                foreground: root.foreground
                accent: root.accent
                hasCursor: root.historyCursorActive && index === root.historyIndex

                StorySeparator {
                  visible: root.storySeparators && index < historyList.count - 1
                }

                Text {
                  id: historyMeta
                  anchors.left: parent.left
                  anchors.right: historyState.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: parent.top
                  anchors.topMargin: Style.spacing.lg
                  textFormat: Text.PlainText
                  text: String(modelData.source || "").toUpperCase()
                    + "  ·  VIEWED " + String(modelData.viewed_age || "now") + " AGO"
                    + (Number(modelData.opens || 0) > 1
                      ? "  ·  " + String(modelData.opens) + " OPENS" : "")
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: historyState.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: historyMeta.bottom
                  anchors.topMargin: Style.spacing.xs
                  textFormat: Text.PlainText
                  text: modelData.title || "Untitled"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                  elide: Text.ElideRight
                }

                Text {
                  id: historyState
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: (Boolean(modelData.bookmarked) ? "󰃀" : "")
                    + (Boolean(modelData.read) ? " 󰄬" : "")
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.historyCursorActive = true
                    root.historyIndex = index
                  }
                  onClicked: function(mouse) {
                    root.historyIndex = index
                    if (mouse.button === Qt.RightButton) root.summarizeArticle(modelData)
                    else root.showArticle(modelData)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: historyList
              visible: root.historyArticles.length === 0 && !historyProc.running
              width: Math.min(historyList.width, Style.space(420))
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              text: "No viewed stories yet. Opening a feed synopsis adds it here without requiring AI."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
          }

          Item {
            id: readView
            anchors.fill: parent
            visible: root.viewMode === "read"

            Text {
              id: readTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              textFormat: Text.PlainText
              text: "HISTORY"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 0.8
            }

            Text {
              id: readDescription
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: readTitle.bottom
              anchors.topMargin: Style.spacing.sm
              textFormat: Text.PlainText
              text: "Marked and dismissed stories stay out of the ranked feed. Restoring a Show Less dismissal also reverses the small ranking signal it created."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            Row {
              id: readHistoryTabs
              anchors.left: parent.left
              anchors.top: readDescription.bottom
              anchors.topMargin: Style.spacing.lg
              spacing: Style.spacing.sm

              Button {
                text: "Viewed · " + String(root.historyCount)
                iconText: "󰋚"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                onClicked: root.showHistory()
              }

              Button {
                text: "Hidden · " + String(root.readCount)
                iconText: "󰄬"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                selected: true
                onClicked: root.showReadArticles()
              }
            }

            ListView {
              id: readList
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: readHistoryTabs.bottom
              anchors.topMargin: Style.spacing.panelGap
              anchors.bottom: parent.bottom
              clip: true
              spacing: Style.spacing.sm
              model: root.readArticles
              currentIndex: root.readIndex
              boundsBehavior: Flickable.StopAtBounds

              delegate: CursorSurface {
                required property var modelData
                required property int index
                width: readList.width
                height: root.libraryStoryRowHeight
                foreground: root.foreground
                accent: root.accent
                hasCursor: root.readCursorActive && index === root.readIndex

                StorySeparator {
                  visible: root.storySeparators && index < readList.count - 1
                }

                Text {
                  id: readMeta
                  anchors.left: parent.left
                  anchors.right: restoreReadButton.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: parent.top
                  anchors.topMargin: Style.spacing.lg
                  textFormat: Text.PlainText
                  text: String(modelData.source || "").toUpperCase()
                    + "  ·  " + String(modelData.age || "")
                    + (Boolean(modelData.dismissed) ? "  ·  SHOW LESS" : "  ·  READ")
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: restoreReadButton.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.top: readMeta.bottom
                  anchors.topMargin: Style.spacing.xs
                  textFormat: Text.PlainText
                  text: modelData.title || "Untitled"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                  elide: Text.ElideRight
                }

                Button {
                  id: restoreReadButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Restore"
                  iconText: readMutationProc.running || dismissProc.running ? "󰦖" : "󰁍"
                  iconSpinning: readMutationProc.running || dismissProc.running
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !readProc.running && !readMutationProc.running && !dismissProc.running
                  onClicked: root.toggleRead(modelData)
                }

                MouseArea {
                  anchors.left: parent.left
                  anchors.right: restoreReadButton.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.readCursorActive = true
                    root.readIndex = index
                  }
                  onClicked: function(mouse) {
                    root.readIndex = index
                    if (mouse.button === Qt.RightButton) root.summarizeArticle(modelData)
                    else root.showArticle(modelData)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: readList
              visible: root.readArticles.length === 0 && !readProc.running
              width: Math.min(readList.width, Style.space(420))
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              text: "No stories are hidden. Press D to mark one read, or Backspace to dismiss it and request fewer similar stories."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
          }

          Item {
            id: alertsView
            anchors.fill: parent
            visible: root.viewMode === "alerts"

            Text {
              id: alertsTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              textFormat: Text.PlainText
              text: "SUBJECT ALERTS"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 0.8
            }

            Text {
              id: alertsDescription
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: alertsTitle.bottom
              anchors.topMargin: Style.spacing.sm
              textFormat: Text.PlainText
              text: "Get an Omarchy notification when a newly fetched story matches all significant words. Click an individual alert to open that exact story in PYIN. Matching is local and does not invoke AI."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            Item {
              id: alertEntryRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: alertsDescription.bottom
              anchors.topMargin: Style.spacing.panelGap
              height: Math.max(alertField.implicitHeight, addAlertButton.implicitHeight)

              TextField {
                id: alertField
                anchors.left: parent.left
                anchors.right: addAlertButton.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Alert subject, e.g. war in Iran"
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                enabled: !alertMutationProc.running

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.addAlert()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    if (text.length > 0) text = ""
                    else root.backToFeed()
                    event.accepted = true
                  }
                }
              }

              Button {
                id: addAlertButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Create alert"
                iconText: alertMutationProc.running ? "󰦖" : "󰂞"
                iconSpinning: alertMutationProc.running
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                bordered: true
                enabled: alertField.text.trim().length > 0 && !alertMutationProc.running
                onClicked: root.addAlert()
              }
            }

            ListView {
              id: alertsList
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: alertEntryRow.bottom
              anchors.topMargin: Style.spacing.panelGap
              anchors.bottom: parent.bottom
              clip: true
              spacing: Style.spacing.sm
              model: root.alerts
              boundsBehavior: Flickable.StopAtBounds

              delegate: CursorSurface {
                required property var modelData
                required property int index
                width: alertsList.width
                height: Style.space(66)
                foreground: root.foreground
                accent: root.accent

                Text {
                  anchors.left: parent.left
                  anchors.right: removeAlertButton.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.query || "Untitled alert"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Button {
                  id: removeAlertButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Remove"
                  iconText: "󰆴"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !alertMutationProc.running
                  onClicked: root.removeAlert(Number(modelData.id))
                }
              }
            }

            Text {
              anchors.centerIn: alertsList
              visible: root.alerts.length === 0 && !alertsProc.running
              width: Math.min(alertsList.width, Style.space(420))
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              text: "No alerts yet. Add a subject above and PYIN will watch future feed refreshes."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
          }

          ProfilePage {
            id: profilePage
            anchors.fill: parent
            visible: root.viewMode === "profile"
            foreground: root.foreground
            background: root.background
            accent: root.accent
            dim: root.dim
            fontFamily: root.fontFamily
            navigationItems: root.navigationItems
            alertCount: root.alertCount
            bookmarkCount: root.bookmarkCount
            historyCount: root.historyCount
            readCount: root.readCount
            topicSummary: root.profileTopicLabels()
            setupSummaryText: root.setupSummary() + "\n" + root.setupLocationSummary()
            setupDetailsText: root.setupChoiceDetails()
            sourceMixText: root.sourceMixSummary()
            aiProvider: root.aiProvider
            aiSummary: root.aiProvider === "system"
              ? String(root.systemAiStatus.message || "Checking selected agent…") + "\n"
                + (root.systemAiStatus.available === false ? "" : root.systemAiSummary)
              : (root.aiProvider === "local"
                ? "Local server · " + root.localAiModel
                : "AI summaries are disabled.")
            systemAiModel: root.systemAiModel
            systemAiEffort: root.systemAiEffort
            aiModelCatalog: root.aiModelCatalog
            aiModelsLoading: aiModelsProc.running
            systemAiAvailable: root.systemAiStatus.available !== false
            articleBackMarksRead: root.articleBackMarksRead
            footerLinkLabel: root.footerLinkLabel
            footerLinkUrl: root.footerLinkUrl
            interestNodes: root.profileInterestNodes
            learnedTerms: root.profileTerms
            recentDismissals: root.recentDismissals
            counts: root.profileCounts
            storage: root.profileStorage
            exposure: root.profileExposure
            updateData: root.applicationUpdateData
            sourceHealthData: root.sourceHealthData
            sourceHealthBusy: sourceHealthProc.running
            feedsRefreshing: refreshProc.running
            showLessTermText: root.showLessTermSummary()
            showLessSourceText: root.showLessSourceSummary()
            profileBusy: profileProc.running
            navigationBusy: navigationProc.running
            behaviorBusy: behaviorProc.running
            footerLinkBusy: footerLinkProc.running
            aiPresetBusy: systemAiPresetProc.running
            interestBusy: interestProc.running
            transferBusy: profileTransferProc.running
            resetBusy: profileResetProc.running || root.readingEventsBusy
            updateBusy: updateStatusProc.running
            updateLaunching: root.applicationUpdateLaunching
            confirmReset: root.confirmProfileReset

            onDestinationRequested: function(destination) {
              if (destination === "history") root.showHistory()
              else if (destination === "bookmarks") root.showBookmarks()
              else if (destination === "read") root.showReadArticles()
              else if (destination === "alerts") root.showAlerts()
            }
            onSetupPageRequested: function(pageNumber) { root.showSetupPage(pageNumber) }
            onSetupRequested: root.showSetup()
            onNavigationRequested: function(item, enabled) {
              root.setNavigationItemEnabled(item, enabled)
            }
            onBackBehaviorRequested: function(enabled) {
              root.setArticleBackMarksRead(enabled)
            }
            onFooterLinkRequested: function(label, url) {
              root.setFooterLink(label, url)
            }
            onAiModelRequested: function(model, effort) { root.setSystemAiModel(model, effort) }
            onAiModelsRequested: function(refresh) { root.loadAiModels(refresh) }
            onInterestRemoveRequested: function(term, scope) {
              root.removeInterestNode(term, scope)
            }
            onExportRequested: root.exportProfile()
            onImportRequested: root.importProfile()
            onResetRequested: root.resetProfileLearning()
            onUpdateCheckRequested: root.loadApplicationUpdateStatus(true)
            onUpdateInstallRequested: root.installApplicationUpdate()
            onSourceHealthRequested: root.loadSourceHealth()
            onFeedsRefreshRequested: root.refresh(false)
          }

          Flickable {
            id: helpScroll
            anchors.fill: parent
            visible: root.viewMode === "help"
            clip: true
            contentWidth: width
            contentHeight: helpColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: helpColumn
              width: helpScroll.width
              spacing: Style.spacing.panelGap

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "PYIN REFERENCE"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                font.letterSpacing: 0.8
              }

              BorderSurface {
                width: parent.width
                implicitHeight: helpTabs.implicitHeight
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                Row {
                  id: helpTabs
                  width: parent.width

                  Button {
                    width: helpTabs.width / 2
                    text: "1 · Keys"
                    iconText: "󰌌"
                    tooltipText: "Keyboard shortcuts"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    selected: root.helpTab === "keys"
                    onClicked: root.setHelpTab("keys")
                  }

                  Button {
                    width: helpTabs.width / 2
                    text: "2 · Feed controls"
                    iconText: "󰒕"
                    tooltipText: "What every option changes in your feed"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    selected: root.helpTab === "feed"
                    onClicked: root.setHelpTab("feed")
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.helpTab === "keys"
                  ? "Shortcuts follow the physical keyboard: number, QWERTY, home, bottom, then navigation keys. Press 1/2 or ←/→ to switch tabs, and / to search."
                  : "A plain-language ledger of what each setup, reading, and personalization choice actually changes. Nothing on this page invokes AI."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
              }

              TextField {
                id: helpFilterField
                width: parent.width
                placeholderText: root.helpTab === "keys"
                  ? "Filter keys and actions…  (press /)"
                  : "Filter feed controls and effects…  (press /)"
                text: root.helpQuery
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                onTextChanged: root.helpQuery = text

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (text.length > 0) {
                      text = ""
                      root.helpQuery = ""
                    } else keyCatcher.forceActiveFocus()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down
                             || event.key === Qt.Key_Return
                             || event.key === Qt.Key_Enter) {
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.foreground
                opacity: 0.12
              }

              Repeater {
                model: root.helpTab === "keys"
                  ? root.filteredHelpEntries() : root.filteredFeedControlEntries()

                delegate: Column {
                  required property var modelData
                  width: helpColumn.width
                  height: implicitHeight
                  spacing: Boolean(modelData.showSection) ? Style.spacing.sm : 0

                  Text {
                    visible: root.helpTab === "keys" && Boolean(modelData.showSection)
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(modelData.section || "")
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.0
                    wrapMode: Text.Wrap
                  }

                  Item {
                    width: parent.width
                    height: Math.max(helpKey.implicitHeight, helpAction.implicitHeight)

                    Text {
                      id: helpKey
                      anchors.left: parent.left
                      width: Math.min(parent.width * 0.34, Style.space(190))
                      textFormat: Text.PlainText
                      text: root.helpTab === "keys"
                        ? String(modelData.keys || "") : String(modelData.option || "")
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      wrapMode: Text.Wrap
                    }

                    Text {
                      id: helpAction
                      anchors.left: helpKey.right
                      anchors.leftMargin: Style.spacing.panelGap
                      anchors.right: parent.right
                      textFormat: Text.PlainText
                      text: root.helpTab === "keys"
                        ? String(modelData.action || "") : String(modelData.effect || "")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.Wrap
                    }
                  }
                }
              }

              Text {
                visible: root.helpTab === "keys"
                  ? root.filteredHelpEntries().length === 0
                  : root.filteredFeedControlEntries().length === 0
                width: parent.width
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                text: "No " + (root.helpTab === "keys" ? "shortcuts" : "feed controls")
                  + " match ‘" + root.helpQuery + "’."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }
            }
          }
        }

        Item {
          id: actionHudOverlay
          anchors.fill: body
          z: 100
          visible: root.actionHudExpanded
          opacity: root.actionHudExpanded ? 1 : 0

          Behavior on opacity {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
          }

          Rectangle {
            anchors.fill: parent
            color: root.background
            opacity: 0.72

            MouseArea {
              anchors.fill: parent
              onClicked: root.closeActionHud()
            }
          }

          BorderSurface {
            id: actionHudPanel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.lg
            width: Math.min(parent.width - Style.spacing.lg * 2, Style.space(690))
            height: Math.min(parent.height - Style.spacing.lg * 2,
              actionHudContent.implicitHeight + Style.spacing.panelPadding * 2)
            color: root.background
            radius: Style.cornerRadius
            clip: true
            borderSpec: Border.controlSpec("focus", root.foreground, root.accent)

            Flickable {
              id: actionHudScroll
              anchors.fill: parent
              anchors.margins: Style.spacing.panelPadding
              contentWidth: width
              contentHeight: actionHudContent.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true

              Column {
                id: actionHudContent
                width: parent.width
                spacing: Style.spacing.md

                Item {
                  width: parent.width
                  height: Math.max(actionHudHeading.implicitHeight, actionHudClose.implicitHeight)

                  Text {
                    id: actionHudHeading
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.actionHudPage === "tune"
                      ? "TUNE YOUR FEED" : "ARTICLE ACTIONS"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    font.letterSpacing: 0.9
                  }

                  Button {
                    id: actionHudClose
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.actionHudPage === "tune" ? "Back" : "Esc"
                    iconText: root.actionHudPage === "tune" ? "󰁍" : "󰅖"
                    tooltipText: root.actionHudPage === "tune"
                      ? "Return to Article Actions · B or Esc"
                      : "Close Article Actions · B or Esc"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    bordered: false
                    onClicked: root.stepBackActionHud()
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.actionHudArticle
                    ? String(root.actionHudArticle.title || "Untitled") : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  maximumLineCount: 1
                  elide: Text.ElideRight
                }

                Rectangle {
                  width: parent.width
                  height: Style.spacing.hairline
                  color: root.foreground
                  opacity: 0.12
                }

                Column {
                  id: mainActionPage
                  visible: root.actionHudPage === "main"
                  width: parent.width
                  spacing: Style.spacing.md

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Press a shown letter, or move with j/k and confirm with Enter."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                Grid {
                  id: actionHudGrid
                  width: parent.width
                  columns: width >= Style.space(500) ? 2 : 1
                  spacing: Style.spacing.sm

                  Repeater {
                    model: root.actionHudActions()

                    delegate: Button {
                      required property var modelData
                      required property int index
                      width: (actionHudGrid.width
                        - actionHudGrid.spacing * (actionHudGrid.columns - 1))
                        / actionHudGrid.columns
                      text: String(modelData.hotkey || "") + "  ·  "
                        + String(modelData.label || "")
                      iconText: ((modelData.key === "bookmark" && bookmarkMutationProc.running)
                        || (modelData.key === "read" && readMutationProc.running))
                        ? "󰦖" : String(modelData.icon || "")
                      iconSpinning: (modelData.key === "bookmark" && bookmarkMutationProc.running)
                        || (modelData.key === "read" && readMutationProc.running)
                      tooltipText: String(modelData.hint || "")
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      leftAlign: true
                      bordered: true
                      selected: index === root.actionHudIndex
                      horizontalPadding: Style.spacing.lg
                      verticalPadding: Style.spacing.md
                      enabled: !feedbackProc.running
                        && (modelData.key !== "summary" || !root.aiBusy)
                      onHovered: function(isHovered) {
                        if (isHovered) root.actionHudIndex = index
                      }
                      onClicked: {
                        root.actionHudIndex = index
                        root.runActionHudAction(String(modelData.key || ""))
                      }
                    }
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(root.selectedActionHudItem().hint || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }
                }

                Column {
                  id: tuneActionPage
                  visible: root.actionHudPage === "tune"
                  width: parent.width
                  spacing: Style.spacing.md

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "One clear choice replaces separate More, Follow, Snooze, and Less Source commands."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                Text {
                  textFormat: Text.PlainText
                  text: "1  ·  DIRECTION"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.7
                }

                Row {
                  id: tuneDirectionRow
                  width: parent.width
                  spacing: Style.spacing.sm
                  property real buttonWidth: (width - spacing * 2) / 3

                  Button {
                    width: tuneDirectionRow.buttonWidth
                    text: "+  More"
                    tooltipText: "Keyboard: + or M"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: root.tuneDirection === "more"
                    onClicked: root.tuneDirection = "more"
                  }
                  Button {
                    width: tuneDirectionRow.buttonWidth
                    text: "0  No signal"
                    tooltipText: "Keyboard: 0 or N"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: root.tuneDirection === "neutral"
                    onClicked: root.tuneDirection = "neutral"
                  }
                  Button {
                    width: tuneDirectionRow.buttonWidth
                    text: "−  Less"
                    tooltipText: "Keyboard: −"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: root.tuneDirection === "less"
                    onClicked: root.tuneDirection = "less"
                  }
                }

                Text {
                  visible: root.tuneDirection !== "neutral"
                  textFormat: Text.PlainText
                  text: "2  ·  SUBJECT OR SOURCE   [j/k or ←/→]"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.7
                }

                Flow {
                  id: tuneTargetFlow
                  visible: root.tuneDirection !== "neutral"
                  width: parent.width
                  spacing: Style.spacing.sm

                  Repeater {
                    model: root.feedbackTargetsForArticle(root.actionHudArticle)

                    delegate: Button {
                      required property var modelData
                      required property int index
                      text: String(modelData.kind || "subject").toUpperCase()
                        + "  ·  " + String(modelData.label || "this story")
                      tooltipText: "Apply feedback to this "
                        + String(modelData.kind || "subject")
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      bordered: true
                      selected: index === root.feedbackTargetIndex
                      onClicked: root.feedbackTargetIndex = index
                    }
                  }
                }

                Text {
                  visible: root.tuneDirection !== "neutral"
                  textFormat: Text.PlainText
                  text: "3  ·  DURATION"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.7
                }

                Row {
                  id: tuneDurationRow
                  visible: root.tuneDirection !== "neutral"
                  width: parent.width
                  spacing: Style.spacing.sm

                  Button {
                    width: (tuneDurationRow.width - tuneDurationRow.spacing) / 2
                    text: "7  ·  7 days"
                    tooltipText: "Temporary · expires automatically"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: root.tuneDuration === "temporary"
                    onClicked: root.tuneDuration = "temporary"
                  }
                  Button {
                    width: (tuneDurationRow.width - tuneDurationRow.spacing) / 2
                    text: "P  ·  Lasting"
                    tooltipText: "Stays until removed in Profile"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: root.tuneDuration === "lasting"
                    onClicked: root.tuneDuration = "lasting"
                  }
                }

                BorderSurface {
                  width: parent.width
                  implicitHeight: tunePreview.implicitHeight + Style.spacing.lg * 2
                  height: implicitHeight
                  color: "transparent"
                  radius: Style.cornerRadius
                  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                  Text {
                    id: tunePreview
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.lg
                    anchors.rightMargin: Style.spacing.lg
                    textFormat: Text.PlainText
                    text: root.tuneSummary()
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.Wrap
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.sm

                  Button {
                    width: (parent.width - parent.spacing) * 0.34
                    text: "Back"
                    iconText: "󰁍"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    onClicked: root.stepBackActionHud()
                  }
                  Button {
                    width: (parent.width - parent.spacing) * 0.66
                    text: "Apply  ·  Enter"
                    iconText: feedbackProc.running ? "󰦖" : "󰄬"
                    iconSpinning: feedbackProc.running
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    bordered: true
                    selected: true
                    enabled: !feedbackProc.running
                    onClicked: root.applyTuneFeedback()
                  }
                }
                }
              }
            }
          }
        }

        Item {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.right: shortcutLegend.visible
              ? shortcutLegend.left
              : (brandLink.visible ? brandLink.left : parent.right)
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.viewMode === "event"
              ? "j/k move  ·  Enter synopsis  ·  b/esc back  ·  coverage stays local"
              : root.statusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            id: shortcutLegend
            anchors.right: brandLink.visible ? brandLink.left : parent.right
            anchors.rightMargin: brandLink.visible ? Style.spacing.lg : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: footer.width >= Style.space(940)
            textFormat: Text.PlainText
            text: root.viewMode === "feed" || root.viewMode === "search"
              ? "/ search  ·  ? help  ·  j/k move  ·  ↵ synopsis  ·  a actions"
              : (root.viewMode === "result"
                ? "a actions  ·  t TL;DR  ·  o original  ·  b/esc back"
                : (root.viewMode === "help"
                  ? "1/2 or ←/→ tabs  ·  / filter  ·  b/esc back"
                  : ((root.viewMode === "bookmarks" || root.viewMode === "history"
                      || root.viewMode === "read")
                    ? "j/k move  ·  ↵ synopsis  ·  Tab controls  ·  b/esc back"
                    : "? help  ·  j/k scroll  ·  Tab controls  ·  b/esc back")))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: brandLink
            visible: root.footerLinkVisible
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.footerLinkLabel + "  ↗"
            color: brandMouse.containsMouse ? root.foreground : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true

            MouseArea {
              id: brandMouse
              anchors.fill: parent
              anchors.margins: -Style.spacing.sm
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached([
                "omarchy-launch-browser", root.footerLinkUrl
              ])
            }
          }
        }
      }
    }
  }
}
