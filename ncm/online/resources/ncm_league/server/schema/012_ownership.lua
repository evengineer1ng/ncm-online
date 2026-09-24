-- ncm_league schema 012: the ownership ledger (L83, IDEA-115).
--
-- L55 described `owned_vehicle` rows per driver from the start and the table was never built; `issued_vehicle`
-- has always been the only garage table, and its `model` column already reserves `'owned'` and `'byo'` for this.
-- Ownership is what makes L83 enforceable: drivers bring their own car, earned through progression, and an entry
-- they do not own is refused rather than substituted.
--
-- One row per (driver, server, record). Ownership is per server because a driver's history is per server
-- (L54/L55 ledger scoping) -- the same person on another NCM server starts again there.
--
-- `acquired_via` is deliberately coarse and free-ish: how a car was come by is history we will want later
-- (progression, prize, purchase, host grant) and it costs nothing to record now. `granted_by` names the operator
-- for host grants, so a seeded garage is always distinguishable from an earned one.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 12,
    name = "ownership",
    statements = {
        [[CREATE TABLE IF NOT EXISTS owned_vehicle (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            record VARCHAR(256) NOT NULL,
            class VARCHAR(32) NULL,
            acquired_via ENUM('grant','progression','prize','purchase','seed') NOT NULL DEFAULT 'grant',
            granted_by VARCHAR(96) NULL,
            acquired_at BIGINT NOT NULL,
            PRIMARY KEY (ncm_driver_id, server_id, record),
            KEY ix_owned_driver (ncm_driver_id, server_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
