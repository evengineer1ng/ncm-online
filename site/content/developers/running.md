---
title: Running NCM
description: How to run an NCM development server locally on Windows with OPEN//77 and MariaDB, and join it.
status: dev
---

# Running NCM

NCM's own development server runs on Windows. These are the steps the project uses. They are scripts written for
one developer's machine, so expect to read them and adapt.

## What you need

- **Windows** with PowerShell 5.1 or newer.
- **The OPEN//77 dedicated server** for Windows, unpacked into `tools/open77/server/` (git-ignored). Running an
  OPEN//77 server requires accepting OPEN//77's terms; a public listing needs a server licence from them. See
  [open2077.net/docs](https://open2077.net/docs/server-resources).
- **MariaDB 10.11** (NCM pins its development database to 10.11, the version production runs).
- **Lua 5.4 and LuaJIT** on `PATH` (or in `%LOCALAPPDATA%\Programs\Lua\bin` and `...\LuaJIT\bin`) for the tests.
- **Cyberpunk 2077** plus the OPEN//77 client to join it.
- For native plugins: Visual Studio 2022 C++ build tools and CMake.

## Steps

```powershell
# 1. Clone, with the RED4ext SDK submodule
git clone --recurse-submodules https://github.com/evengineer1ng/ncm-online.git
cd ncm-online

# 2. Database: installs MariaDB, creates the NCM database and user, stores credentials DPAPI-encrypted
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\db-setup.ps1

# 3. Vendor ncm-core into the resources (idempotent; -Check to verify)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-build.ps1

# 4. First server start: OPEN//77's Warden onboarding on http://127.0.0.1:11780 (local only)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-server.ps1 -SetupOnly

# 5. Start the server. NCM's resources are linked in through a junction (resources\ncm -> ncm\online\resources)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-server.ps1
```

The server's licence key and database connection string are read from the DPAPI secret store and passed as
environment variables (`OP77_LICENSE_KEY`, `OP77_DATABASE_CONNECTION`), so `server.jsonc` never holds credentials.
**Never commit `server.jsonc`**; `.gitignore` excludes it.

On first boot `ncm_league` applies every migration. The other resources wait until the schema version they need
is present.

## Joining your server

Join from the OPEN//77 launcher, or use `tools/o77-client.ps1` for a direct local launch. **Back up your saves first**
(`tools/o77-backup-saves.ps1`). NCM's native plugins must be installed and declared as required mods for an
OPEN//77 client to load them. `tools/dev-hand-install-mods.py` and `tools/staging/publish-carrier.py` are the
project's scripts for that.

## Production

The public server runs the same resources on Linux. `docs/ncm-online/OPS_STAGING.md` and
`tools/deploy-staging.ps1` describe how the project deploys. They are specific to NCM's own server.
