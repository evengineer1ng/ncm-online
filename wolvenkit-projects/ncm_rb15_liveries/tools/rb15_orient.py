import numpy as np, collections, math
from PIL import Image, ImageDraw, ImageFont
exec(open('rb15_uv.py').read().split('# table')[0])
S=4096
# ---- UV islands via union-find on index buffer (per chunk) ----
islands=[]   # list of dict(tris=[(chunk, tri_idx)], ...)
for c in chunks:
    if c['mat']!='rb15_ext' or (c['lod']&1)==0: continue
    nv=c['nv']; parent=list(range(nv))
    def find(a):
        while parent[a]!=a: parent[a]=parent[parent[a]]; a=parent[a]
        return a
    for t in c['idx']:
        a,b,d=map(int,t); ra,rb,rd=find(a),find(b),find(d); parent[rb]=ra; parent[find(rd)]=ra
    groups=collections.defaultdict(list)
    for ti,t in enumerate(c['idx']): groups[find(int(t[0]))].append(ti)
    for g,tis in groups.items(): islands.append(dict(chunk=c, tris=tis))
print("UV islands:", len(islands))

def tri_frame(p,u):
    """returns dU, dV (3D dirs for +u,+v), normal from winding, uv area, 3D area"""
    e1,e2=p[1]-p[0],p[2]-p[0]; du1,dv1=u[1]-u[0]; du2,dv2=u[2]-u[0]
    det=du1*dv2-du2*dv1
    if abs(det)<1e-12: return None
    r=1.0/det
    dU=(e1*dv2-e2*dv1)*r; dV=(e2*du1-e1*du2)*r
    n=np.cross(e1,e2); a3=np.linalg.norm(n)/2
    if a3<1e-9: return None
    return dU,dV,n/(2*a3),abs(det)/2,a3

results=[]
for isl in islands:
    c=isl['chunk']; pos=c['pos']; uv=c['uv']
    sumU=np.zeros(3); sumV=np.zeros(3); sumN=np.zeros(3); auv=0; a3=0; cen=np.zeros(2); cen3=np.zeros(3); w=0
    for ti in isl['tris']:
        t=c['idx'][ti]; f=tri_frame(pos[t],uv[t])
        if f is None: continue
        dU,dV,n,auvt,a3t=f
        sumU+=dU*a3t; sumV+=dV*a3t; sumN+=n*a3t; auv+=auvt; a3+=a3t
        cen+=uv[t].mean(axis=0)*auvt; cen3+=pos[t].mean(axis=0)*a3t; w+=auvt
    if a3<1e-6 or w<1e-9: continue
    dU=sumU/np.linalg.norm(sumU); dV=sumV/np.linalg.norm(sumV); n=sumN/np.linalg.norm(sumN)
    cen/=w; cen3/=a3
    # viewer frame looking at the panel from outside (along -n)
    if abs(n[2])<0.75: up_ref=np.array([0,0,1.0])          # side-ish panel: screen up = world up
    else: up_ref=np.array([0,1.0,0])                        # top/bottom panel: screen up = nose direction
    su=up_ref-np.dot(up_ref,n)*n; su/=np.linalg.norm(su); sr=np.cross(su,n)
    # atlas axes: x=+u (right), y=-v (up).  Where do they land on screen?
    ax=np.array([np.dot(dU,sr),np.dot(dU,su)]); ay=np.array([np.dot(-dV,sr),np.dot(-dV,su)])
    A=np.array([[ax[0],ay[0]],[ax[1],ay[1]]])                # atlas(x,y) -> screen(right,up)
    mirrored=np.linalg.det(A)<0
    theta=math.degrees(math.atan2(ay[0],ay[1]))              # atlas-up appears rotated by theta (CW positive on screen) 
    results.append(dict(chunk=c['i'],ntris=len(isl['tris']),auv=auv*S*S,cen=cen,cen3=cen3,n=n,A=A,mirrored=mirrored,theta=theta,top=abs(n[2])>=0.75))
results.sort(key=lambda r:-r['auv'])
print(f"{'#':>3} {'chunk':>5} {'tris':>5} {'px area':>9} {'atlas centre':>14} {'3D centre (x,y,z)':>22} {'normal':>18} {'mirror':>6} {'rot':>6} face")
for i,r in enumerate(results[:40]):
    print(f"{i:>3} {r['chunk']:>5} {r['ntris']:>5} {int(r['auv']):>9} ({int(r['cen'][0]*S):>4},{int(r['cen'][1]*S):>4})   ({r['cen3'][0]:+.2f},{r['cen3'][1]:+.2f},{r['cen3'][2]:+.2f})   ({r['n'][0]:+.2f},{r['n'][1]:+.2f},{r['n'][2]:+.2f}) {'YES' if r['mirrored'] else 'no':>6} {r['theta']:>6.0f} {'top/bottom' if r['top'] else 'side'}")
import pickle; pickle.dump(results,open('rb15/orient_results.pkl','wb'))
