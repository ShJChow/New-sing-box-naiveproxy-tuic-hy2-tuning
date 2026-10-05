#!/usr/bin/env python3
import sys, os, re, base64, json
from http.server import HTTPServer, BaseHTTPRequestHandler
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
    # 隐私：不落访问日志，也不把客户端 IP / UA 写进 journald；
    # 真正的处理器错误仍写 stderr（不带客户端地址），便于排错
    def version_string(self):
        return "nginx"

    def log_request(self, code="-", size="-"):
        pass

    def send_error(self, code, message=None, explain=None):
        # 不返回 Python 默认错误页（带 "Error response" 特征），只给状态码
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, format, *args):
        # 去掉控制字符，并遮住请求行里像订阅 token 的长路径段，再写 stderr
        msg = re.sub(r"[^\x20-\x7e]", "?", format % args)
        msg = re.sub(r"/[A-Za-z0-9._-]{16,}", "/<redacted>", msg)
        sys.stderr.write("sbbox-sub: " + msg[:200] + "\n")

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        raw_path = self.path.split("#")[0]
        query = raw_path.split("?", 1)[1] if "?" in raw_path else ""
        token_path = unquote(raw_path.split("?")[0]).lstrip("/")
        if token_path in ("", "index.html"):
            # 根路径与未知路径一致返回 404，不暴露服务身份
            self.send_response(404)
            self.end_headers()
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
                # TUN 按客户端平台自适应：?os=windows|linux|macos|android|ios，缺省时看 User-Agent；识别不出则原样下发
                plat = ""
                m = re.search(r"(?:^|&)os=([a-z]+)", q_lower)
                hint = m.group(1) if m else ua
                for key, name in (("android", "android"), ("sfa", "android"), ("iphone", "ios"), ("ios", "ios"), ("sfi", "ios"),
                                  ("darwin", "macos"), ("macos", "macos"), ("sfm", "macos"), ("mac", "macos"),
                                  ("windows", "windows"), ("win", "windows"), ("linux", "linux")):
                    if key in hint:
                        plat = name
                        break
                if plat:
                    try:
                        cfg = json.loads(content)
                        for ib in cfg.get("inbounds", []):
                            if ib.get("type") != "tun":
                                continue
                            ib["stack"] = "mixed"
                            if plat == "windows":
                                ib["strict_route"] = True
                            elif plat == "linux":
                                ib["strict_route"] = True
                                ib["auto_redirect"] = True
                            else:
                                # macOS 不支持 strict_route；Android / iOS 由系统 VPN 接管路由，不需要
                                ib["strict_route"] = False
                                ib.pop("auto_redirect", None)
                        content = json.dumps(cfg, indent=4, ensure_ascii=False).encode("utf-8")
                    except Exception:
                        pass
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
        # Shadowrocket 只认 http3:// / http2:// 形式的 naive 链接（v2.7.28 起订阅只存 naive+ 写法），按 UA 现场转换
        if "shadowrocket" in ua:
            selected_links = [("http3://" + l[len("naive+quic://"):]) if l.startswith("naive+quic://")
                              else ("http2://" + l[len("naive+https://"):]) if l.startswith("naive+https://")
                              else l for l in selected_links]
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
    httpd = HTTPServer(("0.0.0.0", PORT), SubHandler)
    httpd.serve_forever()

if __name__ == "__main__":
    run()
