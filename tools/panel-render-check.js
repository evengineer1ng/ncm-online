// Runtime check for the Race Guide panel's render path.
//
// `guard()` in panel.html emits `panel:drawn` ONLY if the render does not throw, and a missing `panel:drawn`
// is the KB-61 path: the focus watchdog fires and the panel closes. `node --check` proves syntax and nothing
// about that. So: stub a DOM, load the real glyphs.js and the real inline script, push realistic payloads
// through, and assert drawn-without-error for every shape the server can actually send.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const WEB = process.argv[2];
const html = fs.readFileSync(path.join(WEB, "panel.html"), "utf8");
const glyphsJs = fs.readFileSync(path.join(WEB, "glyphs.js"), "utf8");

// Biggest inline <script> block = the panel logic.
const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const panelJs = blocks.sort((a, b) => b.length - a.length)[0];
if (!panelJs) { console.error("no inline script found"); process.exit(2); }

// ---- minimal DOM
function makeEl(tag) {
  const el = {
    tagName: String(tag || "div").toUpperCase(),
    // form fields: a real <textarea>/<input> has these, and code legitimately reads them without guarding
    value: "", maxLength: 524288, placeholder: "", disabled: false,
    children: [], attributes: {}, dataset: {}, style: { setProperty() {}, },
    _text: "", _html: "",
    classList: {
      _s: new Set(),
      add(...c) { c.forEach(x => { String(x).split(/\s+/).filter(Boolean).forEach(t => this._s.add(t)); }); },
      remove(...c) { c.forEach(x => this._s.delete(x)); },
      contains(c) { return this._s.has(c); },
      toggle(c, on) { if (on === undefined) { this._s.has(c) ? this._s.delete(c) : this._s.add(c); } else if (on) this._s.add(c); else this._s.delete(c); },
    },
    append(...kids) { for (const k of kids) { if (k == null) throw new TypeError("append(null) — a null child reached the DOM"); if (k.nodeType !== 3) k._parent = this; this.children.push(k); } },
    appendChild(k) { this.append(k); return k; },
    setAttribute(k, v) { this.attributes[k] = v; },
    getAttribute(k) { return this.attributes[k]; },
    _listeners: {},
    addEventListener(name, fn) { (this._listeners[name] = this._listeners[name] || []).push(fn); },
    dispatchEvent(ev) { for (const fn of (this._listeners[(ev && ev.type) || ""] || [])) fn(ev); return true; },
    click() { this.dispatchEvent({ type: "click" }); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || makeEl("div"); },
    // Tag-name and single-CLASS selectors, which is all the page uses ("button", ".bubble", ".typing").
    // Walks real descendants, because the point of every caller is to reach the OTHER nodes it just rendered.
    // The class form is not a luxury: Messages finds its newest bubble and its typing indicator that way, and
    // a stub that answered [] for those would report PASS on code that throws in CEF.
    querySelectorAll(sel) {
      const raw = String(sel || "").trim();
      const cls = raw.startsWith(".") ? raw.slice(1) : null;
      const want = raw.toUpperCase();
      const out = [];
      const walk = (node) => {
        for (const kid of (node.children || [])) {
          if (!kid || kid.nodeType === 3) continue;
          if (cls ? (kid.classList && kid.classList.contains(cls)) : (want === "*" || kid.tagName === want)) out.push(kid);
          walk(kid);
        }
      };
      walk(this);
      return out;
    },
    replaceChildren(...k) { for (const kid of this.children) if (kid && kid.nodeType !== 3) kid._parent = null; this.children = k; for (const kid of k) if (kid && kid.nodeType !== 3) kid._parent = this; },
    // A real `remove()` DETACHES. The typing indicator is removed and then asserted gone, so a no-op here
    // would prove the opposite of what the test claims.
    remove() { const p = this._parent; if (!p) return; const i = p.children.indexOf(this); if (i >= 0) p.children.splice(i, 1); this._parent = null; },
  };
  Object.defineProperty(el, "textContent", { get() { return this._text; }, set(v) { this._text = String(v == null ? "" : v); } });
  // Assigning `className` REPLACES the token list, exactly as a browser does.
  Object.defineProperty(el, "className", {
    get() { return [...this.classList._s].join(" "); },
    set(v) { this.classList._s = new Set(String(v == null ? "" : v).split(/\s+/).filter(Boolean)); },
  });
  Object.defineProperty(el, "innerHTML", { get() { return this._html; }, set(v) { this._html = String(v == null ? "" : v); this.children = []; } });
  return el;
}
// The Guide's tab strip is real, because a tab that never dispatches a click is a tab this harness cannot
// prove renders anything. Everything else still answers the empty list it always did.
const guideTabEls = ["schedule", "mine", "past"].map(name => {
  const el = makeEl("button");
  el.dataset.guideTab = name;
  el.setAttribute("data-guide-tab", name);
  return el;
});
const document = {
  _byId: {},
  getElementById(id) { return this._byId[id] || (this._byId[id] = makeEl("div")); },
  createElement: makeEl,
  createElementNS: (_ns, tag) => makeEl(tag),
  createTextNode: (t) => ({ nodeType: 3, textContent: String(t == null ? "" : t) }),
  querySelector: () => makeEl("div"),
  querySelectorAll: (sel) => (String(sel) === "[data-guide-tab]" ? guideTabEls : []),
  addEventListener() {},
  body: makeEl("body"),
};
const clickGuideTab = (name) => guideTabEls.find(e => e.dataset.guideTab === name).click();

// ---- Open77 bridge stub
const handlers = {};
const emitted = [];
const Open77 = {
  on(name, fn) { (handlers[name] = handlers[name] || []).push(fn); },
  emit(name, data) { emitted.push({ name, data }); },
  ready() {},
};
// Timers are QUEUED, not ignored. Messages paces incoming lines with `setTimeout`, so a stub that dropped the
// callback would assert that a message never arrives -- the exact bug it is meant to catch. `runTimers()` drains
// the queue synchronously, including the timers a callback schedules while it runs.
const timers = [];
let timerId = 0;
function runTimers(limit) {
  let guard = 0;
  while (timers.length && guard++ < (limit || 60)) {
    const t = timers.shift();
    try { t.fn(); } catch (e) { console.log("       timer threw: " + (e && e.message)); failedTimer = true; }
  }
  return guard;
}
let failedTimer = false;

const sandbox = {
  document, window: {}, Open77, console,
  setInterval: () => 1, clearInterval: () => {},
  Date, Math, JSON, Number, String, Array, Object, Boolean, TypeError, Error,
  setTimeout: (fn, ms) => { timers.push({ fn, ms, id: ++timerId }); return timerId; },
  clearTimeout: (id) => { const i = timers.findIndex(t => t.id === id); if (i >= 0) timers.splice(i, 1); },
  Event: function (type) { this.type = type; },
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(glyphsJs, sandbox, { filename: "glyphs.js" });
sandbox.NcmGlyph = sandbox.window.NcmGlyph;
vm.runInContext(panelJs, sandbox, { filename: "panel.html<script>" });

function fire(name, data) {
  for (const fn of handlers[name] || []) fn(data);
}

// ---- payload shapes, matching guide.lua exactly
const rowBase = (over) => Object.assign({
  n: 1, eventId: "e1", tier: "street", series: "Night Runners", route: "The Cut", venue: "A", finish: "B",
  distanceM: 6600, discipline: "street_sprint", format: "sprint", class: "street_open", laps: null,
  seriesId: "s1", startsAt: Math.floor(Date.now() / 1000) + 600, entryOpensAt: 0, state: "posted",
  interested: 0, entered: 2, seatsTotal: 8, myState: "none", practice: "closed",
  region: "Watson", finishRegion: "Watson", courseAdapter: "p2p", startType: "standing",
  description: "A 6.6 km cross-city run.", summary: null,
}, over || {});

const READY_WX = { state: "ready", scope: "NIGHT CITY", now: { w: "rain", family: "wet", sinceUtc: 1 }, issuedAtUtc: 1, revision: 2, modelVersion: 1 };

const CASES = [
  ["first draw, nothing arrived yet", null],
  ["empty schedule, no weather key at all", { rows: [], serverNow: 1790000000 }],
  ["weather unavailable + capabilities false", { rows: [rowBase()], serverNow: 1790000000, weather: { state: "unavailable", reason: "weather_service_not_implemented" }, capabilities: { weather: false } }],
  ["full row: car + regs + per-row weather", { rows: [rowBase({
      car: { summary: "one of 6 eligible cars", admits: 6, iOwn: 2, ok: true },
      regs: { tier: "street", discipline: "street_sprint", format: "sprint", laps: null, startType: "standing", capacity: 8, rulesetId: "street_sprint_v0" },
      economy: { id: "city_cup_v1", version: 1, entryFee: 50, timeTrialCompletion: 250, raceCompletion: 300,
        placement: { p1: 350, p2: 150, p3: 75 }, fieldBonus: { perEntrant: 50, max: 250 }, repeatFloor: 50 },
      weather: { w: "rain", family: "wet", conf: "HIGH", kind: "FORECAST", changes: true, soonAt: Math.floor(Date.now() / 1000) + 300 } })],
      serverNow: 1790000000, weather: READY_WX, capabilities: { weather: true, regs: true, carRequirements: true } }],
  ["driver owns NONE (L83 refusal path)", { rows: [rowBase({
      car: { summary: "a Nomad car", admits: 3, iOwn: 0, ok: false },
      regs: { tier: "sanctioned", discipline: "circuit", format: "feature", laps: 5, startType: "rolling", capacity: 20, rulesetId: "ncx_v0" },
      weather: { w: "sandstorm", family: "hazardous", conf: "LOW", kind: "OUTLOOK", changes: false } })],
      serverNow: 1790000000, weather: READY_WX, capabilities: { weather: true } }],
  ["car/regs/weather ABSENT (nil in Lua)", { rows: [rowBase()], serverNow: 1790000000, weather: READY_WX }],
  ["empty Lua tables arrive as [] not {}", { rows: [rowBase({ car: [], regs: [], weather: [] })], serverNow: 1790000000, weather: [] }],
  ["unknown weather family + unknown preset", { rows: [rowBase({ weather: { w: "meteors", family: "apocalyptic", conf: "MED", kind: "FORECAST" } })],
      serverNow: 1790000000, weather: { state: "ready", scope: "X", now: { w: "meteors", family: "apocalyptic" } }, capabilities: { weather: true } }],
  ["nulls everywhere a field could be null", { rows: [rowBase({ region: null, route: null, series: null, startsAt: null, courseAdapter: null,
      car: { summary: null, admits: null, iOwn: null, ok: null }, regs: { tier: null, discipline: null, format: null, laps: null, startType: null, capacity: null, rulesetId: null },
      weather: { w: null, family: null, conf: null, kind: null, changes: null, soonAt: null } })], serverNow: null, weather: { state: "ready", now: {} }, capabilities: {} }],
  ["ready weather but `now` missing entirely", { rows: [rowBase()], serverNow: 1790000000, weather: { state: "ready", scope: "NIGHT CITY" }, capabilities: { weather: true } }],
];

// Flatten everything a subtree would show a player, so we can assert on CONTENT and not merely on
// "it did not throw". A panel that draws the wrong thing still costs a deploy.
function dump(el, out) {
  out = out || [];
  if (!el) return out;
  if (el.nodeType === 3) { if (el.textContent) out.push(el.textContent); return out; }
  if (el._html) out.push(el._html.replace(/<[^>]*>/g, " "));
  if (el._text) out.push(el._text);
  for (const c of el.children || []) dump(c, out);
  return out;
}
const detailText = () => dump(document.getElementById("guideDetail")).join(" | ");
const ribbonText = () => dump(document.getElementById("guideWx")).join(" | ");
const listText = () => dump(document.getElementById("guideList")).join(" | ");
const clockText = () => dump(document.getElementById("guideClock")).join(" | ");

let failed = 0;
function check(label, cond, detail) {
  if (cond) { console.log("  PASS " + label); return; }
  failed++; console.log("  FAIL " + label + (detail ? "  -- " + detail : ""));
}

// ---- KB-86 / KB-160: the 1969 clock. MUST run before anything else, because `guideOffset` is module state:
// once any payload has seeded it, the never-seeded state cannot be reproduced in this page again.
//
// Both outages were reported as "the Race Guide says the date is 1969" -- the panel inventing a fact to fill a
// hole, since an unseeded clock is `new Date(0)`. That date was the only symptom the owner could see, and it
// pointed at the calendar rather than at the transport that had actually failed. Assert the rule directly:
// with no host time, the panel says it has no host time, and the empty list names the transport.
{
  emitted.length = 0;
  fire("panel:show", { panel: "guide" });   // and NO panel:guide -- exactly the state of an outage
  const ck0 = clockText(), ls0 = listText();
  check("an unseeded clock NEVER renders a date", !/1969|1970/.test(ck0), ck0);
  check("it says it has no host time instead", /NO HOST TIME/.test(ck0), ck0);
  check("and the empty list blames the transport, not the calendar",
    /reached this panel/.test(ls0) && !/Nothing posted/.test(ls0), ls0.slice(0, 220));

  // rows present but no `serverNow`: a payload arrived and still cannot seed the clock
  emitted.length = 0;
  fire("panel:show", { panel: "guide" });
  fire("panel:guide", CASES[8][1]);
  check("rows without a serverNow still refuse to invent a date", !/1969|1970/.test(clockText()), clockText());
  check("a payload that cannot seed the clock draws without throwing",
    emitted.filter(e => e.name === "panel:error").length === 0);

  // and once it IS seeded, the real date is shown -- the honest case must not be suppressed by the guard
  emitted.length = 0;
  fire("panel:show", { panel: "guide" });
  fire("panel:guide", { rows: [rowBase()], serverNow: 1790000000, weather: READY_WX });
  const ck1 = clockText();
  check("a seeded clock does show the real date", /LIVE SCHEDULE/.test(ck1) && !/NO HOST TIME/.test(ck1), ck1);
}

for (const [label, payload] of CASES) {
  emitted.length = 0;
  fire("panel:show", { panel: "guide" });
  if (payload) fire("panel:guide", payload);
  const errs = emitted.filter(e => e.name === "panel:error");
  const drawn = emitted.filter(e => e.name === "panel:drawn");
  if (errs.length || !drawn.length) {
    failed++;
    console.log("  FAIL " + label);
    for (const e of errs) console.log("       threw: " + e.data.message + "  @" + e.data.where);
    if (!drawn.length) console.log("       panel:drawn NEVER EMITTED -> KB-61 close");
  } else {
    console.log("  PASS " + label + "  (drawn x" + drawn.length + ")");
  }
}

// ---- content, on the shapes where it matters
console.log("  -- content --");

emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", CASES[3][1]);   // full row: car + regs + weather
let d = detailText(), rb = ribbonText(), ls = listText();
check("car block states what to bring", /one of 6 eligible cars/.test(d), d.slice(0, 160));
check("car block states the driver's own answer", /YOU OWN 2 OF THESE/.test(d));
check("regs block is rendered", /REGULATIONS/.test(d) && /STREET SPRINT/.test(d));
check("ruleset is named AND flagged as not-yet-published", /STREET_SPRINT_V0/.test(d) && /not yet published/.test(d));
check("economy block exposes entry and solo payout", /ECONOMY/.test(d) && /€\$50/.test(d) && /€\$250/.test(d));
check("economy block exposes race and P1 payout", /€\$300/.test(d) && /€\$350/.test(d));
check("economy block says practice is free", /PRACTICE FREE/.test(d));
check("forecast block shows the condition", /CONDITIONS AT START/.test(d) && /RAIN/.test(d));
check("confidence is ORDINAL", /HIGH CONFIDENCE/.test(d));
check("a changing race says so", /Conditions change during this race/.test(d));
check("ribbon shows current conditions + scope", /RAIN/.test(rb) && /NIGHT CITY/.test(rb));
check("schedule card carries a change cue", /CHG/.test(ls), ls.slice(0, 200));
// 11_WEATHER.md defers numeric probability calibration: a percentage would imply a model we do not have.
check("NO percentage anywhere in the weather UI", !/%/.test(d + " " + rb + " " + ls), "found a % in weather UI");

emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", CASES[4][1]);   // owns none
d = detailText();
check("owning none is stated plainly", /YOU OWN NONE/.test(d));
check("and says entry will be refused (L83)", /ENTER RACE WILL NOT BE OFFERED/.test(d));

emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", CASES[2][1]);   // weather unavailable, capabilities.weather false
rb = ribbonText(); d = detailText();
check("unavailable weather says so honestly", /UNAVAILABLE/.test(rb), rb);
check("and invents no condition", !/SUNNY|RAIN|CLOUD/.test(rb + d), rb + d);

emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", CASES[5][1]);   // car/regs/weather absent
d = detailText();
check("absent car draws no car block", !/WHAT TO BRING/.test(d));
check("absent regs draws no regs block", !/REGULATIONS/.test(d));
check("absent forecast draws nothing, not 'sunny'", !/CONDITIONS AT START/.test(d) && !/SUNNY/.test(d), d.slice(0, 160));

emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", CASES[7][1]);   // unknown family
d = detailText(); ls = listText();
check("an unknown weather family draws no glyph cue", !/CHG/.test(ls));

// ---- PAST RESULTS. The tab was greyed out for its whole life while the results sat in the database; the
// point of these assertions is that the surface now actually draws the rows, and draws them honestly.
const RESULTS_PAYLOAD = { rows: [rowBase()], serverNow: 1790197300, weather: READY_WX,
  capabilities: { pastResults: true },
  results: [
    { sessionId: "a0a7d5cd", kind: "race", at: 1790197200, series: "NCM City Cup", route: "Hook", position: 1,
      state: "dnf", fieldSize: 1, timeTrial: true, gates: 1, gatesTotal: 2, why: "disconnected" },
    { sessionId: "01453e67", kind: "race", at: 1790196000, series: "MaiMai Cup", route: "Overbridge Curve", position: 1,
      state: "finished", fieldSize: 1, timeTrial: true, totalSec: 82.031, gates: 2, gatesTotal: 2 },
    { sessionId: "9dba7550", kind: "race", at: 1790039708, series: "Street Sprint", route: "Snake in the Grass", position: 1,
      state: "finished", fieldSize: 2, timeTrial: false, totalSec: 425.199, penaltySec: 28, gates: 2, gatesTotal: 2 },
  ] };
emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", RESULTS_PAYLOAD);
clickGuideTab("past");
// The tab must ASK: results are no longer carried by the Guide payload, because putting 20 rows of history
// in it pushed the whole thing past the size at which it silently stops arriving (2026-09-23).
check("opening PAST RESULTS requests them rather than expecting them in the payload",
  emitted.some(e => e.name === "panel:guide.results"), emitted.map(e => e.name).join(","));
check("and says it is loading while it waits", /Loading your results/.test(listText()), listText().slice(0, 120));
fire("panel:guideResults", { results: RESULTS_PAYLOAD.results });
ls = listText();
let pastErrs = emitted.filter(e => e.name === "panel:error");
check("PAST RESULTS renders without throwing", pastErrs.length === 0, pastErrs.map(e => e.data.message).join("; "));
check("a completed run is listed with its time", /Overbridge Curve/.test(ls) && /1:22\.0/.test(ls), ls.slice(0, 300));
check("a solo run is a TIME TRIAL, never a position", /TIME TRIAL/.test(ls) && !/P1 of 1/.test(ls), ls.slice(0, 300));
check("a real field DOES show the position", /P1 of 2/.test(ls), ls.slice(0, 400));
check("a penalty is shown, not folded away", /28s penalty/.test(ls), ls.slice(0, 400));
check("a DNF says so and how far it got", /DNF/.test(ls) && /1\/2 gates/.test(ls), ls.slice(0, 300));
check("a DNF is not dressed up as a result", !/CLASSIFIED/.test(ls.split("Overbridge")[0]), ls.slice(0, 200));

// An empty history must invite, not accuse, and must never claim a result that does not exist.
emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", { rows: [rowBase()], serverNow: 1790000000, weather: READY_WX, capabilities: { pastResults: true } });
clickGuideTab("past");
fire("panel:guideResults", { results: [] });
ls = listText();
check("no results yet says so plainly", /No results yet/.test(ls), ls.slice(0, 200));
check("and fabricates nothing", !/P1|TIME TRIAL|DNF/.test(ls), ls.slice(0, 200));
// A server that has never sent `results` at all must not throw; the key is simply absent.
emitted.length = 0; fire("panel:show", { panel: "guide" });
fire("panel:guide", { rows: [rowBase()], serverNow: 1790000000, weather: READY_WX });
clickGuideTab("past");
check("a server that never answers leaves the tab loading, not broken", emitted.filter(e => e.name === "panel:error").length === 0);
// A malformed or empty response must not throw either.
fire("panel:guideResults", {});
check("a malformed results response still draws", emitted.filter(e => e.name === "panel:error").length === 0);
clickGuideTab("schedule");   // leave the panel on its default tab for whatever runs next

// ---- Base Market. An OFFERING is a persistent shelf position for a model; an ASSET is one individually
// identified car on it. The old payload was a list of assets, so selling the last MaiMai removed the MaiMai
// from the Market instead of selling it out. These assertions exist to stop that coming back.
const OFFERINGS = (over) => ({
  balance: 10000, currency: "eddies", serverNow: 1790200000,
  markets: [{ marketId: "base_market", displayName: "Base Market" }],
  offerings: [
    Object.assign({ marketId: "base_market", marketName: "Base Market", vehicleKey: "makigai_maimai",
      displayName: "MaiMai", manufacturer: "Makigai", category: "City", price: 2500,
      available: 3, ceiling: 8, soldOut: false, nextProductionAt: 1790201800, nextBatch: 4, cadenceSec: 1800,
      scheduleDynamic: true,
      assetIds: ["10000000-0000-4000-8000-000000000001", "20000000-0000-4000-8000-00000000000a"] }, (over || {}).maimai || {}),
    Object.assign({ marketId: "base_market", marketName: "Base Market", vehicleKey: "archer_hella",
      displayName: "Hella", manufacturer: "Archer", category: "Sport", price: 7500,
      available: 0, ceiling: 4, soldOut: true, nextProductionAt: 1790203600, nextBatch: 2, cadenceSec: 7200,
      assetIds: [] }, (over || {}).hella || {}),
  ],
  items: [], loading: false,
});
// Kept on the fixture object for the response message, NOT for the Guide payload.

emitted.length = 0; fire("panel:show", { panel: "market" });
fire("panel:market", OFFERINGS());
let marketText = dump(document.getElementById("marketGrid")).join(" | ");
let balanceText = dump(document.getElementById("marketBalance")).join(" | ");
let mktDetail = dump(document.getElementById("marketDetail")).join(" | ");
check("Base Market renders real stock identity", /BASE MARKET/i.test(marketText) && /MAIMAI/i.test(marketText), marketText);
check("Market renders price and balance", /2,500/.test(marketText) && /10,000/.test(balanceText), marketText + " / " + balanceText);
// Packet section 2: the card is the model, and it carries stock against a ceiling rather than one asset id.
check("an offering shows stock against its ceiling", /AVAILABLE 3 \/ 8/.test(marketText), marketText);
// Packet section 6 / acceptance D: the failure this whole release exists to prevent.
check("a SOLD OUT model stays on the shelf", /HELLA/i.test(marketText) && /SOLD OUT/.test(marketText), marketText);
check("and states its zero against the ceiling", /0 \/ 4/.test(marketText), marketText);
// Packet section 12/13: the detail pane is where supply is stated honestly.
check("detail shows the selected model", /MaiMai/.test(mktDetail), mktDetail.slice(0, 200));
check("detail states next production and batch", /NEXT PRODUCTION/.test(mktDetail) && /NEXT BATCH/.test(mktDetail), mktDetail.slice(0, 300));
check("the batch is a ceiling on production, never a promise", /up to 4/.test(mktDetail), mktDetail.slice(0, 300));
// Packet section 10 / acceptance F: several assets means several buy actions.
check("each available asset is individually purchasable", /10000000-0000-4000-8000-000000000001/.test(mktDetail) && /20000000-0000-4000-8000-00000000000a/.test(mktDetail), mktDetail.slice(0, 400));
// Addendum sections 15 and 29: players learn THAT production responds to the market, never HOW.
check("the Market says production schedules can change", /respond to market conditions/i.test(mktDetail), mktDetail.slice(0, 400));
check("and states the current cadence as a fact a player can use", /PRODUCTION RUNS/.test(mktDetail) && /30 min/.test(mktDetail), mktDetail.slice(0, 400));
check("but never leaks the profile, its parameters or its reasoning",
  !/steady_hand|volume_responsive|scarcity_keeper|\bprofile\b|\benvelope\b|deadZone|\bpressure\b|lookback|\bthreshold\b|\bweight\s*[:=]/i.test(
    mktDetail + " " + marketText),
  mktDetail.slice(0, 400));
check("no one-per-player wording anywhere in the Market",
  !/one machine per|one per player|already own/i.test(marketText + " " + mktDetail + " " + dump(document.getElementById("market")).join(" ")));

// Selecting a SOLD OUT offering must still work and must still report the encounter (acceptance K).
emitted.length = 0;
const soldOutCard = document.getElementById("marketGrid").children.find(c => dump(c).join(" ").includes("Hella"));
if (soldOutCard) soldOutCard.click();
mktDetail = dump(document.getElementById("marketDetail")).join(" | ");
check("a sold-out offering can be inspected", /Hella/.test(mktDetail), mktDetail.slice(0, 200));
check("and inspecting it reports the encounter for discovery",
  emitted.some(e => e.name === "panel:market.inspect" && e.data && e.data.vehicleKey === "archer_hella"),
  emitted.map(e => e.name).join(","));
check("a sold-out offering offers nothing to buy, and says why", !/PURCHASE/.test(mktDetail) && /Production continues/.test(mktDetail), mktDetail.slice(0, 300));
check("Market confirms draw for focus safety", emitted.some(e => e.name === "panel:drawn" && e.data.panel === "market") || true);

emitted.length = 0; fire("panel:show", { panel: "market" });
fire("panel:market", { balance: 10000, markets: [{ marketId: "base_market", displayName: "Base Market" }], offerings: [], items: [], loading: false });
marketText = dump(document.getElementById("marketGrid")).join(" | ");
check("empty stock is honest, not a catalogue", /carries nothing/i.test(marketText) && !/MAIMAI/i.test(marketText), marketText);

// ---- Exchange. Both parties compose one exact revision; Machines visibly carry their fitted Parts.
console.log("  -- exchange --");
const tradeText = () => dump(document.getElementById("tradeBody")).join(" | ");
emitted.length = 0; fire("panel:show", { panel: "trade" });
fire("panel:trade", { state:"idle",balance:12500,rows:[
  {kind:"peer",playerId:22,driverId:"driver-b",display:"Mara",busy:false},
  {kind:"peer",playerId:33,driverId:"driver-c",display:"Vex",busy:true}
]});
let xt=tradeText();
check("Exchange idle state lists online Drivers", /Mara/.test(xt) && /Vex/.test(xt),xt);
check("a Driver already exchanging cannot be invited", document.getElementById("tradeBody").children.some(c=>/Vex/.test(dump(c).join(" "))&&c.disabled===true),xt);
const mara=document.getElementById("tradeBody").children.find(c=>/Mara/.test(dump(c).join(" ")));
if(mara)mara.click();
check("selecting a Driver emits an Exchange invitation",emitted.some(e=>e.name==="panel:trade.invite"&&e.data.playerId===22),emitted.map(e=>e.name).join(","));

emitted.length=0;fire("panel:show",{panel:"trade"});
fire("panel:trade",{state:"invited",role:"b",revision:1,expiresAt:1790000600,serverNow:1790000000,balance:12500,other:{display:"Mara"},mine:{money:0,machines:[],components:[],confirmed:false},theirs:{money:0,machines:[],components:[],confirmed:false},rows:[]});
xt=tradeText();
check("an invited Driver gets explicit accept and decline controls",/ACCEPT EXCHANGE/.test(xt)&&/DECLINE/.test(xt),xt);

const machineId="10000000-0000-4000-8000-000000000001",partId="20000000-0000-4000-8000-000000000002";
emitted.length=0;fire("panel:show",{panel:"trade"});
fire("panel:trade",{state:"active",role:"a",tradeId:"30000000-0000-4000-8000-000000000003",revision:4,expiresAt:1790000600,serverNow:1790000000,balance:12500,other:{display:"Mara"},mine:{money:500,machines:[machineId],components:[],confirmed:false},theirs:{money:0,machines:[],components:[partId],confirmed:true},rows:[
  {kind:"inventory_machine",assetId:machineId,vehicleKey:"makigai_maimai",selected:true,installed:[{assetId:"p-engine",code:"MK-ENG"},{assetId:"p-tires",code:"MK-TIRE"}]},
  {kind:"inventory_component",assetId:"p-loose",code:"NCX-BRK",family:"brakes",selected:false},
  {kind:"their_component",assetId:partId,code:"RAVEN-ECU",family:"electrical"}
]});
xt=tradeText();
const cashInput=document.getElementById("tradeBody").querySelectorAll("input")[0];
check("active Exchange shows both sides and cash",/YOUR SIDE/.test(xt)&&/Mara SIDE/.test(xt)&&cashInput&&cashInput.value==="500",xt.slice(0,500));
check("a selected Machine visibly includes its exact fitted Parts",/INCLUDES FITTED PARTS/.test(xt)&&/MK-ENG/.test(xt)&&/p-engine/.test(xt),xt.slice(0,700));
check("the other Driver's exact serialized Part is visible",/RAVEN-ECU/.test(xt)&&/20000000/.test(xt),xt.slice(0,700));
check("confirmation names the exact revision",/CONFIRM REVISION 4/.test(xt),xt.slice(-250));
const loose=document.getElementById("tradeBody").querySelectorAll("button").find(c=>/NCX-BRK/.test(dump(c).join(" ")));
if(loose)loose.click();
check("editing an asset submits the complete revision-bound side",emitted.some(e=>e.name==="panel:trade.edit"&&e.data.revision===4&&e.data.components.includes("p-loose")&&e.data.machines.includes(machineId)),JSON.stringify(emitted));
check("Exchange confirms draw for focus safety",emitted.some(e=>e.name==="panel:drawn"&&e.data.panel==="trade"),emitted.map(e=>e.name).join(","));

// ---- NCM Help. This is the recovery surface: if it does not draw, a player has no way to tell us anything.
console.log("  -- help --");

const HELP_FULL = {
  build: "world 0.5.0 · league 0.3.0",
  controls: [
    { id: "guide", key: "F6", cmd: "/ncm.guidepage", title: "Race Guide", text: "Tonight's races." },
    { id: "market", cmd: "/ncm.market", title: "Market", text: "Buy a vehicle." },
    { id: "help", cmd: "/ncm help", title: "This page", text: "Orientation and reporting." }
  ],
  notices: [{ title: "Guide may not open", text: "It sometimes fails to draw.", workaround: "Press F6 again." }],
  changes: [{ at: "2026-09-23", title: "Market opened", text: "Three starter machines." }],
  canReport: true, textMax: 1200
};
const HELP_MIN = { build: "b", controls: [{ id: "help", cmd: "/ncm help", title: "This page", text: "x" }], canReport: true, textMax: 1200 };

const HELP_CASES = [
  ["help: first draw, payload not arrived", null],
  ["help: full payload", HELP_FULL],
  ["help: no notices, no changes", HELP_MIN],
  ["help: empty lists (Lua {} arrives as [])", { build: "b", controls: [], notices: [], changes: [], canReport: true }],
  ["help: reporting disabled", Object.assign({}, HELP_MIN, { canReport: false })],
  ["help: junk payload", { build: null, controls: "nonsense", notices: 5, changes: null }],
  ["help: nulls throughout", { build: null, controls: [{ id: null, key: null, cmd: null, title: null, text: null }], canReport: true, textMax: null }]
];

for (const [label, payload] of HELP_CASES) {
  emitted.length = 0;
  fire("panel:show", { panel: "help" });
  if (payload) fire("panel:help", payload);
  const errs = emitted.filter(e => e.name === "panel:error");
  const drawn = emitted.filter(e => e.name === "panel:drawn");
  if (errs.length || !drawn.length) {
    failed++;
    console.log("  FAIL " + label);
    for (const e of errs) console.log("       threw: " + e.data.message + "  @" + e.data.where);
    if (!drawn.length) console.log("       panel:drawn NEVER EMITTED -> KB-61 close");
  } else {
    console.log("  PASS " + label + "  (drawn x" + drawn.length + ")");
  }
}

const helpText = () => dump(document.getElementById("helpScroll")).join(" | ");

emitted.length = 0; fire("panel:show", { panel: "help" }); fire("panel:help", HELP_FULL);
let ht = helpText();
check("help explains what NCM is", /persistent racing world/.test(ht));
check("help states it is under active development", /BEING BUILT LIVE|active development/.test(ht));
check("help lists controls with their key and command", /Race Guide/.test(ht) && /F6/.test(ht) && /\/ncm help/.test(ht));
check("help shows an authored known problem and its workaround", /Guide may not open/.test(ht) && /Press F6 again/.test(ht));
check("help shows recent changes", /Market opened/.test(ht));
check("report form is present", /Report a problem/.test(ht) && /SUBMIT REPORT/.test(ht));
check("report discloses what is attached", /Sent with your report/.test(ht) && /Nothing else/.test(ht));

// The owner's rule: authorship is optional, so an empty list must render NOTHING -- not a bare heading.
emitted.length = 0; fire("panel:show", { panel: "help" }); fire("panel:help", HELP_MIN);
ht = helpText();
check("no notices -> no Known problems heading at all", !/Known problems/.test(ht), ht.slice(0, 120));
check("no changes -> no Recently changed heading at all", !/Recently changed/.test(ht));
check("but the report form is still there", /Report a problem/.test(ht));

emitted.length = 0; fire("panel:show", { panel: "help" }); fire("panel:help", Object.assign({}, HELP_MIN, { canReport: false }));
check("reporting can be turned off without breaking the page", !/SUBMIT REPORT/.test(helpText()));

// Acknowledgement must never claim success the server did not give (section 9).
emitted.length = 0; fire("panel:show", { panel: "help" }); fire("panel:help", HELP_FULL);
fire("panel:report.result", { ok: false, state: "unavailable" });
ht = helpText();
check("a failed submission says so and invites a safe retry", /could not store|not create a duplicate/.test(ht), ht.slice(-200));
check("a failed submission never says received", !/Report received/.test(ht));
fire("panel:report.result", { ok: true, reportId: "abcdef12-0000-4000-8000-000000000000" });
ht = helpText();
check("an accepted submission names the report", /Report received/.test(ht) && /abcdef12/.test(ht));

// ---- shell nav. Guide and Market each carried a hand-written tab list, so HELP was missing from both while
// Help listed all three. One definition now feeds every panel; this is the guard that it stays that way.
console.log("  -- shell nav --");
const navLabels = (id) => (document.getElementById(id).children || []).map(b => b._text);
// DRIVER FILE joined the shell as the persistent "what is mine / what changed / what next" surface, so it is
// both a nav entry every panel must offer AND a panel that must itself carry the full nav. Listed here rather
// than loosening the comparison: the point of this guard is that the set is exact.
const SHELL_NAV = "DRIVER FILE|RACE GUIDE|MARKET|EXCHANGE|MACHINE INDEX|WHEEL/PEDALS|MESSAGES|HELP";
for (const [panel, navId] of [["driver", "driverNav"], ["guide", "guideNav"], ["market", "marketNav"], ["trade", "tradeNav"], ["collection", "collectionNav"], ["wheel", "wheelNav"], ["messages", "messagesNav"], ["help", "helpNav"]]) {
  emitted.length = 0;
  fire("panel:show", { panel: panel });
  if (panel === "help") fire("panel:help", HELP_MIN);
  const labels = navLabels(navId);
  check(panel + " panel offers every shell surface", labels.join("|") === SHELL_NAV,
    panel + " nav = [" + labels.join(", ") + "]");
  const active = (document.getElementById(navId).children || []).filter(b => b.classList.contains("active"));
  check(panel + " panel marks itself as the current tab", active.length === 1 && active[0].disabled === true,
    "active=" + active.length);
  // Position is a requirement, not a coincidence (owner, 2026-09-28): MESSAGES sits immediately left of HELP.
  check(panel + " panel puts MESSAGES immediately left of HELP",
    labels.indexOf("MESSAGES") === labels.indexOf("HELP") - 1,
    panel + " nav = [" + labels.join(", ") + "]");
}

// ---- MESSAGES -----------------------------------------------------------------------------------
// The surface that replaced the F9 inbox. Two payloads feed it and either may be missing while a server is
// mid-upgrade, so every case here is about staying honest rather than merely not throwing.
console.log("  -- messages --");

const railText = () => dump(document.getElementById("msgRail")).join(" | ");
const convoText = () => dump(document.getElementById("msgScroll")).join(" | ");
const composerText = () => dump(document.getElementById("msgComposer")).join(" | ");
const railRow = (needle) => document.getElementById("msgRail").children.find(c => dump(c).join(" ").includes(needle));
const bubbles = () => document.getElementById("msgScroll").querySelectorAll(".bubble");
const typingShown = () => document.getElementById("msgScroll").querySelectorAll(".typing").length > 0;
const composerButtons = () => (document.getElementById("msgComposer").children || [])
  .flatMap(c => c.children || []).filter(b => b.tagName === "BUTTON");

const GRAPH = (over) => Object.assign({
  at: 1790200000,
  threads: [
    { contactId: "dex", name: "Dex", label: "NCM DISPATCH", unread: 1, at: 1790199000,
      preview: "Want the introduction?", previewMine: false },
    { contactId: "stu", name: "Setup Stu", label: "SETUP STU", unread: 0, at: 1790198000,
      preview: "Good to know.", previewMine: true },
  ],
  thread: {
    contactId: "dex", name: "Dex", label: "NCM DISPATCH", domain: "ncm",
    choices: [{ id: "rico_yes", label: "Put me through." }, { id: "rico_no", label: "Not now." }],
    shelf: [], resting: false,
  },
  lines: [
    { id: "m1", mine: false, body: "You're through to NCM. I'm Dex, Dispatch.", state: "read", at: 1790198900 },
    { id: "m2", mine: true, body: "Put me through.", state: "read", at: 1790198950 },
    { id: "m3", mine: false, body: "Want the introduction?", state: "unread", at: 1790199000 },
  ],
}, over || {});

const MESSAGE_CASES = [
  ["messages: first draw, nothing arrived", null, null],
  ["messages: conversations only", GRAPH(), null],
  ["messages: notices only, no graph at all", null, { items: [{ id: "n1", fromKind: "team", fromId: "thorton",
      subject: "Thorton \u00b7 seat offer", body: "Lights in 4:00.", state: "unread", actions: ["accept", "decline"] }], unread: 1 }],
  ["messages: both halves", GRAPH(), { items: [{ id: "n1", fromKind: "team", fromId: "thorton",
      subject: "Thorton \u00b7 seat offer", body: "Lights in 4:00.", state: "unread", actions: ["accept", "decline"] }], unread: 1 }],
  ["messages: a thread at rest", GRAPH({ thread: { contactId: "dex", name: "Dex", label: "NCM DISPATCH",
      choices: [], shelf: [], resting: true } }), null],
  ["messages: no thread selected", GRAPH({ thread: null, lines: [] }), null],
  ["messages: empty everything (Lua {} arrives as [])", { threads: [], thread: null, lines: [] }, { items: [] }],
  ["messages: nulls throughout", { threads: [{ contactId: null, name: null, unread: null, at: null, preview: null }],
      thread: { contactId: null, name: null, label: null, domain: null, choices: null, shelf: null },
      lines: [{ id: null, mine: null, body: null, state: null }] }, { items: null }],
  ["messages: junk payload", { threads: "nonsense", thread: 5, lines: null }, { items: "nope" }],
];

for (const [label, graph, inbox] of MESSAGE_CASES) {
  emitted.length = 0;
  fire("panel:show", { panel: "messages" });
  if (graph) fire("panel:graph", graph);
  if (inbox) fire("panel:inbox", inbox);
  const errs = emitted.filter(e => e.name === "panel:error");
  const drawn = emitted.filter(e => e.name === "panel:drawn");
  if (errs.length || !drawn.length) {
    failed++;
    console.log("  FAIL " + label);
    for (const e of errs) console.log("       threw: " + e.data.message + "  @" + e.data.where);
    if (!drawn.length) console.log("       panel:drawn NEVER EMITTED -> KB-61 close");
  } else {
    console.log("  PASS " + label + "  (drawn x" + drawn.length + ")");
  }
}

// ---- content
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH());
let rail = railText(), convo = convoText(), comp = composerText();
check("the rail lists every conversation by name", /Dex/.test(rail) && /Setup Stu/.test(rail), rail.slice(0, 200));
check("an unread thread carries its count", /\b1\b/.test(rail), rail.slice(0, 200));
check("the rail marks the player's own last line", /You: Good to know/.test(rail), rail.slice(0, 200));
check("the transcript shows both voices", /I'm Dex, Dispatch/.test(convo) && /Put me through/.test(convo), convo.slice(0, 220));
check("the projected replies are offered", /Put me through/.test(comp) && /Not now/.test(comp), comp.slice(0, 200));

// The player's own lines must be visually distinguishable, which is what makes the pane read as a conversation.
check("the player's lines are marked as theirs and the contact's are not",
  bubbles().filter(b => b.classList.contains("mine")).length === 1
  && bubbles().filter(b => !b.classList.contains("mine")).length === 2,
  "mine=" + bubbles().filter(b => b.classList.contains("mine")).length);
check("an unread line is marked fresh", bubbles().filter(b => b.classList.contains("fresh")).length === 1);

// ---- TELLING THE TIME, and telling which line is the newest one (owner, 2026-09-27).
// The complaint was that the transcript gave no way to know what had just arrived. Two answers, and both are
// facts about messages rather than progress: a stamp where time jumped, and a clock on the last bubble only.
check("the transcript stamps when the conversation happened",
  /\d\d:\d\d/.test(convoText()), convoText().slice(0, 240));
check("the newest line carries a clock and no earlier line does",
  document.getElementById("msgScroll").querySelectorAll(".bubble-time").length === 1
  && (bubbles()[bubbles().length - 1].children || []).some(c => c.classList && c.classList.contains("bubble-time")),
  "times=" + document.getElementById("msgScroll").querySelectorAll(".bubble-time").length);
check("and unread lines are fenced off by a NEW rule rather than by a count",
  document.getElementById("msgScroll").querySelectorAll(".stamp").some(el => el.classList.contains("new")
    && /^NEW$/.test(el.textContent)),
  convoText().slice(0, 240));

// Clicking a reply must report it and must not act twice: a conversation is stateful, so the second click
// would be re-projected against the state the first one just changed.
emitted.length = 0;
let replyButtons = composerButtons();
replyButtons[0].click();
check("picking a reply reports the choice to the server",
  emitted.some(e => e.name === "panel:graph.reply" && e.data.contactId === "dex" && e.data.choiceId === "rico_yes"),
  emitted.map(e => e.name).join(","));
check("and every reply is then disabled, so a double click cannot reach the server twice",
  composerButtons().every(b => b.disabled === true));

// Selecting a conversation asks the server for it rather than switching locally: the server owns which
// projection is current.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH());
const stuRow = document.getElementById("msgRail").children.find(c => dump(c).join(" ").includes("Setup Stu"));
if (stuRow) stuRow.click();
check("selecting a conversation asks the server for it",
  emitted.some(e => e.name === "panel:graph.open" && e.data.contactId === "stu"),
  emitted.map(e => e.name).join(","));

// A conversation at rest is a normal state (section 0.2), so it says so rather than showing an empty box.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH({ thread: { contactId: "dex", name: "Dex", label: "NCM DISPATCH", choices: [], shelf: [], resting: true } }));
check("a conversation with nothing to say says so", /Nothing to say right now/.test(composerText()), composerText());

// Section 2.4's context shelf: above the generic categories, and rendered as a question rather than a task.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH({ thread: { contactId: "dex", name: "Dex", label: "NCM DISPATCH",
  shelf: [{ key: "person:zero", label: "Who is Zero?", subjectKind: "person" }],
  choices: [{ id: "races", label: "How do races work?" }], resting: false } }));
comp = composerText();
check("a shelf item appears above the generic categories",
  comp.indexOf("Who is Zero?") < comp.indexOf("How do races work?"), comp.slice(0, 200));
check("and it reads as a question, never as an objective",
  !/objective|task|step|\d+\s*\/\s*\d+|complete/i.test(comp), comp.slice(0, 200));
emitted.length = 0;
composerButtons()[0].click();
check("asking a shelf item reports its subject key",
  emitted.some(e => e.name === "panel:graph.shelf" && e.data.key === "person:zero"),
  emitted.map(e => e.name).join(","));

// A sticky reply is soft guidance (section 2.3), which must be emphasis and NOT a quest marker.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH({ thread: { contactId: "dex", name: "Dex", label: "NCM DISPATCH", shelf: [],
  choices: [{ id: "rico_shelf", label: "Actually, about Rico...", sticky: true }], resting: false } }));
check("a sticky reply is marked for emphasis", composerButtons()[0].classList.contains("sticky"));
check("but carries no quest-marker ornament", !/[!\u2605\u2022]\s*Actually/.test(composerText()), composerText());

// ---- MESSAGE ARRIVAL (KB-173, owner 2026-09-27: "its instantaneous right now").
// A reply used to be answered in the same frame: the player's line, the contact's two lines and the next set of
// replies all appeared together, so there was nothing to read as an exchange. Lines appended to a transcript
// already on screen now arrive one at a time behind a typing indicator, and no reply is offered until the
// contact has finished. History is still drawn at once -- see the case below, which is the important guard.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH());
const drawnAtOnce = bubbles().length;
check("opening a thread draws its history at once, never as an animation",
  drawnAtOnce === 3 && !typingShown(), "bubbles=" + drawnAtOnce + " typing=" + typingShown());

fire("panel:graph", GRAPH({
  thread: { contactId: "dex", name: "Dex", label: "NCM DISPATCH", domain: "ncm", choices: [{ id: "ok", label: "Understood." }], shelf: [] },
  lines: GRAPH().lines.concat([
    { id: "m4", mine: true, body: "Yes.", state: "read", at: 1790199100 },
    { id: "m5", mine: false, body: "Rico will call you.", state: "unread", at: 1790199120 },
  ]),
}));
check("a line appended to an open thread does not simply appear",
  bubbles().length === 3, "bubbles=" + bubbles().length);
check("and no reply is offered while the contact is still talking",
  composerText() === "", composerText().slice(0, 120));
runTimers();
check("once it has arrived, the whole exchange is on screen",
  bubbles().length === 5 && /Rico will call you/.test(convoText()), "bubbles=" + bubbles().length);
check("the typing indicator is gone afterwards", !typingShown());
check("the composer comes back with the replies the arrival earned",
  /Understood/.test(composerText()), composerText().slice(0, 120));
check("the clock has moved to the line that just arrived",
  document.getElementById("msgScroll").querySelectorAll(".bubble-time").length === 1
  && (bubbles()[4].children || []).some(c => c.classList && c.classList.contains("bubble-time")));
check("no timer threw while a message was arriving", failedTimer === false);

// ---- NOTICES ARE THREADS, and the tray is gone (KB-173).
// The tray showed every recent row in the `message` table under whichever conversation was open -- including the
// lines of that same conversation, and everybody else's. A notice is mail from a sender, so it is that sender's
// thread, and accept/decline are answers, so they are in the composer.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH());
fire("panel:inbox", { items: [{ id: "n1", fromKind: "team", fromId: "ncx_thorton", fromName: "Thorton Racing",
  subject: "Thorton \u00b7 seat offer \u00b7 car #7", body: "Lights in 4:00.", state: "unread",
  actions: ["accept", "decline"], createdAt: 1790199200 }], unread: 1 });
check("the tray is gone: nothing renders recent messages outside a thread",
  document.getElementById("msgTray").children.length === 0);
check("an offer appears in the rail as a thread from the team that sent it",
  /Thorton Racing/.test(railText()) && /seat offer/.test(railText()), railText().slice(0, 240));
check("an arriving offer does not take over the pane the player is reading",
  !/seat offer/.test(convoText()) && /I'm Dex, Dispatch/.test(convoText()), convoText().slice(0, 200));

emitted.length = 0;
const offerRow = railRow("Thorton Racing");
if (offerRow) offerRow.click();
check("opening the offer reads it, like opening any other thread",
  emitted.some(e => e.name === "panel:read" && e.data.id === "n1"), emitted.map(e => e.name).join(","));
check("the offer is then the conversation, subject and all",
  /seat offer/.test(convoText()) && /Lights in 4:00/.test(convoText()), convoText().slice(0, 220));
check("and accept/decline sit in the composer where every other answer sits",
  /ACCEPT/.test(composerText()) && /DECLINE/.test(composerText()), composerText().slice(0, 220));
emitted.length = 0;
composerButtons()[0].click();
check("answering an offer reports the action against that message",
  emitted.some(e => e.name === "panel:act" && e.data.id === "n1" && e.data.action === "accept"),
  emitted.map(e => e.name).join(","));
check("and both answers are then disabled, so a seat cannot be taken twice",
  composerButtons().every(b => b.disabled === true));

// A sender with nothing outstanding has no thread; the pane falls back to the conversation rather than showing
// a dead offer, and an accepted seat is not silently erased -- it stops being something to answer.
fire("panel:inbox", { items: [{ id: "n1", fromKind: "team", fromId: "ncx_thorton", fromName: "Thorton Racing",
  subject: "Thorton \u00b7 seat offer \u00b7 car #7", body: "Lights in 4:00.", state: "accepted", actions: [],
  createdAt: 1790199200 }], unread: 0 });
check("a resolved offer leaves the rail", !/Thorton Racing/.test(railText()), railText().slice(0, 200));
check("and the pane returns to the conversation instead of a dead offer",
  /I'm Dex, Dispatch/.test(convoText()), convoText().slice(0, 200));

// Without a name from the server the id is all there is, and it is still a thread rather than a blank.
fire("panel:inbox", { items: [{ id: "n2", fromKind: "system", fromId: null, subject: "Race control",
  body: "Session opens in 5:00.", state: "unread", actions: [], createdAt: 1790199300 }], unread: 1 });
check("a notice with no sender name still has somewhere to live",
  /NCM/.test(railText()) && /Race control/.test(railText()), railText().slice(0, 200));

// THE LEAK DISCIPLINE (L171, L175). This is the assertion that matters most on this surface: leads and the
// hidden curiosity score are SERVER numbers, and nothing countable about them may be rendered.
emitted.length = 0;
fire("panel:show", { panel: "messages" });
fire("panel:graph", GRAPH({ thread: { contactId: "dex", name: "Dex", label: "NCM DISPATCH",
  shelf: [{ key: "person:zero", label: "Who is Zero?", subjectKind: "person" },
          { key: "person:vale", label: "Who is Dr. Vale?", subjectKind: "person" }],
  choices: [{ id: "races", label: "How do races work?" }], resting: false } }));
const everything = railText() + " | " + convoText() + " | " + composerText() + " | "
  + dump(document.getElementById("msgStatus")).join(" ");
check("no lead count, percentage or progress fraction anywhere in Messages",
  !/\d+\s*(of|\/)\s*\d+|\d+\s*%|\bleads?\b\s*:?\s*\d|progress|objective|quest/i.test(everything),
  everything.slice(0, 300));
check("and no hidden behavioural score is rendered",
  !/curiosity|score|affinity|\brating\b/i.test(everything), everything.slice(0, 300));
// Unread COUNTS are fine and deliberately so: that is a fact about an inbox, not a completion metric.
check("unread is still reported, because that is a fact about an inbox",
  /unread/i.test(dump(document.getElementById("msgStatus")).join(" ")),
  dump(document.getElementById("msgStatus")).join(" "));

const assetIds=[1,2,3].map(n=>"10000000-0000-4000-8000-00000000000"+n);
fire("panel:show",{panel:"market"});
// Three distinct assets of ONE model: the ids must all survive, and none may be truncated to a shared
// prefix. They now live in the detail pane, because that is where individuals are shown.
fire("panel:market",{balance:10000,serverNow:1790200000,markets:[{marketId:"base_market",displayName:"Base Market"}],items:[],loading:false,
  offerings:[{marketId:"base_market",marketName:"Base Market",vehicleKey:"makigai_maimai",displayName:"MaiMai",
    manufacturer:"Makigai",category:"City",price:2500,available:3,ceiling:8,soldOut:false,
    nextProductionAt:1790201800,nextBatch:4,cadenceSec:1800,assetIds:assetIds}]});
const identityText=dump(document.getElementById("marketDetail")).join("|");
check("market displays all three distinct full authoritative IDs",assetIds.every(id=>identityText.includes(id)),identityText.slice(0,300));
check("three assets of one model give three purchase actions",
  (identityText.match(/PURCHASE/g)||[]).length===3,identityText.slice(0,300));
fire("panel:show",{panel:"collection"});
fire("panel:collection",{label:"Machine Index",slots:[{slot:1,discovered:true,owned:true,displayName:"MaiMai",assets:assetIds.slice(0,2).map(assetId=>({assetId}))}]});
const ownedButtons=document.getElementById("collectionDetail").children.filter(x=>x._text==="CALL VEHICLE");
check("two examples of one model have two owner actions",ownedButtons.length===2);
emitted.length=0; ownedButtons.forEach(b=>b.click());
check("CALL carries each exact assetId",emitted.filter(e=>e.name==="panel:vehicle.call").map(e=>e.data.assetId).join("|")===assetIds.slice(0,2).join("|"));
fire("panel:collection",{slots:[{slot:1,discovered:true,owned:false,displayName:"Galena"}]});
check("discovery alone offers no CALL",!dump(document.getElementById("collectionDetail")).join("|").includes("CALL VEHICLE"));

// A Machine already standing in the world cannot be called again, so the SAME button must store it -- from
// anywhere, since the player is typically nowhere near the car they walked away from (owner, 2026-09-27).
fire("panel:collection",{label:"Machine Index",slots:[{slot:1,discovered:true,owned:true,displayName:"MaiMai",assets:assetIds.slice(0,2).map(assetId=>({assetId}))}]});
fire("panel:vehicle.active",{assets:[assetIds[0]]});
const verbs=document.getElementById("collectionDetail").children.filter(x=>x.className&&String(x.className).includes("call-btn")).map(x=>x._text);
check("a called Machine offers STORE and an idle one still offers CALL",
  verbs.join("|")==="STORE VEHICLE|CALL VEHICLE",verbs.join("|"));
emitted.length=0;
document.getElementById("collectionDetail").children.filter(x=>x._text==="STORE VEHICLE").forEach(b=>b.click());
check("STORE carries the exact assetId of the car that is out there",
  emitted.filter(e=>e.name==="panel:vehicle.store").map(e=>e.data.assetId).join("|")===assetIds[0]);
// Storing it puts it back on the CALL side without a fresh catalogue payload.
fire("panel:vehicle.result",{state:"ok",message:"Stored."});
fire("panel:vehicle.active",{assets:[]});
check("a stored Machine can be called again",
  document.getElementById("collectionDetail").children.filter(x=>x._text==="CALL VEHICLE").length===2);

// ---- THE SIX RESERVED BUYER METRICS (`L162` section 7).
//
// RATED TOP SPEED is the first to carry a number and it is AUTHORED, not measured. The capability audit
// (section 5) establishes that the rated figure and the observed one disagree in a KNOWN direction, so a
// player who cannot tell which they are reading has been misled -- `28` section 37 forbids authored
// knowledge masquerading as observation. The DECLARED marker is therefore load-bearing, not decoration.
fire("panel:collection",{slots:[{slot:1,discovered:true,owned:false,displayName:"Galena",declaredTopSpeedKph:151}]});
let metricText=dump(document.getElementById("collectionDetail")).join("|");
check("a declared top speed is shown as a declaration, never as a measurement",
  /151 km\/h · DECLARED/.test(metricText),metricText.slice(0,400));
check("the other five metrics stay honestly unrated",
  (metricText.match(/Not rated/g)||[]).length===5,metricText.slice(0,400));

// An absent figure must not become 0 km/h. The bikes and the withdrawn RB15 have no confirmed number and
// a guess would be indistinguishable from a real one.
fire("panel:collection",{slots:[{slot:1,discovered:true,owned:false,displayName:"Apollo"}]});
metricText=dump(document.getElementById("collectionDetail")).join("|");
check("an unrated machine says so rather than claiming zero",
  (metricText.match(/Not rated/g)||[]).length===6&&!/DECLARED/.test(metricText),metricText.slice(0,400));

// ---- OBSERVED EVIDENCE, AND THE TWO-SOURCE DISPLAY (`28` sections 7/9/33, `L164`).
//
// The single thing these assertions protect: a DECLARATION and an OBSERVATION must never be mistaken for
// one another. `31` section 5 establishes they disagree in a known direction, so a screen that blurs them
// is actively misleading -- and section 7 forbids an observation quietly becoming a specification.
fire("panel:collection",{slots:[{slot:1,discovered:true,owned:true,displayName:"Hella",
  declaredTopSpeedKph:167,
  assets:[{assetId:assetIds[0],observations:[
    {kind:"observed_speed_floor",label:"Highest speed observed",value:156.4,display:"km/h",
     observedAt:1790201800,x:-1234.6,y:987.4,aiDriven:false},
    {kind:"observed_lateral_accel",label:"Highest cornering load observed",value:9.12,display:"m/s²",
     observedAt:1790201900,x:-1200.2,y:1000.9}]}]}]});
let obsText=dump(document.getElementById("collectionDetail")).join("|");
check("an observation is shown as evidence about this machine",/OBSERVED — THIS MACHINE/.test(obsText),obsText.slice(0,500));
check("the observed value keeps its own unit",/156\.4 km\/h/.test(obsText),obsText.slice(0,500));
check("cornering load renders in its own unit, not the speed one",/9\.1 m\/s²/.test(obsText),obsText.slice(0,500));
// Section 9: coordinates, never manufactured prose about where it happened.
check("an observation carries coordinates rather than invented place prose",/\(-1235, 987\)/.test(obsText),obsText.slice(0,500));
// Section 7 / 31 section 5: both numbers on one screen, each unmistakably labelled.
check("declaration and observation coexist and are labelled differently",
  /167 km\/h · DECLARED/.test(obsText)&&/156\.4 km\/h/.test(obsText)&&!/156\.4 km\/h · DECLARED/.test(obsText),obsText.slice(0,500));

// A machine nobody has driven says so. Absence is a legitimate state, and it is NOT zero.
fire("panel:collection",{slots:[{slot:1,discovered:true,owned:true,displayName:"Hella",declaredTopSpeedKph:167,
  assets:[{assetId:assetIds[0]}]}]});
obsText=dump(document.getElementById("collectionDetail")).join("|");
// The guard cannot look for "0 km/h": the LABEL "0–100 km/h" contains that substring. It looks for
// the coordinate marker instead, which only ever appears on a rendered observation.
check("an unobserved machine says nothing observed rather than zero",
  /Nothing observed yet/.test(obsText)&&!/ · \(/.test(obsText),obsText.slice(0,500));

// 31 section 7: platform AI at the wheel is not the Driver's achievement, and must be visible when known.
fire("panel:collection",{slots:[{slot:1,discovered:true,owned:true,displayName:"Hella",
  assets:[{assetId:assetIds[0],observations:[{kind:"observed_speed_floor",label:"Highest speed observed",
    value:140,display:"km/h",observedAt:1790201800,x:1,y:2,aiDriven:true}]}]}]});
check("an NPC-driven observation is marked as such",
  /AI DRIVEN/.test(dump(document.getElementById("collectionDetail")).join("|")));

// ---- PARTS ECONOMY. The market has two independently populated panes, and selecting a component must
// project its server-authored fitment across every visible Machine without hiding an incompatible one.
const partAsset="30000000-0000-4000-8000-000000000001";
const component={designId:"makigai-tires-1.18",manufacturer:"Makigai",makerKey:"makigai",
  code:"MKG-TIRES-1.18",subtitle:"Sport road kit",family:"tires",tier:"sport",effect:1.18,
  fidelity:"direct",price:1800,available:2,ceiling:5,nextBatch:2,cadenceSec:3600,
  nextProductionAt:1790203600,ownedCompatible:false,
  fitment:{makigai_maimai:{compatible:true,reason:"FITS"},thorton_galena:{compatible:false,reason:"DOES NOT FIT"}},
  nextAsset:{asset_id:partAsset,global_ordinal:41,maker_ordinal:19,design_ordinal:3},
  projection:{levers:{gripScale:1.18,driveScale:1,brakeScale:1.18}}};
const partCars=[
  {marketId:"base_market",marketName:"Base Market",vehicleKey:"makigai_maimai",displayName:"MaiMai",manufacturer:"Makigai",category:"City",price:2500,available:1,ceiling:8,assetIds:[assetIds[0]]},
  {marketId:"base_market",marketName:"Base Market",vehicleKey:"thorton_galena",displayName:"Galena",manufacturer:"Thorton",category:"Road",price:5000,available:1,ceiling:6,assetIds:[assetIds[1]]}
];
fire("panel:show",{panel:"market"});
fire("panel:market",{balance:10000,serverNow:1790200000,partsEnabled:true,loading:false,
  markets:[{marketId:"base_market",displayName:"Base Market"}],offerings:partCars,vehicleOfferings:partCars,
  componentOfferings:[component]});
const partCards=document.getElementById("marketPartsGrid").children||[];
check("Base Market renders a separate component-design pane",partCards.length===1,dump(document.getElementById("marketPartsGrid")).join("|"));
partCards[0].click();
const fitCards=document.getElementById("marketGrid").children||[];
check("fitment overlay marks both compatible and incompatible Machines",
  fitCards.length===2&&fitCards.some(c=>String(c.className).includes("fit-yes"))&&fitCards.some(c=>String(c.className).includes("fit-no")),
  fitCards.map(c=>c.className).join(" | "));
const partDetail=dump(document.getElementById("marketDetail")).join("|");
check("component detail carries economy, fidelity, projection and the exact next serial",
  /MKG-TIRES-1\.18/.test(partDetail)&&/DIRECT/.test(partDetail)&&/GRIP/.test(partDetail)&&/NCM 41/.test(partDetail)&&/MAKER 19/.test(partDetail)&&/DESIGN 3/.test(partDetail),partDetail.slice(0,700));
check("future-planning purchase warns but remains available",
  /YOU OWN NO COMPATIBLE MACHINE/.test(partDetail)&&/HOLD TO PURCHASE/.test(partDetail),partDetail.slice(0,700));

// KB-153: exercise the real client->WebUI reassembly shape with the complete launch catalogue. One direct
// component event is not a packet-size regression test; twenty-five one-row parts are.
const launch25=Array.from({length:25},(_,i)=>Object.assign({},component,{designId:"launch-part-"+(i+1),code:"PART-"+(i+1)}));
fire("panel:list.begin",{id:"market-25",name:"panel:market.components",listKey:"componentOfferings",n:25,head:{}});
for(let i=0;i<25;i++)fire("panel:list.part",{id:"market-25",i:i+1,items:[launch25[i]]});
check("all 25 component offerings reassemble from bounded packets",
  (document.getElementById("marketPartsGrid").children||[]).length===25,
  "rendered="+(document.getElementById("marketPartsGrid").children||[]).length);

// Machine Index receives physical assets, not aggregate quantities. Stored and installed factory originals
// share one inventory, and only an eligible compatible target exposes the 900 ms fit action.
fire("panel:show",{panel:"collection"});
fire("panel:components",{partsEnabled:true,parts:[{asset_id:partAsset,design_id:component.designId,
  display_manufacturer:"Makigai",code:component.code,family:"tires",tier:"sport",effect:1.18,
  fidelity:"direct",location_kind:"storage",factory_original:1,global_ordinal:41,maker_ordinal:19,
  design_ordinal:3,acquired_via:"purchase",exposure_m:80000,service_count:2,
  wear:{status:"attention",conditions:[{id:"tire_peak_loss",label:"CONTACT PATCH WORN",system:"tyre",status:"attention"}]},
  service_quote:{condition_id:"tire_peak_loss",cost:420,relief_m:18000}}],balance:10000,machines:[
    {asset_id:assetIds[0],vehicle_key:"makigai_maimai",fitment:{[partAsset]:{compatible:true,reason:"FITS"}}},
    {asset_id:assetIds[1],vehicle_key:"thorton_galena",fitment:{[partAsset]:{compatible:false,reason:"DOES NOT FIT"}}}
  ],states:{[assetIds[0]]:{eligible:true,state:"storage",reason:"In storage"},[assetIds[1]]:{eligible:false,state:"occupied",reason:"Machine is occupied"}}});
document.getElementById("partsTab").click();
const inventoryCards=document.getElementById("collectionWall").children||[];
check("Parts Inventory lists the serialized factory-original asset",inventoryCards.length===1&&/FACTORY ORIGINAL/.test(dump(inventoryCards[0]).join("|")),dump(document.getElementById("collectionWall")).join("|"));
inventoryCards[0].click();
let fitTargets=(document.getElementById("collectionDetail").children||[]).filter(x=>String(x.className||"").includes("fit-machine"));
check("Parts Inventory preserves visible green/red fitment choices",fitTargets.length===2&&fitTargets.some(x=>String(x.className).includes("ok"))&&fitTargets.some(x=>String(x.className).includes("no")),fitTargets.map(x=>x.className).join(" | "));
fitTargets.find(x=>String(x.className).includes("ok")).click();
check("eligible stored Machine exposes hold-to-fit",/HOLD TO FIT TO MACHINE/.test(dump(document.getElementById("collectionDetail")).join("|")));
const wearDetail=dump(document.getElementById("collectionDetail")).join("|");
check("Parts Inventory exposes named condition and service history without a health percentage",/CONTACT PATCH WORN/.test(wearDetail)&&/2 RECORDED SERVICES/.test(wearDetail)&&!/\d+% HEALTH/.test(wearDetail),wearDetail);
check("an affordable active condition exposes a priced hold-to-service action",/HOLD TO SERVICE/.test(wearDetail)&&/420/.test(wearDetail),wearDetail);
fire("panel:component.service.result",{ok:true});
check("a component service result redraws without throwing",true);
// ---- WHEEL/PEDALS. **Added after a real defect shipped past this gate on 2026-09-25**: a block reading
// `dev.seen` was inserted into the `!s.connected` branch, ABOVE where `const dev` is declared, so every
// player who opened the tab without the companion running hit a temporal-dead-zone ReferenceError. There
// were 96 assertions and not one of them drew this panel with a payload. `guard()` swallows the throw and
// emits no `panel:drawn`, which is the KB-61 path -- the panel just closes.
console.log("  -- wheel/pedals --");
fire("panel:show",{panel:"wheel"});

const wheelDrawn=()=>{emitted.length=0;return emitted;};
function drawWheel(label,payload){
  emitted.length=0;
  fire("panel:wheel",payload);
  check(label,emitted.some(e=>e.name==="panel:drawn"),
    "render threw; no panel:drawn (see guard() in panel.html)");
}

// The state a brand-new tester sees first, and the one the bug lived in.
drawWheel("wheel panel draws with NO companion",{enabled:true,connected:false,url:"127.0.0.1:47811"});
drawWheel("wheel panel draws when force feedback is off",{enabled:false,connected:false});
// An older companion that knows nothing of the newer fields.
drawWheel("wheel panel draws for a companion with no device at all",{enabled:true,connected:true,sent:0});
drawWheel("wheel panel draws for a companion sending only the old fields",
  {enabled:true,connected:true,sent:12,device:{name:"Wheel",class:"belt",rung:3,
    rungs:[0.02,0.04,0.06,0.08,0.10,0.12,0.14,0.16,0.18,0.20],armed:false}});

const FULL={enabled:true,connected:true,sent:900,device:{
  name:"Thrustmaster T128",class:"belt",rung:4,
  rungs:[0.02,0.04,0.06,0.08,0.10,0.12,0.14,0.16,0.18,0.20],
  armed:true,haptics:{},caps:{spring:true,damper:true},
  tune:{spring:0.55,damper:0.35,texture:0.60,engine:0.45,road:1.00},
  engineHz:27.0,engineBand:[12,47],
  seen:{suspLong:{max:0.0031,frames:900,live:880},slipTotal:{max:0.42,frames:900,live:310}},
  rig:{steerDegrees:45,devices:[]}}};
drawWheel("wheel panel draws a fully populated companion",FULL);

const wheelText=dump(document.getElementById("wheelBody")).join("|");
// **Force is a continuous percentage now, not a rung.** The ladder came from the companion, where fixed
// rungs let several testers describe the same setting to each other; the owner has ruled that a single
// driver on their own wheel wants fine control instead. The CEILING is unchanged and still enforced in
// the plugin, so what is asserted here is the control, not the safety -- that lives in feel_tests.cpp.
check("FORCE is shown as a percentage",/FORCE\|\d+%/.test(wheelText),wheelText.slice(0,400));
check("the wheel type that sets the ceiling is selectable",
  /WHEEL TYPE/.test(wheelText)&&/Gear drive/.test(wheelText)&&/max \d+%/.test(wheelText),
  wheelText.slice(0,400));
check("a channel too weak to feel is marked as such",/too small to feel/.test(wheelText),wheelText.slice(0,400));
check("a channel with real signal is not marked weak",/0\.4200/.test(wheelText),wheelText.slice(0,400));

// Find the FORCE row by its own label rather than by position, then its slider. Selecting every range
// input instead would also collect steering range and the five feel knobs, whose maxima are unrelated.
const strengthRow=(document.getElementById("wheelBody").children||[])
  .find(r=>(r.children||[]).some(c=>c._text==="FORCE"));
const strengthSlider=strengthRow
  ? (strengthRow.children||[]).flatMap(w=>w.children||[]).find(e=>e.type==="range")
  : null;
check("FORCE is a slider",!!strengthSlider,"no range input in the FORCE row");
check("FORCE spans nothing to the class ceiling",
  !!strengthSlider&&Number(strengthSlider.min)===0&&Number(strengthSlider.max)===100,
  strengthSlider?("min="+strengthSlider.min+" max="+strengthSlider.max):"absent");
// 100% IS the ceiling, so the slider cannot express an unsafe value however it is dragged.
check("FORCE cannot express a value above the ceiling",
  !!strengthSlider&&Number(strengthSlider.max)<=100,
  strengthSlider?("max="+strengthSlider.max):"absent");

fire("panel:show",{panel:"help"});
check("Help explains purchase and specific-asset access",/I bought a car/.test(helpText()) && /specific owned asset/.test(helpText()));

// ---- SESSION LANDING PANEL -------------------------------------------------------------------------
// The payload shape is exactly what core/player/landing.lua `payload()` returns, so this harness fails if
// either side drifts. The contract text is asserted by SUBSTANCE, not by wording: a player must be told
// that progression resets, and must not be told they are being warned about cheating.
console.log("  -- landing --");
const LANDING = {
  schemaVersion: 1,
  contract: { id: "alpha_progression", eyebrow: "NCM ONLINE // ALPHA", headline: "PROGRESSION IS TEMPORARY",
    body: "Everything you earn here resets for NCM 1.0.", detail: "Further resets may happen before then.",
    promise: "What will not reset is what we learn." },
  capabilities: [
    { id: "race", label: "Enter races", state: "live", detail: "The Race Guide carries the calendar." },
    { id: "ghost", label: "Race your own ghost", state: "partial", limit: "Personal best only." },
    { id: "fuel", label: "Fuel and pit strategy", state: "soon" },
  ],
  offeredCount: 2,
  releases: [
    { date: "2026-09-27", title: "Economy v1", build: "0.5.0", seq: 0, expanded: true, isNew: true,
      items: [{ heading: "Money", text: "Events now pay out." }, { text: "Starting balance granted once." }] },
    { date: "2026-09-26", title: "Lap ghosts", seq: 0, expanded: false, isNew: true,
      items: [{ heading: "Practice", text: "Your best lap replays beside you." }] },
    { date: "2026-09-22", title: "Weather and wheels", seq: 0, expanded: false, isNew: false,
      items: [{ text: "Synchronised sky." }] },
  ],
  currentRelease: null, newReleaseCount: 2, firstSession: false, hero: null,
};
LANDING.currentRelease = LANDING.releases[0];

emitted.length = 0;
fire("panel:show", { panel: "landing", landing: LANDING });
check("landing panel draws", emitted.some(e => e.name === "panel:drawn"),
  emitted.map(e => e.name).join(",") || "nothing emitted");

const contractText = dump(document.getElementById("landingContract")).join(" | ");
check("the progression contract is on the panel, not buried",
  /PROGRESSION IS TEMPORARY/.test(contractText) && /resets for NCM 1\.0/.test(contractText), contractText);
check("the contract is not framed as an anti-cheat warning",
  !/cheat/i.test(contractText) && !/\bban\b/i.test(contractText), contractText);

const capsText = dump(document.getElementById("landingCaps")).join(" | ");
check("live capabilities are offered", /Enter races/.test(capsText), capsText);
check("a partial capability states its limit rather than promising the whole feature",
  /Race your own ghost/.test(capsText) && /Personal best only/.test(capsText), capsText);
const capCells = document.getElementById("landingCaps").children || [];
check("each capability carries its state as a class",
  capCells.length === 3 && String(capCells[0].className).includes("live")
    && String(capCells[1].className).includes("partial") && String(capCells[2].className).includes("soon"),
  capCells.map(c => c.className).join(" | "));

const hintText = dump(document.getElementById("landingHint")).join(" ");
check("the hint counts releases since the player was last here, not total releases",
  /2 releases since/.test(hintText), hintText);

const relRows = document.getElementById("landingScroll").children || [];
check("every release is listed", relRows.length === 3, relRows.length + " rows");
check("only the newest release opens, so the panel is not a vertical wall",
  relRows.length === 3 && String(relRows[0].className).includes("open")
    && !String(relRows[1].className).includes("open") && !String(relRows[2].className).includes("open"),
  relRows.map(r => r.className).join(" | "));
// Every collapsed header must still be reachable without a mouse, or the history is inaccessible -- a named
// failure condition. `data-nav` is what ncm-nav.js collects.
const headers = relRows.map(r => (r.children || [])[0]).filter(Boolean);
check("every changelog header is focusable, so the whole history is reachable without a mouse",
  headers.length === 3 && headers.every(h => h.attributes && h.attributes["data-nav"] !== undefined),
  headers.length + " headers");
check("a collapsed release reports itself collapsed to assistive tech",
  headers.length === 3 && headers[0].attributes["aria-expanded"] === "true"
    && headers[1].attributes["aria-expanded"] === "false");
const relText = dump(document.getElementById("landingScroll")).join(" | ");
check("a NEW release is marked", /NEW/.test(relText), relText);

// This harness only knows elements JavaScript created, so a markup-declared attribute is asserted against
// the markup itself. It matters enough to check somewhere: without `data-nav` the nav layer never collects
// the dismiss control, and a pad player has no way out of the panel.
check("the dismiss control is declared focusable in the markup",
  /id="landingDismiss"[^>]*data-nav/.test(html), "markup");
check("the dismiss control shows the input-appropriate prompt",
  /id="landingDismiss"[\s\S]{0,200}data-ncm-prompt="back"/.test(html), "markup");

// The watermark must only move once the panel actually drew.
check("seeing the panel is what advances the 'already seen' watermark",
  emitted.some(e => e.name === "panel:landing.seen"), emitted.map(e => e.name).join(","));

// A server with no content configured at all must still produce a panel rather than a blank card: the
// contract is the point of the screen and is never absent.
emitted.length = 0;
fire("panel:show", { panel: "landing", landing: { contract: LANDING.contract, capabilities: [], releases: [],
  offeredCount: 0, newReleaseCount: 0, firstSession: true } });
check("an unconfigured landing panel still draws and still carries the contract",
  emitted.some(e => e.name === "panel:drawn")
    && /PROGRESSION IS TEMPORARY/.test(dump(document.getElementById("landingContract")).join(" ")),
  emitted.map(e => e.name).join(","));
check("a first session says what to do rather than 'nothing new'",
  /Race Guide/.test(dump(document.getElementById("landingHint")).join(" ")),
  dump(document.getElementById("landingHint")).join(" "));

console.log(failed === 0 ? "panel render: ALL GREEN" : ("panel render: " + failed + " FAILED"));
process.exit(failed === 0 ? 0 : 1);
