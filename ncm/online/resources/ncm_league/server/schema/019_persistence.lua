-- ncm_league schema 019: where a driver was, and what colour their machines are.
--
-- Two owner rulings, one migration, because both are "a fact that must survive the session".
--
-- **L110 — where you log out is where you log in.** `driver_location` is a property of the WORLD, not of
-- racing: freeroam and races alike. One row per driver per server, overwritten as they move. It is NOT a
-- history and must never become one -- nobody needs a breadcrumb trail of where a player has been, and
-- collecting one would be surveillance rather than persistence.
--
-- `in_vehicle` is recorded so a restore can REFUSE. A seat is not a place: the vehicle it belonged to is very
-- likely gone by the time they return, and arriving inside a vehicle that no longer exists is the classic
-- wedge. We store the fact in order to decline, not in order to use it.
--
-- **L111 — colour is deterministic and supply-constrained.** Two columns on `vehicle_asset`, written when the
-- machine is minted and never re-rolled. They are NULLABLE and that is meaningful: NULL means "nobody has
-- authored this machine's finish", and `data.vehicle_config` then supplies the factory default deterministically
-- from the assetId, constrained to the range that model is actually produced in. So every existing asset keeps
-- a stable colour from the moment this deploys, with no backfill -- and when allocation (IDEA-144-148) becomes
-- the author of appearance, it writes these columns and they win.
--
-- Deliberately NOT here: a parts or trim column. Parts do not exist yet, and a nullable column nothing writes
-- is the speculative modelling this project has already decided against twice.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 19,
    name = "persistence",
    statements = {
        [[CREATE TABLE IF NOT EXISTS driver_location (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            heading DOUBLE NULL,
            bucket INT NOT NULL DEFAULT 0,
            in_vehicle TINYINT(1) NOT NULL DEFAULT 0,
            saved_at BIGINT NOT NULL,
            PRIMARY KEY (ncm_driver_id, server_id),
            CONSTRAINT fk_driver_location_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver(ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- `#RRGGBB`, so the table is readable by a human. NULL = unauthored, see the note above.
        --
        -- `IF NOT EXISTS` is load-bearing, not decoration: a plain ADD COLUMN is **not replay-safe**, and
        -- MariaDB commits DDL implicitly. If a later statement in this migration failed, the version row would
        -- not be written, the next start would replay the list, and a duplicate-column error would wedge the
        -- runner permanently -- exactly the trap migration 015 avoided by not renaming a table. Verified
        -- against the live MariaDB 10.11 in a scratch schema: first run adds, replay is a clean no-op.
        [[ALTER TABLE vehicle_asset
            ADD COLUMN IF NOT EXISTS paint_primary CHAR(7) NULL,
            ADD COLUMN IF NOT EXISTS paint_secondary CHAR(7) NULL]],
    },
}
