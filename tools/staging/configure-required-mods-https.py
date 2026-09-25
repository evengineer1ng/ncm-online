#!/usr/bin/env python3
"""Prepare NCM Online's existing four RequiredMods for public HTTPS delivery.

The OPEN//77 process becomes a loopback-only HTTP origin on 11782. Caddy owns
the already-public 11779/tcp listener and terminates TLS there. This script
never prints the rest of server.jsonc because it contains the licence key.

Dry-run by default. Pass --apply only after Caddy is installed/configured and
the production whitelist window is active.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from datetime import datetime, timezone


SERVER_CONFIG = Path("/opt/ncm/server/server.jsonc")
MOD_STORE = Path("/opt/ncm/server/.open77/mods")
BACKUP_ROOT = Path("/opt/ncm/backups")
PUBLIC_BASE_URL = "https://52-60-225-137.sslip.io:11779/"
ORIGIN_LISTEN_URL = "http://127.0.0.1:11782"

PACKAGES = (
    {
        "id": "archivexl",
        "source": "hosted",
        "displayName": "ArchiveXL",
        "version": "1.27.1",
        "sha256": "608b7b2fed4c35751cd264a87dcfe9d9074fb6d48458d29bde955f1c03dc0d5c",
        "sizeBytes": 1_037_774,
        "capability": "executable",
    },
    {
        "id": "tweakxl",
        "source": "hosted",
        "displayName": "tweakxl",
        "version": "1.11.4",
        "sha256": "13033a1f10cb1dbfa534964b22e3405aa33e8f29145f17164d318b021402883f",
        "sizeBytes": 1_046_349,
        "capability": "executable",
    },
    {
        "id": "rb15-f1-inert-v10",
        "source": "hosted",
        "displayName": "RB15 F1 (car only, no ERS)",
        "version": "10.0.0",
        "sha256": "d597ceb456f4d1c3b843d0f7e4fe691ba8328524d8634f5f596da8e4405f8e39",
        "sizeBytes": 38_537_004,
        "capability": "inert",
    },
    {
        "id": "ncm-rb15-liveries",
        "source": "hosted",
        "displayName": "NCM RB15 Team Liveries",
        "version": "1.0.0",
        "sha256": "d1fe9bd0ad1b2c8d6a4d9cfc73327660c4d8ec3386391d3d39b387940b0840f9",
        "sizeBytes": 7_829_853,
        "capability": "inert",
    },
)


def find_object(text: str, key: str) -> tuple[int, int, str]:
    match = re.search(rf'"{re.escape(key)}"\s*:', text)
    if not match:
        raise RuntimeError(f"missing {key!r} object")
    start = match.start()
    brace = text.find("{", match.end())
    if brace < 0:
        raise RuntimeError(f"missing opening brace for {key!r}")

    depth = 0
    in_string = False
    escaped = False
    for index in range(brace, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                return start, end, text[start:end]
    raise RuntimeError(f"unterminated {key!r} object")


def replace_string(block: str, key: str, value: str) -> str:
    pattern = rf'("{re.escape(key)}"\s*:\s*)"[^"]*"'
    result, count = re.subn(pattern, rf'\g<1>"{value}"', block, count=1)
    if count != 1:
        raise RuntimeError(f"expected one {key!r} value; replaced {count}")
    return result


def required_mods_block(indent: str = "  ") -> str:
    package_rows = []
    for package in PACKAGES:
        public = {key: value for key, value in package.items() if key != "capability"}
        rendered = json.dumps(public, indent=2, ensure_ascii=False)
        rendered = "\n".join(indent * 3 + line for line in rendered.splitlines())
        package_rows.append(rendered)
    packages = ",\n".join(package_rows)
    return (
        '"requiredMods": {\n'
        f'{indent}"enabled": true,\n'
        f'{indent}"unsecured": true,\n'
        f'{indent}"note": "NCM RB15, liveries, and exact hosted loader dependencies",\n'
        f'{indent}"packages": [\n'
        f"{packages}\n"
        f'{indent}]\n'
        "}"
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_store() -> None:
    for expected in PACKAGES:
        digest = expected["sha256"]
        metadata_path = MOD_STORE / f"{digest}.json"
        blob_path = MOD_STORE / f"{digest}.blob"
        if not metadata_path.is_file() or not blob_path.is_file():
            raise RuntimeError(f"missing store files for {expected['id']}")
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        for key in ("id", "version", "sha256", "sizeBytes", "capability"):
            if metadata.get(key) != expected[key]:
                raise RuntimeError(
                    f"{expected['id']} metadata {key}: "
                    f"{metadata.get(key)!r} != {expected[key]!r}"
                )
        if blob_path.stat().st_size != expected["sizeBytes"]:
            raise RuntimeError(f"{expected['id']} blob size mismatch")
        if sha256(blob_path) != digest:
            raise RuntimeError(f"{expected['id']} blob hash mismatch")
        print(
            f"store PASS {expected['id']} {expected['version']} "
            f"{expected['sizeBytes']} {digest}"
        )


def atomic_write(path: Path, content: str) -> None:
    stat = path.stat()
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.st_mode)
        os.chown(temporary, stat.st_uid, stat.st_gid)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="back up and write server.jsonc")
    args = parser.parse_args()

    verify_store()
    original = SERVER_CONFIG.read_text(encoding="utf-8")

    download_start, download_end, download = find_object(original, "download")
    download = replace_string(download, "listenUrl", ORIGIN_LISTEN_URL)
    download = replace_string(download, "publicBaseUrl", PUBLIC_BASE_URL)
    updated = original[:download_start] + download + original[download_end:]

    mods_start, mods_end, _ = find_object(updated, "requiredMods")
    updated = updated[:mods_start] + required_mods_block() + updated[mods_end:]

    # Validate the exact non-secret result before writing.
    _, _, download_check = find_object(updated, "download")
    _, _, mods_check = find_object(updated, "requiredMods")
    if ORIGIN_LISTEN_URL not in download_check or PUBLIC_BASE_URL not in download_check:
        raise RuntimeError("download endpoint validation failed")
    ids = re.findall(r'"id"\s*:\s*"([^"]+)"', mods_check)
    if ids != [package["id"] for package in PACKAGES]:
        raise RuntimeError(f"package order/content validation failed: {ids}")
    print(f"origin: {ORIGIN_LISTEN_URL}")
    print(f"public: {PUBLIC_BASE_URL}")
    print(f"requiredMods: enabled=true unsecured=true packages={ids}")

    if not args.apply:
        print("DRY RUN: server.jsonc not changed")
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_dir = BACKUP_ROOT / f"required-mods-https-{stamp}"
    backup_dir.mkdir(parents=True, exist_ok=False)
    backup = backup_dir / "server.jsonc"
    shutil.copy2(SERVER_CONFIG, backup)
    atomic_write(SERVER_CONFIG, updated)
    print(f"APPLIED: backup={backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
