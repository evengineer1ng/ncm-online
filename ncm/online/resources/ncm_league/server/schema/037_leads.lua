-- ncm_league schema 037: Leads -- knowledge the player cannot yet use (L175).
--
-- The middle state between unknown and accessible. `17_MARKET_NETWORK.md` separated knowledge from access
-- ("knowledge and access may diverge") and left `player_market_knowledge` as a shape; this generalises that
-- shape so one table can hold a market heard of, a Design whose origin is unknown, a person mentioned but not
-- met, and a place named but not found. Vocabulary and the state machine live in core `player.leads`.
--
-- **Identity is the subject, not the telling.** The primary key is (driver, server, subject_kind, subject_ref),
-- so two characters mentioning the same market are one lead learned twice. That matters because "multiple
-- unresolved leads" is Glass's trigger, and a key on the *source* would count gossip rather than mystery.
--
-- **`source_kind` / `source_ref` are not decoration.** They are what later characters react to: "Rico told you"
-- and "it was stamped on a part you were traded" are different stories, and `IDEA-609` (trade provenance
-- creates a lead) depends entirely on that distinction surviving into the row.
--
-- **No ordering, no step, no objective text.** A lead is not a quest (L175). It resolves when its subject
-- becomes reachable through ANY route, including routes nobody authored -- which is why `resolved_reason` is
-- free text for the record and `state` is not.
--
-- **Nothing here is a completion metric.** L171's leak discipline and L175 both forbid a checklist: no count,
-- no percentage, no "3 / 8 followed" may be derived from this table for a player-facing surface.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 37,
    name = "leads",
    statements = {
        [[CREATE TABLE IF NOT EXISTS lead (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            subject_kind ENUM('market','machine','design','manufacturer','person','place','event','research') NOT NULL,
            subject_ref VARCHAR(96) NOT NULL,
            source_kind ENUM('character','provenance','observation','research','market','event','world','dispatch') NOT NULL,
            source_ref VARCHAR(96) NULL,
            note VARCHAR(240) NULL,
            state ENUM('open','closed','cold') NOT NULL DEFAULT 'open',
            created_at BIGINT NOT NULL,
            resolved_at BIGINT NULL,
            resolved_reason VARCHAR(120) NULL,
            PRIMARY KEY (ncm_driver_id, server_id, subject_kind, subject_ref),
            KEY ix_lead_open (server_id, ncm_driver_id, state, created_at),
            CONSTRAINT fk_lead_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
