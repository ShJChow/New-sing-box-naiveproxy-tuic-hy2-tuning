#!/usr/bin/env python3
import sys, os, re, base64
try:
    from http.server import ThreadingHTTPServer as ServerClass
except ImportError:
    from socketserver import ThreadingMixIn
    from http.server import HTTPServer
    class ServerClass(ThreadingMixIn, HTTPServer):
        daemon_threads = True
from http.server import BaseHTTPRequestHandler
from urllib.parse import unquote

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 50934
WEB_DIR = sys.argv[2] if len(sys.argv) > 2 else "/root/sbbox/websub"
SB_HOME = os.path.dirname(WEB_DIR.rstrip("/"))

# 订阅端口监听 0.0.0.0，请求路径必须白名单校验后才能拼进 WEB_DIR，
# 否则 "/../../../etc/passwd" 会变成公网任意文件读取。
SAFE_TOKEN_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
WEB_DIR_REAL = os.path.realpath(WEB_DIR)

def resolve_token_file(token_path):
    if not SAFE_TOKEN_RE.match(token_path) or token_path.startswith("."):
        return None
    candidate = os.path.realpath(os.path.join(WEB_DIR_REAL, token_path))
    if candidate != WEB_DIR_REAL and not candidate.startswith(WEB_DIR_REAL + os.sep):
        return None
    if not os.path.isfile(candidate):
        return None
    return candidate

class SubHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        ua = self.headers.get("User-Agent", "-") if hasattr(self, "headers") and self.headers else "-"
        sys.stdout.write("%s - - [%s] %s (UA: %s)\n" % (self.address_string(), self.log_date_time_string(), format % args, ua))
        sys.stdout.flush()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        raw_path = self.path.split("#")[0]
        query = raw_path.split("?", 1)[1] if "?" in raw_path else ""
        token_path = unquote(raw_path.split("?")[0]).lstrip("/")
        if token_path in ("", "index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"sbbox subscription server is running.\n")
            return
        if token_path in ("qr", "qr.png", "sub_qr.png") or token_path.endswith((".png", "/qr")):
            qr_file = os.path.join(WEB_DIR_REAL, "sub_qr.png")
            if not os.path.isfile(qr_file):
                qr_file = os.path.join(SB_HOME, "sub_qr.png")
            if os.path.isfile(qr_file):
                with open(qr_file, "rb") as f: content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        force_format = ""
        for suffix in ("/clash", "/singbox", "/sb", "/json", "/b64", "/v2rayn", "/v2ray"):
            if token_path.endswith(suffix):
                force_format = suffix.lstrip("/")
                token_path = token_path[:-len(suffix)]
                break

        token_file = resolve_token_file(token_path)
        if token_file is None:
            self.send_response(404)
            self.end_headers()
            return

        ua = self.headers.get("User-Agent", "").lower()
        q_lower = query.lower()

        is_b64 = force_format in ("b64", "v2rayn", "v2ray") or "format=b64" in q_lower or "b64=1" in q_lower or "v2rayn=1" in q_lower or "v2ray=1" in q_lower
        is_clash = not is_b64 and (force_format == "clash" or "clash=1" in q_lower or "format=clash" in q_lower or any(k in ua for k in ("clash", "mihomo", "stash", "meta", "subconverter", "verge", "flclash")))
        is_singbox = not is_b64 and (force_format in ("singbox", "sb", "json") or "singbox=1" in q_lower or "sb=1" in q_lower or "format=singbox" in q_lower or "format=json" in q_lower or "sing-box" in ua or "sbox" in ua or "nekoray" in ua)

        if is_clash:
            clash_file = os.path.join(SB_HOME, "clmi.yaml")
            if os.path.isfile(clash_file):
                with open(clash_file, "rb") as f: content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/yaml; charset=utf-8")
                self.send_header("profile-update-interval", "24")
                self.send_header("content-disposition", 'attachment; filename="sbbox_clash.yaml"')
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        if is_singbox:
            sb_file = os.path.join(SB_HOME, "sbox_client.json")
            if os.path.isfile(sb_file):
                with open(sb_file, "rb") as f: content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("content-disposition", 'attachment; filename="sbox_client.json"')
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        raw_links = []
        nodes_txt = os.path.join(SB_HOME, "nodes.txt")
        if os.path.isfile(nodes_txt):
            with open(nodes_txt, "r", encoding="utf-8", errors="ignore") as f:
                raw_links = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
        else:
            with open(token_file, "rb") as f: b64 = f.read().strip()
            try:
                decoded = base64.b64decode(b64).decode("utf-8", errors="ignore")
                raw_links = [line.strip() for line in decoded.splitlines() if line.strip() and not line.strip().startswith("#")]
            except Exception: pass

        # 默认下发全量 6 大协议节点，不擅自剔除任何已启用节点
        selected_links = list(raw_links)
        if not selected_links:
            with open(token_file, "rb") as f: content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            return

        body = base64.b64encode("\n".join(selected_links).encode("utf-8"))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Subscription-Userinfo", "upload=0; download=0; total=0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def run():
    httpd = ServerClass(("0.0.0.0", PORT), SubHandler)
    httpd.daemon_threads = True
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()

if __name__ == "__main__":
    run()
