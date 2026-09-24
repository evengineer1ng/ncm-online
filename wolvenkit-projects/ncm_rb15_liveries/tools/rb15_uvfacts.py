import numpy as np, json
from PIL import Image, ImageDraw
exec(open('rb15_uv.py').read().split('# table')[0])
exec(open('rb15_template.py').read().split("tex=Image.open")[0].split("S=4096")[1])  # REGIONS + region()
S=4096
names=[r[0] for r in REGIONS]
# per-region: triangle count, mirrored fraction, uv bbox, mask
masks={}; stats={}
for c in chunks:
    if c['mat']!='rb15_ext' or (c['lod']&1)==0: continue
    uv=c['uv']; pos=c['pos']
    for tri in c['idx']:
        p=pos[tri]; u=uv[tri]; r=region(c['i'],*p.mean(axis=0))
        # 3D normal vs UV winding: mirrored if signs disagree with the majority convention
        n=np.cross(p[1]-p[0],p[2]-p[0]); nlen=np.linalg.norm(n)
        uvw=(u[1,0]-u[0,0])*(u[2,1]-u[0,1])-(u[2,0]-u[0,0])*(u[1,1]-u[0,1])
        st=stats.setdefault(r,{'tris':0,'flip':0,'umin':9,'umax':-9,'vmin':9,'vmax':-9,'area3d':0.0,'areauv':0.0})
        st['tris']+=1; st['flip']+= 1 if uvw<0 else 0
        st['umin']=min(st['umin'],u[:,0].min()); st['umax']=max(st['umax'],u[:,0].max())
        st['vmin']=min(st['vmin'],u[:,1].min()); st['vmax']=max(st['vmax'],u[:,1].max())
        st['area3d']+=nlen/2; st['areauv']+=abs(uvw)/2
        m=masks.setdefault(r,Image.new('1',(S,S),0)); ImageDraw.Draw(m).polygon([(float(x)*S,float(y)*S) for x,y in u],fill=1)
print(f"{'region':18} {'tris':>5} {'uv-flipped%':>11} {'texels/cm':>9}  pixel bbox (x0,y0)-(x1,y1)")
for r in sorted(stats):
    st=stats[r]; dens=(st['areauv']*S*S)**0.5/((st['area3d']*1e4)**0.5) if st['area3d']>0 else 0
    print(f"{names[r]:18} {st['tris']:>5} {100*st['flip']/st['tris']:>10.0f}% {dens:>9.2f}  ({int(st['umin']*S)},{int(st['vmin']*S)})-({int(st['umax']*S)},{int(st['vmax']*S)})")
print("\nUV overlaps between regions (shared texels -> cannot be painted independently):")
arr={r:np.array(m,dtype=bool) for r,m in masks.items()}
keys=sorted(arr)
for i,a in enumerate(keys):
    for b in keys[i+1:]:
        ov=np.logical_and(arr[a],arr[b]).sum()
        if ov>2000: print(f"  {names[a]} <-> {names[b]}: {ov} px ({100*ov/min(arr[a].sum(),arr[b].sum()):.0f}% of smaller)")
# left/right symmetry check: mirror sidepod L uv mask vs R
l,rr=arr[names.index('SIDEPOD L')],arr[names.index('SIDEPOD R')]
print(f"\nSidepod L/R share same texels: {np.logical_and(l,rr).sum()} px  (L={l.sum()}, R={rr.sum()})")
# non-ext geometry that sits on the exterior (badge/misc plates): 3D extents
print("\nNon-livery chunks on the exterior (own textures, unaffected by rb15_ext):")
for c in chunks:
    if c['mat'] in ('rb15_badges','rb15_misc','rb15_cab') and c['nv']>150:
        p=c['pos']; print(f"  chunk {c['i']:2d} {c['mat']:12} tris={c['ni']//3:5d}  x[{p[:,0].min():+.2f},{p[:,0].max():+.2f}] y[{p[:,1].min():+.2f},{p[:,1].max():+.2f}] z[{p[:,2].min():+.2f},{p[:,2].max():+.2f}]")
