#!/usr/bin/env python3
"""The lexicon values known before any server has run (doc 59 §4): NCM's own public Week sentences (Moody lines,
PA steps) and the DNF causes the director can speak. Names arrive later in the `lexicon.json` the `ncm_radio`
resource writes; `render.py lexicon --names` takes either file, or both merged with --merge.

    python ncm/radio/tools/seed_lexicon.py [out.json] [--merge resource-lexicon.json ...]
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_corpus_lua  # noqa: E402  (week_text: the same reader the director data uses)

CAUSES = ['mechanical failure', 'contact with another car', 'a crash']


def main():
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith('--') else 'D:/ncm-radio/lexicon.json'
    merged = {'name': set(), 'org': set(), 'series': set(), 'route': set(), 'phrase': set()}
    moody, steps = build_corpus_lua.week_text()
    merged['phrase'] |= {f['line'] for f in moody.values()} | set(steps.values()) | set(CAUSES)
    if '--merge' in args:
        for path in args[args.index('--merge') + 1:]:
            with io.open(path, encoding='utf-8') as f:
                for cls, values in json.load(f).items():
                    merged.setdefault(cls, set()).update(v for v in values if isinstance(v, str))
    data = {cls: sorted(v) for cls, v in merged.items()}
    with io.open(out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print('wrote %s: %s' % (out, ', '.join('%d %s' % (len(v), k) for k, v in data.items())))


if __name__ == '__main__':
    main()
