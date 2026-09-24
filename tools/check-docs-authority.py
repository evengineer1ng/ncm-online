#!/usr/bin/env python3
"""Gate: documentation authority cannot silently decay (L125).

RUN AS PART OF tools/ncm-test.ps1.

The problem this exists for: old and current NCM architecture were equally discoverable, so a settled
decision (team cars are ordinary machine assets) looked unresolved because superseded TW2-era material sat
beside the current authority. The fix is a status banner on every document plus INDEX.md as the authority
map -- and neither survives more than a few sessions without an assertion.

It deliberately does NOT check that content is correct or current. It checks that a reader can always tell
WHICH documents claim to be current, and that navigation to them works.

Checks:
  1. every .md under docs/ncm-online has exactly one STATUS banner (fenced code blocks ignored, so a
     document may show example banners -- 26_DOCUMENT_AUTHORITY.md does)
  2. every banner names one of the six known statuses
  3. every SUPERSEDED banner names what replaced it
  4. no dangling relative link anywhere under docs/ncm-online
  5. every document appears in INDEX.md
  6. BACKLOG.md ledger ids are unique, and `Next free ID` is above every id used (L68)

Check 6 exists because on 2026-09-24 two concurrent sessions each read `Next free ID`, each claimed
IDEA-369..373, and both were right at the moment they looked. The ledger is append-only and ids are
permanent, so a duplicate that reaches the file is permanent too. `Next free ID` is a read-modify-write on a
shared file with no lock, and the NOW.md claim block already records it going stale three times; this makes
it a refusal instead of a note asking people to try harder.
  6. no two CURRENT documents claim the same "authority for" topic

Exit codes: 0 clean, 1 problems found, 2 could not inspect.
Usage: python tools/check-docs-authority.py [docs-root]
"""
import io
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join('docs', 'ncm-online')
STATUSES = ('CURRENT', 'SPEC', 'PROPOSAL', 'SUPERSEDED', 'HISTORICAL', 'LEDGER')
BANNER = re.compile(r'^> \*\*STATUS: ([A-Z]+)\*\*(.*)$')
LINK = re.compile(r'\]\((?!https?://|mailto:|#|/)([^)]+)\)')


def strip_fences(text):
    """Blank out fenced code blocks so example banners inside them are not counted as real ones."""
    out, fenced = [], False
    for line in text.split('\n'):
        if line.lstrip().startswith('```'):
            fenced = not fenced
            out.append('')
            continue
        out.append('' if fenced else line)
    return out


# ---------------------------------------------------------------------------------------------
# Already-committed duplicate ledger ids, listed rather than hidden.
# ---------------------------------------------------------------------------------------------
#
# **These seven are real and this gate did not exist to stop them.** On 2026-09-24 an external-tooling/API
# audit and a state-bag/machine-knowledge pass ran as concurrent sessions, each read `Next free ID`, and each
# correctly claimed IDEA-340..346. Both sets are committed, and both are referenced from code comments and
# from other documents -- `IDEA-341` appears in `ncm_world/client/race.lua`, for instance.
#
# They are NOT renumbered here. L68 makes ids permanent and rows append-only, and NOW.md is explicit: *do not
# reuse ids or rewrite another session's authored history.* Renumbering either set silently would do exactly
# that, and would strand the references. **Resolving them is an owner decision** and is already open as
# `IDEA-296`; `IDEA-380` records how they happened.
#
# Listing them here is the point: they stay visible on every run, and nothing may be added to this list
# without a person deciding to. A NEW duplicate fails the gate.
KNOWN_DUPLICATE_IDS = {340, 341, 342, 343, 344, 345, 346}


def main():
    if not os.path.isdir(ROOT):
        print('cannot inspect: %s is not a directory' % ROOT)
        return 2
    index_path = os.path.join(ROOT, 'INDEX.md')
    if not os.path.exists(index_path):
        print('cannot inspect: %s is missing -- it is the authority map' % index_path)
        return 2
    index_text = open(index_path, encoding='utf-8').read()

    problems = []
    topics = {}
    docs = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        for f in sorted(filenames):
            if f.endswith('.md'):
                docs.append(os.path.join(dirpath, f))

    for path in docs:
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        text = open(path, encoding='utf-8').read()
        lines = strip_fences(text)

        banners = [m for m in (BANNER.match(l) for l in lines) if m]
        if len(banners) != 1:
            problems.append(('banner count %d (want 1)' % len(banners), rel, ''))
            continue
        status, tail = banners[0].group(1), banners[0].group(2)

        if status not in STATUSES:
            problems.append(('unknown status %r' % status, rel, ''))
        if status == 'SUPERSEDED' and not re.search(r'by \S', tail):
            problems.append(('SUPERSEDED names no successor', rel, ''))
        if status == 'CURRENT':
            m = re.search(r'authority for: \*([^*]+)\*', tail)
            if not m:
                problems.append(('CURRENT names no topic', rel, ''))
            else:
                key = m.group(1).strip().lower()
                if key in topics:
                    problems.append(('two CURRENT docs claim the same topic', rel, topics[key]))
                topics[key] = rel

        # INDEX must list it (the archive is reachable only through the map)
        if rel != 'INDEX.md' and os.path.basename(rel) not in index_text:
            problems.append(('not listed in INDEX.md', rel, ''))

        # links must resolve
        for m in LINK.finditer(text):
            target = m.group(1).split('#')[0]
            if not target:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not os.path.exists(resolved):
                problems.append(('dangling link', rel, target))

    # ---- 6. ledger ids are unique and the next-free line is ahead of them (L68) ----
    ledger = os.path.join(ROOT, 'BACKLOG.md')
    ledger_ids = 0
    if os.path.exists(ledger):
        text = io.open(ledger, encoding='utf-8').read()
        seen = {}
        for m in re.finditer(r'(?m)^\|\s*IDEA-(\d+)\s*\|', text):
            n = int(m.group(1))
            seen[n] = seen.get(n, 0) + 1
        ledger_ids = len(seen)
        for n in sorted(k for k, c in seen.items() if c > 1):
            if n in KNOWN_DUPLICATE_IDS:
                continue
            problems.append(('duplicate ledger id', 'BACKLOG.md', 'IDEA-%d used %d times' % (n, seen[n])))
        free = re.search(r'Next free ID:\s*\*\*IDEA-(\d+)\*\*', text)
        if not free:
            problems.append(('no next-free-id line', 'BACKLOG.md', ''))
        elif seen and int(free.group(1)) <= max(seen):
            problems.append(('next free id already used', 'BACKLOG.md',
                             'says IDEA-%s, highest row is IDEA-%d' % (free.group(1), max(seen))))

    if not problems:
        print('docs authority OK: %d document(s), every banner valid, every link resolves, '
              '%d ledger id(s) unique' % (len(docs), ledger_ids))
        return 0

    print('DOCUMENTATION AUTHORITY PROBLEMS (%d):' % len(problems))
    for kind, where, extra in problems:
        print('  %-42s %s%s' % (kind, where, (' -> ' + extra) if extra else ''))
    print('')
    print('Every document needs a banner directly under its H1:')
    print('  > **STATUS: CURRENT** - authority for: *topic* - affirmed <date> (<L-line>)')
    print('and must be listed in INDEX.md. See 26_DOCUMENT_AUTHORITY.md.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
