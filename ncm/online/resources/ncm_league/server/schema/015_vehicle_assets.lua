-- ncm_league schema 015: ownership becomes asset-keyed (IDEA-157).
--
-- 012 keyed `owned_vehicle` on `(ncm_driver_id, server_id, record)` -- one row per MODEL. That made "this
-- driver owns a Caliburn" expressible and "this driver owns two Caliburns" impossible: the second INSERT hit
-- the ON DUPLICATE KEY path and silently became the first one again. Spec 2's individuality model, spec 1's
-- trading, and the Collection's distinction between discovery and ownership all need the opposite -- a row per
-- PHYSICAL EXAMPLE, with an identity that survives being sold, re-liveried, or renamed upstream by a mod.
--
-- **This is the cheap moment and it does not come back.** 012 holds a handful of seeded alpha rows, so the
-- backfill below is trivial; once real ownership history exists, changing the primary key of this table stops
-- being a migration and starts being a data-loss risk.
--
-- Three identifiers, never collapsed (13_VEHICLE_COLLECTION.md):
--
--   asset_id     this physical example. Permanent, survives transfer. CHAR(36) to match the `source_asset_id`
--                column that 014 already reserved for exactly this.
--   vehicle_key  the conceptual machine. Survives a TweakDB record being renamed by a mod update, which is the
--                entire reason it is STORED here rather than derived from `record` on every read.
--   record       the exact runtime record. Still the spawn / eligibility / performance key, carried on every
--                row so `competition.eligibility` and the Guide keep working untouched across this change.
--
-- **Deliberately NOT in this migration:**
--
--   * `owner_principal_kind/id` (IDEA-168, team-owned cars). It is a cheap later ALTER *precisely because* the
--     primary key is the asset rather than the owner -- which is the point of this migration. Adding a column
--     nothing can populate yet would be inventing team economics, and §28 of spec 3 forbids that.
--   * `disposed_at` / soft deletion. Trading and disposal (IDEA-139) want a transfer LOG, not a flag, and
--     guessing the shape now would force every consumer to filter on a column whose meaning is not settled.
--   * any notion of price, condition, mileage or configuration. Those are spec 2's, and L85 hold #2 still
--     stands: the economy does not begin until Deploy 11 QA is validated.
--
-- `owned_vehicle` is left untouched -- not renamed, not dropped. It is the rollback path for a migration that
-- has never run against a real database, and a rename would not survive a replay. See the note beside the last
-- statement for why that matters more than tidiness here.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 15,
    name = "vehicle_assets",
    statements = {
        [[CREATE TABLE IF NOT EXISTS vehicle_asset (
            asset_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            -- The owner. IDEA-168 will generalise this to an owner principal so an organization can hold
            -- title; that stays a cheap ALTER because nothing keys off it.
            ncm_driver_id CHAR(36) NOT NULL,
            -- NULL is legitimate: an authored or team car the catalogue does not know. Resolved at mint time
            -- and then left alone, so a later record rename cannot orphan the machine's identity.
            vehicle_key VARCHAR(96) NULL,
            record VARCHAR(256) NOT NULL,
            class VARCHAR(32) NULL,
            -- Exactly 012's vocabulary, deliberately. There is no 'migration' value: a seeded car was SEEDED,
            -- and stamping the backfill over that would destroy the one thing 012 built this column for --
            -- keeping a seeded garage distinguishable from an earned one forever.
            acquired_via ENUM('grant','progression','prize','purchase','seed') NOT NULL DEFAULT 'grant',
            granted_by VARCHAR(96) NULL,
            acquired_at BIGINT NOT NULL,
            PRIMARY KEY (asset_id),
            -- the garage read: everything one driver holds on one server
            KEY ix_vehicle_asset_owner (ncm_driver_id, server_id),
            -- "how many of this machine exist here" (supply, IDEA-155) and "who holds one"
            KEY ix_vehicle_asset_key (server_id, vehicle_key),
            KEY ix_vehicle_asset_record (server_id, record),
            CONSTRAINT fk_vehicle_asset_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver(ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Backfill. One asset per existing title, which is the only honest reading of the old rows: a
        -- record-keyed table could never have meant more than one. `UUID()` rather than Lua ids because this
        -- runs once, inside the migration transaction, before any Lua has a chance to see the table.
        --
        -- `vehicle_key` is left NULL here on purpose -- SQL cannot resolve a record through the catalogue.
        -- `ownership.lua` backfills it once on start, where the catalogue exists.
        --
        -- INSERT IGNORE + the NOT EXISTS guard make a re-run (a restored database, a hand-replayed migration)
        -- a no-op instead of a second garage.
        [[INSERT IGNORE INTO vehicle_asset
              (asset_id, server_id, ncm_driver_id, vehicle_key, record, class, acquired_via, granted_by, acquired_at)
          SELECT UUID(), o.server_id, o.ncm_driver_id, NULL, o.record, o.class,
                 o.acquired_via, o.granted_by, o.acquired_at
            FROM owned_vehicle o
           WHERE NOT EXISTS (
                 SELECT 1 FROM vehicle_asset a
                  WHERE a.ncm_driver_id = o.ncm_driver_id
                    AND a.server_id = o.server_id
                    AND a.record = o.record)]],

        -- `owned_vehicle` is deliberately LEFT IN PLACE, neither renamed nor dropped.
        --
        -- The first instinct was to rename it, so no later reader mistakes it for the live table. Two reasons
        -- not to. **It is the rollback path**, and this migration has never run against a real database --
        -- keeping the old rows until `vehicle_asset` has a live PASS beside it costs one unread table and buys
        -- the ability to be wrong. **And a rename is not safely re-runnable**: MariaDB commits DDL implicitly,
        -- so if a later statement in this migration failed, the version row would not be written, the next
        -- start would replay the list, and `RENAME` would fail on a table that had already moved -- wedging
        -- migrations permanently on a table nothing reads. Every statement above survives a replay; that one
        -- would not.
        --
        -- Dropping it is a one-line follow-up migration once §U passes. Until then nothing in NCM reads it:
        -- `ownership.lua` moved to `vehicle_asset` wholesale, and it is the only file that ever touched either.
    },
}
