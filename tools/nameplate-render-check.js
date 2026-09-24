"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const webRoot = process.argv[2];
if (!webRoot) throw new Error("web root argument required");

const events = {};
const emitted = [];
const context = {
  console,
  Map,
  Set,
  Array,
  Object,
  String,
  Number,
  window: {},
  document: {
    getElementById: () => ({ appendChild() {} }),
    createElement: () => { throw new Error("unexpected DOM creation in logic check"); },
    createElementNS: () => { throw new Error("unexpected SVG creation in logic check"); }
  },
  addEventListener: () => {},
  setInterval: () => 1,
  Open77: {
    on: (name, fn) => { events[name] = fn; },
    ready: () => {},
    emit: (name, value) => { emitted.push({ name, value }); }
  }
};
context.window = context;

vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(webRoot, "nameplates.js"), "utf8"), context, {
  filename: "nameplates.js"
});

const api = context.NcmDriverCards;
let bad = 0;
let count = 0;
function check(condition, label) {
  count++;
  if (condition) {
    console.log("  PASS " + label);
  } else {
    bad++;
    console.log("  FAIL " + label);
  }
}

events["ncm-card:assets"]({
  banners: [{ id: "ncm_default" }, { id: "selected_banner" }],
  badges: [
    { id: "one", glyph: "finish" },
    { id: "two", glyph: "completed" },
    { id: "three", glyph: "timer" },
    { id: "four", glyph: "incident" }
  ]
});

const bounded = api.normalizePresentation({
  bannerId: "selected_banner",
  displayedBadgeIds: ["one", "two", "two", "missing", "three", "four"],
  fingerprint: { definitionVersion: 99, values: [0, 0, 0, 0, 0, 0], sampleState: "ready" },
  machines: ["private"]
});
check(bounded.bannerId === "selected_banner", "known selected banner survives");
check(bounded.displayedBadgeIds.join(",") === "one,two,three", "badges dedupe, reject unknown IDs, and stop at three");
check(bounded.fingerprint.sampleState === "unavailable", "fingerprint remains honestly unavailable");
check(bounded.fingerprint.values.length === 0, "unavailable fingerprint has no fabricated polygon values");
check(!Object.prototype.hasOwnProperty.call(bounded, "machines"), "private fields do not survive client normalization");

const fallback = api.normalizePresentation({ bannerId: "missing", displayedBadgeIds: ["missing"] });
check(fallback.bannerId === "ncm_default", "invalid banner uses stable default");
check(fallback.displayedBadgeIds.length === 0, "invalid badges disappear safely");

const hostile = '<img src=x onerror="boom">長い名前🏁';
check(api.safeName(hostile) === hostile, "non-ASCII name content is preserved as text");
check(api.safeName("x".repeat(100)).length === 64, "long name is bounded without changing source identity");
check(api.safeName("   ") === "Unknown driver", "missing name has an honest fallback");

check(api.staleIds(["7", "8", "9"], [{ id: 8 }, { id: "9" }]).join(",") === "7",
  "stream-out/leave reconciliation identifies stale DOM entry");
check(api.staleIds(["7"], []).join(",") === "7", "empty stream removes every proximity card");
check(emitted.some(entry => entry.name === "ncm-card:ready"), "page announces readiness before native handoff");

const source = fs.readFileSync(path.join(webRoot, "nameplates.js"), "utf8");
const style = fs.readFileSync(path.join(webRoot, "nameplates.css"), "utf8");
check(source.includes("nameNode.textContent = name") && !source.includes("nameNode.innerHTML"),
  "verified presentation name is assigned through textContent, never HTML");
check(source.includes("card.remove()") && source.includes("cards.delete(id)"),
  "stale cards are removed from DOM and renderer state");
check(source.includes("safeBannerImage") && style.includes("background-size: cover"),
  "catalogue banner art uses a bounded local path and an explicit cover crop");
check(!style.includes("backdrop-filter") && !/filter\s*:\s*blur\(/.test(style),
  "card uses no blur effect");
check(source.includes("card.dataset.presentationSignature !== presentationSignature"),
  "per-frame projection does not rebuild slow banner and badge DOM");

const clientLua = fs.readFileSync(path.resolve(webRoot, "../client/nameplates.lua"), "utf8");
const streamAt = clientLua.indexOf("Open77.nameplates.stream(page)");
const suppressAt = clientLua.indexOf('call("open77_nameplates", "setEnabled", false)');
check(streamAt >= 0 && suppressAt > streamAt, "custom stream is established before native text is suppressed");
check(clientLua.includes('call("open77_nameplates", "setEnabled", true)') &&
  clientLua.includes('"heartbeat_timeout"') && clientLua.includes("if nativeSuppressed then"),
  "page failure watchdog has an explicit native-renderer restoration path");
check(clientLua.includes('name == "open77_nameplates"') && clientLua.includes("onClientResourceStop"),
  "system and NCM resource reload paths re-establish or release the renderer handoff");

console.log(`nameplate render: ${count - bad} assertion(s) passed, ${bad} bad`);
process.exit(bad ? 1 : 0);
