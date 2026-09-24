# NCM Online — server profile notes (M0.1)

The dedicated server lives at `tools/open77/server/` (unpacked from `open77-server-2.31.13+op77.82-win-x64.zip`, 676 files hash-verified against `package-manifest.json`). It is started only through `tools/o77-server.ps1`, which:

- injects the platform license key from the DPAPI secret store as `OP77_LICENSE_KEY` (the schema's `masterServer.licenseKeyEnvironmentVariable` default) so `server.jsonc` stays credential-free;
- keeps first-run Warden onboarding on `http://127.0.0.1:11780` only;
- maintains the junction `tools/open77/server/resources/ncm` → `ncm/online/resources` so NCM resources are discovered in place (no copying).

`server.jsonc` is written by Warden onboarding, never by hand from chat, and is read by the assistant only through `tools/o77-config-show.ps1` (masked). Settings the dev profile needs after onboarding (to be applied via Warden or a masked patch tool in M0.2):

| Setting | Dev value | Why |
|---|---|---|
| `identity.visibility` | `private` | not listed publicly during development |
| `network.maximumPlayers` | 8 | two local clients + testers |
| `resources.load` | template resources + `"ncm/*"` | loads `ncm_world` through the junction |
| `requiredMods.enabled` | `false` (M0.1) → `true` (M0.3/E13) | mod pipeline experiments come later |
| `database.enabled` | `false` (M0.1) → `true` (M0.2) | MariaDB arrives with M0.2 |
| `masterServer.licenseKey` | absent | env var only |

Package facts recorded 2026-09-19: no `tools/mcp` directory ships in this package despite the README (the devkit MCP is a separate download); `open77_remote_camera` is present as a system resource in .82; template `freeroam` declares `requiresDatabase: true`.


## Observed 2026-09-19
- Onboarding done; `server.jsonc` credential-free (`licenseKey: null`, env `OP77_LICENSE_KEY`); `resources.load` includes `ncm/*`; visibility unlisted; DB disabled.
- The launcher quarantines the player's Solo-profile mods (223 files incl. NCM SP, CustomMapMarkers, RB15 tweaks) while the OPEN//77 profile is active; **Mods & profiles → Play your own game** restores them. Do not start Cyberpunk from Steam expecting SP NCM until then.
- Second client: `tools/o77-client.ps1` + dev console `resource.emit open77:shell:autoconnect 127.0.0.1:11778 alpha`.
