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
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); }
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
  packages: [{id: 'example', version: '1.2.3+build', sha256: 'b'.repeat(64)}]};
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
const link = all(panel).find(item => item.tag === 'a');
link.onclick({preventDefault() {}});
assert.equal(calls[1][0], 'gui.OpenURL( %s )');
assert.equal(calls[1][1], 'https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix');
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
console.log('PASS menu diagnostics');
