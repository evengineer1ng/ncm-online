// NCM race car names (KB-223). Two feeds, two rates -- the platform's own pattern (open77_interactions):
//   * `ncm-names:plates` is content (who, what position, which team), sent by Lua when it changes;
//   * `open77:anchors` is position, projected natively every rendered frame for the anchors Lua registered on each
//     car. An anchor absent from a batch is behind the camera, out of range or not streamed: its plate hides.
(function () {
  "use strict";
  var root = document.getElementById("names");
  var ACCENTS = ["#ffb833", "#ffd64d", "#73e68c", "#80808c"];   // racing, leader, finished, out
  var plates = new Map();     // anchor id -> { el, name, team, chip }
  var frame = new Map();      // anchor id -> { x, y, distance, onScreen }
  var scheduled = 0;

  // screen-space projection: a fixed-pixel plate looks bigger against its car as the car recedes, so taper it
  function scaleFor(distance) {
    var d = Number(distance);
    if (!isFinite(d) || d <= 15) return 1;
    if (d >= 150) return 0.5;
    return Math.round((1 - (d - 15) / 135 * 0.5) * 1000) / 1000;
  }

  function place() {
    scheduled = 0;
    plates.forEach(function (p, id) {
      var a = frame.get(id);
      if (!a || a.onScreen === false) { p.el.classList.remove("on"); return; }
      p.el.style.left = (Math.max(0, Math.min(1, Number(a.x) || 0)) * 100) + "%";
      p.el.style.top = (Math.max(0, Math.min(1, Number(a.y) || 0)) * 100) + "%";
      p.el.style.setProperty("--plate-scale", String(scaleFor(a.distance)));
      p.el.style.setProperty("--plate-opacity", Number(a.distance) > 200 ? "0.6" : "1");
      p.el.classList.add("on");
    });
  }

  function schedule() { if (!scheduled) scheduled = requestAnimationFrame(place); }

  function make() {
    var el = document.createElement("div");
    el.className = "plate";
    var chip = document.createElement("span");
    chip.className = "plate__chip";
    var copy = document.createElement("span");
    copy.className = "plate__copy";
    var name = document.createElement("span");
    name.className = "plate__name";
    var team = document.createElement("span");
    team.className = "plate__team";
    copy.append(name, team);
    el.append(chip, copy);
    root.append(el);
    return { el: el, chip: chip, name: name, team: team };
  }

  // an empty Lua table arrives as {} rather than [], so anything that is not an array is an empty list
  function list(v) { return Array.isArray(v) ? v : []; }

  function update(payload) {
    var seen = new Set();
    list(payload && payload.plates).forEach(function (row) {
      var id = String(row && row.anchor || "");
      if (!id) return;
      seen.add(id);
      var p = plates.get(id);
      if (!p) { p = make(); plates.set(id, p); }
      p.chip.textContent = String(row.chip || "").slice(0, 6);
      p.name.textContent = String(row.title || "").slice(0, 40);
      p.team.textContent = String(row.sub || "").slice(0, 40);
      p.el.style.setProperty("--accent", ACCENTS[Math.max(0, Math.min(3, Number(row.accent) || 0))]);
    });
    plates.forEach(function (p, id) { if (!seen.has(id)) { p.el.remove(); plates.delete(id); } });
    schedule();
  }

  function anchors(payload) {
    frame.clear();
    list(payload && payload.anchors).forEach(function (a) {
      var id = String(a && a.id || "");
      if (id) frame.set(id, a);
    });
    schedule();
  }

  Open77.on("ncm-names:plates", update);
  Open77.on("open77:anchors", anchors);
  Open77.ready();
  Open77.emit("ncm-names:ready", {});
})();
