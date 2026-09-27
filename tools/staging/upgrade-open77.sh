#!/usr/bin/env bash
set -euo pipefail

archive="${1:?usage: upgrade-open77.sh /path/to/open77-server.tar.gz expected-version}"
expected="${2:?usage: upgrade-open77.sh /path/to/open77-server.tar.gz expected-version}"
root=/opt/ncm
active="$root/server"
candidate="$root/server.$expected.new"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$root/backups/server-$stamp"
script_dir="$(cd "$(dirname "$0")" && pwd)"

test -f "$archive"
test -d "$active"
test ! -e "$candidate"
test ! -e "$backup"

mkdir -p "$candidate" "$root/backups"
tar -xzf "$archive" -C "$candidate"

python3 - "$candidate" "$expected" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected = sys.argv[2]
manifest = json.loads((root / "package-manifest.json").read_text(encoding="utf-8"))
if manifest.get("version") != expected:
    raise SystemExit(f"manifest version {manifest.get('version')!r} != {expected!r}")
if manifest.get("runtime") != "linux-x64":
    raise SystemExit(f"wrong runtime: {manifest.get('runtime')!r}")
for entry in manifest.get("files", []):
    path = root / entry["path"]
    if not path.is_file():
        raise SystemExit(f"missing package file: {entry['path']}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest.lower() != entry["sha256"].lower():
        raise SystemExit(f"hash mismatch: {entry['path']}")
print(f"verified {len(manifest.get('files', []))} files for {expected}")
PY

# Preserve operator-owned state without printing it. Platform resources and
# binaries come exclusively from the new archive.
#
# access.json is the whitelist/ban list. It is written by the server at runtime, lives at the
# tree root, and is not part of the package -- so an upgrade that forgets it silently takes the
# whitelist down (KB-52, and again on .87 -> .102). It is preserved here, not re-added by hand.
for item in server.jsonc acl.jsonc access.json .open77 server-banner.png server-icon.png tunables.json; do
    if test -e "$active/$item"; then
        rm -rf "$candidate/$item"
        cp -a "$active/$item" "$candidate/$item"
    fi
done
ln -sfn "$root/resources/ncm" "$candidate/resources/ncm"
chmod +x "$candidate/Open77.Server" "$candidate/start.sh"

# The server writes access.json (and its .tmp sibling) into its own working directory as the
# systemd service user. Run under sudo, the unpacked tree is root-owned, the tree root becomes
# unwritable to that user, and Warden fails every access change with "access list could not be
# saved; identity was not added" while the server otherwise looks healthy.
svc_user="$(systemctl show -p User --value ncm-server 2>/dev/null || true)"
svc_user="${svc_user:-ubuntu}"
sudo chown -R "$svc_user:$svc_user" "$candidate"

# Package upgrades replace the vendor resource tree. Reassert the NCM world boundary on the
# candidate and validate its explicit load list BEFORE the running server is touched. A healthy
# process with an aborted automatic resource set is not a successful upgrade (KB-51), and the
# freeroam sandbox must not return for even one boot (L131/L132).
python3 "$script_dir/close-freeroam-sandbox.py" "$candidate"
python3 "$script_dir/check-load-list.py" "$candidate"

sudo systemctl stop ncm-server
mv "$active" "$backup"
mv "$candidate" "$active"

if ! sudo systemctl start ncm-server; then
    mv "$active" "$candidate.failed"
    mv "$backup" "$active"
    sudo systemctl start ncm-server
    echo "upgrade failed; previous server restored" >&2
    exit 1
fi

sleep 12
if ! systemctl is-active --quiet ncm-server; then
    sudo systemctl stop ncm-server || true
    mv "$active" "$candidate.failed"
    mv "$backup" "$active"
    sudo systemctl start ncm-server
    echo "new server did not stay active; previous server restored" >&2
    exit 1
fi

python3 - "$active/package-manifest.json" <<'PY'
import json
import sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
print(f"active version={p['version']} runtime={p['runtime']} commit={p['baseCommit']}")
PY

# Post-upgrade access guard. Neither condition announces itself when it is wrong: the server
# runs and Warden loads, and only an attempted whitelist edit -- or an uninvited visitor --
# reveals it.
if sudo -u "$svc_user" test -w "$active"; then
    echo "access guard: $active is writable by $svc_user"
else
    echo "access guard: FAILED -- $active is not writable by $svc_user; Warden cannot save access.json" >&2
    exit 1
fi
if test -f "$active/access.json"; then
    python3 - "$active/access.json" <<'ACCESS'
import json
import sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
wl = state.get("whitelist", {})
print(f"access guard: whitelist enabled={wl.get('enabled')} identities={len(wl.get('users', []))} bans={len(state.get('bans', []))}")
ACCESS
else
    echo "access guard: no access.json carried over -- the whitelist is DOWN; re-enable it in Warden" >&2
fi
echo "backup=$backup"
