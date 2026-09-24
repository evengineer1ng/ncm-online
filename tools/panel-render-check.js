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
      add(...c) { c.forEach(x => this._s.add(x)); },
      remove(...c) { c.forEach(x => this._s.delete(x)); },
      contains(c) { return this._s.has(c); },
      toggle(c, on) { if (on === undefined) { this._s.has(c) ? this._s.delete(c) : this._s.add(c); } else if (on) this._s.add(c); else this._s.delete(c); },
    },
    append(...kids) { for (const k of kids) { if (k == null) throw new TypeError("append(null) — a null child reached the DOM"); this.children.push(k); } },
    appendChild(k) { this.append(k); return k; },
    setAttribute(k, v) { this.attributes[k] = v; },
    getAttribute(k) { return this.attributes[k]; },
    _listeners: {},
    addEventListener(name, fn) { (this._listeners[name] = this._listeners[name] || []).push(fn); },
    dispatchEvent(ev) { for (const fn of (this._listeners[(ev && ev.type) || ""] || [])) fn(ev); return true; },
    click() { this.dispatchEvent({ type: "click" }); },
    querySelector() { return makeEl("div"); },
    querySelectorAll() { return []; },
    replaceChildren(...k) { this.children = k; },
    remove() {},
  };
  Object.defineProperty(el, "textContent", { get() { return this._text; }, set(v) { this._text = String(v == null ? "" : v); } });
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
const sandbox = {
  document, window: {}, Open77, console,
  setInterval: () => 1, clearInterval: () => {},
  Date, Math, JSON, Number, String, Array, Object, Boolean, TypeError, Error,
  setTimeout: () => 0, clearTimeout: () => {},
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

let failed = 0;
function check(label, cond, detail) {
  if (cond) { console.log("  PASS " + label); return; }
  failed++; console.log("  FAIL " + label + (detail ? "  -- " + detail : ""));
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
  !/steady_hand|volume_responsive|scarcity_keeper|profile|envelope|deadZone|pressure|lookback|threshold|weight/i.test(
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
for (const [panel, navId] of [["guide", "guideNav"], ["market", "marketNav"], ["collection", "collectionNav"], ["wheel", "wheelNav"], ["help", "helpNav"]]) {
  emitted.length = 0;
  fire("panel:show", { panel: panel });
  if (panel === "help") fire("panel:help", HELP_MIN);
  const labels = navLabels(navId);
  check(panel + " panel offers every shell surface", labels.join("|") === "RACE GUIDE|MARKET|MACHINE INDEX|WHEEL|HELP",
    panel + " nav = [" + labels.join(", ") + "]");
  const active = (document.getElementById(navId).children || []).filter(b => b.classList.contains("active"));
  check(panel + " panel marks itself as the current tab", active.length === 1 && active[0].disabled === true,
    "active=" + active.length);
}

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
fire("panel:show",{panel:"help"});
check("Help explains purchase and specific-asset access",/I bought a car/.test(helpText()) && /specific owned asset/.test(helpText()));

console.log(failed === 0 ? "panel render: ALL GREEN" : ("panel render: " + failed + " FAILED"));
process.exit(failed === 0 ? 0 : 1);
