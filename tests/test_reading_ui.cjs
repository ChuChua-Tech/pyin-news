// Exercise the application's JavaScript, including its Process exit callbacks.
// Node supplies the event loop/process doubles; no QML behavior is reimplemented.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const qml = fs.readFileSync(path.join(__dirname, '..', 'App.qml'), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));

function fixture() {
  const later = [];
  const launches = [];
  const root = {};
  let now = 0;
  let readingClockStart = 0;
  const context = vm.createContext({
    root,
    headlineList: {contentY:0, originY:0, contentHeight:0, height:400, forceLayout() {}},
    console: { log() {} },
    Qt: { callLater(callback) { later.push(callback); }, binding(callback) { return callback(); } },
    openedReload: { restarts: 0, restart() { this.restarts++; } },
    Window: { Hidden: 0, Windowed: 2, Minimized: 3 },
    window: { visible: true },
    windowContent: { Window: { active: true, visibility: 2 } },
    readingClock: {
      restartMs() { readingClockStart = now; },
      elapsedMs() { return now - readingClockStart; },
    },
  });

  // These are the real initial values and method bodies from the root QML item.
  for (const match of qml.matchAll(/^  property (?:var|int|real|bool|string) (\w+): (.+)$/gm)) {
    if (/^(?:\[\]|\(\{\}\)|null|true|false|\d+|".*")$/.test(match[2])) {
      root[match[1]] = vm.runInContext(`(${match[2]})`, context);
    }
  }
  for (const match of qml.matchAll(/^  (function (\w+)\([^\n]*\) \{[\s\S]*?^  \})/gm)) {
    root[match[2]] = vm.runInContext(`(${match[1]})`, context);
  }
  const busyBinding = qml.match(/^  readonly property bool readingEventsBusy: ([^\n]*(?:\n {4}[^\n]+)*)/m);
  assert.ok(busyBinding, 'the queue must expose its actual busy binding');
  Object.defineProperty(root, 'readingEventsBusy', {
    get() { return vm.runInContext(`(${busyBinding[1]})`, context); },
  });
  root.backendPath = '/test/chuchua-news';

  for (const match of qml.matchAll(/^  Timer \{\n    id: (\w+)\n[\s\S]*?^  \}/gm)) {
    const trigger = match[0].match(/^    onTriggered: (\{[\s\S]*?^    \}|[^\n]+)/m);
    const interval = match[0].match(/^    interval: (\d+)$/m);
    context[match[1]] = {
      interval: interval ? Number(interval[1]) : 1000,
      running: false,
      restarts: 0,
      due: 0,
      restart() { this.restarts++; this.running = true; this.due = now + this.interval; },
      stop() { this.running = false; },
      trigger() {
        this.running = false;
        assert.ok(trigger, `${match[1]} must have a callback`);
        vm.runInContext(`(function() { ${trigger[1]} })`, context)();
      },
    };
  }

  const processes = {};
  for (const match of qml.matchAll(/^  Process \{\n    id: (\w+)\n[\s\S]*?^  \}/gm)) {
    const name = match[1];
    const block = match[0];
    const collectors = [...block.matchAll(/(?:stdout|stderr): StdioCollector \{ id: (\w+);/g)]
      .map(value => value[1]);
    for (const collector of collectors) context[collector] = { text: '' };
    const onExited = block.match(/^    onExited: (function\([^\n]*\) \{[\s\S]*?^    \})/m);
    const onRunningChanged = block.match(/^    onRunningChanged: (\{[\s\S]*?^    \})/m);
    let running = false;
    processes[name] = context[name] = {
      command: [],
      get running() { return running; },
      set running(value) {
        const changed = running !== value;
        running = value;
        if (value) {
          for (const collector of collectors) context[collector].text = '';
          launches.push({ process: name, command: plain(this.command) });
        }
        if (changed && onRunningChanged) {
          // QML makes this Process's properties available to its handlers.
          vm.runInContext(`(function(process) {
            var running = process.running;
            ${onRunningChanged[1]}
          })`, context)(this);
        }
      },
      failToStart() {
        assert.equal(running, true, `${name} must have attempted to start`);
        this.running = false;
        // Quickshell emits runningChanged, but no exited, for a failed start.
      },
      complete(payload, exitCode = 0, exitStatus = 0) {
        assert.equal(running, true, `${name} must be running before it exits`);
        this.running = false;
        const stdout = collectors.find(value => /Stdout$/.test(value));
        assert.ok(stdout, `${name} must collect stdout`);
        context[stdout].text = JSON.stringify(payload);
        assert.ok(onExited, `${name} must acknowledge its exit`);
        vm.runInContext(`(${onExited[1]})`, context)(exitCode, exitStatus);
      },
    };
  }

  return {
    root,
    context,
    processes,
    launches,
    advance(milliseconds) {
      const target = now + milliseconds;
      let count = 0;
      while (context.readingEngagementTimer.running && context.readingEngagementTimer.due <= target) {
        assert.ok(count++ < 100, 'the reading deadline must advance or stop');
        now = context.readingEngagementTimer.due;
        context.readingEngagementTimer.trigger();
      }
      now = target;
    },
    enableMeasurementHooks() {
      // Invoke the actual QML property handlers when these input properties change.
      const bind = (object, property, pattern, scope = '') => {
        const hook = qml.match(pattern);
        assert.ok(hook, `missing measurement hook for ${property}`);
        let value = object[property];
        Object.defineProperty(object, property, {
          configurable: true,
          get() { return value; },
          set(next) {
            if (value === next) return;
            value = next;
            vm.runInContext(`(function() { ${scope} ${hook[1]} })`, context)();
          },
        });
      };
      for (const property of ['viewMode', 'resultKind', 'activeArticle', 'opened']) {
        const name = property[0].toUpperCase() + property.slice(1);
        bind(root, property, new RegExp(`^  on${name}Changed: (\\{[\\s\\S]*?^  \\}|[^\\n]+)`, 'm'));
      }
      bind(context.windowContent.Window, 'active',
        /^      Window.onActiveChanged: (\{[\s\S]*?^      \})/m,
        'var Window = windowContent.Window;');
      bind(context.windowContent.Window, 'visibility',
        /^      Window.onVisibilityChanged: (\{[\s\S]*?^      \})/m);
      bind(context.window, 'visible', /^    onVisibleChanged: (\{[\s\S]*?^    \})/m,
        'var visible = window.visible;');
    },
    flush() {
      let count = 0;
      while (later.length) {
        assert.ok(count++ < 100, 'deferred callbacks must become idle');
        later.shift()();
      }
    },
    completeReading(payload, exitCode = 0, exitStatus = 0) {
      processes.readingEventProc.complete(payload, exitCode, exitStatus);
      this.flush();
    },
    readingCommands() {
      return launches.filter(value => value.process === 'readingEventProc')
        .map(value => value.command);
    },
  };
}

function opened(articleId, opens, count, timestamp = 1800000000) {
  return {
    ok: true,
    article_id: articleId,
    signal: 'open',
    opens,
    last_opened_ts: timestamp,
    counts: { history: count },
    applied: opens === 1,
  };
}

function readingIds(f) {
  return f.readingCommands().map(command => command[command.indexOf('--id') + 1]);
}

test('rapid A, B, A views are serialized and only acknowledged distinct counts appear', () => {
  const f = fixture();
  const a = { id: 'a', opened: false };
  const b = { id: 'b', opened: false };
  f.root.learnArticle(a, 'open');
  f.root.learnArticle(b, 'open');
  f.root.learnArticle(a, 'open');
  f.flush();
  assert.deepEqual(readingIds(f), ['a']);
  assert.equal(f.root.historyCount, 0);

  f.completeReading(opened('a', 1, 1));
  assert.deepEqual(readingIds(f), ['a', 'b']);
  assert.equal(f.root.historyCount, 1);
  f.completeReading(opened('b', 1, 2));
  assert.deepEqual(readingIds(f), ['a', 'b', 'a']);
  f.completeReading(opened('a', 2, 2, 1800000060));
  assert.equal(f.root.historyCount, 2);
  assert.equal(f.root.readingQueue.length, 0);
  assert.equal(f.root.activeReadingEvent, null);
  assert.equal(f.processes.readingEventProc.running, false);
});

test('non-open signals deduplicate while pending and after success', () => {
  const f = fixture();
  const article = { id: 'a' };
  f.root.learnArticle(article, 'engaged');
  f.root.learnArticle(article, 'engaged');
  f.flush();
  assert.equal(f.readingCommands().length, 1);
  f.completeReading({ ok: true, article_id: 'a', signal: 'engaged', applied: true });
  f.root.learnArticle(article, 'engaged');
  f.flush();
  assert.equal(f.readingCommands().length, 1);
  assert.equal(f.root.historyCount, 0);

  f.root.learnArticle(article, 'external');
  f.flush();
  assert.equal(f.readingCommands().length, 2);
});

test('failed signals preserve saved counts and allow a later retry', () => {
  const f = fixture();
  f.root.historyCount = 4;
  f.root.articles = [{ id: 'a', opened: false, opens: 0 }];
  f.root.learnArticle(f.root.articles[0], 'open');
  f.flush();
  f.completeReading({ ok: false, error: 'database is locked' }, 1);
  assert.equal(f.root.historyCount, 4);
  assert.equal(f.root.articles[0].opened, false);
  assert.equal(f.context.openedReload.restarts, 0);

  f.root.learnArticle(f.root.articles[0], 'engaged');
  f.flush();
  f.completeReading({ ok: false, error: 'database is locked' }, 1);
  f.root.learnArticle(f.root.articles[0], 'engaged');
  f.flush();
  assert.equal(f.readingCommands().length, 3);
  f.completeReading({ ok: true, article_id: 'a', signal: 'engaged', applied: true });
  assert.equal(f.root.historyCount, 4);
});

test('a failed event does not strand the next queued story', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'open');
  f.root.learnArticle({ id: 'b' }, 'open');
  f.flush();
  f.completeReading({ ok: false, error: 'article not found' }, 1);
  assert.deepEqual(readingIds(f), ['a', 'b']);
  f.completeReading(opened('b', 1, 1));
  assert.equal(f.root.historyCount, 1);
});

test('a failed process cannot acknowledge successful-looking output', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  f.completeReading(opened('a', 1, 1), 1);
  assert.equal(f.root.historyCount, 0);
  assert.equal(f.context.openedReload.restarts, 0);
  assert.equal(f.root.activeReadingEvent, null);
});

test('a helper that crashes with zero exit code cannot acknowledge a view', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  f.completeReading(opened('a', 1, 1), 0, 1);
  assert.equal(f.root.historyCount, 0);
  assert.equal(f.context.openedReload.restarts, 0);
});

test('failed helper starts release the event and continue the queue', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'engaged');
  f.root.learnArticle({ id: 'b' }, 'open');
  f.flush();
  f.processes.readingEventProc.failToStart();
  f.flush();
  assert.deepEqual(readingIds(f), ['a', 'b']);
  assert.equal(f.root.historyCount, 0);
  assert.equal(f.context.openedReload.restarts, 0);
  f.completeReading(opened('b', 1, 1));
  assert.equal(f.root.historyCount, 1);
  f.root.learnArticle({ id: 'a' }, 'engaged');
  f.flush();
  assert.deepEqual(readingIds(f), ['a', 'b', 'a']);
});

test('a deferred fallback from a completed event does not fail its successor', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  // Start a successor before the completed event's deferred fallback runs.
  f.processes.readingEventProc.complete(opened('a', 1, 1));
  f.root.learnArticle({ id: 'b' }, 'open');
  f.flush();
  assert.deepEqual(readingIds(f), ['a', 'b']);
  assert.equal(f.processes.readingEventProc.running, true);
  assert.equal(f.root.historyCount, 1);
  assert.equal(f.context.openedReload.restarts, 1);
  f.completeReading(opened('b', 1, 2));
  assert.equal(f.root.historyCount, 2);
  assert.equal(f.context.openedReload.restarts, 2);
  assert.equal(f.root.activeReadingEvent, null);
});

test('view acknowledgements patch all current models without moving stories or selection', () => {
  const f = fixture();
  for (const key of ['articles', 'searchResults', 'bookmarks', 'historyArticles', 'readArticles']) {
    f.root[key] = [
      { id: 'b', opened: false, title: 'Second story' },
      { id: 'a', opened: true, opens: 1, title: 'First story' },
    ];
  }
  f.root.activeArticle = { id: 'a', opened: true, opens: 1 };
  f.root.activeArticleId = 'a';
  f.root.selectedIndex = 1;
  f.root.historyIndex = 1;
  f.root.learnArticle(f.root.activeArticle, 'open');
  f.flush();
  f.completeReading(opened('a', 2, 2, 1800000060));
  for (const key of ['articles', 'searchResults', 'bookmarks', 'historyArticles', 'readArticles']) {
    assert.deepEqual(plain(f.root[key].map(article => article.id)), ['b', 'a'], key);
    assert.equal(f.root[key][1].opens, 2, key);
    assert.equal(f.root[key][1].last_opened_ts, 1800000060, key);
    assert.equal(f.root[key][1].title, 'First story', key);
    assert.equal(f.root[key][0].opened, false, key);
  }
  assert.equal(f.root.activeArticle.opens, 2);
  assert.equal(f.root.selectedIndex, 1);
  assert.equal(f.root.historyIndex, 1);
});

test('No signal does not prevent a later history entry', () => {
  const f = fixture();
  // Previously cached learning is independent of the factual view ledger.
  f.root.learnedArticles = { 'a:open': true, 'a:engaged': true };
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  assert.deepEqual(readingIds(f), ['a']);
  f.completeReading({ ...opened('a', 2, 1), applied: false });
  assert.equal(f.root.historyCount, 1);
});

test('history requested during rapid reading waits for every queued view to settle', () => {
  const f = fixture();
  f.root.viewMode = 'history';
  f.root.learnArticle({ id: 'a' }, 'open');
  f.root.learnArticle({ id: 'b' }, 'open');
  f.root.loadHistory();
  f.flush();
  assert.equal(f.processes.historyProc.running, false);
  f.completeReading(opened('a', 1, 1));
  assert.equal(f.processes.historyProc.running, false);
  f.completeReading(opened('b', 1, 2));
  assert.equal(f.processes.historyProc.running, true);
  f.processes.historyProc.complete({ ok: true, articles: [{ id: 'b' }, { id: 'a' }], count: 2 });
  f.flush();
  assert.deepEqual(plain(f.root.historyArticles.map(article => article.id)), ['b', 'a']);
});

test('an older in-flight history response cannot overwrite an acknowledged view', () => {
  const f = fixture();
  f.root.viewMode = 'history';
  f.root.historyArticles = [{ id: 'old', opens: 1 }];
  f.root.historyCount = 1;
  f.root.loadHistory();
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  f.completeReading(opened('a', 1, 2));
  f.processes.historyProc.complete({ ok: true, articles: [{ id: 'stale' }], count: 1 });
  f.flush();
  assert.equal(f.root.historyCount, 2);
  assert.deepEqual(plain(f.root.historyArticles.map(article => article.id)), ['old']);
  assert.equal(f.processes.historyProc.running, true);
  f.processes.historyProc.complete({ ok: true, articles: [{ id: 'a' }, { id: 'old' }], count: 2 });
  f.flush();
  assert.deepEqual(plain(f.root.historyArticles.map(article => article.id)), ['a', 'old']);
});

test('history responses arriving before a pending write finishes are refreshed after it', () => {
  const f = fixture();
  f.root.viewMode = 'history';
  f.root.historyArticles = [{ id: 'old' }];
  f.root.loadHistory();
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  f.processes.historyProc.complete({ ok: true, articles: [{ id: 'stale' }], count: 0 });
  f.flush();
  assert.deepEqual(plain(f.root.historyArticles.map(article => article.id)), ['old']);
  assert.equal(f.processes.historyProc.running, false);
  f.completeReading(opened('a', 1, 1));
  assert.equal(f.processes.historyProc.running, true);
  f.processes.historyProc.complete({ ok: true, articles: [{ id: 'a' }], count: 1 });
  f.flush();
  assert.deepEqual(plain(f.root.historyArticles.map(article => article.id)), ['a']);
});

test('an already-applied non-open signal does not trigger a feed reload', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'engaged');
  f.flush();
  f.completeReading({ ok: true, article_id: 'a', signal: 'engaged', applied: false });
  assert.equal(f.context.openedReload.restarts, 0);
});

test('turning learning back on can record a signal previously attempted while disabled', () => {
  const f = fixture();
  f.root.learnArticle({ id: 'a' }, 'engaged');
  f.flush();
  f.completeReading({
    ok: true, article_id: 'a', signal: 'engaged', applied: false, learning_enabled: false,
  });
  assert.equal(f.context.openedReload.restarts, 0);
  f.root.learnArticle({ id: 'a' }, 'engaged');
  f.flush();
  assert.equal(f.readingCommands().length, 2);
  f.completeReading({
    ok: true, article_id: 'a', signal: 'engaged', applied: true, learning_enabled: true,
  });
  f.root.learnArticle({ id: 'a' }, 'engaged');
  f.flush();
  assert.equal(f.readingCommands().length, 2);
  assert.equal(f.context.openedReload.restarts, 1);
});

test('a confirmed reset cannot race an active or queued reading write', () => {
  const f = fixture();
  f.root.confirmProfileReset = true;
  f.root.learnArticle({ id: 'a' }, 'open');
  f.root.learnArticle({ id: 'b' }, 'open');
  f.root.resetProfileLearning();
  assert.equal(f.processes.profileResetProc.running, false);
  assert.equal(f.root.confirmProfileReset, true);
  f.completeReading(opened('a', 1, 1));
  f.root.resetProfileLearning();
  assert.equal(f.processes.profileResetProc.running, false);
  f.completeReading(opened('b', 1, 2));
  f.root.resetProfileLearning();
  assert.equal(f.processes.profileResetProc.running, true);
});

test('acknowledged reading reloads retain the current feed order', () => {
  const f = fixture();
  const loads = [];
  f.root.loadFeed = (...args) => loads.push(args);
  const timer = qml.match(/^  Timer \{\n    id: openedReload\n[\s\S]*?^  \}/m);
  assert.ok(timer, 'reading events must schedule their feed refresh');
  const trigger = timer[0].match(/^    onTriggered: (.+)$/m);
  assert.ok(trigger);
  vm.runInContext(`(function() { ${trigger[1]} })`, f.context)();
  assert.deepEqual(loads, [[true, 'opened-signal']]);
});

test('unversioned or old library counts cannot overwrite acknowledged history', () => {
  const f = fixture();
  const earlierRevision = f.root.historyRevision;
  f.root.learnArticle({ id: 'a' }, 'open');
  f.flush();
  f.completeReading(opened('a', 1, 1));
  f.root.applyLibraryCounts({ history: 0, bookmarks: 3 }, earlierRevision);
  assert.equal(f.root.historyCount, 1);
  assert.equal(f.root.bookmarkCount, 3);
  f.root.applyLibraryCounts({ history: 0 });
  assert.equal(f.root.historyCount, 1);
  f.root.applyLibraryCounts({ history: 4 }, f.root.historyRevision);
  assert.equal(f.root.historyCount, 4);
});

test('queued reading waits for explicit feedback and reset writes', () => {
  for (const blocker of ['feedbackProc', 'profileResetProc']) {
    for (const success of [true, false]) {
      const f = fixture();
      f.root.loadFeed = () => {};
      f.processes[blocker].running = true;
      f.root.learnArticle({ id: 'a' }, 'open');
      f.flush();
      assert.equal(f.readingCommands().length, 0, blocker);
      f.processes[blocker].complete({ ok: success, counts: {} }, success ? 0 : 1);
      f.flush();
      assert.deepEqual(readingIds(f), ['a'], `${blocker} success=${success}`);
    }
  }
});

function readingFixture() {
  const f = fixture();
  f.enableMeasurementHooks();
  f.root.opened = true;
  const signals = [];
  f.root.learnArticle = (article, signal) => signals.push([article.id, signal]);
  f.root.showArticle({ id: 'a', title: 'Story A' });
  return { ...f, signals, engaged: () => signals.filter(value => value[1] === 'engaged') };
}

function eventFixture() {
  const f = readingFixture();
  f.context.resultScroll = { contentY: 120 };
  f.context.eventPage = { position: 0, resetPosition() { this.position = 0; } };
  f.context.keyCatcher = { forceActiveFocus() {} };
  f.context.searchField = { text: '' };
  f.root.returnViewMode = 'history';
  f.root.articleBackMarksRead = true;
  f.root.loadHistory = () => {};
  f.root.eventPayload = {
    ok: true, event_id: 'event-a', seen_through: 10, first_visit: false,
    articles: [{ id: 'a', title: 'Story A', source: 'Alpha', is_new: false },
      { id: 'b', title: 'Story B', source: 'Beta', is_new: true }],
    new_count: 1, article_count: 2, source_count: 2,
  };
  return f;
}

test('opening Event Desk pauses engagement and acknowledges only a displayed snapshot', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  assert.equal(f.root.viewMode, 'event');
  assert.equal(f.root.readingArticleId, '');
  assert.deepEqual(plain(f.processes.eventProc.command), ['/test/chuchua-news', 'event', '--article-id', 'a']);
  f.processes.eventProc.complete(f.root.eventPayload);
  assert.equal(f.processes.eventSeenProc.running, false);
  f.flush();
  assert.deepEqual(plain(f.processes.eventSeenProc.command),
    ['/test/chuchua-news', 'event-seen', '--id', 'event-a', '--through', '10']);
  f.processes.eventSeenProc.complete({ ok: true });
  f.flush();
  assert.equal(f.root.eventData.new_count, 1, 'this visit keeps its original new markers');
  assert.deepEqual(f.signals, [['a', 'open']]);
});

test('leaving before rendering does not acknowledge the event', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.root.navigateBack();
  f.flush();
  assert.equal(f.root.viewMode, 'result');
  assert.equal(f.context.resultScroll.contentY, 120);
  assert.equal(f.processes.eventSeenProc.running, false);
});

test('closing the window before rendering does not acknowledge the event', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.root.opened = false;
  f.flush();
  assert.equal(f.processes.eventSeenProc.running, false);
});

test('unfocused and minimized event pages wait for a visible focused visit', () => {
  for (const state of ['unfocused', 'minimized']) {
    const f = eventFixture();
    f.root.showEventDesk();
    if (state === 'unfocused') f.context.windowContent.Window.active = false;
    else f.context.windowContent.Window.visibility = 3;
    f.processes.eventProc.complete(f.root.eventPayload);
    f.flush();
    assert.equal(f.processes.eventSeenProc.running, false);
    f.context.windowContent.Window.active = true;
    f.context.windowContent.Window.visibility = 2;
    f.flush();
    assert.equal(f.processes.eventSeenProc.running, true);
    f.root.queueEventVisit();
    assert.deepEqual(plain(f.root.eventSeenQueue), []);
  }
});

test('a stale event response cannot replace or acknowledge a newly requested event', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.root.navigateBack();
  f.root.showArticle({ id: 'c', title: 'Story C' });
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.flush();
  assert.deepEqual(plain(f.root.eventData), {});
  assert.equal(f.processes.eventSeenProc.running, false);
  assert.equal(f.processes.eventProc.command.at(-1), 'c');
  f.processes.eventProc.complete({ ...f.root.eventPayload, event_id: 'event-c', seen_through: 22 });
  f.flush();
  assert.equal(f.root.eventData.event_id, 'event-c');
  assert.equal(f.processes.eventSeenProc.command.at(-1), '22');
});

test('timeline report navigation preserves position and does not auto-hide reports', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.flush();
  f.context.eventPage.position = 315;
  f.root.showEventArticle(f.root.eventData.articles[1]);
  assert.equal(f.root.activeArticleId, 'b');
  assert.equal(f.root.returnViewMode, 'history');
  f.root.navigateBack();
  assert.equal(f.root.viewMode, 'event');
  assert.equal(f.context.eventPage.position, 315);
  assert.equal(f.processes.readMutationProc.running, false);
  f.root.navigateBack();
  assert.equal(f.root.viewMode, 'result');
  assert.equal(f.root.activeArticleId, 'a');
  assert.equal(f.context.resultScroll.contentY, 120);
  assert.deepEqual(f.signals, [['a', 'open'], ['b', 'open']]);
});

test('event opened directly from a library returns to that library', () => {
  const f = eventFixture();
  f.root.viewMode = 'bookmarks';
  f.root.selectedBookmark = { id: 'saved', title: 'Saved story' };
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.flush();
  f.root.showEventArticle(f.root.eventData.articles[0]);
  assert.equal(f.root.returnViewMode, 'bookmarks');
  f.root.navigateBack();
  f.root.navigateBack();
  assert.equal(f.root.viewMode, 'bookmarks');
});

test('failed event helper starts and error exits allow retry without recording a visit', () => {
  for (const failure of ['start', 'exit', 'crash']) {
    const f = eventFixture();
    f.root.showEventDesk();
    if (failure === 'start') f.processes.eventProc.failToStart();
    else f.processes.eventProc.complete({ ...f.root.eventPayload }, failure === 'exit' ? 1 : 0,
      failure === 'crash' ? 1 : 0);
    f.flush();
    assert.equal(f.root.eventData.ok, false);
    assert.equal(f.processes.eventSeenProc.running, false);
    f.root.loadEventDesk();
    f.processes.eventProc.complete(f.root.eventPayload);
    f.flush();
    assert.equal(f.root.eventData.ok, true);
    assert.equal(f.processes.eventSeenProc.running, true);
  }
});

test('failed visit writes release the queue and explain repeated new markers', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.flush();
  f.root.eventSeenQueue = [{ id: 'second-event', through: 30 }];
  f.processes.eventSeenProc.failToStart();
  f.flush();
  assert.match(f.root.eventVisitError, /could not be saved/);
  assert.equal(f.root.activeEventSeen.id, 'second-event');
  f.processes.eventSeenProc.complete({ ok: true });
  f.flush();
  assert.equal(f.root.activeEventSeen, null);
});

test('empty filtered coverage cannot record a visit', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete({ ok: true, event_id: 'a', articles: [], seen_through: 0 });
  f.flush();
  assert.equal(f.processes.eventSeenProc.running, false);
});

test('event metadata changes reach the timeline and the original report', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.flush();
  f.root.patchEventArticle('a', { bookmarked: true, read: true });
  assert.equal(f.root.eventData.articles[0].bookmarked, true);
  f.root.patchEventArticle('b', { dismissed: true });
  assert.equal(f.root.eventData.article_count, 1);
  assert.equal(f.root.eventData.source_count, 1);
  assert.equal(f.root.eventData.new_count, 0);
  f.root.navigateBack();
  assert.equal(f.root.activeArticle.bookmarked, true);
  assert.equal(f.root.activeArticle.read, true);
});

test('reset waits for pending visit writes and blocks event entry during reset', () => {
  const f = eventFixture();
  f.root.showEventDesk();
  f.processes.eventProc.complete(f.root.eventPayload);
  f.flush();
  f.root.confirmProfileReset = true;
  f.root.resetProfileLearning();
  assert.equal(f.processes.profileResetProc.running, false);
  f.root.navigateBack();
  f.processes.profileResetProc.running = true;
  f.root.showEventDesk();
  assert.equal(f.root.viewMode, 'result');
});

function eventPageFixture() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'EventDeskPage.qml'), 'utf8');
  const later = [];
  const timeline = {
    contentY: 90,
    forceLayout() {}, returnToBounds() {},
    positionViewAtBeginning() { this.contentY = -146; },
  };
  const page = {
    coverage: {}, displayedEventId: 'event-a', modelRevision: 0,
    selectedIndex: 2, restorePending: false, restorePosition: 0,
  };
  let articles = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
  Object.defineProperty(page, 'articles', {
    get() { return articles; },
    // Native ListView resets its position on JS-array model replacement.
    set(values) { articles = values; timeline.contentY = -146; },
  });
  const context = vm.createContext({ page, timeline, Qt: { callLater(fn) { later.push(fn); } } });
  for (const match of source.matchAll(/^  (function (\w+)\([^\n]*\) \{[\s\S]*?^  \})/gm))
    page[match[2]] = vm.runInContext(`(${match[1]})`, context);
  for (const name of [...Object.keys(page), 'articles'])
    Object.defineProperty(context, name, { get() { return page[name]; }, set(value) { page[name] = value; } });
  const handler = source.match(/^  onCoverageChanged: (\{[\s\S]*?^  \})/m);
  assert.ok(handler);
  return {
    page, timeline,
    update(identity, values) {
      page.coverage = { ok: true, event_id: identity, articles: values };
      vm.runInContext(`(function() { ${handler[1]} })`, context)();
    },
    flush() { while (later.length) later.shift()(); },
  };
}

test('timeline model updates restore scroll position and selected report after native reset', () => {
  const f = eventPageFixture();
  f.update('event-a', [{ id: 'a' }, { id: 'c', read: true }]);
  assert.equal(f.timeline.contentY, -146);
  f.flush();
  assert.equal(f.timeline.contentY, 90);
  assert.equal(f.page.selectedIndex, 1);
});

test('overlapping metadata updates retain the original position until delegates settle', () => {
  const f = eventPageFixture();
  f.update('event-a', [{ id: 'a' }, { id: 'b' }, { id: 'c', read: true }]);
  f.update('event-a', [{ id: 'a' }, { id: 'b' }, { id: 'c', read: true, bookmarked: true }]);
  f.flush();
  assert.equal(f.timeline.contentY, 90);
  assert.equal(f.page.selectedIndex, 2);
});

test('new or empty events invalidate a pending scroll restoration', () => {
  for (const identity of ['event-b', 'event-a']) {
    const f = eventPageFixture();
    f.update('event-a', [{ id: 'a' }, { id: 'b' }]);
    f.update(identity, identity === 'event-a' ? [] : [{ id: 'other' }]);
    f.flush();
    assert.equal(f.timeline.contentY, -146);
    assert.equal(f.page.selectedIndex, -1);
  }
});

test('unsupported System AI explains the choice without opening or launching a summary', () => {
  const { root, launches } = fixture();
  root.aiEnabled = true;
  root.aiProvider = 'system';
  root.systemAiStatus = { available: false, message: 'Claude Code is selected; adapter unavailable.' };
  root.viewMode = 'feed';
  root.summarizeArticle({ id: 'story', title: 'A story' });
  assert.equal(root.statusText, root.systemAiStatus.message);
  assert.equal(root.viewMode, 'feed');
  assert.equal(root.activeArticle, null);
  assert.deepEqual(launches, []);
  root.aiBusy = true;
  root.statusText = 'Summary in progress';
  root.summarizeArticle({ id: 'another' });
  assert.equal(root.statusText, 'Summary in progress');
});

test('profile refresh updates agent availability while preserving setup and saved preference', () => {
  const { root, processes } = fixture();
  root.setupData = { profile: { ai: { system_model: 'saved-model', system_effort: 'low' } }, catalogs: { retained: true } };
  processes.profileProc.running = true;
  processes.profileProc.complete({ ok: true, system_ai_status: { agent: 'claude', available: false } });
  assert.deepEqual(plain(root.setupData.system_ai_status), { agent: 'claude', available: false });
  assert.equal(root.setupData.profile.ai.system_model, 'saved-model');
  assert.equal(root.setupData.catalogs.retained, true);
  processes.profileProc.running = true;
  processes.profileProc.complete({ ok: true, system_ai_status: { agent: 'codex', available: true } });
  assert.equal(root.setupData.system_ai_status.available, true);
});

test('summary command forwards configured preference without inventing a model override', () => {
  const { root } = fixture();
  root.aiProvider = 'system';
  root.systemAiModel = '';
  root.systemAiEffort = '';
  root.localAiUrl = 'http://127.0.0.1:11434/v1';
  root.localAiModel = 'local-model';
  assert.deepEqual(plain(root.aiCommand('summarize', ['--id', 'story', '--stream'])), [
    '/test/chuchua-news', 'summarize', '--id', 'story', '--stream',
    '--provider', 'system', '--system-model', '', '--system-effort', '',
    '--local-url', 'http://127.0.0.1:11434/v1', '--local-model', 'local-model',
  ]);
});

test('model discovery runs only on request and guards concurrent or unsupported launches', () => {
  const { root, launches, processes } = fixture();
  root.systemAiStatus = { agent: 'codex', available: true };
  assert.deepEqual(launches, []);
  root.loadAiModels(false);
  root.loadAiModels(false);
  assert.deepEqual(launches.map(x => x.command), [['/test/chuchua-news', 'ai-models']]);
  processes.aiModelsProc.complete({ ok: true, agent: 'codex', models: [{ value: 'new-model' }] });
  root.loadAiModels(true);
  assert.deepEqual(launches[1].command, ['/test/chuchua-news', 'ai-models', '--refresh']);
  processes.aiModelsProc.complete({ ok: false, agent: 'codex', models: [{ value: 'new-model' }], stale: true, error: 'Retry' }, 1);
  assert.equal(root.aiModelCatalog.models[0].value, 'new-model');
  assert.equal(root.aiModelCatalog.error, 'Retry');
  root.systemAiStatus.available = false;
  root.loadAiModels(true);
  assert.equal(launches.length, 2);
});

test('failed model discovery starts allow retry and stale agent responses are discarded', () => {
  const f = fixture();
  const { root, processes } = f;
  root.systemAiStatus = { agent: 'codex', available: true };
  root.loadAiModels(false);
  processes.aiModelsProc.failToStart();
  f.flush();
  assert.match(root.aiModelCatalog.error, /Could not load models/);
  root.loadAiModels(false);
  root.aiModelCatalogRevision++;
  root.aiModelCatalog = {};
  processes.aiModelsProc.complete({ ok: true, agent: 'codex', models: [{ value: 'stale' }] });
  f.flush();
  assert.deepEqual(root.aiModelCatalog, {});
  root.loadAiModels(false);
  processes.aiModelsProc.complete({ ok: false, agent: 'claude', models: [] }, 1);
  assert.match(root.aiModelCatalog.error, /agent changed/);
});

test('saving a manual model uses structured arguments and failed writes preserve setup', () => {
  const { root, processes, launches } = fixture();
  root.systemAiModel = '';
  root.systemAiEffort = '';
  root.setupData = { profile: { ai: { system_model: '' } } };
  root.setSystemAiModel('provider/future:v2', 'deeper');
  assert.deepEqual(JSON.parse(launches[0].command[3]), { model: 'provider/future:v2', effort: 'deeper' });
  processes.systemAiPresetProc.complete({ ok: true, profile: { ai: { system_model: 'wrong' } } }, 1);
  assert.equal(root.setupData.profile.ai.system_model, '');
});

test('reading engagement requires twelve focused seconds and is emitted once', () => {
  const f = readingFixture();
  f.advance(11999);
  assert.deepEqual(f.engaged(), []);
  f.advance(1);
  assert.deepEqual(f.engaged(), [['a', 'engaged']]);
  f.advance(60000);
  f.root.syncReadingEngagement();
  assert.deepEqual(f.engaged(), [['a', 'engaged']]);
  assert.equal(f.context.readingEngagementTimer.running, false);
});

test('focus loss pauses reading and focus return schedules only the remaining time', () => {
  const f = readingFixture();
  f.advance(4500);
  f.context.windowContent.Window.active = false;
  assert.equal(f.root.readingElapsedMs, 4500);
  assert.equal(f.context.readingEngagementTimer.running, false);
  f.advance(90000);
  assert.deepEqual(f.engaged(), []);
  f.context.windowContent.Window.active = true;
  assert.equal(f.context.readingEngagementTimer.interval, 7500);
  f.advance(7499);
  assert.deepEqual(f.engaged(), []);
  f.advance(1);
  assert.deepEqual(f.engaged(), [['a', 'engaged']]);
});

test('an article opened while unfocused gets no reading time before focus returns', () => {
  const f = fixture();
  f.enableMeasurementHooks();
  f.root.opened = true;
  f.context.windowContent.Window.active = false;
  const signals = [];
  f.root.learnArticle = (article, signal) => signals.push([article.id, signal]);
  f.root.showArticle({ id: 'a', title: 'Story A' });
  f.advance(90000);
  assert.equal(f.root.readingElapsedMs, 0);
  assert.equal(f.context.readingEngagementTimer.running, false);
  f.context.windowContent.Window.active = true;
  f.advance(12000);
  assert.deepEqual(signals, [['a', 'open'], ['a', 'engaged']]);
});

test('minimized windows pause reading even if the active flag has not changed', () => {
  const f = readingFixture();
  f.advance(5000);
  f.context.windowContent.Window.visibility = f.context.Window.Minimized;
  f.advance(60000);
  assert.deepEqual(f.engaged(), []);
  assert.equal(f.root.readingElapsedMs, 5000);
  f.context.windowContent.Window.visibility = f.context.Window.Windowed;
  f.advance(6999);
  assert.deepEqual(f.engaged(), []);
  f.advance(1);
  assert.deepEqual(f.engaged(), [['a', 'engaged']]);
});

test('closing the reader discards unfinished reading time and stops its deadline', () => {
  const f = readingFixture();
  f.advance(7000);
  f.root.close();
  f.advance(60000);
  assert.equal(f.root.opened, false);
  assert.equal(f.root.readingElapsedMs, 0);
  assert.equal(f.context.readingEngagementTimer.running, false);
  assert.deepEqual(f.engaged(), []);
});

test('hiding the native window stops measurement and closes the reader', () => {
  const f = readingFixture();
  f.advance(5000);
  f.context.window.visible = false;
  f.advance(60000);
  assert.equal(f.root.opened, false);
  assert.equal(f.context.readingEngagementTimer.running, false);
  assert.deepEqual(f.engaged(), []);
});

test('leaving the synopsis or switching to AI discards the unfinished interval', () => {
  for (const leave of [root => { root.viewMode = 'feed'; }, root => { root.resultKind = 'ai'; }]) {
    const f = readingFixture();
    f.advance(11000);
    leave(f.root);
    f.advance(60000);
    assert.equal(f.context.readingEngagementTimer.running, false);
    assert.equal(f.root.readingElapsedMs, 0);
    assert.deepEqual(f.engaged(), []);
    f.root.showArticle({ id: 'a', title: 'Story A' });
    f.advance(11999);
    assert.deepEqual(f.engaged(), []);
    f.advance(1);
    assert.deepEqual(f.engaged(), [['a', 'engaged']]);
  }
});

test('switching stories cannot apply the previous story reading time to the new one', () => {
  const f = readingFixture();
  f.advance(10000);
  f.root.showArticle({ id: 'b', title: 'Story B' });
  f.advance(11999);
  assert.deepEqual(f.engaged(), []);
  f.advance(1);
  assert.deepEqual(f.engaged(), [['b', 'engaged']]);
});

test('history metadata updates do not restart the current article reading interval', () => {
  const f = readingFixture();
  f.advance(5000);
  f.root.activeArticle = { ...f.root.activeArticle, opens: 2, last_opened_ts: 1800000000 };
  assert.equal(f.context.readingEngagementTimer.interval, 7000);
  f.advance(7000);
  assert.deepEqual(f.engaged(), [['a', 'engaged']]);
});

test('focused reading uses elapsed time independently of wall clock corrections', () => {
  const f = readingFixture();
  f.advance(6000);
  f.context.Date = { now: () => 99999999999999 };
  f.root.syncReadingEngagement();
  assert.deepEqual(f.engaged(), []);
  assert.equal(f.context.readingEngagementTimer.interval, 6000);
  f.advance(6000);
  assert.deepEqual(f.engaged(), [['a', 'engaged']]);
});

test('revisiting an engaged article still uses the established reading-signal deduplication', () => {
  const f = fixture();
  f.enableMeasurementHooks();
  f.root.opened = true;
  f.root.showArticle({ id: 'a', title: 'Story A' });
  f.completeReading(opened('a', 1, 1));
  f.advance(12000);
  f.completeReading({ ok: true, article_id: 'a', signal: 'engaged', applied: true });
  f.root.viewMode = 'feed';
  f.root.showArticle({ id: 'a', title: 'Story A' });
  f.completeReading(opened('a', 2, 1));
  f.advance(12000);
  const signals = f.readingCommands().map(command => command[command.indexOf('--signal') + 1]);
  assert.deepEqual(signals, ['open', 'engaged', 'open']);
});

function impressionsFixture(rows, height = 200) {
  const f = fixture();
  f.root.opened = true;
  f.root.articles = rows.filter(Boolean).map(row => ({ id: row.id }));
  const list = f.context.headlineList = {
    visible: true, width: 300, height, count: rows.length,
    itemAtIndex(index) { return this.rows[index]; },
    rows: [],
  };
  list.rows = rows.map(row => row === null ? null : ({
    visible: true, opacity: 1, leavingFeed: false,
    width: 300, height: 100, ...row,
    modelData: { id: row.id },
    mapToItem(view, x, y, width, rowHeight) {
      assert.equal(view, list);
      return { x: (this.x || 0) + x, y: this.y + y, width, height: rowHeight };
    },
  }));
  return f;
}

function sentImpressions(f) {
  const command = f.processes.impressionProc.command;
  return JSON.parse(command[command.indexOf('--items-json') + 1]);
}

test('impressions include partial cards and exclude both cached offscreen edges', () => {
  const f = impressionsFixture([
    { id: 'above', y: -100 }, { id: 'partial-top', y: -99 },
    { id: 'middle', y: 10 }, { id: 'partial-bottom', y: 199.5 },
    { id: 'below', y: 200 }, { id: 'overscan', y: 310 },
  ]);
  f.root.recordVisibleImpressions();
  assert.deepEqual(sentImpressions(f), [
    { id: 'partial-top', position: 2 }, { id: 'middle', position: 3 },
    { id: 'partial-bottom', position: 4 },
  ]);
});

test('visible geometry handles spacing gaps, variable rows, and uninstantiated delegates', () => {
  const f = impressionsFixture([
    { id: 'top-gap', y: -120, height: 100 }, null,
    { id: 'short', y: 12, height: 40 },
    { id: 'tall', y: 65, height: 150 },
    { id: 'bottom-gap', y: 230, height: 100 },
  ], 225);
  f.root.recordVisibleImpressions();
  assert.deepEqual(sentImpressions(f), [{ id: 'short', position: 3 }, { id: 'tall', position: 4 }]);
});

test('hidden, collapsed, dismissed, transparent, and horizontally clipped cards are not exposed', () => {
  const f = impressionsFixture([
    { id: 'hidden', y: 0, visible: false },
    { id: 'transparent', y: 0, opacity: 0 },
    { id: 'collapsed', y: 0, height: 0 },
    { id: 'dismissing', y: 0, leavingFeed: true },
    { id: 'right', x: 300, y: 0 },
    { id: 'left', x: -300, y: 0 },
    { id: 'visible', y: 0 },
  ]);
  f.root.recordVisibleImpressions();
  assert.deepEqual(sentImpressions(f), [{ id: 'visible', position: 7 }]);
});

test('hidden, minimized, unfocused, closed, and non-feed surfaces do not submit impressions', () => {
  const changes = [
    f => { f.root.opened = false; },
    f => { f.context.window.visible = false; },
    f => { f.context.windowContent.Window.active = false; },
    f => { f.context.windowContent.Window.visibility = f.context.Window.Minimized; },
    f => { f.context.windowContent.Window.visibility = f.context.Window.Hidden; },
    f => { f.root.viewMode = 'search'; },
    f => { f.context.headlineList.visible = false; },
    f => { f.context.headlineList.height = 0; },
    f => { f.context.headlineList.width = 0; },
  ];
  for (const change of changes) {
    const f = impressionsFixture([{ id: 'a', y: 0 }]);
    change(f);
    f.root.recordVisibleImpressions();
    assert.equal(f.processes.impressionProc.running, false);
  }
});

test('pending impression writes resample the current viewport instead of replaying stale rows', () => {
  const f = impressionsFixture([{ id: 'a', y: 0 }, { id: 'b', y: 220 }]);
  f.root.recordVisibleImpressions();
  assert.deepEqual(sentImpressions(f), [{ id: 'a', position: 1 }]);
  f.context.headlineList.rows[0].y = -220;
  f.context.headlineList.rows[1].y = 0;
  f.root.recordVisibleImpressions();
  assert.equal(f.root.pendingImpressions, true);
  f.processes.impressionProc.complete({ ok: true });
  f.context.impressionTimer.trigger();
  assert.deepEqual(sentImpressions(f), [{ id: 'b', position: 2 }]);
});

function feedProbeFixture() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'FeedProbe.qml'), 'utf8');
  const later = [];
  const probe = { backendPath: '/fixture/backend', feedUrl: ' https://example.test/feed?a=1&b=2 ',
    revision: 0, requestRevision: -1, responseReceived: false, result: {} };
  const context = vm.createContext({ probe, checkProc: { running: false, command: [] },
    checkOutput: { text: '' }, Qt: { callLater(fn) { later.push(fn); } } });
  Object.defineProperty(probe, 'checking', { get() { return context.checkProc.running; } });
  for (const key of [...Object.keys(probe), 'checking'])
    Object.defineProperty(context, key, { get() { return probe[key]; }, set(value) { probe[key] = value; } });
  Object.defineProperty(context, 'running', { get() { return context.checkProc.running; } });
  for (const match of source.matchAll(/^  (function (\w+)\([^\n]*\) \{[\s\S]*?^  \})/gm))
    probe[match[2]] = vm.runInContext(`(${match[1]})`, context);
  const exited = source.match(/onExited: (function\([^\n]*\) \{[\s\S]*?^    \})/m)[1];
  const changed = source.match(/onRunningChanged: (\{[\s\S]*?^    \})/m)[1];
  return { probe, context,
    stop() { context.checkProc.running = false; vm.runInContext(`(function() ${changed})`, context)(); },
    exit(payload, code = 0, status = 0) {
      context.checkOutput.text = JSON.stringify(payload);
      vm.runInContext(`(${exited})`, context)(code, status);
      this.stop();
    },
    flush() { while (later.length) later.shift()(); },
  };
}

test('feed probe uses one URL argument and prevents overlapping requests', () => {
  const f = feedProbeFixture();
  f.probe.checkFeed();
  assert.deepEqual(plain(f.context.checkProc.command), ['/fixture/backend', 'sources', '--test', 'https://example.test/feed?a=1&b=2']);
  const revision = f.probe.requestRevision;
  f.probe.checkFeed();
  assert.equal(f.probe.requestRevision, revision);
});

test('feed probe discards stale replies even after editing back to the original URL', () => {
  const f = feedProbeFixture();
  f.probe.checkFeed();
  f.probe.invalidate();
  f.probe.invalidate();
  f.exit({ ok: true, title: 'Outdated feed' });
  f.flush();
  assert.deepEqual(plain(f.probe.result), {});
  f.probe.checkFeed();
  f.exit({ ok: true, title: 'Current feed' });
  f.flush();
  assert.equal(f.probe.result.title, 'Current feed');
});

test('failed feed probe launch reports an error even when the collector retains old output', () => {
  const f = feedProbeFixture();
  f.probe.checkFeed();
  f.exit({ ok: true, title: 'Previous success' });
  f.flush();
  f.probe.checkFeed();
  f.stop(); // Failed launch sends no exit event and retains collector text.
  f.flush();
  assert.equal(f.probe.result.ok, false);
  assert.match(f.probe.result.error, /Could not start/);
});

test('feed probe rejects crash-success payloads and malformed results, then permits retry', () => {
  const f = feedProbeFixture();
  for (const payload of [{ ok: true }, null, 'broken']) {
    f.probe.checkFeed();
    f.exit(payload, 1);
    f.flush();
    assert.equal(f.probe.result.ok, false);
    assert.ok(f.probe.result.error);
  }
  f.probe.checkFeed();
  f.exit({ ok: true, latest: null });
  f.flush();
  assert.equal(f.probe.result.ok, true);
});

function editionFixture() {
  const f = eventFixture();
  f.root.viewMode = 'edition';
  f.root.editionData = { id: 'edition-one', total: 2, completed: 0, remaining: 2,
    articles: [{ id: 'a', title: 'Story A', edition_status: 'pending' },
      { id: 'b', title: 'Story B', edition_status: 'pending' }] };
  f.root.interests = 'science';
  f.root.loadFeed = () => {};
  return f;
}

test('edition opens only after saved cursor acknowledgement; Back pauses even with mark-read enabled', () => {
  const f = editionFixture();
  f.root.openEditionArticle(f.root.editionData.articles[0]);
  assert.equal(f.root.viewMode, 'edition');
  assert.deepEqual(plain(f.processes.editionProc.command),
    ['/test/chuchua-news', 'edition', '--id', 'edition-one', '--open', 'a']);
  f.processes.editionProc.complete({ ok: true, edition: f.root.editionData });
  assert.equal(f.root.viewMode, 'result');
  assert.equal(f.root.returnViewMode, 'edition');
  f.root.navigateBack();
  f.flush();
  assert.equal(f.root.viewMode, 'edition');
  assert.equal(f.processes.readMutationProc.running, false);
  assert.equal(f.root.editionData.completed, 0);
});

test('Done acknowledges progress before advancing and the final story returns to the finish page', () => {
  const f = editionFixture();
  f.root.showArticle(f.root.editionData.articles[0]);
  f.root.activateReadAction(f.root.activeArticle);
  assert.equal(f.root.activeArticle.id, 'a');
  const progressed = plain(f.root.editionData);
  progressed.articles[0].edition_status = 'done';
  progressed.completed = 1; progressed.remaining = 1;
  f.processes.editionProc.complete({ ok: true, edition: progressed });
  assert.equal(f.root.activeArticle.id, 'b');
  f.root.completeEditionStory('skip');
  progressed.articles[1].edition_status = 'skipped';
  progressed.completed = 2; progressed.remaining = 0;
  f.processes.editionProc.complete({ ok: true, edition: progressed });
  assert.equal(f.root.viewMode, 'edition');
  assert.equal(f.root.editionData.remaining, 0);
  assert.equal(f.processes.readMutationProc.running, false);
});

test('edition write errors keep the current story and can be retried without overlapping commands', () => {
  const f = editionFixture();
  f.root.showArticle(f.root.editionData.articles[0]);
  f.root.completeEditionStory('done');
  f.root.completeEditionStory('skip');
  assert.equal(f.launches.filter(x => x.process === 'editionProc').length, 1);
  f.processes.editionProc.complete({ ok: false, error: 'Storage unavailable' }, 1);
  assert.equal(f.root.activeArticle.id, 'a');
  assert.equal(f.root.editionData.completed, 0);
  assert.equal(f.root.editionError, 'Storage unavailable');
  f.root.completeEditionStory('done');
  assert.equal(f.processes.editionProc.running, true);
});

test('late edition acknowledgements never drag the reader away from another page', () => {
  for (const action of ['open', 'done']) {
    const f = editionFixture();
    if (action === 'open') f.root.openEditionArticle(f.root.editionData.articles[0]);
    else { f.root.showArticle(f.root.editionData.articles[0]); f.root.completeEditionStory('done'); }
    f.root.viewMode = 'profile';
    f.processes.editionProc.complete({ ok: true, edition: f.root.editionData });
    assert.equal(f.root.viewMode, 'profile');
  }
});

test('opening Coverage from an edition returns to its same article and pause destination', () => {
  const f = editionFixture();
  f.root.showArticle(f.root.editionData.articles[0]);
  f.root.showEventDesk();
  assert.equal(f.root.eventOrigin.context, 'edition');
  f.root.navigateBack();
  assert.equal(f.root.viewMode, 'result');
  assert.equal(f.root.returnViewMode, 'edition');
  f.root.navigateBack();
  assert.equal(f.root.viewMode, 'edition');
});

test('failed edition starts and crash-success replies leave progress intact and permit retry', () => {
  const f = editionFixture();
  f.root.showArticle(f.root.editionData.articles[0]);
  f.root.completeEditionStory('done');
  f.context.editionStdout.text = JSON.stringify({ ok: true, edition: { ...f.root.editionData, remaining: 0 } });
  f.processes.editionProc.running = false; // no exit signal on a failed launch
  f.flush();
  assert.equal(f.root.editionRequestActive, false);
  assert.equal(f.root.editionData.remaining, 2);
  assert.match(f.root.editionError, /retry/i);
  f.root.completeEditionStory('done');
  f.processes.editionProc.complete({ ok: true, edition: { ...f.root.editionData, remaining: 0 } }, 0, 1);
  f.flush();
  assert.equal(f.root.editionData.remaining, 2);
  assert.equal(f.root.activeArticle.id, 'a');
});

function hideFixture() {
  const f = fixture();
  Object.assign(f.root, { viewMode: 'feed', opened: true, feedLimit: 3, interests: '',
    articles: [{ id: 'a', cluster_ids: ['a', 'a2'] }, { id: 'b' }, { id: 'c' }],
    searchResults: [], bookmarks: [], historyArticles: [], readArticles: [] });
  Object.defineProperty(f.root, 'visibleArticles', { get() {
    return this.viewMode === 'search' ? this.searchResults : this.articles;
  }});
  Object.defineProperty(f.root, 'selectedArticle', { get() { return this.visibleArticles[this.selectedIndex]; }});
  f.context.headlineList = { originY: 0, forceLayout() {}, contentY: 80, contentHeight: 1000, height: 400, positionViewAtBeginning() {}, positionViewAtIndex() {} };
  f.context.keyCatcher = { forceActiveFocus() {} };
  return f;
}

for (const action of ['read', 'dismiss']) {
  const start = f => action === 'read'
    ? f.root.toggleRead(f.root.articles[0]) : f.root.dismissArticle(f.root.articles[0]);
  const process = f => f.processes[action === 'read' ? 'readMutationProc' : 'dismissProc'];
  test(`${action}: failed process start restores hidden stories and permits retry`, () => {
    for (const animationFinished of [false, true]) {
      const f = hideFixture();
      start(f);
      if (animationFinished) f.context.hideCollapseTimer.trigger();
      process(f).failToStart();
      f.flush();
      assert.deepEqual(plain(f.root.optimisticHiddenIds), {});
      assert.deepEqual(plain(f.root.articles).map(a => a.id), ['a', 'b', 'c']);
      assert.match(f.root.statusText, /could not|failed/i);
      start(f);
      assert.equal(process(f).running, true);
    }
  });
  test(`${action}: unsuccessful exits cannot acknowledge a successful-looking payload`, () => {
    for (const [code, status] of [[1, 0], [0, 1]]) {
      const f = hideFixture(); start(f);
      process(f).complete({ ok: true, article_id: 'a', article_ids: ['a', 'a2'], read: true }, code, status);
      f.flush();
      assert.deepEqual(plain(f.root.optimisticHiddenIds), {});
      assert.deepEqual(plain(f.root.articles).map(a => a.id), ['a', 'b', 'c']);
    }
  });
  test(`${action}: an acknowledged hide finishes before another action can replace its animation`, () => {
    const f = hideFixture(); start(f);
    process(f).complete({ ok: true, article_id: 'a', article_ids: ['a', 'a2'], read: true, counts: {} });
    const before = f.launches.length;
    f.root.toggleRead(f.root.articles[1]);
    assert.equal(f.launches.length, before);
    f.context.hideCollapseTimer.trigger(); f.flush();
    assert.deepEqual(plain(f.root.articles).map(a => a.id), ['b', 'c']);
    assert.equal(f.processes.loadProc.running, true);
    assert.equal(f.root.toggleRead(f.root.articles[0]), true);
  });
}

test('stale pre-hide feed responses cannot resurrect a removed event; refill appends without moving selection', () => {
  const f = hideFixture();
  f.root.loadFeed(true, 'background-refresh');
  f.root.toggleRead(f.root.articles[0]);
  f.processes.readMutationProc.complete({ ok: true, article_id: 'a', article_ids: ['a', 'a2'], read: true, counts: {} });
  f.context.hideCollapseTimer.trigger(); f.flush();
  f.processes.loadProc.complete({ ok: true, articles: [{ id: 'a' }, { id: 'b' }, { id: 'c' }] });
  f.flush();
  assert.deepEqual(plain(f.root.articles).map(a => a.id), ['b', 'c']);
  f.root.selectedIndex = 1;
  f.processes.loadProc.complete({ ok: true, articles: [{ id: 'd' }, { id: 'c' }, { id: 'b' }] });
  f.flush();
  assert.deepEqual(plain(f.root.articles).map(a => a.id), ['b', 'c', 'd']);
  assert.equal(f.root.selectedArticle.id, 'c');
  assert.equal(f.context.headlineList.contentY, 80);
});


test('invalid read replies restore the story rather than strand a pending action', () => {
  for (const payload of [null, [], { ok: true }, { ok: false, error: 'disk is full' }]) {
    const f = hideFixture();
    f.root.toggleRead(f.root.articles[0]);
    f.processes.readMutationProc.complete(payload);
    f.flush();
    assert.deepEqual(plain(f.root.optimisticHiddenIds), {});
    assert.equal(f.root.toggleRead(f.root.articles[0]), true);
  }
});

test('a completed read launch fallback cannot roll back the next save', () => {
  const f = hideFixture();
  f.root.viewMode = 'search';
  f.root.searchResults = f.root.articles.slice();
  f.root.toggleRead(f.root.articles[0]);
  f.processes.readMutationProc.complete({ ok: true, article_id: 'a', read: true, counts: {} });
  f.root.toggleRead(f.root.articles[0]);
  f.flush();
  assert.equal(f.processes.readMutationProc.running, true);
  assert.equal(f.root.readMutationActive, true);
  assert.equal(f.root.optimisticHiddenIds.b, true);
});

test('context/framing save is acknowledged before the toggle changes and permits retry after failure', () => {
  const f = fixture();
  f.root.setupData = { profile: { ai: { context_framing: false } } };
  const original = f.root.setupData;
  f.root.setContextFraming(true);
  assert.deepEqual(f.launches.at(-1).command.slice(-2), ['--context-framing', 'on']);
  assert.equal(f.root.setupData, original);
  f.root.setContextFraming(false);
  assert.equal(f.launches.length, 1);
  f.processes.contextFramingProc.failToStart(); f.flush();
  assert.equal(f.root.contextFramingSaving, false);
  assert.equal(f.root.setupData, original);
  f.root.setContextFraming(true);
  f.processes.contextFramingProc.complete({ ok: true, profile: { ai: { context_framing: true } } }); f.flush();
  assert.equal(f.root.setupData.profile.ai.context_framing, true);
});

test('failed or malformed context preference writes preserve the previous setting', () => {
  for (const [payload, code, status] of [[null, 0, 0], [{ok: true}, 0, 0],
    [{ok: true, profile:{ai:{context_framing:true}}}, 0, 1]]) {
    const f = fixture(); const original = { profile:{ai:{context_framing:false}} };
    f.root.setupData = original; f.root.setContextFraming(true);
    f.processes.contextFramingProc.complete(payload, code, status); f.flush();
    assert.equal(f.root.setupData, original);
    assert.equal(f.root.contextFramingSaving, false);
  }
});

test('context notice follows summary metadata, not a subsequently changed preference', () => {
  const f = fixture();
  f.root.handleAiStreamLine(JSON.stringify({event:'meta',context_framing:true}));
  assert.equal(f.root.resultContextFraming, true);
  f.root.setupData = {profile:{ai:{context_framing:false}}};
  assert.equal(f.root.resultContextFraming, true);
  f.root.resetAiPresentation();
  assert.equal(f.root.resultContextFraming, false);
  f.root.handleAiStreamLine(JSON.stringify({event:'meta',context_framing:false}));
  assert.equal(f.root.resultContextFraming, false);
});

test('article image preference waits for acknowledgment and recovers from failed launch', () => {
  const f = fixture(); const original = {profile:{appearance:{article_images:false}}};
  f.root.setupData = original;
  f.root.setArticleImages(true);
  assert.equal(f.root.setupData, original);
  f.processes.articleImagesProc.failToStart(); f.flush();
  assert.equal(f.root.articleImagesSaving, false);
  assert.equal(f.root.setupData, original);
  f.root.setArticleImages(true);
  f.processes.articleImagesProc.complete({ok:true,profile:{appearance:{article_images:true}}}); f.flush();
  assert.equal(f.root.setupData.profile.appearance.article_images, true);
});

test('invalid or failed article image saves preserve the saved preference', () => {
  for (const [payload,code,status] of [[null,0,0],[{ok:true},0,0],
    [{ok:true,profile:{appearance:{article_images:'true'}}},0,0],
    [{ok:true,profile:{appearance:{article_images:true}}},1,0]]) {
    const f=fixture(); const original={profile:{appearance:{article_images:false}}};
    f.root.setupData=original; f.root.setArticleImages(true);
    f.processes.articleImagesProc.complete(payload,code,status); f.flush();
    assert.equal(f.root.setupData, original); assert.equal(f.root.articleImagesSaving,false);
  }
});

function imageQueueFixture() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'ArticleImageCache.qml'), 'utf8');
  const cache = {active:false,clients:[],paths:{},fetching:'',revision:0,backendPath:'/fixture/backend'};
  const later=[]; const downloader={running:false,command:[]};
  const context=vm.createContext({cache,downloader,Qt:{callLater:f=>later.push(f)},
    pending:{restart(){},stop(){}},deadline:{restart(){},stop(){}}});
  for (const key of Object.keys(cache)) Object.defineProperty(context,key,{get:()=>cache[key],set:value=>{cache[key]=value;},configurable:true});
  for (const match of source.matchAll(/^  (function (\w+)\([^\n]*\) \{[\s\S]*?^  \})/gm))
    context[match[2]]=cache[match[2]]=vm.runInContext(`(${match[1]})`,context);
  // schedule is deliberately a one-line QML method.
  cache.schedule=()=>{};
  return {cache,downloader,flush(){while(later.length)later.shift()();}};
}

test('thumbnail queue fetches only visible clients, serializes requests and remembers failures',()=>{
  const f=imageQueueFixture();
  f.cache.clients=[{articleId:'hidden',wantsImage:false},{articleId:'a',wantsImage:true},{articleId:'b',wantsImage:true}];
  f.cache.pump(); assert.deepEqual(f.downloader.command,[]);
  f.cache.active=true;f.cache.pump();
  assert.deepEqual(plain(f.downloader.command),['/fixture/backend','article-images','--ids-json','["a"]']);
  f.cache.pump();assert.equal(f.cache.fetching,'a');
  f.downloader.running=false;f.cache.finish('file:///cache/a.img');
  f.cache.pump();assert.equal(f.cache.fetching,'b');
  f.downloader.running=false;f.cache.finish('');f.cache.pump();
  assert.equal(f.cache.fetching,'');assert.equal(f.cache.paths.b,'');
  assert.equal(f.cache.paths.hidden,undefined);
});

test('thumbnail queue rechecks visibility and survives a failed process start',()=>{
  const f=imageQueueFixture();f.cache.active=true;
  f.cache.clients=[{articleId:'a',wantsImage:true},{articleId:'b',wantsImage:true}];
  f.cache.pump();f.downloader.running=false;f.flush();
  assert.equal(f.cache.fetching,'');assert.equal(f.cache.paths.a,'');
  f.cache.clients[1].wantsImage=false;f.cache.pump();assert.equal(f.cache.fetching,'');
  f.cache.clients[1].wantsImage=true;f.cache.pump();assert.equal(f.cache.fetching,'b');
  f.flush();assert.equal(f.cache.fetching,'b');
});

function foldingFixture() {
  const f=fixture();f.root.viewMode='result';
  f.context.readingImage={reserved:true};
  f.context.readingImageFrame={y:140,height:240};
  f.context.resultScroll={contentY:0,contentHeight:1800,height:650,cancelFlick(){}};
  f.context.resultColumn={spacing:16,forceLayout(){}};
  return f;
}

test('first Down folds the visible photo without skipping opening text; next Down scrolls',()=>{
  const f=foldingFixture();f.root.scrollReading(70);
  assert.equal(f.root.readingImageFolded,true);assert.equal(f.context.resultScroll.contentY,0);
  f.root.scrollReading(70);assert.equal(f.context.resultScroll.contentY,70);
  f.root.scrollReading(-70);assert.equal(f.root.readingImageFolded,false);
  assert.equal(f.context.resultScroll.contentY,0);
});

test('reader scroll stays ordinary without an image and ignores horizontal or invalid steps',()=>{
  const f=foldingFixture();f.context.readingImage.reserved=false;
  f.root.scrollReading(70);assert.equal(f.context.resultScroll.contentY,70);
  assert.equal(f.root.readingImageFolded,false);
  f.root.scrollReading(0);f.root.scrollReading(NaN);assert.equal(f.context.resultScroll.contentY,70);
  f.root.scrollReading(-1000);assert.equal(f.context.resultScroll.contentY,0);
});

test('folding above the viewport keeps the current prose anchored including the removed gap',()=>{
  const f=foldingFixture();f.context.resultScroll.contentY=700;
  f.root.keepReadingImageAnchor(240,0,140);
  assert.equal(f.context.resultScroll.contentY,444);
  f.root.keepReadingImageAnchor(0,240,140);
  assert.equal(f.context.resultScroll.contentY,700);
  assert.equal(f.root.adjustingReadingImage,false);
  f.context.resultScroll.contentY=0;f.root.keepReadingImageAnchor(240,0,140);
  assert.equal(f.context.resultScroll.contentY,0);
});

test('an offscreen photo folds without consuming the requested reading step',()=>{
  const f=foldingFixture();f.context.resultScroll.contentY=700;
  f.root.scrollReading(70);assert.equal(f.root.readingImageFolded,true);
  assert.equal(f.context.resultScroll.contentY,770);
});

test('reader wheel handler accepts pixel scrolling and wheel notches in the same direction',()=>{
  const match=qml.match(/onWheel: (function\(event\) \{[\s\S]*?^              \})/m);
  assert.ok(match);
  const steps=[];
  const handler=vm.runInNewContext(`(${match[1]})`,{root:{scrollReading:delta=>steps.push(delta)},Style:{space:v=>v}});
  const pixel={pixelDelta:{y:-4},angleDelta:{y:0},accepted:false};handler(pixel);
  const down={pixelDelta:{y:0},angleDelta:{y:-120},accepted:false};handler(down);
  const up={pixelDelta:{y:3},angleDelta:{y:0},accepted:false};handler(up);
  const horizontal={pixelDelta:{y:0},angleDelta:{y:0},accepted:true};handler(horizontal);
  assert.deepEqual(steps,[4,70,-3]);assert.equal(pixel.accepted,true);
  assert.equal(down.accepted,true);assert.equal(up.accepted,true);assert.equal(horizontal.accepted,false);
});

test('AI reading text formats bold and heading lines while preserving paragraphs', () => {
  const f = fixture();
  assert.equal(f.root.formatAiReadingText('**What happened**\n\nA **small change**.\n## Why it matters'),
    '<b>What happened</b><br><br>A <b>small change</b>.<br><br><b>Why it matters</b>');
  assert.equal(f.root.formatAiReadingText('### Context & framing ###\r\nMore detail'),
    '<b>Context &amp; framing</b><br><br>More detail');
});

test('AI reading text cannot introduce images, links or raw HTML into styled output', () => {
  const f = fixture();
  const result = f.root.formatAiReadingText('**<img src="https://example.invalid/track">**\n<a href="file:///tmp/a">open</a> &lt;b&gt;');
  assert.equal(result, '<b>&lt;img src="https://example.invalid/track"&gt;</b><br><br>&lt;a href="file:///tmp/a"&gt;open&lt;/a&gt; &amp;lt;b&amp;gt;');
  assert.deepEqual(result.match(/<[^>]+>/g), ['<b>', '</b>', '<br>', '<br>']);
});

test('incomplete bold output remains readable until the streamed closing marker arrives', () => {
  const f = fixture();
  assert.equal(f.root.formatAiReadingText('**Context'), '**Context');
  assert.equal(f.root.formatAiReadingText('**Context**'), '<b>Context</b>');
  assert.equal(f.root.formatAiReadingText('2 * 3 < 7\n\nNext paragraph'), '2 * 3 &lt; 7<br><br>Next paragraph');
});

test('reading-size save waits for acknowledgment, blocks overlapping appearance writes and permits retry', () => {
  const f = fixture(); f.root.readingSize = 'regular';
  const original = {profile:{appearance:{reading_size:'regular'}}}; f.root.setupData = original;
  f.root.setReadingSize('large');
  assert.deepEqual(f.launches.at(-1).command.slice(-2), ['--reading-size', 'large']);
  assert.equal(f.root.setupData, original);
  f.root.setArticleImages(true); f.root.setReadingSize('extra-large');
  assert.equal(f.launches.length, 1);
  f.processes.readingSizeProc.failToStart(); f.flush();
  assert.equal(f.root.readingSizeSaving, false);
  assert.match(f.root.readingSizeMessage, /try again/i);
  f.root.setReadingSize('large');
  f.processes.readingSizeProc.complete({ok:true,profile:{appearance:{reading_size:'large'}}}); f.flush();
  assert.equal(f.root.setupData.profile.appearance.reading_size, 'large');
  assert.equal(f.root.readingSizeSaving, false);
});

test('reading-size errors and mismatched responses preserve the saved profile', () => {
  for (const [payload,code,status] of [[null,1,0],[{ok:true,profile:{appearance:{reading_size:'extra-large'}}},0,0],[{ok:true,profile:{appearance:{reading_size:'large'}}},0,1]]) {
    const f=fixture(); f.root.readingSize='regular';const original={profile:{appearance:{reading_size:'regular'}}};f.root.setupData=original;
    f.root.setReadingSize('large');f.processes.readingSizeProc.complete(payload,code,status);f.flush();
    assert.equal(f.root.setupData,original);assert.equal(f.root.readingSizeSaving,false);
  }
});

test('readability uses the existing palette and falls back when muted text is too faint', () => {
  const utility=vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(__dirname,'..','Reading.js'),'utf8').replace('.pragma library',''),utility);
  const rgb=hex=>({r:parseInt(hex.slice(0,2),16)/255,g:parseInt(hex.slice(2,4),16)/255,b:parseInt(hex.slice(4,6),16)/255});
  const dark=rgb('1f1f28'),light=rgb('dcd7ba'),faint=rgb('54546d');
  assert.equal(utility.secondaryColor(light,dark,faint),light);
  const pale=rgb('ffffff'),ink=rgb('111111'),gray=rgb('666666');
  assert.equal(utility.secondaryColor(ink,pale,gray),gray);
  assert.ok(utility.contrast(gray,pale)>=4.5);
  assert.equal(utility.sizeScale('regular'),1);assert.ok(utility.sizeScale('extra-large')>utility.sizeScale('large'));
});

test('feed scrolling under a parked pointer cannot steal keyboard selection', () => {
  const f = fixture();
  const r = f.root;
  r.viewMode = 'feed';
  r.visibleArticles = Array.from({length: 20}, (_, i) => ({id: String(i)}));
  f.context.headlineList = {moving: false};
  r.pointAtHeadline(0, 40, 100);
  for (let i = 1; i <= 15; i++) {
    r.moveCursor(1);
    // Different rows pass under the same window position, including fractional
    // coordinate noise from animated scrolling and hover delivery after settling.
    r.pointAtHeadline(Math.max(0, i - 3), 40, 100.2);
    assert.equal(r.selectedIndex, i);
  }
  r.pointAtHeadline(12, 45, 100);
  assert.equal(r.selectedIndex, 12, 'deliberate mouse movement restores hover selection');
  r.pointAtHeadline(13, 45.7, 100);
  r.pointAtHeadline(13, 46.4, 100);
  assert.equal(r.selectedIndex, 13, 'slow pointer movement accumulates past rounding tolerance');
});

test('feed pointer tracking observes motion without selecting during a flick', () => {
  const f = fixture();
  f.root.visibleArticles = Array.from({length: 10}, (_, i) => ({id: String(i)}));
  f.root.selectedIndex = 4;
  f.context.headlineList = {moving: true};
  f.root.pointAtHeadline(7, 20, 80);
  assert.equal(f.root.selectedIndex, 4);
  f.context.headlineList.moving = false;
  f.root.pointAtHeadline(8, 20, 80);
  assert.equal(f.root.selectedIndex, 4, 'flick completion does not look like pointer movement');
  f.root.pointAtHeadline(8, 30, 80);
  assert.equal(f.root.selectedIndex, 8);
});

test('feed navigation advances once per key and stops at either end', () => {
  const f = fixture();
  const r = f.root;
  r.viewMode = 'search';
  r.visibleArticles = [{id:'a'}, {id:'b'}, {id:'c'}];
  r.moveCursor(-1);
  assert.equal(r.selectedIndex, 0);
  for (let i = 0; i < 10; i++) r.moveCursor(1);
  assert.equal(r.selectedIndex, 2);
  r.moveCursor(-1);
  assert.equal(r.selectedIndex, 1);
  r.viewMode = 'result';
  r.moveCursor(1);
  assert.equal(r.selectedIndex, 1);
});

for (const action of ['read', 'dismiss']) {
  test(`${action}: a late manual refresh cannot reorder survivors or prepend replacements`, () => {
    const f = hideFixture();
    f.root.refresh(false);
    if (action === 'read') f.root.toggleRead(f.root.articles[0]);
    else f.root.dismissArticle(f.root.articles[0]);
    f.processes[action === 'read' ? 'readMutationProc' : 'dismissProc'].complete({
      ok:true, article_id:'a', article_ids:['a', 'a2'], read:true, counts:{}
    });
    f.context.hideCollapseTimer.trigger(); f.flush();
    f.root.selectedIndex = 1;
    f.processes.loadProc.complete({ok:true, articles:[{id:'new-first',score:999}, {id:'c'}, {id:'b'}]});
    f.flush();
    assert.deepEqual(plain(f.root.articles).map(a=>a.id), ['b','c','new-first']);
    // The older network refresh returns after the immediate hide refill.
    f.processes.refreshProc.complete({ok:true, inserted:1, sources_attempted:1, sources_skipped:0});
    assert.equal(f.root.activeFeedOrderPreservation, true);
    f.processes.loadProc.complete({ok:true, articles:[{id:'new-second',score:1000}, {id:'new-first'}, {id:'c'}]});
    f.flush();
    assert.deepEqual(plain(f.root.articles).map(a=>a.id), ['b','c','new-first']);
    assert.equal(f.root.selectedArticle.id, 'c');
    assert.equal(f.context.headlineList.contentY, 80);
    // Hide again: even the highest-ranked replacement belongs at the bottom.
    if (action === 'read') f.root.toggleRead(f.root.articles[0]);
    else f.root.dismissArticle(f.root.articles[0]);
    f.processes[action === 'read' ? 'readMutationProc' : 'dismissProc'].complete({
      ok:true, article_id:'b', read:true, counts:{}
    });
    f.context.hideCollapseTimer.trigger(); f.flush();
    f.processes.loadProc.complete({ok:true, articles:[{id:'new-second'}, {id:'new-first'}, {id:'c'}]});
    f.flush();
    assert.deepEqual(plain(f.root.articles).map(a=>a.id), ['c','new-first','new-second']);
  });
}

test('a stale rerank retried during a hide loses permission to shuffle the feed', () => {
  const f = hideFixture();
  f.root.loadFeed(false, 'manual-refresh');
  f.root.dismissArticle(f.root.articles[0]);
  f.processes.loadProc.complete({ok:true, articles:[{id:'new'}, {id:'c'}, {id:'b'}]});
  f.flush();
  assert.equal(f.root.activeFeedOrderPreservation, true);
  f.processes.dismissProc.complete({ok:true, article_id:'a', read:true, counts:{}});
  f.context.hideCollapseTimer.trigger(); f.flush();
  f.processes.loadProc.complete({ok:true, articles:[{id:'new'}, {id:'c'}, {id:'b'}]});
  f.flush();
  f.processes.loadProc.complete({ok:true, articles:[{id:'new'}, {id:'c'}, {id:'b'}]});
  f.flush();
  assert.deepEqual(plain(f.root.articles).map(a=>a.id), ['b','c','new']);
});

test('a newly requested manual refresh can still apply a fresh ranking when no hide intervenes', () => {
  const f = hideFixture();
  f.root.refresh(false);
  f.processes.refreshProc.complete({ok:true, inserted:1, sources_attempted:1, sources_skipped:0});
  assert.equal(f.root.activeFeedOrderPreservation, false);
  f.processes.loadProc.complete({ok:true, articles:[{id:'new'}, {id:'c'}, {id:'b'}]});
  f.flush();
  assert.deepEqual(plain(f.root.articles).map(a=>a.id), ['new','c','b']);
});

test('hide selects the next surviving story, with a previous-story fallback at the end', () => {
  const f = fixture();
  const values = ['a','b','c','d','e'].map(id=>({id}));
  assert.equal(f.root.selectionAfterHide(values, ['c'], 2), 'd');
  assert.equal(f.root.selectionAfterHide(values, ['c','d'], 2), 'e');
  assert.equal(f.root.selectionAfterHide(values, ['e'], 4), 'd');
  assert.equal(f.root.selectionAfterHide(values, ['a','b'], 2), 'c');
  assert.equal(f.root.selectionAfterHide([{id:'a'}], ['a'], 0), '');
});

test('hide and refill restore the native cursor and viewport after model resets', () => {
  const f = hideFixture();
  f.root.selectedIndex = 1;
  f.context.headlineList.forceLayout = function() {
    // Native reproduction: rebuilding a JS model resets the view independently
    // of root.selectedIndex, which may legitimately remain unchanged.
    this.currentIndex = 0;
    this.contentY = 0;
  };
  f.root.dismissArticle(f.root.selectedArticle);
  f.processes.dismissProc.complete({ok:true, article_id:'b', read:true, counts:{}});
  f.context.hideCollapseTimer.trigger(); f.flush();
  assert.equal(f.root.selectedArticle.id, 'c');
  assert.equal(f.context.headlineList.currentIndex, 1);
  assert.equal(f.context.headlineList.contentY, 80);
  f.processes.loadProc.complete({ok:true, articles:[{id:'replacement'},{id:'c'},{id:'a'}]});
  f.flush();
  assert.equal(f.root.selectedArticle.id, 'c');
  assert.equal(f.context.headlineList.currentIndex, 1);
  assert.equal(f.context.headlineList.contentY, 80);
  assert.equal(f.root.feedLayoutChanging, false);
  f.root.moveCursor(1);
  assert.equal(f.root.selectedArticle.id, 'replacement');
});

test('failed hide restores the original story and pre-hide scroll position', () => {
  const f = hideFixture();
  f.root.selectedIndex = 1;
  f.root.dismissArticle(f.root.selectedArticle);
  f.context.hideCollapseTimer.trigger();
  f.context.headlineList.contentY = 20;
  f.processes.dismissProc.complete({ok:false, error:'write failed'}, 1);
  f.flush();
  assert.equal(f.root.selectedArticle.id, 'b');
  assert.equal(f.context.headlineList.currentIndex, 1);
  assert.equal(f.context.headlineList.contentY, 80);
  assert.equal(f.root.feedLayoutChanging, false);
});
