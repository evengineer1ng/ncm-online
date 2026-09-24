#!/usr/bin/env python
"""
Build the NCM RB15 livery add-on from a folder of PNGs.

    python build_liveries.py                 # builds every liveries/rb15_ext_*.png
    python build_liveries.py --deploy        # ...and copies the result into the game folder
    python build_liveries.py --with-test     # also include the green 'ncm_test' livery

Input : liveries/rb15_ext_<name>.png      (4096x4096 RGB, sRGB, opaque; <name> = [a-z0-9_]+)   REQUIRED per livery
        liveries/rb15_badges_<name>.png   (1024x1024 RGB) OPTIONAL sponsor/decal plate sheet for that livery
        liveries/rb15_badges_default.png  (1024x1024 RGB) OPTIONAL fallback badges for liveries without their own
        Badge resolution order: own file > rb15_badges_default.png > the RB15's stock badges (nothing patched).
Output: out/payload/  (archive/pc/mod/ncm_rb15_liveries.archive + .xl, r6/tweaks/zzzz_ncm_rb15_liveries.yaml — named to sort after rb15_f1_*.yaml: TweakXL reads alphabetically and $base clones need the RB15 record first)
        out/NCM_RB15_Liveries_<date>.zip   (same payload under NCM_RB15_Liveries/ for the checkpoint deploy scripts)

For every livery <name> it produces, entirely inside OUR archive (nothing of the RB15 is copied or overwritten):
  * ncm\rb15_liveries\textures\rb15_ext_<name>.xbm         BC7 / sRGB / mips, same as the original
  * mesh appearance <name> + local material rb15_ext_<name> (+ rb15_badges_<name> when a badge sheet is given)
    in the geometry-free patch mesh
  * appearance <name> in ncm\rb15_liveries\rb15_liveries.app (clone of player_01, body_01 -> <name>)
  * appearance entry <name> in the .ent patch applied to fable5\rb15\rb15.ent
  * TweakXL record Vehicle.v_sport1_rb15_f1_<name> ($base RB15, only appearanceName differs)

Requires: WolvenKit CLI 8.20 (tools/WolvenKit.Console-8.20.0), the RB15 installed (fable5.archive).
"""
import argparse, copy, datetime, json, os, re, shutil, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
WORKSPACE = os.path.dirname(os.path.dirname(PROJ))
CLI = os.path.join(WORKSPACE, 'tools', 'WolvenKit.Console-8.20.0', 'WolvenKit.CLI.exe')
GAME = r'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
RB15_ARCHIVE = os.environ.get('NCM_RB15_ARCHIVE') or os.path.join(GAME, 'archive', 'pc', 'mod', 'fable5.archive')  # override when the launcher has quarantined the game copy
BS = chr(92)

LIVERY_DIR = os.path.join(PROJ, 'liveries')
OUT = os.path.join(PROJ, 'out')
TEST_PNG = os.path.join(PROJ, 'source', 'ncm', 'rb15_liveries', 'textures', 'rb15_ext_ncm_test.png')

BODY_MESH = BS.join(['fable5', 'rb15', 'meshes', 'rb15_body.mesh'])
RB15_ENT = BS.join(['fable5', 'rb15', 'rb15.ent'])
NS = ['ncm', 'rb15_liveries']                     # our namespace inside the archive
APP_PATH = BS.join(NS + ['rb15_liveries.app'])
MESH_PATCH_PATH = BS.join(NS + ['meshes', 'rb15_body_liveries.mesh'])
ENT_PATCH_PATH = BS.join(NS + ['rb15_ent_patch.ent'])


def run(*args, check=True):
    p = subprocess.run([CLI, *args], capture_output=True, text=True)
    if check and p.returncode != 0:
        print(p.stdout, p.stderr); raise SystemExit(f'WolvenKit CLI failed: {args[0]}')
    return p.stdout + p.stderr


def serialize(path):
    run('convert', 's', path)
    return json.load(open(path + '.json', encoding='utf-8'))


def deserialize(json_path):
    out = run('convert', 'd', json_path)
    if 'Success' not in out and 'Converted' not in out and 'Imported' not in out:
        print(out); raise SystemExit('deserialize failed: ' + json_path)


def png_size(path):
    import struct
    with open(path, 'rb') as f:
        f.read(16); w, h = struct.unpack('>II', f.read(8))
    return w, h


CACHE = os.path.join(OUT, 'xbm-cache')

def import_texture(png, xbm_out):
    """PNG -> xbm with TCM_QualityColor (BC7), sRGB, mipchain. Cached by PNG content hash so unchanged
    liveries are not re-encoded on every build (BC7 at 4096^2 takes ~60-90 s each)."""
    import hashlib
    os.makedirs(CACHE, exist_ok=True)
    digest = hashlib.sha256(open(png, 'rb').read()).hexdigest()[:20]
    cached = os.path.join(CACHE, f'{os.path.splitext(os.path.basename(xbm_out))[0]}_{digest}.xbm')
    if os.path.exists(cached):
        os.makedirs(os.path.dirname(xbm_out), exist_ok=True); shutil.copy2(cached, xbm_out)
        print(f'   texture {os.path.basename(xbm_out)}: cached ({digest})'); return
    _import_texture_uncached(png, xbm_out)
    shutil.copy2(xbm_out, cached)


def _import_texture_uncached(png, xbm_out):
    d = os.path.dirname(xbm_out); os.makedirs(d, exist_ok=True)
    base = os.path.splitext(os.path.basename(png))[0]
    tmp_png = os.path.join(d, base + '.png')
    if os.path.abspath(tmp_png) != os.path.abspath(png): shutil.copy(png, tmp_png)
    xbm = os.path.join(d, base + '.xbm')
    if os.path.exists(xbm): os.remove(xbm)
    run('import', tmp_png, '-o', d)                       # first pass: header with defaults
    j = serialize(xbm)
    s = j['Data']['RootChunk']['setup']
    s['compression'] = 'TCM_QualityColor'; s['isGamma'] = 1; s['group'] = 'TEXG_Generic_Color'; s['hasMipchain'] = 1
    json.dump(j, open(xbm + '.json', 'w', encoding='utf-8'))
    os.remove(xbm); deserialize(xbm + '.json'); os.remove(xbm + '.json')
    run('import', tmp_png, '-o', d, '--keep')             # second pass: encode with the corrected header
    j = serialize(xbm); os.remove(xbm + '.json')
    info = j['Data']['RootChunk']['renderTextureResource']['renderResourceBlobPC']['Data']['header']['textureInfo']
    print(f'   texture {base}: {j["Data"]["RootChunk"]["width"]}x{j["Data"]["RootChunk"]["height"]} '
          f'{s["compression"]} gamma={s["isGamma"]} mips={info["mipCount"]} bytes={info["textureDataSize"]}')
    os.remove(tmp_png)
    if xbm != xbm_out: shutil.move(xbm, xbm_out)


def max_id(obj, key, cur=0):
    """Largest integer value of `key` (HandleId / BufferId) anywhere in a WolvenKit JSON tree."""
    if isinstance(obj, dict):
        if key in obj:
            try: cur = max(cur, int(obj[key]))
            except (TypeError, ValueError): pass
        for v in obj.values(): cur = max_id(v, key, cur)
    elif isinstance(obj, list):
        for v in obj: cur = max_id(v, key, cur)
    return cur


def remap_ids(obj, keys, counter, mapping):
    """Renumber every key in `keys` inside a cloned subtree with ONE consistent old->new mapping.
    WolvenKit JSON defines a handle as {"HandleId": n, "Data": ...} and references it later as
    {"HandleRefId": n}; both must move together. counter = [last_used_id]."""
    if isinstance(obj, dict):
        for key in keys:
            if key in obj:
                old = str(obj[key])
                if old not in mapping:
                    counter[0] += 1; mapping[old] = str(counter[0])
                obj[key] = mapping[old]
        for v in obj.values(): remap_ids(v, keys, counter, mapping)
    elif isinstance(obj, list):
        for v in obj: remap_ids(v, keys, counter, mapping)


def clone_unique(node, doc_max_handle, doc_max_buffer):
    """Deep-copy a WolvenKit JSON node and give it handle/buffer ids that collide with nothing else."""
    c = copy.deepcopy(node)
    remap_ids(c, ('HandleId', 'HandleRefId'), doc_max_handle, {})
    remap_ids(c, ('BufferId', 'BufferRefId'), doc_max_buffer, {})
    return c


def build(liveries, with_fallback=False):
    if not os.path.exists(CLI): raise SystemExit('WolvenKit CLI not found: ' + CLI)
    if not os.path.exists(RB15_ARCHIVE): raise SystemExit('RB15 not installed: ' + RB15_ARCHIVE)
    tmp = tempfile.mkdtemp(prefix='rb15liv_')
    raw = os.path.join(tmp, 'raw')
    print('* extracting RB15 ent/app/body mesh for reference (read-only)')
    run('extract', RB15_ARCHIVE, '-o', raw, '-r', r'(rb15\.ent|rb15\.app|rb15_body\.mesh)$')
    ent = serialize(os.path.join(raw, 'fable5', 'rb15', 'rb15.ent'))
    app = serialize(os.path.join(raw, 'fable5', 'rb15', 'rb15.app'))
    mesh = serialize(os.path.join(raw, 'fable5', 'rb15', 'meshes', 'rb15_body.mesh'))

    pack_root = os.path.join(tmp, 'pack', 'ncm_rb15_liveries')
    ns_dir = os.path.join(pack_root, *NS)
    os.makedirs(os.path.join(ns_dir, 'meshes'), exist_ok=True); os.makedirs(os.path.join(ns_dir, 'textures'), exist_ok=True)

    # ---- textures ---------------------------------------------------------
    print('* textures')
    badge_source = {}   # name -> 'own' | 'default' | 'stock'
    default_badges = os.path.join(LIVERY_DIR, 'rb15_badges_default.png')
    for name, png in liveries.items():
        w, h = png_size(png)
        if w != h or w not in (1024, 2048, 4096): print(f'   WARNING {name}: {w}x{h} (expected square 4096)')
        import_texture(png, os.path.join(ns_dir, 'textures', f'rb15_ext_{name}.xbm'))
        own = os.path.join(LIVERY_DIR, f'rb15_badges_{name}.png')
        bpng = own if os.path.exists(own) else (default_badges if os.path.exists(default_badges) else None)
        if bpng:
            bw, bh = png_size(bpng)
            if (bw, bh) != (1024, 1024): print(f'   WARNING badges for {name}: {bw}x{bh} (stock sheet is 1024x1024)')
            import_texture(bpng, os.path.join(ns_dir, 'textures', f'rb15_badges_{name}.xbm'))
            badge_source[name] = 'own' if bpng == own else 'default'
        else:
            badge_source[name] = 'stock'
        print(f'   badges for {name}: {badge_source[name]}')

    # ---- mesh patch: appearances + materials only, no geometry ------------
    print('* mesh patch')
    r = mesh['Data']['RootChunk']
    default_app = [a for a in r['appearances'] if a['Data']['name']['$value'] == 'default'][0]
    lmb = r['localMaterialBuffer']
    def stock_material(mat_name):
        idx = [e['index'] for e in r['materialEntries'] if e['name']['$value'] == mat_name][0]
        return lmb['materials'][idx], lmb['rawData']['Data']['Files'][idx], lmb['rawDataHeaders'][idx]
    def add_material(slot, name, texture_rel):
        """Clone the RB15's local material `slot` (rb15_ext / rb15_badges) as `<slot>_<name>` pointing at our texture."""
        smat, sfile, shdr = stock_material(slot)
        m = copy.deepcopy(smat)
        for v in m['values']:
            if 'BaseColor' in v: v['BaseColor']['DepotPath']['$value'] = BS.join(NS + ['textures', texture_rel])
        mats.append(m)
        f = copy.deepcopy(sfile); f['RootChunk'] = copy.deepcopy(m); files.append(f)
        hdrs.append({'$type': 'meshLocalMaterialHeader', 'offset': 0, 'size': shdr['size']})
        entries.append({'$type': 'CMeshMaterialEntry', 'index': len(entries), 'isLocalInstance': 1,
                        'name': {'$type': 'CName', '$storage': 'string', '$value': f'{slot}_{name}'}})
    apps, mats, files, hdrs, entries = [], [], [], [], []
    hmax, bmax = [max(max_id(mesh, 'HandleId'), max_id(mesh, 'HandleRefId'))], [max_id(mesh, 'BufferId')]
    for i, name in enumerate(liveries):
        slots = {'rb15_ext': f'rb15_ext_{name}.xbm'}
        if badge_source[name] != 'stock': slots['rb15_badges'] = f'rb15_badges_{name}.xbm'
        a = clone_unique(default_app, hmax, bmax); a['Data']['name']['$value'] = name
        for cm in a['Data']['chunkMaterials']:
            if cm['$value'] in slots: cm['$value'] = f"{cm['$value']}_{name}"
        apps.append(a)
        for slot, tex in slots.items(): add_material(slot, name, tex)
    r['appearances'] = apps; lmb['materials'] = mats; lmb['rawData']['Data']['Files'] = files; lmb['rawDataHeaders'] = hdrs
    r['materialEntries'] = entries
    for k in ('localMaterialInstances', 'externalMaterials', 'preloadExternalMaterials', 'preloadLocalMaterialInstances',
              'parameters', 'boneNames', 'boneRigMatrices', 'boneVertexEpsilons', 'lodBoneMask', 'inplaceResources', 'floatTrackNames'):
        r[k] = []
    r['renderResourceBlob'] = None; r['geometryHash'] = 0; mesh['Data']['EmbeddedFiles'] = []
    mp = os.path.join(ns_dir, 'meshes', 'rb15_body_liveries.mesh')
    json.dump(mesh, open(mp + '.json', 'w', encoding='utf-8')); deserialize(mp + '.json'); os.remove(mp + '.json')

    # ---- .app: one appearance per livery, cloned from player_01 ------------
    print('* app')
    ar = app['Data']['RootChunk']
    p1 = [a for a in ar['appearances'] if a['Data']['name']['$value'] == 'player_01'][0]
    new_apps = []
    hmax, bmax = [max(max_id(app, 'HandleId'), max_id(app, 'HandleRefId'))], [max_id(app, 'BufferId')]
    for i, name in enumerate(liveries):
        a = clone_unique(p1, hmax, bmax); a['Data']['name']['$value'] = name
        for c in a['Data']['components']:
            if isinstance(c.get('mesh'), dict) and c['mesh']['DepotPath']['$value'] == BODY_MESH:
                c['meshAppearance']['$value'] = name
        new_apps.append(a)
    ar['appearances'] = new_apps; app['Data']['EmbeddedFiles'] = []
    ap = os.path.join(ns_dir, 'rb15_liveries.app')
    json.dump(app, open(ap + '.json', 'w', encoding='utf-8')); deserialize(ap + '.json'); os.remove(ap + '.json')

    # ---- .ent patch: appearance entries only --------------------------------
    print('* ent patch')
    er = ent['Data']['RootChunk']
    proto = er['appearances'][0]
    entries = []
    for name in liveries:
        e = copy.deepcopy(proto); e['name']['$value'] = name; e['appearanceName']['$value'] = name
        e['appearanceResource']['DepotPath']['$value'] = APP_PATH; entries.append(e)
    patch = copy.deepcopy(ent); pr = patch['Data']['RootChunk']
    pr['appearances'] = entries; pr['components'] = []; pr['resolvedDependencies'] = []; pr['compiledData'] = None
    patch['Data']['EmbeddedFiles'] = []
    ep = os.path.join(ns_dir, 'rb15_ent_patch.ent')
    json.dump(patch, open(ep + '.json', 'w', encoding='utf-8')); deserialize(ep + '.json'); os.remove(ep + '.json')

    if with_fallback:   # local diagnostics only - contains the author's compiled entity data, never ship
        fb = copy.deepcopy(ent); fb['Data']['RootChunk']['appearances'] += copy.deepcopy(entries)
        fp = os.path.join(ns_dir, 'rb15_ncm_fallback.ent')
        json.dump(fb, open(fp + '.json', 'w', encoding='utf-8')); deserialize(fp + '.json'); os.remove(fp + '.json')

    # ---- pack + payload -------------------------------------------------------
    print('* pack')
    payload = os.path.join(OUT, 'payload')
    if os.path.exists(payload): shutil.rmtree(payload)
    mod_dir = os.path.join(payload, 'archive', 'pc', 'mod'); os.makedirs(mod_dir); os.makedirs(os.path.join(payload, 'r6', 'tweaks'))
    run('pack', pack_root, '-o', mod_dir)
    with open(os.path.join(mod_dir, 'ncm_rb15_liveries.archive.xl'), 'w', newline='\n') as f:
        f.write('resource:\n  patch:\n')
        f.write(f'    {MESH_PATCH_PATH}:\n      - {BODY_MESH}\n')
        f.write(f'    {ENT_PATCH_PATH}:\n      - {RB15_ENT}\n')
    with open(os.path.join(payload, 'r6', 'tweaks', 'zzzz_ncm_rb15_liveries.yaml'), 'w', newline='\n') as f:
        f.write('# NCM RB15 livery add-on (generated by build_liveries.py). Requires RB15 F1 Car Mod Demo (Nexus 31543).\n')
        f.write('# Each record inherits everything from Vehicle.v_sport1_rb15_f1; only appearanceName differs.\n')
        for name in liveries:
            f.write(f'\nVehicle.v_sport1_rb15_f1_{name}:\n  $base: Vehicle.v_sport1_rb15_f1\n  appearanceName: {name}\n')
            if with_fallback:
                f.write(f'\nVehicle.v_sport1_rb15_f1_{name}_fb:\n  $base: Vehicle.v_sport1_rb15_f1\n  appearanceName: {name}\n'
                        f'  entityTemplatePath: {BS.join(NS + ["rb15_ncm_fallback.ent"])}\n')
    # livery manifest for NCM / humans
    json.dump({'liveries': list(liveries), 'appearance_names': {n: n for n in liveries}, 'badges': badge_source,
               'records': {n: f'Vehicle.v_sport1_rb15_f1_{n}' for n in liveries},
               'built': datetime.datetime.now().isoformat(timespec='seconds')},
              open(os.path.join(payload, 'r6', 'tweaks', 'ncm_rb15_liveries.manifest.json'), 'w'), indent=2)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M')
    zpath = os.path.join(OUT, f'NCM_RB15_Liveries_{stamp}.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for dp, _, fs in os.walk(payload):
            for fn in fs:
                full = os.path.join(dp, fn); z.write(full, os.path.join('NCM_RB15_Liveries', os.path.relpath(full, payload)))
    print('* archive contents:'); print(run('archiveinfo', os.path.join(mod_dir, 'ncm_rb15_liveries.archive'), '-l').strip())
    shutil.rmtree(tmp, ignore_errors=True)
    print(f'\nDONE  payload: {payload}\n      zip:     {zpath}')
    return payload, zpath


def deploy(payload):
    """Copy payload into the game folder (only our files; refuses if the game is running)."""
    import ctypes
    if any(p.lower().startswith('cyberpunk2077') for p in os.popen('tasklist').read().split()):
        raise SystemExit('Cyberpunk 2077 is running - close it first.')
    for dp, _, fs in os.walk(payload):
        for fn in fs:
            src = os.path.join(dp, fn); rel = os.path.relpath(src, payload); dst = os.path.join(GAME, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(src, dst); print('   ->', rel)
    # a livery removed from liveries/ must also disappear from the game: the archive/yaml are regenerated wholesale, so nothing else to do
    print('deployed.')


if __name__ == '__main__':
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser()
    ap.add_argument('--deploy', action='store_true'); ap.add_argument('--with-test', action='store_true')
    ap.add_argument('--with-fallback', action='store_true', help='include local-only fallback .ent (diagnostics, never ship)')
    args = ap.parse_args()
    os.makedirs(LIVERY_DIR, exist_ok=True); os.makedirs(OUT, exist_ok=True)
    liveries = {}
    for fn in sorted(os.listdir(LIVERY_DIR)):
        m = re.fullmatch(r'rb15_ext_([a-z0-9_]+)\.png', fn)
        if m: liveries[m.group(1)] = os.path.join(LIVERY_DIR, fn)
        elif re.fullmatch(r'rb15_badges_([a-z0-9_]+)\.png', fn): pass   # paired with a livery below
        elif fn.lower().endswith('.png'): print(f'skipping {fn}: name must be rb15_ext_<name>.png or rb15_badges_<name>.png')
    if args.with_test: liveries = {'ncm_test': TEST_PNG, **liveries}
    if not liveries: raise SystemExit(f'no liveries found in {LIVERY_DIR} (expected rb15_ext_<name>.png)')
    print('liveries:', ', '.join(liveries))
    for fn in os.listdir(LIVERY_DIR):
        m = re.fullmatch(r'rb15_badges_([a-z0-9_]+)\.png', fn)
        if m and m.group(1) != 'default' and m.group(1) not in liveries:
            print(f'WARNING: {fn} has no matching rb15_ext_{m.group(1)}.png and will be ignored')
    payload, _ = build(liveries, with_fallback=args.with_fallback)
    if args.deploy: deploy(payload)
