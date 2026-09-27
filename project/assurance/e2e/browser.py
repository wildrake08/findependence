# HTTP driver for the real Findependence server (WI-049): a small browser that reads a page, fills the
# form it finds there (hidden fields as rendered, plus overrides), submits it, and follows the redirect.
# Standard library only. Used by alpha_e2e.py.
import sys, re, json, html, urllib.request, urllib.parse, http.cookiejar
from html.parser import HTMLParser

class Forms(HTMLParser):
    def __init__(self):
        super().__init__(); self.forms = []; self.cur = None; self.sel = None
    def handle_starttag(self, tag, a):
        a = dict(a)
        if tag == "form": self.cur = {"action": a.get("action"), "method": (a.get("method") or "get").lower(), "fields": [], "id": a.get("id")}; self.forms.append(self.cur)
        elif self.cur is None: return
        elif tag == "input":
            t = (a.get("type") or "text").lower()
            if t in ("checkbox", "radio"):
                if "checked" in a: self.cur["fields"].append((a.get("name"), a.get("value", "on")))
            elif t not in ("submit", "file"): self.cur["fields"].append((a.get("name"), a.get("value", "")))
        elif tag == "select": self.sel = [a.get("name"), None, None]
        elif tag == "option" and self.sel is not None:
            if self.sel[2] is None: self.sel[2] = a.get("value", "")
            if "selected" in a: self.sel[1] = a.get("value", "")
    def handle_endtag(self, tag):
        if tag == "select" and self.sel is not None and self.cur is not None:
            self.cur["fields"].append((self.sel[0], self.sel[1] if self.sel[1] is not None else ""))
            self.sel = None
        if tag == "form": self.cur = None

class Browser:
    def __init__(self, port):
        self.base = f"http://127.0.0.1:{port}"
        self.jar = http.cookiejar.CookieJar()
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *a, **k): return None
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar), NoRedirect)
    def req(self, method, path, data=None, files=None):
        body = None; headers = {}
        if files:
            b = "----e2eboundary"; parts = []
            for k, v in data:
                parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
            for k, (fn, content) in files.items():
                parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{k}"; filename="{fn}"\r\nContent-Type: application/json\r\n\r\n'.encode() + content + b"\r\n")
            body = b"".join(parts) + f"--{b}--\r\n".encode(); headers["Content-Type"] = f"multipart/form-data; boundary={b}"
        elif data is not None:
            body = urllib.parse.urlencode(data).encode(); headers["Content-Type"] = "application/x-www-form-urlencoded"
        r = urllib.request.Request(self.base + path, data=body, method=method, headers=headers)
        try: resp = self.op.open(r); code = resp.status; hdrs = resp.headers; text = resp.read()
        except urllib.error.HTTPError as e: code = e.code; hdrs = e.headers; text = e.read()
        return code, hdrs, text
    def get(self, path):
        c, h, t = self.req("GET", path); return c, t.decode("utf-8", "replace")
    def submit(self, page_path, action, overrides=None, follow=True, pick=0, drop=(), files=None, page=None):
        if page is None: _, page = self.get(page_path)
        p = Forms(); p.feed(page)
        forms = [f for f in p.forms if f["action"] == action]
        if not forms: raise SystemExit(f"no form {action} on {page_path}")
        f = forms[pick]
        fields = [(k, v) for k, v in f["fields"] if k and k not in drop]
        ov = overrides or {}
        fields = [(k, v) for k, v in fields if k not in ov]
        for k, v in ov.items():
            if isinstance(v, list): fields += [(k, x) for x in v]
            else: fields.append((k, v))
        code, hdrs, text = self.req("POST", action, fields, files=files)
        loc = hdrs.get("location")
        if follow and code == 303 and loc:
            c2, t2 = self.get(loc); return code, loc, t2
        return code, loc, text.decode("utf-8", "replace")

def text(page): return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", page)))
def msgs(page): return [text(m) for m in re.findall(r'<p class="msg[^"]*"[^>]*>.*?</p>', page, re.S)]
