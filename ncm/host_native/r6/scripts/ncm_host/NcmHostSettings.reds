// NCM Host -- NCM's settings live in Mod Settings (L340; owner: "just put it in mod settings").
//
// **No `module`** (KB-182). No new button, no popup (KB-389): Settings -> Mod Settings -> Night City Motorsports is the one
// place NCM is set up, in the main menu and the pause menu alike, with Mod Settings' own Apply. Mod Settings stores the
// values; NcmHostRuntime reads them when a save loads and is told when they change (OnModSettingsChange).
//
// Tape in play: 0 = Cyberpunk without NCM; 1 = TAPE 01, 2 = TAPE 02 ...; a number past your last tape starts a new tape
// (which becomes the next TAPE). The Race Week line on the HUD shows the tape in play.

public class NcmHostSettings extends IScriptable {
  public let runtime: wref<NcmHostRuntime>;

  @runtimeProperty("ModSettings.mod", "Night City Motorsports")
  @runtimeProperty("ModSettings.category", "Race Week tapes")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Tape in play")
  @runtimeProperty("ModSettings.description", "0 = play without NCM. 1 = TAPE 01, 2 = TAPE 02, and so on. Each tape is its own Race Week, running in real time. Choose the number after your last tape to start a new one. Takes effect on Apply, or when your save loads.")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "16")
  public let tape: Int32 = 0;

  public func Listen() -> Void {
    ModSettings.RegisterListenerToClass(this);
    ModSettings.RegisterListenerToModifications(this);
  }

  public func Unlisten() -> Void {
    ModSettings.UnregisterListenerToModifications(this);
    ModSettings.UnregisterListenerToClass(this);
  }

  public cb func OnModSettingsChange() -> Void {
    if IsDefined(this.runtime) {
      this.runtime.OnSettingsChanged();
    }
  }
}
