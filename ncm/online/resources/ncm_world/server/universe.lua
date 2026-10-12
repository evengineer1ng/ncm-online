-- ncm_world / server / universe -- doc 57 §5: load the star catalogue into this resource's space.catalogue a chunk per
-- tick (OPEN//77 meters instructions per call), so the server's unhosted Deep flight feels every relevant star exactly
-- as the substrate says. The Solar System is in from the first gravity call; until the stars are in, a vehicle between
-- the stars would only miss pulls that are below the field's floor inside the Solar System anyway.
CreateThread(function()
    local Cat = NcmCore.get("space.catalogue")
    local steps = 0
    while true do
        local ok, done, text = pcall(Cat.loadStep)
        steps = steps + 1
        if not ok then print("[ncm_world/universe] star catalogue load FAILED: " .. tostring(done)); return end
        if done then
            print(("[ncm_world/universe] catalogue ready in %d steps: %d records, %d stars"):format(steps, #Cat.list(), Cat.starCount()))
            return
        end
        Wait(0)
    end
end)
