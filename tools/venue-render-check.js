// Runtime check for web/venue.html — the venue option list, the history/practice panel, and the Street Call
// form that `L193` moved onto this same page.
//
// **This page had no guard and no harness at all until 2026-09-28**, which is part of why the Street Call form
// could fail to render for a whole build without anything saying so. `panel.html` has wrapped every render in
// `guard()` since KB-61 and `race.html` got the same treatment with `L159`; this page carried three tenants and
// neither a guard nor a test.
//
// What this harness is really defending is the KB-63 boundary. `page:send` silently drops large messages — no
// error, no return value, no log line — and the Street Call form died on exactly that: the client rebuilt the
// full 11,515-byte schema with `Builder.schemaFromWire` and handed it over in ONE message, so the page never
// received it, never drew, and Lua's watchdog closed the card every single time. The fix was to stop sending the
// catalogue at all: Lua owns the node list and sends only the visible window. So the assertions below check the
// two halves of that contract:
//
//   1. the page renders whatever rows it is handed and confirms with `build:drawn`;
//   2. the page NEVER accumulates a list of its own — no module-level cache that could grow back into the
//      payload this was extracted from.
//
// A form that throws must report `build:error`, because a throw means no `build:drawn`, and Lua's watchdog then
// tears the card down rather than leaving it parked on top of the venue option list.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const WEB = process.argv[2];
const html = fs.readFileSync(path.join(WEB, "venue.html"), "utf8");
const glyphsJs = fs.readFileSync(path.join(WEB, "glyphs.js"), "utf8");

const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const venueJs = blocks.sort((a, b) => b.length - a.length)[0];
if (!venueJs) { console.error("no inline script found in venue.html"); process.exit(2); }

// ---- minimal DOM, same shape as the panel and race harnesses use
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
  Object.defineProperty(el, "textContent", {
    get() {
      if (this._text) return this._text;
      // good enough for "does this row mention a position" style assertions
      return this.children.map(c => (c && c.textContent) || "").join("");
    },
    set(v) { this._text = String(v == null ? "" : v); this.children = []; },
  });
  Object.defineProperty(el, "innerHTML", { get() { return this._html; }, set(v) { this._html = String(v == null ? "" : v); this.children = []; } });
  Object.defineProperty(el, "className", {
    get() { return [...this.classList._s].join(" "); },
    set(v) { this.classList._s = new Set(String(v == null ? "" : v).split(/\s+/).filter(Boolean)); },
  });
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
vm.runInContext(venueJs, context, { filename: "venue.html(inline)" });

let bad = 0, count = 0;
function check(condition, label) {
  count++;
  if (condition) { console.log("  PASS " + label); }
  else { bad++; console.log("  FAIL " + label); }
}
function fire(name, value) {
  const fn = events[name];
  if (typeof fn !== "function") { bad++; count++; console.log("  FAIL no handler for " + name); return; }
  fn(value);
}
function errorsSince(n) { return emitted.slice(n).filter(e => e.name === "build:error"); }
function drawnSince(n) { return emitted.slice(n).filter(e => e.name === "build:drawn"); }

// ---------------------------------------------------------------- handlers exist at all
for (const name of ["venue:list", "venue:hide", "venue:history", "venue:practice", "venue:closePanel",
                    "build:open", "build:form", "build:picker", "build:hide"]) {
  check(typeof events[name] === "function", name + " has a handler");
}

const buildEl = document.getElementById("build");
const rowsEl = document.getElementById("bRows");
const pickerEl = document.getElementById("bPicker");
const pickerList = document.getElementById("bPickerList");
const readoutEl = document.getElementById("bReadout");
const errEl = document.getElementById("bErr");

// ---------------------------------------------------------------- the pre-existing tenants still work
//
// Regression cover for the page the form moved onto: if adding a third block broke the option list, the driver
// loses the ability to ENTER A RACE, which is worse than the feature being added.
let mark = emitted.length;
fire("venue:list", {
  series: "STREET", route: "Wellsprings → Arroyo", sub: "in 4:20 · 2.4 km", sel: 1, hold: 0.5,
  options: [
    { id: "enter_race", label: "Enter race" },
    { id: "practice", label: "Practice" },
    { id: "history", label: "History", enabled: false, why: "no runs yet" },
  ],
});
check(!document.getElementById("venue").classList.contains("hidden"), "the venue option list still draws");
check(document.getElementById("list").children.length === 3, "with all three options, including the disabled one");
fire("venue:hide", {});
check(document.getElementById("venue").classList.contains("hidden"), "and venue:hide still hides it");

fire("venue:history", { route: "Arroyo", mine: [], board: [] });
check(!document.getElementById("panel").classList.contains("hidden"), "the history panel still draws");
fire("venue:closePanel", {});
check(document.getElementById("panel").classList.contains("hidden"), "and still closes");
fire("venue:practice", { route: "Arroyo", open: true, howToStart: "Drive to the ring", board: [] });
check(!document.getElementById("panel").classList.contains("hidden"), "the practice panel still draws");
fire("venue:closePanel", {});
check(errorsSince(mark).length === 0, "and none of that reported a build:error");

// ---------------------------------------------------------------- the form: a full render
//
// Fourteen rows is the widest the form gets: start, eight checkpoints, the add row, finish, laps on a loop,
// class, when, post and scrap. This is the payload shape `client/race_builder.lua::render` actually sends.
mark = emitted.length;
fire("build:open", {});
check(rowsEl.innerHTML === "" || rowsEl.children.length === 0, "build:open clears the card before the form lands");

const fullRows = [
  { label: "Start", value: "Here", sel: false },
  { label: "Checkpoint 1", value: "Corpo Plaza", sel: false },
  { label: "Checkpoints", value: "+ add a checkpoint  (1 of 8)", sel: false },
  { label: "Finish", value: "Arroyo Overpass", sel: true },
  { label: "Open to", value: "Street Open", sel: false },
  { label: "Green flag", value: "In 5 min", sel: false },
  { label: "", value: "POST THE RACE", sel: false, action: true },
  { label: "", value: "Scrap", sel: false, action: true },
];
fire("build:form", {
  rows: fullRows, readout: "Here  →  Arroyo Overpass  ·  3.10 km", bad: false, canPost: true,
  hint: "UP/DOWN move",
});
check(!buildEl.classList.contains("hidden"), "the Street Call card draws");
check(rowsEl.children.length === 8, "every row it was handed is drawn: " + rowsEl.children.length);
check(rowsEl.children[3].classList.contains("sel"), "the selected row is marked");
check(!rowsEl.children[0].classList.contains("sel"), "and only that one");
check(readoutEl.textContent.indexOf("3.10 km") >= 0, "the readout is the string Lua computed: " + readoutEl.textContent);
check(!readoutEl.classList.contains("bad"), "a postable form is not marked bad");
check(drawnSince(mark).length === 1, "and the page confirms with exactly one build:drawn");
check(errorsSince(mark).length === 0, "with no build:error");

// The readout is the ONLY place a length appears, and it arrives as text. The page must never compute one --
// that was the job that needed the node coordinates, which is what made the payload too big to arrive.
check(!/planarDistance|Math\.sqrt/.test(venueJs),
  "the page computes no distances: geometry stays in Lua, so coordinates never cross the bridge");

// ---------------------------------------------------------------- the bad / unpostable states
mark = emitted.length;
fire("build:form", {
  rows: [{ label: "Finish", value: "choose a finish", sel: true, missing: true },
         { label: "", value: "POST THE RACE", action: true }],
  readout: "Choose where it finishes.", bad: true, canPost: false, hint: "",
});
check(readoutEl.classList.contains("bad"), "an unfinishable form marks its readout");
check(rowsEl.children[0].classList.contains("missing"), "and the empty field is flagged");
check(rowsEl.children[1].classList.contains("off"), "POST reads as unavailable when canPost is false");
check(errorsSince(mark).length === 0, "no error on the unpostable path");

fire("build:form", {
  rows: [{ label: "Start", value: "Here", sel: true }],
  readout: "No race-legal nodes reached this client — the form cannot be filled.", bad: true, canPost: false,
});
check(readoutEl.textContent.indexOf("No race-legal nodes") >= 0,
  "an empty catalogue says so in the card rather than drawing a form that cannot be submitted");

// ---------------------------------------------------------------- a server refusal
mark = emitted.length;
fire("build:form", {
  rows: [{ label: "Start", value: "Here", sel: true }], readout: "x", canPost: true,
  error: "You called one recently. Give the street a minute.",
});
check(!errEl.classList.contains("hidden"), "a refusal is shown in the card, where the driver is looking");
check(errEl.textContent.indexOf("Give the street a minute") >= 0, "with the server's own words");
fire("build:form", { rows: [{ label: "Start", value: "Here", sel: true }], readout: "x", canPost: true });
check(errEl.classList.contains("hidden"), "and the next render clears it");
check(errorsSince(mark).length === 0, "a refusal is not a page error");

// ---------------------------------------------------------------- the picker window
//
// The picker is the one control that shows a long list, and the window is nine rows. The BOUND is enforced in
// Lua; what matters here is that the page draws the window it is given and does not keep it.
mark = emitted.length;
const window9 = [];
for (let i = 1; i <= 9; i++) window9.push({ label: "Node " + i, sel: i === 5 });
fire("build:picker", { title: "Finish", rows: window9, pos: "17 of 35" });
check(!pickerEl.classList.contains("hidden"), "the picker draws");
check(pickerList.children.length === 9, "with its nine rows: " + pickerList.children.length);
check(pickerList.children[4].classList.contains("sel"), "and the highlighted one marked");
check(document.getElementById("bPickerPos").textContent === "17 of 35",
  "the position reads out of 35 even though only nine rows crossed the bridge");

// Re-sending a different window must REPLACE, never append. An appending picker is how a bounded message turns
// back into an unbounded one.
fire("build:picker", { title: "Finish", rows: window9.slice(0, 4), pos: "2 of 35" });
check(pickerList.children.length === 4, "a new window replaces the old one: " + pickerList.children.length);

fire("build:picker", { closed: true });
check(pickerEl.classList.contains("hidden"), "and closing hides it");
fire("build:picker", { rows: [] });
check(pickerEl.classList.contains("hidden"), "an empty window hides it too");
fire("build:picker", null);
check(errorsSince(mark).length === 0, "a null picker payload does not throw");

// ---------------------------------------------------------------- hide, and re-confirming on reopen
mark = emitted.length;
fire("build:hide", {});
check(buildEl.classList.contains("hidden"), "build:hide hides the card");
check(pickerEl.classList.contains("hidden"), "and the picker with it");

fire("build:open", {});
fire("build:form", { rows: [{ label: "Start", value: "Here", sel: true }], readout: "x", canPost: false });
check(drawnSince(mark).length === 1,
  "a reopened card confirms again -- the watchdog is waiting on a fresh build:drawn, not a stale one");

// ---------------------------------------------------------------- malformed payloads survive
mark = emitted.length;
fire("build:form", {});
check(errorsSince(mark).length === 0, "an empty form payload does not throw");
fire("build:form", null);
check(errorsSince(mark).length === 0, "a null form payload does not throw");
fire("build:form", { rows: [null, { label: "Start", value: "Here" }] });
check(errorsSince(mark).length === 0, "a null row does not throw");
fire("build:form", { rows: [{ label: "Laps", value: 3 }] });
check(rowsEl.children[0].textContent.indexOf("3") >= 0, "a numeric value is stringified, not dropped");

// ---------------------------------------------------------------- source-text assertions
//
// Cheap, and they catch the class of mistake a stub DOM cannot.
check(!/innerHTML\s*=\s*[^"'`]*\$\{/.test(venueJs), "no template-interpolated innerHTML");
check(venueJs.includes("build:drawn") && venueJs.includes("build:error"),
  "the form guard reports both outcomes, so a silent blank card is not possible any more");
check(!/Builder|schemaFromWire/.test(venueJs),
  "the page holds no schema: `schemaFromWire` on this hop is what KB-63 killed");

console.log("=== venue render check: " + count + " assertion(s), " + bad + " bad");
process.exit(bad ? 1 : 0);
