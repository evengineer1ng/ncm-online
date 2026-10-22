// NCM Online docs: phone menu + client-side search over search-index.json. No dependencies.
(function () {
  "use strict";
  // The menu ships open so the site works without JavaScript; on a phone, start it collapsed.
  var menu = document.querySelector(".menu");
  if (menu && window.matchMedia && window.matchMedia("(max-width: 52rem)").matches) menu.open = false;

  var input = document.getElementById("q");
  var out = document.getElementById("results");
  if (!input || !out) return;
  var root = input.getAttribute("data-root") || "";
  var index = null, loading = false;

  function load(cb) {
    if (index) return cb();
    if (loading) return;
    loading = true;
    fetch(root + "search-index.json").then(function (r) { return r.json(); })
      .then(function (d) { index = d; cb(); })
      .catch(function () { out.innerHTML = "<li>Search is unavailable offline.</li>"; });
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function snippet(text, term) {
    var i = text.toLowerCase().indexOf(term);
    if (i < 0) return text.slice(0, 110);
    var s = Math.max(0, i - 45);
    return (s > 0 ? "…" : "") + text.slice(s, s + 120) + "…";
  }

  function run() {
    var q = input.value.trim().toLowerCase();
    if (q.length < 2) { out.innerHTML = ""; return; }
    var terms = q.split(/\s+/);
    var hits = [];
    index.forEach(function (p) {
      var t = p.t.toLowerCase(), x = (p.d + " " + p.x).toLowerCase(), score = 0;
      for (var i = 0; i < terms.length; i++) {
        var w = terms[i];
        if (t.indexOf(w) >= 0) score += 10;
        var n = x.split(w).length - 1;
        if (n === 0 && t.indexOf(w) < 0) return;
        score += Math.min(n, 8);
      }
      hits.push({ p: p, s: score });
    });
    hits.sort(function (a, b) { return b.s - a.s; });
    out.innerHTML = hits.slice(0, 8).map(function (h) {
      return '<li><a href="' + root + h.p.u + '">' + esc(h.p.t) + "<span>" + esc(snippet(h.p.x, terms[0])) + "</span></a></li>";
    }).join("") || "<li>No matches.</li>";
  }

  input.addEventListener("input", function () { load(run); });
  input.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { input.value = ""; out.innerHTML = ""; }
    if (e.key === "Enter") { var a = out.querySelector("a"); if (a) a.click(); }
  });
})();
