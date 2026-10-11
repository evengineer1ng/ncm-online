NcmSchema=NcmSchema or {}
-- IDEA-1282: the Build primitive. One row per attachment, its transform RELATIVE TO ITS PARENT (a Machine, or another
-- attachment: chains), never a world coordinate. Keyed by the Machine's permanent asset id (root_machine_id), not by a
-- spawned vehicle, so a wing comes back with that Mai Mai after a recall and goes with it on a trade. Removal is a
-- soft delete (removed_at, removed_by): the Machine's physical history is kept. revision counts edits.
NcmSchema[#NcmSchema+1]={version=78,name="build_attachment",statements={
[[CREATE TABLE IF NOT EXISTS build_attachment (
 attachment_id CHAR(36) NOT NULL, server_id VARCHAR(96) NOT NULL, build_asset_id VARCHAR(48) NOT NULL,
 parent_kind VARCHAR(16) NOT NULL, parent_id CHAR(36) NOT NULL, root_machine_id CHAR(36) NOT NULL,
 pos_x DOUBLE NOT NULL, pos_y DOUBLE NOT NULL, pos_z DOUBLE NOT NULL,
 rot_roll DOUBLE NOT NULL, rot_pitch DOUBLE NOT NULL, rot_yaw DOUBLE NOT NULL,
 builder_driver_id CHAR(36) NOT NULL, provenance VARCHAR(32) NOT NULL DEFAULT 'player_build',
 created_at BIGINT NOT NULL, updated_at BIGINT NOT NULL, revision INT NOT NULL DEFAULT 1,
 removed_at BIGINT NULL, removed_by CHAR(36) NULL,
 PRIMARY KEY(attachment_id), KEY ix_build_attachment_root(server_id, root_machine_id, removed_at),
 KEY ix_build_attachment_builder(server_id, builder_driver_id, removed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}}
