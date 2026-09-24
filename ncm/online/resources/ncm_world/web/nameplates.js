(function () {
  "use strict";

  var MAX_BADGES = 3;
  var DEFAULT_BANNER = "ncm_default";
  var root = document.getElementById("nameplates");
  var cards = new Map();
  var latestPlayers = new Map();
  var presentationById = new Map();
  var assets = { banners: {}, badges: {} };
  var assetGeneration = 0;

  function safeName(value) {
    var name = typeof value === "string" ? value.trim() : "";
    if (!name) return "Unknown driver";
    return Array.from(name).slice(0, 64).join("");
  }

  function normalizeAssets(value) {
    var next = { banners: {}, badges: {} };
    var banners = value && Array.isArray(value.banners) ? value.banners : [];
    var badges = value && Array.isArray(value.badges) ? value.badges : [];
    banners.forEach(function (entry) {
      if (entry && typeof entry.id === "string") next.banners[entry.id] = entry;
    });
    badges.forEach(function (entry) {
      if (entry && typeof entry.id === "string") next.badges[entry.id] = entry;
    });
    assets = next;
    assetGeneration++;
  }

  function safeBannerImage(value) {
    var image = typeof value === "string" ? value : "";
    return /^assets\/banners\/[a-z0-9_-]+\.svg$/i.test(image) ? image : "";
  }

  function normalizePresentation(value) {
    var source = value && typeof value === "object" ? value : {};
    var bannerId = typeof source.bannerId === "string" && assets.banners[source.bannerId]
      ? source.bannerId
      : DEFAULT_BANNER;
    if (!assets.banners[bannerId]) {
      var available = Object.keys(assets.banners);
      bannerId = available.length ? available[0] : DEFAULT_BANNER;
    }

    var seen = {};
    var displayedBadgeIds = [];
    if (Array.isArray(source.displayedBadgeIds)) {
      source.displayedBadgeIds.forEach(function (id) {
        if (displayedBadgeIds.length >= MAX_BADGES) return;
        if (typeof id !== "string" || seen[id] || !assets.badges[id]) return;
        seen[id] = true;
        displayedBadgeIds.push(id);
      });
    }

    return {
      schemaVersion: 1,
      bannerId: bannerId,
      displayedBadgeIds: displayedBadgeIds,
      fingerprint: {
        definitionVersion: 0,
        values: [],
        sampleState: "unavailable"
      }
    };
  }

  function staleIds(currentIds, players) {
    var present = {};
    (Array.isArray(players) ? players : []).forEach(function (player) {
      if (player && player.id !== undefined && player.id !== null) present[String(player.id)] = true;
    });
    return (Array.isArray(currentIds) ? currentIds : []).filter(function (id) {
      return !present[String(id)];
    });
  }

  function fallbackGlyph() {
    var ns = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    var p = document.createElementNS(ns, "path");
    p.setAttribute("d", "M7 12h10M12 7v10");
    svg.appendChild(p);
    return svg;
  }

  function createCard(id) {
    var card = document.createElement("section");
    card.className = "ncm-card";
    card.dataset.playerId = String(id);
    card.innerHTML =
      '<div class="ncm-card__banner">' +
        '<div class="ncm-card__banner-art" aria-hidden="true"></div>' +
        '<div class="ncm-card__identity">' +
          '<div class="ncm-card__eyebrow"><i class="ncm-card__voice"></i>NCM DRIVER</div>' +
          '<span class="ncm-card__name"></span>' +
        '</div>' +
        '<div class="ncm-card__badges"></div>' +
      '</div>' +
      '<aside class="ncm-card__fingerprint" aria-label="Driver Fingerprint unavailable">' +
        '<div class="ncm-card__fingerprint-title">FINGERPRINT</div>' +
        '<div class="ncm-card__fingerprint-state">Unavailable</div>' +
        '<div class="ncm-card__fingerprint-note">Insufficient data</div>' +
      '</aside>';
    root.appendChild(card);
    cards.set(String(id), card);
    return card;
  }

  function renderBadgeRow(card, presentation) {
    var row = card.querySelector(".ncm-card__badges");
    while (row.firstChild) row.removeChild(row.firstChild);
    presentation.displayedBadgeIds.forEach(function (id) {
      var definition = assets.badges[id];
      if (!definition) return;
      var badge = document.createElement("span");
      badge.className = "ncm-card__badge";
      badge.dataset.badgeId = id;
      badge.setAttribute("aria-label", definition.label || "Driver badge");
      var glyphId = definition.glyphId || definition.glyph;
      if (window.NcmGlyph && window.NcmGlyph.has(glyphId)) {
        badge.appendChild(window.NcmGlyph.create(glyphId));
      } else {
        badge.appendChild(fallbackGlyph());
      }
      row.appendChild(badge);
    });
  }

  function renderPlayer(player) {
    if (!player || player.id === undefined || player.id === null) return;
    var id = String(player.id);
    var card = cards.get(id) || createCard(id);
    var presentation = normalizePresentation(presentationById.get(id));
    var name = safeName(player.label);
    var nameNode = card.querySelector(".ncm-card__name");
    if (nameNode.textContent !== name) {
      nameNode.textContent = name;
      nameNode.title = name;
    }
    card.classList.toggle("ncm-card--talking", !!player.talking);
    var x = Math.max(0, Math.min(1, Number(player.x) || 0));
    var y = Math.max(0, Math.min(1, Number(player.y) || 0));
    var distance = Math.max(0, Number(player.distance) || 0);
    card.style.left = (x * 100) + "%";
    card.style.top = (y * 100) + "%";
    card.style.setProperty("--card-opacity", String(Math.max(0.42, 1 - distance / 80)));
    var presentationSignature = assetGeneration + "|" + presentation.bannerId + "|" + presentation.displayedBadgeIds.join(",");
    if (card.dataset.presentationSignature !== presentationSignature) {
      card.dataset.presentationSignature = presentationSignature;
      card.dataset.bannerId = presentation.bannerId;
      card.classList.toggle("ncm-card--banner-development", presentation.bannerId === "ncm_development");
      var bannerDefinition = assets.banners[presentation.bannerId] || {};
      var art = card.querySelector(".ncm-card__banner-art");
      var image = safeBannerImage(bannerDefinition.image);
      art.style.backgroundImage = image ? 'url("' + image + '")' : "none";
      art.style.backgroundPosition = typeof bannerDefinition.crop === "string" ? bannerDefinition.crop : "50% 50%";
      renderBadgeRow(card, presentation);
    }
  }

  function updatePlayers(event) {
    var players = event && Array.isArray(event.players) ? event.players : [];
    var present = {};
    players.forEach(function (player) {
      if (!player || player.id === undefined || player.id === null) return;
      var id = String(player.id);
      present[id] = true;
      latestPlayers.set(id, player);
      renderPlayer(player);
    });
    cards.forEach(function (card, id) {
      if (present[id]) return;
      card.remove();
      cards.delete(id);
      latestPlayers.delete(id);
    });
  }

  function updatePresentations(event) {
    presentationById.clear();
    var rows = event && Array.isArray(event.rows) ? event.rows : [];
    rows.forEach(function (row) {
      if (!row || row.id === undefined || row.id === null) return;
      presentationById.set(String(row.id), normalizePresentation(row.presentation));
    });
    cards.forEach(function (_card, id) {
      var player = latestPlayers.get(id);
      if (player) renderPlayer(player);
    });
  }

  function onStreamEvent(event) {
    try {
      if (!event || typeof event.type !== "string") return;
      if (event.type === "nameplates:update") updatePlayers(event);
      if (event.type === "ncm-card:assets") {
        normalizeAssets(event.assets);
        updatePresentations({ rows: Array.from(presentationById, function (row) {
          return { id: row[0], presentation: row[1] };
        }) });
      }
      if (event.type === "ncm-card:presentations") updatePresentations(event);
    } catch (error) {
      Open77.emit("ncm-card:error", { message: String(error && error.message || error) });
    }
  }

  Open77.on("nameplates:update", function (event) {
    onStreamEvent({ type: "nameplates:update", players: event && event.players });
  });
  Open77.on("ncm-card:assets", function (event) {
    onStreamEvent({ type: "ncm-card:assets", assets: event });
  });
  Open77.on("ncm-card:presentations", function (event) {
    onStreamEvent({ type: "ncm-card:presentations", rows: event && event.rows });
  });

  window.addEventListener("error", function (event) {
    Open77.emit("ncm-card:error", { message: String(event && event.message || "WebUI error") });
  });
  window.addEventListener("unhandledrejection", function (event) {
    Open77.emit("ncm-card:error", { message: String(event && event.reason || "WebUI rejection") });
  });

  window.NcmDriverCards = {
    safeName: safeName,
    normalizePresentation: normalizePresentation,
    staleIds: staleIds,
    onStreamEvent: onStreamEvent,
    count: function () { return cards.size; }
  };

  Open77.ready();
  Open77.emit("ncm-card:ready", {});
  window.setInterval(function () { Open77.emit("ncm-card:heartbeat", {}); }, 1000);
}());
