/*
 * The menu on the home page that a visitor can try. No dependencies.
 *
 * Each row is a button. A row with a submenu opens and closes it (aria-expanded); one submenu at a time is open at
 * each level, as in a real menu. A row with an action fills the panel next to the menu from its data attributes,
 * which tools/render_pages.py writes from the output of `rh run <action> --dry-run --json`. The page starts with
 * Claude Code Here chosen, so it says the same without this script. Escape closes the innermost open submenu.
 */
(function () {
  'use strict';

  var root = document.querySelector('.try');
  if (!root) return;
  var panel = root.querySelector('.try-panel');
  var title = panel.querySelector('.try-title');
  var command = panel.querySelector('.try-command code');
  var summary = panel.querySelector('.try-summary');
  var text = panel.querySelector('.try-text');
  var kinds = panel.querySelectorAll('.try-kind');
  var labels = panel.querySelectorAll('.try-detail-label');

  function each(list, fn) { Array.prototype.forEach.call(list, fn); }

  function ownButton(item) {
    var first = item.firstElementChild;
    return first && first.classList.contains('m-row') ? first : null;
  }

  function ownSubmenu(item) {
    var last = item.lastElementChild;
    return last && last.classList.contains('m-sub') ? last : null;
  }

  function setOpen(item, open) {
    var button = ownButton(item);
    var sub = ownSubmenu(item);
    if (!button || !sub) return;
    button.setAttribute('aria-expanded', open ? 'true' : 'false');
    item.classList.toggle('m-open', open);
    sub.hidden = !open;
    if (!open) each(sub.children, function (child) { setOpen(child, false); });
  }

  function closeOthers(item) {
    each(item.parentElement.children, function (other) {
      if (other !== item) setOpen(other, false);
    });
  }

  function choose(button) {
    each(root.querySelectorAll('.m-row[aria-pressed="true"]'), function (b) { b.setAttribute('aria-pressed', 'false'); });
    button.setAttribute('aria-pressed', 'true');
    var kind = button.getAttribute('data-kind');
    var detail = button.getAttribute('data-detail');
    title.textContent = button.querySelector('.m-title').textContent;
    each(kinds, function (p) { p.hidden = p.getAttribute('data-kind') !== kind; });
    command.textContent = 'rh run ' + button.getAttribute('data-action') + ' main.swift';
    summary.textContent = button.getAttribute('data-summary');
    each(labels, function (l) { l.hidden = l.getAttribute('data-detail') !== detail; });
    text.textContent = button.getAttribute('data-text');
    text.hidden = !button.getAttribute('data-text');
    // On a phone the panel is under the menu: bring it up when the answer would be out of sight.
    if (panel.getBoundingClientRect().top > window.innerHeight - 96) {
      var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      panel.scrollIntoView({ block: 'nearest', behavior: still ? 'auto' : 'smooth' });
    }
  }

  root.addEventListener('click', function (event) {
    var button = event.target.closest('.m-row');
    if (!button || !root.contains(button)) return;
    var item = button.parentElement;
    closeOthers(item);
    if (button.hasAttribute('aria-expanded')) {
      setOpen(item, button.getAttribute('aria-expanded') !== 'true');
    } else {
      choose(button);
    }
  });

  root.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') return;
    var open = root.querySelectorAll('.m-item.m-open');
    if (!open.length) return;
    var innermost = open[open.length - 1];
    setOpen(innermost, false);
    ownButton(innermost).focus();
    event.preventDefault();
  });
})();
