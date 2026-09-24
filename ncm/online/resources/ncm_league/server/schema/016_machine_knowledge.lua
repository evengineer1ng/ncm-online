-- Schema 016: durable evidence beneath the Machine Index.
-- `vehicle_discovery` remains the compatible first-identity summary and Discoveries Inspired source. This
-- table is deliberately narrower than a universal ledger: one Driver's evidence about one vehicle model,
-- optionally tied to a persistent physical asset. Unknown information is represented by no row.
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 16,
    name = "machine_knowledge",
    statements = {
        -- A market reveal is not a physical encounter. Keep the old summary table, but stop forcing it to lie:
        -- no encounter timestamp and a zero encounter count are valid for identity learned from stock/publication.
        [[ALTER TABLE vehicle_discovery
            MODIFY last_encounter_at BIGINT NULL,
            MODIFY encounter_count INT UNSIGNED NOT NULL DEFAULT 0]],
        [[CREATE TABLE IF NOT EXISTS vehicle_knowledge_evidence (
            evidence_id CHAR(36) NOT NULL,
            evidence_key VARCHAR(190) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            vehicle_key VARCHAR(96) NOT NULL,
            asset_id CHAR(36) NULL,
            knowledge_kind VARCHAR(48) NOT NULL,
            source_kind VARCHAR(48) NOT NULL,
            epistemic_kind VARCHAR(32) NULL,
            observed_at BIGINT NOT NULL,
            evidence_json LONGTEXT NULL,
            PRIMARY KEY (evidence_id),
            UNIQUE KEY uq_vehicle_knowledge_retry (ncm_driver_id, server_id, evidence_key),
            KEY ix_vehicle_knowledge_model (ncm_driver_id, server_id, vehicle_key, observed_at),
            KEY ix_vehicle_knowledge_asset (asset_id, observed_at),
            CONSTRAINT fk_vehicle_knowledge_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver(ncm_driver_id),
            CONSTRAINT fk_vehicle_knowledge_asset FOREIGN KEY (asset_id)
                REFERENCES vehicle_asset(asset_id),
            CHECK (JSON_VALID(evidence_json) OR evidence_json IS NULL)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Existing discovery facts are not discarded or silently promoted to omniscient knowledge. Each
        -- becomes exactly one observed identity reveal. Deterministic evidence_key + NOT EXISTS makes replay
        -- safe; UUID is only the opaque row identity.
        [[INSERT INTO vehicle_knowledge_evidence
              (evidence_id, evidence_key, ncm_driver_id, server_id, vehicle_key, asset_id,
               knowledge_kind, source_kind, epistemic_kind, observed_at, evidence_json)
          SELECT UUID(), CONCAT('identity:', d.vehicle_key), d.ncm_driver_id, d.server_id, d.vehicle_key,
                 d.source_asset_id, 'identity_reveal',
                 CASE d.discovery_method
                   WHEN 'proximity_dwell' THEN 'world_encounter'
                   ELSE d.discovery_method
                 END,
                 'observed', d.first_discovered_at, NULL
            FROM vehicle_discovery d
           WHERE NOT EXISTS (
                 SELECT 1 FROM vehicle_knowledge_evidence e
                  WHERE e.ncm_driver_id = d.ncm_driver_id
                    AND e.server_id = d.server_id
                    AND e.evidence_key = CONCAT('identity:', d.vehicle_key))]],
    },
}
