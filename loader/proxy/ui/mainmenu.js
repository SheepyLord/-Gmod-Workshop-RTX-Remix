// Main-menu diagnostics. Data is text-only; nothing is uploaded or opened automatically.
(function () {
  'use strict';
  // The verified RTX multiplayer bootstrap starts here. It needs only the menu's Lua bridge, not the
  // diagnostics panel or the menu controller it decorates, so a changed menu cannot stop it.
  if (!window.NativeLoaderClientBootstrap || window.NativeLoaderClientBootstrapRequested) return;
  var attempts = 0;
  function request() {
    if (window.NativeLoaderClientBootstrapRequested) return;
    if (window.lua && window.lua.Run) {
      window.NativeLoaderClientBootstrapRequested = true;
      window.lua.Run('require( "nlrtxclient" )');
    } else if (++attempts < 240 && window.setTimeout) {
      window.setTimeout(request, 500);
    }
  }
  request();
})();
(function () {
  'use strict';
  var data = window.NativeLoaderDiagnostics;
  var catalogs = window.NativeLoaderDiagnosticLabels;
  if (!data || !catalogs || window.NativeLoaderDiagnosticsInstalled) return;
  window.NativeLoaderDiagnosticsInstalled = true;
  var panel, body, copyButton, project;
  var last = '';
  function language(scope) {
    var code = String(scope && scope.Language || 'en').toLowerCase();
    if (code === 'zh' || code === 'zh-cn') code = 'zh-CN';
    if (code === 'zh-tw') code = 'zh-TW';
    return catalogs[code] || catalogs.en;
  }
  function gib(value) { return (Number(value) / 1073741824).toFixed(1) + ' GiB'; }
  function hash(value, labels) { return value ? value.slice(0, 12) : labels.unavailable; }
  function element(tag, parent) {
    var item = document.createElement(tag); parent.appendChild(item); return item;
  }
  function update() {
    var scope = typeof gScope !== 'undefined' ? gScope : null;
    var labels = language(scope);
    var home = !window.location || !window.location.hash || window.location.hash === '#/' || window.location.hash === '#';
    panel.style.display = scope && !scope.InGame && home ? 'block' : 'none';
    if (panel.style.display === 'none') return;
    var game = scope.Version && String(scope.Version) !== '0' ? String(scope.Version) : labels.unavailable;
    if (scope.Branch) game += ' · ' + String(scope.Branch);
    var signature = JSON.stringify([labels, game]);
    if (signature === last) return;
    last = signature;
    while (body.firstChild) body.removeChild(body.firstChild);
    var title = element('strong', body); title.textContent = labels.heading;
    var lines = [labels.heading];
    function row(label, value, full) {
      var line = element('div', body);
      var key = element('span', line); key.className = 'nl-debug-key'; key.textContent = label + ': ';
      var text = element('span', line); text.textContent = value;
      if (full) text.title = 'SHA-256: ' + full;
      lines.push(label + ': ' + value + (full ? '\nSHA-256: ' + full : ''));
    }
    row(labels.os, data.os || labels.unavailable);
    row(labels.cpu, (data.cpu || labels.unavailable) + (data.threads ? ' · ' + data.threads + ' ' + labels.threads : ''));
    row(labels.ram, data.memory ? gib(data.memory) : labels.unavailable);
    if (!data.graphics.length) row(labels.gpu, labels.unavailable);
    data.graphics.forEach(function (gpu) { row(labels.gpu, gpu.name + (gpu.memory ? ' · ' + gib(gpu.memory) : '')); });
    row(labels.game, game);
    row(labels.loader, data.loader.version + ' · ' + hash(data.loader.sha256, labels), data.loader.sha256);
    if (!data.packages.length) row(labels.package, labels.none);
    data.packages.forEach(function (item) {
      row(labels.package + ' (' + item.id + ')', item.version + ' · ' + hash(item.sha256, labels), item.sha256);
    });
    copyButton.textContent = labels.copy;
    copyButton.onclick = function () {
      if (window.lua && window.lua.Run) window.lua.Run('SetClipboardText( %s )', lines.join('\n'));
    };
    project.textContent = labels.project;
  }
  function install() {
    if (!document.body || document.getElementById('native-loader-diagnostics')) return;
    var style = element('style', document.head);
    style.textContent = '#native-loader-diagnostics{position:fixed;right:18px;bottom:82px;width:430px;max-width:42vw;max-height:42vh;overflow:auto;box-sizing:border-box;padding:12px 14px;background:rgba(16,23,32,.88);border:1px solid #2387ed;border-radius:5px;color:#eee;font:12px/1.55 Arial,sans-serif;z-index:40;user-select:text}#native-loader-diagnostics strong{display:block;color:#a9d4ff;margin-bottom:5px}#native-loader-diagnostics .nl-debug-key{color:#aab9cc}#native-loader-diagnostics button{margin-top:8px;padding:3px 8px;border:1px solid #60738d;background:#24364d;color:#fff;cursor:pointer}#native-loader-diagnostics a{margin-left:12px;color:#83bbff;cursor:pointer}';
    panel = element('section', document.body); panel.id = 'native-loader-diagnostics'; panel.style.display = 'none';
    body = element('div', panel);
    copyButton = element('button', panel); copyButton.type = 'button';
    project = element('a', panel); project.href = '#';
    project.onclick = function (event) {
      event.preventDefault();
      if (window.lua && window.lua.Run) window.lua.Run('gui.OpenURL( %s )', 'https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix');
    };
    update(); window.setInterval(update, 500);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();
})();
