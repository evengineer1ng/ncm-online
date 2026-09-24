/* NCM system glyphs v0.1. Semantic IDs are stable; drawing details may evolve. */
(() => {
  "use strict";
  const NS = "http://www.w3.org/2000/svg";
  const symbols = {
    sanctioned: '<path d="M5 3v18M7 4h6v5H7zm6 0h6v5h-6zM7 9h6v5H7zm6 0h6v5h-6z"/><path class="accent" d="M7 4h6v5H7zm6 5h6v5h-6z"/>',
    street: '<path d="M4 20c5-1 3-7 8-8s3-7 8-8"/><path class="accent" d="m8 5 2 2m4-4 2 2M5 11l2 2m5 3 2 2"/>',
    timer: '<circle cx="12" cy="13" r="8"/><path d="M9 2h6M12 5v2m0 6 4-3"/>',
    practice: '<path d="m8 20 4-16 4 16M6 20h12M9.5 13h5"/>',
    circuit: '<path d="M6 18c-3-3-3-9 0-12s9-3 12 0 3 9 0 12-9 3-12 0Z"/><path class="accent" d="M8 16c-2-2-2-6 0-8s6-2 8 0 2 6 0 8-6 2-8 0Z"/>',
    point_to_point: '<circle cx="5" cy="18" r="2"/><circle cx="19" cy="6" r="2"/><path d="M7 17c4-1 3-7 7-7h3"/><path class="accent" d="m14 7 3 3-3 3"/>',
    signup: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M8 3v4m8-4v4M8 12h8m-4-4v8"/>',
    registered: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M8 3v4m8-4v4m-7 7 2 2 5-5"/>',
    upcoming: '<path d="M7 3h10M7 21h10M8 3c0 5 3 5 4 9-1 4-4 4-4 9m8-18c0 5-3 5-4 9 1 4 4 4 4 9"/>',
    live: '<path class="accent fill" d="m8 5 11 7-11 7Z"/>',
    completed: '<path d="M5 3v18M7 5h12l-3 4 3 4H7"/><path class="accent" d="m9 9 2 2 5-5"/>',
    cancelled: '<path d="m5 5 14 14M19 5 5 19"/>',
    full: '<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2"/><path d="M3 20c0-5 3-7 6-7s6 2 6 7m0-6c3 0 5 2 5 6"/>',
    private: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3"/>',
    history: '<path d="M4 20V10m5 10V5m5 15v-7m5 7V3"/><path class="accent" d="M3 21h18"/>',
    incident: '<path d="m12 3 10 18H2Z"/><path class="accent" d="M12 9v5m0 3v.1"/>',
    penalty: '<path d="M5 3v18M7 5h12l-3 4 3 4H7"/>',
    disconnect: '<path d="M4 9a12 12 0 0 1 16 0M7 13a8 8 0 0 1 10 0m-6 5h2"/><path class="accent" d="m4 4 16 16"/>',
    formation: '<rect x="3" y="5" width="7" height="5" rx="1"/><rect x="14" y="5" width="7" height="5" rx="1"/><rect x="3" y="15" width="7" height="5" rx="1"/><rect x="14" y="15" width="7" height="5" rx="1"/>',
    finish: '<path d="M5 3v18M7 5h12v10H7"/><path class="accent fill" d="M7 5h6v5H7zm6 5h6v5h-6z"/>',
    message: '<path d="M3 5h18v13H8l-5 3Z"/><path class="accent" d="M7 9h10M7 13h7"/>',
    enter: '<path d="M4 12h12m-4-4 4 4-4 4M14 4h6v16h-6"/>',
    withdraw: '<path d="M20 12H8m4-4-4 4 4 4M10 4H4v16h6"/>',
    // Weather FAMILIES, not the eight presets (core/world/weather.lua FAMILY): dry / wet / obscured /
    // hazardous. Four marks are what the forecast can honestly distinguish at a glance, and a family survives
    // the preset vocabulary changing under us -- 11_WEATHER.md still lists the final classification as open.
    wx_dry: '<circle cx="12" cy="12" r="5"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5M17.5 17.5 19 19M19 5l-1.5 1.5M6.5 17.5 5 19"/>',
    wx_wet: '<path d="M7 15a4 4 0 0 1 .4-8 5.5 5.5 0 0 1 10.3 1.6A3.5 3.5 0 0 1 17.5 15Z"/><path class="accent" d="M8 18l-1 3m5-3-1 3m5-3-1 3"/>',
    wx_obscured: '<path d="M4 10h13M6 14h12M8 18h9"/><path d="M6 6h11"/>',
    wx_hazardous: '<path d="M12 3 2 20h20Z"/><path class="accent" d="M12 9v5"/><path class="accent fill" d="M11.2 16.2h1.6v1.6h-1.6z"/>',
    // "what car do I need" and "what are the rules" -- IDEA-124 / IDEA-125
    car_req: '<path d="M3 15h18M5 15l2-6h10l2 6v4h-3v-2H8v2H5Z"/><circle class="accent" cx="8" cy="15.5" r="1.3"/><circle class="accent" cx="16" cy="15.5" r="1.3"/>',
    regs: '<path d="M6 3h9l3 3v15H6Z"/><path class="accent" d="M9 9h7M9 13h7M9 17h4"/>'
  };

  function create(name, label) {
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("class", "ncm-glyph ncm-glyph--" + name);
    svg.setAttribute("aria-hidden", label ? "false" : "true");
    if (label) { svg.setAttribute("role", "img"); svg.setAttribute("aria-label", label); }
    svg.innerHTML = symbols[name] || symbols.incident;
    return svg;
  }

  window.NcmGlyph = { create, has: (name) => !!symbols[name], ids: Object.freeze(Object.keys(symbols)) };
})();
