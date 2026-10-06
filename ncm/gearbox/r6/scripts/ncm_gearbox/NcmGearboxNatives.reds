// NCM Gearbox -- the natives `ncm_gearbox.dll` registers (L306 phase 3: the manual).
//
// **This file must never declare a `module`.** RED4ext validates every `native func` against the functions a plugin
// registered, by fully qualified name; inside a module these would not match and RED4ext closes the game before it
// starts (KB-182).

public static native func NcmGearbox_Observe(vehicle: ref<VehicleObject>, hudGear: Int32, hudRpm: Float, speed: Float) -> Bool
public static native func NcmGearbox_Drive(record: Uint64, hudGear: Int32, speed: Float) -> Int32
public static native func NcmGearbox_Rpm() -> Float
public static native func NcmGearbox_RpmFraction() -> Float
public static native func NcmGearbox_EngineAudioValue() -> Float
public static native func NcmGearbox_DisplayGear(value: Int32) -> Int32
public static native func NcmGearbox_DisplayRpm(value: Float) -> Float
public static native func NcmGearbox_AudioMode() -> String
public static native func NcmGearbox_AudioDetail() -> String
public static native func NcmGearbox_DashSpeed(value: Float) -> Bool
public static native func NcmGearbox_AudioName() -> String
public static native func NcmGearbox_EngineAudio() -> Bool
public static native func NcmGearbox_ShiftEvent() -> Int32
public static native func NcmGearbox_Left() -> Bool
public static native func NcmGearbox_Status() -> String
public static native func NcmGearbox_Log(text: String) -> Bool
