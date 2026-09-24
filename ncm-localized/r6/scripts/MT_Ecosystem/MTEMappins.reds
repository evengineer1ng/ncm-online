// MT_Ecosystem: MTEMappins.reds
// Drives hover tooltip text and per-pin tint color for our race map pins.
// debugCaption format: "MT_Ecosystem|Title|Description|R|G|B|A"

// ── shared helpers ──────────────────────────────────────────────────────────

@addMethod(BaseMappinBaseController)
protected final func MTE_IsOurPin() -> Bool {
  let sd: ref<GameplayRoleMappinData> = this.GetMappin().GetScriptData() as GameplayRoleMappinData;
  if !IsDefined(sd) || !sd.m_isMappinCustom { return false; }
  let parts: array<String> = StrSplit(sd.m_customMappinDescription, "|");
  return ArraySize(parts) >= 1 && Equals(parts[0], "MT_Ecosystem");
}

@addMethod(BaseMappinBaseController)
protected final func MTE_ApplyPinColor() -> Void {
  if !this.MTE_IsOurPin() { return; }
  let sd: ref<GameplayRoleMappinData> = this.GetMappin().GetScriptData() as GameplayRoleMappinData;
  let parts: array<String> = StrSplit(sd.m_customMappinDescription, "|");
  if ArraySize(parts) < 5 { return; }
  let tint: HDRColor = new HDRColor(
    StringToFloat(parts[1]),
    StringToFloat(parts[2]),
    StringToFloat(parts[3]),
    StringToFloat(parts[4])
  );
  inkWidgetRef.SetTintColor(this.iconWidget, tint);
}

// ── minimap POI pin ─────────────────────────────────────────────────────────

@wrapMethod(MinimapPOIMappinController)
protected final func UpdateIcon() -> Void {
  wrappedMethod();
  this.MTE_ApplyPinColor();
}

// ── minimap device pin ──────────────────────────────────────────────────────

@wrapMethod(MinimapDeviceMappinController)
protected func Update() -> Void {
  wrappedMethod();
  this.MTE_ApplyPinColor();
}

// ── world-space floating pin (QuestMappinController) ────────────────────────

@wrapMethod(QuestMappinController)
protected func UpdateIcon() -> Void {
  wrappedMethod();
  this.MTE_ApplyPinColor();
}

// ── tracked gameplay pin (compass / in-world) ───────────────────────────────

@wrapMethod(GameplayMappinController)
private func UpdateIcon() -> Void {
  wrappedMethod();
  this.MTE_ApplyPinColor();
}

// ── full world-map screen pin ────────────────────────────────────────────────

@wrapMethod(BaseWorldMapMappinController)
protected func UpdateIcon() -> Void {
  wrappedMethod();
  this.MTE_ApplyPinColor();
}

// ── world-map hover tooltip ──────────────────────────────────────────────────

@wrapMethod(WorldMapTooltipController)
public func SetData(const data: script_ref<WorldMapTooltipData>, menu: ref<WorldMapMenuGameController>) -> Void {
  wrappedMethod(data, menu);
  let sd: ref<GameplayRoleMappinData> = Deref(data).mappin.GetScriptData() as GameplayRoleMappinData;
  if IsDefined(sd) && sd.m_isMappinCustom {
    let parts: array<String> = StrSplit(sd.m_customMappinDescription, "|");
    if ArraySize(parts) >= 1 && Equals(parts[0], "MT_Ecosystem") {
      inkTextRef.SetText(this.m_titleText, sd.m_customMappinTitle);
    }
  }
}
