#!/usr/bin/env bash
set -euo pipefail

archive="${1:?usage: upgrade-open77.sh /path/to/open77-server.tar.gz expected-version}"
expected="${2:?usage: upgrade-open77.sh /path/to/open77-server.tar.gz expected-version}"
root=/opt/ncm
active="$root/server"
candidate="$root/server.$expected.new"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$root/backups/server-$stamp"

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
for item in server.jsonc acl.jsonc .open77 server-banner.png server-icon.png tunables.json; do
    if test -e "$active/$item"; then
        rm -rf "$candidate/$item"
        cp -a "$active/$item" "$candidate/$item"
    fi
done
ln -sfn "$root/resources/ncm" "$candidate/resources/ncm"
chmod +x "$candidate/Open77.Server" "$candidate/start.sh"

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
echo "backup=$backup"
