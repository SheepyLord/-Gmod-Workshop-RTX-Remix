'use strict';
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const labels = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const calls = [];
let tick;
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.style = {}; this.textContent = ''; }
  appendChild(child) { this.children.push(child); child.parentNode = this; return child; }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); child.parentNode = null; }
  setAttribute(key, value) { this[key] = value; }
  focus() { this.focused = true; }
  get firstChild() { return this.children[0]; }
  set innerHTML(_) { throw Error('Raw HTML must never be used'); }
}
function all(root) { return [root, ...root.children.flatMap(all)]; }
function makeDocument() {
  const body = new Element('body');
  const head = new Element('head');
  return {body, head, readyState: 'complete', createElement: tag => new Element(tag),
    getElementById: id => all(body).find(item => item.id === id)};
}
const document = makeDocument();
const body = document.body;
const data = {os: 'Windows 11 x64', cpu: '<img src=x onerror=unexpected()>', threads: 24,
  memory: 64 * 1073741824, graphics: [{name: 'GPU', memory: 16 * 1073741824}],
  loader: {version: '0.8.1', sha256: 'a'.repeat(64)},
  packages: [{id: 'gmod-rtx-remix', version: '1.2.3+build', sha256: 'b'.repeat(64)},
    ...Array.from({length: 4}, (_, i) => ({id: 'content-' + i, version: '9.8.7', sha256: 'c'.repeat(64)}))]};
const window = {NativeLoaderDiagnostics: data, NativeLoaderDiagnosticLabels: labels,
  location: {hash: '#/'}, setInterval: fn => { tick = fn; }, lua: {Run: (...args) => calls.push(args)}};
const gScope = {Version: '2026.10.20', Branch: 'x86-64', Language: 'en', InGame: false};
const context = {window, document, gScope};
vm.runInNewContext(source, context);
const panel = document.getElementById('native-loader-diagnostics');
assert(panel);
assert.equal(panel.style.display, 'block');
assert.equal(calls.length, 0);
assert(all(panel).some(item => item.textContent === data.cpu + ' · 24 ' + labels.en.threads));
assert(all(panel).some(item => item.title === 'SHA-256: ' + 'a'.repeat(64)));
const button = all(panel).find(item => item.tag === 'button');
button.onclick();
assert.equal(calls[0][0], 'SetClipboardText( %s )');
assert(calls[0][1].includes('a'.repeat(64)) && calls[0][1].includes('b'.repeat(64)));
assert(calls[0][1].includes('2026.10.20'));
assert(calls[0][1].includes(labels.en.content_addons + ': ' + labels.en.content_enabled.replace('{count}', '4')));
assert(!calls[0][1].includes('content-') && !calls[0][1].includes('9.8.7') && !calls[0][1].includes('c'.repeat(64)));
assert(all(panel).some(item => item.textContent === labels.en.content_enabled.replace('{count}', '4')));
for (const [code, catalog] of Object.entries(labels)) {
  for (const count of [0, 1, 4]) {
    const doc = makeDocument(), copied = [];
    const packages = [data.packages[0], ...data.packages.slice(1, 1 + count)];
    const win = {NativeLoaderDiagnostics: {...data, packages}, NativeLoaderDiagnosticLabels: labels,
      location: {hash: '#/'}, setInterval() {}, lua: {Run: (...args) => copied.push(args)}};
    vm.runInNewContext(source, {window: win, document: doc, gScope: {...gScope, Language: code}});
    const nodes = all(doc.body);
    assert.equal(nodes.filter(item => item.textContent === catalog.content_addons + ': ').length, 1);
    assert(nodes.some(item => item.textContent === catalog.content_enabled.replace('{count}', String(count))));
    nodes.find(item => item.tag === 'button').onclick();
    assert(copied[0][1].includes(catalog.content_addons + ': ' + catalog.content_enabled.replace('{count}', String(count))));
    assert(copied[0][1].includes('b'.repeat(64)) && !copied[0][1].includes('c'.repeat(64)));
    assert(!copied[0][1].includes('content-'));
  }
}
const link = all(panel).find(item => item.tag === 'a');
link.onclick({preventDefault() {}});
assert.equal(calls[1][0], 'gui.OpenURL( %s )');
assert.equal(calls[1][1], 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix');
gScope.InGame = true; tick(); assert.equal(panel.style.display, 'none');
gScope.InGame = false; window.location.hash = '#/addons/'; tick(); assert.equal(panel.style.display, 'none');
window.location.hash = '#/'; gScope.Language = 'zh-cn'; tick();
assert.equal(panel.style.display, 'block');
assert(all(panel).some(item => item.textContent === labels['zh-CN'].heading));
gScope.Language = 'fr'; gScope.Version = 'new build'; tick();
assert(all(panel).some(item => item.textContent === labels.fr.heading));
assert(all(panel).some(item => item.textContent === 'new build · x86-64'));
const count = body.children.length;
vm.runInNewContext(source, context); assert.equal(body.children.length, count);
assert.equal(calls.length, 2, 'no bootstrap request without client_bootstrap');

// The row describes an effective tier layer and needs an adapter description.
for (const [adapter, layer, visible] of [['GPU', 'native-loader/remix/tier.conf', true],
                                      ['', 'native-loader/remix/tier.conf', false], ['GPU', '', false]]) {
  for (const code of Object.keys(labels)) {
    const doc = makeDocument();
    const tier = {tier: 'low', source: 'config', adapter, layer};
    const win = {NativeLoaderDiagnostics: {...data, performance_tier: tier}, NativeLoaderDiagnosticLabels: labels,
      location: {hash: '#/'}, setInterval() {}};
    vm.runInNewContext(source, {window: win, document: doc, gScope: {...gScope, Language: code}});
    const row = all(doc.body).find(item => item.textContent === labels[code].performance_tier + ': ');
    assert.equal(Boolean(row), visible, `tier row adapter=${adapter} layer=${layer} language=${code}`);
    if (visible) assert(all(doc.body).some(item => item.textContent === labels[code].tier_low + ' · ' + labels[code].tier_config));
  }
}

// client_bootstrap: true. The multiplayer bootstrap is requested once, with the overlay or without it.
function bootstrapCase(withDiagnostics, bridgeAvailable) {
  const requests = [];
  const timeouts = [];
  const doc = makeDocument();
  const bridge = {Run: (...args) => requests.push(args)};
  const win = {NativeLoaderClientBootstrap: true, location: {hash: '#/'},
    setInterval: () => {}, setTimeout: (fn, delay) => { assert.equal(delay, 500); timeouts.push(fn); }};
  if (withDiagnostics) { win.NativeLoaderDiagnostics = data; win.NativeLoaderDiagnosticLabels = labels; }
  if (bridgeAvailable) win.lua = bridge;
  const scope = {Version: '2026.10.20', Branch: 'x86-64', Language: 'en', InGame: false};
  const ctx = {window: win, document: doc, gScope: scope};
  vm.runInNewContext(source, ctx);
  return {requests, timeouts, doc, bridge, win, ctx};
}
const both = bootstrapCase(true, true);
assert.deepEqual(both.requests, [['require( "nlrtxclient" )']]);
assert(both.doc.getElementById('native-loader-diagnostics'), 'the overlay still installs beside the trigger');
vm.runInNewContext(source, both.ctx);
assert.equal(both.requests.length, 1, 'requested once per menu page');
const alone = bootstrapCase(false, true);
assert.deepEqual(alone.requests, [['require( "nlrtxclient" )']], 'the trigger needs no diagnostics data');
assert.equal(alone.doc.getElementById('native-loader-diagnostics'), undefined, 'no overlay without its data');
const later = bootstrapCase(false, false);
assert.equal(later.requests.length, 0);
assert.equal(later.timeouts.length, 1, 'waits for the Lua bridge');
later.win.lua = later.bridge;
later.timeouts.shift()();
assert.deepEqual(later.requests, [['require( "nlrtxclient" )']]);
assert.equal(later.timeouts.length, 0, 'no further polling once requested');
const never = bootstrapCase(false, false);
let attempts = 0;
while (never.timeouts.length) { never.timeouts.shift()(); attempts++; assert(attempts < 1000, 'polling never ends'); }
assert(attempts > 0 && attempts < 240, 'bounded polling without a Lua bridge');
assert.equal(never.requests.length, 0);

// Current-process notices use bounded local reads, never the startup snapshot from another run.
function noticeCase(code = 'en', inGame = false, hash = '#/', clock) {
  const requests = [], doc = makeDocument();
  let update;
  const diagnostic = {...data, process_id: 123, session_token: '123-456'};
  const win = {NativeLoaderDiagnostics: diagnostic, NativeLoaderDiagnosticLabels: labels,
    NativeLoaderReadNotices: 'read-local-notices', location: {hash},
    setInterval: fn => { update = fn; }, lua: {Run: (...args) => requests.push(args)}};
  const scope = {Language: code, InGame: inGame};
  const ctx = {window: win, document: doc, gScope: scope};
  if (clock) ctx.Date = clock;
  vm.runInNewContext(source, ctx);
  const panel = doc.getElementById('native-loader-diagnostics');
  return {requests, win, scope, panel, tick: () => update(),
    text: () => all(panel).map(item => item.textContent),
    receive: value => win.NativeLoaderReceiveNotices(value)};
}
function notice(reason = 'device_lost', warning = false) {
  return {session_token: '123-456', warning_allowed: true,
    previous_session: {reason, folder: 'native-loader/logs/sessions/<literal>-failure'},
    commit: {session_token: '123-456', time_utc: new Date().toISOString(),
      commit_total: (warning ? 50 : 16) * 1073741824, commit_limit: 64 * 1073741824, warning}};
}
for (const [code, catalog] of Object.entries(labels)) {
  for (const reason of ['device_lost', 'cs_exception', 'allocation_failed', 'out_of_memory', 'likely_out_of_memory', 'crash']) {
    const view = noticeCase(code);
    assert.equal(view.requests.length, 1);
    assert.deepEqual(view.requests[0], ['read-local-notices', '123-456', 123]);
    view.receive(notice(reason));
    const expected = catalog.previous_session + ': ' + catalog['failure_' + reason] + ' · native-loader/logs/sessions/<literal>-failure';
    assert(view.text().includes(expected), code + '/' + reason + ' is localized and text-only');
    all(view.panel).find(item => item.tag === 'button').onclick();
    assert(view.requests.find(item => item[0] === 'SetClipboardText( %s )')[1].includes(expected));
  }
  const view = noticeCase(code);
  view.receive(notice('out_of_memory', true));
  assert(view.text().some(text => text.includes(catalog.ram_warning)), code + ' includes meaning and both fixes');
}
for (const reason of ['clean', 'unknown', 'future_reason']) {
  const view = noticeCase(); view.receive(notice(reason));
  assert(!view.text().some(text => text.startsWith(labels.en.previous_session + ':')));
}
const unsaved = noticeCase(); const noFolder = notice(); noFolder.previous_session.folder = '';
unsaved.receive(noFolder);
assert(unsaved.text().some(text => text.includes(labels.en.evidence_unavailable)));

const warning = noticeCase(); warning.receive(notice('out_of_memory', true));
const acknowledgements = () => warning.requests.filter(item => item[0] === '_G.NativeLoaderRAMWarningSession = %s');
assert.equal(acknowledgements().length, 1);
warning.receive(notice('out_of_memory', true)); warning.tick();
assert.equal(acknowledgements().length, 1, 'one warning acknowledgement per start');
assert.equal(warning.text().filter(text => text.startsWith(labels.en.ram_warning_heading + ':')).length, 1);
warning.scope.Language = 'fr'; warning.tick();
assert(warning.text().some(text => text.includes(labels.fr.ram_warning)), 'visible warning follows language changes');
warning.win.location.hash = '#/addons/'; warning.tick();
warning.win.location.hash = '#/'; warning.tick();
warning.receive(notice('out_of_memory', true));
assert(!warning.text().some(text => text.startsWith(labels.fr.ram_warning_heading + ':')), 'no repeat after leaving home');
const reloaded = noticeCase(); const alreadyShown = notice('out_of_memory', true); alreadyShown.warning_allowed = false;
reloaded.receive(alreadyShown);
assert(!reloaded.text().some(text => text.includes(labels.en.ram_warning)), 'Lua realm remembers a warning across page reloads');

const duringMap = noticeCase('en', true);
assert.equal(duringMap.requests.length, 0, 'no automatic diagnostics reads in a map');
duringMap.receive(notice('crash', true)); duringMap.scope.InGame = false; duringMap.tick();
duringMap.receive(notice('crash', true));
assert(!duringMap.text().some(text => text.includes(labels.en.ram_warning)), 'RAM warning only before the first map');
const hidden = noticeCase('en', false, '#/addons/'); hidden.receive(notice('crash', true));
assert.equal(hidden.requests.length, 0, 'hidden notice is not consumed');
hidden.win.location.hash = '#/'; hidden.tick(); hidden.receive(notice('crash', true));
assert(hidden.text().some(text => text.includes(labels.en.ram_warning)));

for (const mutate of [
  value => { value.session_token = 'old-process'; },
  value => { value.commit.session_token = 'old-process'; },
  value => { value.commit.time_utc = new Date(Date.now() - 31000).toISOString(); },
  value => { value.commit.time_utc = new Date(Date.now() + 10000).toISOString(); },
  value => { value.commit.commit_limit = 0; },
  value => { value.commit.commit_total = 'invalid'; },
  value => { value.commit.commit_limit = Infinity; },
  value => { value.commit = null; }
]) {
  const view = noticeCase(), value = notice('crash', true); mutate(value); view.receive(value);
  assert(!view.text().some(text => text.includes(labels.en.ram_warning)), 'invalid/stale snapshots do not warn');
  assert(!view.requests.some(item => item[0] === '_G.NativeLoaderRAMWarningSession = %s'));
}
let now = Date.now();
const bounded = noticeCase('en', false, '#/', {now: () => now, parse: Date.parse});
for (let i = 0; i < 200; i++) { now += 1000; bounded.tick(); }
assert.equal(bounded.requests.length, 120, 'bounded retries if local status/snapshot never become readable');
console.log('PASS menu diagnostics');

// The real RTX modal and Angular route listener, including navigation by code and a pause menu.
function menuCase(options = {}) {
  const doc = makeDocument(), requests = [], intervals = [], handlers = {}, ready = [];
  if (options.loading) { doc.readyState = 'loading'; doc.addEventListener = (_, fn) => ready.push(fn); }
  const scope = {Language: options.language || 'en', InGame: !!options.inGame};
  let route = options.route || '/', proposed = route;
  const loc = {path: () => decodeURIComponent(proposed.split('?')[0]),
    url(value) {
      if (value === undefined) return proposed;
      proposed = value;
      let cancelled = false;
      if (handlers.$locationChangeStart) handlers.$locationChangeStart({preventDefault() { cancelled = true; }});
      if (!cancelled) route = value;
      proposed = route;
    }};
  const r = {$on(name, fn) { handlers[name] = fn; }, $evalAsync: options.noDigest ? undefined : function (fn) { fn(); }};
  const released = options.release === undefined ? '0.16.0' : options.release;
  const diagnostic = {...data, rtx_active: options.active !== false, session_token: 'start-123',
    loader: {...data.loader, version: options.current || '0.15.0'},
    released_loader: typeof released === 'string' ? {version: released,
      url: 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v' + released} : released};
  const win = {NativeLoaderDiagnostics: diagnostic, NativeLoaderDiagnosticLabels: labels,
    NativeLoaderMenuChoices: 'choices-reader', location: {hash: '#/'},
    setInterval(fn) { intervals.push(fn); },
    lua: options.bridge === false ? null : {Run(...args) {
      requests.push(args);
      if (options.brokenBridge) throw Error('bridge changed');
    }}};
  const ctx = {window: win, document: doc, gScope: scope, App: {run(parts) { parts[parts.length - 1](r, loc); }}};
  vm.runInNewContext(source, ctx);
  const view = {doc, win, requests, scope, loc, ctx, tick: () => intervals.forEach(fn => fn()), route: () => route,
    ready: () => ready.forEach(fn => fn()), hasRouteHandler: () => !!handlers.$locationChangeStart,
    receive(value = {}) { win.NativeLoaderReceiveMenuState({session_token: 'start-123', ...value}); },
    modal: () => doc.getElementById('native-loader-modal'),
    click(key) {
      const caption = labels[scope.Language][key];
      const btn = all(view.modal()).find(n => n.tag === 'button' && n.textContent === caption);
      assert(btn, key); btn.onclick();
    }};
  return view;
}
for (const code of Object.keys(labels)) {
  const view = menuCase({language: code});
  view.receive();
  assert(view.modal());
  assert(all(view.modal()).some(n => n.textContent === labels[code].update_title));
  assert(all(view.modal()).some(n => n.textContent.includes('0.15.0') && n.textContent.includes('0.16.0')));
  view.click('update_open');
  assert.equal(view.modal(), undefined);
  assert(view.requests.some(call => call[0] === 'gui.OpenURL( %s )' && call[1].endsWith('/v0.16.0')));
}
for (const [running, latest, expected] of [
  ['0.15.0', '0.15.0', false], ['0.16.0', '0.15.0', false], ['0.15.0', '0.16.0', true],
  ['1.0.0-rc.2', '1.0.0-rc.10', true], ['1.0.0-rc.10', '1.0.0-rc.2', false],
  ['1.0.0-rc.1', '1.0.0', true], ['1.0.0', '1.0.0-rc.1', false],
  ['1.0.0-alpha', '1.0.0-alpha.1', true], ['1.0.0-9', '1.0.0-alpha', true],
  ['1.0.0-a', '1.0.0-b', true], ['1.0.0', '01.1.0', false], ['1.0.0', '1.0.1-01', false],
  ['1.0.0', '1.0.1+build', false], ['1.0.0', '1.0.1-a..b', false],
  ['1.0.0', '18446744073709551616.0.0', false], ['1.0.0', '1.0.1\n', false]
]) {
  const view = menuCase({current: running, release: latest}); view.receive();
  assert.equal(!!view.modal(), expected, running + ' versus ' + latest);
}
for (const release of [{version: '9.0.0', url: 'https://evil.test/'}, {version: '9.0.0', url: 'javascript:bad()'},
  {version: '9.0.0', url: 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v8.0.0'},
  {version: '9.0.0', url: 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v9.0.0', extra: true}, null]) {
  const view = menuCase({release}); view.receive(); assert(!view.modal());
}
const laterUpdate = menuCase(); laterUpdate.receive(); laterUpdate.click('update_later'); laterUpdate.tick();
assert(!laterUpdate.modal(), 'Later is for this start');
assert(!laterUpdate.requests.some(call => call[0].includes('file.Write')), 'Later writes no preference');
const ignoredUpdate = menuCase(); ignoredUpdate.receive();
all(ignoredUpdate.modal()).find(n => n.tag === 'button' && n.textContent.includes('0.16.0')).onclick();
assert(ignoredUpdate.requests.some(call => call[0].includes('loader-update-ignored.txt') && call[1] === '0.16.0'));
for (const [remembered, hidden] of [['0.16.0', true], ['0.15.0', false]]) {
  const view = menuCase(); view.receive({ignored_version: remembered}); assert.equal(!view.modal(), hidden);
}
const reloadedMenu = menuCase(); reloadedMenu.receive({update_seen: true}); assert(!reloadedMenu.modal());
const wrongToken = menuCase(); wrongToken.receive({session_token: 'another-start'}); assert(!wrongToken.modal());
const away = menuCase({route: '/addons/'}); away.receive(); assert(!away.modal());
away.loc.url('/'); away.tick(); assert(away.modal(), 'wait for home before consuming reminder');
const pause = menuCase({inGame: true}); pause.receive(); assert(!pause.modal(), 'no menu update reminder during gameplay');
const loading = menuCase({loading: true, release: null});
assert(loading.hasRouteHandler(), 'register App.run before DOM-ready Angular bootstrap');
loading.ready(); loading.receive(); loading.loc.url('/servers/'); assert(loading.modal());
for (const inGame of [false, true]) {
  for (const target of ['/servers/', '/servers', '/servers/history?sort=ping', '/%73ervers/']) {
    const view = menuCase({inGame, release: null}); view.receive();
    view.loc.url(target); assert(view.modal(), target); assert.equal(view.route(), '/');
    view.click('multiplayer_back'); assert.equal(view.route(), '/'); assert(!view.modal());
    view.loc.url(target); view.click('multiplayer_continue'); assert.equal(view.route(), target); assert(!view.modal());
    view.loc.url('/'); view.loc.url(target); assert(view.modal(), 'without checkbox, warn on next visit');
  }
}
for (const code of Object.keys(labels)) {
  const view = menuCase({language: code, release: null}); view.receive(); view.loc.url('/servers/');
  for (const key of ['multiplayer_title', 'multiplayer_rules', 'multiplayer_performance', 'multiplayer_risk', 'multiplayer_remember'])
    assert(all(view.modal()).some(n => n.textContent === labels[code][key]));
}
const rememberServer = menuCase({release: null}); rememberServer.receive(); rememberServer.loc.url('/servers/');
all(rememberServer.modal()).find(n => n.tag === 'input').checked = true;
rememberServer.click('multiplayer_continue');
assert(rememberServer.requests.some(call => call[0].includes('multiplayer-warning-dismissed.txt')));
rememberServer.loc.url('/'); rememberServer.loc.url('/servers/'); assert(!rememberServer.modal());
const restarted = menuCase({release: null}); restarted.receive({multiplayer_dismissed: true});
restarted.loc.url('/servers/'); assert(!restarted.modal()); assert.equal(restarted.route(), '/servers/');
const backNeverSaves = menuCase({release: null}); backNeverSaves.receive(); backNeverSaves.loc.url('/servers/');
all(backNeverSaves.modal()).find(n => n.tag === 'input').checked = true;
backNeverSaves.click('multiplayer_back');
assert(!backNeverSaves.requests.some(call => call[0].includes('file.Write')));
for (const options of [{bridge: false}, {brokenBridge: true}, {active: false}]) {
  const view = menuCase({release: null, ...options}); view.loc.url('/servers/');
  assert.equal(view.route(), '/servers/', 'fail open or RTX off: ' + JSON.stringify(options)); assert(!view.modal());
}
const brokenDom = menuCase({release: null}); brokenDom.receive();
brokenDom.doc.createElement = () => { throw Error('menu DOM changed'); };
brokenDom.loc.url('/servers/'); assert.equal(brokenDom.route(), '/servers/'); assert(!brokenDom.modal());
const earlyClick = menuCase({release: null}); earlyClick.loc.url('/servers/');
all(earlyClick.modal()).find(n => n.tag === 'input').checked = true;
earlyClick.click('multiplayer_continue'); assert.equal(earlyClick.route(), '/servers/');
const lateState = menuCase({release: null}); lateState.loc.url('/servers/'); lateState.receive({multiplayer_dismissed: true});
assert(!lateState.modal()); assert.equal(lateState.route(), '/servers/');
for (const noDigest of [false, true]) {
  const view = menuCase({release: null, noDigest}); view.receive(); view.loc.url('/servers/');
  if (!noDigest) view.loc.url = function () { throw Error('location API changed'); };
  view.click('multiplayer_continue');
  assert(!view.modal()); assert.equal(view.win.location.hash, '#/servers/', 'direct hash fallback when Angular navigation fails');
}
console.log('PASS loader reminders and multiplayer routes');
