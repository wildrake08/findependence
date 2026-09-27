# Walks a page with the Tab key via the DevTools protocol at a given width.
# usage: tabwalk.py <file.html> <width>   (prints focusable count, how many Tab reached, DOM order, and focus visibility)
# UX-003 C1: also the focus outline's contrast against the nearest opaque background behind the control
# (WCAG 1.4.11 asks 3:1); any stop below 3:1 is listed under low_contrast_focus.
import sys, json, socket, base64, os, struct, subprocess, time, urllib.request, collections
path, width = sys.argv[1], int(sys.argv[2])
port = 9333
p = subprocess.Popen(["/usr/bin/chromium","--headless=new","--no-sandbox","--disable-gpu",f"--remote-debugging-port={port}","--window-size=1200,900","about:blank"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    for _ in range(50):
        try:
            tabs=json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json")); break
        except Exception: time.sleep(0.2)
    ws_url=[t for t in tabs if t["type"]=="page"][0]["webSocketDebuggerUrl"]
    hostport, rest = ws_url[5:].split("/",1)
    s=socket.create_connection(hostport.split(":")[0:1]+[] and None or ("127.0.0.1",port))
    key=base64.b64encode(os.urandom(16)).decode()
    s.send(f"GET /{rest} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
    buf=b""
    while b"\r\n\r\n" not in buf: buf+=s.recv(4096)
    buf=buf.split(b"\r\n\r\n",1)[1]
    def send(obj):
        data=json.dumps(obj).encode(); mask=os.urandom(4)
        hdr=bytes([0x81]); n=len(data)
        hdr+= bytes([0x80|n]) if n<126 else (bytes([0x80|126])+struct.pack(">H",n) if n<65536 else bytes([0x80|127])+struct.pack(">Q",n))
        s.send(hdr+mask+bytes(b^mask[i%4] for i,b in enumerate(data)))
    def recv_frame():
        global buf
        def need(k):
            global buf
            while len(buf)<k: buf+=s.recv(65536)
        need(2); b1=buf[1]&0x7f; off=2
        if b1==126: need(4); n=struct.unpack(">H",buf[2:4])[0]; off=4
        elif b1==127: need(10); n=struct.unpack(">Q",buf[2:10])[0]; off=10
        else: n=b1
        need(off+n); payload=buf[off:off+n]; fin=buf[0]&0x80; buf=buf[off+n:]
        return payload, fin
    def recv_msg():
        data=b""
        while True:
            pl,fin=recv_frame(); data+=pl
            if fin: return json.loads(data)
    i=[0]
    def call(method, params={}):
        i[0]+=1; send({"id":i[0],"method":method,"params":params})
        while True:
            m=recv_msg()
            if m.get("id")==i[0]: return m.get("result",m)
    call("Emulation.setDeviceMetricsOverride",{"width":width,"height":900,"deviceScaleFactor":1,"mobile":width<500})
    call("Page.enable"); call("Page.navigate",{"url":"file://"+os.path.abspath(path)}); time.sleep(1.5)
    def ev(expr): return call("Runtime.evaluate",{"expression":expr,"returnByValue":True})["result"].get("value")
    focusable=ev("""[...document.querySelectorAll('a[href],button,input:not([type=hidden]),select,textarea,summary,[tabindex]')].filter(e=>!e.disabled&&e.tabIndex>=0&&e.getClientRects().length).length""")
    positive=ev("[...document.querySelectorAll('[tabindex]')].filter(e=>e.tabIndex>0).length")
    seen=[]; invisible=[]; low=[]; ratios=[]
    for k in range(focusable+5):
        call("Input.dispatchKeyEvent",{"type":"keyDown","key":"Tab","code":"Tab","windowsVirtualKeyCode":9})
        call("Input.dispatchKeyEvent",{"type":"keyUp","key":"Tab","code":"Tab","windowsVirtualKeyCode":9})
        info=ev("""(()=>{const e=document.activeElement;if(!e||e===document.body)return null;const r=e.getBoundingClientRect();const cs=getComputedStyle(e);return {tag:e.tagName,id:e.id||e.name||e.textContent.trim().slice(0,20),y:Math.round(r.top+scrollY),outline:cs.outlineStyle!=='none'&&parseFloat(cs.outlineWidth)>=2,ratio:(()=>{const rgb=c=>c.match(/[\\d.]+/g).slice(0,4).map(Number);const lum=([r,g,b])=>[r,g,b].map(v=>{v/=255;return v<=0.03928?v/12.92:Math.pow((v+0.055)/1.055,2.4)}).reduce((a,v,i)=>a+v*[0.2126,0.7152,0.0722][i],0);let p=e.parentElement,bg=[255,255,255];while(p){const c=rgb(getComputedStyle(p).backgroundColor);if(c.length<4||c[3]>0){bg=c.slice(0,3);break}p=p.parentElement}const a=lum(rgb(cs.outlineColor)),b=lum(bg);return Math.round((Math.max(a,b)+0.05)/(Math.min(a,b)+0.05)*100)/100})(),idx:[...document.querySelectorAll('*')].indexOf(e)}})()""")
        if info is None: break
        key=(info["tag"],info["idx"])
        if seen and key==seen[0]: break
        seen.append(key)
        if not info["outline"]: invisible.append(info["tag"]+":"+str(info["id"]))
        elif info["ratio"] < 3: low.append(info["tag"]+":"+str(info["id"])+" "+str(info["ratio"]))
        if info["outline"]: ratios.append(info["ratio"])
    order_ok = [i for _,i in seen]==sorted(i for _,i in seen)
    print(json.dumps({"focusable":focusable,"reached":len(set(seen)),"dom_order":order_ok,"positive_tabindex":positive,"no_visible_focus":invisible[:5],"min_focus_contrast":min(ratios) if ratios else None,"low_contrast_focus":low[:5]}))
finally:
    p.kill()
