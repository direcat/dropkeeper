(function () {
  var copyBtns = document.querySelectorAll('.copy');
  var status = document.getElementById('copy-status');
  var cmd = 'brew install --cask direcat/tap/dropkeeper';
  function done(btn) {
    var old = btn.textContent;
    btn.textContent = 'Copied';
    if (status) status.textContent = 'Command copied to the clipboard.';
    setTimeout(function () { btn.textContent = old; if (status) status.textContent = ''; }, 1800);
  }
  function fallback(btn) {
    var t = document.createElement('textarea');
    t.value = cmd; t.setAttribute('readonly', '');
    t.style.position = 'fixed'; t.style.opacity = '0';
    document.body.appendChild(t); t.select();
    try { if (document.execCommand('copy')) done(btn); } catch (e) {}
    document.body.removeChild(t);
  }
  copyBtns.forEach(function (btn) {
    btn.addEventListener('click', function () {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(cmd).then(function () { done(btn); }, function () { fallback(btn); });
      } else { fallback(btn); }
    });
  });

  var v = document.getElementById('demo');
  var pp = document.getElementById('pp');
  if (!v || !pp) return;
  function label() {
    var paused = v.paused;
    pp.textContent = paused ? 'Play' : 'Pause';
    pp.setAttribute('aria-label', paused ? 'Play the demo video' : 'Pause the demo video');
  }
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce) { v.removeAttribute('autoplay'); v.pause(); v.controls = true; return; }
  pp.hidden = false;
  pp.addEventListener('click', function () { if (v.paused) { v.play(); } else { v.pause(); } });
  v.addEventListener('play', label);
  v.addEventListener('pause', label);
  label();
})();
