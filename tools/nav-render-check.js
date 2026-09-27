// Runtime check for the shared navigation layer (web/ncm-nav.js).
//
// This is the file that decides whether a player holding a controller can use NCM at all, and almost all of
// it is geometry and state -- exactly the kind of logic that is wrong in ways `node --check` cannot see. So:
// stub a DOM with real rectangles, load the real ncm-nav.js, and drive it the way Lua and the keyboard do.
//
// The DOM stub here is richer than the panel harness's in one way that matters: every element has a real
// `getBoundingClientRect`, because spatial navigation is nothing but rectangles.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const WEB = process.argv[2];
const navJs = fs.readFileSync(path.join(WEB, "ncm-nav.js"), "utf8");

let failed = 0;
function check(name, ok, detail) {
  if (ok) { console.log("  PASS " + name); return; }
  failed++;
  console.log("  FAIL " + name + (detail ? "  -- " + detail : ""));
}

// ---- DOM stub with geometry ---------------------------------------------------------------------------
function makeEl(tag) {
  const el = {
    tagName: String(tag || "div").toUpperCase(),
    children: [], attributes: {}, dataset: {}, disabled: false, hidden: false,
    offsetParent: {}, _rect: { left: 0, top: 0, width: 0, height: 0 },
    style: { setProperty() {} },
    _text: "",
    classList: {
      _s: new Set(),
      add(...c) { c.forEach(x => this._s.add(x)); },
      remove(...c) { c.forEach(x => this._s.delete(x)); },
      contains(c) { return this._s.has(c); },
      toggle(c, on) { if (on === undefined) { this._s.has(c) ? this._s.delete(c) : this._s.add(c); } else if (on) this._s.add(c); else this._s.delete(c); },
    },
    append(...k) { for (const kid of k) { this.children.push(kid); kid.parentElement = this; } },
    appendChild(k) { this.append(k); return k; },
    setAttribute(k, v) { this.attributes[k] = String(v); },
    getAttribute(k) { return this.attributes[k] === undefined ? null : this.attributes[k]; },
    hasAttribute(k) { return this.attributes[k] !== undefined; },
    getBoundingClientRect() { return this._rect; },
    _listeners: {},
    addEventListener(n, fn) { (this._listeners[n] = this._listeners[n] || []).push(fn); },
    dispatchEvent(ev) { for (const fn of (this._listeners[(ev && ev.type) || ""] || [])) fn(ev); return true; },
    click() { this.clicked = (this.clicked || 0) + 1; this.dispatchEvent({ type: "click" }); },
    focus() { this.focused = true; },
    scrollIntoView() { this.revealed = true; },
    querySelectorAll() { return []; },
    querySelector() { return null; },
    remove() {},
  };
  Object.defineProperty(el, "textContent", { get() { return this._text; }, set(v) { this._text = String(v == null ? "" : v); } });
  return el;
}

/** A focusable at a position. `nav` marks it with data-nav, which is what the layer collects. */
function cell(id, left, top, width, height, over) {
  const el = makeEl("button");
  el.id = id;
  el._rect = { left, top, width, height };
  el.setAttribute("data-nav", "");
  Object.assign(el, over || {});
  return el;
}

/** A container whose querySelectorAll answers its own registered cells, in insertion order. */
function container(cells) {
  const root = makeEl("div");
  root._rect = { left: 0, top: 0, width: 1920, height: 1080 };
  root.querySelectorAll = () => cells;
  for (const c of cells) { root.children.push(c); c.parentElement = root; }
  return root;
}

const listeners = {};
const document = {
  body: makeEl("body"),
  createElement: makeEl,
  addEventListener(name, fn) { (listeners[name] = listeners[name] || []).push(fn); },
  querySelectorAll() { return []; },
  querySelector() { return null; },
};
document.body.dataset = {};

const padSent = [];
const Open77 = {
  on(name, fn) { (Open77._h[name] = Open77._h[name] || []).push(fn); },
  emit(name, data) { padSent.push({ name, data }); },
  _h: {},
};

const sandbox = { document, Open77, console, Math, Number, String, Array, Object, Boolean, Event: function (t) { this.type = t; } };
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(navJs, sandbox, { filename: "ncm-nav.js" });
const Nav = sandbox.window.NcmNav;
if (!Nav) { console.error("ncm-nav.js did not export NcmNav"); process.exit(2); }

/** Deliver a pad action the way client/nav_input.lua does. */
function pad(action) { for (const fn of Open77._h["nav:pad"] || []) fn({ action }); }
function key(k, shift) { for (const fn of listeners["keydown"] || []) fn({ key: k, shiftKey: !!shift, preventDefault() {} }); }

console.log("  -- focus collection --");
{
  const ok = cell("ok", 0, 0, 100, 40);
  const hiddenByClass = cell("byClass", 0, 50, 100, 40); hiddenByClass.classList.add("hidden");
  const disabled = cell("disabled", 0, 100, 100, 40, { disabled: true });
  const aria = cell("aria", 0, 150, 100, 40); aria.setAttribute("aria-hidden", "true");
  const zeroSize = cell("zero", 0, 200, 0, 0);
  const displayNone = cell("none", 0, 250, 100, 40, { offsetParent: null });
  const root = container([ok, hiddenByClass, disabled, aria, zeroSize, displayNone]);
  const got = Nav._focusables(root).map(e => e.id);
  check("only genuinely usable controls are focusable", got.length === 1 && got[0] === "ok", got.join(","));
  check("a disabled control never takes focus", !Nav._usable(disabled));
  check("a hidden control never takes focus", !Nav._usable(aria) && !Nav._usable(displayNone));
  check("a zero-size control never takes focus", !Nav._usable(zeroSize));
}

console.log("  -- spatial navigation --");
{
  // The exact complaint from the brief: a button one column to the RIGHT must not require pressing Down.
  //   [a]        [b]
  //   [c]
  //            [d far below, slightly right]
  const a = cell("a", 0, 0, 100, 40);
  const b = cell("b", 300, 0, 100, 40);
  const c = cell("c", 0, 60, 100, 40);
  const d = cell("d", 320, 700, 100, 40);
  const root = container([a, b, c, d]);
  Nav.clear();
  Nav.push({ id: "grid", root, first: a });
  check("initial focus is the requested element", Nav.focused() === a, String(Nav.focused() && Nav.focused().id));

  pad("right");
  check("right moves to the element on the right, not the one far below it",
    Nav.focused() === b, String(Nav.focused() && Nav.focused().id));

  Nav.clear(); Nav.push({ id: "grid", root, first: a });
  pad("down");
  check("down moves within the column", Nav.focused() === c, String(Nav.focused() && Nav.focused().id));

  // Runaway prevention: at the edge, focus must STAY rather than wrap. A held stick on a wrapping list is
  // exactly the "analog stick generating runaway navigation" failure.
  Nav.clear(); Nav.push({ id: "grid", root, first: b });
  pad("right");
  check("no candidate in that direction leaves focus where it is, never wrapping",
    Nav.focused() === b, String(Nav.focused() && Nav.focused().id));

  // Same row beats nearer-but-different-row.
  const r1 = cell("r1", 0, 0, 80, 30);
  const sameRow = cell("sameRow", 200, 0, 80, 30);
  const nearerOtherRow = cell("other", 120, 200, 80, 30);
  const root2 = container([r1, sameRow, nearerOtherRow]);
  Nav.clear(); Nav.push({ id: "rows", root: root2, first: r1 });
  pad("right");
  check("an element on the same row wins over a nearer one on another row",
    Nav.focused() === sameRow, String(Nav.focused() && Nav.focused().id));
}

console.log("  -- lists behave like lists --");
{
  const rows = [];
  for (let i = 0; i < 5; i++) rows.push(cell("row" + i, 0, i * 30, 400, 28));
  const root = container(rows);
  Nav.clear(); Nav.push({ id: "list", root, first: rows[0] });
  pad("down"); pad("down");
  check("repeated down walks the list one row at a time", Nav.focused() === rows[2],
    String(Nav.focused() && Nav.focused().id));
  pad("up");
  check("up walks back", Nav.focused() === rows[1], String(Nav.focused() && Nav.focused().id));
  // Tab is linear and clamps at the end rather than cycling.
  Nav.clear(); Nav.push({ id: "list", root, first: rows[4] });
  key("Tab");
  check("Tab clamps at the last control rather than cycling to the top",
    Nav.focused() === rows[4], String(Nav.focused() && Nav.focused().id));
  key("Tab", true);
  check("Shift+Tab steps backwards", Nav.focused() === rows[3], String(Nav.focused() && Nav.focused().id));
}

console.log("  -- focus is visible and revealed --");
{
  const one = cell("one", 0, 0, 100, 40);
  const two = cell("two", 0, 2000, 100, 40);   // far offscreen
  const root = container([one, two]);
  Nav.clear(); Nav.push({ id: "scroll", root, first: one });
  pad("down");
  check("a focused element that is offscreen is scrolled into view", two.revealed === true);
  check("the focused element carries a class so focus is legible without the ring",
    two.classList.contains("ncm-focused"));
  check("the previous element stops claiming focus", !one.classList.contains("ncm-focused"));
}

console.log("  -- modal trap and restoration --");
{
  const base = cell("base", 0, 0, 100, 40);
  const baseRoot = container([base]);
  const modalA = cell("modalA", 0, 0, 100, 40);
  const modalB = cell("modalB", 0, 60, 100, 40);
  const modalRoot = container([modalA, modalB]);
  Nav.clear();
  Nav.push({ id: "base", root: baseRoot, first: base });
  Nav.push({ id: "modal", root: modalRoot, first: modalA });
  check("a pushed scope owns navigation", Nav.depth() === 2 && Nav.focused() === modalA,
    Nav.depth() + " / " + String(Nav.focused() && Nav.focused().id));
  pad("down"); pad("down"); pad("down");
  check("focus cannot escape the modal scope",
    Nav.focused() === modalB, String(Nav.focused() && Nav.focused().id));
  Nav.pop();
  check("popping restores focus to the surface underneath",
    Nav.depth() === 1 && Nav.focused() === base, Nav.depth() + " / " + String(Nav.focused() && Nav.focused().id));
}

console.log("  -- activation --");
{
  const btn = cell("btn", 0, 0, 100, 40);
  const root = container([btn]);
  Nav.clear(); Nav.push({ id: "one", root, first: btn });
  pad("activate");
  check("pad CONFIRM activates the focused control exactly once", btn.clicked === 1, "clicked=" + btn.clicked);
  key("Enter");
  check("Enter activates it too", btn.clicked === 2, "clicked=" + btn.clicked);

  // A text field must keep its own Enter: hijacking standard conventions is explicitly unwanted.
  const field = cell("field", 0, 60, 100, 40);
  field.tagName = "INPUT";
  const root2 = container([field]);
  Nav.clear(); Nav.push({ id: "form", root: root2, first: field });
  key("Enter");
  check("Enter inside a text field is left to the field", !field.clicked, "clicked=" + field.clicked);
}

console.log("  -- back --");
{
  let backs = 0;
  const btn = cell("btn", 0, 0, 100, 40);
  const root = container([btn]);
  Nav.clear(); Nav.push({ id: "one", root, first: btn, onBack: () => { backs++; } });
  pad("back");
  check("pad BACK reaches the surface's own close path", backs === 1, "backs=" + backs);
  // Escape is deliberately NOT claimed here: the host page has owned it since KB-61, and claiming it would
  // close the panel twice.
  key("Escape");
  check("Escape is left to the host surface, so it cannot close two layers at once",
    backs === 1, "backs=" + backs);
}

console.log("  -- input family and prompts --");
{
  const btn = cell("btn", 0, 0, 100, 40);
  const root = container([btn]);
  Nav.clear(); Nav.push({ id: "one", root, first: btn });

  Nav.setFamily("keyboard");
  check("keyboard prompts name keys", Nav.glyph("activate") === "ENTER" && Nav.glyph("back") === "ESC",
    Nav.glyph("activate") + "/" + Nav.glyph("back"));

  pad("down");
  check("a pad action switches the family to pad", Nav.family() === "pad", Nav.family());
  // Controller BRAND is not detectable from Open77.input.devices(), so the default must be neutral rather
  // than an Xbox guess that is wrong on a PlayStation pad.
  check("the default pad prompt is layout-neutral, not Xbox wording",
    Nav.glyph("activate") === "CONFIRM" && Nav.glyph("back") === "BACK",
    Nav.glyph("activate") + "/" + Nav.glyph("back"));
  Nav.setPadStyle("playstation");
  check("an explicitly chosen layout is honoured", Nav.glyph("back") === "○", Nav.glyph("back"));
  Nav.setPadStyle("xbox");
  check("so is Xbox", Nav.glyph("activate") === "A" && Nav.glyph("back") === "B",
    Nav.glyph("activate") + "/" + Nav.glyph("back"));
  Nav.setPadStyle("pad");

  // Switching family must not lose focus -- a named failure condition.
  const before = Nav.focused();
  Nav.setFamily("mouse");
  check("switching input family keeps the focused element", Nav.focused() === before,
    String(Nav.focused() && Nav.focused().id));
  check("the family is published for CSS", document.body.dataset.ncmInput === "mouse",
    String(document.body.dataset.ncmInput));
}

console.log("  -- prompt painting --");
{
  const activate = makeEl("span"); activate.dataset.ncmPrompt = "activate";
  const up = makeEl("span"); up.dataset.ncmPrompt = "up";
  activate.setAttribute("data-ncm-prompt", "activate");
  up.setAttribute("data-ncm-prompt", "up");
  const host = makeEl("div");
  host.querySelectorAll = () => [activate, up];
  Nav.setFamily("keyboard");
  Nav.paintPrompts(host);
  check("prompts are painted for the active family", activate.textContent === "ENTER", activate.textContent);
  Nav.setFamily("mouse");
  Nav.paintPrompts(host);
  check("a prompt with no meaning under this family is hidden, not left as an empty box",
    activate.textContent === "CLICK" && up.style.display === "none",
    activate.textContent + " / up.display=" + up.style.display);
}

console.log(failed === 0 ? "nav render: ALL GREEN" : ("nav render: " + failed + " FAILED"));
process.exit(failed === 0 ? 0 : 1);
