# NCM Rig Bridge third-party notices

- RED4ext.SDK by WopsS and contributors — MIT License. Build dependency from `ncm/carrier/third_party`.
- nlohmann/json by Niels Lohmann and contributors — MIT License. Header-only build dependency.
- cp2077-wheel-mod by clevergrant — MIT License. Architectural reference for in-process input injection.
- cp2077-wheel-mod-moza by natpoh and contributors — MIT License. Architectural reference for generic
  DirectInput, split wheel/pedal devices and DirectInput force effects.
- custom_game_controller by Jack Humbert and contributors — MIT License. Architectural reference for
  arbitrary multi-device controller enumeration and hot-plug behavior.

- SDL 3.4.10 by Sam Lantinga and contributors — zlib License (`SDL3-LICENSE.txt`). Redistributed unmodified
  as `SDL3.dll` (the official win32-x64 runtime) and loaded at run time for Joy-Con and SDL-only device input.
- The gamepad layer (`src/pad/`) is a C++ port of JoyMoCo, the owner's own motion-to-XInput mapper; its
  profile format v1 is kept so profiles move between the two.

No vendor SDK is linked. Windows DirectInput is supplied by the operating system.

