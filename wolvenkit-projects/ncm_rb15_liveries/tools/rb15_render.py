import numpy as np, sys
from PIL import Image
exec(open('rb15_uv.py').read().split('# table')[0])
TEX=sys.argv[1] if len(sys.argv)>1 else 'rb15/rb15_ext_probe_grid.png'
OUT=sys.argv[2] if len(sys.argv)>2 else 'rb15/render_probe'
BTEX=sys.argv[3] if len(sys.argv)>3 else None
tex=np.array(Image.open(TEX).convert('RGB')); TS=tex.shape[0]
btex=np.array(Image.open(BTEX).convert('RGB')) if BTEX else None; BTS=btex.shape[0] if BTEX else 1
# gather all rb15_ext + other chunks (others drawn grey) LOD0
V=[];U=[];F=[];M=[]
for c in chunks:
    if (c['lod']&1)==0: continue
    base=len(V)
    V.extend(c['pos']); U.extend(c['uv']); F.extend([(t[0]+base,t[1]+base,t[2]+base) for t in c['idx']]); M.extend([1 if c['mat']=='rb15_ext' else (2 if c['mat']=='rb15_badges' else 0)]*len(c['idx']))
V=np.array(V,dtype=np.float64); U=np.array(U); F=np.array(F); M=np.array(M)
# views: name -> (right axis, up axis, toward-camera axis)  (orthographic)
X,Y,Z=np.eye(3)
# +X is the car's RIGHT (verified against in-game screenshots 2026-09-18)
views={'right_side':(Y,Z,X), 'left_side':(-Y,Z,-X), 'top':(X,Y,Z), 'front':(-X,Z,Y), 'rear':(X,Z,-Y)}
# note: which of ±X is "left" is settled below by comparing with the in-game screenshots
W=2400
def render(name,r,u,n):
    P=np.stack([V@r,V@u,V@n],axis=1)
    mn=P[:,:2].min(axis=0); mx=P[:,:2].max(axis=0); span=(mx-mn); scale=(W-40)/span.max()
    H=int(span[1]*scale)+40
    px=(P[:,0]-mn[0])*scale+20; py=(H-20)-(P[:,1]-mn[1])*scale
    depth=P[:,2]
    img=np.full((H,W,3),40,dtype=np.uint8); zb=np.full((H,W),-1e9)
    for fi,(a,b,c) in enumerate(F):
        xs=np.array([px[a],px[b],px[c]]); ys=np.array([py[a],py[b],py[c]]); zs=np.array([depth[a],depth[b],depth[c]])
        x0,x1=int(max(0,np.floor(xs.min()))),int(min(W-1,np.ceil(xs.max()))); y0,y1=int(max(0,np.floor(ys.min()))),int(min(H-1,np.ceil(ys.max())))
        if x1<x0 or y1<y0: continue
        gx,gy=np.meshgrid(np.arange(x0,x1+1),np.arange(y0,y1+1))
        d=(ys[1]-ys[2])*(xs[0]-xs[2])+(xs[2]-xs[1])*(ys[0]-ys[2])
        if abs(d)<1e-9: continue
        l1=((ys[1]-ys[2])*(gx-xs[2])+(xs[2]-xs[1])*(gy-ys[2]))/d; l2=((ys[2]-ys[0])*(gx-xs[2])+(xs[0]-xs[2])*(gy-ys[2]))/d; l3=1-l1-l2
        inside=(l1>=-1e-4)&(l2>=-1e-4)&(l3>=-1e-4)
        if not inside.any(): continue
        z=l1*zs[0]+l2*zs[1]+l3*zs[2]
        sel=inside&(z>zb[y0:y1+1,x0:x1+1])
        if not sel.any(): continue
        zb[y0:y1+1,x0:x1+1][sel]=z[sel]
        if M[fi]==1 or (M[fi]==2 and btex is not None):
            T=tex if M[fi]==1 else btex; TSZ=TS if M[fi]==1 else BTS
            uu=(l1*U[a,0]+l2*U[b,0]+l3*U[c,0]); vv=(l1*U[a,1]+l2*U[b,1]+l3*U[c,1])
            ti=np.clip((uu*TSZ).astype(int),0,TSZ-1); tj=np.clip((vv*TSZ).astype(int),0,TSZ-1)
            col=T[tj,ti]
            img[y0:y1+1,x0:x1+1][sel]=col[sel]
        else:
            img[y0:y1+1,x0:x1+1][sel]=(90,90,95)
    Image.fromarray(img).save(f'{OUT}_{name}.png'); print("rendered",name)
for k,(r,u,n) in views.items(): render(k,r,u,n)
