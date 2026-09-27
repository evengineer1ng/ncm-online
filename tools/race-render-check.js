// Runtime check for the RACE HUD's render path.
//
// **This page had no guard and no harness at all until 2026-09-26.** `panel.html` has wrapped every render
// in `guard()` since KB-61, with `tools/panel-render-check.js` firing payloads at it. `race.html` had
// neither -- and it carries the lights, the strip, the board, the graph, the odometer, the driver inputs
// and now the tyre gauge. A throw anywhere inside `apply` vanished into CEF and took ALL of it, silently,
// with no log line and no error event.
//
// It went unnoticed for a simple reason: the race HUD never takes input focus, so there was no soft-lock
// to make a failure obvious the way KB-61 made the panel's obvious. The page just quietly went blank.
//
// So: stub a DOM, load the real inline script, push every payload shape `client/race.lua` can actually
// send, and assert `race:drawn` without `race:error`.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const WEB = process.argv[2];
const html = fs.readFileSync(path.join(WEB, "race.html"), "utf8");
const glyphsJs = fs.readFileSync(path.join(WEB, "glyphs.js"), "utf8");

const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const raceJs = blocks.sort((a, b) => b.length - a.length)[0];
if (!raceJs) { console.error("no inline script found in race.html"); process.exit(2); }

// ---- minimal DOM, same shape as the panel harness uses
function makeEl(tag) {
  const el = {
    tagName: String(tag || "div").toUpperCase(),
    children: [], attributes: {}, dataset: {},
    style: new Proxy({}, { get: (t, k) => (k === "setProperty" ? () => {} : t[k]), set: (t, k, v) => { t[k] = v; return true; } }),
    _text: "", _html: "",
    classList: {
      _s: new Set(),
      add(...c) { c.forEach(x => this._s.add(x)); },
      remove(...c) { c.forEach(x => this._s.delete(x)); },
      contains(c) { return this._s.has(c); },
      toggle(c, on) { if (on === undefined) { this._s.has(c) ? this._s.delete(c) : this._s.add(c); } else if (on) this._s.add(c); else this._s.delete(c); },
    },
    append(...kids) { for (const k of kids) { if (k == null) throw new TypeError("append(null) — a null child reached the DOM"); this.children.push(k); } },
    appendChild(k) { this.append(k); return k; },
    setAttribute(k, v) { this.attributes[k] = v; },
    getAttribute(k) { return this.attributes[k]; },
    addEventListener() {},
    querySelector() { return makeEl("div"); },
    querySelectorAll() { return []; },
    replaceChildren(...k) { this.children = k; },
    remove() {},
  };
  Object.defineProperty(el, "textContent", { get() { return this._text; }, set(v) { this._text = String(v == null ? "" : v); } });
  Object.defineProperty(el, "innerHTML", { get() { return this._html; }, set(v) { this._html = String(v == null ? "" : v); this.children = []; } });
  return el;
}

const byId = {};
const document = {
  getElementById(id) { return (byId[id] = byId[id] || makeEl("div")); },
  createElement: (t) => makeEl(t),
  createElementNS: (_ns, t) => makeEl(t),
  createTextNode: (s) => ({ nodeType: 3, textContent: String(s == null ? "" : s) }),
  querySelector() { return makeEl("div"); },
  querySelectorAll() { return []; },
  addEventListener() {},
  body: makeEl("body"),
};

const events = {};
const emitted = [];
const context = {
  console, Math, JSON, Date, Map, Set, Array, Object, String, Number, isFinite, parseInt, parseFloat,
  document,
  setTimeout: () => 1, clearTimeout: () => {}, setInterval: () => 1, clearInterval: () => {},
  requestAnimationFrame: () => 1,
  addEventListener: () => {},
  WebSocket: function () { this.close = () => {}; },
  Open77: {
    on: (name, fn) => { events[name] = fn; },
    ready: () => {},
    emit: (name, value) => { emitted.push({ name, value }); },
  },
};
context.window = context;
context.globalThis = context;
vm.createContext(context);

vm.runInContext(glyphsJs, context, { filename: "glyphs.js" });
vm.runInContext(raceJs, context, { filename: "race.html(inline)" });

let bad = 0, count = 0;
function check(condition, label) {
  count++;
  if (!condition) { bad++; console.log("    FAIL " + label); }
}

function fire(name, payload) {
  emitted.length = 0;
  const fn = events[name];
  if (!fn) { bad++; count++; console.log("    FAIL no handler registered for " + name); return; }
  fn(payload);
}

function drewCleanly(label) {
  const errs = emitted.filter(e => e.name === "race:error");
  const drawn = emitted.filter(e => e.name === "race:drawn");
  if (errs.length) {
    bad++; count++;
    console.log("    FAIL " + label + " -> race:error " + JSON.stringify(errs[0].value));
    return;
  }
  check(drawn.length > 0, label + " -> race:drawn");
}

// ---------------------------------------------------------------- the guard exists at all
check(typeof events["race:state"] === "function", "race:state has a handler");
check(typeof events["race:inputs"] === "function", "race:inputs has a handler");
check(typeof events["race:tyre"] === "function", "race:tyre has a handler (L159)");

// ---------------------------------------------------------------- every state shape race.lua can send
fire("race:state", {});
drewCleanly("an empty state");

fire("race:state", null);
drewCleanly("a null state -- the shape sent when nothing is running");

fire("race:state", { instrument: { odo: "12 345 km", name: "Galena", ord: 2 } });
drewCleanly("odometer only, which is the freeroam case");

fire("race:state", {
  banner: { text: "RACE COMPLETE", kind: "finish", sub: "P3" },
  board: { rows: [{ pos: 1, name: "easporks", time: "1:23.456", gap: "+0.000", me: true }] },
});
drewCleanly("a finished race with a board");

fire("race:state", { board: { rows: [] } });
drewCleanly("an empty board, which is not the same as no board");

fire("race:state", { lights: 3 });
drewCleanly("a countdown");

// ---------------------------------------------------------------- driver inputs
fire("race:inputs", { throttle: 0.5, brake: 0, steering: -0.25 });
check(true, "inputs accepted");
fire("race:inputs", { off: true });
check(true, "inputs off accepted");
fire("race:inputs", null);
check(true, "a null inputs payload does not throw");

// ---------------------------------------------------------------- the tyre gauge (L159)
//
// IDEA-361 is the rule under test here: "zero is a measurement; absence is not". A needle resting in the
// middle of the window is the single most plausible-looking wrong value this whole design can produce --
// it reads as "your tyres are perfect" when the truth is "we could not derive a temperature".
const tyreEl = document.getElementById("inTyre");
const tyrePct = document.getElementById("inTyrePct");

fire("race:tyre", false);
check(tyreEl.classList.contains("na"), "unknown tyre state marks the gauge not-available");
check(tyrePct.textContent === "--", "and renders a dash, never a plausible resting value");

fire("race:tyre", { p: 0, m: 1.0 });
check(!tyreEl.classList.contains("na"), "a known temperature clears not-available");
check(tyreEl.classList.contains("good"), "dead centre reads as in-window");
check(tyrePct.textContent === "OK", "and costs nothing");

fire("race:tyre", { p: -1, m: 0.85 });
check(tyreEl.classList.contains("cold"), "fully cold reads cold");
check(tyrePct.textContent === "-15%", "and shows the cost as a percentage, not a multiplier");

fire("race:tyre", { p: 1, m: 0.85 });
check(tyreEl.classList.contains("hot"), "fully hot reads hot");

fire("race:tyre", { p: 5, m: 0.85 });
check(tyreEl.classList.contains("hot"), "an out-of-range position clamps rather than escaping the gauge");

fire("race:tyre", { p: "hot" });
check(tyreEl.classList.contains("na"), "a non-numeric position is unknown, not zero");

fire("race:tyre", {});
check(tyreEl.classList.contains("na"), "an empty payload is unknown too");

fire("race:tyre", null);
check(true, "a null tyre payload does not throw");

// ---------------------------------------------------------------- the cluster visibility rule
//
// The bug this guards: `race:inputs` used to hide the WHOLE #inputs box when inputs were unreadable, which
// would have taken the tyre gauge with it -- and tyre temperature is server-derived, so it is available in
// exactly the cases where the client snapshot is not.
const cluster = document.getElementById("inputs");
fire("race:inputs", { off: true });
fire("race:tyre", { p: 0.2, m: 0.99 });
check(!cluster.classList.contains("hidden"),
  "tyre state alone keeps the cluster visible when inputs are unreadable");

fire("race:tyre", false);
fire("race:inputs", { off: true });
check(cluster.classList.contains("hidden"), "and with neither known it hides");

// ---------------------------------------------------------------- the ghost row (L166)
//
// The presentation rule this guards is not cosmetic: a ghost must never read as an entrant. It has no
// position, it is not in the field, and it is drawn outside `#rows`. If a ghost ever appears as `P2` a driver
// is being told there was a competitor who did not exist.
check(typeof events["race:ghost"] === "function", "race:ghost has a handler");

const ghostEl = document.getElementById("ghost");
const ghostDelta = document.getElementById("ghostDelta");
const ghostTime = document.getElementById("ghostTime");
const ghostWarn = document.getElementById("ghostWarn");
const ghostRows = document.getElementById("rows");

fire("race:ghost", { present: false, mode: "personal" });
check(ghostEl.classList.contains("hidden"), "no ghost means no row");

const rowsBefore = ghostRows.children.length;
fire("race:ghost", {
  present: true, mode: "personal", label: "PERSONAL BEST", display: "baremetaleven",
  elapsedMs: 102318, deltaMs: -216, playing: true,
});
check(!ghostEl.classList.contains("hidden"), "a loaded ghost draws its row");
check(ghostTime.textContent === "1:42.318", "the recorded lap time, formatted: " + ghostTime.textContent);
check(ghostDelta.textContent.indexOf("-0.216") >= 0, "the delta, signed: " + ghostDelta.textContent);
check(ghostDelta.classList.contains("ahead"), "a negative delta is ahead");
check(!/P\d/.test(ghostEl.textContent || ""),
  "the ghost row carries no position -- it is a target, not an entrant");
check(ghostRows.children.length === rowsBefore,
  "and drawing it adds nothing to the standings table");

fire("race:ghost", { present: true, label: "PERSONAL BEST", elapsedMs: 102318, deltaMs: 431, playing: true });
check(ghostDelta.classList.contains("behind"), "a positive delta is behind");
check(ghostDelta.textContent.indexOf("+0.431") >= 0, "and is shown with its sign: " + ghostDelta.textContent);

// A loaded ghost that is not currently replaying has no delta to report, and a stale number would be a
// confidently wrong instrument -- the same rule the driver inputs follow.
fire("race:ghost", { present: true, label: "PERSONAL BEST", elapsedMs: 102318, deltaMs: -216, playing: false });
check(ghostDelta.textContent === "--", "a ghost that is not playing shows a dash, not the last delta");
check(ghostDelta.classList.contains("na"), "and is marked unknown");

fire("race:ghost", { present: true, label: "PERSONAL BEST", elapsedMs: 102318, playing: true });
check(ghostDelta.textContent === "--", "a missing delta is a dash too");

// Sub-minute laps must not be shown as "0:xx".
fire("race:ghost", { present: true, label: "SESSION BEST", elapsedMs: 42318, deltaMs: 0, playing: true });
check(ghostTime.textContent === "42.318", "a sub-minute lap drops the minute field: " + ghostTime.textContent);

// A fallback model means the record has no authored template. Say so, rather than leaving a driver to wonder
// why they are chasing a road arrow.
fire("race:ghost", { present: true, label: "PERSONAL BEST", elapsedMs: 1000, playing: true, fallbackModel: true });
check(!ghostWarn.classList.contains("hidden"), "a fallback model is reported on the HUD");
fire("race:ghost", { present: true, label: "PERSONAL BEST", elapsedMs: 1000, playing: true, fallbackModel: false });
check(ghostWarn.classList.contains("hidden"), "and a real model says nothing");

fire("race:ghost", null);
check(true, "a null ghost payload does not throw");
fire("race:ghost", {});
check(ghostEl.classList.contains("hidden"), "an empty ghost payload hides the row");

// ---------------------------------------------------------------- source-text assertions
//
// Cheap, and they catch the class of mistake a stub DOM cannot: a value written straight into the page.
check(!/innerHTML\s*=\s*[^"'`]*\$\{/.test(raceJs), "no template-interpolated innerHTML");
check(raceJs.includes("race:drawn") && raceJs.includes("race:error"),
  "the guard reports both outcomes, so a silent blank HUD is not possible any more");

console.log("=== race render check: " + count + " assertion(s), " + bad + " bad");
process.exit(bad ? 1 : 0);
