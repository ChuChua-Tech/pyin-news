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
    console: { log() {} },
    Qt: { callLater(callback) { later.push(callback); } },
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
