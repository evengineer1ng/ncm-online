# Mods your server requires › Mods your server requires

Declare, host and manage the mods required by your server. This guide covers Warden, trust levels and review. For installation flow and troubleshooting, see [Mods](mods.md).

A server declares the mods its world needs, hosts the bytes itself, and the launcher installs them
when the player presses Connect — before the game process exists. The master vouches for hashes,
never for files: no third-party mod transits Open77 infrastructure. Because the install happens
before boot, a normal join needs no restart. The game was not running yet.

Use this guide to decide whether your world needs a mod at all, import one from Warden, choose who
hosts the bytes, read the trust badge your players will see before they join, request a review, and
remove a mod later without stranding anyone.


## Mods your server requires › Quick start: add a mod in five steps

If you already have the archive and just want it required, this is the whole flow. Each step is
explained in full under [Add a mod from the Warden panel](#add-a-mod-from-the-warden-panel).

1. **Open Warden → Mods.** Under *Platform* in the sidebar. Needs the `mods.manage` permission.
2. **Drop the archive in.** Zip, 7z or RAR. Nothing is written yet — you get a plan back.
3. **Read the plan.** Every file, where it lands, whether it *runs*, and whether it **adds** or
   **replaces**. Refuse anything you did not expect; this is the only moment you see it before your
   players do.
4. **Commit.** Now it is written: the bytes are stored under their own hash and `requiredMods` is
   updated in `server.jsonc` for you.
5. **Restart the server.** The set digest changed, and that is what every launcher compares.

That is it. You never hand-edit `server.jsonc`, and you never upload anything to Open77 — the bytes
stay on your server.

> **Before you reach for a mod at all:** if the content can be built from assets the game already
> has — props, markers, zones, a course — it is a [server resource](/docs/server-resources), not a
> mod. No download, no restart, hot-reloadable. See [Is it a mod at all?](#is-it-a-mod-at-all)


## Mods your server requires › What happens when a player presses Connect

1. The launcher reads your catalogue row, which carries the required list and a set digest announced
   by your server's heartbeat.
2. It asks the master for a verdict on every SHA-256 in that list. Hashes go up, verdicts come back;
   no file moves.
3. It applies the capability cap to each package: an unverified package containing an executable
   type is refused here, before anything is downloaded.
4. It shows the player what the world requires — each package named, sized and badged — and waits
   for consent.
5. It fetches the missing blobs from *your* server, hashes every byte against the announced hash,
   resolves dependencies, projects the files into the game folder and commits.
6. It launches the game into your world.

The player's own game is not touched permanently. World mods live in a per-world profile alongside
the OPEN//77 profile; the Solo profile still gives them their own install back.

There is one restart case, and it is not a normal join: the client is already running in a different
world whose profile does not match. The launcher says so, closes the game, projects the new set and
relaunches straight back into your world.


## Mods your server requires › Is it a mod at all?

This is the second question every owner asks, usually as "can I have a custom map?", and the answer
splits in two. Which half you are in decides whether you need this pipeline or none of it.

| | Runtime placement | Baked geometry |
|---|---|---|
| Examples | Props, barriers, markers, zones, furnished interiors, spawned objects | New buildings, new interiors, terrain |
| Ships as | A Lua resource | `.archive` meshes and sectors plus an ArchiveXL `.xl` |
| Player download | None | The full archive |
| Applies | Hot-reloadable, live | On the next boot |
| Needs this guide | No | Yes |

Use a Lua resource for content assembled from existing game assets: props, barriers, markers, zones or furnished interiors. See [props](props.md), [world UI](worldui.md) and [interactions](interactions.md). Resources can update while players are connected, without downloading additional model archives.

Use a required mod for assets the game does not include. Delivery of `.archive` and `.xl` files does not guarantee custom `.streamingsector` compatibility with world suppression or routing buckets. Custom map geometry remains experimental.


## Mods your server requires › What you can require

Every package carries a trust verdict, and the verdict decides what the package is allowed to
contain.

| Verdict | Meaning | Effect |
|---|---|---|
| `verified` | We read those exact bytes. The hash is in the whitelist with a name, author, source page and a redistribution finding. | Anything, including executable content. The mod menu carries the Open77 mark. |
| `unverified` | Supplied by your world, not reviewed by us. | **Inert data only.** Size-capped, confined to known roots. The player is told before anything is written and can decline. |
| `blocked` | Refused outright. | The join is refused with the reason named. |

Unverified is warned, not blocked, because blocking would make Open77 a bottleneck on every server's
creative choices. That is only safe because of a hard capability cap.

**The cap.** An unverified package may contain inert data and nothing else: `.archive`, `.tweak`,
`.xl`, and INI files under `engine/config`. Executable content — `.dll`, `.reds`, CET Lua, `.asi` —
is refused unless that exact SHA-256 is verified, whatever your server claims about it. The launcher
enforces this against the file's own type and destination, not against your declaration.

**There is no player toggle to bypass it.** Not a global switch, not a per-package grant. A single
"allow unverified mods" checkbox is functionally "let any world run code on my PC", and its failure
mode is normalisation: servers post *just turn on the toggle*, players tick it once and forget, and
within a month the setting protects nobody while still reading as protection. Do not build your
world around a bypass arriving.

A package is also blocked when it writes outside the allowed roots, when the archive contains a path
traversal entry, or when a downloaded file does not hash to what your server announced. That last
one is indistinguishable from tampering and is treated as such.


### Mods your server requires › Redistribution is a separate axis

A mod can be perfectly inert and still be one its author never licensed anyone to hand out. The
whitelist records **safety** and **redistribution** separately, and they often disagree.

When redistribution is refused, you cannot host the bytes. The launcher routes to the player-fetch
flow instead: the player downloads the archive once from the author's own page, the launcher
recognises it by the pinned hash, and every world requiring it afterwards is satisfied from the
local store. Nobody rehosts anything.

Check the author's terms before you import. "It is only a small file" is not a licence.


## Mods your server requires › Add a mod from the Warden panel
### Mods: the complete guide › What a package may contain

The launcher confines every file to a known root and classifies the package by its most privileged
file.

| Root | Typical content | Class |
|---|---|---|
| `archive/pc/mod` | `.archive`, `.xl` | inert |
| `r6/tweaks` | TweakXL `.tweak` / `.yaml` | inert |
| `engine/config` | INI overrides | inert |
| `r6/input`, `r6/config` | input and config XML | inert |
| `r6/scripts` | redscript `.reds` | executable |
| `red4ext/plugins`, `bin/x64/plugins` | `.dll`, `.asi` | executable |
| `bin/x64/plugins/cyber_engine_tweaks/mods` | CET Lua | executable |
| `engine/tools`, `bin/x64`, `mods` | tooling, loaders | executable |

Anything outside these roots, a path-traversal entry, or bytes that do not hash to the announced
value refuses the package.


## Mods: the complete guide › Worked example: a Nexus vehicle on the freeroam server
