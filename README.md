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
- Optional: Codex, Claude Code, Gemini CLI or Grok Build for System AI, or a loopback OpenAI-compatible server for
  Local server mode; the news reader remains fully usable with No AI

PYIN has no installer script, package-manager step, background system service,
or elevated-privilege operation. Like every Omarchy shell plugin, its QML and
helper process run unsandboxed with the permissions of the signed-in user.

## Update

Profile → App & Updates can identify the installed version and channel, check
the stable branch on demand, and install a release after a second confirmation.
It delegates installation, validation, rollback, and shell reload to Omarchy.
Checks are never automatic, development and modified checkouts are protected,
and user data remains outside the plugin folder.

The equivalent terminal command is:

```bash
omarchy plugin update tech.chuchua.news
```

Updates preserve the local database and user-owned source configuration.

## Remove

```bash
omarchy plugin remove tech.chuchua.news
```

Removal deletes the plugin code but intentionally leaves the user's database and
optional source override in place. To erase those records too, move
`~/.local/state/chuchua-news/` and `~/.config/chuchua-news/` to Trash after
removing the plugin. Profile → Data & Privacy can reset or export personal data
before removal. Profile export transfers settings and explicit interests; it is
not a backup of the article cache or reading library.

## Privacy and network boundaries

PYIN has no account, advertising, analytics, tracking pixel, or telemetry. It
stores its article cache, reading history, bookmarks, alerts, current edition,
and curation profile locally. Normal refreshes contact configured RSS/Atom
endpoints. Reading a synopsis uses cached feed text; requesting a TL;DR can also
fetch the publisher's article page, and Open Original opens that page in your
browser.

AI never ranks the feed and runs only after an explicit TL;DR or question. In
System AI mode, the supplied article text is sent to the selected agent's
configured model. In Local server mode, it is sent only to the configured
loopback endpoint. With No AI selected, article text is not sent to any model.
The feedback form opens a local pre-addressed email draft and sends nothing
until the user chooses to send it. Explicit update checks contact GitHub;
opening or refreshing the model picker can contact the selected agent’s service
for its catalog without submitting an AI prompt.

## Controls

- `j` / `k` or arrow keys: move through stories
- `Tab` / `Shift+Tab`: move through the persistent menu and page controls; `Enter` or `Space` activates the focused control
- `Enter` or left-click: open the feed-provided synopsis without AI
- `e`: open Coverage for the current story; its synopsis also has a Coverage button
- `o`: open the selected story in the browser
- `t`, `s`, or right-click: create an AI TL;DR for the selected story
- `a` or `A`: open the keyboard-first Article Actions HUD for the selected story
- `Backspace`: dismiss the selected story and add a small, reversible local Show Less signal
- `=`: show more news about the selected subject
- `f`: follow the selected subject as a strong, lasting interest
- `-`: show less news about the selected subject
- `/`: focus Search News; in `?` Help, focus its instant shortcut filter
- `m`: save or remove the current story from Read Later
- `d`: mark the current story read; in Hidden history, restore the selected story. In an edition article, mark done and advance
- `g`: open Daily Editions; choose a fixed 5/15/30-minute selection and resume saved progress
- `v`: open the Read Later list
- `h`: open History, with Viewed and Hidden tabs
- `n`: manage subject alerts
- `p`: inspect your local curation profile
- `c`: reopen the setup wizard
- `r`: check active RSS sources; the freshness chip shows age, progress, and results
- `i` or click the `PYIN` masthead: read the story behind the name and chuchua.tech
- `b` or `Esc`: leave the current view; on an ordinary article, follow your Back-action switch. In Daily Editions, pause; in Coverage, return to the timeline
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

- a main feed size of 15, 30, or 60 stories and Calm, Compact, or Classic layout
- optional country, region, and city boosts, stored locally
- language, must-see, interested, and muted topics
- a 50-entry keyword blacklist that hard-filters the feed and alert notifications
- independent, nonprofit, local, community, expert, original-research,
  mainstream, and grassroots source packs
- a searchable catalogue showing every publisher, feed host, region, source type, and topic
- individual sources to hide plus up to 50 user-added RSS or Atom feeds
- open-minded, broad, or familiar-first discovery ratios
- desktop-alert quiet hours and a daily notification ceiling
- Follow Omarchy with Agent default or your own model choice; a loopback local server; or no AI
- reading-choice learning and cache retention
- whether leaving an article with Back marks it read and hides it

The app always inherits the active Omarchy palette, controls, borders, spacing,
and type. The density choice changes layout without creating a competing theme.
Calm uses roomy story rows with subtle inset separators; Compact keeps the
separators and fits more stories on screen. Classic keeps the original roomy
layout without separator lines. All three choices follow profile export/import.
Background is a separate Plain/Paper choice on the first setup page, with a live
preview. Plain is the default. Paper adds a faint, static grain tinted by the
active Omarchy palette; article-reading and AI-result views keep a plain surface.
It uses one small repeating texture with no animation, downloads, or additional
service. The choice is included in profile export/import; older profiles use Plain.
Every choice is visible later under Profile, and `c` reopens the wizard.
Geography is deliberately separate from subject topics: the saved location
provides each reader's local and national lens, while country names such as
Canada remain ordinary searchable source metadata rather than privileged
universal categories.

## Daily Editions

Press **G** or the calendar icon to choose a 5, 15, or 30 minute edition.
The local ranker selects a fixed set of stories using your existing preferences.
Edition time is independent of Feed size in setup; the picker starts at 15 minutes
and remembers the duration of your most recent edition.
The time is an estimate for reading RSS synopses, with at least a minute per
story; reading publisher originals or requesting AI can take longer. Quiet days
can contain fewer stories.

**Done & next** (or **D**) marks the story read and advances. **Skip** completes
that slot without hiding the story from the feed or adding a negative preference
signal. **Back** and **Pause edition** leave progress unchanged, regardless of
the ordinary article Back setting. Resume returns to the last opened unfinished
story; it does not restore the exact scroll offset within a synopsis.

The ending stays visible until you deliberately make another edition. Refreshes
and profile changes affect the feed and future editions; they never replace or
append stories inside the current edition. Story labels reuse the local ranker's
explanations. The current edition and its cached articles are retained locally,
including through cache cleanup, until another edition replaces it. Only one
edition is kept, and no AI call is needed to create or finish one.

## Navigation, History, and Profile

The same ordered main menu remains at the top of Feed, Search, article, Daily
Editions, Coverage, Read Later, History, Alerts, Profile, Help, and About views.
A contextual Back button becomes the left-most control wherever it is needed.
The stable order is Feed, Daily Editions, Read Later, History, Alerts, Profile,
and Help, followed by a separated freshness chip at the far right. The chip
reads `NOW` or the age of the latest source check; while working it becomes a
terminal scan, then briefly reports the new-story count, success, or failures.
Profile → Customize can show or hide the optional Read Later, History, Alerts,
and freshness controls; Feed, Daily Editions, Profile, and Help always remain
available so the reader cannot customize itself into a dead end.

The bottom-right footer is unbranded by default. Profile → Customize can add one
user-owned HTTP/HTTPS link with a short label, or clear it again. The setting is
stored locally and follows profile export/import.

History keeps deliberate synopsis opens in newest-viewed order, including the
last-viewed age and repeat-open count. Its Viewed and Hidden tabs separate
reading history from items marked read or dismissed. The history index is
stored only in PYIN's local database and does not depend on personalization
being enabled. Every deliberate reopen updates the visit count and latest-view
time; repeated visits do not repeatedly increase the story's learning weight.
The reader saves visits in order and updates its counts after each save succeeds.

Profile is organized into five collapsed groups: Customize, Your Choices,
Learned Curation, App & Updates, and Data & Privacy, with a separate Source
Health section. A compact Library & Controls block keeps History, Read Later,
Hidden, Alerts, and Edit Setup immediately reachable. The full viewed-story list
now lives on History instead of expanding the Profile page indefinitely.

## AI providers

`Follow Omarchy` is the default wizard choice (System AI mode). PYIN reads Omarchy's selected agent from
`~/.config/omarchy/defaults/agent`. Codex uses its local app-server event stream
in an ephemeral, read-only sandbox. Claude Code uses its native streaming CLI,
with existing authentication and model settings, no session persistence, and
tools disabled. Claude's safe mode disables customizations such as hooks,
plugins and project instructions for these source-bound requests. Use a current
Claude Code release; this adapter was verified with 2.1.261. See the
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference).
Gemini CLI uses ACP; Grok Build uses ACP for discovery and its constrained
headless interface for summaries. Tools are disabled and session storage is
temporary. Gemini reuses its
existing keychain or file-backed sign-in and settings; Grok retains its model
and authentication configuration and references its existing login. Agent
customizations are excluded from these article requests. No extra Python
packages or AI SDKs are required. The adapters were checked against Gemini CLI
0.58.0 and Grok Build 1.0.13; use current releases. See the
[Gemini configuration reference](https://geminicli.com/docs/reference/configuration/)
and [Grok integration reference](https://docs.x.ai/build/cli/headless-scripting).
Grok receives the article as an embedded text resource, avoiding an extra
session-title request; auxiliary turn and title summaries are disabled.
Sign in through your chosen agent first. A missing login is reported in the
picker or summary; PYIN does not open an interactive sign-in flow.
Answer text appears as it arrives; reasoning and subagent text are excluded.
PYIN never uses Omarchy's generic auto-approval launcher.

The Model dropdown in Setup and Profile starts with **Agent default**, which
leaves model and reasoning overrides unset. Choose a model from the agent's
catalog or select **Enter model name manually…** to use an exact identifier.
An optional reasoning dropdown shows settings advertised for the chosen model;
**Agent default** leaves reasoning to the agent's configuration. These choices
apply only to PYIN and do not change the agent's settings.

Model discovery runs when the picker is opened or explicitly refreshed.
It reads Codex's app-server catalog, Claude Code's initialization catalog,
or Gemini/Grok's ACP model catalog
without submitting an AI prompt. Results are cached locally for fifteen minutes. A failed
refresh can show the previous catalog with an error; Agent default and manual
entry remain available. Model access is checked when requested, and PYIN does
not request a fallback model. Changing Omarchy agents retains a saved model
override: choose **Agent default** or a model supported by the newly selected
agent if the old choice is unavailable. Other agents require their own discovery
and summary adapters; a provider API catalog alone does not supply that adapter.
Grok's reasoning menu uses the values advertised for each model. Gemini manages
reasoning itself; clear an old reasoning override when switching to Gemini.

Old Fast, Balanced, and Thorough preferences migrate to their exact model and
reasoning choices. The three preset buttons are replaced by the model picker.
Completed summaries show the effective model returned by the agent, plus
provider information where the agent supplies it.
Requests using the new model settings generate fresh summaries because provider
configuration can change outside PYIN. Legacy CLI preset flags remain accepted
for compatibility; their original caching behavior applies only to Codex.

Setup and Profile also report the selected agent's availability. If Omarchy has
no selected agent, PYIN does not infer Codex from its installation. Unsupported
agents and missing commands are explained before a summary request.
Availability checks do not launch an agent. Opening the model picker starts
a catalog lookup; summary authentication is checked when a summary is requested.
Other agent adapters and hosted endpoints are not currently supported. Local
server and No AI remain usable regardless of Omarchy's selected agent.

`Local server` sends a standard chat-completions request to a loopback-only
OpenAI-compatible endpoint. Ollama's default example is
`http://127.0.0.1:11434/v1`; set the model to one installed on your server. The
request enables OpenAI-compatible SSE streaming and falls back cleanly when a
server returns its answer as one JSON message.

`No AI` disables AI TL;DR while leaving the entire RSS reader, model-free
catalog search, ranking system, source catalog, bookmarks, and alerts available.

## Responsive article actions

In the ordinary feed, Mark Read and Dismiss remove the selected story and every
visible member of its event cluster from the panel immediately, then persist the
change in the background. Feed calculations carry a mutation generation, so a
calculation started before the action cannot put stale stories back on screen. A
failed write restores the optimistic local change and reports the error.

The configured feed size is still replenished after each removal, but that
background result is merged into the current reading session instead of
replacing its ranking. Every surviving headline keeps its relative position, the
reader's selected story and scroll offset stay anchored, and replacement stories
arrive at the bottom. The dismissed card now fades and collapses first, visibly
carrying the existing cards below it upward instead of swapping the row's
contents in place; the status line confirms how many replacement cards were
appended. Automatic source checks merge without disturbing the active session.
Pressing `r`, changing curation controls, or reopening the panel intentionally
starts a newly ranked session. Daily Editions keeps its fixed selection and
saved progress throughout; these replenishment rules apply to the ordinary feed.

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

Every article TL;DR request includes the bundled
`skills/journalistic-news-summary/SKILL.md`. It instructs the selected model to
stay within the supplied article, preserve attribution and uncertainty, resist
instructions embedded in article text, avoid loaded framing and false balance,
and disclose the limits of a one-source summary. These are instructions to the
model, not independent fact-checking or a guarantee of accuracy or impartiality.
Important claims should still be checked in the original article and, where
warranted, other sources.

## Curation and alerts

### Personalized ranking

Every ranked article now carries a small set of inspectable feedback targets,
such as a named entity, recurring subject, catalog topic, distinctive keyword,
or the publisher itself. Press `a` to open Article Actions, then choose Tune
your feed. One three-step control replaces the older list of separate commands:
choose More, No signal, or Less; choose the exact subject or source; then choose
7 days or Lasting. “No signal” reverses that article's inferred reading signals
without treating an important story as an unwanted subject. It also prevents
later views, reading time, saves, original-article opens, and summaries from
relearning that story, including after restarting PYIN. Views still appear in
History. Resetting learned history clears this suppression along with the
inferred signals while preserving explicit interests.

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
With the same event index, articles, settings, and scoring time, ranking is
reproducible across launches. Initial event assignment is independent of database
insertion order within each refresh. Equal scores use stable article identities
to resolve ties.

### Coverage (Event Desk)

Open **Coverage** beside the publisher line in a synopsis or press `e` on a story in the feed, Search,
Read Later, or History. It shows cached reporting from earliest to latest, with
publisher names and publication times in your time zone. `j`/`k` selects reports;
`Enter` opens a synopsis. Back returns to the same timeline position, then to
the original story or list. Moving within Event Desk does not automatically mark
reports read; explicit read, dismiss, and bookmark actions apply to one report.

Events have persistent local identities. New reporting joins an existing event
when its headline matches the original anchor and its publication date is within
four days of that anchor. Existing memberships survive ranking changes, corrected
headlines, and later arrivals. Matching uses local text rules and can be imperfect;
it does not establish that publishers agree or verify their claims.

The first visit establishes a baseline. Later visits mark reporting added to the
cache since that baseline as **New**, including reports published earlier but
fetched later. Each visit keeps its original snapshot and markers; subsequent
arrivals appear on the next visit. A separate acknowledgement records only the
loaded snapshot, so arrivals during navigation are not silently consumed.

Coverage respects active publishers, blocked keywords, and dismissals. Read
reports remain available for context. Event Desk makes no network or AI requests.
Its index and visits stay in the local database and are excluded from portable
profile exports. **Reset learned history** also forgets event visits. Normal cache
retention removes expired reports; an event disappears when its last report is
removed. Calm and Compact use subtle report separators; Classic omits them, and
Plain/Paper continues to follow your appearance choice.

PYIN also records feed cards whose actual bounds intersect the viewport while
the reader is focused, in 15-minute de-duplicated buckets. Offscreen cached rows
and collapsing hidden stories are excluded. This local exposure ledger is the groundwork
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
weak evidence; reading it for at least 12 focused seconds, saving it, opening the
original, or requesting a TL;DR is stronger. Ordinary Mark Read is neutral.
Terms are conservative named entities, recurring headline subjects, and
confirmed catalog topics—not an unrestricted bag of every word in the RSS
text. This can be disabled without erasing existing data; when disabled, stored
memory stops affecting ranking and no new signals are added.
The reading timer pauses when PYIN loses focus or is hidden and resumes for the
same article. Leaving or switching articles starts a new reading interval.

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
subjects, and publisher. Profile → Learned Curation → Show Less exposes those
values and recent dismissals. Restoring the story from History → Hidden reverses
its contribution; resetting learning removes inferred reading and Show Less
weights, the exposure ledger, and legacy open counts, while leaving dismissed
stories hidden and keeping explicit interest-graph choices until they are
individually removed.

The Profile page is the control centre for topic choices, menu layout, article
behaviour, AI model preferences, source setup, app updates, and local data. Its
five primary groups and nested Setup & Source Mix and Show Less sections start
collapsed, keeping everyday controls compact. Its Back-action switch chooses
whether Back/Escape means “finished—mark read and hide” or simply returns
without changing the story. The page also shows explicit choices, editable
interest-graph nodes, active inferred subjects in both memory horizons, recent
dismissals, and local data counts. Its two-step reset forgets inferred weights,
exposure, and open history while preserving explicit interests, setup choices,
saved stories, alerts, and sources. Profile JSON exports and imports
setup—including custom feeds and the optional footer link—and explicit interest
nodes through `~/Downloads/chuchua-news-profile.json`.

Subject alerts match all significant words locally against each newly fetched
title and publisher-provided feed synopsis. Static publisher topics and
geography are deliberately excluded, so a `Kamloops`-tagged source does not
trigger unless that story mentions Kamloops. For example, `war in Iran` watches for
new items matching both `war` and `Iran`. Matches produce Omarchy desktop
notifications and are de-duplicated per article. Alerts do not scan old cached
items and never invoke AI.

Read Later bookmarks are stored locally. Saved articles are exempt from the
configured article-cache cleanup (90 days by default) until you remove the
bookmark. Articles in the current Daily Edition are also retained until that
edition is replaced.

Marking a story read stores its stable article ID locally and removes it from
the ranked feed, including after a refresh. When a card represents multiple
publishers, its currently grouped articles are hidden and restored together as
one Read-history card. Read stories remain searchable and saved copies remain in
Read Later. History → Hidden (also reachable from Profile → Hidden) lists the
hidden stories and lets you restore them. Marking read is deliberately separate
from opening a synopsis and does not teach the ranking profile. When it is used
from an article page outside Daily Editions or Coverage—directly or through the
configurable Back action—the page closes and the main feed reappears. Daily
Editions uses Done & next; Coverage returns to its timeline.

Article pages keep four predictable everyday controls—AI TL;DR, Read Later, Open
Original, and Article Actions—plus the Back button in the header. Edition
articles additionally offer Done & next, Skip, and Pause edition. The transient
Article Actions HUD opens with `a`, exposes visible letter commands, supports
`j`/`k`, arrows, Enter, and Escape, and works identically by mouse. Its Tune
screen consolidates subject/source direction and duration. The Back-action
switch remains in Profile instead of occupying every article menu. For ordinary
articles, when configured to mark read, Back returns to the feed immediately
while the local read-state update completes in the background.

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
Feed responses must contain a recognized RSS, Atom, or RSS 1.0 structure;
HTML and unrelated XML are recorded as failures. Valid empty feeds remain valid.
Previously cached responses are revalidated once before conditional responses
are trusted after upgrading.
Cross-publisher trending scores are calculated once after a real source check
and cached; closing the panel does not rebuild its visible feed model.

Profile → Source Health shows the last saved results for active feeds, including
each failing publisher's error, consecutive failures, and last successful check.
Reload status reads local data; Refresh feeds contacts active publishers. Failed
checks keep cached stories available within the configured retention window,
and successful checks clear prior errors. The same saved status is available with
`chuchua-news sources --health` (`--all` also includes inactive sources).

OPML makes existing public feed lists reusable instead of locking the catalog to
one application:

```bash
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news sources \
  --all --export-opml ~/Downloads/chuchua-news-sources.opml
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news sources \
  --import-opml ~/Downloads/my-feeds.opml
```

The setup wizard's fourth page is the simpler path for adding one-off feeds: give
the feed a name and its HTTP/HTTPS RSS or Atom endpoint. **Test feed** checks
that URL and previews its latest available headline without saving anything.
Empty valid feeds are accepted; HTML pages and unreadable responses show errors.
You can also run `bin/chuchua-news sources --test https://example.org/feed.xml`.
Changes remain staged until the final setup page; custom feeds are fetched during the next refresh and
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

Profile export/import transfers setup choices and explicit interests. Imports
accept PYIN export formats 1–3 and complete, versioned legacy setup objects.
Unrelated files, unsupported versions, malformed settings, and invalid interest
entries are rejected before changing saved preferences. Settings and imported
interests are saved together; a failed write leaves both unchanged. Older files
without an interest graph keep existing explicit interests, while an explicitly
empty graph clears them. Expired temporary interests are not restored. Importing
a valid profile completes setup. Reading history, saved stories, and alerts are
not included in the profile export. Neither are cached articles, current edition
progress, event visits, or inferred learning history.

Useful checks:

```bash
~/.config/omarchy/plugins/tech.chuchua.news/bin/chuchua-news doctor
omarchy plugin validate ~/.config/omarchy/plugins/tech.chuchua.news
```
