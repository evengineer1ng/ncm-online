# Third-party notices

NCM's own work is MIT licensed (see `LICENSE`). These components in this repository are other people's work and
keep their own licences.

| Component | Where | Licence | Notes |
|---|---|---|---|
| RED4ext.SDK (WopsS and contributors) | `ncm/carrier/third_party/RED4ext.SDK` (git submodule) | MIT | Fetched from https://github.com/WopsS/RED4ext.SDK; its licence is in the submodule. |
| SDL3 (Sam Lantinga and contributors) | `ncm/rig_bridge/third_party/SDL3/` | zlib | `ncm/rig_bridge/third_party/SDL3/LICENSE.txt`. |
| miniaudio (David Reid) | `ncm/radio/third_party/miniaudio.h` | Public domain (Unlicense) or MIT-0, at your choice | Licence text at the end of the header. |
| stb_vorbis (Sean Barrett) | `ncm/radio/third_party/stb_vorbis.c` | Public domain or MIT, at your choice | Licence text at the end of the file. |
| In-World Navigation (jackhumbert) | `wolvenkit-projects/ncm_iwn_braking/` (`packed.reds.orig`, and the particle/effect clones) | MIT | NCM's braking-zone add-on patches this mod. Upstream: Nexus Mods 4583 / https://github.com/jackhumbert/in_world_navigation. Its copyright notice and licence apply to those files. |
| Wheel input lineage | `ncm/rig_bridge/` | MIT | Rig Bridge is new code, validated against `clevergrant/cp2077-wheel-mod`, `natpoh/cp2077-wheel-mod-moza` and `jackhumbert/custom_game_controller`. See `ncm/rig_bridge/THIRD_PARTY_NOTICES.md`. |

## Not included

- **Cyberpunk 2077** game files, assets and data belong to CD PROJEKT S.A. NCM references game records, places and
  assets by name. Where authoring sources serialise game structures (WolvenKit CR2W JSON), they are NCM's own
  modifications.
- **OPEN//77**: the platform, server binaries and launcher are not part of this repository. NCM targets OPEN//77's
  public APIs; research notes in `docs/research/open77/` quote its documentation for reference.
- **Third-party loaders** NCM depends on at runtime (ArchiveXL, TweakXL, Codeware, RED4ext, redscript) are installed
  by the OPEN//77 launcher from their own releases, not from this repository.
- **The "Manual Transmission" mod (keanuWheeze)** and **files derived from the third-party RB15 car mod**: earlier
  versions of this workspace held patched copies. They were removed from the tree and its history before publication.
  NCM Gearbox is NCM's own manual transmission.
- **Race Week Live voices** are rendered with OmniVoice, whose model weights are licensed CC-BY-NC. The rendered voice
  packs ship as separate downloads, not in this repository.
- **NASA imagery** used by NCM Deep (public domain) is fetched by `tools/fetch-deep-assets.py`, not stored here.
