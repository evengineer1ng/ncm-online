-- The manual clones are generated from core (L306): clones.yaml and the DLL's spec file must equal what
-- `machine.gearbox` produces today. Joins the gate by existing.
local root = arg[1] or "."
arg = { root, "--check" }
dofile(root .. "/tools/gen-gearbox-records.lua")
