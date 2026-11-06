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

// RTX notices use the stock menu Lua bridge, and Angular's navigation event in both menu modes.
(function () {
  'use strict';
  var data = window.NativeLoaderDiagnostics, catalogs = window.NativeLoaderDiagnosticLabels;
  if (!data || !data.rtx_active || !catalogs || window.NativeLoaderMenuNoticesInstalled) return;
  window.NativeLoaderMenuNoticesInstalled = true;
  var state, modal, pending, root, location, allowedRoute, shown = false, failed = false;
  var requested = false, attempts = 0;
  function decimal(a, b) { return a.length !== b.length ? a.length - b.length : a < b ? -1 : a > b ? 1 : 0; }
  function version(value) {
    if (typeof value !== 'string' || value.length > 128) return null;
    var match = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/.exec(value);
    if (!match || match[0].length !== value.length) return null;
    var core = match.slice(1, 4), pre = match[4] ? match[4].split('.') : [];
    if (core.some(function (n) { return decimal(n, '18446744073709551615') > 0; }) ||
        pre.some(function (n) { return /^[0-9]+$/.test(n) && n.length > 1 && n[0] === '0'; })) return null;
    return {core: core, pre: pre};
  }
  function compare(a, b) {
    for (var i = 0; i < 3; i++) { var c = decimal(a.core[i], b.core[i]); if (c) return c; }
    if (!a.pre.length || !b.pre.length) return a.pre.length ? -1 : b.pre.length ? 1 : 0;
    for (var j = 0; j < Math.min(a.pre.length, b.pre.length); j++) {
      var x = a.pre[j], y = b.pre[j], xn = /^[0-9]+$/.test(x), yn = /^[0-9]+$/.test(y);
      var order = xn && yn ? decimal(x, y) : xn !== yn ? (xn ? -1 : 1) : x < y ? -1 : x > y ? 1 : 0;
      if (order) return order;
    }
    return a.pre.length - b.pre.length;
  }
  var release = data.released_loader, current = version(data.loader && data.loader.version);
  if (!release || Object.keys(release).sort().join(',') !== 'url,version' || !version(release.version) ||
      release.url !== 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v' + release.version ||
      !current || compare(version(release.version), current) <= 0) release = null;
  function labels() {
    var code = String(typeof gScope !== 'undefined' && gScope && gScope.Language || 'en').toLowerCase();
    return catalogs[code === 'zh' || code === 'zh-cn' ? 'zh-CN' : code === 'zh-tw' ? 'zh-TW' : code] || catalogs.en;
  }
  function run() {
    if (!window.lua || typeof window.lua.Run !== 'function') throw Error('menu bridge unavailable');
    return window.lua.Run.apply(window.lua, arguments);
  }
  function close() { if (modal && modal.parentNode) modal.parentNode.removeChild(modal); modal = null; }
  function node(tag, parent, text) {
    var child = document.createElement(tag); if (text) child.textContent = text; parent.appendChild(child); return child;
  }
  function dialog(title) {
    close();
    modal = node('div', document.body); modal.id = 'native-loader-modal';
    var card = node('section', modal); card.setAttribute('role', 'dialog'); card.setAttribute('aria-modal', 'true');
    var heading = node('h2', card, title); heading.id = 'native-loader-modal-title';
    card.setAttribute('aria-labelledby', heading.id);
    return card;
  }
  function button(parent, text, action) {
    var item = node('button', parent, text); item.type = 'button'; item.onclick = action; return item;
  }
  function navigate(target) {
    allowedRoute = target;
    function fallback() { failed = true; window.location.hash = '#' + target; }
    try {
      root.$evalAsync(function () { try { location.url(target); } catch (_) { fallback(); } });
    } catch (_) { fallback(); }
  }
  function failOpen() {
    failed = true; close();
    if (pending) { var target = pending; pending = null; navigate(target); }
  }
  function multiplayer(target) {
    try {
      pending = target;
      var l = labels(), card = dialog(l.multiplayer_title);
      node('p', card, l.multiplayer_rules); node('p', card, l.multiplayer_performance); node('p', card, l.multiplayer_risk);
      var checkLabel = node('label', card), check = node('input', checkLabel); check.type = 'checkbox';
      node('span', checkLabel, l.multiplayer_remember);
      var actions = node('div', card);
      button(actions, l.multiplayer_continue, function () {
        if (check.checked) {
          if (!state) state = {};
          state.multiplayer_dismissed = true;
          try { run('file.CreateDir("native-loader") file.Write("native-loader/multiplayer-warning-dismissed.txt", "1")'); } catch (_) { }
        }
        var next = pending; pending = null; close(); navigate(next);
      }).focus();
      button(actions, l.multiplayer_back, function () { pending = null; close(); navigate('/'); });
    } catch (_) { failOpen(); }
  }
  function reminder() {
    if (!release || !state || shown || state.update_seen || state.ignored_version === release.version || modal || failed) return;
    var scope = typeof gScope !== 'undefined' ? gScope : null;
    if (!scope || scope.InGame || location && location.path() !== '/' ||
        !location && window.location.hash && window.location.hash !== '#/' && window.location.hash !== '#') return;
    try {
      var l = labels(), card = dialog(l.update_title);
      node('p', card, l.update_versions.replace('{current}', data.loader.version).replace('{latest}', release.version));
      node('p', card, l.update_instructions);
      var actions = node('div', card);
      button(actions, l.update_open, function () { try { run('gui.OpenURL( %s )', release.url); } catch (_) { } close(); });
      button(actions, l.update_later, close).focus();
      button(actions, l.update_ignore.replace('{version}', release.version), function () {
        try { run('file.CreateDir("native-loader") file.Write("native-loader/loader-update-ignored.txt", %s)', release.version); } catch (_) { }
        close();
      });
      shown = true;
      run('_G.NativeLoaderUpdateSession = %s', data.session_token);
    } catch (_) { close(); }
  }
  window.NativeLoaderReceiveMenuState = function (value) {
    if (!value || value.session_token !== data.session_token) return;
    state = {update_seen: value.update_seen === true, ignored_version: value.ignored_version,
      multiplayer_dismissed: value.multiplayer_dismissed === true};
    if (pending && state.multiplayer_dismissed) { var target = pending; pending = null; close(); navigate(target); }
    reminder();
  };
  function install() {
    if (!document.body) return;
    if (!document.getElementById('native-loader-modal-style')) {
      var style = node('style', document.head); style.id = 'native-loader-modal-style';
      style.textContent = '#native-loader-modal{position:fixed;inset:0;z-index:10000;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.76);font:clamp(16px,1.65vh,36px)/1.55 Arial,sans-serif;color:#edf4ff}' +
        '#native-loader-modal section{box-sizing:border-box;width:44em;max-width:90vw;max-height:90vh;overflow:auto;background:#162333;border:2px solid #468ed0;border-radius:8px;padding:1.6em;box-shadow:0 8px 50px #000}' +
        '#native-loader-modal h2{font-size:1.35em;margin:0 0 .8em}#native-loader-modal p{margin:.8em 0;white-space:pre-line}' +
        '#native-loader-modal button{font:inherit;padding:.5em .8em;margin:.8em .6em 0 0;background:#264867;color:white;border:1px solid #8ab1d7;border-radius:4px;cursor:pointer}' +
        '#native-loader-modal label{display:flex;align-items:center;gap:.6em;margin-top:1em;cursor:pointer}#native-loader-modal input{width:1.1em;height:1.1em}';
    }
    poll();
    if (window.setInterval) window.setInterval(poll, 500);
  }
  // Register while scripts are loading, before Angular's DOM-ready bootstrap consumes run blocks.
  // Registering in install() would be too late on the real stock page.
  try {
    if (typeof App !== 'undefined' && App.run) App.run(['$rootScope', '$location', function (r, loc) {
        if (!r || typeof r.$on !== 'function' || !loc || typeof loc.url !== 'function' || typeof loc.path !== 'function') return;
        root = r; location = loc;
        r.$on('$locationChangeStart', function (event) {
          try {
          var target = loc.url();
          if (!/^\/servers(?:\/|$)/i.test(loc.path())) { if (pending) { pending = null; close(); } return; }
          if (failed || !window.lua || !window.lua.Run || state && state.multiplayer_dismissed) return;
          if (allowedRoute === target) { allowedRoute = null; return; }
          // Do not cancel a route until the modal has actually been built successfully.
          multiplayer(target);
          if (modal && pending) event.preventDefault();
          } catch (_) { failOpen(); }
        });
    }]);
  } catch (_) { failOpen(); }
  function poll() {
    if (!requested && attempts++ < 120 && window.lua && window.lua.Run && window.NativeLoaderMenuChoices && data.session_token) {
      try { run(window.NativeLoaderMenuChoices, data.session_token); requested = true; } catch (_) { failOpen(); }
    }
    reminder();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();
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
  var failures = ['device_lost', 'cs_exception', 'allocation_failed', 'out_of_memory', 'likely_out_of_memory', 'crash'];
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
    if (data.performance_tier && data.performance_tier.adapter && data.performance_tier.layer) {
      var tier = data.performance_tier;
      row(labels.performance_tier, labels['tier_' + tier.tier] + ' · ' + labels['tier_' + tier.source]);
    }
    row(labels.game, game);
    row(labels.loader, data.loader.version + ' · ' + hash(data.loader.sha256, labels), data.loader.sha256);
    var contentCount = 0;
    data.packages.forEach(function (item) {
      if (item.id === 'gmod-rtx-remix')
        row(labels.package + ' (' + item.id + ')', item.version + ' · ' + hash(item.sha256, labels), item.sha256);
      else contentCount++;
    });
    row(labels.content_addons, labels.content_enabled.replace('{count}', String(contentCount)));
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
      if (window.lua && window.lua.Run) window.lua.Run('gui.OpenURL( %s )', 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix');
    };
    update(); window.setInterval(update, 500);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();
})();
