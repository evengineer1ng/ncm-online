-- Persist the maker's design competency per physical programme and per continuity.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=72,name="physical_rnd_competency",statements={
[[CREATE TABLE IF NOT EXISTS component_rnd_competency (
 server_id VARCHAR(96) NOT NULL, programme_key VARCHAR(64) NOT NULL,
 design_score INT NOT NULL DEFAULT 0, updated_at BIGINT NOT NULL,
 PRIMARY KEY(server_id,programme_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
