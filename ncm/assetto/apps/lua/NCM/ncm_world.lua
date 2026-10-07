-- NCM Deep's WORLD layer in Assetto Corsa (L332, owner brief 2026-10-06: "more actual geography underneath, fewer pixels
-- spent rendering it, smarter reconstruction on top, and never upscale the HUD").
--
--   geography  core space.geolod plans a clipmap (one 4x4-tile window per zoom 5..16) around the point under the camera
--              and the tiles ahead on the path; the host bridge fetches them (public-domain imagery) into its disk cache;
--              this file draws each into a cell of a 4096x3072 atlas (toroidal: tile x,y lives in slot x%4, y%4) and
--              marks it resident in a 16x12 mask. The shader samples the finest RESIDENT window whose texels are not
--              smaller than the pixel's ground footprint -- a missing tile shows the coarser level, never a blank.
--   world      the planet is ray-traced (camera-relative, stable root) into a canvas at an INTERNAL resolution
--              (100 / 77 / 67 / 59 / 50 %, stepped by the frame rate).
--   reconstruct EASU (edge-adaptive spatial upsampling) to the display size, then RCAS (restrained contrast-adaptive
--              sharpening) in the final pass -- ported from AMD FidelityFX FSR 1 (MIT licence, (c) Advanced Micro
--              Devices) -- which also draws the sky and stars at NATIVE resolution and keeps the depth composition
--              (AC's own track and car stay AC's). The HUD is ui.dwriteDrawText: native, untouched.
-- Anything CSP refuses (a canvas, a shader) turns this layer off and the old direct pass draws the planet -- said in a
-- probe to the bridge, never a broken frame.
local W = {}
local GL, D, post
local BRIDGE = "http://127.0.0.1:47710"
local LEVELS, ZMIN = 12, 5

local RS = { steps = { 1, 0.77, 0.67, 0.59, 0.5 }, i = 2, world = nil, out = nil, broken = nil, frameMs = 16.7, lastT = nil,
  slowSince = nil, fastSince = nil, changedAt = 0, sharp = 0.5, probed = false, size = nil }
local GEO = { ok = false, atlas = nil, res = nil, lev = {}, zFine = -1, credit = nil, dir = nil, planAt = -10, prefetchAt = -10,
  fetching = 0, loaded = 0, failed = 0, marks = {}, probed = false }

local function clock() return (os.preciseClock and os.preciseClock()) or os.clock() end
local function span(z) return 180 / 2 ^ z end

function W.init(Core, postFn)
  GL, D, post = Core.get("space.geolod"), Core.get("space.deep"), postFn
  for li = 1, LEVELS do GEO.lev[li] = { z = ZMIN + li - 1, ox = nil, oy = nil, layer = nil, active = false, slots = {} } end
  -- the bridge says where its tile cache is: AC draws the tiles from those local files
  pcall(web.get, BRIDGE .. "/tiles-status", nil, function(err, r)
    if err or not r or r.status ~= 200 then return end
    local ok, j = pcall(JSON.parse, r.body)
    if ok and type(j) == "table" and j.dir then GEO.dir = j.dir end
  end)
end

local function broken(why)
  if RS.broken then return end
  RS.broken = tostring(why)
  if post then post({ type = "probe", what = "render", ok = false, why = RS.broken }) end
end

-- ------------------------------------------------------------------------------------------------ the clipmap
local function mark(li, s, on) GEO.marks[#GEO.marks + 1] = { li = li, s = s, on = on } end

local function ensureGeo()
  if GEO.ok or GEO.failedInit or not GEO.dir then return GEO.ok end
  local ok, err = pcall(function()
    GEO.atlas = ui.ExtraCanvas(vec2(4096, 3072))
    GEO.res = ui.ExtraCanvas(vec2(16, LEVELS))
    GEO.atlas:clear(rgbm(0, 0, 0, 1))
    GEO.res:clear(rgbm(0, 0, 0, 1))
  end)
  if not ok then GEO.failedInit = true; broken("clipmap canvas: " .. tostring(err)); return false end
  GEO.ok = true
  return true
end

--- the plan (twice a second, around the camera's ground point) and the prefetch along the path (every two seconds)
local function plan(now, lat, lon, alt, p, v, dest, heightPx)
  if now - GEO.planAt < 0.5 then return end
  GEO.planAt = now
  local view = { fovY = RS.fovY or 1.0, heightPx = heightPx }
  local pl = GL.plan(lat, lon, math.max(1, alt), view)
  GEO.zFine, GEO.credit = pl.zFine, GL.credit(pl)
  local act = {}
  for _, l in ipairs(pl.levels) do
    local li = l.z - ZMIN + 1
    local L = GEO.lev[li]
    act[li] = true
    L.active, L.layer, L.ox, L.oy = true, l.layer, l.ox, l.oy
    local cols = 2 ^ (l.z + 1)
    for j = 0, 3 do
      for i = 0, 3 do
        local x, y = ((l.ox + i) % cols + cols) % cols, l.oy + j
        local s = (x % 4) + (y % 4) * 4
        local cur = L.slots[s]
        if not cur or cur.x ~= x or cur.y ~= y then
          if cur and cur.state == "ok" then mark(li, s, false) end
          L.slots[s] = { x = x, y = y, state = l.layer and "want" or "none" }
        end
      end
    end
  end
  for li = 1, LEVELS do if not act[li] then GEO.lev[li].active = false end end
  if now - GEO.prefetchAt >= 2 then
    GEO.prefetchAt = now
    local list = GL.prefetch({ p = p, v = v or { 0, 0, 0 } }, dest, view)
    local ok, body = pcall(JSON.stringify, { tiles = list })
    if ok then pcall(web.post, BRIDGE .. "/tiles/prefetch", { ["Content-Type"] = "application/json" }, body, function() end) end
  end
end

--- fetch through the bridge (it caches to disk), then draw the local file into its atlas slot once CSP has it
local function pump()
  local draws = {}
  for li = 1, LEVELS do
    local L = GEO.lev[li]
    if L.active then
      for s, t in pairs(L.slots) do
        if t.state == "want" and GEO.fetching < 6 then
          t.state = "fetching"
          GEO.fetching = GEO.fetching + 1
          local layer, z = L.layer, L.z
          local ok = pcall(web.get, ("%s/tiles/%s/%d/%d/%d.jpg"):format(BRIDGE, layer, z, t.x, t.y), nil, function(err, r)
            GEO.fetching = GEO.fetching - 1
            if L.slots[s] ~= t then return end
            if not err and r and r.status == 200 then
              t.state, t.path, t.since = "file", ("%s\\%s\\%d\\%d\\%d.jpg"):format(GEO.dir, layer, z, t.x, t.y), clock()
              if not GEO.probed then GEO.probed = true; post({ type = "probe", what = "tiles", ok = true, first = layer .. "/" .. z }) end
            else
              t.state = "none"; GEO.failed = GEO.failed + 1
            end
          end)
          if not ok then GEO.fetching = GEO.fetching - 1; t.state = "none" end
        elseif t.state == "file" then
          local ready = false
          pcall(function() ready = ui.isImageReady(t.path) end)
          if ready then draws[#draws + 1] = { li = li, s = s, t = t }
          elseif clock() - t.since > 20 then t.state = "none"; GEO.failed = GEO.failed + 1 end
        end
      end
    end
  end
  if #draws > 0 then
    local ok, err = pcall(function()
      GEO.atlas:update(function()
        for _, d in ipairs(draws) do
          local cx, cy = (d.li - 1) % 4, math.floor((d.li - 1) / 4)
          local sx, sy = d.s % 4, math.floor(d.s / 4)
          local x0, y0 = cx * 1024 + sx * 256, cy * 1024 + sy * 256
          ui.drawImage(d.t.path, vec2(x0, y0), vec2(x0 + 256, y0 + 256))
        end
      end)
    end)
    if not ok then broken("atlas update: " .. tostring(err)); return end
    for _, d in ipairs(draws) do
      d.t.state = "ok"; GEO.loaded = GEO.loaded + 1; mark(d.li, d.s, true)
      pcall(ui.unloadImage, d.t.path)
    end
  end
  if #GEO.marks > 0 then
    local marks = GEO.marks
    GEO.marks = {}
    pcall(function()
      GEO.res:update(function()
        for _, m in ipairs(marks) do
          ui.drawRectFilled(vec2(m.s, m.li - 1), vec2(m.s + 1, m.li), m.on and rgbm(1, 1, 1, 1) or rgbm(0, 0, 0, 1))
        end
      end)
    end)
  end
end

-- ------------------------------------------------------------------------------------------------ shaders
local WORLD_SHADER = [[
  float4 main(PS_IN pin) {
    float2 ndc = float2(pin.Tex.x * 2 - 1, 1 - pin.Tex.y * 2);
    float3 d = normalize(gFwd + ndc.x * gTan * gAspect * gSide + ndc.y * gTan * gUp);
    float b = dot(gCam, d);
    float disc = b * b - gC;
    if (disc <= 0 || b >= 0) return float4(0, 0, 0, 0);
    float t = gC / (-b + sqrt(disc));
    float3 hr = d * t;
    float3 n = normalize(gCam + hr);
    float2 uv = float2(atan2(n.y, n.x) / 6.2831853 + 0.5, 0.5 - asin(clamp(n.z, -1, 1)) / 3.1415927);
    float3 col = txEarth.SampleLevel(samAnisotropic, uv, 0).rgb;
    if (gGeo > 0.5) {
      float3 ps = gU * gAlt + hr;
      float rr = gR + dot(ps, gU);
      float dlat = atan2(dot(ps, gN), rr);
      float dlon = atan2(dot(ps, gE), rr) / max(cos(gSubLat + dlat), 0.01);
      float latD = degrees(dlat), lonD = degrees(dlon);
      float inc = max(-dot(d, n), 0.08);
      float zd = log2(78271.52 * inc / max(t * gPixAng, 0.01));
      float4 Ls[12] = { gL0, gL1, gL2, gL3, gL4, gL5, gL6, gL7, gL8, gL9, gL10, gL11 };
      [loop] for (int i = 0; i < 12; i++) {
        float fi = (float)i;
        if (fi > gZFine) break;
        float4 L = Ls[i];
        float z = fi + 5;
        float wz = saturate(zd - z + 1);
        if (L.z < 0.5 || wz <= 0) continue;
        float sp = 180.0 / exp2(z);
        float tu = L.x + lonD / sp, tv = L.y - latD / sp;
        float edge = min(min(tu, 4 - tu), min(tv, 4 - tv));
        if (edge <= 0) continue;
        float2 slot = fmod(floor(float2(tu, tv)) + float2(fmod(L.w, 4), floor(L.w / 4)), 4);
        if (txRes.Load(int3((int)(slot.x + slot.y * 4), i, 0)).r < 0.5) continue;
        float2 f = clamp(frac(float2(tu, tv)) * 256, 0.5, 255.5);
        float2 cell = float2(fmod(fi, 4), floor(fi / 4));
        float2 a = (cell * 1024 + slot * 256 + f) / float2(4096, 3072);
        col = lerp(col, txAtlas.SampleLevel(samAnisotropic, a, 0).rgb, wz * saturate(edge / 0.35));
      }
    }
    float day = smoothstep(-0.08, 0.25, dot(n, gSun));
    float airTop = saturate(1 - gAlt / 70000.0);
    float3 lit = col * (0.03 + 0.97 * day);
    lit = lerp(lit, float3(0.6, 0.72, 0.9) * (0.1 + 0.9 * day), 0.35 * saturate(t / 400000.0) * airTop);
    return float4(lit, 1);
  }
]]

local EASU_SHADER = [[
  float4 T(float2 p) { return txIn.Load(int3(clamp(p, float2(0, 0), gInSize - 1), 0)); }
  float Lu(float4 c) { return c.b * 0.5 + (c.r * 0.5 + c.g); }
  void tap(inout float4 aC, inout float aW, float2 off, float2 dir, float2 len, float lob, float clp, float4 c) {
    float2 v = float2(off.x * dir.x + off.y * dir.y, off.x * (-dir.y) + off.y * dir.x) * len;
    float d2 = min(dot(v, v), clp);
    float wB = 0.4 * d2 - 1.0, wA = lob * d2 - 1.0;
    wB *= wB; wA *= wA; wB = 1.5625 * wB - 0.5625;
    float w = wB * wA; aC += c * w; aW += w;
  }
  void setDir(inout float2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE) {
    float lx = max(abs(lD - lC), abs(lC - lB)); lx = lx > 0 ? 1.0 / lx : 0.0;
    float dx = lD - lB; dir.x += dx * w; lx = saturate(abs(dx) * lx); lx *= lx; len += lx * w;
    float ly = max(abs(lE - lC), abs(lC - lA)); ly = ly > 0 ? 1.0 / ly : 0.0;
    float dy = lE - lA; dir.y += dy * w; ly = saturate(abs(dy) * ly); ly *= ly; len += ly * w;
  }
  float4 main(PS_IN pin) {
    float2 pp = pin.Tex * gOutSize * (gInSize / gOutSize) - 0.5;
    float2 fp = floor(pp); pp -= fp;
    float4 b = T(fp + float2(0, -1)), c = T(fp + float2(1, -1));
    float4 e = T(fp + float2(-1, 0)), f = T(fp), g = T(fp + float2(1, 0)), h = T(fp + float2(2, 0));
    float4 i = T(fp + float2(-1, 1)), j = T(fp + float2(0, 1)), k = T(fp + float2(1, 1)), l = T(fp + float2(2, 1));
    float4 n = T(fp + float2(0, 2)), o = T(fp + float2(1, 2));
    float bL = Lu(b), cL = Lu(c), eL = Lu(e), fL = Lu(f), gL = Lu(g), hL = Lu(h), iL = Lu(i), jL = Lu(j), kL = Lu(k), lL = Lu(l), nL = Lu(n), oL = Lu(o);
    float2 dir = 0; float len = 0;
    setDir(dir, len, (1 - pp.x) * (1 - pp.y), bL, eL, fL, gL, jL);
    setDir(dir, len, pp.x * (1 - pp.y), cL, fL, gL, hL, kL);
    setDir(dir, len, (1 - pp.x) * pp.y, fL, iL, jL, kL, nL);
    setDir(dir, len, pp.x * pp.y, gL, jL, kL, lL, oL);
    float dirR = dot(dir, dir);
    bool zro = dirR < 1.0 / 32768.0;
    dirR = zro ? 1.0 : rsqrt(dirR);
    dir.x = zro ? 1.0 : dir.x;
    dir *= dirR;
    len = len * 0.5; len *= len;
    float stretch = dot(dir, dir) / max(abs(dir.x), abs(dir.y));
    float2 len2 = float2(1 + (stretch - 1) * len, 1 - 0.5 * len);
    float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    float clp = 1.0 / lob;
    float4 mn = min(min(f, g), min(j, k)), mx = max(max(f, g), max(j, k));
    float4 aC = 0; float aW = 0;
    tap(aC, aW, float2(0, -1) - pp, dir, len2, lob, clp, b); tap(aC, aW, float2(1, -1) - pp, dir, len2, lob, clp, c);
    tap(aC, aW, float2(-1, 1) - pp, dir, len2, lob, clp, i); tap(aC, aW, float2(0, 1) - pp, dir, len2, lob, clp, j);
    tap(aC, aW, float2(0, 0) - pp, dir, len2, lob, clp, f); tap(aC, aW, float2(-1, 0) - pp, dir, len2, lob, clp, e);
    tap(aC, aW, float2(1, 1) - pp, dir, len2, lob, clp, k); tap(aC, aW, float2(2, 1) - pp, dir, len2, lob, clp, l);
    tap(aC, aW, float2(2, 0) - pp, dir, len2, lob, clp, h); tap(aC, aW, float2(1, 0) - pp, dir, len2, lob, clp, g);
    tap(aC, aW, float2(1, 2) - pp, dir, len2, lob, clp, o); tap(aC, aW, float2(0, 2) - pp, dir, len2, lob, clp, n);
    return min(mx, max(mn, aC / aW));
  }
]]

-- the final pass: RCAS on the reconstructed world, over the sky and stars drawn at the display's own resolution
local FINAL_SHADER = [[
  float4 T(float2 p) { return txOut.Load(int3(clamp(p, float2(0, 0), gSize - 1), 0)); }
  float4 main(PS_IN pin) {
    float2 p = floor(pin.Tex * gSize);
    float4 e = T(p), b = T(p + float2(0, -1)), d = T(p + float2(-1, 0)), f = T(p + float2(1, 0)), h = T(p + float2(0, 1));
    float3 mn4 = min(min(b.rgb, d.rgb), min(f.rgb, h.rgb)), mx4 = max(max(b.rgb, d.rgb), max(f.rgb, h.rgb));
    float3 hitMin = mn4 / (4 * mx4 + 1e-5), hitMax = (1 - mx4) / (4 * mn4 - 4 - 1e-5);
    float3 lobeRGB = max(-hitMin, hitMax);
    float lobe = max(-0.1875, min(max(lobeRGB.r, max(lobeRGB.g, lobeRGB.b)), 0)) * exp2(-gSharp);
    float4 w = saturate((lobe * (b + d + f + h) + e) / (4 * lobe + 1));
    float2 ndc = float2(pin.Tex.x * 2 - 1, 1 - pin.Tex.y * 2);
    float3 dv = normalize(gFwd + ndc.x * gTan * gAspect * gSide + ndc.y * gTan * gUp);
    float airTop = saturate(1 - gAlt / 70000.0);
    float dayHere = saturate(dot(normalize(gCam), gSun) * 3 + 0.4);
    float2 sph = float2(atan2(dv.y, dv.x), asin(clamp(dv.z, -1, 1)));
    float2 cell = floor(sph * 400);
    float hs = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
    float star = step(0.9975, hs) * (0.5 + 0.5 * hs) * (1 - airTop * dayHere);
    float3 sky = float3(0.35, 0.55, 0.9) * airTop * dayHere + star;
    float3 col = w.rgb + sky * (1 - w.a);
    return float4(col, gK);
  }
]]

-- ------------------------------------------------------------------------------------------------ targets + pacing
local function targets(sim)
  local k = RS.steps[RS.i]
  local ow, oh = math.max(64, sim.windowWidth), math.max(64, sim.windowHeight)
  local iw, ih = math.max(64, math.floor(ow * k + 0.5)), math.max(64, math.floor(oh * k + 0.5))
  local key = iw .. "x" .. ih .. "/" .. ow .. "x" .. oh
  if RS.size == key then return true end
  local ok, err = pcall(function()
    if RS.world then RS.world:dispose() end
    if RS.out then RS.out:dispose() end
    RS.world = ui.ExtraCanvas(vec2(iw, ih))
    RS.out = ui.ExtraCanvas(vec2(ow, oh))
  end)
  if not ok then broken("render targets: " .. tostring(err)); return false end
  RS.size, RS.iw, RS.ih, RS.ow, RS.oh = key, iw, ih, ow, oh
  return true
end

-- step down after 1 s over 20 ms a frame, back up after 5 s under 17.5 ms (2 s between changes)
local function pace(now)
  if RS.lastT then local dt = (now - RS.lastT) * 1000; if dt > 0 and dt < 250 then RS.frameMs = RS.frameMs * 0.95 + dt * 0.05 end end
  RS.lastT = now
  if now - RS.changedAt < 2 then return end
  if RS.frameMs > 20 then
    RS.fastSince = nil; RS.slowSince = RS.slowSince or now
    if now - RS.slowSince > 1 and RS.i < #RS.steps then RS.i, RS.changedAt, RS.slowSince = RS.i + 1, now, nil end
  elseif RS.frameMs < 17.5 then
    RS.slowSince = nil; RS.fastSince = RS.fastSince or now
    if now - RS.fastSince > 5 and RS.i > 1 then RS.i, RS.changedAt, RS.fastSince = RS.i - 1, now, nil end
  else RS.slowSince, RS.fastSince = nil, nil end
end

-- ------------------------------------------------------------------------------------------------ one frame
--- v = { sim, cam (ECEF), alt, fwd, up, side, tanHalf, fovY, k, depth, sun, earth (texture path), p, vel, dest }.
--- Returns true when it drew; false = the caller draws the planet its old way.
function W.draw(v)
  if RS.broken or not render or not ui.ExtraCanvas then return false end
  local now = clock()
  pace(now)
  RS.fovY = v.fovY
  if not targets(v.sim) then return false end
  -- geography
  local la, lo = D.ecefToLla(v.cam)
  local geo = false
  if ensureGeo() then
    plan(now, la, lo, v.alt, v.p or v.cam, v.vel, v.dest, RS.ih)
    pump()
    geo = GEO.zFine >= ZMIN
  end
  local U = D.vec.unit(v.cam)
  local E = D.vec.unit(D.vec.cross({ 0, 0, 1 }, U))
  local N = D.vec.cross(U, E)
  local vals = {
    gCam = vec3(v.cam[1], v.cam[2], v.cam[3]), gC = v.alt * (2 * D.R + v.alt), gAlt = v.alt, gR = D.R,
    gFwd = vec3(v.fwd[1], v.fwd[2], v.fwd[3]), gUp = vec3(v.up[1], v.up[2], v.up[3]), gSide = vec3(v.side[1], v.side[2], v.side[3]),
    gTan = v.tanHalf, gAspect = RS.ow / RS.oh, gSun = vec3(v.sun[1], v.sun[2], v.sun[3]),
    gE = vec3(E[1], E[2], E[3]), gN = vec3(N[1], N[2], N[3]), gU = vec3(U[1], U[2], U[3]),
    gSubLat = math.rad(la), gPixAng = 2 * v.tanHalf / RS.ih, gGeo = geo and 1 or 0, gZFine = geo and (GEO.zFine - ZMIN) or -1,
  }
  for li = 1, LEVELS do
    local L = GEO.lev[li]
    local x = vec4(0, 0, 0, 0)
    if geo and L.active and L.ox then
      local s0, cols = span(L.z), 2 ^ (L.z + 1)
      local u0 = (lo + 180) / s0 - L.ox
      if u0 > cols / 2 then u0 = u0 - cols elseif u0 < -cols / 2 then u0 = u0 + cols end
      x = vec4(u0, (90 - la) / s0 - L.oy, 1, (L.ox % 4) + (L.oy % 4) * 4)
    end
    vals["gL" .. (li - 1)] = x
  end
  local ok, err = pcall(function()
    RS.world:updateWithShader({
      textures = { txEarth = v.earth, txAtlas = GEO.atlas or v.earth, txRes = GEO.res or v.earth },
      values = vals, shader = WORLD_SHADER, cacheKey = 332001,
    })
    RS.out:updateWithShader({
      textures = { txIn = RS.world }, values = { gInSize = vec2(RS.iw, RS.ih), gOutSize = vec2(RS.ow, RS.oh) },
      shader = EASU_SHADER, cacheKey = 332002,
    })
    render.fullscreenPass({
      async = true, blendMode = render.BlendMode.AlphaBlend, depth = v.depth, textures = { txOut = RS.out },
      values = { gSize = vec2(RS.ow, RS.oh), gSharp = RS.sharp, gK = v.k, gCam = vals.gCam, gAlt = v.alt, gSun = vals.gSun,
        gFwd = vals.gFwd, gUp = vals.gUp, gSide = vals.gSide, gTan = v.tanHalf, gAspect = vals.gAspect },
      shader = FINAL_SHADER, cacheKey = 332003,
    })
  end)
  if not ok then broken("world passes: " .. tostring(err)); return false end
  if not RS.probed then
    RS.probed = true
    post({ type = "probe", what = "render", ok = true, internal = { RS.iw, RS.ih }, display = { RS.ow, RS.oh }, geo = GEO.ok,
      tileDir = GEO.dir ~= nil })
  end
  return true
end

-- ------------------------------------------------------------------------------------------------ the readout
function W.renderText()
  if RS.broken then return "RENDER     direct planet pass (" .. RS.broken .. ")" end
  if not RS.iw then return "RENDER     -" end
  return ("RENDER     WORLD %d%% %dx%d -> %dx%d  EASU+RCAS  |  %.1f ms"):format(math.floor(RS.steps[RS.i] * 100 + 0.5),
    RS.iw, RS.ih, RS.ow, RS.oh, RS.frameMs)
end

function W.geoText()
  if not GEO.dir then return "GEOGRAPHY  global image only (no tile bridge)" end
  if not GEO.ok or GEO.zFine < ZMIN then return "GEOGRAPHY  global image only" end
  local have, want, fine = 0, 0, nil
  for li = 1, LEVELS do
    local L = GEO.lev[li]
    if L.active and L.layer then
      want = want + 16
      for _, t in pairs(L.slots) do if t.state == "ok" then have = have + 1 end end
      if not fine or L.z > fine.z then fine = L end
    end
  end
  if not fine then return "GEOGRAPHY  global image only" end
  local m = span(fine.z) * 111319.49 / 256
  return ("GEOGRAPHY  z%d %s m/texel %s  |  tiles %d/%d"):format(fine.z, m < 10 and ("%.1f"):format(m) or ("%.0f"):format(m), fine.layer, have, want)
end

function W.credit()
  if GEO.loaded > 0 and GEO.credit then return GEO.credit end
  return "Imagery: NASA Blue Marble (global)"
end

return W
