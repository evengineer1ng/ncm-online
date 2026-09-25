#!/usr/bin/env python3
"""Set the resource-download `publicBaseUrl` -- the URL the launcher fetches mod blobs from.

    python3 set-download-url.py <server-root> --url http://127.0.0.1:11779/
    python3 set-download-url.py <server-root>                 # show the current value

WHY THIS EXISTS: `KB-112`. Launchers `.89` and `.100` **sanitize every non-loopback `http:` mod URL to
null**, then misreport the missing URL as `Unverifiable`. The failure happens before download, cache, root
check, collision, hash or projection -- so the package looks fine from the server side and simply never
reaches the game. The visible symptom is a join that reports `OP77_WORLD_MODS_DIGEST=-` and projects
`0 added`, with no consent prompt at all.

Two URLs survive sanitation:

  * **loopback HTTP** -- `http://127.0.0.1:<port>/`, correct for a Development box you play on yourself.
  * **public HTTPS** -- what Production uses, via Caddy TLS termination.

A private-LAN address like `http://10.0.0.70:11779/` is neither, and it is what the server advertises by
default because it picks the host's own interface.

NEVER PRINTS THE LICENCE. Backs up before writing. Restart the server afterwards.
"""
import argparse
import datetime
import os
import re
import shutil
import sys


def find_value(text, key):
    m = re.search(r'"%s"\s*:\s*"([^"]*)"' % re.escape(key), text)
    return m.group(1) if m else None


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("server_root", nargs="?",
                        default=os.environ.get("NCM_SERVER_ROOT", "/opt/ncm/server"))
    parser.add_argument("--url", help="the new publicBaseUrl, e.g. http://127.0.0.1:11779/")
    args = parser.parse_args()

    conf = os.path.join(args.server_root, "server.jsonc")
    if not os.path.exists(conf):
        raise SystemExit("no server.jsonc under %s -- wrong server root?" % args.server_root)

    with open(conf, "r", encoding="utf-8") as fh:
        text = fh.read()

    current = find_value(text, "publicBaseUrl")
    print("server root    : %s" % os.path.abspath(args.server_root))
    print("publicBaseUrl  : %s" % (current if current is not None else "(not set)"))

    if not args.url:
        if current and current.startswith("http://") and "127.0.0.1" not in current \
                and "localhost" not in current:
            print("\nWARNING (KB-112): this is a non-loopback plain-HTTP URL. The launcher will null it out,")
            print("the world's mods digest will be empty, and no package will ever be offered to the player.")
        return 0

    if current is None:
        raise SystemExit("no publicBaseUrl field to set -- is resource downloading configured?")

    new = args.url
    if not new.endswith("/"):
        new += "/"
    if new.startswith("http://") and "127.0.0.1" not in new and "localhost" not in new:
        print("\nREFUSING: %s is non-loopback plain HTTP and the launcher will discard it (KB-112)." % new)
        print("Use http://127.0.0.1:<port>/ for Development, or an https:// origin for a public server.")
        return 1

    updated, n = re.subn(r'("publicBaseUrl"\s*:\s*)"[^"]*"',
                         lambda m: m.group(1) + '"' + new.replace('"', '\\"') + '"', text, count=1)
    if n != 1:
        raise SystemExit("expected exactly one publicBaseUrl; replaced %d" % n)

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    shutil.copy2(conf, "%s.bak-%s" % (conf, stamp))
    with open(conf, "w", encoding="utf-8") as fh:
        fh.write(updated)

    print("\nbackup         : server.jsonc.bak-%s" % stamp)
    print("publicBaseUrl  : %s  (was %s)" % (new, current))
    print("\nRESTART THE SERVER, then rejoin. Expect the launcher to log a consent line and `N added`,")
    print("and the game to launch with OP77_WORLD_MODS_DIGEST set rather than '-'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
