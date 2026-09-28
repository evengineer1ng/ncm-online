/* NCM shared navigation layer v0.1 — keyboard, gamepad and mouse for every interactive NCM surface.
 *
 * THE ONE ARCHITECTURAL FACT THAT SHAPES ALL OF THIS
 * --------------------------------------------------
 * A CEF page cannot see the gamepad. The pad is read on the Lua side with `Open77.input.isDown` /
 * `Open77.input.axis` (physical device reads), translated into SEMANTIC actions there, and sent here as
 * ordinary page events. So this file never mentions a button: it receives "up", "activate", "back".
 *
 * That split is not a workaround, it is the safe design. `KB-61` cost a player their game: the panel took
 * keyboard AND cursor focus, and both ways out ran through the page, so when the page broke the player could
 * not move, could not open the pause menu, and had to kill Cyberpunk. The rule that came out of it —
 * "nothing about releasing focus may depend on the page being healthy" — applies to the pad too:
 *
 *   >>> The pad's BACK action is handled in Lua and is authoritative there. This file also handles it, for
 *   >>> responsiveness, but Lua does not wait for us. A dead page must still be escapable with the pad alone.
 *
 * WHAT THIS OWNS
 *   focus scopes (stacked, so a modal traps focus) · spatial navigation · a visible focus ring ·
 *   scroll-into-view · activation · back · input-family detection · glyph/prompt labels
 *
 * WHAT IT DELIBERATELY DOES NOT OWN
 *   input capture (Lua) · gameplay input blocking (Lua) · what any control does (the surface)
 */
(() => {
  "use strict";

  // ---------------------------------------------------------------------------------------------------
  // Glyphs. Controller BRAND IS NOT DETECTABLE: `Open77.input.devices()` reports device/kind/availability
  // and nothing about layout, and the underlying API is XInput, which is Xbox-shaped. So the default is a
  // NEUTRAL label that is true on every pad, and a style can be set explicitly later (a setting, not a
  // guess). This is the graceful fallback the brief asked for rather than a wrong PlayStation prompt.
  // ---------------------------------------------------------------------------------------------------
  const GLYPHS = {
    keyboard: { activate: "ENTER", back: "ESC", up: "↑", down: "↓", left: "←", right: "→",
                pageUp: "PGUP", pageDown: "PGDN", tab: "TAB" },
    mouse:    { activate: "CLICK", back: "CLOSE", up: "", down: "", left: "", right: "",
                pageUp: "", pageDown: "", tab: "" },
    // Neutral: position words, true on any layout. No A/B, no Cross/Circle.
    pad:      { activate: "CONFIRM", back: "BACK", up: "↑", down: "↓", left: "←", right: "→",
                pageUp: "L1", pageDown: "R1", tab: "L1/R1" },
    xbox:     { activate: "A", back: "B", up: "↑", down: "↓", left: "←", right: "→",
                pageUp: "LB", pageDown: "RB", tab: "LB/RB" },
    playstation: { activate: "✕", back: "○", up: "↑", down: "↓", left: "←", right: "→",
                pageUp: "L1", pageDown: "R1", tab: "L1/R1" },
  };

  let family = "mouse";       // mouse | keyboard | pad
  let padStyle = "pad";       // pad | xbox | playstation — explicit only, never inferred
  const scopes = [];          // stack; the top scope owns navigation
  let ring = null;

  const listeners = { family: [], back: [] };
  function emit(kind, value) { for (const fn of listeners[kind] || []) { try { fn(value); } catch (_) {} } }

  // ---------------------------------------------------------------------------------------------------
  // Focusables
  // ---------------------------------------------------------------------------------------------------
  const SELECTOR = 'a[href],button,input,select,textarea,[tabindex],[data-nav]';

  /** Visible, enabled, and actually reachable. Hidden and disabled controls must never take focus — both
   *  are named failure conditions, and both are how a player ends up on something they cannot use. */
  function usable(el) {
    if (!el || el.disabled === true) return false;
    if (el.getAttribute && el.getAttribute("aria-hidden") === "true") return false;
    if (el.getAttribute && el.getAttribute("tabindex") === "-1" && !el.hasAttribute("data-nav")) return false;
    if (el.hidden === true) return false;
    if (el.classList && el.classList.contains("hidden")) return false;
    // offsetParent is null for display:none subtrees. Guarded because the render harness stubs the DOM.
    if ("offsetParent" in el && el.offsetParent === null && el.tagName !== "BODY") return false;
    const r = rect(el);
    return r.width > 0 && r.height > 0;
  }

  function rect(el) {
    if (el && typeof el.getBoundingClientRect === "function") {
      const r = el.getBoundingClientRect();
      // Normalised so the geometry below never has to care which shape came back.
      return { left: r.left || 0, top: r.top || 0, width: r.width || 0, height: r.height || 0,
               cx: (r.left || 0) + (r.width || 0) / 2, cy: (r.top || 0) + (r.height || 0) / 2 };
    }
    return { left: 0, top: 0, width: 0, height: 0, cx: 0, cy: 0 };
  }

  function focusables(root) {
    if (!root || typeof root.querySelectorAll !== "function") return [];
    const all = Array.from(root.querySelectorAll(SELECTOR));
    const out = [];
    for (const el of all) if (usable(el)) out.push(el);
    // Explicit order wins where a surface has declared one; otherwise DOM order, which is why markup order
    // is expected to be semantic. `data-nav-order` exists for the cases where it genuinely cannot be.
    out.sort((a, b) => (+(a.dataset && a.dataset.navOrder || 0)) - (+(b.dataset && b.dataset.navOrder || 0)));
    return out;
  }

  // ---------------------------------------------------------------------------------------------------
  // Spatial navigation. Exported for tests, because this is the part with real geometry in it.
  //
  // Scoring: a candidate must lie in the half-plane of travel. Cost is the distance along the axis of
  // travel plus TWICE the cross-axis offset, so "one column to the right" beats "far down and slightly
  // right" — which is the specific complaint in the brief about pressing Down seventeen times.
  // ---------------------------------------------------------------------------------------------------
  function pick(fromRect, candidates, direction) {
    const axis = (direction === "left" || direction === "right") ? "x" : "y";
    const sign = (direction === "right" || direction === "down") ? 1 : -1;
    let best = null, bestCost = Infinity;
    for (const c of candidates) {
      const r = c.rect;
      const along = axis === "x" ? (r.cx - fromRect.cx) * sign : (r.cy - fromRect.cy) * sign;
      if (along <= 1) continue;                       // not in the direction of travel
      const across = axis === "x" ? Math.abs(r.cy - fromRect.cy) : Math.abs(r.cx - fromRect.cx);
      // An overlapping band on the cross axis means "same row" / "same column": always eligible, and
      // strongly preferred.
      const overlaps = axis === "x"
        ? (r.top < fromRect.top + fromRect.height && r.top + r.height > fromRect.top)
        : (r.left < fromRect.left + fromRect.width && r.left + r.width > fromRect.left);
      // A DIRECTIONAL CONE, and it is load-bearing. Without it a bare half-plane test calls anything at all
      // to the right "right" — including a control 700 px BELOW and 20 px across, which is plainly "down".
      // A player pressing right and landing at the bottom of the screen has lost their place.
      if (!overlaps && across > along * 2 + 40) continue;
      const cost = along + across * 2 - (overlaps ? 100000 : 0);
      if (cost < bestCost) { bestCost = cost; best = c.el; }
    }
    return best;
  }

  // ---------------------------------------------------------------------------------------------------
  // Scopes
  // ---------------------------------------------------------------------------------------------------
  function top() { return scopes.length ? scopes[scopes.length - 1] : null; }

  function ensureRing() {
    if (ring || typeof document === "undefined" || !document.body) return ring;
    ring = document.createElement("div");
    ring.className = "ncm-focus-ring";
    ring.setAttribute("aria-hidden", "true");
    document.body.appendChild(ring);
    return ring;
  }

  /** The ring is a separate element rather than an outline so that focus is legible over ANY surface,
   *  including a themed market plate or a photographic hero. A subtle colour change is explicitly not
   *  enough — that is a stated requirement, and it is also just true on a moving backdrop. */
  function paint(el) {
    const r = ensureRing();
    if (!r || !r.style) return;
    if (!el) { r.style.opacity = "0"; return; }
    const b = rect(el);
    r.style.opacity = "1";
    r.style.transform = "translate(" + Math.round(b.left - 3) + "px," + Math.round(b.top - 3) + "px)";
    r.style.width = Math.round(b.width + 6) + "px";
    r.style.height = Math.round(b.height + 6) + "px";
  }

  /** A focused element must never sit silently outside the viewport. */
  function reveal(el) {
    if (el && typeof el.scrollIntoView === "function") {
      try { el.scrollIntoView({ block: "nearest", inline: "nearest" }); } catch (_) { el.scrollIntoView(false); }
    }
  }

  function setFocus(scope, el, why) {
    if (!scope) return null;
    if (scope.current && scope.current.classList) scope.current.classList.remove("ncm-focused");
    scope.current = el || null;
    if (el) {
      if (el.classList) el.classList.add("ncm-focused");
      // Real DOM focus too, so browser semantics (typing into an input) keep working for keyboard users.
      if (typeof el.focus === "function") { try { el.focus({ preventScroll: true }); } catch (_) { el.focus(); } }
      if (why !== "pointer") reveal(el);
    }
    paint(family === "mouse" ? null : el);
    return el;
  }

  function scopeItems(scope) {
    return focusables(scope.root).map((el) => ({ el, rect: rect(el) }));
  }

  function move(direction) {
    const scope = top();
    if (!scope) return false;
    const items = scopeItems(scope);
    if (!items.length) return false;
    if (!scope.current || items.every((i) => i.el !== scope.current)) {
      setFocus(scope, items[0].el, "move");
      return true;
    }
    const next = pick(rect(scope.current), items.filter((i) => i.el !== scope.current), direction);
    if (next) { setFocus(scope, next, "move"); return true; }
    // No candidate that way. Deliberately do NOT wrap: wrapping under a held stick is how focus runs away.
    return false;
  }

  function scrollableAncestor(el) {
    let node = el;
    while (node && node !== document.body) {
      if (node.scrollHeight && node.clientHeight && node.scrollHeight > node.clientHeight + 1) return node;
      node = node.parentElement;
    }
    const scope = top();
    return (scope && scope.scroller) || null;
  }

  function scrollBy(amount) {
    const scope = top();
    const target = scrollableAncestor(scope && scope.current) || (scope && scope.scroller);
    if (!target) return false;
    const before = target.scrollTop || 0;
    target.scrollTop = before + amount;
    return (target.scrollTop || 0) !== before;
  }

  function activate() {
    const scope = top();
    const el = scope && scope.current;
    if (!el || !usable(el)) return false;
    // One synthetic click, so a control only ever needs a click handler. Double activation is a named
    // failure condition, so the edge detection that prevents it lives on the Lua side, once.
    if (typeof el.click === "function") el.click();
    else if (typeof el.dispatchEvent === "function" && typeof Event === "function") {
      el.dispatchEvent(new Event("click", { bubbles: true }));
    }
    return true;
  }

  function back() {
    const scope = top();
    if (!scope) return false;
    emit("back", scope.id);
    if (typeof scope.onBack === "function") { scope.onBack(); return true; }
    return false;
  }

  // ---------------------------------------------------------------------------------------------------
  // Input family. The page can see mouse and keyboard itself; only Lua can see the pad, so the pad family
  // arrives with the action. Switching family must not lose focus — a named failure condition — so the
  // focused element is kept and only the ring's visibility changes.
  // ---------------------------------------------------------------------------------------------------
  // **The in-game cursor is driven BY the pad**, so a pad action emits a synthetic `mousemove` a frame
  // later. Switching family on that move flips pad -> mouse -> pad continuously, and since the family
  // controls the focus ring's visibility and the `.ncm-focused` background, the whole panel strobes --
  // on every page, not just the one being used. Two guards below: a real pointer has to actually move,
  // and it has to move outside the shadow of a deliberate pad or keyboard action.
  const MOUSE_AFTER_ACTION_MS = 600;
  let lastDeliberateAt = 0;
  let lastPointer = null;

  function setFamily(next) {
    if (next !== "mouse" && next !== "keyboard" && next !== "pad") return;
    if (next !== "mouse") lastDeliberateAt = Date.now();
    if (family === next) return;
    family = next;
    if (typeof document !== "undefined" && document.body && document.body.dataset) {
      document.body.dataset.ncmInput = family;
    }
    const scope = top();
    paint(family === "mouse" ? null : (scope && scope.current));
    emit("family", family);
  }

  const ACTIONS = {
    up: () => move("up"), down: () => move("down"), left: () => move("left"), right: () => move("right"),
    activate, back,
    pageUp: () => scrollBy(-320), pageDown: () => scrollBy(320),
    scrollUp: () => scrollBy(-90), scrollDown: () => scrollBy(90),
    next: () => step(1), previous: () => step(-1),
  };

  /** Linear step, for Tab and for shoulder paging within a scope. */
  function step(delta) {
    const scope = top();
    if (!scope) return false;
    const items = scopeItems(scope);
    if (!items.length) return false;
    let index = items.findIndex((i) => i.el === scope.current);
    if (index < 0) index = delta > 0 ? -1 : 0;
    // Clamped, not wrapped, for the same runaway reason as `move`.
    const nextIndex = Math.max(0, Math.min(items.length - 1, index + delta));
    setFocus(scope, items[nextIndex].el, "move");
    return true;
  }

  function perform(action, source) {
    if (source === "pad") setFamily("pad");
    const fn = ACTIONS[action];
    if (!fn) return false;
    return fn() !== false;
  }

  // ---------------------------------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------------------------------
  const NcmNav = {
    /** Push a focus scope. While it is on top it OWNS navigation: focus cannot leave it.
     *  `first` is a selector or element for initial focus — for a landing panel that is the dismiss
     *  control, so the player is never made to tab through a changelog to get out. */
    push(spec) {
      const root = (spec && spec.root) || (typeof document !== "undefined" ? document.body : null);
      if (!root) return null;
      const scope = {
        id: (spec && spec.id) || "scope" + scopes.length,
        root, current: null,
        onBack: spec && spec.onBack,
        scroller: (spec && spec.scroller) || null,
      };
      scopes.push(scope);
      let first = null;
      if (spec && spec.first) {
        first = typeof spec.first === "string" ? root.querySelector(spec.first) : spec.first;
      }
      if (!first || !usable(first)) { const items = scopeItems(scope); first = items.length ? items[0].el : null; }
      // Under the mouse there is no focus ring to show, but focus is still set so a later keypress or pad
      // nudge starts somewhere sensible rather than at the top of the document.
      setFocus(scope, first, "push");
      return scope.id;
    },

    /** Pop a scope and restore focus to whatever the scope below was on. Focus restoration after closing a
     *  child surface is a stated requirement and the reason scopes are a stack rather than a flag. */
    pop(id) {
      if (!scopes.length) return false;
      if (id && top().id !== id) {
        const index = scopes.findIndex((s) => s.id === id);
        if (index < 0) return false;
        scopes.splice(index, 1);
        return true;
      }
      const gone = scopes.pop();
      if (gone && gone.current && gone.current.classList) gone.current.classList.remove("ncm-focused");
      const now = top();
      if (now) setFocus(now, now.current, "pop"); else paint(null);
      return true;
    },

    clear() { while (scopes.length) NcmNav.pop(); },
    depth() { return scopes.length; },
    focused() { const s = top(); return s ? s.current : null; },
    family() { return family; },
    setFamily,

    /** Explicit pad style. Never inferred: brand is not detectable from `Open77.input.devices()`. */
    setPadStyle(style) { if (GLYPHS[style]) padStyle = style; },

    /** The label for one semantic action under the CURRENT input family. */
    glyph(action) {
      const table = family === "pad" ? GLYPHS[padStyle] || GLYPHS.pad : GLYPHS[family] || GLYPHS.keyboard;
      return table[action] || "";
    },

    /** Paint every `[data-ncm-prompt="activate|back|..."]` with the right label for the active family. */
    paintPrompts(root) {
      const scope = root || (typeof document !== "undefined" ? document : null);
      if (!scope || typeof scope.querySelectorAll !== "function") return;
      for (const el of Array.from(scope.querySelectorAll("[data-ncm-prompt]"))) {
        const label = NcmNav.glyph(el.dataset.ncmPrompt);
        el.textContent = label;
        // A prompt with no label under this family (mouse has no "up") should not leave an empty box.
        if (el.style) el.style.display = label ? "" : "none";
      }
    },

    perform,
    on(kind, fn) { if (listeners[kind]) listeners[kind].push(fn); },
    refresh() { const s = top(); if (s) paint(family === "mouse" ? null : s.current); },

    // Exposed for the offline harness.
    _pick: pick, _focusables: focusables, _usable: usable,
  };

  // ---------------------------------------------------------------------------------------------------
  // Wiring. Keyboard and mouse are native to the page; the pad arrives over the bridge.
  // ---------------------------------------------------------------------------------------------------
  if (typeof document !== "undefined" && document.addEventListener) {
    document.addEventListener("keydown", (event) => {
      if (!scopes.length) return;
      setFamily("keyboard");
      const key = event.key;
      // Escape is DELIBERATELY absent. The host surface already owns it (panel.html has handled it since
      // KB-61), and claiming it here would close the panel twice and hijack a standard convention for no
      // gain. The pad's BACK still routes through `perform("back")`; only the keyboard is left alone.
      const map = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
                    PageUp: "pageUp", PageDown: "pageDown" };
      if (key === "Tab") { perform(event.shiftKey ? "previous" : "next", "keyboard"); event.preventDefault(); return; }
      if (key === "Enter" || key === " ") {
        // Let a text field keep its own Enter. Hijacking standard conventions is explicitly unwanted.
        const el = NcmNav.focused();
        const tag = el && el.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
        if (perform("activate", "keyboard")) event.preventDefault();
        return;
      }
      if (map[key]) { if (perform(map[key], "keyboard")) event.preventDefault(); }
    }, true);

    document.addEventListener("mousemove", (event) => {
      // A repeated event at the same coordinates is not movement; the game emits those.
      if (event && typeof event.clientX === "number") {
        if (lastPointer && lastPointer.x === event.clientX && lastPointer.y === event.clientY) return;
        lastPointer = { x: event.clientX, y: event.clientY };
      }
      if (Date.now() - lastDeliberateAt < MOUSE_AFTER_ACTION_MS) return;
      setFamily("mouse");
    }, true);
    // Hover must not fight pad focus: under pad or keyboard, a mouse that has not moved changes nothing.
    document.addEventListener("mouseover", (event) => {
      if (family !== "mouse") return;
      const scope = top();
      if (!scope) return;
      let el = event.target;
      while (el && el !== scope.root && !usable(el)) el = el.parentElement;
      if (el && el !== scope.root && usable(el)) setFocus(scope, el, "pointer");
    }, true);

    if (typeof window !== "undefined" && window.addEventListener) {
      // Resolution changes invalidate every cached rectangle, which is a named failure condition.
      window.addEventListener("resize", () => NcmNav.refresh());
    }
  }

  // Lua → page. One event, one semantic action. See the header for why BACK is also handled in Lua.
  if (typeof Open77 !== "undefined" && Open77 && typeof Open77.on === "function") {
    Open77.on("nav:pad", (data) => {
      if (!data || typeof data.action !== "string") return;
      perform(data.action, "pad");
      NcmNav.paintPrompts();
    });
    Open77.on("nav:family", (data) => {
      if (data && typeof data.family === "string") { setFamily(data.family); NcmNav.paintPrompts(); }
    });
    Open77.on("nav:padStyle", (data) => {
      if (data && typeof data.style === "string") { NcmNav.setPadStyle(data.style); NcmNav.paintPrompts(); }
    });
  }

  NcmNav.on("family", () => NcmNav.paintPrompts());

  if (typeof window !== "undefined") window.NcmNav = NcmNav;
  if (typeof module !== "undefined" && module.exports) module.exports = NcmNav;
})();
