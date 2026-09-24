import json,copy,sys
BS=chr(92)
src='rb15/raw/fable5/rb15/meshes/rb15_body.mesh.json'
m=json.load(open(src,encoding='utf-8'))
r=m['Data']['RootChunk']
NEWMAT='rb15_ext_ncm_test'; TEX=BS.join(['ncm','rb15_liveries','textures','rb15_ext_ncm_test.xbm'])
app=[a for a in r['appearances'] if a['Data']['name']['$value']=='default'][0]
app=copy.deepcopy(app); app['HandleId']='1'
app['Data']['name']['$value']='ncm_test'
for cm in app['Data']['chunkMaterials']:
    if cm['$value']=='rb15_ext': cm['$value']=NEWMAT
r['appearances']=[app]
lmb=r['localMaterialBuffer']
mat=copy.deepcopy(lmb['materials'][3])
for v in mat['values']:
    if 'BaseColor' in v: v['BaseColor']['DepotPath']['$value']=TEX
lmb['materials']=[mat]
f=copy.deepcopy(lmb['rawData']['Data']['Files'][3]); f['RootChunk']=copy.deepcopy(mat)
lmb['rawData']['Data']['Files']=[f]
lmb['rawDataHeaders']=[{'$type':'meshLocalMaterialHeader','offset':0,'size':lmb['rawDataHeaders'][3]['size']}]
r['materialEntries']=[{'$type':'CMeshMaterialEntry','index':0,'isLocalInstance':1,'name':{'$type':'CName','$storage':'string','$value':NEWMAT}}]
r['localMaterialInstances']=[]; r['externalMaterials']=[]; r['preloadExternalMaterials']=[]; r['preloadLocalMaterialInstances']=[]
r['renderResourceBlob']=None; r['parameters']=[]
r['boneNames']=[]; r['boneRigMatrices']=[]; r['boneVertexEpsilons']=[]; r['lodBoneMask']=[]
r['inplaceResources']=[]; r['floatTrackNames']=[]; r['geometryHash']=0
m['Data']['EmbeddedFiles']=[]
out='build/src/ncm/rb15_liveries/meshes/rb15_body_liveries.mesh.json'
json.dump(m,open(out,'w',encoding='utf-8'))
print("TEX repr:",repr(TEX))
