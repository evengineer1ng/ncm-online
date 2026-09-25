#!/usr/bin/env python3
"""Evict the freeroam sandbox: no free vehicles, weapons, /freeroam, /race or /pvp. Keep /anim.

WHY THIS EXISTS
---------------
`freeroam` is OPEN//77's own gamemode resource and it hands players a vehicle-and-weapon vending
machine. On 2026-09-25 at 03:22 a player took a Masamune with 500 rounds, a katana and an Archer
Bandit out of it, then crashed the car -- having opened NCM's Market four times and bought nothing.
That is L102 ("a player being able to spawn cars, even loaners, sinks economy") being violated by a
resource sitting beside NCM rather than by NCM.

It also brings /race and /pvp, which compete with the thing NCM is for.

WHAT THIS CHANGES (four edits, all reversible)
----------------------------------------------
1. `restrictPlayerCommands = true` in shared/config.lua.
   This is the one flag that closes the WHOLE delivery surface, not just half of it: freeroam's
   `RegisterNetEvent("freeroam:menu")` handler refuses every mutation when it is set (server/main.lua
   ~L822), and /car /dv /goto /tpc /spawn /suicide /revive go behind the ACL. Setting only the
   commands would have left the menu -- and the menu is the path the player actually used.

2. `combat.pvpEnabled = false`.
   freeroam opts INTO friendly fire; the platform default is off. Turning the opt-in off restores it.

3. The race and pvp SERVER and CLIENT scripts, plus server/playtest.lua, are commented out of
   open77.lua.
   Their `shared_script` lines STAY. `client/main.lua` line 38 reads `DeathmatchConfig.blade`
   unguarded, so dropping pvp/shared/config.lua raises at client-script load and takes the whole
   freeroam client with it -- including the animation menu we are keeping. The shared files are pure
   data tables with no side effects, so keeping them costs nothing and removing them costs the client.
   server/combat.lua L45 reads `Open77.combat.setFriendlyFire(Deathmatch ~= nil)`; with the pvp
   server half gone `Deathmatch` is nil, so friendly fire is off there too.
   server/playtest.lua calls `FreeroamRace.canPlaytest` with no nil guard, so it goes with them.

4. `freeroam` and `open77_freeroam` are removed from `resources.load`, and the `freeroam` discovery
   tag is removed from `server.jsonc`. This is the actual authority boundary. The edits above remain
   as defence in depth if an operator accidentally starts the resource by hand.

WHAT IS DELIBERATELY KEPT
-------------------------
`open77_animations` remains loaded. `/anim <profile>`, `/anim list`, `/anim info` and `/anim stop`
are registered by that standalone platform resource. Only the no-argument picker page was supplied
by the freeroam client and leaves with it.

This also intentionally removes freeroam's join kill/respawn spine. OPEN//77 0.87 has a real player
teleport and NCM already owns persistent placement. NCM does not yet own respawn-after-death, so a
dead player may need to reconnect until that separate lifecycle is implemented. That known gap is
preferable to retaining an unauthorized gamemode whose command and spawn surfaces contradict NCM.

USAGE
    python3 close-freeroam-sandbox.py [server-root]      # default: /opt/ncm/server
    python3 close-freeroam-sandbox.py ... --revert

Idempotent. RE-RUN AFTER EVERY OPEN//77 UPGRADE: this tree is vendor-owned and an upgrade restores it.
Exit 0 changed or already applied, 2 could not inspect.
"""
import os
import re
import sys

MARK = "-- ncm: disabled by tools/staging/close-freeroam-sandbox.py --"

# Scripts to disable. Shared scripts are absent on purpose (see the docstring).
DISABLE = (
    "server_script \"pvp/server/instances.lua\"",
    "server_script \"pvp/server/mapstore.lua\"",
    "server_script \"pvp/server/bounds.lua\"",
    "server_script \"pvp/server/loadout.lua\"",
    "server_script \"pvp/server/scoring.lua\"",
    "server_script \"pvp/server/bots.lua\"",
    "server_script \"pvp/server/round.lua\"",
    "server_script \"pvp/server/arena.lua\"",
    "server_script \"pvp/server/rating.lua\"",
    "server_script \"pvp/server/ranked.lua\"",
    "server_script \"pvp/server/survey.lua\"",
    "server_script \"pvp/server/main.lua\"",
    "server_script \"pvp/server/freeroam.lua\"",
    "server_script \"race/server/courses.lua\"",
    "server_script \"race/server/main.lua\"",
    "server_script \"server/playtest.lua\"",
    "client_script \"race/client/foot_markers.lua\"",
    "client_script \"race/client/checkpoints.lua\"",
    "client_script \"race/client/main.lua\"",
    "client_script \"pvp/client/bounds.lua\"",
    "client_script \"pvp/client/main.lua\"",
)


def edit(path, pairs, revert):
    """Apply (old, new) replacements. Returns a list of what actually changed."""
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    before = text
    done = []
    for old, new in pairs:
        frm, to = (new, old) if revert else (old, new)
        # Manifest disable markers contain the original directive verbatim. Without this guard an
        # idempotent re-run finds that substring and prepends a second marker.
        if not revert and old in new and new in text:
            continue
        if frm in text:
            text = text.replace(frm, to, 1)
            done.append(to.strip().splitlines()[0][:72])
    if text != before:
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
    return done


def set_array_values(path, key, values, present):
    """Add/remove exact string entries in one JSONC array without depending on their order."""
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    pattern = re.compile(
        r'(?P<head>^[ \t]*"%s"\s*:\s*\[)(?P<body>.*?)(?P<tail>^[ \t]*\])'
        % re.escape(key), re.M | re.S)
    match = pattern.search(text)
    if not match:
        raise ValueError("cannot find JSONC array: %s" % key)
    current = re.findall(r'"([a-zA-Z0-9_]+)"', match.group("body"))
    before = list(current)
    if present:
        for value in values:
            if value not in current:
                current.append(value)
    else:
        current = [value for value in current if value not in values]
    if current == before:
        return []
    indent_match = re.search(r'^([ \t]*)"', match.group("body"), re.M)
    indent = indent_match.group(1) if indent_match else "      "
    body = "\n" + ",\n".join('%s"%s"' % (indent, value) for value in current) + "\n"
    text = text[:match.start()] + match.group("head") + body + match.group("tail") + text[match.end():]
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    action = "added" if present else "removed"
    return ["%s %s from %s[]" % (action, ", ".join(values), key)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    revert = "--revert" in sys.argv
    server = args[0] if args else os.environ.get("NCM_SERVER_ROOT", "/opt/ncm/server")
    root = os.path.join(server, "resources", "gamemodes", "freeroam")
    conf = os.path.join(root, "shared", "config.lua")
    manifest = os.path.join(root, "open77.lua")
    server_conf = os.path.join(server, "server.jsonc")

    for p in (conf, manifest, server_conf):
        if not os.path.exists(p):
            print("cannot inspect: %s missing" % p)
            return 2

    # Repair marker stacking produced by the pre-eviction version of this script. This is bounded
    # normalization of our own exact marker, not a generic rewrite of vendor comments.
    with open(manifest, "r", encoding="utf-8") as fh:
        manifest_text = fh.read()
    doubled = "%s %s " % (MARK, MARK)
    normalized = manifest_text
    while doubled in normalized:
        normalized = normalized.replace(doubled, MARK + " ")
    if normalized != manifest_text:
        with open(manifest, "w", encoding="utf-8", newline="") as fh:
            fh.write(normalized)

    changed = edit(conf, [
        ("restrictPlayerCommands = false", "restrictPlayerCommands = true"),
        ("pvpEnabled = true", "pvpEnabled = false"),
    ], revert)

    changed += edit(manifest, [(line, "%s %s" % (MARK, line)) for line in DISABLE], revert)
    try:
        changed += set_array_values(server_conf, "tags", ["freeroam"], present=revert)
        changed += set_array_values(
            server_conf, "load", ["freeroam", "open77_freeroam"], present=revert)
    except ValueError as exc:
        print("cannot inspect: %s" % exc)
        return 2

    verb = "re-enabled" if revert else "disabled"
    if not changed:
        print("already %s -- nothing to do" % ("re-enabled" if revert else "applied"))
    else:
        print("%s %d item(s):" % (verb, len(changed)))
        for c in changed:
            print("  " + c)

    # State readback, so the caller never has to trust the word "applied".
    with open(conf, encoding="utf-8") as fh:
        c = fh.read()
    with open(manifest, encoding="utf-8") as fh:
        m = fh.read()
    with open(server_conf, encoding="utf-8") as fh:
        s = fh.read()
    tag_match = re.search(r'"tags"\s*:\s*\[(.*?)\]', s, re.S)
    tags = set(re.findall(r'"([a-zA-Z0-9_]+)"', tag_match.group(1))) if tag_match else set()
    load_match = re.search(r'"resources"\s*:\s*\{.*?"load"\s*:\s*\[(.*?)\]', s, re.S)
    loaded = set(re.findall(r'"([a-zA-Z0-9_]+)"', load_match.group(1))) if load_match else set()
    print("")
    print("restrictPlayerCommands = %s" % ("true" if "restrictPlayerCommands = true" in c else "false"))
    print("combat.pvpEnabled      = %s" % ("false" if "pvpEnabled = false" in c else "true"))
    print("race/pvp scripts active= %d of %d" % (
        sum(1 for d in DISABLE if re.search(r"^\s*%s" % re.escape(d), m, re.M)), len(DISABLE)))
    print("freeroam loaded        = %s" % ("yes" if "freeroam" in loaded else "no"))
    print("open77_freeroam loaded = %s" % ("yes" if "open77_freeroam" in loaded else "no"))
    print("open77_animations kept = %s" % ("yes" if "open77_animations" in loaded else "NO"))
    print("freeroam server tag     = %s" % ("yes" if "freeroam" in tags else "no"))

    expected = revert == ("freeroam" in loaded and "open77_freeroam" in loaded)
    expected_tag = revert == ("freeroam" in tags)
    if not expected or not expected_tag or "open77_animations" not in loaded:
        print("ERROR: resources.load did not reach the requested state")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
