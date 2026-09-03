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
import base64
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 50934
WEB_DIR = sys.argv[2] if len(sys.argv) > 2 else "/root/sbbox/websub"
SB_HOME = os.path.dirname(WEB_DIR.rstrip("/"))

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
        token_path = self.path.lstrip("/").split("?")[0]
        token_file = os.path.join(WEB_DIR, token_path)

        # 1. Root / healthcheck
        if token_path in ("", "index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"sbbox subscription server is running.\n")
            return

        # 2. Check if requested token file exists
        if not os.path.isfile(token_file):
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
            # Shadowrocket: Tuic, Hy2, http3, http2
            for l in raw_links:
                if l.startswith("tuic://") or l.startswith("hysteria2://") or l.startswith("http3://") or l.startswith("http2://"):
                    selected_links.append(l)
        elif "v2rayn" in ua or "nekobox" in ua:
            # v2rayN / NekoBox: Tuic, Hy2, naive+quic, naive+https
            for l in raw_links:
                if l.startswith("tuic://") or l.startswith("hysteria2://") or l.startswith("naive+quic://") or l.startswith("naive+https://"):
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
