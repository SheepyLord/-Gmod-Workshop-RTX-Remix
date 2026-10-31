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
const body = new Element('body');
const head = new Element('head');
function all(root) { return [root, ...root.children.flatMap(all)]; }
const document = {body, head, readyState: 'complete', createElement: tag => new Element(tag),
  getElementById: id => all(body).find(item => item.id === id)};
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
console.log('PASS menu diagnostics');
