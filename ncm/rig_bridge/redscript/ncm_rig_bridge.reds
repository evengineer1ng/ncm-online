// NCM Rig Bridge -- native vehicle ownership boundary.
// The detour fires for every visible vehicle, so these wrappers identify exactly the local player's mount.

public static native func NcmRig_SetPlayerVehicle(vehicle: ref<VehicleObject>) -> Bool;
public static native func NcmRig_ClearPlayerVehicle() -> Bool;
public static native func NcmRig_GetStatus() -> String;

@wrapMethod(VehicleComponent)
protected cb func OnVehicleFinishedMountingEvent(evt: ref<VehicleFinishedMountingEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let character: ref<GameObject> = evt.character as GameObject;
  if IsDefined(character) && character.IsPlayer() && evt.isMounting {
    NcmRig_SetPlayerVehicle(this.GetVehicle());
  }
  return result;
}

@wrapMethod(VehicleComponent)
protected cb func OnUnmountingEvent(evt: ref<UnmountingEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);
  let game: GameInstance = this.GetVehicle().GetGame();
  let childId: EntityID = evt.request.lowLevelMountingInfo.childId;
  let child: ref<GameObject> = GameInstance.FindEntityByID(game, childId) as GameObject;
  if IsDefined(child) && child.IsPlayer() {
    NcmRig_ClearPlayerVehicle();
  }
  return result;
}


// ---------------------------------------------------------------------------------------------------
// Collision jolts.
//
// `OnVehicleBumpEvent` is CDPR's only VehicleObject-owned collision event. It fires on scrapes, nudges,
// traffic bumps and full-speed crashes, and carries `impactVelocityChange` (the delta-v for this contact)
// and `hitNormal` (world-space contact normal).
//
// **CDPR dispatches it to the vehicle that got STRUCK, not the one doing the striking.** So when the
// player rams an NPC, `this` is the NPC's vehicle and `evt.hitVehicle` is the player's. Forwarding only
// on `this` would silently drop every collision the player caused, which is most of them.
//
// The kick is computed in the PLAYER's frame regardless of which vehicle received the event, because
// `hitNormal` is world-space and the wheel responds to left/right relative to the driver. A negative dot
// with the player's right vector means the impact landed on the driver's left, so the rim jerks right --
// the chassis rotates about the contact and the front tyres scrub away from it.
// ---------------------------------------------------------------------------------------------------
public static native func NcmRig_OnVehicleBump(vehicle: ref<VehicleObject>, kick: Float) -> Bool;

@wrapMethod(VehicleObject)
protected cb func OnVehicleBumpEvent(evt: ref<VehicleBumpEvent>) -> Bool {
  let result: Bool = wrappedMethod(evt);

  let intensity: Float = ClampF(AbsF(evt.impactVelocityChange) / 20.0, 0.0, 1.0);
  if intensity <= 0.0 {
    return result;
  }

  let player: ref<PlayerPuppet> = GetPlayer(this.GetGame());
  if !IsDefined(player) {
    return result;
  }
  let playerVeh: ref<VehicleObject> = player.GetMountedVehicle() as VehicleObject;
  if !IsDefined(playerVeh) {
    return result;
  }

  // Which side is the player on? If the player IS the struck vehicle the normal faces away, so flip it.
  let normalSign: Float = 0.0;
  let other: ref<VehicleObject> = evt.hitVehicle as VehicleObject;
  if Equals(this, playerVeh) {
    normalSign = -1.0;
  } else {
    if IsDefined(other) && Equals(other, playerVeh) {
      normalSign = 1.0;
    } else {
      return result;                   // NPC <-> NPC traffic, nothing to do with this driver
    }
  }

  let pr: Vector4 = playerVeh.GetWorldRight();
  let lateral: Float = pr.X * evt.hitNormal.X
                     + pr.Y * evt.hitNormal.Y
                     + pr.Z * evt.hitNormal.Z;
  let kick: Float = ClampF(-normalSign * lateral * intensity, -1.0, 1.0);
  NcmRig_OnVehicleBump(playerVeh, kick);

  return result;
}
