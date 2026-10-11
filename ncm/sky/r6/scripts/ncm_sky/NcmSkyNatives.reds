// NCM Sky -- the natives `ncm_sky.dll` registers (KB-430).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a plugin
// registered, by fully qualified name; inside a module these would not match and RED4ext closes the game before it
// starts (KB-182). `tools/build-sky.ps1` refuses that shape.

public static native func NcmSky_Scene() -> String
public static native func NcmSky_Report(id: String, state: Int32, entity: Uint64, why: String) -> Bool
public static native func NcmSky_Log(text: String) -> Bool
// The game's own entity spawner (exEntitySpawner), called from the DLL inside this script call (vanilla redscript
// cannot reach it). Spawned at identity: the system turns the body with TeleportationFacility.
public static native func NcmSky_Spawn(template: String, appearance: String, x: Float, y: Float, z: Float) -> EntityID
public static native func NcmSky_Despawn(entity: ref<Entity>) -> Bool
