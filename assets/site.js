/*
 * Language handling for the Right Here site. No dependencies, no build step.
 *
 * The HTML carries the English text. Every translatable element has data-i18n="key" (text) or
 * data-i18n-<attr>="key" (an attribute: alt, aria-label, content). Other languages come from
 * i18n/<code>.json, a flat key -> string map. A key a language file lacks keeps its English text.
 * In a string, `backticks` mark code and become <code>.
 *
 * Choice order: ?lang=xx, then the saved choice, then navigator.languages, then English.
 * Every URL here is relative, so the site works from a project sub-path and from file://
 * (where browsers block fetch, so a language other than English cannot load and English stays).
 */
(function () {
  'use strict';

  var STORAGE_KEY = 'rh-site-lang';
  var RTL = { ar: true, fa: true, he: true, ur: true };
  var select = document.getElementById('lang');
  var statusEl = document.getElementById('lang-status');
  if (!select) return;

  var codes = Array.prototype.map.call(select.options, function (o) { return o.value; });
  var byLower = {};
  codes.forEach(function (c) { byLower[c.toLowerCase()] = c; });

  var ALIASES = {
    'iw': 'he', 'in': 'id', 'zh': 'zh-Hans', 'zh-cn': 'zh-Hans', 'zh-sg': 'zh-Hans',
    'zh-tw': 'zh-Hant', 'zh-hk': 'zh-Hant', 'zh-mo': 'zh-Hant', 'pt': 'pt-BR', 'pt-pt': 'pt-BR'
  };

  function match(tag) {
    if (!tag) return null;
    var lower = String(tag).toLowerCase().replace(/_/g, '-');
    if (byLower[lower]) return byLower[lower];
    if (ALIASES[lower]) return ALIASES[lower];
    if (/^zh-hans/.test(lower)) return 'zh-Hans';
    if (/^zh-hant/.test(lower)) return 'zh-Hant';
    var base = lower.split('-')[0];
    return byLower[base] || ALIASES[base] || null;
  }

  function readStored() {
    try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }
  function writeStored(code) {
    try { localStorage.setItem(STORAGE_KEY, code); } catch (e) { /* private mode: the choice just is not kept */ }
  }

  function initialLanguage() {
    var fromQuery = null;
    try { fromQuery = match(new URLSearchParams(location.search).get('lang')); } catch (e) { /* old browser */ }
    if (fromQuery) return fromQuery;
    var stored = match(readStored());
    if (stored) return stored;
    var prefs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language];
    for (var i = 0; i < prefs.length; i++) {
      var m = match(prefs[i]);
      if (m) return m;
    }
    return 'en';
  }

  // Remember the English markup of every translatable node, so English and missing keys can be restored.
  var targets = [];
  Array.prototype.forEach.call(document.querySelectorAll('[data-i18n]'), function (el) {
    targets.push({ el: el, key: el.getAttribute('data-i18n'), attr: null, original: Array.prototype.slice.call(el.cloneNode(true).childNodes) });
  });
  Array.prototype.forEach.call(document.querySelectorAll('*'), function (el) {
    Array.prototype.forEach.call(el.attributes, function (a) {
      if (a.name.indexOf('data-i18n-') === 0) {
        var attr = a.name.slice(10);
        targets.push({ el: el, key: a.value, attr: attr, original: el.getAttribute(attr) });
      }
    });
  });
  var links = Array.prototype.map.call(document.querySelectorAll('a[data-keep-lang]'), function (a) {
    return { el: a, href: a.getAttribute('href') };
  });

  function renderText(el, text) {
    el.textContent = '';
    text.split('`').forEach(function (part, i) {
      if (!part) return;
      if (i % 2 === 1) {
        var code = document.createElement('code');
        code.textContent = part;
        el.appendChild(code);
      } else {
        el.appendChild(document.createTextNode(part));
      }
    });
  }

  function paint(dict) {
    targets.forEach(function (t) {
      var text = dict && typeof dict[t.key] === 'string' && dict[t.key].trim() ? dict[t.key] : null;
      if (t.attr) {
        t.el.setAttribute(t.attr, text ? text.replace(/`/g, '') : t.original);
      } else if (t.el.tagName === 'TITLE') {
        t.el.textContent = text ? text.replace(/`/g, '') : t.original.map(function (n) { return n.textContent; }).join('');
      } else if (text) {
        renderText(t.el, text);
      } else {
        t.el.textContent = '';
        t.original.forEach(function (n) { t.el.appendChild(n.cloneNode(true)); });
      }
    });
  }

  function setDocument(code) {
    var root = document.documentElement;
    root.lang = code;
    root.dir = RTL[code] ? 'rtl' : 'ltr';
    select.value = code;
    links.forEach(function (l) {
      var hash = '', href = l.href, i = href.indexOf('#');
      if (i >= 0) { hash = href.slice(i); href = href.slice(0, i); }
      href = href.replace(/[?&]lang=[^&]*/, '');
      l.el.setAttribute('href', href + (href.indexOf('?') >= 0 ? '&' : '?') + 'lang=' + encodeURIComponent(code) + hash);
    });
  }

  function say(message) {
    if (!statusEl) return;
    statusEl.textContent = message || '';
    statusEl.hidden = !message;
  }

  var cache = {};
  var latest = 0;

  function load(code) {
    if (cache[code]) return Promise.resolve(cache[code]);
    return fetch('i18n/' + code + '.json').then(function (r) {
      if (!r.ok) throw new Error('missing');
      return r.json();
    }).then(function (dict) { cache[code] = dict; return dict; });
  }

  function show(code, remember) {
    var ticket = ++latest;
    if (remember) writeStored(code);
    if (code === 'en') {
      paint(null);
      setDocument('en');
      say('');
      return;
    }
    load(code).then(function (dict) {
      if (ticket !== latest) return;
      paint(dict);
      setDocument(code);
      say('');
    }).catch(function () {
      if (ticket !== latest) return;
      paint(null);
      setDocument('en');
      say(location.protocol === 'file:'
        ? 'Browsers do not load translation files from file:// pages. Open the site over http(s) to read it in another language.'
        : 'This language is not available yet. Showing English.');
    });
  }

  select.addEventListener('change', function () {
    var code = select.value;
    try {
      var url = new URL(location.href);
      url.searchParams.set('lang', code);
      history.replaceState(null, '', url.pathname.split('/').pop() + url.search + url.hash);
    } catch (e) { /* the address bar just keeps its old query */ }
    show(code, true);
  });

  var start = initialLanguage();
  select.value = start;
  if (start !== 'en') show(start, false);
  else setDocument('en');
})();
