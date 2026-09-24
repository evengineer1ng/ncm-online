import json, base64, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
exec(open('rb15_uv.py').read().split('# table')[0])   # reuse chunk decoding

S=4096
REGIONS=[ # name, color, predicate on centroid (x,y,z) and chunk index
 ('FRONT WING',      (0,200,255),   lambda c,x,y,z: c==31),
 ('REAR WING',       (255,220,0),   lambda c,x,y,z: c==18),
 ('MIRRORS',         (255,255,255), lambda c,x,y,z: c in (20,26)),
 ('NOSE',            (255,90,0),    lambda c,x,y,z: c==13 and y>1.75),
 ('FRONT SUSP/DUCTS',(255,160,120), lambda c,x,y,z: c in (15,17) or (c==13 and 1.35<y<=1.75)),
 ('FLOOR/UNDERTRAY', (120,120,120), lambda c,x,y,z: c==13 and z<-0.52),
 ('SIDEPOD L',       (0,255,90),    lambda c,x,y,z: c==13 and x<-0.30 and -1.2<y<=1.35),
 ('SIDEPOD R',       (0,170,60),    lambda c,x,y,z: c==13 and x> 0.30 and -1.2<y<=1.35),
 ('COCKPIT/HALO',    (255,0,255),   lambda c,x,y,z: c==13 and abs(x)<=0.30 and 0.2<y<=1.35 and z>-0.2),
 ('ENGINE COVER',    (255,60,60),   lambda c,x,y,z: c==13 and abs(x)<=0.30 and -1.2<y<=0.2 and z>-0.2),
 ('CHASSIS SIDES',   (200,120,255), lambda c,x,y,z: c==13 and -1.2<y<=1.35),
 ('REAR/DIFFUSER',   (255,255,150), lambda c,x,y,z: c==13 and y<=-1.2),
 ('OTHER EXT',       (150,220,220), lambda c,x,y,z: True),
]
def region(c,x,y,z):
    for i,(n,col,p) in enumerate(REGIONS):
        if p(c,x,y,z): return i
    return len(REGIONS)-1

tex=Image.open('rb15/uncooked/fable5/rb15/textures/2019_f1_red_bull_rb15_ext_23.png').convert('RGBA')
base=Image.new('RGBA',(S,S),(25,25,25,255)); base.alpha_composite(tex)
base=Image.blend(base, Image.new('RGBA',(S,S),(0,0,0,255)), 0.45)   # darken art so the map reads
fill=Image.new('RGBA',(S,S),(0,0,0,0)); df=ImageDraw.Draw(fill)
counts=np.zeros(len(REGIONS)); cent=np.zeros((len(REGIONS),2))
for c in chunks:
    if c['mat']!='rb15_ext' or (c['lod']&1)==0: continue
    uv=c['uv']; pos=c['pos']
    for tri in c['idx']:
        p=pos[tri].mean(axis=0); r=region(c['i'],*p)
        col=REGIONS[r][1]+(110,)
        pts=[(float(uv[t,0])*S,float(uv[t,1])*S) for t in tri]
        df.polygon(pts,fill=col,outline=REGIONS[r][1]+(200,))
        u=uv[tri].mean(axis=0); counts[r]+=1; cent[r]+=u
base.alpha_composite(fill)
d=ImageDraw.Draw(base)
font=ImageFont.truetype("arialbd.ttf",64); small=ImageFont.truetype("arial.ttf",44)
# legend
y0=60
for i,(n,col,_) in enumerate(REGIONS):
    if counts[i]==0: continue
    d.rectangle([40,y0,120,y0+60],fill=col+(255,),outline=(0,0,0,255),width=3)
    d.text((140,y0-4),f"{n}  ({int(counts[i])} tris)",fill=(255,255,255,255),font=font,stroke_width=3,stroke_fill=(0,0,0,255))
    y0+=80
d.text((40,S-120),"RB15 rb15_ext UV map  |  4096x4096  |  V axis: top of image = v0  |  generated from rb15_body.mesh (LOD0)",fill=(255,255,255,255),font=small,stroke_width=2,stroke_fill=(0,0,0,255))
base.convert('RGB').save('rb15/rb15_ext_uv_regions_4096.png')
base.convert('RGB').resize((2048,2048)).save('rb15/rb15_ext_uv_regions_2048.jpg',quality=88)
print("done")
