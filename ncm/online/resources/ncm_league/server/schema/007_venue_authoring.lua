-- ncm_league schema 007: venue authoring (M7.5.1; P26, P35, P36). Points and routes captured by the owner in the world:
-- tester spawn spots, chauffeur nodes, paddock/drop-off, grid, and the followRoute point lists between them.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 7,
    name = "venue_authoring",
    statements = {
        [[CREATE TABLE IF NOT EXISTS venue_point (
            server_id VARCHAR(96) NOT NULL,
            venue_id VARCHAR(64) NOT NULL,
            kind VARCHAR(16) NOT NULL,
            point_key VARCHAR(32) NOT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            heading DOUBLE NOT NULL DEFAULT 0,
            meta_json JSON NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (server_id, venue_id, kind, point_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS venue_route (
            server_id VARCHAR(96) NOT NULL,
            venue_id VARCHAR(64) NOT NULL,
            route_key VARCHAR(32) NOT NULL,
            from_kind VARCHAR(16) NOT NULL,
            from_key VARCHAR(32) NOT NULL,
            to_kind VARCHAR(16) NOT NULL,
            to_key VARCHAR(32) NOT NULL,
            points_json JSON NOT NULL,
            length_m DOUBLE NOT NULL DEFAULT 0,
            recorded_by CHAR(36) NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (server_id, venue_id, route_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
