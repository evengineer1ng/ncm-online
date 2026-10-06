// NCM Gearbox -- the dash shows the manual's gear and revs (owner, 2026-10-04: "i didnt see our dash showing gear and
// revs"). Writing the Vehicle blackboard alone lost to the game's own write every frame, and the widgets redraw only on
// a change. So every vanilla gear / rpm callback the 0.1.0 census named is wrapped: whatever value arrives, the widget
// draws `NcmGearbox_DisplayGear` / `NcmGearbox_DisplayRpm` -- the virtual gear and rpm while a manual is being driven,
// the game's own value otherwise. No module: these are plain wrappers over vanilla classes.

@wrapMethod(hudCarController)
protected cb func OnGearValueChanged(gearValue: Int32) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayGear(gearValue));
}

@wrapMethod(hudCarController)
protected cb func OnRpmValueChanged(rpmValue: Float) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayRpm(rpmValue));
}

@wrapMethod(vehicleInteriorUIGameController)
protected cb func OnGearValueChanged(gearValue: Int32) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayGear(gearValue));
}

@wrapMethod(vehicleInteriorUIGameController)
protected cb func OnRpmValueChanged(rpmValue: Float) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayRpm(rpmValue));
}

@wrapMethod(vehicleVcarGameController)
protected cb func OnRpmValueChanged(rpmValue: Float) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayRpm(rpmValue));
}

@wrapMethod(inkMotorcycleHUDGameController)
protected cb func OnGearValueChanged(gearValue: Int32) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayGear(gearValue));
}

@wrapMethod(inkMotorcycleHUDGameController)
protected cb func OnRpmValueChanged(rpmValue: Float) -> Bool {
  return wrappedMethod(NcmGearbox_DisplayRpm(rpmValue));
}

@wrapMethod(gearboxLogicController)
public func OnGearBoxChanged(gear: Int32) -> Void {
  wrappedMethod(NcmGearbox_DisplayGear(gear));
}

@wrapMethod(tachometerLogicController)
public func OnRpmValueChanged(rpmValue: Float) -> Void {
  wrappedMethod(NcmGearbox_DisplayRpm(rpmValue));
}

@wrapMethod(analogTachLogicController)
public func OnRpmValueChanged(rpmValue: Float) -> Void {
  wrappedMethod(NcmGearbox_DisplayRpm(rpmValue));
}
