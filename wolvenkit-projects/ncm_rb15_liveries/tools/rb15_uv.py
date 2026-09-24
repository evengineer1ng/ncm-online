import json, base64, struct, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

R='rb15/raw/fable5/rb15'
m=json.load(open(os.path.join(R,'meshes/rb15_body.mesh.json'),encoding='utf-8'))
root=m['Data']['RootChunk']
blob=root['renderResourceBlob']['Data']; hdr=blob['header']
buf=base64.b64decode(blob['renderBuffer']['Bytes'])
qs=hdr['quantizationScale']; qo=hdr['quantizationOffset']
ibo=hdr['indexBufferOffset']
app=[a.get('Data',a) for a in root['appearances'] if a.get('Data',a)['name']['$value']=='default'][0]
chunkMats=[c['$value'] for c in app['chunkMaterials']]

def half(u16):
    return np.frombuffer(np.array(u16,dtype=np.uint16).tobytes(),dtype=np.float16).astype(np.float32)

chunks=[]
for ci,c in enumerate(hdr['renderChunkInfos']):
    nv=c['numVertices']; ni=c['numIndices']
    offs=c['chunkVertices']['byteOffsets']['Elements']
    elems=c['chunkVertices']['vertexLayout']['elements']['Elements']
    # stream 0: positions Short4N (8 bytes)
    p=np.frombuffer(buf,dtype='<i2',count=nv*4,offset=offs[0]).reshape(nv,4).astype(np.float32)/32767.0
    pos=p[:,:3]*np.array([qs['X'],qs['Y'],qs['Z']])+np.array([qo['X'],qo['Y'],qo['Z']])
    # stream 1: uv0 half2
    uv=np.frombuffer(buf,dtype='<u2',count=nv*2,offset=offs[1]).reshape(nv,2)
    uv=half(uv.flatten()).reshape(nv,2)
    uv=uv.copy(); uv[:,1]=1.0-uv[:,1]   # game samples V flipped relative to the WolvenKit mesh dump (verified with in-game probe 2026-09-18)
    # indices (ushort) at indexBufferOffset + teOffset
    io=ibo+c['chunkIndices']['teOffset']
    idx=np.frombuffer(buf,dtype='<u2',count=ni,offset=io).reshape(-1,3)
    lod=c['lodMask']
    chunks.append(dict(i=ci,mat=chunkMats[ci] if ci<len(chunkMats) else '?',nv=nv,ni=ni,lod=lod,pos=pos,uv=uv,idx=idx))

# table
print(f"{'chunk':>5} {'material':12} {'lod':>3} {'verts':>6} {'tris':>6}  bbox x[min,max] y[min,max] z[min,max]   uv u[min,max] v[min,max]")
for c in chunks:
    p=c['pos']; u=c['uv']
    print(f"{c['i']:>5} {c['mat']:12} {c['lod']:>3} {c['nv']:>6} {c['ni']//3:>6}  x[{p[:,0].min():+.2f},{p[:,0].max():+.2f}] y[{p[:,1].min():+.2f},{p[:,1].max():+.2f}] z[{p[:,2].min():+.2f},{p[:,2].max():+.2f}]   u[{u[:,0].min():.2f},{u[:,0].max():.2f}] v[{u[:,1].min():.2f},{u[:,1].max():.2f}]")

# UV wireframe over the atlas for rb15_ext chunks (LOD0 only)
S=2048
tex=Image.open('rb15/uncooked/fable5/rb15/textures/2019_f1_red_bull_rb15_ext_23.png').convert('RGBA').resize((S,S))
bg=Image.new('RGBA',(S,S),(30,30,30,255)); bg.alpha_composite(tex)
over=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(over)
colors=[(255,0,255),(0,255,0),(0,200,255),(255,255,0),(255,128,0),(255,255,255),(0,255,180),(255,80,80)]
labels=[]
k=0
for c in chunks:
    if c['mat']!='rb15_ext' or (c['lod']&1)==0: continue
    col=colors[k%len(colors)]+(200,); k+=1
    uv=c['uv']; idx=c['idx']
    for tri in idx:
        pts=[(float(uv[t,0])*S, float(uv[t,1])*S) for t in tri]
        d.line([pts[0],pts[1],pts[2],pts[0]],fill=col,width=1)
    cu=float(uv[:,0].mean())*S; cv=float(uv[:,1].mean())*S
    labels.append((cu,cv,str(c['i']),col))
bg.alpha_composite(over)
d2=ImageDraw.Draw(bg)
try: font=ImageFont.truetype("arial.ttf",40)
except: font=ImageFont.load_default()
for cu,cv,t,col in labels:
    d2.rectangle([cu-30,cv-24,cu+30,cv+24],fill=(0,0,0,200)); d2.text((cu-22,cv-24),t,fill=col,font=font)
bg.convert('RGB').save('rb15/rb15_ext_uv_wireframe.png')
# also a pure wireframe template on white (for GIMP/Photoshop layer)
tpl=Image.new('RGBA',(4096,4096),(255,255,255,0)); dt=ImageDraw.Draw(tpl)
for c in chunks:
    if c['mat']!='rb15_ext' or (c['lod']&1)==0: continue
    uv=c['uv']
    for tri in c['idx']:
        pts=[(float(uv[t,0])*4096, float(uv[t,1])*4096) for t in tri]
        dt.line([pts[0],pts[1],pts[2],pts[0]],fill=(0,0,0,255),width=1)
tpl.save('rb15/rb15_ext_uv_template_4096.png')
print("wrote rb15/rb15_ext_uv_wireframe.png and rb15/rb15_ext_uv_template_4096.png")
