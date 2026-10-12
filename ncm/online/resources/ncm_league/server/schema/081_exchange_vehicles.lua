NcmSchema=NcmSchema or {}
-- 2026-10-12 (owner: NPC resales "should never have been able to sell back to manufacturer to begin with"; live: 24 of
-- Base Market's 29 Galenas and 20 of Badlands 01's 25 Colby pickups were NPC trade-ins on new-car shelves).
--   exchange_post.asset_kind   'part' (as before) or 'vehicle': a whole car offered on the Exchange
--   the backfill               every used car standing on a manufacturer shelf goes back to the NPC that traded it
--                              in (its latest `traded_in` transfer names them), marked lifecycle 'npc_spare'; its
--                              shelf row is withdrawn (kept, never deleted). The Paddock's Exchange pass then posts it.
--                              Its installed parts follow it back to the same owner.
NcmSchema[#NcmSchema+1]={version=81,name="exchange_vehicles",statements={
[[ALTER TABLE exchange_post ADD COLUMN IF NOT EXISTS asset_kind VARCHAR(16) NOT NULL DEFAULT 'part']],
[[UPDATE vehicle_asset a
  JOIN market_inventory mi ON mi.asset_id = a.asset_id AND mi.state = 'available'
  JOIN (SELECT t.asset_id, t.from_principal FROM vehicle_asset_transfer t
        JOIN (SELECT asset_id, MAX(occurred_at) AS m FROM vehicle_asset_transfer WHERE kind = 'traded_in' GROUP BY asset_id) x
          ON x.asset_id = t.asset_id AND x.m = t.occurred_at
        WHERE t.kind = 'traded_in' AND t.from_principal LIKE '%:%') tr ON tr.asset_id = a.asset_id
  SET a.owner_principal_kind = SUBSTRING_INDEX(tr.from_principal, ':', 1),
      a.owner_principal_id = SUBSTRING(tr.from_principal, LOCATE(':', tr.from_principal) + 1),
      a.lifecycle = 'npc_spare', mi.state = 'withdrawn'
  WHERE a.ncm_driver_id IS NULL AND a.origin = 'paddock_genesis']],
[[UPDATE component_asset c JOIN vehicle_asset a ON a.asset_id = c.machine_asset_id
  SET c.owner_principal_kind = a.owner_principal_kind, c.owner_principal_id = a.owner_principal_id
  WHERE a.lifecycle = 'npc_spare' AND c.location_kind = 'installed' AND c.ncm_driver_id IS NULL AND c.owner_principal_kind IS NULL]],
}}
