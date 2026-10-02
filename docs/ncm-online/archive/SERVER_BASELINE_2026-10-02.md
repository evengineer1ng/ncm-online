# Server inventory — 2026-10-02

> **STATUS: HISTORICAL** — read-only snapshot before the next OPEN//77 platform update. Current environment policy: [16_ENVIRONMENTS.md](../16_ENVIRONMENTS.md). Operations: [OPS_STAGING.md](../OPS_STAGING.md).

Checked against the running Development manifest at `127.0.0.1:11779`, the running Online manifest through SSH at `127.0.0.1:11782`, each server's package manifest, and the declared hosted blobs. No server configuration, package, resource, database, or process was changed.

| | NCM Development (Windows) | NCM Online (Lightsail Linux) |
|---|---|---|
| OPEN//77 server package | `2.31.21+op77.120 win-x64` | `2.31.21+op77.120 linux-x64` |
| Process | `Open77.Server.exe` running | `ncm-server` systemd unit active; NCM resource log activity observed |
| Required mods | enabled; 8 hosted packages | enabled; 3 hosted packages |
| Manifest digest | `8dc855d1265fe5674b2dd756375347256d82ccd56397c2af85d057949f1750b9` | `879af3286c16ed2ecd971024a8febbbe81ead75744576f4d4280f73a9fb82c99` |
| NCM resource directories | `ncm_broadcast`, `ncm_league`, `ncm_paddock`, `ncm_probe`, `ncm_scanner`, `ncm_weather_probe`, `ncm_world` | `ncm_league`, `ncm_probe`, `ncm_scanner`, `ncm_weather_probe`, `ncm_world` |

## Declared client packages

| Package ID | Development | Online | SHA-256 of declared package |
|---|---|---|---|
| `ncm-carrier` | 0.1.30 | 0.1.30 | `d4431422ef567c6312151605137c33f92365aa354248b89fcd1255048ca96dc9` |
| `ncm-rig-bridge` | 0.1.7 | 0.1.7 | `eea1aba61388a2fd92a57415197243f45e27c5f45b2ba2c6cb1549558ce84e80` |
| `ncm-vision` (NCM Scanner) | 0.3.0 | 0.3.0 | `e44ecafa7de0da94b217fcaeb2aa73ffdac7249690f8774a75076d755b4d50c9` |
| `ncm-clock` | 0.1.0 | — | `389a87dfbc329c725217b428592c0579d0f1473d2ce3c8b76b45e40241fb19ab` |
| `ncm-broadcast` | 0.1.0 | — | `9fdd2a0ec1cfe5f7f9ca2e03af2155febaecc4ff5656104fc6fe5a814a5caf5b` |
| `archivexl` | 1.27.1 | — | `608b7b2fed4c35751cd264a87dcfe9d9074fb6d48458d29bde955f1c03dc0d5c` |
| `ncm-pace` | 0.8.5 | — | `3a75b08252bf08f19e1ea8f8f344ce686a20c7bfeadf80eeada418e9187511b9` |
| `tweakxl` | 1.11.4 | — | `13033a1f10cb1dbfa534964b22e3405aa33e8f29145f17164d318b021402883f` |

All eight Development blobs and all three Online blobs exist in their respective server stores and hash to the declared SHA-256. These are packages required for client join, not a census of every package previously imported into the store or every mod installed in a player's game. Extra old blobs in a content-addressed store do not become required unless declared in the running manifest.

The launcher reports that the servers are outdated after its update. This inventory confirms both servers still advertise platform `op77.120`; it does not establish the launcher's required minimum or prove the precise rejection rule. Before a platform-only update, identify the target server build, check the candidate load list, preserve the Online Baseline 1 code/mod/data freeze, and follow the environment-specific upgrade and rollback procedures. Do not promote Development's five additional required packages to Online as part of a platform update.
