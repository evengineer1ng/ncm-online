-- ncm_league schema 001: identity (architecture §5; decision record L11, P2, L21).
-- Loaded before migrations.lua (manifest order). Registers itself on a global list the runner reads.
-- Statements are idempotent (IF NOT EXISTS) so a partially applied migration can be re-run safely.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 1,
    name = "identity",
    statements = {
        -- One NCM Driver, minted by NCM (uuid), never by a server.
        [[CREATE TABLE IF NOT EXISTS ncm_driver (
            ncm_driver_id CHAR(36) NOT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            origin ENUM('sp','online') NOT NULL,
            PRIMARY KEY (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Binding between a platform identity (userId) on this server and an NCM Driver.
        [[CREATE TABLE IF NOT EXISTS ncm_driver_binding (
            server_id VARCHAR(96) NOT NULL,
            user_id CHAR(36) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            bound_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (server_id, user_id),
            KEY ix_binding_driver (ncm_driver_id),
            CONSTRAINT fk_binding_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Per-server driver profile. `dimensions` and `sr` are JSON documents (Q19 default: independent dimensions).
        [[CREATE TABLE IF NOT EXISTS driver_profile (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            display VARCHAR(64) NOT NULL,
            number SMALLINT UNSIGNED NULL,
            dimensions JSON NULL,
            sr JSON NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (ncm_driver_id, server_id),
            CONSTRAINT fk_profile_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Content packs known to this server (id@version, hash), enabled flag.
        [[CREATE TABLE IF NOT EXISTS content_pack (
            pack_id VARCHAR(96) NOT NULL,
            version VARCHAR(32) NOT NULL,
            sha256 CHAR(64) NOT NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            registered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (pack_id, version)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
