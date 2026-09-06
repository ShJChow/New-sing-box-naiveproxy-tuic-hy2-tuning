#!/usr/bin/env python3
"""
sbbox Smart Subscription Server
Provides User-Agent adaptive subscription distribution:
- Shadowrocket: returns Shadowrocket compatible base64 (tuic, hy2, http3, http2)
- v2rayN / NekoBox: returns v2rayN compatible base64 (tuic, hy2, naive+quic)
- Clash / Mihomo: returns clmi.yaml directly
- sing-box: returns sbox_client.json directly
- Default / Other: returns full static base64 file
"""

import sys
import os
import re
import base64
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import unquote

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 50934
WEB_DIR = sys.argv[2] if len(sys.argv) > 2 else "/root/sbbox/websub"
SB_HOME = os.path.dirname(WEB_DIR.rstrip("/"))

# 订阅 token 只可能是安装期生成的十六进制串（见 sbbox.sh 的 subtoken）。
# 这里用白名单而不是黑名单：任何带 "/"、".." 或转义字符的请求路径一律 404，
# 否则 os.path.join(WEB_DIR, token_path) 会被 "/../../../etc/passwd" 这类路径
# 带出 WEB_DIR，变成公网上的任意文件读取（订阅端口监听 0.0.0.0）。
SAFE_TOKEN_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
WEB_DIR_REAL = os.path.realpath(WEB_DIR)


def resolve_token_file(token_path):
    """把请求路径解析成 WEB_DIR 内的文件；越界或非法一律返回 None。"""
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
        # Keep standard access log format to stdout for journalctl
        sys.stdout.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format % args))
        sys.stdout.flush()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        raw_path = self.path.split("?")[0].split("#")[0]
        token_path = unquote(raw_path).lstrip("/")

        # 1. Root / healthcheck
        if token_path in ("", "index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"sbbox subscription server is running.\n")
            return

        # 2. Check if requested token file exists (且必须落在 WEB_DIR 内)
        token_file = resolve_token_file(token_path)
        if token_file is None:
            self.send_response(404)
            self.end_headers()
            return

        ua = self.headers.get("User-Agent", "").lower()

        # 3. Clash / Mihomo
        if "clash" in ua or "mihomo" in ua or "stash" in ua or "meta" in ua or "subconverter" in ua:
            clash_file = os.path.join(SB_HOME, "clmi.yaml")
            if os.path.isfile(clash_file):
                with open(clash_file, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/yaml; charset=utf-8")
                self.send_header("profile-update-interval", "24")
                self.send_header("content-disposition", 'attachment; filename="sbbox_clash.yaml"')
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        # 4. sing-box client
        if "sing-box" in ua or "sbox" in ua:
            sb_file = os.path.join(SB_HOME, "sbox_client.json")
            if os.path.isfile(sb_file):
                with open(sb_file, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("content-disposition", 'attachment; filename="sbox_client.json"')
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        # 5. Read raw links from nodes.txt
        raw_links = []
        nodes_txt = os.path.join(SB_HOME, "nodes.txt")
        if os.path.isfile(nodes_txt):
            with open(nodes_txt, "r", encoding="utf-8", errors="ignore") as f:
                raw_links = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]
        else:
            with open(token_file, "rb") as f:
                b64 = f.read().strip()
            try:
                decoded = base64.b64decode(b64).decode("utf-8", errors="ignore")
                raw_links = [line.strip() for line in decoded.splitlines() if line.strip() and not line.strip().startswith("#")]
            except Exception:
                pass

        # 6. Filter nodes by client User-Agent
        selected_links = []
        if "shadowrocket" in ua:
            # Shadowrocket: Tuic, Hy2, Vless Reality, http3, http2
            for l in raw_links:
                if l.startswith("tuic://") or l.startswith("hysteria2://") or l.startswith("vless://") or l.startswith("http3://") or l.startswith("http2://"):
                    selected_links.append(l)
        elif "v2rayn" in ua or "nekobox" in ua:
            # v2rayN / NekoBox: Tuic, Hy2, Vless Reality, naive+quic, naive+https
            for l in raw_links:
                if l.startswith("tuic://") or l.startswith("hysteria2://") or l.startswith("vless://") or l.startswith("naive+quic://") or l.startswith("naive+https://"):
                    selected_links.append(l)
        else:
            # Default: if no specific UA matched, serve token_file directly
            with open(token_file, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            return

        body = base64.b64encode("\n".join(selected_links).encode("utf-8"))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Subscription-Userinfo", "upload=0; download=0; total=0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def run():
    server_address = ("0.0.0.0", PORT)
    httpd = HTTPServer(server_address, SubHandler)
    httpd.serve_forever()

if __name__ == "__main__":
    run()
