-- ncm-core data: data.grid_overrides
-- The owner's hand-tuned start grids (L250 step 1). The baked grid (`tools/bake-grids.py`, lane-based) stands unless a
-- start or a leg is listed here. `tools/grid-report.md` lists the starts that need one (formation, columns, depth,
-- short legs).
--
--   NODES["<start node id>"] = { ... }            applies to every leg from that start
--   LEGS["<start id>__<next id>"] = { ... }       one leg only (wins over NODES)
--
-- Fields (all optional):
--   slots       = { { x, y, z, heading }, ... }    the grid, pole first (replaces the bake entirely)
--   excludeCols = { 3 }                            drop baked columns (1 = the pole's, leftmost)
local Core = NcmCore

Core.define("data.grid_overrides", function(C)
    local M = { version = "0.1.0" }
    M.NODES = {}
    M.LEGS = {}
    return M
end)
