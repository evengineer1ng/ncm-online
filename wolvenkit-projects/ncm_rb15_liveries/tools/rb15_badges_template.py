import numpy as np, collections
from PIL import Image, ImageDraw, ImageFont
exec(open('rb15_uv.py').read().split('# table')[0])
S=1024
def zone(ci,x,y,z):
    if ci==24: return 'FRONT WING PLATES'
    if ci==16: return 'REAR WING PLATES'
    if y>1.9: return 'NOSE PLATES'
    if y<-1.2: return 'REAR BODY PLATES'
    if abs(x)>0.30: return 'SIDEPOD L PLATES' if x<0 else 'SIDEPOD R PLATES'
    if z>-0.05: return 'ENGINE COVER PLATES'
    return 'CHASSIS MID PLATES'
COL={'FRONT WING PLATES':(0,200,255),'REAR WING PLATES':(255,220,0),'NOSE PLATES':(255,90,0),'REAR BODY PLATES':(255,255,150),
     'SIDEPOD L PLATES':(0,255,90),'SIDEPOD R PLATES':(0,170,60),'ENGINE COVER PLATES':(255,60,60),'CHASSIS MID PLATES':(200,120,255)}
def render(bg_img, out_png, out_jpg, legend=True, wire_only=False):
    base=bg_img.convert('RGBA'); ov=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(ov); cnt=collections.Counter()
    for c in chunks:
        if c['mat']!='rb15_badges' or (c['lod']&1)==0: continue
        uv=c['uv']; pos=c['pos']
        for tri in c['idx']:
            z=zone(c['i'],*pos[tri].mean(axis=0)); cnt[z]+=1
            pts=[(float(x)*S,float(y)*S) for x,y in uv[tri]]
            if wire_only: d.line(pts+[pts[0]],fill=(0,0,0,255),width=1)
            else: d.polygon(pts,fill=COL[z]+(120,),outline=COL[z]+(220,))
    base.alpha_composite(ov)
    if legend:
        dd=ImageDraw.Draw(base); f=ImageFont.truetype("arialbd.ttf",26); y=12
        for z,n in cnt.most_common():
            dd.rectangle([10,y,34,y+22],fill=COL[z]+(255,)); dd.text((42,y-3),f"{z} ({n} tris)",fill=(255,255,255,255),font=f,stroke_width=2,stroke_fill=(0,0,0,255)); y+=30
        dd.text((10,S-30),"RB15 rb15_badges UV map | 1024x1024 | sponsor plate geometry",fill=(255,255,255,255),font=ImageFont.truetype("arial.ttf",20),stroke_width=2,stroke_fill=(0,0,0,255))
    base.convert('RGB').save(out_png)
    if out_jpg: base.convert('RGB').save(out_jpg,quality=90)
    return cnt
# 1) transparent wireframe template
tpl=Image.new('RGBA',(S,S),(255,255,255,0)); d=ImageDraw.Draw(tpl)
for c in chunks:
    if c['mat']!='rb15_badges' or (c['lod']&1)==0: continue
    for tri in c['idx']:
        pts=[(float(x)*S,float(y)*S) for x,y in c['uv'][tri]]; d.line(pts+[pts[0]],fill=(0,0,0,255),width=1)
tpl.save('rb15/rb15_badges_uv_template_1024.png')
# 2) regions on neutral bg (public) and over stock art (local)
cnt=render(Image.new('RGBA',(S,S),(28,28,32,255)),'rb15/pub_rb15_badges_uv_regions_1024.png',None)
stock=Image.open('rb15/uncooked/fable5/rb15/textures/2019_f1_red_bull_rb15_badges.png').convert('RGBA')
bg=Image.new('RGBA',(S,S),(25,25,25,255)); bg.alpha_composite(stock); bg=Image.blend(bg,Image.new('RGBA',(S,S),(0,0,0,255)),0.35)
render(bg,'rb15/rb15_badges_uv_regions_1024.png',None)
# 3) stock art + wireframe (local only)
bg2=Image.new('RGBA',(S,S),(25,25,25,255)); bg2.alpha_composite(stock); render(bg2,'rb15/rb15_badges_uv_wireframe_1024.png',None,legend=False,wire_only=True)
print(dict(cnt))
