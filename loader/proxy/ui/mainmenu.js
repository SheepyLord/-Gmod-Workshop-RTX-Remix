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
  var previous, commit, warningVisible = false, warningChecked = false, noticesLoaded = false, everInGame = false;
  var requestedAt = 0, noticeAttempts = 0;
  var failures = ['device_lost', 'cs_exception', 'allocation_failed', 'out_of_memory', 'crash'];
  function requestNotices() {
    if (!data.session_token || !window.NativeLoaderReadNotices || !window.lua || !window.lua.Run) return;
    if ((warningChecked || everInGame) && noticesLoaded || noticeAttempts >= 120) return;
    var now = Date.now();
    if (now - requestedAt < 1000) return;
    requestedAt = now; noticeAttempts++;
    window.lua.Run(window.NativeLoaderReadNotices, data.session_token, Number(data.process_id) || 0);
  }
  window.NativeLoaderReceiveNotices = function (value) {
    if (!value || !data.session_token || value.session_token !== data.session_token) return;
    var old = value.previous_session;
    if (old && typeof old.reason === 'string') {
      previous = {reason: old.reason, folder: typeof old.folder === 'string' ? old.folder.slice(0, 4096) : ''};
      noticesLoaded = true;
    }
    var current = value.commit;
    var age = current ? Date.now() - Date.parse(current.time_utc) : NaN;
    if (!warningChecked && !everInGame && panel && panel.style.display === 'block' && current &&
        current.session_token === data.session_token && age >= -5000 && age <= 30000 &&
        typeof current.commit_total === 'number' && isFinite(current.commit_total) && current.commit_total >= 0 &&
        typeof current.commit_limit === 'number' && isFinite(current.commit_limit) && current.commit_limit > 0 &&
        typeof current.warning === 'boolean') {
      commit = current; warningChecked = true;
      warningVisible = current.warning && value.warning_allowed === true;
      if (warningVisible && window.lua && window.lua.Run)
        window.lua.Run('_G.NativeLoaderRAMWarningSession = %s', data.session_token);
    }
    last = '';
    if (panel) update();
  };
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
    if (scope && scope.InGame) everInGame = true;
    panel.style.display = scope && !scope.InGame && home ? 'block' : 'none';
    if (panel.style.display === 'none') { warningVisible = false; return; }
    requestNotices();
    var game = scope.Version && String(scope.Version) !== '0' ? String(scope.Version) : labels.unavailable;
    if (scope.Branch) game += ' · ' + String(scope.Branch);
    var signature = JSON.stringify([labels, game, previous, warningVisible, commit]);
    if (signature === last) return;
    last = signature;
    while (body.firstChild) body.removeChild(body.firstChild);
    var title = element('strong', body); title.textContent = labels.heading;
    var lines = [labels.heading];
    function notice(label, text) {
      var line = element('div', body); line.className = 'nl-debug-warning'; line.textContent = label + ': ' + text;
      lines.push(label + ': ' + text);
    }
    if (previous && failures.indexOf(previous.reason) !== -1)
      notice(labels.previous_session, labels['failure_' + previous.reason] + ' · ' + (previous.folder || labels.evidence_unavailable));
    if (warningVisible)
      notice(labels.ram_warning_heading, gib(commit.commit_total) + ' / ' + gib(commit.commit_limit) + '. ' + labels.ram_warning);
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
    style.textContent += '#native-loader-diagnostics .nl-debug-warning{color:#ffd58d;border-left:2px solid #d8a44e;padding-left:8px;margin:7px 0;overflow-wrap:anywhere}';
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
