#!/usr/bin/env python3
"""Split the NCM Radio package into required mods under OPEN//77's archive cap (doc 59 §7, KB-418).

    python tools/split-radio-pack.py dist/ncm-radio-0.1.2-full.zip --version 0.1.2

OPEN//77 caps a required-mod archive at 64 MiB (`docs/rcon.md`); a larger hosted blob is declared in the manifest
but never served (404), so no player could download the 265 MB voice pack. Every clip is its own file under
`red4ext/plugins/ncm_radio/pack/clips/`, so the pack splits cleanly: `ncm-radio` keeps the plugin, the scripts and
the manifest, and `ncm-radio-voices-<n>` packages carry the rest of the clips into the same folder. The installed
tree is byte-identical to the single zip.
"""
import argparse
import os
import zipfile

CAP = 60 * 1024 * 1024   # under the 64 MiB cap with room for zip overhead


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('zip')
    ap.add_argument('--version', required=True)
    ap.add_argument('--out', default=None)
    a = ap.parse_args()
    out = a.out or os.path.dirname(os.path.abspath(a.zip))
    src = zipfile.ZipFile(a.zip)
    src_path = os.path.normcase(os.path.abspath(a.zip))
    entries = [i for i in src.infolist() if not i.is_dir()]
    name = lambda i: i.filename.replace('\\', '/')
    clips = sorted((i for i in entries if '/pack/clips/' in name(i)), key=name)
    rest = [i for i in entries if '/pack/clips/' not in name(i)]
    parts = [rest]
    size = sum(i.compress_size for i in rest)
    for i in clips:
        if size + i.compress_size > CAP:
            parts.append([])
            size = 0
        parts[-1].append(i)
        size += i.compress_size
    written = []
    for n, part in enumerate(parts):
        pid = 'ncm-radio' if n == 0 else 'ncm-radio-voices-%d' % n
        path = os.path.join(out, '%s-%s.zip' % (pid, a.version))
        assert os.path.normcase(os.path.abspath(path)) != src_path, 'refusing to overwrite the source zip ' + path
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_STORED) as z:   # OGG is already compressed
            for i in part:
                z.writestr(name(i), src.read(i))
        written.append((pid, path, os.path.getsize(path), len(part)))
    for pid, path, sz, k in written:
        print('%-20s %6.1f MiB %6d files  %s' % (pid, sz / 1048576.0, k, path))
        assert sz < 64 * 1024 * 1024, pid


if __name__ == '__main__':
    main()
