#!/usr/bin/env python3
"""Build the NCM Online website (GitHub Pages) from site/content into site/_site.

One dependency (Markdown, pinned in site/requirements.txt). No framework, no node, no backend.

    python site/build.py            # build into site/_site
    python site/build.py --check    # build, then fail on any broken internal link (CI runs this)

Content is Markdown with a small front-matter block. Two pages are partly GENERATED from the game's own data so
they cannot drift from what players see in game:

  * the command reference comes from the Help catalogue in ncm/core/player/help.lua
  * the in-game release notes come from ncm/online/resources/ncm_world/client/landing_content.lua

Both are read with a tiny Lua-literal reader below. If either file changes shape, the build fails loudly rather
than publishing an empty page.
"""
import html
import io
import json
import os
import re
import shutil
import subprocess
import sys
import datetime

import markdown

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CONTENT = os.path.join(HERE, 'content')
STATIC = os.path.join(HERE, 'static')
OUT = os.path.join(HERE, '_site')

SITE_NAME = 'NCM Online'
TAGLINE = 'Motorsports in Night City'
REPO_URL = 'https://github.com/evengineer1ng/ncm-online'
OPEN77_URL = 'https://open2077.net'

# The status vocabulary. One place; every badge on the site comes from here.
STATUSES = {
    'live': ('LIVE', 'Available on the public NCM Online server.'),
    'experimental': ('EXPERIMENTAL', 'Implemented and testable, but unstable or incomplete.'),
    'in-development': ('IN DEVELOPMENT', 'Being built; not necessarily available to players.'),
    'planned': ('PLANNED', 'Designed or intended, not implemented.'),
    'historical': ('HISTORICAL', 'Earlier design or implementation, kept for history.'),
    'dev': ('DEVELOPER', 'Developer infrastructure, not a player feature.'),
}


# ---------------------------------------------------------------------------------------------------------------
# A minimal reader for Lua table literals (strings, numbers, booleans, nil, nested tables, `..` concatenation).
# It is NOT a Lua parser: it reads the authored data tables the game itself renders, nothing more.
# ---------------------------------------------------------------------------------------------------------------
_TOKEN = re.compile(r'''
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*) |
    (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*') |
    (?P<num>-?\d+(?:\.\d+)?) |
    (?P<concat>\.\.) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<punct>[{}=,;])
''', re.S | re.X)


def _lua_tokens(src):
    pos = 0
    while pos < len(src):
        m = _TOKEN.match(src, pos)
        if not m:
            raise ValueError('lua reader: unexpected %r at %d' % (src[pos:pos + 20], pos))
        pos = m.end()
        kind = m.lastgroup
        if kind == 'ws':
            continue
        yield kind, m.group(kind)


def _lua_unquote(s):
    body = s[1:-1]
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), body)


def prose(s):
    """Game copy uses ASCII ` -- ` for a dash; print a real one on the web."""
    return s.replace(' -- ', ' — ') if isinstance(s, str) else s


def lua_table_after(src, marker):
    """Read the table literal that follows `marker` (e.g. 'local CATALOGUE =') in src."""
    i = src.find(marker)
    if i < 0:
        raise ValueError('lua reader: marker %r not found' % marker)
    j = src.index('{', i)
    depth, k, in_str = 0, j, None
    while k < len(src):
        c = src[k]
        if in_str:
            if c == '\\':
                k += 2
                continue
            if c == in_str:
                in_str = None
        elif src.startswith('--', k):
            k = src.find('\n', k)
            continue
        elif c in '"\'':
            in_str = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        k += 1
    toks = list(_lua_tokens(src[j:k + 1]))
    value, _ = _lua_value(toks, 0)
    return value


def _lua_value(toks, i):
    kind, text = toks[i]
    if text == '{':
        return _lua_table(toks, i + 1)
    if kind == 'str':
        s, i = _lua_unquote(text), i + 1
        while i < len(toks) and toks[i][0] == 'concat':
            nxt, i = _lua_value(toks, i + 1)
            s += str(nxt)
        return s, i
    if kind == 'num':
        return (float(text) if '.' in text else int(text)), i + 1
    if text in ('true', 'false'):
        return text == 'true', i + 1
    if text == 'nil':
        return None, i + 1
    raise ValueError('lua reader: unsupported value %r' % text)


def _lua_table(toks, i):
    arr, obj = [], {}
    while toks[i][1] != '}':
        if toks[i][0] == 'name' and i + 1 < len(toks) and toks[i + 1][1] == '=':
            key = toks[i][1]
            val, i = _lua_value(toks, i + 2)
            obj[key] = val
        else:
            val, i = _lua_value(toks, i)
            arr.append(val)
        if toks[i][1] in (',', ';'):
            i += 1
    if obj and arr:
        obj['_list'] = arr
        return obj, i + 1
    return (obj if obj else arr), i + 1


# ---------------------------------------------------------------------------------------------------------------
# Generated sections
# ---------------------------------------------------------------------------------------------------------------
def read_text(rel):
    return io.open(os.path.join(REPO, rel), encoding='utf-8-sig').read()


def gen_commands():
    cat = lua_table_after(read_text('ncm/core/player/help.lua'), 'local CATALOGUE =')
    if not isinstance(cat, list) or len(cat) < 5:
        raise SystemExit('build: the Help catalogue in ncm/core/player/help.lua could not be read')
    rows = ['<div class="table-wrap"><table class="ref" id="command-table">',
            '<thead><tr><th scope="col">Control</th><th scope="col">Key</th><th scope="col">Chat command</th>'
            '<th scope="col">What it does</th></tr></thead><tbody>']
    for e in cat:
        needs = e.get('needs')
        note = (' <span class="note">Shown in game only while the %s system is running.</span>' % html.escape(needs)
                if needs else '')
        rows.append('<tr><td data-label="Control">%s</td><td data-label="Key">%s</td>'
                    '<td data-label="Chat command">%s</td><td data-label="What it does">%s%s</td></tr>' % (
            html.escape(e.get('title', '')),
            '<kbd>%s</kbd>' % html.escape(e['key']) if e.get('key') else '&mdash;',
            '<code>%s</code>' % html.escape(e['cmd']) if e.get('cmd') else '&mdash;',
            html.escape(prose(e.get('text', ''))), note))
    rows.append('</tbody></table></div>')
    return '\n'.join(rows)


def gen_releases():
    data = lua_table_after(read_text('ncm/online/resources/ncm_world/client/landing_content.lua'),
                           'NcmLandingContent =')
    rels = data.get('releases') if isinstance(data, dict) else None
    if not rels:
        raise SystemExit('build: releases in landing_content.lua could not be read')
    rels = sorted(rels, key=lambda r: (r.get('date', ''), r.get('seq', 0)), reverse=True)
    out = []
    for r in rels:
        out.append('<section class="release"><h3>%s <span class="muted">%s%s</span></h3><ul>' % (
            html.escape(r['title']), html.escape(r['date']),
            (' &middot; build %s' % html.escape(r['build'])) if r.get('build') else ''))
        for it in r.get('items', []):
            if isinstance(it, dict):
                head = ('<strong>%s.</strong> ' % html.escape(it['heading'])) if it.get('heading') else ''
                out.append('<li>%s%s</li>' % (head, html.escape(prose(it.get('text', '')))))
            else:
                out.append('<li>%s</li>' % html.escape(str(it)))
        out.append('</ul></section>')
    return '\n'.join(out)


def gen_capabilities():
    data = lua_table_after(read_text('ncm/online/resources/ncm_world/client/landing_content.lua'),
                           'NcmLandingContent =')
    caps = data.get('capabilities') or []
    word = {'live': 'live', 'partial': 'experimental', 'soon': 'planned'}
    out = ['<div class="table-wrap"><table class="ref"><thead><tr><th scope="col">Capability</th>'
           '<th scope="col">Status in game</th><th scope="col">Detail</th></tr></thead><tbody>']
    for c in caps:
        st = word.get(c.get('state', 'live'), 'live')
        detail = html.escape(prose(c.get('detail') or ''))
        if c.get('limit'):
            detail += ' <span class="note">Limit: %s</span>' % html.escape(prose(c['limit']))
        out.append('<tr><td data-label="Capability">%s</td><td data-label="Status">%s</td><td data-label="Detail">%s</td>'
                   '</tr>' % (html.escape(c['label']), badge(st), detail))
    out.append('</tbody></table></div>')
    return '\n'.join(out)


GENERATORS = {'commands': gen_commands, 'releases': gen_releases, 'capabilities': gen_capabilities}


# ---------------------------------------------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------------------------------------------
def badge(status):
    label, title = STATUSES[status]
    return '<span class="badge badge-%s" title="%s">%s</span>' % (status, html.escape(title), label)


def parse_page(path):
    text = io.open(path, encoding='utf-8').read()
    meta = {}
    if text.startswith('---\n'):
        end = text.index('\n---\n', 4)
        for line in text[4:end].splitlines():
            if ':' in line:
                k, v = line.split(':', 1)
                meta[k.strip()] = v.strip()
        text = text[end + 5:]
    if meta.get('status') and meta['status'] not in STATUSES:
        raise SystemExit('build: %s has unknown status %r' % (path, meta['status']))
    return meta, text


def build_info():
    sha = os.environ.get('GITHUB_SHA', '')
    if not sha:
        try:
            sha = subprocess.run(['git', '-C', REPO, 'rev-parse', 'HEAD'], capture_output=True, text=True,
                                 check=True).stdout.strip()
        except Exception:
            sha = ''
    date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
    return sha[:7], sha, date


def nav_tree():
    return json.load(io.open(os.path.join(HERE, 'nav.json'), encoding='utf-8'))


def rel(from_url, to_url):
    """Relative href from page from_url ('systems/racing.html') to to_url ('index.html')."""
    depth = from_url.count('/')
    return ('../' * depth) + to_url


def render_nav(cur, tree):
    parts = ['<ul class="nav-list">']
    for sec in tree:
        if 'children' in sec:
            open_attr = ' open' if any(c['url'] == cur for c in sec['children']) or sec['url'] == cur else ''
            parts.append('<li><details%s><summary><a href="%s"%s>%s</a></summary><ul>' % (
                open_attr, rel(cur, sec['url']), ' aria-current="page"' if sec['url'] == cur else '',
                html.escape(sec['title'])))
            for c in sec['children']:
                parts.append('<li><a href="%s"%s>%s</a></li>' % (
                    rel(cur, c['url']), ' aria-current="page"' if c['url'] == cur else '', html.escape(c['title'])))
            parts.append('</ul></details></li>')
        else:
            parts.append('<li><a href="%s"%s>%s</a></li>' % (
                rel(cur, sec['url']), ' aria-current="page"' if sec['url'] == cur else '', html.escape(sec['title'])))
    parts.append('</ul>')
    return '\n'.join(parts)


TEMPLATE = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:type" content="website">
<meta name="theme-color" content="#05090f">
<link rel="icon" href="{root}assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{root}assets/site.css?v={ver}">
</head>
<body class="{body_class}">
<a class="skip" href="#main">Skip to content</a>
<header class="topbar">
  <a class="brand" href="{root}index.html"><span class="brand-mark" aria-hidden="true">NCM</span><span class="brand-text"><strong>NCM ONLINE</strong><span>Motorsports in Night City</span></span></a>
  <nav class="top-links" aria-label="Primary">
    <a href="{root}getting-started.html">Getting Started</a>
    <a href="{root}how-to-play.html">How to Play</a>
    <a href="{root}systems/index.html">Systems</a>
    <a href="{root}developers/index.html">Developers</a>
    <a href="{repo}">Source</a>
  </nav>
</header>
<div class="layout">
  <aside class="sidebar">
    <details class="menu" {menu_open}>
      <summary>Menu</summary>
      <form class="search" role="search" onsubmit="return false">
        <label for="q" class="sr-only">Search the documentation</label>
        <input id="q" type="search" placeholder="Search docs" autocomplete="off" data-root="{root}">
        <ol id="results" class="results" aria-live="polite"></ol>
      </form>
      <nav aria-label="Site">{nav}</nav>
    </details>
  </aside>
  <main id="main" tabindex="-1">
    {status_line}
    {body}
  </main>
</div>
<footer class="footer">
  <p><strong>NCM Online</strong> is an alpha, actively developed <a href="{open77}">OPEN//77</a> server for Cyberpunk 2077. Not affiliated with or endorsed by CD PROJEKT RED or OPEN//77.</p>
  <p><a href="{repo}">Source on GitHub</a> &middot; <a href="{root}changelog.html">Changelog</a> &middot; <a href="{root}known-issues.html">Known issues</a> &middot; <a href="{repo}/issues">Report a problem</a> &middot; <a href="{repo}/blob/main/LICENSE">MIT License</a></p>
  <p class="muted">Docs built {date} from <a href="{repo}/commit/{sha_full}">{sha}</a>. Status labels: <a href="{root}status.html">what they mean</a>.</p>
</footer>
<script src="{root}assets/search.js?v={ver}" defer></script>
</body>
</html>
'''


def render_page(url, meta, md_text, tree, info, index):
    sha, sha_full, date = info
    root = rel(url, '')
    # `{{!x}}` is an escaped token: it renders literally as `{{x}}` (for pages that document the tokens).
    body_md = md_text.replace('{{!', '')
    body_md = body_md.replace('{{root}}', root)

    def gen(m):
        return GENERATORS[m.group(1)]()
    body_md = re.sub(r'\{\{generated:([a-z]+)\}\}', gen, body_md)
    body_md = re.sub(r'\{\{status:([a-z-]+)\}\}', lambda m: badge(m.group(1)), body_md)
    md = markdown.Markdown(extensions=['tables', 'fenced_code', 'toc', 'attr_list', 'md_in_html', 'sane_lists'],
                           extension_configs={'toc': {'permalink': False}})
    body = md.convert(body_md).replace('', '{{')
    # authored links point at .md sources; publish them as .html
    body = re.sub(r'href="([^":#]+)\.md(#[^"]*)?"', lambda m: 'href="%s.html%s"' % (m.group(1), m.group(2) or ''),
                  body)
    # wrap bare tables so they scroll sideways on phones instead of breaking the page
    body = re.sub(r'(?<!<div class="table-wrap">)<table>', '<div class="table-wrap"><table>', body)
    body = re.sub(r'</table>(?!</div>)', '</table></div>', body)
    status_line = ''
    if meta.get('status'):
        status_line = '<p class="page-status">%s <span class="muted">%s</span></p>' % (
            badge(meta['status']), html.escape(STATUSES[meta['status']][1]))
    title = meta.get('title', SITE_NAME)
    full_title = SITE_NAME + ' — ' + TAGLINE if url == 'index.html' else '%s · %s' % (title, SITE_NAME)
    page = TEMPLATE.format(
        title=html.escape(full_title), description=html.escape(meta.get('description', TAGLINE)),
        root=root, nav=render_nav(url, tree), body=body, status_line=status_line,
        repo=REPO_URL, open77=OPEN77_URL, sha=sha or 'local', sha_full=sha_full or '', date=date,
        body_class='home' if url == 'index.html' else 'doc', menu_open='open',
        ver=sha or date.replace('-', ''))
    text = re.sub(r'<[^>]+>', ' ', body)
    text = re.sub(r'\s+', ' ', html.unescape(text)).strip()
    index.append({'t': title, 'u': url, 'd': meta.get('description', ''), 'x': text[:6000]})
    return page


def check_links():
    bad = []
    for dirpath, _, files in os.walk(OUT):
        for f in files:
            if not f.endswith('.html'):
                continue
            p = os.path.join(dirpath, f)
            src = io.open(p, encoding='utf-8').read()
            for m in re.finditer(r'(?:href|src)="([^"]+)"', src):
                target = m.group(1)
                if re.match(r'^(https?:|mailto:|#|data:)', target):
                    continue
                path = target.split('#')[0].split('?')[0]
                if not path:
                    continue
                if not os.path.exists(os.path.normpath(os.path.join(dirpath, path))):
                    bad.append((os.path.relpath(p, OUT), target))
    return bad


REPO_PATH = re.compile(r'^(?:ncm|tools|docs|site|\.github|wolvenkit-projects|prototypes|ncm-localized)/[^\s<>]*$')


def check_repo_paths():
    """Every repository path a page names (in <code>, or as a GitHub blob link) must still exist."""
    import glob
    bad = []
    for dirpath, _, files in os.walk(OUT):
        for f in files:
            if not f.endswith('.html'):
                continue
            src = io.open(os.path.join(dirpath, f), encoding='utf-8').read()
            cands = [html.unescape(m.group(1)) for m in re.finditer(r'<code>([^<]+)</code>', src)]
            cands += [m.group(1) for m in re.finditer(re.escape(REPO_URL) + r'/blob/main/([^"#]+)', src)]
            for c in cands:
                c = c.strip().rstrip('.,;:')
                if re.match(r'^ncm_[a-z_]+/\S*$', c):      # resource-relative: ncm_world/server/fuel.lua
                    c = 'ncm/online/resources/' + c
                if not REPO_PATH.match(c) or '<' in c or 'NNN' in c or '…' in c:
                    continue
                pattern = re.sub(r'<[^>]+>', '*', c)
                if glob.glob(os.path.join(REPO, pattern.rstrip('/'))):
                    continue
                # a documented path that is git-ignored on purpose (a downloaded runtime, a local build) is fine
                ignored = subprocess.run(['git', '-C', REPO, 'check-ignore', '-q', '--no-index', pattern],
                                         capture_output=True).returncode == 0
                if not ignored:
                    bad.append((os.path.relpath(os.path.join(dirpath, f), OUT), c))
    return bad


def main():
    check = '--check' in sys.argv
    if os.path.isdir(OUT):
        # empty it rather than removing it: a shell sitting in _site would otherwise block the build on Windows
        for name in os.listdir(OUT):
            p = os.path.join(OUT, name)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    shutil.copytree(STATIC, OUT, dirs_exist_ok=True)
    tree = nav_tree()
    info = build_info()
    index = []
    count = 0
    for dirpath, _, files in os.walk(CONTENT):
        for f in sorted(files):
            if not f.endswith('.md'):
                continue
            src = os.path.join(dirpath, f)
            url = os.path.relpath(src, CONTENT).replace(os.sep, '/')[:-3] + '.html'
            meta, text = parse_page(src)
            out = os.path.join(OUT, url)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            io.open(out, 'w', encoding='utf-8', newline='\n').write(render_page(url, meta, text, tree, info, index))
            count += 1
    io.open(os.path.join(OUT, 'search-index.json'), 'w', encoding='utf-8').write(
        json.dumps(index, ensure_ascii=False, separators=(',', ':')))
    io.open(os.path.join(OUT, '.nojekyll'), 'w').write('')
    print('built %d pages into %s' % (count, os.path.relpath(OUT, REPO)))
    if check:
        bad = check_links()
        nav_urls = [s['url'] for s in tree] + [c['url'] for s in tree for c in s.get('children', [])]
        missing = [u for u in nav_urls if not os.path.exists(os.path.join(OUT, u))]
        for p, t in bad:
            print('broken link: %s -> %s' % (p, t))
        for u in missing:
            print('nav entry has no page: %s' % u)
        stale = check_repo_paths()
        for p, c in stale:
            print('names a repository path that does not exist: %s -> %s' % (p, c))
        if bad or missing or stale:
            return 1
        print('links OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
