/* Sync the suggested upload directory with the SSH login account.
 * Leave explicitly customized remote paths untouched. */
(function () {
  'use strict';
  var lastUser = '';
  var lastSuggested = '/home/etech';
  function labelFor(input) {
    var id = input.id;
    var label = id ? document.querySelector('label[for="' + CSS.escape(id) + '"]') : null;
    var p = input.closest('label, .field, .form-row, .form-group, .kv, .row, .setting, .deploy-field');
    return [input.name, input.id, input.placeholder, input.getAttribute('aria-label'),
      label && label.textContent, p && p.textContent && p.textContent.slice(0,180)].filter(Boolean).join(' ');
  }
  function findField(kind) {
    var items = Array.from(document.querySelectorAll('#main input, #main textarea'));
    var exact = kind === 'user' ? /^(deploy[_-]?user|ssh[_-]?user)$/i : /^(deploy[_-]?remote[_-]?dir|remote[_-]?dir)$/i;
    var re = kind === 'user' ? /(SSH.{0,12}(로그인|계정|사용자)|로그인.{0,12}계정|DEPLOY_USER)/i :
                              /(원격.{0,12}(전송|폴더|디렉터리)|DEPLOY_REMOTE_DIR)/i;
    return items.find(function (e) { return exact.test(e.id) || exact.test(e.name); }) ||
      items.find(function (e) { return re.test(labelFor(e)); }) ||
      items.find(function (e) { return kind === 'user' ? e.value === lastUser || e.value === 'etech' : e.value === lastSuggested; });
  }
  function sync(source) {
    var userInput = findField('user');
    var dirInput = findField('dir');
    if (!userInput || !dirInput || userInput === dirInput) return;
    var user = String(userInput.value || '').trim();
    if (!/^[a-z_][a-z0-9_-]*\$?$/i.test(user)) return;
    var old = lastUser || 'etech';
    var current = String(dirInput.value || '').trim();
    var suggested = '/home/' + user;
    var wasAuto = current === '' || current === '/home/' + old ||
      current === lastSuggested || (current === '/home/etech' && old === 'etech');
    lastUser = user;
    lastSuggested = suggested;
    if (!wasAuto || current === suggested) return;
    dirInput.value = suggested;
    dirInput.dispatchEvent(new Event('input', {bubbles:true}));
    dirInput.dispatchEvent(new Event('change', {bubbles:true}));
  }
  // React to edits after the wizard has processed its own update and rerender.
  document.addEventListener('input', function (event) {
    if (!event.target || event.target.tagName !== 'INPUT') return;
    if (/SSH|DEPLOY_USER|로그인|계정/i.test(labelFor(event.target))) {
      setTimeout(sync, 0);
    }
  }, false);
  document.addEventListener('change', function (event) {
    if (event.target && /SSH|DEPLOY_USER|로그인|계정/i.test(labelFor(event.target))) {
      setTimeout(sync, 0);
    }
  }, false);
  // Initially synchronize a persisted/imported username while retaining custom paths.
  window.addEventListener('load', function () { setTimeout(sync, 250); });
})();
