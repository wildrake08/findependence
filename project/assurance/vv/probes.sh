#!/bin/sh
# VV-001 probes against a running server (mix findependence.serve <vault> 4871). Prints one result per probe.
# Needs curl and python3. Expected results are in project/assurance/runs/VV-RUN-001.txt.
U=http://127.0.0.1:4871
python3 - <<'PY'
import socket,struct
for f in ('/proc/net/tcp','/proc/net/tcp6'):
    for l in open(f).read().splitlines()[1:]:
        p=l.split(); ip,port=p[1].split(':'); port=int(port,16)
        if p[3]=='0A' and port==4871:
            print('listen', f, socket.inet_ntoa(struct.pack('<I',int(ip,16))) if len(ip)==8 else ip, port)
PY
curl -s -D - -o /dev/null $U/ | grep -iE "content-security|x-frame|x-content|referrer|cache-control|set-cookie" | sed 's/_fv=[^;]*/_fv=<redacted>/'
echo "foreign Host: $(curl -s -o /dev/null -w %{http_code} -H 'Host: evil.example' $U/)"
echo "localhost Host: $(curl -s -o /dev/null -w %{http_code} -H 'Host: localhost:4871' $U/)"
echo "traversal: $(curl -s -o /dev/null -w %{http_code} --path-as-is "$U/../../etc/passwd")"
echo "20 MB body: $(head -c 20000000 /dev/zero | tr '\0' a | curl -s -o /dev/null -w %{http_code} -X POST --data-binary @- -H 'Content-Type: application/x-www-form-urlencoded' $U/login)"
echo "bad percent-encoding: $(curl -s -o /dev/null -w %{http_code} -X POST --data 'member=%ZZ&passphrase=%' $U/login)"
echo "no CSRF token: $(curl -s -o /dev/null -w %{http_code} -X POST --data 'member=Ana&passphrase=x' $U/login)"
echo "unknown route: $(curl -s -o /dev/null -w %{http_code} $U/nowhere)"
echo "alive after probes: $(curl -s -o /dev/null -w %{http_code} $U/)"
