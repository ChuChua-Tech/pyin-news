# Changelog

All notable changes to PYIN News are recorded here. Versions follow Semantic
Versioning.

## Unreleased

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
