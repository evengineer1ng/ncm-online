// NCM Broadcast -- the natives `ncm_broadcast.dll` registers (L235).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a
// plugin registered, by fully qualified name; inside a module the names would not match and RED4ext closes the game
// before it starts (`KB-182`). `tools/build-broadcast.ps1` checks for it.

public static native func NcmBroadcast_LabelCount() -> Int32
public static native func NcmBroadcast_LabelEntity(index: Int32) -> EntityID
public static native func NcmBroadcast_LabelText(index: Int32) -> String
public static native func NcmBroadcast_Tower() -> String
public static native func NcmBroadcast_TowerRow(index: Int32) -> String
public static native func NcmBroadcast_View() -> String
public static native func NcmBroadcast_Log(text: String) -> Bool
