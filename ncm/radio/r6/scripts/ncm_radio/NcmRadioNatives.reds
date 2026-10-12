// NCM Radio -- the natives `ncm_radio.dll` registers (doc 59 §6).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a plugin
// registered, by fully qualified name; inside a module the names do not match and RED4ext closes the game before it
// starts (KB-182). `tools/build-radio.ps1` checks for it.

public static native func NcmRadio_Tick(listening: Bool, volume: Float) -> String
public static native func NcmRadio_Pref() -> String
public static native func NcmRadio_SetPref(value: String) -> Bool
public static native func NcmRadio_Log(text: String) -> Bool
