-- NCM Online: Race Week Live, the deterministic Race Week talk-radio station (doc 59, L348).
--
-- Writers authored every line (docs/ncm-online/radio/RACE_WEEK_RADIO_BIBLE.md); the simulation decides which beat
-- airs and which names fill it; the voices are pre-rendered and ship in the `ncm-radio` required mod beside the
-- player-side plugin that plays them. No LLM anywhere, no text generated at runtime.
--
-- A resource of its own (feedback: new features, new mods): it reads the Paddock's and the Week's tables (SELECT
-- only), never writes a game table, and shares no memory with ncm_paddock / ncm_world / ncm_league.
-- `radioEnabled` is the kill switch.
resource "ncm_radio"
version "0.1.0"
auto_start true

-- database.access: SELECT on the tape, the Week and results. network.events: the programme to each listener.
-- filesystem.read/write: lexicon.json (the names the voice render still has to voice) and history/<driver>.json (each
-- listener's show history, bible §247) in this resource's data directory.
permissions { "database.access", "network.events", "filesystem.read", "filesystem.write" }

server_script "server/corpus_data.lua"
server_script "server/spoken.lua"
server_script "server/clock.lua"
server_script "server/director.lua"
server_script "server/facts.lua"
server_script "server/main.lua"

client_script "client/radio.lua"
