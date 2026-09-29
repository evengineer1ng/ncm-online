// NCM Scanner -- the natives `ncm_vision.dll` registers (`L197`).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a
// plugin registered, by fully qualified name. Inside `module NcmVision` these would be `NcmVision.NcmScanner_*`;
// the DLL registers them as globals, the names do not match, and RED4ext closes the game before it starts
// (`KB-182`, 2026-09-28). `scc` compiles either form happily, so `tools/build-vision.ps1` checks for it.

public static native func NcmScanner_Reticle() -> String
public static native func NcmScanner_Panel() -> String
public static native func NcmScanner_Report(active: Bool, entity: Uint64, record: Uint64, kind: Int32, distance: Float, x: Float, y: Float, z: Float) -> Bool
public static native func NcmScanner_Log(text: String) -> Bool
