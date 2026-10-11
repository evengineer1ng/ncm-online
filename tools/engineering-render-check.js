// Runtime check for the Engineering panel (ncm_engineering/web/engineering.html).
//
// The page emits `eng:drawn` only if a render does not throw; a missing `eng:drawn` is the KB-61 path (the cursor
// goes back, the panel closes). So: stub a DOM, run the real inline script, push the shapes the server sends --
// a damaged car with quotes, a car being worked on, the repair verdict with four section rolls (the ink ceremony),
// parts in storage / installed / add-on -- and assert every one drew.
//   node tools/engineering-render-check.js ncm/online/resources/ncm_engineering/web
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(process.argv[2], "engineering.html"), "utf8");
const js = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).sort((a, b) => b.length - a.length)[0];

function makeEl(tag) {
  const el = {
    tagName: String(tag || "div").toUpperCase(), disabled: false, children: [], attributes: {}, dataset: {},
    style: { setProperty() {} }, _text: "", _html: "", _listeners: {},
    classList: { _s: new Set(), add(...c) { c.forEach(x => this._s.add(x)); }, remove(...c) { c.forEach(x => this._s.delete(x)); },
      contains(c) { return this._s.has(c); }, toggle(c, on) { if (on === undefined ? !this._s.has(c) : on) this._s.add(c); else this._s.delete(c); } },
    append(...kids) { for (const k of kids) { if (k == null) throw new TypeError("append(null)"); this.children.push(k); } },
    setAttribute(k, v) { this.attributes[k] = v; },
    addEventListener(n, fn) { (this._listeners[n] = this._listeners[n] || []).push(fn); },
    fire(n, ev) { for (const fn of (this._listeners[n] || [])) fn(ev || { preventDefault() {} }); },
    all() { const out = []; const walk = (x) => { for (const k of x.children || []) { if (k && k.tagName) { out.push(k); walk(k); } } }; walk(this); return out; },
  };
  Object.defineProperty(el, "textContent", { get() { return this._text; }, set(v) { this._text = String(v == null ? "" : v); } });
  Object.defineProperty(el, "className", { get() { return [...this.classList._s].join(" "); }, set(v) { this.classList._s = new Set(String(v || "").split(/\s+/).filter(Boolean)); } });
  Object.defineProperty(el, "innerHTML", { get() { return this._html; }, set(v) { this._html = String(v || ""); this.children = []; } });
  return el;
}
const tabs = ["service", "parts", "build", "workshop"].map(t => { const b = makeEl("button"); b.dataset.tab = t; return b; });
const byId = {};
const document = {
  getElementById(id) { return byId[id] || (byId[id] = makeEl("div")); },
  createElement: makeEl, createElementNS: (_n, t) => makeEl(t),
  createTextNode: (t) => ({ nodeType: 3, textContent: String(t) }),
  querySelectorAll(sel) { return sel === "nav button" ? tabs : []; },
};
const handlers = {}, emitted = [];
const Open77 = { on(n, fn) { handlers[n] = fn; }, emit(n, d) { emitted.push({ n, d }); } };
const timers = [];
const ctx = { document, Open77, console, Math, Date, Number, String, Object, Array, JSON, Set,
  performance: { now: () => 0 }, requestAnimationFrame: () => 0, cancelAnimationFrame() {},
  setTimeout: (fn) => { timers.push(fn); return timers.length; }, clearTimeout() {}, setInterval: () => 0 };
// the markup starts the dock and the job sheet hidden, as engineering.html does
document.getElementById("dock").classList.add("hidden");
document.getElementById("sheet").classList.add("hidden");
vm.createContext(ctx);
vm.runInContext(js, ctx);

let passed = 0;
function check(label, ok) { if (!ok) { console.error("FAIL " + label); process.exit(1); } passed++; console.log("  PASS " + label); }
const send = (n, d) => { if (!handlers[n]) throw new Error("no handler " + n); handlers[n](d); };
const drawnCount = () => emitted.filter(e => e.n === "eng:drawn").length;
const main = byId.main;
const text = () => main.all().map(e => e.textContent).join(" | ");

check("the page says it is ready", emitted.some(e => e.n === "eng:ready"));
send("eng:show", { tab: "service" });
check("an empty open draws (eng:drawn)", drawnCount() === 1);

const car = { assetId: "10000000-0000-4000-8000-000000000002", vehicleKey: "galena", name: "Galena", maker: "Thorton", stored: true,
  severity: 0.34, areas: [{ area: "chassis", label: "Chassis", value: 0.445 }, { area: "glass", label: "Glass", value: 1, count: 7 },
    { area: "tires", label: "Tyres", value: 0.25, count: 1 }],
  selfQuote: { cost: 150, materials: 150, labour: 0, benchSeconds: 29 }, shopQuote: { cost: 900, materials: 300, labour: 600, benchSeconds: 29 },
  work: { grade: "fair", provider: "self", sections: [{ section: "grip", delta: 0.012 }, { section: "drive", delta: -0.02 }, { section: "brake", delta: 0 }, { section: "drag", delta: -0.05 }],
    scalars: { gripScale: 1.012, driveScale: 0.98, brakeScale: 1, dragScale: 1.05 } } };
send("eng:service.head", { balance: 5000, skill: 220, site: { siteId: "g1", label: "Kabuki garage", distance: 12, usable: true, x: 1, y: 2, z: 3 }, n: 1 });
send("eng:service.car", { index: 1, car });
send("eng:service.done", { n: 1 });
check("a damaged car shows its areas and both quotes", /Glass/.test(text()) && /SERVICE IT YOURSELF/.test(text()) && /HAVE A SHOP/.test(text()));
check("self work says materials only", /your own hands cost nothing/.test(text()));
check("the last job shows each section", /GRIP/.test(text()) && /DRAG/.test(text()));

// far from a workshop: the self button is refused with a reason, and ROUTE ME THERE appears
send("eng:service.head", { balance: 5000, skill: 220, site: { siteId: "g1", label: "Kabuki garage", distance: 840, usable: false, x: 1, y: 2, z: 3 }, n: 1 });
send("eng:service.car", { index: 1, car }); send("eng:service.done", { n: 1 });
check("away from a workshop: go there, and a route", /Go to a workshop/.test(text()) && /ROUTE ME THERE/.test(text()));

// the ceremony: four rolls, drawn one at a time, then the stamp
send("eng:repair.result", { ok: true, assetId: car.assetId, message: "done",
  workmanship: { provider: "self", grade: "good", cost: 150, sections: [
    { section: "grip", roll: 0.91, delta: 0.021, grade: "excellent" }, { section: "drive", roll: 0.4, delta: -0.008, grade: "fair" },
    { section: "brake", roll: 0.66, delta: 0.006, grade: "good" }, { section: "drag", roll: 0.05, delta: -0.06, grade: "botched" }] } });
const sheet = byId.sheet;
const lines = sheet.all().filter(e => e.classList.contains("line"));
check("the job sheet has four inked lines", lines.length === 4);
const before = lines.filter(l => l.classList.contains("drawn")).length;
timers.splice(0).forEach(fn => fn());
check("the lines are drawn in turn, then stamped", before === 0 && lines.every(l => l.classList.contains("drawn"))
  && sheet.all().some(e => e.classList.contains("stamp") && e.classList.contains("show")));
check("gains and losses are inked in their colours", sheet.all().some(e => e.classList.contains("up")) && sheet.all().some(e => e.classList.contains("down")));
send("eng:repair.result", { ok: false, assetId: car.assetId, message: "go_to_garage_workshop", workmanship: null });
check("a refused job still draws a sheet", sheet.all().length > 0);

// PARTS
tabs[1].fire("click");
const machine = { asset_id: car.assetId, vehicle_key: "galena", fitment: { "p-1": { compatible: true } } };
send("eng:parts.head", { balance: 2000, partsEnabled: true, n: 5, m: 1 });
send("eng:parts.machine", { index: 1, machine });
send("eng:parts.item", { index: 1, part: { asset_id: "p-1", code: "TX-2", family: "tyres", location_kind: "storage", wear: { status: "normal" } } });
send("eng:parts.item", { index: 2, part: { asset_id: "p-2", code: "GB-6", family: "gearbox", addOn: true, location_kind: "installed", machine_asset_id: car.assetId,
  wear: { status: "worn", conditions: [{ label: "Clutch glazing" }] }, service_quote: { cost: 120, condition_id: "c1" } } });
send("eng:parts.item", { index: 3, part: { asset_id: "p-3", code: "FD-1", family: "impulse_actuator", addOn: true, location_kind: "storage", mounts: { [car.assetId]: [{ mountId: "mount.floor", facing: "down" }] } } });
send("eng:parts.item", { index: 4, part: { asset_id: "p-4", code: "IA-10", family: "impulse_actuator", addOn: true, location_kind: "installed", machine_asset_id: car.assetId,
  mountId: "mount.underside", facing: "down", bindings: [] } });
send("eng:parts.item", { index: 5, part: { asset_id: "p-5", code: "RP-16", family: "propulsor", addOn: true, location_kind: "installed", machine_asset_id: car.assetId,
  mountId: "mount.front", facing: "down", bindings: [{ control: "padY", gesture: "hold", command: "throttle" }] } });
send("eng:parts.done", { n: 5 });
send("eng:parts.states", { [car.assetId]: { eligible: true, reason: "Machine is parked" } });
check("the parts list draws with the first part's detail", /TX-2/.test(text()) && /LOAD IN TRUNK/.test(text()));
const rows = main.all().filter(e => e.classList.contains("partrow"));
rows[1].fire("click");
check("an installed gearbox offers service and control binding", /SERVICE/.test(text()) && /BIND ENGAGE/.test(text()));
main.all().filter(e => e.classList.contains("partrow"))[2].fire("click");
check("an add-on in storage lists mount positions", /mount positions/.test(text()));
main.all().filter(e => e.classList.contains("partrow"))[3].fire("click");
check("an unbound downward actuator offers top face tap", /FACING DOWN/.test(text()) && /NONE/.test(text()) && /BIND TAP · Y \/ TRIANGLE \(SWITCH TOP X\)/.test(text()));
const tapButton = main.all().find(e => /BIND TAP · Y \/ TRIANGLE \(SWITCH TOP X\)/.test(e.textContent));
tapButton.fire("pointerdown"); timers.splice(0).forEach(fn => fn());
check("actuator binding sends tap discharge", emitted.some(e => e.n === "eng:part.bind" && e.d.componentAssetId === "p-4"
  && e.d.control === "padY" && e.d.gesture === "tap" && e.d.command === "discharge"));
main.all().filter(e => e.classList.contains("partrow"))[4].fire("click");
check("a propulsor shows its hold control", /BIND HOLD · Y \/ TRIANGLE \(SWITCH TOP X\)/.test(text()) && /padY hold → throttle/.test(text()));

tabs[2].fire("click");
check("the BUILD tab is reserved", /Build/.test(text()));

// L361: the WORKSHOP tab
tabs[3].fire("click");
check("the WORKSHOP tab asks for the bench", /Reading the bench/.test(text()) && emitted.some(e => e.n === "eng:workshop" && e.d.op === "refresh"));
byId.sheet.classList.add("hidden");   // the earlier job sheet is filed
send("eng:workshop.state", { enabled: true, slots: 2, now: 1000,
  card: { depth: 2, disciplines: [{ id: "diagnostics", word: "Apprentice" }, { id: "fabrication", word: "Novice" }] },
  bench: [{ projectId: "pj-1", kind: "teardown", slot: 1, label: "Tear down ZTC-FD1 (to stage 2)", cost: 960, startedAt: 900, dueAt: 1300, state: "running" },
          { projectId: "pj-2", kind: "fabricate", slot: 2, label: "Fabricate a ZTC-RP16 prototype", cost: 2600, startedAt: 100, dueAt: 900, state: "resolved", outcome: "neutral" }],
  storage: [{ assetId: "a-1", code: "ZTC-FD1", name: "Fusion Drive FD-1", physical: true, junk: false, origin: "design", teardownCost: 960, price: 48000 },
            { assetId: "a-2", code: "ZTC-RP16-PAB12", name: "RP-16 prototype", physical: true, junk: false, origin: "prototype" },
            { assetId: "a-3", code: "ZTC-RP16", name: "Reaction Propulsor RP-16", physical: true, junk: true, origin: "design" },
            { assetId: "a-4", code: "EAS-THR001", name: "My drive", physical: true, junk: false, origin: "player_design", mine: true, price: 7000 }],
  knowledge: [{ designId: "eng:zetatech:rp16:r1", code: "ZTC-RP16", name: "Reaction Propulsor RP-16", stage: 3, stageLabel: "Manufacturing method and internal layout",
    facts: { thrustN: { value: 29500, band: 0.05 }, massKg: { value: 86, band: 0.05 }, process: { value: "a regeneratively cooled chamber" } },
    canFabricate: true, fabricateCost: 2600, fabricateMinutes: 18 }],
  designs: [{ designId: "pd:x:p-1:001", code: "EAS-THR001", name: "My drive", price: 7000, listed: false, runCost: 2100 }] });
check("the engineer is shown in words", /DIAGNOSTICS Apprentice/.test(text()) && /stage 2 of 4/.test(text()));
check("a running job shows time left and a finished one offers its sheet", /left · materials/.test(text()) && /COLLECT THE JOB SHEET/.test(text()));
check("storage offers teardown, promotion and listing; junk says so", /TEAR DOWN/.test(text()) && /PROMOTE TO MY DESIGN/.test(text())
  && /LIST ON THE BASE MARKET/.test(text()) && /NONFUNCTIONAL/.test(text()));
check("knowledge shows the read facts and offers fabrication", /29\.5 kN ±5%/.test(text()) && /FABRICATE A PROTOTYPE/.test(text()));
check("your designs offer runs", /MAKE 1/.test(text()) && /MAKE 3/.test(text()));
const fab = main.all().find(e => /FABRICATE A PROTOTYPE/.test(e.textContent || "") && e.tagName === "BUTTON");
fab.fire("pointerdown"); timers.splice(0).forEach(fn => fn());
check("holding FABRICATE starts the project", emitted.some(e => e.n === "eng:workshop" && e.d.op === "start" && e.d.kind === "fabricate" && e.d.designId === "eng:zetatech:rp16:r1"));
send("eng:workshop.sheet", { kind: "fabricate", outcome: "neutral", name: "RP-16 prototype", cost: 2600,
  perf: { thrustN: 29000 }, massKg: 88, source: { code: "ZTC-RP16", perf: { thrustN: 30000 }, massKg: 85 } });
const wsLines = sheet.all().filter(e => e.classList.contains("line"));
timers.splice(0).forEach(fn => fn());
check("the fabrication sheet inks output and mass, then stamps", wsLines.length === 2 && wsLines.every(l => l.classList.contains("drawn"))
  && sheet.all().some(e => e.classList.contains("stamp") && e.classList.contains("show")));
send("eng:workshop.sheet", { kind: "fabricate", outcome: "junk", code: "ZTC-RP16", text: "nothing usable", cost: 2600 });
check("a junk result still gets a sheet, stamped NONFUNCTIONAL", sheet.all().some(e => e.classList.contains("stamp") && /NONFUNCTIONAL/.test(e.textContent)));
send("eng:hide", {});
check("hide hides the dock", byId.dock.classList.contains("hidden"));
console.log("engineering panel: " + passed + " passed, 0 failed");
