import sys, json, urllib.request
def call(tool, args, build=None):
    url='https://mcp.open2077.net/mcp' + (f'?build={build}' if build else '')
    body=json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":tool,"arguments":args}}).encode()
    req=urllib.request.Request(url,data=body,headers={'Content-Type':'application/json','Accept':'application/json, text/event-stream','User-Agent':'Mozilla/5.0 (ncm-research)'})
    txt=urllib.request.urlopen(req,timeout=60).read().decode('utf-8','replace')
    out=[]
    for line in txt.split('\n'):
        if line.startswith('data: '):
            try:
                p=json.loads(line[6:])
            except Exception:
                out.append('RAW '+line); continue
            if 'result' in p:
                out += [c.get('text','') for c in p['result'].get('content',[]) if c.get('type')=='text']
            elif 'error' in p:
                out.append('ERR '+json.dumps(p['error']))
    return '\n'.join(out)
if __name__=='__main__':
    tool=sys.argv[1]; args=json.loads(sys.argv[2]) if len(sys.argv)>2 else {}
    build=sys.argv[3] if len(sys.argv)>3 else None
    print(call(tool,args,build))
