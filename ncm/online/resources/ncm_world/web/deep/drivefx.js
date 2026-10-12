// NCM Deep -- doc 58: the experimental drives, SEEN. One 2D layer of the Deep page (web/deep.html), drawn over the
// native REDengine view (the car in first person) and over NCM's own WebGL views alike. Lua sends the drives' states
// (`deep:drivefx`, ~30 Hz: client/drivefx.lua); this file only draws.
//
// Every effect is built from OUR OWN STAR FIELD: the Hipparcos stars in skystars.js (positions in parsecs, absolute
// magnitudes), placed from the Machine's real position among them -- so far from the Sun the sky is the sky from THERE.
// Each technology is recognisable without its label:
//   impulse     a hard kick: a white-orange flare at the edge, a jolt of the frame; the stars do nothing
//   fusion      a sustained warm exhaust glow that breathes with the throttle; the stars do nothing
//   warp        STAR STREAKS: points elongate along lines from the vanishing point, then the field flows past
//   alcubierre  the sky BENDS: stars crowd into a bright ring ahead, thin and redden behind, smear into arcs at the wall
//               of a shimmering bubble around a calm car; a violent flash when the bubble collapses
//   jump        a navigation lock, the stars drawn into the target point as the charge builds, a flash, black, and the
//               destination's sky -- discontinuity, no streaks
//   wormhole    a hole in the sky: a disc that shows another sky (the far mouth's), a lensing ring around it; crossing
//               it is a tunnel of rings; behind you, the mouth you came out of
// What the native view cannot do yet, said so: this layer is not depth-tested (it also draws over the cabin, kept to a
// soft forward mask), and the game's own star dome is not re-projected (doc 58 §8: pending the ncm-sky DLL templates).
(function () {
  "use strict";
  var PC = 3.0856775814913673e16;
  var STARS = window.NCM_SKYSTARS || [];
  var N = Math.floor(STARS.length / 5);
  // the Sun as a star (seen from anywhere): position 0, absolute magnitude 4.83, B-V 0.65
  var SX = new Float64Array(N + 1), SY = new Float64Array(N + 1), SZ = new Float64Array(N + 1), SM = new Float32Array(N + 1), SB = new Float32Array(N + 1);
  for (var i = 0; i < N; i++) { SX[i] = STARS[5 * i]; SY[i] = STARS[5 * i + 1]; SZ[i] = STARS[5 * i + 2]; SM[i] = STARS[5 * i + 3]; SB[i] = STARS[5 * i + 4]; }
  SX[N] = 0; SY[N] = 0; SZ[N] = 0; SM[N] = 4.83; SB[N] = 0.65;
  var NS = N + 1;
  // apparent directions (ICRF unit) + magnitude from a position (pc); recomputed when the Machine moves
  var DX = new Float32Array(NS), DY = new Float32Array(NS), DZ = new Float32Array(NS), AM = new Float32Array(NS);
  var lastC = null;
  function sky(C, force) {
    if (!force && lastC && Math.abs(C[0] - lastC[0]) + Math.abs(C[1] - lastC[1]) + Math.abs(C[2] - lastC[2]) < 2e-4) return;
    lastC = [C[0], C[1], C[2]];
    for (var i = 0; i < NS; i++) {
      var x = SX[i] - C[0], y = SY[i] - C[1], z = SZ[i] - C[2];
      var d = Math.sqrt(x * x + y * y + z * z);
      if (d < 1e-9) { DX[i] = 0; DY[i] = 0; DZ[i] = 1; AM[i] = 99; continue; }
      DX[i] = x / d; DY[i] = y / d; DZ[i] = z / d;
      AM[i] = SM[i] + 5 * (Math.log(d) / Math.LN10 - 1);
      if (i === N && d < 0.05) AM[i] = Math.min(AM[i], -26.7 + 5 * Math.log(d * PC / 1.496e11) / Math.LN10);   // the Sun up close
    }
  }
  // a second sky for the far side of a wormhole
  var FX = new Float32Array(NS), FY = new Float32Array(NS), FZ = new Float32Array(NS), FM = new Float32Array(NS), lastF = null;
  function farSky(C) {
    if (lastF && Math.abs(C[0] - lastF[0]) + Math.abs(C[1] - lastF[1]) + Math.abs(C[2] - lastF[2]) < 1e-4) return;
    lastF = [C[0], C[1], C[2]];
    for (var i = 0; i < NS; i++) {
      var x = SX[i] - C[0], y = SY[i] - C[1], z = SZ[i] - C[2];
      var d = Math.sqrt(x * x + y * y + z * z) || 1e-9;
      FX[i] = x / d; FY[i] = y / d; FZ[i] = z / d; FM[i] = SM[i] + 5 * (Math.log(d) / Math.LN10 - 1);
    }
  }
  function colour(bv, a) {
    // B-V to a star colour (blue-white .. orange-red)
    var t = Math.max(-0.3, Math.min(1.8, bv || 0.6));
    var r = t < 0.4 ? 170 + (t + 0.3) * 120 : 255, g = t < 0.4 ? 200 + (t + 0.3) * 70 : 255 - (t - 0.4) * 70, b = t < 0.4 ? 255 : 255 - (t - 0.4) * 140;
    return "rgba(" + (r | 0) + "," + (g | 0) + "," + (b | 0) + "," + a.toFixed(3) + ")";
  }
  function shifted(bv, k, a) {   // k > 0 blue-shift, < 0 red-shift (presentation, not spectroscopy)
    var t = Math.max(-0.4, Math.min(2.2, (bv || 0.6) - k));
    return colour(t, a);
  }
  function bright(m) { return Math.max(0, Math.min(1, Math.pow(10, -0.4 * (m - 1.5)))); }
  // a star brighter than any in Earth's night sky (a star you are near: the Sun from Proxima, Vega from 2 AU) is a glow,
  // its size growing with its brightness
  function glow(ctx, x, y, m, bv, px, cap) {
    if (m > -1.5) return false;
    var r = Math.min(cap || 140 * px, (4 + 3.2 * (-1.5 - m)) * px);
    var g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, "rgba(255,255,255,1)"); g.addColorStop(0.12, colour(bv, 0.95)); g.addColorStop(0.4, colour(bv, 0.28)); g.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, 6.283); ctx.fill();
    return true;
  }

  var M = null, Mat = 0;
  var flash = { a: 0, col: "255,255,255", decay: 2 }, jolt = { x: 0, y: 0, t: 0 };
  var memo = { lastState: {}, warpFlow: 0 };

  function vlen(a) { return Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); }
  function vunit(a) { var l = vlen(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }
  function vdot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
  function vcross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function rot(axis, ang, v) {   // Rodrigues
    var c = Math.cos(ang), s = Math.sin(ang), k = axis, kv = vdot(k, v), kx = vcross(k, v);
    return [v[0] * c + kx[0] * s + k[0] * kv * (1 - c), v[1] * c + kx[1] * s + k[1] * kv * (1 - c), v[2] * c + kx[2] * s + k[2] * kv * (1 - c)];
  }
  // bend direction d toward / away from axis a: new angle = f(old angle)
  function bend(d, a, f) {
    var c = Math.max(-1, Math.min(1, vdot(d, a))), th = Math.acos(c);
    var th2 = f(th);
    if (Math.abs(th2 - th) < 1e-6) return d;
    var ax = vcross(a, d), l = vlen(ax);
    if (l < 1e-9) return d;
    return rot([ax[0] / l, ax[1] / l, ax[2] / l], th2 - th, d);
  }

  // ------------------------------------------------------------------------------------------------ what is active
  function active(m) {
    var out = { warp: null, alc: null, jump: null, worm: null };
    for (var i = 0; m && m.drives && i < m.drives.length; i++) {
      var d = m.drives[i];
      if (d.drive === "warp" && (d.state === "SPOOLING" || d.state === "ENGAGED" || d.state === "DISENGAGING")) out.warp = d;
      if (d.drive === "alcubierre" && d.state !== "OFF" && d.state !== "COOLDOWN" && d.state !== "FAILED") out.alc = d;
      if (d.drive === "jump" && d.state !== "OFF" && d.state !== "FAILED") out.jump = d;
      if (d.drive === "wormhole" && (d.wormhole || d.state === "DESTINATION_LOCKED")) out.worm = d;
      // edge-triggered moments
      var prev = memo.lastState[d.drive];
      if (prev !== d.state) {
        memo.lastState[d.drive] = d.state;
        if (d.drive === "alcubierre" && prev === "ENGAGED" && d.state === "DISENGAGING") { flash = { a: 1.0, col: "255,250,235", decay: 1.1 }; jolt = { x: 0, y: 0, t: 0.9 }; }
        if (d.drive === "jump" && prev === "CHARGING" && d.state === "ENGAGED") { flash = { a: 1.0, col: "255,255,255", decay: 5 }; lastC = null; }
        if (d.drive === "warp" && d.state === "ENGAGED") { flash = { a: 0.25, col: "180,210,255", decay: 3 }; }
      }
      if (d.drive === "wormhole" && d.throat !== undefined && d.throat !== null && d.throat < 0.05 && !memo.crossFlash) { memo.crossFlash = true; flash = { a: 0.8, col: "200,170,255", decay: 1.4 }; lastC = null; }
      if (d.drive === "wormhole" && (d.throat === undefined || d.throat === null || d.throat >= 1)) memo.crossFlash = false;
    }
    return out;
  }

  // ------------------------------------------------------------------------------------------------ the layer
  function draw(ctx, W, H, cam, nowMs) {
    if (!M) return false;
    var dt = Math.min(0.1, Math.max(0, (nowMs - (memo.lastMs || nowMs)) / 1000)); memo.lastMs = nowMs;
    var A = active(M);
    var conv = M.conv || {};
    var any = A.warp || A.alc || A.jump || A.worm || flash.a > 0.01 || conv.method || M.far;
    ctx.clearRect(0, 0, W, H);
    if (!any) return false;
    var cx = W / 2, cy = H / 2, f = cam.focal, px = cam.px || 1;
    if (jolt.t > 0) { jolt.t = Math.max(0, jolt.t - dt); var amp = 18 * px * jolt.t * jolt.t; jolt.x = (Math.random() - 0.5) * amp; jolt.y = (Math.random() - 0.5) * amp; cx += jolt.x; cy += jolt.y; }
    function proj(d) {   // ICRF direction -> screen, or null behind
      var c = cam.toCam(d);
      if (c[2] <= 0.02) return null;
      return [cx + f * c[0] / c[2], cy - f * c[1] / c[2], c[2]];
    }
    if (M.carPc) sky(M.carPc, false);
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    // a soft forward mask: the cabin is darker and nearer than the sky; effects favour the windscreen
    var maskR = Math.max(W, H) * 0.75;

    // ---------------------------------------------------------------- conventional (no stars)
    if (conv.method === "fusion" && (conv.throttle || 0) > 0.01) {
      var th = conv.throttle, flick = 0.85 + 0.15 * Math.sin(nowMs / 37) * Math.sin(nowMs / 91);
      var g = ctx.createRadialGradient(cx, H * 1.25, 0, cx, H * 1.25, H * 1.25);
      g.addColorStop(0, "rgba(210,225,255," + (0.85 * th * flick).toFixed(3) + ")");
      g.addColorStop(0.25, "rgba(150,140,255," + (0.42 * th * flick).toFixed(3) + ")");
      g.addColorStop(0.6, "rgba(90,60,200," + (0.12 * th * flick).toFixed(3) + ")");
      g.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      // the torch's light on the cabin edges: two side glows that breathe with the throttle
      for (var sd2 = -1; sd2 <= 1; sd2 += 2) {
        var gs = ctx.createRadialGradient(cx + sd2 * W * 0.55, H, 0, cx + sd2 * W * 0.55, H, H * 0.7);
        gs.addColorStop(0, "rgba(170,160,255," + (0.25 * th * flick).toFixed(3) + ")"); gs.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = gs; ctx.fillRect(0, 0, W, H);
      }
      // heat shimmer lines along the bottom edge
      ctx.strokeStyle = "rgba(200,190,255," + (0.08 * th).toFixed(3) + ")"; ctx.lineWidth = 2 * px;
      for (var hs = 0; hs < 6; hs++) { var yy = H - (20 + hs * 14) * px; ctx.beginPath();
        for (var xx = 0; xx <= W; xx += 40 * px) ctx.lineTo(xx, yy + Math.sin(xx / (60 * px) + nowMs / 120 + hs) * 3 * px); ctx.stroke(); }
    }
    if (conv.method === "impulse" && conv.pulse) {
      if (!memo.pulseOn) { memo.pulseOn = true; memo.kick = 1; jolt = { x: 0, y: 0, t: 0.45 }; }
    } else memo.pulseOn = false;
    if ((memo.kick || 0) > 0.01) {
      var kk = memo.kick;
      var gk = ctx.createRadialGradient(cx, H * 1.05, 0, cx, H * 1.05, H * (0.5 + 0.6 * kk));
      gk.addColorStop(0, "rgba(255,235,200," + (0.95 * kk).toFixed(3) + ")"); gk.addColorStop(0.3, "rgba(255,150,70," + (0.55 * kk).toFixed(3) + ")");
      gk.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = gk; ctx.fillRect(0, 0, W, H);
      memo.kick = Math.max(0, kk - dt * 4);
    }

    // ---------------------------------------------------------------- WARP: streaks from our own stars
    if (A.warp && A.warp.dir) {
      var wd = vunit(A.warp.dir), k = Math.max(0, Math.min(1, A.warp.spool || 0));
      var vC = A.warp.vC || 0, lv = Math.log(1 + vC) / Math.LN10;       // 0 .. 5
      var vp = proj(wd);
      // aberration-like crowding toward the vanishing point grows with the field (presentation of "moving very fast")
      var beta = Math.min(0.97, 0.15 * k + 0.16 * lv * k);
      var crowd = Math.sqrt((1 - beta) / (1 + beta));
      memo.warpFlow = (memo.warpFlow + dt * (0.2 + lv * 0.9) * k) % 1;
      var streakK = k * k * (0.08 + 0.09 * lv);
      for (var si = 0; si < NS; si++) {
        var mg = AM[si];
        if (mg > 7.2) continue;
        var d0 = [DX[si], DY[si], DZ[si]];
        var d1 = bend(d0, wd, function (t) { return 2 * Math.atan(Math.tan(t / 2) * crowd); });
        var p1 = proj(d1);
        if (!p1) continue;
        var a = bright(mg) * (0.6 + 0.4 * k);
        if (!vp || k < 0.02) { ctx.fillStyle = colour(SB[si], Math.min(1, a + 0.1)); ctx.fillRect(p1[0], p1[1], 1.6 * px, 1.6 * px); continue; }
        var rx = p1[0] - vp[0], ry = p1[1] - vp[1], rr = Math.sqrt(rx * rx + ry * ry) || 1;
        // the streak: from the star outward along its line from the vanishing point; plus a flowing copy
        var L = rr * streakK;
        var phase = (memo.warpFlow + (si * 0.61803) % 1) % 1;
        var fr = rr * (0.35 + 1.4 * phase);
        var fx = vp[0] + rx / rr * fr, fy = vp[1] + ry / rr * fr, fL = fr * streakK * 1.6;
        var tint = 0.6 * k * Math.min(1, lv / 3);
        ctx.strokeStyle = shifted(SB[si], tint, Math.min(1, a * (0.8 + k)));
        ctx.lineWidth = Math.max(1, (1 + 1.6 * a) * px);
        ctx.beginPath(); ctx.moveTo(p1[0], p1[1]); ctx.lineTo(p1[0] + rx / rr * L, p1[1] + ry / rr * L); ctx.stroke();
        if (k > 0.5 && mg < 6.0) {
          ctx.strokeStyle = shifted(SB[si], tint, Math.min(0.9, a * 0.7 * (k - 0.5) * 2 * (1 - phase)));
          ctx.beginPath(); ctx.moveTo(fx, fy); ctx.lineTo(fx + rx / rr * fL, fy + ry / rr * fL); ctx.stroke();
        }
      }
      // the field's own glow at the vanishing point
      if (vp) { var gw = ctx.createRadialGradient(vp[0], vp[1], 0, vp[0], vp[1], 160 * px * k);
        gw.addColorStop(0, "rgba(170,200,255," + (0.35 * k).toFixed(3) + ")"); gw.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = gw; ctx.fillRect(0, 0, W, H); }
    }

    // ---------------------------------------------------------------- ALCUBIERRE: the sky bends around a calm bubble
    if (A.alc) {
      var ad = A.alc.dir ? vunit(A.alc.dir) : null;
      var kb = Math.max(0, Math.min(1, A.alc.bubble || 0));
      var engaged = A.alc.state === "ENGAGED", collapsing = A.alc.state === "DISENGAGING";
      var ride = engaged ? Math.max(0, Math.min(1, A.alc.vC ? Math.log(1 + A.alc.vC) / Math.log(1 + 1e6) : 0)) : 0;
      var strength = kb * (0.35 + 0.65 * ride);
      var tt = nowMs / 1000;
      if (ad && kb > 0.01) {
        for (var ai = 0; ai < NS; ai++) {
          var am = AM[ai];
          if (am > 6.8) continue;
          var e0 = [DX[ai], DY[ai], DZ[ai]];
          var c0 = Math.max(-1, Math.min(1, vdot(e0, ad))), th0 = Math.acos(c0);
          // contraction ahead (angles shrink toward the axis), expansion behind (angles grow away from it)
          var th1 = th0 < Math.PI / 2 ? th0 * (1 - 0.75 * strength * Math.cos(th0)) : th0 - 0.45 * strength * Math.sin(th0) * Math.cos(th0);
          // the wall: a shimmering lens band; stars near it are displaced and smeared into arcs along it
          var wall = 1.15 + 0.08 * Math.sin(tt * 1.7);
          var nearWall = Math.exp(-Math.pow((th0 - wall) / 0.22, 2));
          th1 += strength * 0.12 * nearWall * Math.sin(tt * 3.1 + ai);
          var e1 = bend(e0, ad, function () { return th1; });
          var q = proj(e1);
          if (!q) continue;
          var ab = bright(am) * (th0 < Math.PI / 2 ? 1 + 1.5 * strength * Math.cos(th0) : Math.max(0.15, 1 - 0.9 * strength));
          var sh = th0 < Math.PI / 2 ? 0.8 * strength * Math.cos(th0) : -1.0 * strength * (-Math.cos(th0));
          ctx.strokeStyle = shifted(SB[ai], sh, Math.min(1, ab));
          ctx.fillStyle = ctx.strokeStyle;
          if (nearWall > 0.2 && strength > 0.05) {
            // an arc along the wall: tangential smear (lensing caustic), not a radial streak
            var ap = proj(ad);
            if (ap) {
              var rx2 = q[0] - ap[0], ry2 = q[1] - ap[1], rr2 = Math.sqrt(rx2 * rx2 + ry2 * ry2) || 1;
              var ang = Math.atan2(ry2, rx2), span = 0.25 * nearWall * strength;
              ctx.lineWidth = Math.max(1, 1.4 * px); ctx.beginPath(); ctx.arc(ap[0], ap[1], rr2, ang - span, ang + span); ctx.stroke();
              continue;
            }
          }
          var sz = (1.2 + 2.2 * Math.min(1, ab)) * px;
          ctx.fillRect(q[0] - sz / 2, q[1] - sz / 2, sz, sz);
        }
        // the bubble wall itself: a translucent shimmering ring at the lens band, and a calm clear centre
        var ap2 = proj(ad);
        if (ap2) {
          var wallR = f * Math.tan(1.1);
          for (var ring = 0; ring < 3; ring++) {
            var rr3 = wallR * (0.92 + ring * 0.07) * (1 + 0.02 * Math.sin(tt * 2.3 + ring));
            ctx.strokeStyle = "rgba(160,190,255," + (0.07 * kb).toFixed(3) + ")"; ctx.lineWidth = (6 - ring * 2) * px;
            ctx.beginPath(); ctx.ellipse(ap2[0], ap2[1], rr3, rr3 * 0.92, Math.sin(tt * 0.4) * 0.2, 0, 6.283); ctx.stroke();
          }
          var gc = ctx.createRadialGradient(ap2[0], ap2[1], 0, ap2[0], ap2[1], 90 * px * (0.5 + strength));
          gc.addColorStop(0, "rgba(190,215,255," + (0.5 * strength).toFixed(3) + ")"); gc.addColorStop(1, "rgba(0,0,0,0)");
          ctx.fillStyle = gc; ctx.fillRect(0, 0, W, H);
        }
        // formation: the periphery ripples inward
        if (A.alc.state === "BUBBLE_FORMING") {
          for (var rp = 0; rp < 3; rp++) {
            var rk = (tt * 0.45 + rp / 3) % 1;
            ctx.strokeStyle = "rgba(150,175,255," + (0.35 * (1 - rk) * (0.3 + kb)).toFixed(3) + ")"; ctx.lineWidth = (2 + 5 * (1 - rk)) * px;
            ctx.beginPath(); ctx.ellipse(cx, cy, Math.max(W, H) * (1.1 - 0.75 * rk), Math.max(W, H) * (1.0 - 0.7 * rk), Math.sin(tt) * 0.1, 0, 6.283); ctx.stroke();
          }
        }
      }
      if (collapsing && A.alc.collapse !== undefined && A.alc.collapse !== null) {
        var ck = A.alc.collapse, apc = ad ? proj(ad) : [cx, cy];
        var shock = Math.max(W, H) * 1.3 * ck;
        ctx.strokeStyle = "rgba(255,240,220," + (0.5 * (1 - ck)).toFixed(3) + ")"; ctx.lineWidth = 14 * px * (1 - ck);
        ctx.beginPath(); ctx.arc(apc ? apc[0] : cx, apc ? apc[1] : cy, shock, 0, 6.283); ctx.stroke();
      }
      if (A.alc.state === "DESTINATION_LOCKED" && ad) reticle(ctx, proj(ad), px, nowMs, "ALCUBIERRE SOLUTION");
    }

    // ---------------------------------------------------------------- JUMP: lock, charge, collapse to a point, discontinuity
    if (A.jump) {
      var jd = A.jump.dir ? vunit(A.jump.dir) : null;
      var ch = A.jump.charge || 0, st = A.jump.state;
      if (jd && (st === "DESTINATION_LOCKED" || st === "CHARGING")) {
        var jp = proj(jd);
        var pull = st === "CHARGING" ? ch * ch : 0;
        if (pull > 0.01) {
          var swirl = pull * 1.2;
          for (var ji = 0; ji < NS; ji++) {
            var jm = AM[ji];
            if (jm > 6.6) continue;
            var j0 = [DX[ji], DY[ji], DZ[ji]];
            var j1 = bend(j0, jd, function (t) { return t * (1 - 0.92 * pull); });
            j1 = rot(jd, swirl * (1 - vdot(j0, jd)), j1);
            var jq = proj(j1);
            if (!jq) continue;
            var ja = bright(jm) * (1 + 2 * pull);
            ctx.fillStyle = shifted(SB[ji], 0.6 * pull, Math.min(1, ja));
            var js = (1.3 + 1.5 * Math.min(1, ja)) * px;
            ctx.fillRect(jq[0] - js / 2, jq[1] - js / 2, js, js);
          }
          // the build-up: darkness closing in, a burning point at the target
          var vg = ctx.createRadialGradient(jp ? jp[0] : cx, jp ? jp[1] : cy, 0, jp ? jp[0] : cx, jp ? jp[1] : cy, Math.max(W, H) * (1.2 - 0.9 * pull));
          vg.addColorStop(0, "rgba(255,255,255," + (0.6 * pull).toFixed(3) + ")"); vg.addColorStop(0.06, "rgba(200,220,255," + (0.25 * pull).toFixed(3) + ")");
          vg.addColorStop(1, "rgba(0,0,0,0)");
          ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);
          ctx.globalCompositeOperation = "source-over";
          var dark = ctx.createRadialGradient(cx, cy, Math.min(W, H) * (0.6 - 0.45 * pull), cx, cy, Math.max(W, H) * 0.8);
          dark.addColorStop(0, "rgba(0,0,0,0)"); dark.addColorStop(1, "rgba(0,0,0," + (0.85 * pull).toFixed(3) + ")");
          ctx.fillStyle = dark; ctx.fillRect(0, 0, W, H);
          ctx.globalCompositeOperation = "lighter";
        }
        reticle(ctx, jp, px, nowMs, st === "CHARGING" ? ("JUMP CHARGE " + Math.round(ch * 100) + "%") : "JUMP LOCK");
      }
      if (st === "ENGAGED") {
        // arrival: the destination sky snaps in; a fading afterimage ring where the old sky collapsed
        var ar = A.jump.arrive || 0;
        ctx.strokeStyle = "rgba(220,230,255," + (0.4 * (1 - ar)).toFixed(3) + ")"; ctx.lineWidth = 3 * px;
        ctx.beginPath(); ctx.arc(cx, cy, Math.min(W, H) * 0.08 * (1 + 6 * ar), 0, 6.283); ctx.stroke();
      }
    }

    // ---------------------------------------------------------------- WORMHOLE: a hole that shows another sky
    if (A.worm && A.worm.wormhole) {
      var w = A.worm.wormhole;
      var mouths = [{ side: "a", rel: w.a.rel, n: w.a.n, sky: "far" }, { side: "b", rel: w.b.rel, n: w.b.n, sky: "near" }];
      for (var mi = 0; mi < 2; mi++) {
        var mo = mouths[mi], dist = vlen(mo.rel);
        if (!(dist > 0) || !(w.radius > 0)) continue;
        if (dist > 5e6) continue;                            // a mouth far away is a point: not drawn
        var md = vunit(mo.rel), mp = proj(md);
        if (!mp) continue;
        var alpha = Math.atan2(w.radius, dist), rpx = f * Math.tan(alpha);
        if (rpx < 1) continue;
        var tt2 = nowMs / 1000;
        // lensing ring: local stars around the aperture pushed outward (Einstein ring), arcs at the rim
        var thE = alpha * 1.25;
        for (var li = 0; li < NS; li++) {
          var lm = AM[li];
          if (lm > 6.5) continue;
          var l0 = [DX[li], DY[li], DZ[li]];
          var cc = vdot(l0, md);
          if (cc < Math.cos(Math.min(1.2, alpha * 6))) continue;
          var th = Math.acos(Math.max(-1, Math.min(1, cc)));
          var thL = 0.5 * (th + Math.sqrt(th * th + 4 * thE * thE));
          var l1 = bend(l0, md, function () { return thL; });
          var lq = proj(l1);
          if (!lq) continue;
          var la = bright(lm) * (1 + 3 * Math.exp(-Math.pow((thL - alpha) / (alpha * 0.25), 2)));
          ctx.strokeStyle = colour(SB[li], Math.min(1, la));
          var ang2 = Math.atan2(lq[1] - mp[1], lq[0] - mp[0]), rr4 = Math.sqrt(Math.pow(lq[0] - mp[0], 2) + Math.pow(lq[1] - mp[1], 2));
          var span2 = 0.6 * thE / Math.max(th, thE * 0.5);
          ctx.lineWidth = Math.max(1, 1.3 * px); ctx.beginPath(); ctx.arc(mp[0], mp[1], rr4, ang2 - span2 * 0.5, ang2 + span2 * 0.5); ctx.stroke();
        }
        // the aperture: black, then the other side's sky inside it
        ctx.save();
        ctx.globalCompositeOperation = "source-over";
        ctx.beginPath(); ctx.arc(mp[0], mp[1], rpx, 0, 6.283); ctx.fillStyle = "rgba(0,0,4,0.97)"; ctx.fill();
        ctx.clip();
        ctx.globalCompositeOperation = "lighter";
        // through a mouth you see the sky at the OTHER mouth, turned by the mouth pair's mapping
        var R = mo.side === "a" ? w.map : w.mapBA;
        var otherPc = mo.side === "a" ? w.bPc : w.aPc;
        if (otherPc) farSky(otherPc);
        var useFar = !!otherPc;
        for (var fi = 0; fi < NS; fi++) {
          var fm = useFar ? FM[fi] : AM[fi];
          if (fm > 7.0) continue;
          var s0 = useFar ? [FX[fi], FY[fi], FZ[fi]] : [DX[fi], DY[fi], DZ[fi]];
          // a direction s on the other side is seen through this mouth at R^T s
          var dd = R ? [R[0] * s0[0] + R[3] * s0[1] + R[6] * s0[2], R[1] * s0[0] + R[4] * s0[1] + R[7] * s0[2], R[2] * s0[0] + R[5] * s0[1] + R[8] * s0[2]] : s0;
          var fq = proj(dd);
          if (!fq) continue;
          var dx3 = fq[0] - mp[0], dy3 = fq[1] - mp[1];
          if (dx3 * dx3 + dy3 * dy3 > rpx * rpx) continue;
          if (glow(ctx, fq[0], fq[1], fm, SB[fi], px, rpx * 0.9)) continue;
          var fa = bright(fm) * 1.4;
          ctx.fillStyle = colour(SB[fi], Math.min(1, fa));
          var fs = (1.2 + 1.8 * Math.min(1, fa)) * px; ctx.fillRect(fq[0] - fs / 2, fq[1] - fs / 2, fs, fs);
        }
        ctx.restore();
        // the rim: a photon-ring glow, pulsing while it stabilises
        var pulse = w.phase === "opening" ? 0.6 + 0.4 * Math.sin(tt2 * 9) : (w.phase === "collapsing" ? 0.5 + 0.5 * Math.sin(tt2 * 25) : 0.75);
        var rg = ctx.createRadialGradient(mp[0], mp[1], rpx * 0.92, mp[0], mp[1], rpx * 1.35);
        rg.addColorStop(0, "rgba(200,170,255," + (0.55 * pulse).toFixed(3) + ")"); rg.addColorStop(0.3, "rgba(120,140,255," + (0.25 * pulse).toFixed(3) + ")"); rg.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(mp[0], mp[1], rpx * 1.35, 0, 2 * Math.PI); ctx.moveTo(mp[0] + rpx * 0.985, mp[1]); ctx.arc(mp[0], mp[1], rpx * 0.985, 0, 2 * Math.PI); ctx.fill("evenodd");
        if (mo.side === "a" && w.phase === "opening") {
          var sk = (tt2 * 1.3) % 1;
          ctx.strokeStyle = "rgba(220,200,255," + (0.35 * (1 - sk)).toFixed(3) + ")"; ctx.lineWidth = 2 * px;
          ctx.beginPath(); ctx.arc(mp[0], mp[1], rpx * (1 + 2 * sk), 0, 6.283); ctx.stroke();
        }
        label(ctx, mp[0], mp[1] - rpx - 14 * px, px, (mo.side === "a" ? "WORMHOLE  " : "EXIT MOUTH  ") + (dist >= 1000 ? (dist / 1000).toFixed(2) + " km" : Math.round(dist) + " m"));
      }
      // the crossing: a tunnel of rings rushing past, the far sky opening from the centre
      if (A.worm.throat !== undefined && A.worm.throat !== null && A.worm.throat < 1) {
        var tk = A.worm.throat;
        for (var tr = 0; tr < 9; tr++) {
          var u = ((tr / 9) + nowMs / 260) % 1;
          var rad = Math.min(W, H) * 0.03 / Math.max(0.03, 1 - u);
          ctx.strokeStyle = "rgba(" + (170 + tr * 9) + ",150,255," + (0.5 * (1 - tk) * (1 - u)).toFixed(3) + ")"; ctx.lineWidth = (2 + 10 * u) * px;
          ctx.beginPath(); ctx.ellipse(cx + Math.sin(u * 7 + tr) * 12 * px, cy + Math.cos(u * 5) * 10 * px, rad, rad * 0.9, u * 2, 0, 6.283); ctx.stroke();
        }
      }
    }

    // ---------------------------------------------------------------- the far sky (no drive): what has changed out there
    if (!A.warp && !A.alc && !(A.jump && A.jump.state === "CHARGING") && M.far) {
      for (var pi = 0; pi < NS; pi++) {
        if (AM[pi] > 6.0) continue;
        if (!M.farAll && !(pi === N || SM[pi] < 3 && AM[pi] < 2.5)) continue;   // the Sun as a star, and the near bright ones
        var pq = proj([DX[pi], DY[pi], DZ[pi]]);
        if (!pq) continue;
        if (glow(ctx, pq[0], pq[1], AM[pi], SB[pi], px)) { if (pi === N) label(ctx, pq[0] + 8 * px, pq[1], px, "SOL"); continue; }
        var pa = bright(AM[pi]);
        ctx.fillStyle = colour(SB[pi], Math.min(1, pa)); var ps = (1.5 + 2 * Math.min(1, pa)) * px; ctx.fillRect(pq[0] - ps / 2, pq[1] - ps / 2, ps, ps);
        if (pi === N) label(ctx, pq[0] + 8 * px, pq[1], px, "SOL");
      }
    }

    // ---------------------------------------------------------------- flash
    if (flash.a > 0.003) {
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = "rgba(" + flash.col + "," + Math.min(1, flash.a).toFixed(3) + ")"; ctx.fillRect(0, 0, W, H);
      flash.a = Math.max(0, flash.a - dt * flash.decay);
    }
    ctx.restore();
    return true;
  }

  function reticle(ctx, p, px, nowMs, text) {
    if (!p) return;
    var r = 26 * px, spin = nowMs / 900;
    ctx.save(); ctx.globalCompositeOperation = "source-over";
    ctx.strokeStyle = "rgba(140,230,255,0.9)"; ctx.lineWidth = 1.5 * px;
    for (var q = 0; q < 4; q++) { var a0 = spin + q * Math.PI / 2; ctx.beginPath(); ctx.arc(p[0], p[1], r, a0, a0 + 0.9); ctx.stroke(); }
    ctx.beginPath(); ctx.moveTo(p[0] - r * 1.6, p[1]); ctx.lineTo(p[0] - r * 0.4, p[1]); ctx.moveTo(p[0] + r * 0.4, p[1]); ctx.lineTo(p[0] + r * 1.6, p[1]);
    ctx.moveTo(p[0], p[1] - r * 1.6); ctx.lineTo(p[0], p[1] - r * 0.4); ctx.moveTo(p[0], p[1] + r * 0.4); ctx.lineTo(p[0], p[1] + r * 1.6); ctx.stroke();
    ctx.restore();
    label(ctx, p[0] + r * 1.8, p[1] - r, px, text);
  }
  function label(ctx, x, y, px, text) {
    ctx.save(); ctx.globalCompositeOperation = "source-over";
    ctx.font = (12 * px) + "px Consolas, monospace"; ctx.fillStyle = "rgba(170,235,255,0.95)"; ctx.fillText(text, x, y); ctx.restore();
  }

  window.NcmDriveFx = {
    set: function (m) { M = m; Mat = performance.now(); },
    draw: draw,
    stars: NS,
    reset: function () { lastC = null; lastF = null; },
  };
})();
