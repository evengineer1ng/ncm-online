#!/usr/bin/env python
"""
Apply the NCM braking-zone racing-line patch to In-World Navigation's packed.reds (jackhumbert, MIT).

    python apply_braking_patch.py <path-to-packed.reds>          # patches in place, keeps <file>.orig

Idempotent: refuses to patch a file that already contains the marker. Re-run after a mod update.

What the patch does to class InWorldNavigation:
  * adds Mod Settings knobs: Render distance (m), Braking lookahead (m), Braking sensitivity (deg)
  * Setup(): loads the four red arrow effects from archive/pc/mod/ncm_iwn_braking.archive
  * UpdateNavPath(): draws only `renderDistance` metres of route ahead of the player (never the whole line),
    and tints each arrow by the turning found within `lookahead` metres ahead of it (orange -> deep red)
  * UpdateFxInstance(): respawns an arrow when its colour tier changes
"""
import sys, os, shutil

MARKER = '// NCM_BRAKING_LINE_PATCH v1'

FIELDS = '''  let distanceToFade: Float = 25.0;
  ''' + MARKER + '''
  @runtimeProperty("ModSettings.mod", "In-World Navigation")
  @runtimeProperty("ModSettings.displayName", "Render distance (m)")
  @runtimeProperty("ModSettings.description", "NCM: only this much route ahead of the player is drawn, whatever Max number of arrows says.")
  @runtimeProperty("ModSettings.step", "10.0")
  @runtimeProperty("ModSettings.min", "30.0")
  @runtimeProperty("ModSettings.max", "400.0")
  @runtimeProperty("ModSettings.dependency", "enabled")
  let ncmRenderDistance: Float = 150.0;
  @runtimeProperty("ModSettings.mod", "In-World Navigation")
  @runtimeProperty("ModSettings.displayName", "Braking zone lookahead (m)")
  @runtimeProperty("ModSettings.description", "NCM: how far ahead of each arrow the route is scanned for turning.")
  @runtimeProperty("ModSettings.step", "5.0")
  @runtimeProperty("ModSettings.min", "10.0")
  @runtimeProperty("ModSettings.max", "120.0")
  @runtimeProperty("ModSettings.dependency", "enabled")
  let ncmLookahead: Float = 40.0;
  @runtimeProperty("ModSettings.mod", "In-World Navigation")
  @runtimeProperty("ModSettings.displayName", "Braking zone sensitivity (deg)")
  @runtimeProperty("ModSettings.description", "NCM: total turning inside the lookahead that gives the deepest red. Lower = redder.")
  @runtimeProperty("ModSettings.step", "5.0")
  @runtimeProperty("ModSettings.min", "20.0")
  @runtimeProperty("ModSettings.max", "180.0")
  @runtimeProperty("ModSettings.dependency", "enabled")
  let ncmFullRedDeg: Float = 75.0;
  @runtimeProperty("ModSettings.mod", "In-World Navigation")
  @runtimeProperty("ModSettings.displayName", "Braking zones (red arrows)")
  @runtimeProperty("ModSettings.dependency", "enabled")
  let ncmBrakingEnabled: Bool = true;
  let ncmRedResources: array<FxResource>;
  let ncmFxTier: array<array<Int32>>;
'''

SETUP_TAIL = '''    ArrayPush(this.navPathTransforms, poisTransforms);
    // NCM braking line: red arrow tiers (archive/pc/mod/ncm_iwn_braking.archive)
    ArrayClear(this.ncmRedResources);
    ArrayPush(this.ncmRedResources, Cast<FxResource>(r"user\\\\ncm\\\\effects\\\\world_navigation_red_1.effect"));
    ArrayPush(this.ncmRedResources, Cast<FxResource>(r"user\\\\ncm\\\\effects\\\\world_navigation_red_2.effect"));
    ArrayPush(this.ncmRedResources, Cast<FxResource>(r"user\\\\ncm\\\\effects\\\\world_navigation_red_3.effect"));
    ArrayPush(this.ncmRedResources, Cast<FxResource>(r"user\\\\ncm\\\\effects\\\\world_navigation_red_4.effect"));
    ArrayClear(this.ncmFxTier);
    let questTiers: array<Int32>;
    let poiTiers: array<Int32>;
    ArrayPush(this.ncmFxTier, questTiers);
    ArrayPush(this.ncmFxTier, poiTiers);
'''

NEW_METHODS = '''  // NCM: turn severity -> colour tier (0 = the mod's own colour, 1..4 = orange -> deep red)
  private func NcmTierForIntensity(intensity: Float) -> Int32 {
    if intensity < 0.15 { return 0; }
    if intensity < 0.35 { return 1; }
    if intensity < 0.60 { return 2; }
    if intensity < 0.85 { return 3; }
    return 4;
  }

  private func UpdateNavPath(type: Int32, points: array<Vector4>, resource: FxResource, force: Bool) -> Void {
    let pointDrawnCount: Int32 = 0;
    let dots: array<Transform>;
    let i = ArraySize(points) - 1;
    if i < 0 { return; }
    let lastDrawnPoint: Vector4 = points[i];
    // resample the route every `spacing` metres, destination -> player (unchanged)
    while i > 0 {
      let tweenPointDistance = Vector4.Distance(points[i-1], lastDrawnPoint);
      if i == 1 {
        tweenPointDistance += this.spacing;
      }
      if tweenPointDistance >= this.spacing {
        let lastDrawnPointInLastGroup = lastDrawnPoint;
        let distance = this.spacing;
        while distance <= tweenPointDistance {
          let ratio: Float = distance / tweenPointDistance;
          let position = Vector4.Interpolate(lastDrawnPointInLastGroup, points[i-1], ratio);
          let orientation = Quaternion.BuildFromDirectionVector(lastDrawnPoint - position);
          distance += this.spacing;
          ArrayPush(dots, Transform.Create(position, orientation));
          lastDrawnPoint = position;
        }
      }
      i -= 1;
    }
    i = 0;
    while i < ArraySize(dots) {
      if ArraySize(this.navPathTransforms[type]) <= i {
        ArrayPush(this.navPathTransforms[type], dots[i]);
      } else {
        if Vector4.Distance(this.navPathTransforms[type][i].position, dots[i].position) < this.distanceToAnimate {
          this.navPathTransforms[type][i].position = Vector4.Interpolate(this.navPathTransforms[type][i].position, dots[i].position, 0.1);
          this.navPathTransforms[type][i].orientation = Quaternion.Slerp(this.navPathTransforms[type][i].orientation, dots[i].orientation, 0.1);
        } else {
          this.navPathTransforms[type][i].position = dots[i].position;
          this.navPathTransforms[type][i].orientation = dots[i].orientation;
        }
      }
      i += 1;
    }
    ArrayResize(this.navPathTransforms[type], ArraySize(dots));

    // NCM: heading change at each dot (deg). dots[n-1] is nearest the player, dots[0] the destination.
    let n = ArraySize(dots);
    let turn: array<Float>;
    ArrayResize(turn, n);
    let j = 0;
    while j < n {
      turn[j] = 0.0;
      if this.ncmBrakingEnabled && j > 0 && j < n - 1 {
        let incoming = dots[j].position - dots[j + 1].position;
        let outgoing = dots[j - 1].position - dots[j].position;
        incoming.Z = 0.0;
        outgoing.Z = 0.0;
        if Vector4.Length(incoming) > 0.01 && Vector4.Length(outgoing) > 0.01 {
          turn[j] = AbsF(Vector4.GetAngleBetween(incoming, outgoing));
        }
      }
      j += 1;
    }
    let lookDots = Cast<Int32>(this.ncmLookahead / MaxF(this.spacing, 0.5));
    if lookDots < 1 { lookDots = 1; }

    // NCM: draw from the player outwards, but only ncmRenderDistance metres of route
    let maxDots = Cast<Int32>(this.ncmRenderDistance / MaxF(this.spacing, 0.5));
    if maxDots < 1 { maxDots = 1; }
    if maxDots > this.maxPoints { maxDots = this.maxPoints; }
    i = n - 1;
    while pointDrawnCount < maxDots && i >= 0 {
      let tier = 0;
      if this.ncmBrakingEnabled {
        let acc: Float = 0.0;
        let k = i;
        let kEnd = i - lookDots;
        if kEnd < 0 { kEnd = 0; }
        while k >= kEnd {
          acc += turn[k];
          k -= 1;
        }
        tier = this.NcmTierForIntensity(MinF(acc / MaxF(this.ncmFullRedDeg, 1.0), 1.0));
      }
      let res = resource;
      if tier > 0 && ArraySize(this.ncmRedResources) >= tier {
        res = this.ncmRedResources[tier - 1];
      }
      let p = this.navPathTransforms[type][i].position;
      let q = this.navPathTransforms[type][i].orientation;
      this.UpdateFxInstance(type, pointDrawnCount, p, q, res, tier, force);
      pointDrawnCount += 1;
      i -= 1;
    }
    // retire every arrow beyond the render window
    while pointDrawnCount < ArraySize(this.navPathFXs[type]) {
      if IsDefined(this.navPathFXs[type][pointDrawnCount]) {
        this.navPathFXs[type][pointDrawnCount].SetBlackboardValue(n"alpha", 0.0);
        this.navPathFXs[type][pointDrawnCount].BreakLoop();
        this.navPathFXs[type][pointDrawnCount].Kill();
      }
      pointDrawnCount += 1;
    }
  }

  private func UpdateFxInstance(type: Int32, i: Int32, p: Vector4, q: Quaternion, resource: FxResource, tier: Int32, force: Bool) {
    let wt: WorldTransform;
    WorldTransform.SetPosition(wt, p);
    WorldTransform.SetOrientation(wt, q);
    while ArraySize(this.ncmFxTier[type]) <= i {
      ArrayPush(this.ncmFxTier[type], -1);
    }
    let tierChanged = this.ncmFxTier[type][i] != tier;
    if i >= ArraySize(this.navPathFXs[type]) {
      ArrayPush(this.navPathFXs[type], GameInstance.GetFxSystem(this.player.GetGame()).SpawnEffect(resource, wt));
      this.ncmFxTier[type][i] = tier;
    } else {
      if IsDefined(this.navPathFXs[type][i]) && this.navPathFXs[type][i].IsValid() && !force && !tierChanged {
        this.navPathFXs[type][i].UpdateTransform(wt);
      } else {
        if IsDefined(this.navPathFXs[type][i]) {
          this.navPathFXs[type][i].BreakLoop();
          this.navPathFXs[type][i].Kill();
        }
        this.navPathFXs[type][i] = GameInstance.GetFxSystem(this.player.GetGame()).SpawnEffect(resource, wt);
        this.ncmFxTier[type][i] = tier;
      }
    }
    this.navPathFXs[type][i].SetBlackboardValue(n"alpha", MinF(Vector4.Distance2D(this.player.GetWorldPosition(), p) / this.distanceToFade, 1.0));
  }
}
'''


def patch(path):
    s = open(path, encoding='utf-8').read()
    if MARKER in s:
        print('already patched:', path); return False
    a = s.index('  let distanceToFade: Float = 25.0;\n')
    assert s.count('  let distanceToFade: Float = 25.0;\n') == 1
    s = s.replace('  let distanceToFade: Float = 25.0;\n', FIELDS, 1)
    assert s.count('    ArrayPush(this.navPathTransforms, poisTransforms);\n') == 1
    s = s.replace('    ArrayPush(this.navPathTransforms, poisTransforms);\n', SETUP_TAIL, 1)
    # replace from the original UpdateNavPath through the end of the class (the closing brace after UpdateFxInstance)
    start = s.index('  private func UpdateNavPath(')
    end_marker = '\npublic static native func Cast(a: ResRef) -> FxResource;'
    end = s.index(end_marker)
    # the class closes with "}\n" right before end_marker
    s = s[:start] + NEW_METHODS + s[end:]
    shutil.copy2(path, path + '.orig')
    open(path, 'w', encoding='utf-8', newline='\n').write(s)
    print('patched:', path, '(original kept as .orig)')
    return True


if __name__ == '__main__':
    patch(sys.argv[1])
