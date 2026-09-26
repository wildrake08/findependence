# Reads Chromium's accessibility tree for a page at a given width via the DevTools protocol.
# usage: axtree.py <file.html> <width>   (prints role counts and table-related nodes)
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
    call("Accessibility.enable")
    tree=call("Accessibility.getFullAXTree")["nodes"]
    roles=collections.Counter(n.get("role",{}).get("value") for n in tree if not n.get("ignored"))
    keep=["table","row","cell","columnheader","rowheader","rowgroup","LayoutTable","LayoutTableRow","LayoutTableCell","generic"]
    print(json.dumps({k:roles[k] for k in keep if roles[k]}))
    # first data cell's name/label, to see if column headers are exposed
    for n in tree:
        if n.get("role",{}).get("value") in ("cell","LayoutTableCell") and not n.get("ignored"):
            print("first cell:", n.get("role",{}).get("value"), repr(n.get("name",{}).get("value"))); break
finally:
    p.kill()
