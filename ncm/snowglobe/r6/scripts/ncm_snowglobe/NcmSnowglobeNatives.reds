// NCM Snowglobe -- the natives `ncm_snowglobe.dll` registers (L317 SEAM-1).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a plugin
// registered, by fully qualified name; inside a module these would not match and RED4ext closes the game before it
// starts (KB-182).

public static native func NcmSnowglobe_Poll() -> Int32
public static native func NcmSnowglobe_Offset(axis: Int32) -> Float
public static native func NcmSnowglobe_MinZ() -> Float
public static native func NcmSnowglobe_WatchFrames() -> Int32
public static native func NcmSnowglobe_Kick(vx: Float, vy: Float, vz: Float) -> Int32
public static native func NcmSnowglobe_Log(text: String) -> Bool
