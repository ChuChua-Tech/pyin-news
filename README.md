# PYIN News

**Get the news. Keep your time.**

Every social feed wants another hour from you. PYIN does not. There are no bot
replies, rage-bait arguments, popularity contests, or infinite scroll. Choose
the reporting and subjects that matter, read a finite edition with a beginning
and an end, then get on with your day.

PYIN is a private, keyboard-first, tiled news reader for Omarchy. It ships with
a catalog of 226 RSS/Atom feeds, groups repeated coverage into events, and
ranks those events locally using choices you can inspect and change. AI runs
only when you explicitly request it.

![PYIN News vision page running as a tiled Omarchy application](preview.png)

## Install

Install the current release directly from GitHub:

```bash
omarchy plugin add https://github.com/chuchua-tech/pyin-news.git --enable
```

Open PYIN News from its bar widget. The setup wizard runs the first time the
panel is opened; it can be reopened later with `c` or from Profile.

### Requirements and privileges

- A current Omarchy installation with shell-plugin support
- Python 3 with its standard-library SQLite support (included with Omarchy)
- Network access to the RSS/Atom and article hosts the reader checks
- Subject alerts use Omarchy's native notification sender; `notify-send` is a
  non-clickable compatibility fallback when that helper is unavailable
- Optional: Codex for System AI, or a loopback OpenAI-compatible server for
  Local server mode; the news reader remains fully usable with No AI

PYIN has no installer script, package-manager step, background system service,
or elevated-privilege operation. Like every Omarchy shell plugin, its QML and
helper process run unsandboxed with the permissions of the signed-in user.

## Update

```bash
omarchy plugin update tech.chuchua.news
```

Updates preserve the local database and user-owned source configuration.

## Remove

```bash
omarchy plugin remove tech.chuchua.news
```

Removal deletes the plugin code but intentionally leaves the user's database
and optional source override in place. To erase those records too, move
`~/.local/state/chuchua-news/` and `~/.config/chuchua-news/` to Trash after
removing the plugin. Profile → Data & Privacy can reset or export personal data
before removal.

## Privacy and network boundaries

PYIN has no account, advertising, analytics, tracking pixel, or telemetry. It
stores its article cache, reading history, bookmarks, alerts, and curation
profile locally. Normal refreshes contact only configured RSS/Atom endpoints;
opening or summarizing a story can also fetch that publisher's article page.

AI never ranks the feed and runs only after an explicit TL;DR or question. In
System AI mode, the supplied article text is sent to the configured Codex
model. In Local server mode, it is sent only to the configured loopback
endpoint. With No AI selected, article text is not sent to any model. The
feedback form opens a local pre-addressed email draft and sends nothing until
the user chooses to send it.

## Controls

- `j` / `k` or arrow keys: move through stories
- `Tab` / `Shift+Tab`: move through the persistent menu and page controls; `Enter` or `Space` activates the focused control
- `Enter` or left-click: open the feed-provided synopsis without AI
- `o`: open the selected story in the browser
- `t`, `s`, or right-click: create an AI TL;DR for the selected story
- `a` or `A`: open the keyboard-first Article Actions HUD for the selected story
- `Backspace`: dismiss the selected story and add a small, reversible local Show Less signal
- `=`: show more news about the selected subject
- `f`: follow the selected subject as a strong, lasting interest
- `-`: show less news about the selected subject
- `/`: focus Search News; in `?` Help, focus its instant shortcut filter
- `m`: save or remove the current story from Read Later
- `d`: mark the current story read and hide it from the ranked feed; press again to restore it
- `v`: open the Read Later list
- `h`: open History, with Viewed and Hidden companion lists
- `n`: manage subject alerts
- `p`: inspect your local curation profile
- `c`: reopen the setup wizard
- `r`: check active RSS sources; the freshness chip shows age, progress, and results
- `i` or click the `PYIN` masthead: read the story behind the name and chuchua.tech
- `b` or `Esc`: leave the current view; on an article, either mark it read and return to the main feed or return without hiding, according to your Back-action switch
- `?`: show the searchable Keys and Feed Controls reference
- `q`: close PYIN News
- right- or middle-click the bar icon: refresh feeds

The left bar click opens a normal application window. Hyprland tiles it like
other apps; it is not a layer-shell popup.

## Name and identity

`pyin` means “now” in Secwepemctsín. The name reflects the goal of understanding
what matters now without living inside an endless social timeline. Click the
four-cell `PYIN` masthead, or press `i`, for the in-app story of the name, why the
reader exists, and the people behind chuchua.tech.

The About page includes a small feedback form for ideas, problems, and source
suggestions. It opens a pre-addressed draft to
`pyin-news-feedback@chuchua.tech` in the reader's local email application;
nothing is transmitted until the reader reviews and sends that draft.

Subject-alert notifications use PYIN's bundled split-flap icon rather than the
desktop theme's generic news tile. The asset stays inside the plugin and is
resolved by absolute path, so it survives theme and icon-pack changes. Clicking
an individual alert summons PYIN and opens that exact cached story, including
from Omarchy's persisted notification history.

While the feed is idle, the four mechanical cells occasionally flip from
`PYIN` to `NEWS`, hold briefly, and return. This can be disabled with the
`Occasional split-flap logo` plugin setting. On first open, a larger copy of
the same masthead rapidly cascades between both words while the local feed is
being assembled, then settles on `PYIN` as the edition appears.

## Setup wizard

First launch opens an eight-page, re-runnable wizard. It configures:

- a finite 5, 15, or 30 minute reading window and calm/compact density
- optional country, region, and city boosts, stored locally
- language, must-see, interested, and muted topics
- a 50-entry keyword blacklist that hard-filters the feed and alert notifications
- independent, nonprofit, local, community, expert, original-research,
  mainstream, and grassroots source packs
- a searchable catalogue showing every publisher, feed host, region, source type, and topic
- individual sources to hide plus up to 50 user-added RSS or Atom feeds
- open-minded, broad, or familiar-first discovery ratios
- desktop-alert quiet hours and a daily notification ceiling
- System AI with Fast, Balanced, or Thorough presets; a loopback local server; or no AI
- reading-choice learning and cache retention
- whether leaving an article with Back marks it read and hides it

The app always inherits the active Omarchy palette, controls, borders, spacing,
and type. The density choice changes layout without creating a competing theme.
Every choice is visible later under Profile, and `c` reopens the wizard.
Geography is deliberately separate from subject topics: the saved location
provides each reader's local and national lens, while country names such as
Canada remain ordinary searchable source metadata rather than privileged
universal categories.

## Navigation, History, and Profile

The same ordered main menu remains at the top of Feed, Search, article,
Read Later, History, Alerts, Profile, Help, and About views. A contextual Back
button becomes the left-most control wherever it is needed. The stable order is
Feed, Read Later, History, Alerts, Profile, and Help, followed by a separated
freshness chip at the far right. The chip reads `NOW` or the age of the latest
source check; while working it becomes a terminal scan, then briefly reports
the new-story count, success, or failures. Profile → Customize can show or hide
the optional Read Later, History, Alerts, and freshness controls; Feed, Profile,
and Help always remain available so the reader cannot customize itself into a
dead end.

The bottom-right footer is unbranded by default. Profile → Customize can add one
user-owned HTTP/HTTPS link with a short label, or clear it again. The setting is
stored locally and follows profile export/import.

History keeps deliberate synopsis opens in newest-viewed order, including the
last-viewed age and repeat-open count. Its Viewed and Hidden tabs separate
reading history from items marked read or dismissed. The history index is
stored only in PYIN's local database and does not depend on personalization
being enabled.

Profile is organized into four collapsed groups: Customize, Your Choices,
Learned Curation, and Data & Privacy. A compact Library & Controls block keeps
History, Read Later, Hidden, Alerts, and Edit Setup immediately reachable. The
full viewed-story list now lives on History instead of expanding the Profile
page indefinitely.

## AI providers

`System AI` is the default wizard choice. PYIN reads Omarchy's selected agent from
`~/.config/omarchy/defaults/agent`. The current adapter supports Codex through
Codex's local app-server event stream in an ephemeral, read-only sandbox. Final-answer
deltas appear as they arrive; commentary events are discarded. It never uses the normal
`omarchy agent` auto-approval launcher.

System AI has three per-PYIN presets: Fast uses GPT-5.6 Luna with low reasoning,
Balanced uses GPT-5.6 Sol with low reasoning, and Thorough uses GPT-5.6 Sol with
high reasoning. Balanced is the default. These overrides apply only to PYIN's
ephemeral summary thread, so changing them does not alter the user's normal Codex
model or reasoning setting. Profile exposes the active preset, model, and effort and
allows one-click switching. The exact model and effort are also included in each
summary's cache identity and visible provider label, so a preset change cannot silently
reuse output from a different model configuration.

`Local server` sends a standard chat-completions request to a loopback-only
OpenAI-compatible endpoint. Ollama's default example is
`http://127.0.0.1:11434/v1`; set the model to one installed on your server. The
request enables OpenAI-compatible SSE streaming and falls back cleanly when a
server returns its answer as one JSON message.

`No AI` disables AI TL;DR while leaving the entire RSS reader, model-free
catalog search, ranking system, source catalog, bookmarks, and alerts available.

## Responsive article actions

Mark Read and Dismiss remove the selected story and every visible member of its
event cluster from the panel immediately, then persist the change in the
background. Feed calculations carry a mutation generation, so a calculation
started before the action cannot put stale stories back on screen. A failed
write restores the optimistic local change and reports the error.

The configured feed size is still replenished after each removal, but that
background result is merged into the current reading session instead of replacing
its ranking. Every surviving headline keeps its relative position, the reader's
selected story and scroll offset stay anchored, and replacement stories arrive at
the bottom. The dismissed card now fades and collapses first, visibly carrying the
existing cards below it upward instead of swapping the row's contents in place;
the status line confirms how many replacement cards were appended. Automatic
source checks merge without disturbing the active session. Pressing `r`, changing
curation controls, or reopening the panel intentionally starts a newly ranked
session.

Session-preserving order is also the internal default: every asynchronous feed
load must opt in explicitly before it may replace the visible ranking. Each load
records a named reason plus its before/after article IDs in the Quickshell log,
so an unexpected reorder can be traced to its exact caller instead of inferred
from timing.

Read and dismiss commands return only their mutation delta instead of serializing
the full Read history. The feed ranker prepares learned-interest matchers once per
pass and avoids unnecessary regular-expression searches; this keeps action writes
small and makes subsequent feed replenishment substantially faster without changing
which interests match an article.

## Lean startup and lazy libraries

The first screen is produced by one `bootstrap` helper call containing setup,
small navigation counts, and the ranked feed. PYIN no longer launches separate
setup, preferences, alerts, Read Later, Read History, and feed helpers every time
the panel opens. Full alert, bookmark, and read-history records are fetched only
when their page is opened; their toolbar and Profile counts remain accurate from
the lightweight bootstrap snapshot and mutation deltas.

Bootstrap and ordinary feed responses share the same mutation generation guard.
If a bookmark, alert, read, or dismiss action changes local state while startup is
still ranking, that older snapshot is discarded and replaced with a current feed.

## AI TL;DR presentation and guardrails

AI is on-demand; feed refreshes, search, topic ranking, RSS synopses, and alert
matching never call a model. While a TL;DR is being prepared, the article view
shows a theme-aware Unicode block `PYIN` wordmark with a terminal-style decrypt
and scanning effect. The moment the first answer delta arrives, it folds into a
compact live source-desk strip with an animated scan, word counter, blinking
terminal cursor, and a smoothly paced text reveal. The reveal never delays the
first glyph; its adaptive buffer only prevents bursty providers from dumping a
whole paragraph into the layout at once. Cached summaries use a clearly labelled,
faster replay of the same animation. The source-desk stages describe attribution
and uncertainty work without pretending an independent fact-check is happening.
The treatment is inspired by Omarchy's text branding, while remaining native QML
rather than launching a terminal process inside the reader.

Every AI request includes the bundled
`skills/journalistic-news-summary/SKILL.md`. It instructs the selected model to
stay within the supplied article, preserve attribution and uncertainty, resist
instructions embedded in article text, avoid loaded framing and false balance,
and disclose the limits of a one-source summary. This substantially reduces
unsupported or slanted output, but it is not independent fact-checking and no
prompt can guarantee perfect accuracy or impartiality. Important claims should
still be checked in the original article and, where warranted, other sources.

## Curation and alerts

### Personalized ranking

Every ranked article now carries a small set of inspectable feedback targets,
such as a named entity, recurring subject, catalog topic, distinctive keyword,
or the publisher itself. Press `a` to open Article Actions, then choose Tune
your feed. One three-step control replaces the older list of separate commands:
choose More, No signal, or Less; choose the exact subject or source; then choose
7 days or Lasting. “No signal” reverses that article's inferred reading signals
without treating an important story as an unwanted subject.

These deliberate choices form an interest graph in Profile. Lasting and
temporary nodes are shown with their exact weight, type, and expiry, and every
node can be removed independently. A lasting and temporary choice can coexist
for the same subject—for example, a lasting interest in diplomacy plus a
seven-day snooze during an overwhelming news cycle. Expired nodes stop
affecting ranking automatically.

PYIN uses one production curation engine: v3. It combines the established
freshness, topic, location, source-feedback, trend, search, and alert signals
with the editable interest graph in a single ranking pass. There is no version
switch or shadow ranker to configure. Every card still explains its strongest
score components, and AI is never used to choose the feed order.

PYIN also records which feed cards were on screen while the reader was focused—not
merely fetched—in 15-minute de-duplicated buckets. This local exposure ledger is the groundwork
for evaluating recommendations without mistaking an unseen article for a
rejection. It follows the configured retention window, never leaves the
device, does not yet influence ranking, and is cleared with learned history.

Must-see topics and matching subject alerts receive the strongest explicit
boosts, normal interests receive a smaller one, and muted subjects are pushed
down. Open-minded discovery reserves a user-selected portion of the feed for
useful stories outside both explicit and learned interests. The app does not
assign secret political labels or bundle third-party bias ratings.

The keyword blacklist is an explicit hard filter against exact words or phrases
in headlines, RSS text, and source topics. It also suppresses matching alert
notifications. Manual Search intentionally remains unfiltered as a transparent
escape hatch.

The local profile learns deliberately weighted signals. Opening a synopsis is
weak evidence; reading it for at least 12 seconds, saving it, opening the
original, or requesting a TL;DR is stronger. Ordinary Mark Read is neutral.
Terms are conservative named entities, recurring headline subjects, and
confirmed catalog topics—not an unrestricted bag of every word in the RSS
text. This can be disabled without erasing existing data; when disabled, stored
memory stops affecting ranking and no new signals are added.

Recent and lasting memory are maintained separately. Recent memory decays at
7% per day, while lasting memory decays at 0.6% per day. This lets a developing
event fade without erasing stable interests. Saving and removing a bookmark,
and dismissing and restoring a story, apply exactly reversible signals.

Before scoring, PYIN admits at most 20 recent articles per publisher into the
candidate pool. Near-identical headlines inside a four-day window are then
clustered against a stable event anchor. One representative card is shown with
the other publishers available under Coverage. The final reranker penalizes
repeated publishers, subjects, regions, source types, and similar events while
preserving the configured discovery lane.

Backspace is intentionally different from ordinary Mark Read: it hides the
currently grouped event and adds negative weights for its extracted entities,
subjects, and publisher.
Profile → Show Less Feedback exposes those values and recent dismissals.
Restoring the story from Read history reverses its contribution; resetting
learning removes inferred reading and Show Less weights, the exposure ledger,
and legacy open counts, while leaving dismissed stories hidden and keeping
explicit interest-graph choices until they are individually removed.

The Profile page is the control centre for topic choices, menu layout, article
behaviour, AI speed, source setup, and local data. Its four primary groups and
nested Setup & Source Mix and Show Less sections start collapsed, keeping
everyday controls compact. Its Back-action switch chooses whether
Back/Escape means “finished—mark read and hide” or simply returns without
changing the story. The page also shows explicit choices, editable
interest-graph nodes, active inferred subjects in both memory horizons, recent
dismissals, and local data counts.
Its two-step reset forgets inferred weights, exposure, and open history while
preserving explicit interests, setup choices, saved stories, alerts, and
sources. Profile JSON exports and imports setup—including custom feeds and the
optional footer link—and explicit interest nodes through
`~/Downloads/chuchua-news-profile.json`.

Subject alerts match all significant words locally against each newly fetched
title, feed synopsis, and source topics. For example, `war in Iran` watches for
new items matching both `war` and `Iran`. Matches produce Omarchy desktop
notifications and are de-duplicated per article. Alerts do not scan old cached
items and never invoke AI.

Read Later bookmarks are stored locally. Saved articles are exempt from the
normal 90-day article-cache cleanup until you remove the bookmark.

Marking a story read stores its stable article ID locally and removes it from
the ranked feed, including after a refresh. When a card represents multiple
publishers, its currently grouped articles are hidden and restored together as
one Read-history card. Read stories remain searchable and
saved copies remain in Read Later. Profile → Read lists the hidden stories and
lets you restore them. Marking read is deliberately separate from opening a
synopsis and does not teach the ranking profile. When it is used from an article
page—directly or through the configurable Back action—the page closes and the
main feed reappears.

Article pages keep four predictable everyday controls—AI TL;DR, Read Later,
Open Original, and Article Actions—plus the Back button in the header. The
transient Article Actions HUD opens with `a`, exposes visible letter commands,
supports `j`/`k`, arrows, Enter, and Escape, and works identically by mouse.
Its Tune screen consolidates subject/source direction and duration. The
Back-action switch remains in Profile instead of occupying every article menu.
When configured to mark read, Back returns to the feed immediately while the
local read-state update completes in the background.

The `?` page has separate Keys and Feed Controls tabs. Its shortcut list follows
the physical keyboard—number row, QWERTY row, home row, bottom row, then
navigation keys—while remaining instantly searchable. Feed Controls is a
searchable, plain-language ledger covering every setup, reading,
personalization, discovery, privacy, and ranking choice and its exact effect on
the feed.

## Sources and local data

The bundled 226-source list spans Canadian and Kamloops/BC reporting, Indigenous outlets,
public broadcasters, independent and nonprofit newsrooms, established general
news, and country- or region-rooted reporting across Africa, Asia, Europe,
Latin America, Oceania, and the Pacific, alongside competing political traditions, fact-checking,
media criticism, technology, science, health, sports, gaming, official Omarchy
updates, and primary institutions. More
sources improve breadth, but source count is not a claim of neutrality.
Descriptive, overlapping source-format metadata is maintained separately in
`source-catalog.json` under CC0-1.0 and contains no proprietary political-bias
scores. The Profile page exposes the active mix.

Catalog additions are accepted only after a direct fetch returns parseable
articles. Public feed directories are treated as discovery leads rather than a
source of truth; dead, stale, blocked, and incorrectly attributed endpoints are
left out.

Search is intentionally separate from curation: an SQLite FTS5 index searches
up to 5,000 locally cached stories from every catalog source, ignores the
interest profile, and does not call AI. Feed selection remains personalized and
explainable. Ranking is deterministic and model-free; optional AI summaries do
not choose, suppress, or reorder stories.

Background refreshes are network-conscious. PYIN retains publisher-provided
`ETag` and `Last-Modified` validators, detects identical feed bodies when those
headers are unavailable, gradually checks unchanged feeds less often, and backs
off temporarily failing feeds. Pressing `r` remains an explicit full refresh.
Cross-publisher trending scores are calculated once after a real source check
and cached; closing the panel does not rebuild its visible feed model.

OPML makes existing public feed lists reusable instead of locking the catalog to
one application:

```bash
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news sources \
  --all --export-opml ~/Downloads/chuchua-news-sources.opml
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news sources \
  --import-opml ~/Downloads/my-feeds.opml
```

The setup wizard's fourth page is the simpler path for adding one-off feeds: give
the feed a name and its HTTP/HTTPS RSS or Atom endpoint. Changes remain staged
until the final setup page; custom feeds are checked during the next refresh and
can be removed from the same page later.

To customize it without editing the plugin:

```bash
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news sources --install-user-copy
$EDITOR ~/.config/chuchua-news/sources.json
```

The article cache and learned profile stay in
`~/.local/state/chuchua-news/news.sqlite3`. No browsing history or profile is
sent anywhere. An article excerpt is sent only to the AI provider you choose
when you request an answer.

Useful checks:

```bash
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news doctor
omarchy plugin validate ~/.config/omarchy/plugins/tech.chuchua.news
```
