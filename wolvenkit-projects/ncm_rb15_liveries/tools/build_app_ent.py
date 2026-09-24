import json,copy
BS=chr(92)
APP_PATH=BS.join(['ncm','rb15_liveries','rb15_liveries.app'])
BODY=BS.join(['fable5','rb15','meshes','rb15_body.mesh'])

# ---------- .app : one appearance cloned from player_01 ----------
app=json.load(open('rb15/raw/fable5/rb15/rb15.app.json',encoding='utf-8'))
r=app['Data']['RootChunk']
p1=[a for a in r['appearances'] if a['Data']['name']['$value']=='player_01'][0]
na=copy.deepcopy(p1); na['HandleId']='1'
na['Data']['name']['$value']='ncm_test'
changed=[]
for c in na['Data']['components']:
    mesh=c.get('mesh',{}).get('DepotPath',{}).get('$value') if isinstance(c.get('mesh'),dict) else None
    if mesh==BODY:
        c['meshAppearance']['$value']='ncm_test'; changed.append((c['$type'],c['name']['$value']))
r['appearances']=[na]
app['Data']['EmbeddedFiles']=[]
json.dump(app,open('build/src/ncm/rb15_liveries/rb15_liveries.app.json','w',encoding='utf-8'))
print("app: components",len(na['Data']['components']),"retargeted:",changed)

# ---------- .ent patch : only an appearance entry ----------
ent=json.load(open('rb15/raw/fable5/rb15/rb15.ent.json',encoding='utf-8'))
er=ent['Data']['RootChunk']
entry=copy.deepcopy(er['appearances'][0])
entry['name']['$value']='ncm_test'; entry['appearanceName']['$value']='ncm_test'
entry['appearanceResource']['DepotPath']['$value']=APP_PATH
patch=copy.deepcopy(ent); pr=patch['Data']['RootChunk']
pr['appearances']=[entry]
pr['components']=[]; pr['resolvedDependencies']=[]; pr['compiledData']=None if 'compiledData' in pr else pr.get('compiledData')
for k in ('bindings','inplaceResources','localBlackboard','includeInstanceData','visualTagsSchema','backendData','compiledData','compiledDataBuffer','defaultAppearance'):
    pass
patch['Data']['EmbeddedFiles']=[]
json.dump(patch,open('build/src/ncm/rb15_liveries/rb15_ent_patch.ent.json','w',encoding='utf-8'))
print("ent patch keys:", [k for k in pr.keys()])
print("ent patch appearances:", [(a['name']['$value'],a['appearanceName']['$value'],a['appearanceResource']['DepotPath']['$value'].replace(BS,'/')) for a in pr['appearances']])

# ---------- fallback: standalone .ent (full copy + our appearance added) ----------
fb=copy.deepcopy(ent); fr=fb['Data']['RootChunk']
fr['appearances']=fr['appearances']+[copy.deepcopy(entry)]
json.dump(fb,open('build/fallback/ncm/rb15_liveries/rb15_ncm_fallback.ent.json','w',encoding='utf-8'))
print("fallback ent appearances:", [a['name']['$value'] for a in fr['appearances']])
