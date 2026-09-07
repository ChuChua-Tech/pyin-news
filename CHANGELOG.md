# Changelog

All notable changes to PYIN News are recorded here. Versions follow Semantic
Versioning.

## [0.25.1] - 2026-09-06

### Security

- Route feed, article and optional image downloads through one bounded public-web
  transport. Reject non-public and mixed DNS answers, bind connections to the
  checked numeric IP, verify the connected peer, and validate every redirect.
  HTTPS retains certificate and hostname verification. Private/LAN feeds and
  proxy environment variables are no longer supported for these downloads.
- Preserve Codex summaries, native sign-in and dynamic model discovery through
  an isolated app-server with tools disabled. Apply private runtimes and filtered
  configuration to Claude Code, Gemini CLI and Grok Build too. Personal files,
  instructions and agent customizations are excluded; native credential files
  remain available to their own agent for sign-in and refresh.
- Check native agent compatibility before sending article text. Unverified
  versions and unsupported authentication configurations stop with an actionable
  error; they never fall back to a less restricted invocation.
- Bound AI input, output and process lifetime, reject response tool calls, and
  constrain Local server requests to numeric loopback peers with no redirects or
  inherited proxy settings. Local server and No AI remain available.
- Remove PYIN's mutable-HEAD self-updater, including its CLI and QML actions.
  Profile shows local version information; updates are managed through Omarchy.

## [0.25.0] - 2026-09-06

### Added

- Regular, Large and Extra large reading text in Setup and Profile → Customize,
  with a preview before applying. Saves with the profile independently of layout
  density; existing profiles keep Regular and toolbar controls retain their size.

### Changed

- Center and limit the article column in wide windows, increase reading line
  spacing and separate AI headings from paragraphs.
- Use the selected theme's foreground for essential secondary text when its
  muted color has insufficient contrast against the app background.
- Keep article actions, Coverage and edition controls in a fixed bottom toolbar,
  reserving reading space above it and adapting to narrow windows.
- Move the Context & framing scope notice below the article in readable small
  print; remove the repeated shortcut row from the reading body.

### Fixed

- Keep the reader on the next surviving headline after hiding a story, preserving
  the native list cursor and viewport through collapse, save and refill. Hiding
  the last story selects the previous one; a failed save restores the original.
- Prevent a parked mouse from pulling feed selection backward as rows scroll
  beneath it. Keyboard navigation uses a short native scroll transition; actual
  pointer movement still selects rows, and mouse-wheel scrolling stays native.
- Preserve feed order when an older refresh completes after a story is hidden.
  Replacements append at the bottom, including when stale feed requests retry.
- Render bold text and Markdown-style headings in AI TL;DRs instead of showing
  their markers; preserve paragraphs and keep supplied HTML inert.
- Hide the Read Later count badge when no stories are saved.

## [0.24.0] - 2026-09-06

### Added

- Optional feed-supplied article thumbnails in headlines, search and Daily
  Editions. Defaults off, follows profile export/import, respects each reading
  style and falls back to text when images are unavailable. Visible rows share
  one bounded downloader and an expiring 32 MiB local cache. The reader also
  centers the whole image below its headline and source, folds it away on
  downward scrolling and unfolds it on upward scrolling; no article-page
  crawling, image service or extra dependency.
- Optional Context & framing in AI summaries, off by default in Setup and
  Profile. Adds supported framing concerns, quote-context limits and evidence
  gaps using the supplied article only, within the existing AI request.
  Includes an explicit scope notice and separate cache identity; the preference
  follows profile export/import. No AI remains fully disabled.

### Fixed

- Recover Mark Read and Dismiss when their helper fails to start or exits
  unsuccessfully. Keep each action intact until its row animation and saved
  acknowledgement finish, including during rapid repeated input.
- Clarify checked sources as hidden in setup, and align Help/Profile wording
  with Daily Editions, Coverage and History → Hidden.
- Fix the empty-feed loading icon's animation visibility reference.

## [0.23.0] - 2026-09-05

### Added

- Daily Editions: a fixed 5, 15, or 30 minute selection with saved story progress
  and a clear finish. Open with G or the calendar icon. Done advances and marks
  read; Skip advances without a negative preference signal; Back pauses.
- Edition stories remain available through feed refreshes and cache cleanup.
  Quiet days can be shorter, and another edition starts only when requested.
  Reading estimates cover synopses, independently of optional AI.

### Changed

- Renamed setup's Daily reading window to Feed size, with 15/30/60-story choices
  and matching Profile/Help wording. Existing feed sizes are preserved.
- Daily Editions chooses its duration separately and remembers the most recent
  edition's duration. Changing Feed size no longer changes the edition picker.

### Upgrade

- Update through App & Updates. Existing preferences, saved stories, history and
  edition progress are preserved. Press G or use the calendar icon for editions.

## [0.22.0] - 2026-09-05

### Added

- Gemini CLI and Grok Build support for Follow Omarchy, with agent-provided
  model catalogs, manual model entry, streamed summaries, and temporary session
  storage. Grok reasoning choices come from its catalog; Gemini manages its own.
- Test feed in custom-source setup: validate a URL and preview a headline
  without saving a subscription or changing the article cache.
- Claude Code support for Follow Omarchy, with a discovered model catalog,
  advertised reasoning options, manual model entry, and streamed summaries.
  Existing sign-in and model settings are used; tools and customizations are
  disabled for article summaries.

### Upgrade

- Update through App & Updates. Existing preferences, saved stories and reading
  history are preserved. Sign in through your chosen AI agent before use.

## [0.21.1] - 2026-09-05

### Changed

- Faster local search by formatting only the results shown, while preserving
  matching, ordering, and result counts.
- Less database and CPU work when opening the feed or refreshing unchanged
  sources. Corrected headlines, changing publishers, and ageing reports still
  update coverage trends.
- Lower loader animation overhead after its logo finishes appearing, with the
  same appearance and timing.

### Fixed

- Recreating a missing search index now restores searchable cached stories.

### Upgrade

- Update normally through App & Updates. Existing articles, preferences, saved
  stories, reading history, and AI settings are preserved.

## [0.21.0] - 2026-09-05

### Added

- Coverage (Event Desk): open a story's reporting timeline from the compact
  Coverage action beside its publisher or press `e`.
  Browse publishers and publication times, return to the same position, and see
  reporting added since your previous visit marked New.
- A searchable AI model picker in Setup and Profile, with Agent default,
  models discovered from Codex, manual model entry, and optional reasoning settings
- On-demand model catalog refresh with a local cache and useful failure messages;
  discovery does not generate an AI response
- A small masthead Easter egg that respects the logo animation preference

### Changed

- Follow Omarchy uses the selected agent's configuration by default. Choosing a
  model or reasoning setting overrides it only for PYIN summaries.
- Fast, Balanced, and Thorough buttons are replaced by the model picker. Existing
  selections retain their exact model and reasoning settings.
- Summaries using the new model settings are generated fresh and display the
  effective model and provider returned by Codex.

### Fixed

- Missing, unset, and unsupported Omarchy agents are explained before a summary;
  PYIN no longer selects Codex merely because it is installed.
- Event membership remains stable across ranking changes and later arrivals.
  Read, bookmark, and dismiss actions in Event Desk apply to the selected report.
- Event visit acknowledgements require a displayed, focused timeline; metadata
  updates preserve its scroll position and selected report.

### Upgrade

- Profiles migrate automatically, preserving saved choices. Supported older
  profile exports can still be imported.
- Event Desk indexes the existing local cache on first use. Its first visit
  establishes a baseline for later New markers.
- Codex remains the supported System AI adapter. Local server and No AI remain
  available; this release does not add other agent adapters or hosted endpoints.

## [0.20.0] - 2026-09-04

### Added

- Subtle article separators in Calm and Compact layouts, with a line-free
  Classic layout for the original appearance
- Independent Plain and Paper backgrounds with a live setup preview; Paper
  follows Omarchy's palette while article and AI reading views stay plain
- A Source Health section in Profile with persistent feed errors, failed-check
  counts, last-check and last-success times, and refresh controls

### Fixed

- Invalid profile imports leave saved choices untouched; supported older
  exports remain compatible and settings plus explicit interests restore atomically
- Identical ranking inputs produce consistent story order and coverage groups
  across processes and database insertion order
- Every deliberate reopen updates viewed history without repeatedly increasing
  preference weights; acknowledged saves keep counts and current lists consistent
- No signal prevents a story's inferred reading signals from returning after
  another visit or app restart, while preserving its viewed history
- Exposure measurement excludes offscreen cards; the 12-second reading signal
  counts focused article time and pauses when the reader loses focus
- Feed checks reject HTML and unrelated XML rather than reporting an empty
  success; cached stories remain available within the configured retention window

### Upgrade

- Existing profiles retain their choices and use Plain by default. Layout and
  background settings travel with profile exports.
- The first check of previously cached feeds revalidates their content before
  trusting conditional responses. Healthy checks clear prior source errors.

## [0.19.0] - 2026-09-04

### Added

- A manual App & Updates profile section that identifies stable, development,
  modified, and packaged copies before delegating confirmed installations to
  Omarchy's validated, rollback-capable native updater
- Clickable Omarchy subject-alert notifications that summon PYIN and open the
  exact cached story, with persisted deep links in notification history
- First-class Sports, Gaming, and Omarchy topics backed by 26 fetched and
  parser-verified feeds, bringing the bundled catalog to 226 sources
- Geography-neutral setup topics: local and national relevance now comes only
  from each reader's optional country, region, and city profile

### Fixed

- Location alerts now match each article's title and publisher synopsis rather
  than static source geography, preventing every story from a local publisher
  from triggering the same city alert

## [0.18.0] - 2026-09-04

Initial public release.

### Added

- A tiled, theme-native Omarchy news reader with persistent keyboard navigation
- A curated catalog of 200 RSS/Atom feeds plus user-added feeds and OPML tools
- Deterministic v3 personalization with visible, editable local preferences
- Search, reading history, hidden stories, Read Later, and subject alerts
- An eight-page setup wizard and an inspectable Data & Privacy profile
- Feed-provided synopses and optional streaming AI TL;DRs with journalistic guardrails
- System AI presets, a loopback local-server option, and a complete No AI mode
- Event clustering, stable feed ordering, adaptive source backoff, and source diagnostics
- Feed compatibility for publishers that reject explicit compression or emit
  isolated legacy bytes in otherwise valid UTF-8 XML

[0.20.0]: https://github.com/chuchua-tech/pyin-news/releases/tag/v0.20.0
[0.19.0]: https://github.com/chuchua-tech/pyin-news/releases/tag/v0.19.0
[0.18.0]: https://github.com/chuchua-tech/pyin-news/releases/tag/v0.18.0
