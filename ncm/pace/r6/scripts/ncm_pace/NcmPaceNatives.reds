// NCM Pace -- the natives `ncm_pace.dll` registers (Paddock phase 5, doc 44 §15).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a
// plugin registered, by fully qualified name. Inside a module these would be `NcmPace.NcmPace_*`; the DLL registers
// them as globals, the names do not match, and RED4ext closes the game before it starts (`KB-182`). `scc` compiles
// either form happily, so `tools/build-pace.ps1` checks for it.

public static native func NcmPace_Count() -> Int32
public static native func NcmPace_Revision() -> Int32
public static native func NcmPace_Entity(index: Int32) -> EntityID
public static native func NcmPace_Step(index: Int32, x: Float, y: Float, z: Float) -> String
public static native func NcmPace_Banner() -> String
public static native func NcmPace_Log(text: String) -> Bool
