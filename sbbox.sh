#!/usr/bin/env bash
# ======================================================
# sing-box-naiveproxy (sbbox.sh) — Sing-box 三协议安全加固代理脚本
#
# 基于 yonggekkk/argosbx 架构，剥离为 sing-box 单内核，
# 保留 Tuic / Hysteria2 / Naiveproxy(H2+H3) 三协议。
# 默认使用官方正式版内核（sbrel=stable），默认开启 QUIC 与 BBR 拥塞控制。
#
# 集成内核级流控调优 (xh tuning on) + acme.sh 证书申请。
#
# 免责声明：
#   本脚本仅供网络技术研究与学习交流使用。使用者须自行遵守所在国家/地区的
#   法律法规，因使用本脚本产生的一切后果由使用者自行承担，作者不对任何直接
#   或间接损失负责。请勿用于任何非法用途。
#
# 用法：
#   bash sbbox.sh                     # 安装（需前置协议变量，见 README）
#   sbbox list                        # 显示节点信息
#   sbbox status                      # 服务状态 + 流控状态
#   sbbox res                         # 重启 sing-box
#   sbbox tune [show|off]             # 流控调优管理
#   sbbox cert [status|renew]         # 证书管理
#   sbbox up                          # 更新 sing-box 内核
#   sbbox log [N]                     # 查看最近 N 行日志
#   sbbox del                         # 卸载
#
# 安全设计原则：
#   1. TLS 一律 insecure=0，不允许自签证书绕过（Naive 强制 acme 证书）
#   2. Hysteria2/Tuic 无 acme 证书时使用自签 + SHA256 固定指纹
#   3. 内核流控调优全部 best-effort，写入独立文件可整体回滚
#   4. 只写自己的文件，不修改用户既有 /etc/sysctl.conf 与官方 unit
# ======================================================

# ---------- 全局路径与常量 ----------
SB_HOME="$HOME/sbbox"
SB_BIN="$SB_HOME/sing-box"
SB_CONF="$SB_HOME/sb.json"
SB_LOG="$SB_HOME/sb.log"
SB_LINK="$SB_HOME/nodes.txt"
SUB_DIR="$SB_HOME/websub"
CERT_DIR="$SB_HOME/cert"
SYSCTL_CONF="/etc/sysctl.d/99-sbbox.conf"
LIMITS_CONF="/etc/security/limits.d/99-sbbox.conf"
SB_SERVICE="sbbox"
SB_SEC_DIR="$SB_HOME/sec"
SBBOX_VERSION="v2.0.0"
SB_URL="https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh"
# root 装到 /usr/local/bin（始终在 PATH 中）；非 root 退回 ~/bin
if [ "$(id -u 2>/dev/null)" = "0" ] && [ -d /usr/local/bin ]; then
  SB_BINDIR="/usr/local/bin"
else
  SB_BINDIR="$HOME/bin"
fi

# ---------- 颜色输出 ----------
NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[-]${NC} $*"; }

# ---------- 环境变量默认值 ----------
uuid="${uuid:-}"
ym="${ym:-}"                                # acme 证书域名（启用 alns 时必需）
alns="${alns:-}"                            # 申请 acme 证书：alns=1
tup="${tup:-}" hyp="${hyp:-}" nvp="${nvp:-}"
hyjpt="${hyjpt:-}"                          # Hysteria2 跳跃端口，如 "20000:30000"
hyobfs="${hyobfs:-1}"                       # Hysteria2 salamander 混淆，默认开启；关闭用 hyobfs=0
hyobfs_pw="${hyobfs_pw:-}"                  # 混淆密码（默认独立随机值）
hymask="${hymask:-https://www.bing.com}"    # Hysteria2 伪装：反代真实站点；静态 404 用 hymask=none
sblevel="${sblevel:-error}"                 # 服务端日志级别：error（默认，少留痕）/ warn / info / off
blkport="${blkport:-1}"                     # 阻断出站邮件/SMB 端口（防凭据外泄后被拿去发垃圾邮件），关闭用 blkport=0
hyup="${hyup:-}"                            # Hysteria2 上行 Mbps（与 hydown 同时设置才启用 Brutal CC）
hydown="${hydown:-}"                        # Hysteria2 下行 Mbps
ippz="${ippz:-}"                            # 4 / 6 / 双栈
name="${name:-}"
noautoup="${noautoup:-}"                    # 关闭每周内核自动升级：noautoup=1
# 内核版本通道：默认 stable，只跟踪官方正式版；若需跟踪 pre-release（beta/rc）用 sbrel=pre。
# 先记下用户是否显式指定，再套默认值 —— 否则「没传」与「传了 stable」无法区分，
# 已持久化的通道选择会被默认值静默覆盖。
sbrel_explicit="${sbrel:+1}"
sbrel="${sbrel:-stable}"
tuicuos="${tuicuos:-0}"                     # Tuic UDP 中继模式：默认原生 UDP(native，防队头阻塞断流)；QUIC流用 tuicuos=1
tuils="${tuils:-1}"                         # Tuic TLS 加固（证书公钥 SHA-256 固定），关闭用 tuils=0

tuech="${tuech:-}"                          # Tuic ECH：tuech=1 且 tuech_config=<base64> 时启用（需服务端支持）
tuech_config="${tuech_config:-}"            # ECH config list（base64）
sub="${sub:-}"                              # 启用订阅服务：sub=1
subport="${subport:-}"                      # 订阅端口（默认随机）
subid="${subid:-}"                          # 订阅令牌（默认用 uuid）
sub_nonaive="${sub_nonaive:-}"              # 剔除 Naiveproxy 节点（客户端不支持时用）

# ---------- 架构 / 系统探测 ----------
detect_env() {
  case $(uname -m) in
    arm64|aarch64) cpu=arm64 ;;
    amd64|x86_64)  cpu=amd64 ;;
    *) error "目前脚本不支持 $(uname -m) 架构" && exit 1 ;;
  esac
  if [ "$EUID" -eq 0 ] 2>/dev/null; then IS_ROOT=1; else IS_ROOT=0; fi
  if pidof systemd >/dev/null 2>&1; then
    SERVICE_TYPE="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    SERVICE_TYPE="openrc"
  else
    SERVICE_TYPE="cron"
  fi
  hostname_s=$(hostname 2>/dev/null || echo vps)
}

# ---------- 网络地址探测 (IPv4/IPv6/归属地) ----------
v4v6() {
  local v46url="https://api.ip.sb/geoip"
  v4=$( { command -v curl >/dev/null 2>&1 && curl -s4m5 -k "$v46url" 2>/dev/null; } || { command -v wget >/dev/null 2>&1 && timeout 3 wget -4 --tries=2 -qO- "$v46url" 2>/dev/null; } )
  v6=$( { command -v curl >/dev/null 2>&1 && curl -s6m5 -k "$v46url" 2>/dev/null; } || { command -v wget >/dev/null 2>&1 && timeout 3 wget -6 --tries=2 -qO- "$v46url" 2>/dev/null; } )
  server_ip=$( { command -v curl >/dev/null 2>&1 && curl -s4m5 -k https://api.ipify.org 2>/dev/null; } || { command -v wget >/dev/null 2>&1 && timeout 3 wget -4 --tries=2 -qO- https://api.ipify.org 2>/dev/null; } )
  if [ -z "$server_ip" ] && [ -n "$v6" ]; then
    server_ip=$( { command -v curl >/dev/null 2>&1 && curl -s6m5 -k https://api64.ipify.org 2>/dev/null; } || true )
  fi
  echo "$server_ip" > "$SB_HOME/server_ip.log" 2>/dev/null
}

# ---------- 帮助信息 ----------
showmode() {
  echo "==========================================================="
  echo "sbbox $SBBOX_VERSION — Sing-box-Only 三协议安全代理脚本"
  echo "支持协议：Tuic / Hysteria2 / Naiveproxy(H2+H3)"
  echo "-----------------------------------------------------------"
  echo "主脚本：bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh)"
  echo "显示节点信息：sbbox list 【或】 bash sbbox.sh list"
  echo "服务与流控状态：sbbox status"
  echo "重启 sing-box：sbbox res"
  echo "更新内核：sbbox up"
  echo "流控调优：sbbox tune show | sbbox tune off"
  echo "证书管理：sbbox cert status | sbbox cert renew"
  echo "订阅地址：sbbox sub 【关闭】 sbbox sub off"
  echo "自检修复：sbbox doctor"
  echo "卸载：sbbox del"
  echo "-----------------------------------------------------------"
  echo "环境变量（安装期）：tup=1 hyp=1 nvp=1"
  echo "  alns=1   启用 acme 证书（需 ym=你的域名）"
  echo "  ym=域名  acme 证书域名（Hysteria2/Tuic/Naive 使用）"
  echo "  hyjpt=20000:30000  Hysteria2 跳跃端口"
  echo "  sub=1    启用 v2rayN 订阅服务（subport=端口 subid=令牌 可选）"
  echo "  sbrel=stable  内核只跟踪正式版（默认 stable；跟踪 beta/rc 用 sbrel=pre）"
  echo "  uuid=自定义 UUID（Tuic 用；各协议密码独立随机，不再复用）"
  echo "  hymask=URL  Hysteria2 伪装反代目标（默认 https://www.bing.com，none=静态 404）"
  echo "  sblevel=error|warn|info|off  服务端日志级别（默认 error）"
  echo "轮换全部密码：sbbox rotate（各协议独立新密钥，需重新导入客户端）"
  echo "-----------------------------------------------------------"
  echo "免责声明：本脚本仅供网络技术研究与学习交流。使用者须遵守所在国家/地区"
  echo "法律法规，一切后果自负，作者不承担任何责任。请勿用于非法用途。"
  echo "==========================================================="
}

# ---------- 依赖安装 ----------
install_deps() {
  if [ ! -f "$SB_HOME/deps_done" ]; then
    info "安装系统依赖……"
    if command -v apk >/dev/null 2>&1; then
      apk update >/dev/null 2>&1 && apk add --no-cache bash coreutils curl wget openssl iptables ip6tables ca-certificates ethtool iproute2 >/dev/null 2>&1
    elif command -v apt >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt update >/dev/null 2>&1 && apt install -y curl wget openssl ca-certificates iptables iptables-persistent net-tools ethtool iproute2 >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl wget openssl ca-certificates iptables ethtool iproute >/dev/null 2>&1
    fi
    touch "$SB_HOME/deps_done"
  fi
}

# ---------- 端口防火墙放行 (iptables / ip6tables / ufw / firewalld) ----------
open_port() {
  local port="$1" proto="${2:-tcp}"
  [ -n "$port" ] || return 0
  if [ "$IS_ROOT" = 1 ]; then
    if command -v iptables >/dev/null 2>&1; then
      iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    fi
    if command -v ip6tables >/dev/null 2>&1; then
      ip6tables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
        ip6tables -I INPUT 1 -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
      ufw allow "${port}/${proto}" >/dev/null 2>&1
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
      firewall-cmd --add-port="${port}/${proto}" --permanent >/dev/null 2>&1
      firewall-cmd --reload >/dev/null 2>&1
    fi
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save >/dev/null 2>&1
    elif [ -x "$(command -v iptables-save 2>/dev/null)" ] && [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4 2>/dev/null
      ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
    fi
  fi
}


# ---------- sing-box 内核下载/更新 ----------
# 查询 sing-box 最新版本号（去掉 tag 的 v 前缀）。
# 默认通道是 pre：跟踪最新 pre-release（beta/rc），正式版本身也在该列表里，
# 所以「pre」等价于「最新的一个 release，不论是否预发布」。
# sbrel=stable 时改用 releases/latest，GitHub 只在该端点返回正式版。
latest_sb_version() {
  local api
  if [ "$sbrel" = "pre" ]; then
    # 列表 API 包含 pre-release；按发布时间倒序，取第一条（最新的）
    api="https://api.github.com/repos/SagerNet/sing-box/releases?per_page=5"
  else
    api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  fi
  { (command -v curl >/dev/null 2>&1 && curl -fsSL --retry 2 "$api" 2>/dev/null) || \
    (command -v wget >/dev/null 2>&1 && wget -qO- --tries=2 "$api" 2>/dev/null); } \
    | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | cut -d'"' -f4 | sed 's/^v//'
}

sb_installed_version() {
  [ -x "$SB_BIN" ] || return 1
  "$SB_BIN" version 2>/dev/null | awk '/version/{print $NF; exit}'
}

# 从官方 release 安装指定版本；成功返回 0
install_sb_official() {
  local ver="$1" tmp="$SB_HOME/.sbdl" tgz
  [ -n "$ver" ] || return 1
  tgz="$tmp/sing-box-${ver}-linux-${cpu}.tar.gz"
  rm -rf "$tmp"; mkdir -p "$tmp"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${cpu}.tar.gz"
  if ! { (command -v curl >/dev/null 2>&1 && curl -fL --retry 2 -o "$tgz" "$url" 2>/dev/null) || \
         (command -v wget >/dev/null 2>&1 && wget -qO "$tgz" --tries=2 "$url" 2>/dev/null); }; then
    rm -rf "$tmp"; return 1
  fi
  # 连同 libcronet.so 一起解压：naive **出站**（客户端方向）靠 dlopen 加载它，
  # 缺库会以 "cronet: library not found" 启动失败。放在二进制同目录即可被找到。
  tar -xzf "$tgz" -C "$tmp" "sing-box-${ver}-linux-${cpu}/sing-box" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  tar -xzf "$tgz" -C "$tmp" "sing-box-${ver}-linux-${cpu}/libcronet.so" 2>/dev/null || true
  # 先落到临时文件校验可执行，再覆盖，避免下载损坏把可用内核冲掉
  if [ -s "$tmp/sing-box-${ver}-linux-${cpu}/sing-box" ]; then
    chmod +x "$tmp/sing-box-${ver}-linux-${cpu}/sing-box"
    if "$tmp/sing-box-${ver}-linux-${cpu}/sing-box" version >/dev/null 2>&1; then
      mv -f "$tmp/sing-box-${ver}-linux-${cpu}/sing-box" "$SB_BIN"
      chmod +x "$SB_BIN"
      [ -s "$tmp/sing-box-${ver}-linux-${cpu}/libcronet.so" ] && \
        mv -f "$tmp/sing-box-${ver}-linux-${cpu}/libcronet.so" "$SB_HOME/libcronet.so"
      rm -rf "$tmp"; return 0
    fi
  fi
  rm -rf "$tmp"; return 1
}

upsingbox() {
  local cur latest
  cur=$(sb_installed_version)
  latest=$(latest_sb_version)

  if [ -z "$latest" ]; then
    warn "无法查询 sing-box 最新版本（GitHub API 不可达）"
    if [ -x "$SB_BIN" ]; then
      info "保留现有内核：${cur:-未知}"
      return 0
    fi
  else
    if [ -n "$cur" ] && [ "$cur" = "$latest" ]; then
      if [ "$sbrel" = "pre" ]; then
        info "sing-box 已是最新 pre-release 通道版本：$cur"
      else
        info "sing-box 已是最新正式版：$cur"
      fi
      return 0
    fi
    if [ "$sbrel" = "pre" ]; then
        info "下载 sing-box pre-release 通道 ${latest} (linux-$cpu)……"
      else
        info "下载 sing-box 官方正式版 ${latest} (linux-$cpu)……"
      fi
    if install_sb_official "$latest"; then
      info "sing-box 内核：${cur:-无} → $(sb_installed_version)"
      return 0
    fi
    warn "官方源下载失败，尝试镜像源"
  fi

  # 回退：argosbx 镜像（版本可能滞后，仅在官方源不可达时使用）
  local url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/sing-box-$cpu"
  (command -v curl >/dev/null 2>&1 && curl -fLo "$SB_BIN" -# --retry 2 "$url") || \
    (command -v wget >/dev/null 2>&1 && wget -O "$SB_BIN" --tries=2 "$url")
  chmod +x "$SB_BIN" 2>/dev/null
  if [ -x "$SB_BIN" ] && "$SB_BIN" version >/dev/null 2>&1; then
    warn "已使用镜像源内核：$(sb_installed_version)（可能非最新，稍后可重试 sbbox up）"
  else
    error "sing-box 内核下载失败" && exit 1
  fi
}

# ---------- UUID 生成 ----------
insuuid() {
  if [ -z "$uuid" ] && [ ! -e "$SB_HOME/uuid" ]; then
    uuid=$("$SB_BIN" generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    echo "$uuid" > "$SB_HOME/uuid"
  elif [ -n "$uuid" ]; then
    echo "$uuid" > "$SB_HOME/uuid"
  fi
  uuid=$(cat "$SB_HOME/uuid")
  info "UUID：$uuid"
}

# ---------- 每协议独立密钥 ----------
# v1.8.0 起，Tuic/Hysteria2/Naive 的密码与 obfs 密码不再复用 uuid：
# 复用意味着任一节点链接（或订阅 URL）泄露即等于交出全部协议的凭据，
# 且 obfs 密码等于认证密码时，抓到一个就能同时通过混淆层与认证层。
# 每个密钥独立随机 32 hex（128 bit），单独落盘、单独轮换。
gen_secret() {
  "$SB_BIN" generate rand --hex 16 2>/dev/null || \
    openssl rand -hex 16 2>/dev/null || \
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

load_secrets() {
  mkdir -p "$SB_SEC_DIR" 2>/dev/null
  chmod 700 "$SB_SEC_DIR" 2>/dev/null
  # 平滑升级：老版本（<=v1.7.1）装好的机器所有协议共用 uuid。
  # 此时若直接生成新密钥，用户现网客户端会在一次 `sbbox up` 后全部掉线且毫无提示，
  # 故沿用 uuid 保持兼容，只提示可用 `sbbox rotate` 主动升级到独立密钥。
  local legacy=0
  if [ -s "$SB_CONF" ] && [ ! -s "$SB_SEC_DIR/tuic_pw" ] && [ -z "$SBBOX_ROTATE" ]; then legacy=1; fi
  _load_sec() { # $1=文件名
    local f="$SB_SEC_DIR/$1"
    if [ ! -s "$f" ]; then
      if [ "$legacy" = 1 ]; then printf '%s\n' "$uuid" > "$f"; else gen_secret > "$f"; fi
    fi
    chmod 600 "$f" 2>/dev/null
    cat "$f"
  }
  pw_tu=$(_load_sec tuic_pw)
  pw_hy=$(_load_sec hy2_pw)
  nv_user=$(_load_sec naive_user)
  nv_pw=$(_load_sec naive_pw)
  if [ "$legacy" = 1 ]; then
    warn "检测到旧版共用密码的安装，已沿用以免现网客户端掉线"
    warn "建议执行 sbbox rotate 换成各协议独立密钥（之后需重新导入订阅）"
  fi
}

# ---------- 证书状态 ----------
cert_ready() { [ -s "$CERT_DIR/fullchain.cer" ] && [ -s "$CERT_DIR/private.key" ]; }

cert_matches_ym() {
  local target="${1:-$ym}"
  [ -z "$target" ] && return 1
  cert_ready || return 1
  local names
  names=$(openssl x509 -in "$CERT_DIR/fullchain.cer" -noout -subject -ext subjectAltName 2>/dev/null)
  if echo "$names" | grep -Fwq "$target" || echo "$names" | grep -Fiq "DNS:$target"; then
    openssl x509 -checkend 86400 -in "$CERT_DIR/fullchain.cer" -noout 2>/dev/null && return 0
  fi
  return 1
}

get_cert_paths() {
  if cert_ready; then
    cert_path="$CERT_DIR/fullchain.cer"
    key_path="$CERT_DIR/private.key"
    CERT_OK=1
    sha=$(openssl x509 -in "$CERT_DIR/fullchain.cer" -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
    [ -n "$sha" ] && echo "$sha" > "$SB_HOME/SHA256.txt"
  else
    cert_path="$SB_HOME/selfsigned.crt"
    key_path="$SB_HOME/selfsigned.key"
    CERT_OK=0
    if [ -s "$SB_HOME/selfsigned.crt" ]; then
      sha=$(openssl x509 -in "$SB_HOME/selfsigned.crt" -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
      [ -n "$sha" ] && echo "$sha" > "$SB_HOME/SHA256.txt"
    fi
  fi
}

# ---------- 自签证书（Hysteria2/Tuic 无 acme 时的安全替代） ----------
make_selfsigned() {
  local snidom="${ym:-www.bing.com}"
  info "生成自签证书 (CN=$snidom) —— 仅 Hysteria2/Tuic 使用，客户端将固定 SHA256 指纹"
  # 先生成私钥，再签发自签证书（openssl req -key 需要 key 已存在）
  openssl genrsa -out "$SB_HOME/selfsigned.key" 2048 >/dev/null 2>&1
  if [ -s "$SB_HOME/selfsigned.key" ]; then
    openssl req -new -x509 -days 3650 -nodes \
      -key "$SB_HOME/selfsigned.key" -out "$SB_HOME/selfsigned.crt" \
      -subj "/CN=$snidom" -addext "subjectAltName=DNS:$snidom" >/dev/null 2>&1
    # 老版本 OpenSSL 不支持 -addext，回退纯 CN 自签
    if [ ! -s "$SB_HOME/selfsigned.crt" ]; then
      openssl req -new -x509 -days 3650 -nodes \
        -key "$SB_HOME/selfsigned.key" -out "$SB_HOME/selfsigned.crt" \
        -subj "/CN=$snidom" >/dev/null 2>&1
    fi
  fi
  if [ -s "$SB_HOME/selfsigned.crt" ]; then
    sha=$(openssl x509 -in "$SB_HOME/selfsigned.crt" -outform DER | sha256sum | awk '{print $1}')
    echo "$sha" > "$SB_HOME/SHA256.txt"
  else
    warn "自签证书生成失败，请检查 openssl"
  fi
}

# ======================================================
# acme.sh 证书申请（集成自 xh-tuned/src/07-acme-cert.sh）
# ======================================================
# ---------- 证书链裁剪（握手提速） ----------
# Let's Encrypt 的 fullchain 末尾带一张交叉签名的自签根（如 ISRG Root X2
# by X1）。根证书本来就该由客户端信任库提供，服务端发过去纯属浪费：
# 它在每一次 TLS 握手里都要重传一遍。对 QUIC 尤其贵——QUIC 有 3 倍放大
# 限制，握手数据越大越容易多吃一个 RTT。
#
# 判据不能用「自签根」：Let's Encrypt 链尾那张是**交叉签名**的
# （ISRG Root X2 由 X1 签发），subject != issuer，按自签去找会一张都裁不掉。
# 改成直接测我们真正要的性质——从尾部逐张试删，每删一张就拿系统信任库
# 验一次，验得过才落实这一步，验不过立即停手。裁掉的都是客户端本地已有
# 的根，对信任该根的客户端不产生任何验证差异。
#
# 前提是本机信任库能代表客户端信任库。找不到 CA bundle 时直接放弃裁剪，
# 不猜——宁可慢一点也不能签发出连不上的节点。
trim_cert_chain() {
  local f="$1" d n bundle
  [ -s "$f" ] || return 0
  command -v openssl >/dev/null 2>&1 || return 0
  for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
                /etc/ssl/cert.pem /etc/ssl/certs/ca-bundle.crt; do
    [ -s "$bundle" ] && break || bundle=""
  done
  [ -n "$bundle" ] || return 0
  d=$(mktemp -d 2>/dev/null) || return 0
  awk -v d="$d" 'BEGIN{n=0} /-----BEGIN CERTIFICATE-----/{n++} n>0{print > (d "/c" n ".pem")}' "$f"
  n=$(find "$d" -name 'c*.pem' 2>/dev/null | wc -l)
  [ "$n" -ge 2 ] || { rm -rf "$d"; return 0; }

  # 用前 $keep 张组成的链能否验证通过
  _chain_ok() {
    local keep=$1 i=2 args=()
    while [ "$i" -le "$keep" ]; do args+=(-untrusted "$d/c$i.pem"); i=$((i+1)); done
    openssl verify -CAfile "$bundle" "${args[@]}" "$d/c1.pem" >/dev/null 2>&1
  }
  # 完整链本来就验不过（私有 CA / 中间证书缺失）就别动它
  _chain_ok "$n" || { rm -rf "$d"; return 0; }

  local keep=$n
  while [ "$keep" -gt 1 ] && _chain_ok $((keep-1)); do keep=$((keep-1)); done
  [ "$keep" -lt "$n" ] || { rm -rf "$d"; return 0; }

  local tmp="$d/trimmed.pem" i=1
  : > "$tmp"
  while [ "$i" -le "$keep" ]; do cat "$d/c$i.pem" >> "$tmp"; i=$((i+1)); done
  local before after
  before=$(wc -c < "$f"); after=$(wc -c < "$tmp")
  cp -f "$f" "$f.full" 2>/dev/null
  cp -f "$tmp" "$f"
  chmod 600 "$f" "$f.full" 2>/dev/null
  info "证书链已裁剪：$n → $keep 张（${before} → ${after} 字节，每次握手少传 $((before-after)) 字节）"
  rm -rf "$d"
}

install_cert() {
  [ -z "$ym" ] && return 1

  # 1. 优先复用本机已存在的任何针对 $ym 的有效证书
  local found_cert="" found_key=""
  local cand_ecc="$HOME/.acme.sh/${ym}_ecc"
  local cand_rsa="$HOME/.acme.sh/${ym}"
  local cand_yg="$HOME/ygkkkca"
  local cand_le="/etc/letsencrypt/live/${ym}"
  local cand_xhttp="/etc/xhttp-cdn"
  local cand_ssl="/etc/ssl/private"

  if [ -f "$cand_ecc/fullchain.cer" ] && [ -f "$cand_ecc/${ym}.key" ]; then
    found_cert="$cand_ecc/fullchain.cer"; found_key="$cand_ecc/${ym}.key"
  elif [ -f "$cand_rsa/fullchain.cer" ] && [ -f "$cand_rsa/${ym}.key" ]; then
    found_cert="$cand_rsa/fullchain.cer"; found_key="$cand_rsa/${ym}.key"
  elif [ -f "$cand_ssl/fullchain.cer" ] && [ -f "$cand_ssl/private.key" ] && openssl x509 -in "$cand_ssl/fullchain.cer" -noout -subject -ext subjectAltName 2>/dev/null | grep -Fq "$ym"; then
    found_cert="$cand_ssl/fullchain.cer"; found_key="$cand_ssl/private.key"
  elif [ -f "$cand_ssl/cert.crt" ] && [ -f "$cand_ssl/private.key" ] && openssl x509 -in "$cand_ssl/cert.crt" -noout -subject -ext subjectAltName 2>/dev/null | grep -Fq "$ym"; then
    found_cert="$cand_ssl/cert.crt"; found_key="$cand_ssl/private.key"
  elif [ -f "$cand_ssl/${ym}/fullchain.cer" ] && [ -f "$cand_ssl/${ym}/private.key" ]; then
    found_cert="$cand_ssl/${ym}/fullchain.cer"; found_key="$cand_ssl/${ym}/private.key"
  elif [ -f "$cand_yg/${ym}/fullchain.cer" ] && [ -f "$cand_yg/${ym}/private.key" ]; then
    found_cert="$cand_yg/${ym}/fullchain.cer"; found_key="$cand_yg/${ym}/private.key"
  elif [ -f "$cand_yg/${ym}/cert.crt" ] && [ -f "$cand_yg/${ym}/private.key" ]; then
    found_cert="$cand_yg/${ym}/cert.crt"; found_key="$cand_yg/${ym}/private.key"
  elif [ -f "$cand_yg/cert.crt" ] && [ -f "$cand_yg/private.key" ] && openssl x509 -in "$cand_yg/cert.crt" -noout -subject -ext subjectAltName 2>/dev/null | grep -Fq "$ym"; then
    found_cert="$cand_yg/cert.crt"; found_key="$cand_yg/private.key"
  elif [ -f "$cand_yg/fullchain.cer" ] && [ -f "$cand_yg/private.key" ] && openssl x509 -in "$cand_yg/fullchain.cer" -noout -subject -ext subjectAltName 2>/dev/null | grep -Fq "$ym"; then
    found_cert="$cand_yg/fullchain.cer"; found_key="$cand_yg/private.key"
  elif [ -f "$cand_le/fullchain.pem" ] && [ -f "$cand_le/privkey.pem" ]; then
    found_cert="$cand_le/fullchain.pem"; found_key="$cand_le/privkey.pem"
  elif [ -f "$cand_xhttp/cert.crt" ] && [ -f "$cand_xhttp/private.key" ] && openssl x509 -in "$cand_xhttp/cert.crt" -noout -subject -ext subjectAltName 2>/dev/null | grep -Fq "$ym"; then
    found_cert="$cand_xhttp/cert.crt"; found_key="$cand_xhttp/private.key"
  fi

  if [ -n "$found_cert" ] && [ -n "$found_key" ]; then
    info "检测到本机已存在域名 $ym 的有效证书 ($found_cert)，直接复用"
    mkdir -p "$CERT_DIR"
    cp -f "$found_cert" "$CERT_DIR/fullchain.cer"
    cp -f "$found_key" "$CERT_DIR/private.key"
    chmod 600 "$CERT_DIR/fullchain.cer" "$CERT_DIR/private.key" 2>/dev/null
    trim_cert_chain "$CERT_DIR/fullchain.cer"
    info "证书已落地：$CERT_DIR/fullchain.cer"
    get_cert_paths
    return 0
  fi

  info "安装 acme.sh 证书申请程序……"
  if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    (command -v curl >/dev/null 2>&1 && curl -fsSL https://get.acme.sh | sh -s email=${ACME_EMAIL:-admin@example.com}) || \
      (command -v wget >/dev/null 2>&1 && wget -O- https://get.acme.sh | sh -s email=${ACME_EMAIL:-admin@example.com})
  fi
  [ -f "$HOME/.acme.sh/acme.sh" ] || { error "acme.sh 安装失败" && return 1; }
  "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1

  # 强制 IPv4 优先（纯 IPv6 环境跳过）
  if [ -z "$v6" ] && [ -n "$v4" ] && ! grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null; then
    echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf 2>/dev/null
  fi

  # 检查 80 端口占用并临时让路
  local stopped_nginx=0 stopped_caddy=0 stopped_apache=0 stopped_xray=0 stopped_sb=0
  if port_listening 80 tcp; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
      systemctl stop nginx 2>/dev/null && stopped_nginx=1
    fi
    if systemctl is-active --quiet caddy 2>/dev/null; then
      systemctl stop caddy 2>/dev/null && stopped_caddy=1
    fi
    if systemctl is-active --quiet apache2 2>/dev/null; then
      systemctl stop apache2 2>/dev/null && stopped_apache=1
    fi
    if systemctl is-active --quiet xray 2>/dev/null; then
      systemctl stop xray 2>/dev/null && stopped_xray=1
    fi
    if systemctl is-active --quiet sing-box 2>/dev/null; then
      systemctl stop sing-box 2>/dev/null && stopped_sb=1
    fi
  fi

  info "开始申请证书：$ym (需 80 端口空闲)……"
  if [ -n "$v6" ] && [ -z "$v4" ]; then
    "$HOME/.acme.sh/acme.sh" --issue -d "$ym" --standalone --listen-v6 --keylength ec-256
  else
    "$HOME/.acme.sh/acme.sh" --issue -d "$ym" --standalone --listen-v4 --keylength ec-256
  fi

  # 恢复被暂停的服务
  [ "$stopped_nginx" = 1 ] && systemctl start nginx 2>/dev/null || true
  [ "$stopped_caddy" = 1 ] && systemctl start caddy 2>/dev/null || true
  [ "$stopped_apache" = 1 ] && systemctl start apache2 2>/dev/null || true
  [ "$stopped_xray" = 1 ] && systemctl start xray 2>/dev/null || true
  [ "$stopped_sb" = 1 ] && systemctl start sing-box 2>/dev/null || true

  local acme_home="$HOME/.acme.sh/${ym}_ecc"
  if [ ! -f "$acme_home/fullchain.cer" ]; then
    acme_home="$HOME/.acme.sh/${ym}"
  fi

  if [ -f "$acme_home/fullchain.cer" ] && [ -f "$acme_home/${ym}.key" ]; then
    mkdir -p "$CERT_DIR"
    cp -f "$acme_home/fullchain.cer" "$CERT_DIR/fullchain.cer"
    cp -f "$acme_home/${ym}.key" "$CERT_DIR/private.key"
    chmod 600 "$CERT_DIR/fullchain.cer" "$CERT_DIR/private.key" 2>/dev/null
    trim_cert_chain "$CERT_DIR/fullchain.cer"
    info "证书已落地：$CERT_DIR/fullchain.cer"
    get_cert_paths
    return 0
  else
    error "证书申请失败。请确认："
    error "  1. 域名 $ym 已 A 记录解析到本机 IP：$server_ip"
    error "  2. 本机 80 端口空闲（无 nginx/apache 占用）"
    error "  3. 若使用 CF 代理，请先关闭橙色云朵（仅 DNS）"
    return 1
  fi
}

# ======================================================
# 内核级流控调优（移植自 xh-tuned/src/06-tuning-lib.sh）
# 安装期自动执行；sbbox tune off 可整体回滚
# ======================================================
sysctl_get() { sysctl -n "$1" 2>/dev/null || true; }

# fs.nr_open 是单进程可打开句柄数的内核硬上限，systemd 的 DefaultLimitNOFILE 无论
# 写多大都不能越过它。两者一旦倒挂（DefaultLimitNOFILE > fs.nr_open），systemd 在
# 拉起任何"没有自己声明 LimitNOFILE"的服务时都会在设限那一步失败：
#
#   Failed to adjust resource limit RLIMIT_NOFILE: Operation not permitted
#   Failed at step LIMITS spawning ...: Operation not permitted
#   Main process exited, code=exited, status=205/LIMITS
#
# 这不是本脚本独有的坑，而是我们把 fs.nr_open 钉到 1048576 之后，会让别的调优脚本
# 早先写下的更大的 DefaultLimitNOFILE 变成非法值。实测踩过：某第三方 TCP 调优脚本
# 写了 DefaultLimitNOFILE=2097152，本脚本随后设 fs.nr_open=1048576，结果 logrotate /
# apt-daily / systemd-timedated / netfilter-persistent 等十个单元全部起不来；sing-box
# 反而幸免——因为它的 drop-in 与主 unit 自带 LimitNOFILE=1048576，没走默认值。
# 最难查的地方就在这里：代理本身一切正常，坏掉的是系统里其他所有服务。
#
# 所以设完 fs.nr_open 必须把 DefaultLimitNOFILE 拉回来对齐。写 system.conf.d/ 下的
# drop-in 而不是改 /etc/systemd/system.conf 本体：drop-in 优先级更高，别的脚本以后
# 再改主文件也覆盖不掉我们，且 sbbox tune off 删一个文件即可干净回滚。
align_default_nofile() {
  [ "$SERVICE_TYPE" = "systemd" ] || return 0

  local nr_open cur
  nr_open=$(sysctl_get fs.nr_open)
  case "$nr_open" in ''|*[!0-9]*) return 0 ;; esac

  cur=$(systemctl show -p DefaultLimitNOFILE --value 2>/dev/null)
  # infinity 同样越界（systemd 会解析成远大于 nr_open 的值）
  case "$cur" in
    ''|*[!0-9]*) ;;
    *) [ "$cur" -le "$nr_open" ] && return 0 ;;
  esac

  install -d -m 755 /etc/systemd/system.conf.d 2>/dev/null || {
    warn "无法创建 /etc/systemd/system.conf.d，跳过 DefaultLimitNOFILE 对齐"; return 0; }
  if ! cat > /etc/systemd/system.conf.d/10-sbbox-nofile.conf <<EOF
# 由 sbbox tune on 生成 / sbbox tune off 移除。
# 与 fs.nr_open 对齐——高于它会让 systemd 无法启动未自带 LimitNOFILE 的服务
# （报 205/LIMITS）。详见 sbbox.sh 中 align_default_nofile 的注释。
[Manager]
DefaultLimitNOFILE=${nr_open}
EOF
  then
    warn "写入 DefaultLimitNOFILE drop-in 失败"
    return 0
  fi
  systemctl daemon-reexec >/dev/null 2>&1 || warn "systemctl daemon-reexec 失败"
  info "已将 DefaultLimitNOFILE 由 ${cur:-未设置} 对齐到 fs.nr_open=${nr_open}（原值越界会导致服务报 205/LIMITS）"
}

# 默认路由所在网卡（QUIC 调优要作用在真正出流量的接口上）
default_nic() {
  ip route show default 2>/dev/null | awk '/default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

# 网卡层调优：全部 best-effort，失败只告警。
#   1) fq：QUIC 强依赖 pacing，sysctl 的 default_qdisc 不会改已存在的网卡
#   2) GRO/GSO：让内核合并/分片 UDP 段，高速 QUIC 下显著降低 CPU 占用
apply_nic_tuning() {
  local nic
  nic=$(default_nic)
  if [ -z "$nic" ]; then
    warn "未识别到默认路由网卡，跳过网卡层调优"
    return 0
  fi
  echo "$nic" > "$SB_HOME/nic" 2>/dev/null || true

  if command -v tc >/dev/null 2>&1; then
    local before_qd
    before_qd=$(tc qdisc show dev "$nic" 2>/dev/null | head -1 | awk '{print $2}')
    if tc qdisc replace dev "$nic" root fq >/dev/null 2>&1; then
      info "网卡 $nic 队列规则：${before_qd:-未知} → fq（QUIC pacing 生效）"
    else
      warn "网卡 $nic 设置 fq 失败（容器/受限环境常见），跳过"
    fi
  else
    warn "未安装 tc(iproute2)，跳过 fq 队列设置"
  fi

  if command -v ethtool >/dev/null 2>&1; then
    # 收发环形队列拉到硬件上限：高速 QUIC 是突发型流量，默认 ring（常见 256/512）
    # 在瞬时突发下会直接 rx_dropped，而这类丢包在 sing-box 日志里完全看不见。
    local rx_max tx_max
    rx_max=$(ethtool -g "$nic" 2>/dev/null | awk '/^RX:/{print $2; exit}')
    tx_max=$(ethtool -g "$nic" 2>/dev/null | awk '/^TX:/{print $2; exit}')
    if [ -n "$rx_max" ] && [ -n "$tx_max" ]; then
      ethtool -G "$nic" rx "$rx_max" tx "$tx_max" >/dev/null 2>&1 && \
        info "网卡 $nic 收发队列已拉满：rx=$rx_max tx=$tx_max"
    fi
    local ok=""
    ethtool -K "$nic" gro on  >/dev/null 2>&1 && ok="gro"
    ethtool -K "$nic" gso on  >/dev/null 2>&1 && ok="$ok gso"
    ethtool -K "$nic" tso on  >/dev/null 2>&1 && ok="$ok tso"
    if [ -n "$ok" ]; then
      info "网卡 $nic 已开启分片卸载：$ok"
    else
      warn "网卡 $nic 不支持或不允许修改卸载选项（虚拟网卡常见），跳过"
    fi
  else
    warn "未安装 ethtool，跳过 GRO/GSO（apt install ethtool 后重跑 sbbox tune on 可启用）"
  fi
}

apply_tuning() {
  local SYSCTL_APPLIED=() SYSCTL_SKIPPED=() TUNING_BBR_OK=false
  local MEM_MB CPU_CORES ARCH PAGE_SIZE MEM_PAGES
  local TUNE_TIER SOCK_MEM_MAX TCP_MEM_MAX NETDEV_BACKLOG CONNTRACK_MAX NETDEV_BUDGET
  local BEFORE_QDISC BEFORE_CC BEFORE_RMEM BEFORE_NOFILE AVAILABLE_CC

  try_sysctl() {
    if sysctl -w "${1}=${2}" >/dev/null 2>&1; then
      SYSCTL_APPLIED+=("${1} = ${2}")
    else
      SYSCTL_SKIPPED+=("$1")
    fi
  }

  # ---------- 机型探测：按内存分档 ----------
  MEM_MB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  CPU_CORES=$(nproc 2>/dev/null || echo 1)
  ARCH=$(uname -m 2>/dev/null || echo unknown)
  PAGE_SIZE=$(getconf PAGESIZE 2>/dev/null || echo 4096)
  MEM_PAGES=$(awk -v ps="$PAGE_SIZE" '/^MemTotal:/{printf "%d", $2*1024/ps}' /proc/meminfo 2>/dev/null || echo 262144)

  # 网卡链路速率（Mb/s）。内存分档决定的是「能不能吃得下」，真正决定 BDP 的是
  # 带宽 × RTT：24GB/4Gbps 与 24GB/200Mbps 需要的 socket 缓冲差一个数量级。
  local NIC_SPEED=0 _nic_probe
  _nic_probe=$(default_nic)
  if [ -n "$_nic_probe" ] && [ -r "/sys/class/net/$_nic_probe/speed" ]; then
    NIC_SPEED=$(cat "/sys/class/net/$_nic_probe/speed" 2>/dev/null)
    case "$NIC_SPEED" in ''|*[!0-9]*) NIC_SPEED=0 ;; esac   # 虚拟网卡常返回 -1/空
  fi

  if [ "$MEM_MB" -ge 16384 ]; then
    # 大内存档抬到 128MB：QUIC(Tuic/Hysteria2) 的 UDP socket 不像 TCP 那样自动
    # 扩缩，quic-go 直接按 rmem_max 上限申请缓冲，上限偏小会打印
    # "failed to sufficiently increase receive buffer size" 并压低吞吐。
    TUNE_TIER="large";  SOCK_MEM_MAX=134217728; TCP_MEM_MAX=33554432; NETDEV_BACKLOG=65536; CONNTRACK_MAX=1048576; NETDEV_BUDGET=6000
  elif [ "$MEM_MB" -ge 4096 ]; then
    TUNE_TIER="medium"; SOCK_MEM_MAX=33554432; TCP_MEM_MAX=16777216; NETDEV_BACKLOG=32768; CONNTRACK_MAX=262144; NETDEV_BUDGET=6000
  else
    TUNE_TIER="small";  SOCK_MEM_MAX=16777216; TCP_MEM_MAX=8388608;  NETDEV_BACKLOG=16384; CONNTRACK_MAX=0; NETDEV_BUDGET=""
  fi
  # 千兆以上链路把 socket 缓冲拉到 128MB：4Gbps × 200ms RTT 的 BDP 已接近 100MB，
  # 缓冲小于 BDP 时单条 TCP/QUIC 连接根本跑不满出口，与内存是否富余无关。
  # 需要 16GB 以上内存兜底，避免小内存机被一条连接的缓冲吃穿。
  if [ "$NIC_SPEED" -ge 1000 ] && [ "$MEM_MB" -ge 16384 ]; then
    SOCK_MEM_MAX=134217728; TCP_MEM_MAX=67108864; NETDEV_BACKLOG=131072; NETDEV_BUDGET=8000
    TUNE_TIER="large+${NIC_SPEED}M"
  fi
  info "机型: ${CPU_CORES} 核 / ${MEM_MB} MB / ${ARCH} / 链路 ${NIC_SPEED:-未知}Mb → 调优档位 ${TUNE_TIER}"

  # ---------- 调优前快照 ----------
  BEFORE_QDISC=$(sysctl_get net.core.default_qdisc)
  BEFORE_CC=$(sysctl_get net.ipv4.tcp_congestion_control)
  BEFORE_RMEM=$(sysctl_get net.core.rmem_max)
  BEFORE_NOFILE=$(ulimit -n 2>/dev/null || echo unknown)

  # ---------- BBR 能力探测 ----------
  AVAILABLE_CC=$(sysctl_get net.ipv4.tcp_available_congestion_control)
  if ! echo "$AVAILABLE_CC" | grep -qw bbr; then
    modprobe tcp_bbr >/dev/null 2>&1 || true
    AVAILABLE_CC=$(sysctl_get net.ipv4.tcp_available_congestion_control)
  fi
  if echo "$AVAILABLE_CC" | grep -qw bbr; then
    TUNING_BBR_OK=true
    try_sysctl net.core.default_qdisc fq
    try_sysctl net.ipv4.tcp_congestion_control bbr
  else
    warn "当前内核不提供 BBR（可用算法: ${AVAILABLE_CC:-未知}），保持系统默认拥塞算法"
  fi

  # ---------- 收发缓冲区（过 CDN 高 BDP 链路关键项） ----------
  try_sysctl net.core.rmem_max "$SOCK_MEM_MAX"
  try_sysctl net.core.wmem_max "$SOCK_MEM_MAX"
  if [ "$MEM_MB" -ge 4096 ]; then
    try_sysctl net.core.rmem_default 4194304
    try_sysctl net.core.wmem_default 4194304
    try_sysctl net.ipv4.udp_rmem_min 131072
    try_sysctl net.ipv4.udp_wmem_min 131072
  else
    try_sysctl net.core.rmem_default 1048576
    try_sysctl net.core.wmem_default 1048576
    try_sysctl net.ipv4.udp_rmem_min 16384
  try_sysctl net.ipv4.udp_wmem_min 16384
  fi
  try_sysctl net.ipv4.tcp_rmem "4096 262144 ${TCP_MEM_MAX}"
  try_sysctl net.ipv4.tcp_wmem "4096 262144 ${TCP_MEM_MAX}"
  try_sysctl net.ipv4.tcp_adv_win_scale 1
  try_sysctl net.ipv4.tcp_autocorking 1
  try_sysctl net.ipv4.tcp_comp_sack_nr 44
  try_sysctl net.ipv4.tcp_comp_sack_delay_ns 1000000
  try_sysctl net.ipv4.tcp_mem "$(( MEM_PAGES * 6 / 100 )) $(( MEM_PAGES * 8 / 100 )) $(( MEM_PAGES * 12 / 100 ))"
  # QUIC / HTTP3：Hysteria2 / Tuic 关键
  try_sysctl net.core.optmem_max 65536
  # udp_mem 是**全局**的 UDP 内存上限（页数）
  if [ "$MEM_MB" -ge 16384 ]; then
    try_sysctl net.ipv4.udp_mem "$(( MEM_PAGES * 4 / 100 )) $(( MEM_PAGES * 8 / 100 )) $(( MEM_PAGES * 16 / 100 ))"
  elif [ "$MEM_MB" -ge 1024 ]; then
    try_sysctl net.ipv4.udp_mem "$(( MEM_PAGES * 2 / 100 )) $(( MEM_PAGES * 4 / 100 )) $(( MEM_PAGES * 8 / 100 ))"
  fi

  # ---------- 队列与并发 ----------
  try_sysctl net.core.netdev_max_backlog "$NETDEV_BACKLOG"
  if [ -n "$NETDEV_BUDGET" ]; then
    try_sysctl net.core.netdev_budget "$NETDEV_BUDGET"
    try_sysctl net.core.netdev_budget_usecs 8000
  fi
  try_sysctl net.core.somaxconn 65535
  try_sysctl net.ipv4.tcp_max_syn_backlog "$NETDEV_BACKLOG"
  try_sysctl net.ipv4.tcp_max_tw_buckets 65536
  try_sysctl net.ipv4.ip_local_port_range "1024 65535"

  # conntrack 仅在模块已加载时调整
  if [ "$CONNTRACK_MAX" -gt 0 ] && [ -r /proc/sys/net/netfilter/nf_conntrack_max ]; then
    try_sysctl net.netfilter.nf_conntrack_max "$CONNTRACK_MAX"
    try_sysctl net.netfilter.nf_conntrack_tcp_timeout_established 3600
  fi

  # ---------- 连接建立与保持 ----------
  try_sysctl net.ipv4.tcp_fastopen 3
  try_sysctl net.ipv4.tcp_mtu_probing 1
  try_sysctl net.ipv4.tcp_slow_start_after_idle 0
  # 不缓存上条连接的 cwnd/ssthresh：跨境链路抖动大，缓存下来的坏指标会让
  # 后续新连接一开始就被压在低速率上
  try_sysctl net.ipv4.tcp_no_metrics_save 1
  try_sysctl net.ipv4.tcp_notsent_lowat 262144
  try_sysctl net.ipv4.tcp_syncookies 1
  try_sysctl net.ipv4.tcp_tw_reuse 1
  try_sysctl net.ipv4.tcp_ecn 2
  try_sysctl net.ipv4.tcp_ecn_fallback 1
  try_sysctl net.ipv4.tcp_retries2 8
  try_sysctl net.ipv4.tcp_syn_retries 4
  try_sysctl net.ipv4.tcp_rfc1337 1
  try_sysctl net.ipv4.tcp_fin_timeout 15
  try_sysctl net.ipv4.tcp_keepalive_time 600
  try_sysctl net.ipv4.tcp_keepalive_intvl 30
  try_sysctl net.ipv4.tcp_keepalive_probes 5

  # ---------- 内存行为 ----------
  if [ "$MEM_MB" -ge 4096 ]; then try_sysctl vm.swappiness 10; else try_sysctl vm.swappiness 30; fi
  try_sysctl vm.vfs_cache_pressure 50

  # ---------- 文件句柄 ----------
  try_sysctl fs.file-max 1048576
  try_sysctl fs.nr_open 1048576
  align_default_nofile

  # ---------- 落盘（只写成功项，避免重启后 sysctl --system 报错） ----------
  if [ "${#SYSCTL_APPLIED[@]}" -gt 0 ]; then
    {
      echo "# sbbox 流控调优，由 sbbox tune on 生成"
      echo "# 回滚: sbbox tune off"
      printf '%s\n' "${SYSCTL_APPLIED[@]}"
    } > "$SYSCTL_CONF" 2>/dev/null || warn "写入 $SYSCTL_CONF 失败，本次调优仅在重启前有效"
    sysctl --system >/dev/null 2>&1 || sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || \
      warn "sysctl 重载失败，参数已在运行时生效但可能无法持久化"
    info "已应用 ${#SYSCTL_APPLIED[@]} 项内核参数 → $SYSCTL_CONF"
  else
    warn "当前环境不允许修改任何 sysctl 参数（常见于 OpenVZ / 受限容器），已跳过内核调优"
  fi
  if [ "${#SYSCTL_SKIPPED[@]}" -gt 0 ]; then
    warn "以下参数当前内核不支持或只读，已跳过: ${SYSCTL_SKIPPED[*]}"
  fi

  # ---------- 进程句柄上限 ----------
  if [ -d /etc/security/limits.d ]; then
    cat > "$LIMITS_CONF" <<'LIMITSEOF' 2>/dev/null || warn "写入 $LIMITS_CONF 失败"
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITSEOF
    info "已写入句柄上限 → $LIMITS_CONF"
  fi

  # ---------- sing-box systemd drop-in ----------
  if [ "$SERVICE_TYPE" = "systemd" ]; then
    local dropin="10-sbbox.conf"
    local dir="/etc/systemd/system/${SB_SERVICE}.service.d"
    install -d -m 755 "$dir" 2>/dev/null || true
    cat > "${dir}/${dropin}" <<'DROPINEOF' 2>/dev/null || warn "写入 ${SB_SERVICE} drop-in 失败"
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
Environment="GOGC=200"
DROPINEOF
    local legacy="${dir}/override.conf"
    if [ -f "$legacy" ]; then
      if [ "$(grep -vE '^\s*(#|$)' "$legacy" | tr -d '[:space:]')" = "[Service]LimitNOFILE=1048576LimitNPROC=infinity" ] || \
         [ "$(grep -vE '^\s*(#|$)' "$legacy" | tr -d '[:space:]')" = "[Service]LimitNOFILE=1048576LimitNPROC=infinityEnvironment=\"GOGC=200\"" ]; then
        rm -f "$legacy"
      fi
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
    info "已为 sing-box 写入 systemd drop-in（LimitNOFILE=1048576 → ${dropin}）"
  elif [ -d /etc/conf.d ]; then
    grep -q '^rc_ulimit=' /etc/conf.d/sing-box 2>/dev/null || \
      echo 'rc_ulimit="-n 1048576"' >> /etc/conf.d/sing-box 2>/dev/null || true
    info "已为 sing-box 写入 rc_ulimit"
  fi

  # ---------- 网卡层：fq 队列 + UDP 分片卸载 ----------
  # net.core.default_qdisc=fq 只对**此后新建**的 qdisc 生效，已存在的网卡不会
  # 自动切换，所以必须显式对当前网卡再设一次，否则 QUIC 依赖的 pacing 拿不到。
  apply_nic_tuning
  echo "$(date +%s)" > "$SB_HOME/nic_tuned" 2>/dev/null || true

  # ---------- Before / After ----------
  echo ""
  echo -e "${CYAN}[+] 流控调优 Before / After${NC}"
  printf '  %-28s %-18s -> %s\n' "net.core.default_qdisc"          "${BEFORE_QDISC:--}" "$(sysctl_get net.core.default_qdisc)"
  printf '  %-28s %-18s -> %s\n' "net.ipv4.tcp_congestion_control" "${BEFORE_CC:--}"    "$(sysctl_get net.ipv4.tcp_congestion_control)"
  printf '  %-28s %-18s -> %s\n' "net.core.rmem_max"               "${BEFORE_RMEM:--}"  "$(sysctl_get net.core.rmem_max)"
  printf '  %-28s %-18s -> %s\n' "net.ipv4.tcp_fastopen"           "-"                  "$(sysctl_get net.ipv4.tcp_fastopen)"
  printf '  %-28s %-18s -> 重新登录后生效: %s\n' \
    "ulimit -n (当前 shell)" "${BEFORE_NOFILE}" "$(grep -E '^\*\s+soft\s+nofile' "$LIMITS_CONF" 2>/dev/null | awk '{print $4}' || echo 1048576)"
  echo ""
  info "BBR: $TUNING_BBR_OK；回滚请执行 sbbox tune off"
}

tune_off() {
  info "回滚 sbbox 流控调优……"
  # 网卡层：把队列规则交还给系统默认（default_qdisc 此时已随 sysctl 一起移除），
  # 卸载选项保持开启——GRO/GSO 属于网卡通用能力，关掉反而可能损害其他服务。
  if [ -s "$SB_HOME/nic" ] && command -v tc >/dev/null 2>&1; then
    local nic; nic=$(cat "$SB_HOME/nic")
    tc qdisc del dev "$nic" root >/dev/null 2>&1 && \
      info "网卡 $nic 队列规则已交还系统默认" || true
  fi
  rm -f "$SB_HOME/nic" "$SB_HOME/nic_tuned" 2>/dev/null
  rm -f "$SYSCTL_CONF" 2>/dev/null
  rm -f "$LIMITS_CONF" 2>/dev/null
  local dir="/etc/systemd/system/${SB_SERVICE}.service.d"
  rm -f "${dir}/10-sbbox.conf"
  local legacy="${dir}/override.conf"
  if [ -f "$legacy" ]; then
    if [ "$(grep -vE '^\s*(#|$)' "$legacy" | tr -d '[:space:]')" = "[Service]LimitNOFILE=1048576LimitNPROC=infinity" ] || \
       [ "$(grep -vE '^\s*(#|$)' "$legacy" | tr -d '[:space:]')" = "[Service]LimitNOFILE=1048576LimitNPROC=infinityEnvironment=\"GOGC=200\"" ]; then
      rm -f "$legacy"
    fi
  fi
  rmdir "$dir" 2>/dev/null || true
  # 与 fs.nr_open 对齐用的 DefaultLimitNOFILE drop-in 也一并移除（见
  # align_default_nofile）。删掉后 systemd 回到 /etc/systemd/system.conf 的值。
  if [ -f /etc/systemd/system.conf.d/10-sbbox-nofile.conf ]; then
    rm -f /etc/systemd/system.conf.d/10-sbbox-nofile.conf
    rmdir /etc/systemd/system.conf.d 2>/dev/null || true
    systemctl daemon-reexec >/dev/null 2>&1 || true
  fi
  sysctl --system >/dev/null 2>&1 || true
  info "已移除全部 sbbox 调优配置（BBR 等运行时参数将由系统默认接管）"
}

tune_show() {
  local MEM_MB CPU_CORES ARCH TUNE_TIER
  MEM_MB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  CPU_CORES=$(nproc 2>/dev/null || echo 1)
  ARCH=$(uname -m 2>/dev/null || echo unknown)
  if [ "$MEM_MB" -ge 16384 ]; then TUNE_TIER="large";
  elif [ "$MEM_MB" -ge 4096 ]; then TUNE_TIER="medium";
  else TUNE_TIER="small"; fi
  echo -e "${CYAN}[+] 流控状态${NC}"
  printf '  %-32s %s\n' "net.core.default_qdisc"          "$(sysctl_get net.core.default_qdisc)"
  printf '  %-32s %s\n' "net.ipv4.tcp_congestion_control" "$(sysctl_get net.ipv4.tcp_congestion_control)"
  printf '  %-32s %s\n' "net.core.rmem_max"               "$(sysctl_get net.core.rmem_max)"
  printf '  %-32s %s\n' "net.ipv4.tcp_fastopen"           "$(sysctl_get net.ipv4.tcp_fastopen)"
  printf '  %-32s %s\n' "机型 / 调优档位" "${CPU_CORES} 核 / ${MEM_MB} MB / ${ARCH} → ${TUNE_TIER}"
  # 网卡层：QUIC 的 pacing 取决于真实网卡的队列规则，而非 sysctl 的 default_qdisc
  local _nic; _nic=$(default_nic)
  if [ -n "$_nic" ]; then
    printf '  %-32s %s\n' "网卡 $_nic 队列规则" \
      "$(tc qdisc show dev "$_nic" 2>/dev/null | head -1 | awk '{print $2}' || echo n/a)"
    if command -v ethtool >/dev/null 2>&1; then
      printf '  %-32s %s\n' "网卡 $_nic 卸载(GRO/GSO)" \
        "$(ethtool -k "$_nic" 2>/dev/null | awk -F': ' '/^(generic-receive-offload|generic-segmentation-offload)/{printf "%s=%s ",substr($1,9,3),$2}' || echo n/a)"
    fi
  fi
  if [ -f "$SYSCTL_CONF" ]; then
    printf '  %-32s %s\n' "调优配置文件" "$SYSCTL_CONF（已启用）"
  else
    printf '  %-32s %s\n' "调优配置文件" "未启用（安装期默认已开启，如被移除请 sbbox res 重装）"
  fi
}

# ======================================================
# sing-box 服务端配置生成（三协议，Naiveproxy 服务端单入站同时支持 H2+H3）
# ======================================================
installsb() {
  echo ""
  echo "========= 启用 Sing-box 内核 ========="
  if [ ! -e "$SB_BIN" ]; then upsingbox; fi
  insuuid
  load_secrets

  # ---------- 证书准备 ----------
  if [ -n "$nvp" ] && [ -z "$alns" ] && [ -z "$ym" ]; then
    error "Naiveproxy 需要有效 TLS 证书。请设置 alns=1 与 ym=你的域名后再安装"
    exit 1
  fi
  if [ -n "$alns" ] || [ -n "$ym" ]; then
    if [ -n "$ym" ] && cert_matches_ym "$ym"; then
      # 重装 / 加装协议时不重复签发，避免撞上 Let's Encrypt 的签发频率限制
      info "检测到已有证书且域名匹配 ($ym)，跳过申请（如需续期请执行 sbbox cert renew）"
    else
      if [ -z "$ym" ]; then
        # 交互式输入域名，避免出现在命令行历史记录中
        if [ -t 0 ]; then
          printf '%s' "请输入证书域名（申请 Let's Encrypt 证书，需已解析到本机）：" >&2
          read -r ym
        fi
      fi
      if [ -z "$ym" ]; then
        error "启用证书功能需要提供证书域名。请在安装时输入，或用 ym=你的域名 指定"
        exit 1
      fi
      install_cert
    fi
    get_cert_paths
    if [ "$CERT_OK" != 1 ]; then
      warn "证书未就绪，Hysteria2/Tuic 将回退自签证书；Naive 不会启用"
      make_selfsigned
      get_cert_paths
    fi
  else
    make_selfsigned
    get_cert_paths
  fi

  # ---------- 端口分配 ----------
  assign_port() { # $1=name $2=env_port
    local name=$1 val=${2:-}
    if [ -z "$val" ] && [ ! -e "$SB_HOME/port_$name" ]; then
      val=$(shuf -i 10000-65535 -n 1)
      echo "$val" > "$SB_HOME/port_$name"
    elif [ -n "$val" ]; then
      echo "$val" > "$SB_HOME/port_$name"
    fi
    eval "port_$name=$(cat "$SB_HOME/port_$name")"
  }
  [ -n "$tup" ] && { assign_port tu "$port_tu"; echo "Tuic 端口：$port_tu"; open_port "$port_tu" udp; }
  [ -n "$hyp" ] && { assign_port hy2 "$port_hy2"; echo "Hysteria2 端口：$port_hy2"; open_port "$port_hy2" udp; }
  [ -n "$nvp" ] && { assign_port nv "$port_nv"; echo "Naiveproxy 端口：$port_nv"; open_port "$port_nv" tcp; open_port "$port_nv" udp; }


  # ---------- 生成 sb.json ----------
  # 日志隐私：sing-box 的 warn/info 级别会把失败连接的目标域名写进磁盘日志，
  # 等于在服务器上留了一份用户访问记录。默认收到 error，sblevel=off 则完全不落盘。
  local log_block
  case "$sblevel" in
    off|no|0|false)
      log_block='    "log": { "disabled": true },'
      ;;
    *)
      log_block="    \"log\": {
        \"disabled\": false,
        \"level\": \"$sblevel\",
        \"timestamp\": true,
        \"output\": \"$SB_LOG\"
    },"
      ;;
  esac
  cat > "$SB_CONF" <<EOF
{
$log_block
    "dns": {
        "servers": [
            { "type": "tls", "tag": "dns-secure", "server": "1.1.1.1" },
            { "type": "tls", "tag": "dns-backup", "server": "9.9.9.9" },
            { "type": "https", "tag": "dns-doh", "server": "1.1.1.1" }
        ],
        "strategy": "prefer_ipv4",
        "disable_cache": false
    },
    "inbounds": [
EOF

  # Tuic
  if [ -n "$tup" ]; then
    cat >> "$SB_CONF" <<EOF
        {
            "type": "tuic",
            "tag": "tuic-in",
            "listen": "::",
            "listen_port": $port_tu,
            "users": [
                { "uuid": "$uuid", "password": "$pw_tu" }
            ],
            "congestion_control": "bbr",
            "zero_rtt_handshake": true,
            "auth_timeout": "8s",
            "heartbeat": "10s",

            "tls": {
                "enabled": true,
                "alpn": [ "h3" ],
                "certificate_path": "$cert_path",
                "key_path": "$key_path"
            }
        },
EOF
  fi

  # Hysteria2
  if [ -n "$hyp" ]; then
    # 拥塞控制二选一，两者互斥（官方文档：设了带宽上限即禁止客户端用 BBR）：
    #   不设带宽   + ignore_client_bandwidth=true → 客户端统一用 BBR（稳、公平、默认）
    #   设了带宽上限                              → 走 Hysteria Brutal CC
    # Brutal 在高丢包跨境链路上吞吐显著更高，但会激进抢占带宽、特征更明显，
    # 且必须填写接近真实的带宽值，填错反而更慢，故设为可选。
    if [ -n "$hyup" ] && [ -n "$hydown" ]; then
      hy_bw="            \"up_mbps\": $hyup,
            \"down_mbps\": $hydown,"
      info "Hysteria2 拥塞控制：Brutal（上行 ${hyup}Mbps / 下行 ${hydown}Mbps）"
    else
      # 不设带宽 → 客户端统一走 BBR。bbr_profile 是 sing-box 1.14 新增项，
      # 不写等价于 standard；显式写出来是为了这条策略不随上游默认值漂移。
      #   conservative 更让路、aggressive 更抢占。默认 standard：目标是长期
      #   稳定吞吐，而不是单次 Speedtest 峰值。
      hy_bw="            \"ignore_client_bandwidth\": true,
            \"bbr_profile\": \"standard\",
            \"brutal_debug\": false,"
    fi
    # salamander 混淆：把 QUIC 握手特征打乱，主动探测与协议识别更难命中。
    # 客户端必须同样配置，故分享链接/订阅会带上 obfs 参数。
    # 默认开启；显式关闭用 hyobfs=0/no/off/false（空串也视为关闭）
    case "$hyobfs" in
      ""|0|no|off|false|NO|OFF|FALSE) hyobfs_on="" ;;
      *) hyobfs_on=1 ;;
    esac
    if [ -n "$hyobfs_on" ]; then
      # obfs 密码必须独立于认证密码：两者相同的话，一份泄露就同时破掉混淆层与认证层
      if [ -z "$hyobfs_pw" ]; then
        [ -s "$SB_SEC_DIR/hy2_obfs" ] || gen_secret > "$SB_SEC_DIR/hy2_obfs"
        chmod 600 "$SB_SEC_DIR/hy2_obfs" 2>/dev/null
        hyobfs_pw=$(cat "$SB_SEC_DIR/hy2_obfs")
      fi
      echo "$hyobfs_pw" > "$SB_HOME/hyobfs_pw"
      chmod 600 "$SB_HOME/hyobfs_pw" 2>/dev/null
      hy_obfs="            \"obfs\": { \"type\": \"salamander\", \"password\": \"$hyobfs_pw\" },"
      info "Hysteria2 已启用 salamander 混淆"
    else
      hy_obfs=""
      rm -f "$SB_HOME/hyobfs_pw"
    fi
    # 主动探测防护：静态 404 页面对探测者是明显信号——一个只回 404、
    # 没有任何真实资源的 HTTPS 端口本身就可疑。反代一个真站点后，
    # 未通过认证的 HTTP 请求会拿到该站点的真实响应，探测结果与普通反代无异。
    case "$hymask" in
      none|off|0|"")
        hy_mask='            "masquerade": {
                "type": "string",
                "status_code": 404,
                "headers": { "Content-Type": "text/html" },
                "content": "<html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center></body></html>"
            },' ;;
      *)
        hy_mask="            \"masquerade\": {
                \"type\": \"proxy\",
                \"url\": \"$hymask\",
                \"rewrite_host\": true
            }," ;;
    esac
    cat >> "$SB_CONF" <<EOF
        {
            "type": "hysteria2",
            "tag": "hy2-in",
            "listen": "::",
            "listen_port": $port_hy2,
            "users": [
                { "password": "$pw_hy" }
            ],
$hy_bw
${hy_obfs:+$hy_obfs}
$hy_mask
            "tls": {
                "enabled": true,
                "alpn": [ "h3" ],
                "certificate_path": "$cert_path",
                "key_path": "$key_path"
            }
        },
EOF
  fi

  # Naiveproxy
  if [ -n "$nvp" ] && [ "$CERT_OK" = 1 ]; then
    cat >> "$SB_CONF" <<EOF
        {
            "type": "naive",
            "tag": "naive-in",
            "listen": "::",
            "listen_port": $port_nv,
            "tcp_fast_open": true,
            "quic_congestion_control": "bbr",
            "users": [
                { "username": "$nv_user", "password": "$nv_pw" }
            ],
            "tls": {
                "enabled": true,
                "min_version": "1.2",
                "alpn": [ "h3", "h2", "http/1.1" ],
                "certificate_path": "$CERT_DIR/fullchain.cer",
                "key_path": "$CERT_DIR/private.key"
            }
        },
EOF
  fi

  # 收尾：outbounds + route
  # 出站防护：
  #   1) 私网/回环一律拒绝 —— 否则任何持有节点凭据的人都能拿这台机器当跳板，
  #      打内网服务与 169.254.169.254 云元数据接口（可读出实例凭据）。
  #   2) 邮件与 SMB 端口拒绝 —— 凭据外泄后最常见的滥用是发垃圾邮件，
  #      直接导致 VPS 被投诉停机。确需用代理发信时 blkport=0 关闭。
  local route_rules='            { "action": "reject", "ip_is_private": true }'
  case "$blkport" in
    0|no|off|false) : ;;
    *) route_rules="$route_rules,
            { \"action\": \"reject\", \"port\": [ 25, 135, 137, 138, 139, 445, 465, 587 ] }" ;;
  esac
  route_rules="$route_rules,
            { \"action\": \"reject\", \"protocol\": [ \"bittorrent\" ] }"
  sed -i '${s/,$//}' "$SB_CONF"
  cat >> "$SB_CONF" <<EOF
    ],
    "outbounds": [
        { "type": "direct", "tag": "direct", "tcp_fast_open": true, "tcp_multi_path": true, "udp_fragment": true }
    ],
    "route": {
        "rules": [
$route_rules
        ],
        "final": "direct",
        "default_domain_resolver": "dns-secure"
    }
}
EOF
  info "服务端配置已生成：$SB_CONF"

  # 配置自检：把 JSON/字段错误在安装期暴露出来，而不是留到服务静默启动失败
  if ! "$SB_BIN" check -c "$SB_CONF" 2>"$SB_HOME/check.err"; then
    error "sing-box 配置校验失败，服务不会启动。错误信息："
    cat "$SB_HOME/check.err" >&2
    error "配置文件保留在 $SB_CONF 供排查"
    exit 1
  fi
  info "配置校验通过"

  # sb.json 含全部明文密码，证书私钥同理；仅属主可读
  chmod 600 "$SB_CONF" 2>/dev/null
  chmod 700 "$CERT_DIR" 2>/dev/null
  chmod 600 "$CERT_DIR"/private.key "$CERT_DIR"/fullchain.cer 2>/dev/null
  chmod 600 "$SB_HOME/uuid" "$SB_HOME/selfsigned.key" 2>/dev/null
}

# ======================================================
# 客户端节点链接生成 + 聚合订阅
# ======================================================
# 证书 SHA-256 指纹（hex，无冒号）——v2rayN 固定证书/naive 用
_cert_fp() {
  [ "$CERT_OK" = 1 ] && [ -s "$CERT_DIR/fullchain.cer" ] || return 0
  openssl x509 -in "$CERT_DIR/fullchain.cer" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | tr -d ':'
}

gen_client() {
  # add：有真实证书用域名（TLS 校验通过），否则用 IP
  if [ "$CERT_OK" = 1 ] && [ -n "$ym" ]; then add="$ym"; else add="$server_ip"; fi
  # sni：有证书用证书域名，否则用伪装域名
  if [ "$CERT_OK" = 1 ] && [ -n "$ym" ]; then sni="$ym"; else sni="www.bing.com"; fi
  if [ "$CERT_OK" = 1 ]; then msins=false; jhins=0; else msins=true; jhins=1; fi

  sxname="${name:+${name}-}"

  # Hysteria2 salamander 混淆：服务端开了客户端就必须跟着开，
  # 这里按服务端落盘的密码文件推导各客户端格式的片段。
  hyobfs_json="" ; hyobfs_yaml=""
  if [ -s "$SB_HOME/hyobfs_pw" ]; then
    _obfs_pw=$(cat "$SB_HOME/hyobfs_pw")
    hyobfs_json="
        \"obfs\": { \"type\": \"salamander\", \"password\": \"$_obfs_pw\" },"
    hyobfs_yaml="
    obfs: salamander
    obfs-password: $_obfs_pw"
  fi
  : > "$SB_LINK"

  if [ -n "$tup" ]; then
    # v2rayN 通用 URL 参数：fp=Fingerprint、pcs=固定证书(SHA-256 指纹)、ech=ECH config list。
    # 指纹从真实证书算出，导入后「固定证书」字段显示已设置。
    # ECH 默认不加：Encrypted ClientHello 需要服务端(CDN)配置 ECH keys，直连 VPS 没有，
    # 填了反而会导致握手失败。确有必要时用 tuech=1 tuech_config=<base64> 自定义。
    local tuic_fp="" tuic_ech=""
    [ "$CERT_OK" = 1 ] && tuic_fp="&fp=chrome&pcs=$(_cert_fp)"
    case "$tuech" in
      1|on|yes|true) [ -n "$tuech_config" ] && tuic_ech="&ech=$(printf %s "$tuech_config" | base64 | tr -d '
')" ;;
    esac
    tuic_link="tuic://$uuid:$pw_tu@$add:$port_tu?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&insecure=$jhins&allowInsecure=$jhins&allow_insecure=$jhins$tuic_fp$tuic_ech#${sxname}tuic-$hostname_s"
    echo "$tuic_link" >> "$SB_LINK"
    echo "💣【 Tuic 】节点信息如下："
    echo "$tuic_link"; echo
  fi

  if [ -n "$hyp" ]; then
    local hyps=""
    if [ -n "$hyjpt" ]; then
      hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$port_hy2" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
      if [ -n "$hy2_ports" ]; then
        echo "Hysteria2 跳跃端口已开启：$hy2_ports"
        hyps="&mport=$hy2_ports"
      fi
    fi
    local sha pinsha=""
    sha=$(cat "$SB_HOME/SHA256.txt" 2>/dev/null)
    [ -n "$sha" ] && pinsha="&pinSHA256=$sha"
    # 服务端启用 salamander 时，客户端必须带相同 obfs 参数，否则握手不上
    local hyobfs_q=""
    if [ -s "$SB_HOME/hyobfs_pw" ]; then
      hyobfs_q="&obfs=salamander&obfs-password=$(cat "$SB_HOME/hyobfs_pw")"
    fi
    hy2_link="hysteria2://$pw_hy@$add:$port_hy2?security=tls&alpn=h3&insecure=$jhins&allowInsecure=$jhins$hyps&sni=$sni$pinsha$hyobfs_q#${sxname}hy2-$hostname_s"
    echo "$hy2_link" >> "$SB_LINK"
    echo "💣【 Hysteria2 】节点信息如下："
    echo "$hy2_link"; echo
  fi

  if [ -n "$nvp" ] && [ "$CERT_OK" = 1 ]; then
    # Naiveproxy 同一入站同时服务 H2 与 H3，但不同客户端认的 URL scheme 不同：
    #   naive+https:// / naive+quic://  —— v2rayN、NekoBox 等
    #   http2://       / http3://       —— Shadowrocket（认不出 naive+ 前缀）
    # 两套都放进订阅，各客户端各取所需。
    # UDP over TCP 默认关闭，链接直接带 udp-over-tcp=true 让能解析的客户端默认开启。
    # 注意：v2rayN 的 naive 节点**不解析**该 URL 参数（源码里 Uot 仅 UI 手动开关），
    # 因此 v2rayN 里仍需在节点属性手动勾选一次 UDP over TCP；sing-box 客户端则确定开启。
    # H3(naive+quic/http3) 拥塞控制用 congestion_control=bbr（H3 默认本就是 bbr）。
    #
    # 固定证书：v2rayN 解析 pcs= 参数填充节点「固定证书」字段（CertSha，证书 SHA-256 指纹）。
    # 不加的话导入后显示「证书未设置」。有真实证书时算指纹带上。
    local nv_pcs=""
    if [ "$CERT_OK" = 1 ] && [ -s "$CERT_DIR/fullchain.cer" ]; then
      local _fp
      _fp=$(openssl x509 -in "$CERT_DIR/fullchain.cer" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | tr -d ':')
      [ -n "$_fp" ] && nv_pcs="&pcs=$_fp"
    fi
    # 默认优先使用 QUIC (HTTP/3) 极速通道，同时保留 HTTP/2 供客户端兼容与回退
    nv1_link="naive+quic://$nv_user:$nv_pw@$add:$port_nv?congestion_control=bbr&security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1&uot=1$nv_pcs#${sxname}naive-h3-$hostname_s"
    nv2_link="naive+https://$nv_user:$nv_pw@$add:$port_nv?quic=1&congestion_control=bbr&security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1&uot=1$nv_pcs#${sxname}naive-h2-$hostname_s"
    nv3_link="http3://$nv_user:$nv_pw@$add:$port_nv?congestion_control=bbr&security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1&uot=1$nv_pcs#${sxname}naive-h3-rocket-$hostname_s"
    nv4_link="http2://$nv_user:$nv_pw@$add:$port_nv?quic=1&congestion_control=bbr&security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1&uot=1$nv_pcs#${sxname}naive-h2-rocket-$hostname_s"

    for l in "$nv1_link" "$nv2_link" "$nv3_link" "$nv4_link"; do
      echo "$l" >> "$SB_LINK"
    done
    echo "💣【 Naiveproxy 】节点信息如下（前两条 v2rayN/NekoBox，后两条 Shadowrocket）："
    echo "$nv1_link"; echo "$nv2_link"; echo "$nv3_link"; echo "$nv4_link"; echo
  fi

  # ---------- sing-box 客户端聚合配置 ----------
  gen_client_sbox
  # ---------- Clash / Mihomo 聚合配置 ----------
  gen_client_clash
  info "节点信息已保存：$SB_LINK"
  info "sing-box 客户端配置：$SB_HOME/sbox_client.json"
  info "Clash/Mihomo 客户端配置：$SB_HOME/clmi.yaml"

  # ---------- v2rayN / 通用订阅 ----------
  gen_sub
}

# ======================================================
# 订阅：base64 节点列表 + 本机 HTTP 托管（v2rayN 可直接导入）
# ======================================================
gen_sub() {
  [ -n "$sub" ] || return 0
  [ -s "$SB_LINK" ] || { warn "无节点可生成订阅"; return 0; }

  # 订阅令牌：独立随机值，**不复用 uuid**。
  # uuid 同时是各协议的连接密码，若拿它当令牌，订阅 URL（明文 HTTP）一旦泄露
  # 就等同于泄露代理密码。已有安装沿用旧令牌，避免客户端订阅地址失效。
  local token
  if [ -n "$subid" ]; then
    token="$subid"
  elif [ -s "$SB_HOME/subtoken" ]; then
    token=$(cat "$SB_HOME/subtoken")
  else
    token=$("$SB_BIN" generate rand --hex 16 2>/dev/null || openssl rand -hex 16 2>/dev/null)
    [ -n "$token" ] || token=$(head -c32 /dev/urandom | od -An -tx1 | tr -d ' 
')
  fi
  echo "$token" > "$SB_HOME/subtoken"
  chmod 600 "$SB_HOME/subtoken" 2>/dev/null

  # 订阅端口：默认随机高位端口，可用 subport= 固定
  if [ -z "$subport" ]; then
    subport=$(cat "$SB_HOME/subport" 2>/dev/null || shuf -i 10000-65535 -n 1)
  fi
  echo "$subport" > "$SB_HOME/subport"

  mkdir -p "$SUB_DIR"
  # 空 index.html：让 HTTP 服务返回它而不是列出目录，避免令牌文件名被直接看到
  : > "$SUB_DIR/index.html"
  # 默认把全部节点（含 Naiveproxy H2/H3）打进订阅。
  # 若客户端不支持 naive+ 链接（如某些 v2rayN 版本），可加 sub_nonaive=1 剔除。
  if [ -n "$sub_nonaive" ]; then
    # naive 有两套 scheme：naive+https/naive+quic 与 Shadowrocket 的 http2/http3
    grep -Ev '^(naive\+|http2://|http3://)' "$SB_LINK" > "$SB_HOME/.sub.plain"
  else
    cp "$SB_LINK" "$SB_HOME/.sub.plain"
  fi
  if [ ! -s "$SB_HOME/.sub.plain" ]; then
    warn "无节点可生成订阅（nodes.txt 为空或全部被 sub_nonaive 剔除）"
    rm -f "$SB_HOME/.sub.plain"
    return 0
  fi
  # v2rayN 订阅格式 = 分享链接换行拼接后的 base64（不能有换行）
  base64 < "$SB_HOME/.sub.plain" | tr -d '\n' > "$SUB_DIR/$token"
  rm -f "$SB_HOME/.sub.plain"

  start_sub_server

  local subhost="$server_ip"
  case "$subhost" in *:*) subhost="[$subhost]" ;; esac   # IPv6 需方括号
  echo ""
  echo "==========================================================="
  info "v2rayN / 通用订阅地址（复制到客户端「订阅设置」）："
  echo "http://$subhost:$subport/$token"
  echo "==========================================================="
  echo -e "  ${CYAN}[提示]${NC} Clash/Mihomo 请直接导入配置文件: ${YELLOW}$SB_HOME/clmi.yaml${NC}"
  echo -e "  ${CYAN}[提示]${NC} sing-box 客户端请导入配置文件: ${YELLOW}$SB_HOME/sbox_client.json${NC}"
  echo "==========================================================="
  warn "订阅经明文 HTTP 提供，令牌即密码，请勿外泄；不用时执行 sbbox sub off"
}

start_sub_server() {
  local runner=""
  if command -v python3 >/dev/null 2>&1; then
    # 绑定 0.0.0.0（IPv4）而非 ::，纯 IPv4 VPS 上没有 IPv6 地址，绑定 :: 会启动失败
    runner="python3 -m http.server $subport --bind 0.0.0.0 --directory $SUB_DIR"
    SUB_MARK="python3 -m http.server $subport"
  elif command -v busybox >/dev/null 2>&1; then
    runner="busybox httpd -f -p $subport -h $SUB_DIR"
    SUB_MARK="busybox httpd -f -p $subport"
  else
    warn "未找到 python3 或 busybox，无法启动订阅服务；请手动分发 $SUB_DIR/$(cat "$SB_HOME/subtoken" 2>/dev/null)"
    return 1
  fi

  # 放行订阅端口防火墙
  open_port "$subport" tcp

  # 清理旧进程避免端口占用冲突
  pkill -f "python3 -m http.server $subport" >/dev/null 2>&1
  pkill -f "busybox httpd -f -p $subport" >/dev/null 2>&1
  [ -f "$SB_HOME/sub.pid" ] && kill "$(cat "$SB_HOME/sub.pid")" 2>/dev/null && rm -f "$SB_HOME/sub.pid"

  if [ "$SERVICE_TYPE" = "systemd" ] && [ "$IS_ROOT" = 1 ]; then
    cat > /etc/systemd/system/sbbox-sub.service <<EOF
[Unit]
Description=sbbox subscription server
After=network.target

[Service]
Type=simple
ExecStart=$runner
Restart=always
RestartSec=3s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable sbbox-sub >/dev/null 2>&1
    systemctl restart sbbox-sub >/dev/null 2>&1
  else
    nohup $runner >/dev/null 2>&1 &
    echo $! > "$SB_HOME/sub.pid"
    if [ "$SERVICE_TYPE" = "cron" ]; then
      crontab -l > /tmp/sbbox_sub_cron.tmp 2>/dev/null || true
      sed -i '/sbbox-sub\|http.server\|httpd -f/d' /tmp/sbbox_sub_cron.tmp 2>/dev/null || true
      echo "@reboot sleep 12 && nohup $runner >/dev/null 2>&1 &" >> /tmp/sbbox_sub_cron.tmp
      crontab /tmp/sbbox_sub_cron.tmp >/dev/null 2>&1
      rm -f /tmp/sbbox_sub_cron.tmp
    fi
  fi

  sleep 1
  # 确认服务运行状态
  if ([ "$SERVICE_TYPE" = "systemd" ] && systemctl is-active --quiet sbbox-sub 2>/dev/null) || pgrep -f "$SUB_MARK" >/dev/null 2>&1; then
    info "订阅服务已启动（端口 $subport）"
  else
    warn "订阅服务启动可能失败（端口 $subport 可能被占用），执行 sbbox doctor 排查"
  fi
}

stop_sub_server() {
  if [ "$SERVICE_TYPE" = "systemd" ] && [ "$IS_ROOT" = 1 ]; then
    systemctl stop sbbox-sub >/dev/null 2>&1
    systemctl disable sbbox-sub >/dev/null 2>&1
    rm -f /etc/systemd/system/sbbox-sub.service
    systemctl daemon-reload >/dev/null 2>&1
  fi
  [ -f "$SB_HOME/sub.pid" ] && kill "$(cat "$SB_HOME/sub.pid")" 2>/dev/null
  pkill -f "python3 -m http.server" >/dev/null 2>&1
  pkill -f "busybox httpd -f -p" >/dev/null 2>&1
  crontab -l > /tmp/sbbox_sub_cron.tmp 2>/dev/null || true
  sed -i '/sbbox-sub\|http.server\|httpd -f/d' /tmp/sbbox_sub_cron.tmp 2>/dev/null || true
  crontab /tmp/sbbox_sub_cron.tmp >/dev/null 2>&1
  rm -f /tmp/sbbox_sub_cron.tmp
  rm -f "$SB_HOME/sub.pid"
  info "订阅服务已停止"
}

# sbbox sub [show|off]
cmd_sub() {
  case "${1:-show}" in
    show)
      local token port subhost
      token=$(cat "$SB_HOME/subtoken" 2>/dev/null)
      port=$(cat "$SB_HOME/subport" 2>/dev/null)
      subhost=$(cat "$SB_HOME/server_ip.log" 2>/dev/null)
      if [ -z "$token" ] || [ -z "$port" ]; then
        warn "未启用订阅。安装时加 sub=1，或执行：sub=1 sbbox list"
        return 0
      fi
      open_port "$port" tcp
      case "$subhost" in *:*) subhost="[$subhost]" ;; esac
      if ([ "$SERVICE_TYPE" = "systemd" ] && systemctl is-active --quiet sbbox-sub 2>/dev/null) || pgrep -f "http.server $port" >/dev/null 2>&1 || pgrep -f "httpd -f -p $port" >/dev/null 2>&1; then
        info "订阅服务：运行中"
      else
        warn "订阅服务：未运行，正在重新拉起……"
        sub=1 subport="$port" subid="$token" start_sub_server
      fi
      echo ""
      echo "==========================================================="
      info "v2rayN / 通用订阅地址（复制到客户端「订阅设置」）："
      echo "http://$subhost:$port/$token"
      echo "==========================================================="
      echo -e "  ${CYAN}[提示]${NC} Clash/Mihomo 请直接导入配置文件: ${YELLOW}$SB_HOME/clmi.yaml${NC}"
      echo -e "  ${CYAN}[提示]${NC} sing-box 客户端请导入配置文件: ${YELLOW}$SB_HOME/sbox_client.json${NC}"
      echo "==========================================================="
      ;;
    off) stop_sub_server ;;
    *) echo "用法: sbbox sub [show|off]" ;;
  esac
}


gen_client_sbox() {
  local ob=() tags=() json_file="$SB_HOME/sbox_client.json"

  # Tuic 的 UDP 中继二选一，官方文档标明两者互斥：
  #   udp_relay_mode=native  原生 UDP，保留 UDP 语义、不保证可靠（默认）
  #   udp_over_stream=true   把 UDP 封进 QUIC 流，可靠有序
  # 文档原文：该模式「在正常 UDP 代理场景下没有正面效果，只应用于中继流式
  # UDP 流量（基本上就是 QUIC 流）」。对 QUIC 类站点可能有益，对普通 UDP
  # 会引入队头阻塞。默认按需开启，tuicuos=0 可退回 native。
  local tuic_udp
  case "$tuicuos" in
    ""|0|no|off|false) tuic_udp='"udp_relay_mode": "native",' ;;
    *)                 tuic_udp='"udp_over_stream": true,' ;;
  esac

  # Tuic TLS 加固：uTLS 指纹 + 证书公钥 SHA-256 固定（防中间人）
  #   utls.fingerprint 只对 TCP 的 ClientHello 生效；QUIC 的 TLS 握手由
  #   quic-go 内部完成，uTLS 通常不接管——对 Tuic 更多是防御纵深。
  #   certificate_public_key_sha256 是证书验证层，QUIC 同样适用，价值更大。
  #   tuils=0 可整体关闭；公钥固定仅在持有真实证书（CERT_OK=1）时生成，
  #   且需要 sing-box >= 1.13.0。
  local tuic_tls_extra sb64
  tuic_tls_extra=""
  case "$tuils" in
    ""|0|no|off|false) : ;;
    *)
      # uTLS 只作用于 TCP 上的 TLS 握手，Tuic 跑在 QUIC 上：
      # 加了它 sing-box 客户端会在建连时直接报 "unsupported usage for uTLS"，
      # 该出站完全不可用（sing-box check 不会报错，只在实际连接时炸）。
      # 因此 Tuic 的 TLS 加固只保留证书公钥固定。
      tuic_tls_extra=''
      if [ "$CERT_OK" = 1 ] && [ -s "$CERT_DIR/fullchain.cer" ]; then
        sb64=$(openssl x509 -in "$CERT_DIR/fullchain.cer" -pubkey -noout 2>/dev/null               | openssl pkey -pubin -outform DER 2>/dev/null               | openssl dgst -sha256 -binary 2>/dev/null               | openssl base64 2>/dev/null)
        [ -n "$sb64" ] && tuic_tls_extra="$tuic_tls_extra, \"certificate_public_key_sha256\": [\"$sb64\"]"
      fi
      ;;
  esac

  if [ -n "$tup" ]; then
    ob+=('{
        "type": "tuic",
        "tag": "tuic",
        "server": "'"$add"'",
        "server_port": '"$port_tu"',
        "uuid": "'"$uuid"'",
        "password": "'"$pw_tu"'",
        "congestion_control": "bbr",
        '"$tuic_udp"'
        "zero_rtt_handshake": true,
        "heartbeat": "10s",
        "tls": { "enabled": true, "server_name": "'"$sni"'", "insecure": '"$msins"', "alpn": ["h3"]'"$tuic_tls_extra"' }
    }')
    tags+=("tuic")
  fi

  if [ -n "$hyp" ]; then
    local hy_ports_json=""
    if [ -n "$hyjpt" ]; then
      # 支持 sing-box 1.14 端口跳跃与随机化抖动 hop_interval_max（单端口自动补齐为 start:end 格式）
      local formatted_jpt="" item
      for item in $(echo "$hyjpt" | tr ',' ' '); do
        case "$item" in
          *:*) formatted_jpt="$formatted_jpt \"$item\"," ;;
          *)   formatted_jpt="$formatted_jpt \"${item}:${item}\"," ;;
        esac
      done
      formatted_jpt="${formatted_jpt%,}"
      hy_ports_json="\"server_ports\": [$formatted_jpt], \"hop_interval\": \"30s\", \"hop_interval_max\": \"90s\","
    fi
    ob+=('{
        "type": "hysteria2",
        "tag": "hysteria2",
        "server": "'"$add"'",
        "server_port": '"$port_hy2"',
        '"$hy_ports_json"'
        "password": "'"$pw_hy"'",'"$hyobfs_json"'
        "tls": { "enabled": true, "server_name": "'"$sni"'", "insecure": '"$msins"', "alpn": ["h3"] }
    }')
    tags+=("hysteria2")
  fi

  # naive 出站需要 libcronet.so 与 sing-box 二进制同目录（官方 tarball 已附带，
  # 本脚本安装时会一并保留）。缺库时该出站会以 "cronet: library not found" 启动失败，
  # 故客户端若用自行编译/精简版内核，需自行补上该库或删掉这条出站。
  if [ -n "$nvp" ] && [ "$CERT_OK" = 1 ]; then
    # 默认 naive 出站开启 QUIC (H3)+bbr 与多路径 TCP (MPTCP)
    ob+=('{
        "type": "naive",
        "tag": "naive-h3",
        "server": "'"$add"'",
        "server_port": '"$port_nv"',
        "username": "'"$nv_user"'",
        "password": "'"$nv_pw"'",
        "tcp_fast_open": true,
        "tcp_multi_path": true,
        "udp_over_tcp": true,
        "quic": true,
        "quic_congestion_control": "bbr",
        "tls": { "enabled": true, "insecure": false, "server_name": "'"$sni"'" }
    }')
    tags+=("naive-h3")
    # 独立 H2(TCP) 出站：供需要 TCP / HTTP2 的环境回退使用（默认开启 quic 与 bbr）
    ob+=('{
        "type": "naive",
        "tag": "naive",
        "server": "'"$add"'",
        "server_port": '"$port_nv"',
        "username": "'"$nv_user"'",
        "password": "'"$nv_pw"'",
        "tcp_fast_open": true,
        "tcp_multi_path": true,
        "udp_over_tcp": true,
        "quic": true,
        "quic_congestion_control": "bbr",
        "tls": { "enabled": true, "insecure": false, "server_name": "'"$sni"'" }
    }')
    tags+=("naive")

  fi

  if [ "${#tags[@]}" -eq 0 ]; then
    warn "未生成任何客户端协议配置（服务器端可能未启用对应协议）"
    return
  fi

  # 组装 outbounds：协议节点 + direct + auto(urltest)
  local i taglist="" sel=""
  for i in "${!ob[@]}"; do
    sel="${sel}${ob[$i]}"
    [ $((i+1)) -lt "${#ob[@]}" ] && sel="$sel,"
  done
  for t in "${tags[@]}"; do
    taglist="$taglist \"$t\","
  done
  taglist="${taglist%,}"

  cat > "$json_file" <<EOF
{
    "log": { "level": "warn", "timestamp": true },
    "dns": {
        "servers": [
            { "tag": "remote", "type": "https", "server": "1.1.1.1", "detour": "auto" },
            { "tag": "local", "type": "udp", "server": "223.5.5.5" }
        ],
        "rules": [ { "rule_set": "geosite-cn", "server": "local" } ],
        "strategy": "prefer_ipv4",
        "final": "remote"
    },
    "outbounds": [
$sel,
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "urltest",
            "tag": "auto",
            "outbounds": [$taglist],
            "url": "http://www.gstatic.com/generate_204",
            "interval": "10m",
            "tolerance": 50
        }
    ],
    "route": {
        "auto_detect_interface": true,
        "default_domain_resolver": { "server": "local" },
        "rules": [
            {
                "action": "sniff",
                "timeout": "300ms"
            },
            { "rule_set": "geosite-cn", "outbound": "direct" }
        ],
        "rule_set": [
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs"
            }
        ],
        "final": "auto"
    }
}
EOF
  info "sing-box 客户端配置已生成：$json_file"
}

gen_client_clash() {
  local proxies="" groups="" rules=""
  local p
  if [ -n "$tup" ]; then
    proxies="$proxies
  - name: tuic-$hostname_s
    server: $add
    port: $port_tu
    type: tuic
    uuid: $uuid
    password: $pw_tu
    alpn: [h3]
    reduce-rtt: true
    heartbeat-interval: 10000
    request-timeout: 8000
    udp-relay-mode: native
    congestion-controller: bbr
    sni: $sni
    skip-cert-verify: $msins"

    groups="$groups
      - tuic-$hostname_s"
  fi
  if [ -n "$hyp" ]; then
    local hy_ports_yaml=""
    [ -n "$hyjpt" ] && hy_ports_yaml="
    ports: $hyjpt"
    proxies="$proxies
  - name: hysteria2-$hostname_s
    server: $add
    port: $port_hy2
    type: hysteria2
    password: $pw_hy
    alpn: [h3]$hyobfs_yaml$hy_ports_yaml
    sni: $sni
    skip-cert-verify: $msins"
    groups="$groups
      - hysteria2-$hostname_s"
  fi
  if [ -n "$nvp" ] && [ "$CERT_OK" = 1 ]; then
    proxies="$proxies
  - name: naive-$hostname_s
    server: $add
    port: $port_nv
    type: http
    username: $nv_user
    password: $nv_pw
    tls: true
    sni: $sni
    skip-cert-verify: false"
    groups="$groups
      - naive-$hostname_s"
  fi
  cat > "$SB_HOME/clmi.yaml" <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
tcp-concurrent: true
global-client-fingerprint: chrome
geodata-mode: false
geo-auto-update: true
geo-update-interval: 24
find-process-mode: strict
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://1.1.1.1/dns-query
    - https://9.9.9.9/dns-query
proxies:$proxies

proxy-groups:
  - name: AUTO
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:$groups
  - name: PROXY
    type: select
    proxies:
      - AUTO$groups

rules:
  - GEOSITE,CN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
}

# ======================================================
# 服务管理
# ======================================================
install_service() {
  # 覆盖安装：先停掉在跑的旧实例，避免旧进程仍占着端口导致新实例起不来。
  # unit 文件下面会整体重写，无需单独删除。
  if pgrep -f "sing-box run -c $SB_CONF" >/dev/null 2>&1; then
    info "检测到已运行的实例，停止后覆盖安装"
    if [ "$SERVICE_TYPE" = "systemd" ] && [ "$IS_ROOT" = 1 ]; then
      systemctl stop "$SB_SERVICE" >/dev/null 2>&1
    elif [ "$SERVICE_TYPE" = "openrc" ] && [ "$IS_ROOT" = 1 ]; then
      rc-service sing-box stop >/dev/null 2>&1
    fi
    kill -15 $(pgrep -f "sing-box run -c $SB_CONF" 2>/dev/null) >/dev/null 2>&1
    sleep 1
  fi

  if [ "$SERVICE_TYPE" = "systemd" ] && [ "$IS_ROOT" = 1 ]; then
    cat > /etc/systemd/system/${SB_SERVICE}.service <<EOF
[Unit]
Description=sbbox sing-box service
# network-online 而非 network：network.target 只表示网络栈已初始化，此时
# 地址常常还没配上，入站 listen "::" 会起得来但 ACME/出站 DNS 会瞬间失败。
Wants=network-online.target
After=network-online.target nss-lookup.target
# 反复崩溃时不要被 systemd 的默认限流（5 次/10 秒）永久熔断——代理挂了
# 无人值守，宁可一直重试也不能停在 failed 状态
StartLimitIntervalSec=0
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$SB_BIN run -c $SB_CONF
# always 而非 on-failure：进程以 exit 0 退出时也要拉起，长期运行不留缺口
Restart=always
RestartSec=3s
# 句柄上限直接写进主 unit，不再依赖 tune 的 drop-in（用户可能执行过 tune off）
LimitNOFILE=1048576
LimitNPROC=infinity
TasksMax=infinity
Environment="GOGC=200"
# 代理进程的延迟直接决定体感，给一点调度优先级；受限环境设不上会被忽略
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=2
# 优雅退出：先 SIGTERM 让 sing-box 收敛连接，超时再强杀
KillSignal=SIGTERM
TimeoutStopSec=10
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable ${SB_SERVICE} >/dev/null 2>&1
    systemctl restart ${SB_SERVICE} >/dev/null 2>&1
  elif [ "$SERVICE_TYPE" = "openrc" ] && [ "$IS_ROOT" = 1 ]; then
    cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="sbbox sing-box service"
command="$SB_BIN"
command_args="run -c $SB_CONF"
command_background=yes
pidfile="/run/sing-box.pid"
depend() { need net; }
EOF
    chmod +x /etc/init.d/sing-box >/dev/null 2>&1
    rc-update add sing-box default >/dev/null 2>&1
    rc-service sing-box start >/dev/null 2>&1
  else
    # 非 systemd/root：crontab 开机自启
    crontab -l > /tmp/sbbox_cron.tmp 2>/dev/null || true
    sed -i '/sbbox\/sing-box/d' /tmp/sbbox_cron.tmp 2>/dev/null || true
    echo '@reboot sleep 10 && /bin/sh -c "nohup '"$SB_BIN"' run -c '"$SB_CONF"' >'"$SB_LOG"' 2>&1 &"' >> /tmp/sbbox_cron.tmp 2>/dev/null
    crontab /tmp/sbbox_cron.tmp >/dev/null 2>&1
    rm -f /tmp/sbbox_cron.tmp
    nohup "$SB_BIN" run -c "$SB_CONF" >> "$SB_LOG" 2>&1 &
  fi
  sleep 2
  if pgrep -f "sing-box run -c $SB_CONF" >/dev/null 2>&1; then
    info "sing-box 进程启动成功"
  else
    error "sing-box 进程启动失败，请查看日志：$SB_LOG"
  fi
}

sbrestart() {
  kill -15 $(pgrep -f "sing-box run -c $SB_CONF" 2>/dev/null) >/dev/null 2>&1
  sleep 1
  if [ "$SERVICE_TYPE" = "systemd" ] && [ "$IS_ROOT" = 1 ]; then
    systemctl restart ${SB_SERVICE} >/dev/null 2>&1
  elif [ "$SERVICE_TYPE" = "openrc" ] && [ "$IS_ROOT" = 1 ]; then
    rc-service sing-box restart >/dev/null 2>&1
  else
    nohup "$SB_BIN" run -c "$SB_CONF" >> "$SB_LOG" 2>&1 &
  fi
  sleep 2
  if pgrep -f "sing-box run -c $SB_CONF" >/dev/null 2>&1; then
    info "sing-box 已重启"
  else
    error "sing-box 重启失败"
  fi
}

cleandel() {
  # 交互式确认，避免误删（非 TTY 自动跳过确认直接卸载）
  if [ -t 0 ]; then
    printf '%s' "确认卸载 sbbox 全部节点与配置？(y/N) " >&2
    read -r _confirm
    case "$_confirm" in y|Y|yes|YES) : ;; *) warn "已取消卸载" && return 0 ;; esac
  fi
  info "停止 sing-box 并清理……"
  stop_sub_server >/dev/null 2>&1
  kill -15 $(pgrep -f "sing-box run -c $SB_CONF" 2>/dev/null) >/dev/null 2>&1
  if [ "$SERVICE_TYPE" = "systemd" ]; then
    systemctl stop ${SB_SERVICE} >/dev/null 2>&1
    systemctl disable ${SB_SERVICE} >/dev/null 2>&1
    rm -f /etc/systemd/system/${SB_SERVICE}.service
    rm -rf /etc/systemd/system/${SB_SERVICE}.service.d
  elif [ "$SERVICE_TYPE" = "openrc" ]; then
    rc-service sing-box stop >/dev/null 2>&1
    rc-update del sing-box default >/dev/null 2>&1
    rm -f /etc/init.d/sing-box
  fi
  crontab -l > /tmp/sbbox_cron.tmp 2>/dev/null || true
  sed -i '/sbbox\/sing-box/d' /tmp/sbbox_cron.tmp 2>/dev/null || true
  crontab /tmp/sbbox_cron.tmp >/dev/null 2>&1
  rm -f /tmp/sbbox_cron.tmp
  iptables -t nat -F PREROUTING >/dev/null 2>&1
  ip6tables -t nat -F PREROUTING >/dev/null 2>&1
  rm -f "$SB_BINDIR/sbbox" "$SB_HOME/deps_done"
  rm -rf "$SB_HOME" 2>/dev/null
  info "sbbox 已完全卸载"
}

# Hysteria2 跳跃端口（iptables DNAT）
apply_hy_hop() {
  if [ -n "$hyjpt" ] && [ -n "$hyp" ]; then
    echo ""
    echo "设置 Hysteria2 跳跃端口：$hyjpt"
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    ip6tables -t nat -F PREROUTING >/dev/null 2>&1
    for port in $hyjpt; do
      iptables -t nat -A PREROUTING -p udp --dport "$port" -j DNAT --to-destination :$port_hy2 2>/dev/null
      ip6tables -t nat -A PREROUTING -p udp --dport "$port" -j DNAT --to-destination :$port_hy2 2>/dev/null
    done
    netfilter-persistent save >/dev/null 2>&1
    [ -x "$(command -v iptables-save 2>/dev/null)" ] && iptables-save > /etc/iptables/rules.v4 2>/dev/null
    info "Hysteria2 跳跃端口配置完成"
  fi
}

# 密钥轮换：各协议密码、obfs 密码、订阅令牌全部换成新的独立随机值。
# UUID、端口、证书保持不变。
cmd_rotate() {
  [ -x "$SB_BIN" ] || { error "未安装 sbbox，无需轮换"; exit 1; }
  if [ -t 0 ]; then
    printf '%s' "轮换后所有客户端必须重新导入节点/订阅，确认继续？(y/N) " >&2
    read -r _c
    case "$_c" in y|Y|yes|YES) : ;; *) warn "已取消"; return 0 ;; esac
  fi
  export SBBOX_ROTATE=1
  rm -f "$SB_SEC_DIR"/* "$SB_HOME/hyobfs_pw" "$SB_HOME/subtoken" 2>/dev/null
  hyobfs_pw=""
  v4v6
  load_state
  subid=""                       # 令牌一并换新：旧订阅 URL 里存的是旧密码
  [ -s "$SB_HOME/subport" ] && sub=1
  [ "$CERT_OK" = 1 ] && alns=1   # 证书已在本地，installsb 不会重新签发
  installsb
  sbrestart
  gen_client
  info "密钥轮换完成，请用上面的新节点信息重新导入客户端"
}

status_show() {
  echo "========= sbbox 服务状态 ========="
  if pgrep -f "sing-box run -c $SB_CONF" >/dev/null 2>&1; then
    echo -e "sing-box: ${GREEN}运行中${NC}"
  else
    echo -e "sing-box: ${RED}未运行${NC}"
  fi
  echo ""
  if command -v ss >/dev/null 2>&1; then
    echo -e "${CYAN}[+] 监听端口${NC}"
    ss -tulnp 2>/dev/null | grep -E 'sing-box' || echo "  （未发现 sing-box 监听）"
  fi
  echo ""
  tune_show
  echo ""
  if [ -x "$SB_BIN" ]; then
    echo -e "${CYAN}[+] 版本${NC}"
    "$SB_BIN" version 2>/dev/null | head -1
  fi
}

sblog() {
  local n=${1:-20}
  if [ -f "$SB_LOG" ]; then
    tail -n "$n" "$SB_LOG"
  else
    warn "日志文件不存在：$SB_LOG"
  fi
}

# ======================================================
# 主流程 / 管理命令分发
# ======================================================
main() {
  detect_env
  # 支持 `bash sbbox.sh tup=1 hyp=1 ...` 位置参数形式：将 key=value 参数转换为环境变量
  # （与 `tup=1 bash sbbox.sh` 环境变量前缀形式等价，二者可混用）
  for arg in "$@"; do
    case "$arg" in
      *=*) export "$arg" ;;
    esac
  done
  local cmd="${1:-}"
  case "$cmd" in
    list)   v4v6; load_state; gen_client; exit ;;
    status) status_show; exit ;;
    res)    sbrestart; exit ;;
    up)     cmd_update; exit ;;
    log)    sblog "$2"; exit ;;
    tune)   shift; cmd_tune "$@"; exit ;;   # 安装期已自动 on，off 用于回滚
    cert)   shift; cert_mgmt "$@"; exit ;;
    sub)    shift; cmd_sub "$@"; exit ;;
    doctor) doctor; exit ;;
    rotate) cmd_rotate; exit ;;
    del)    cleandel; exit ;;
    help|-h|--help) showmode; exit ;;
  esac

  # 安装流程
  if [ -z "$tup" ] && [ -z "$hyp" ] && [ -z "$nvp" ]; then
    if [ -x "$SB_BIN" ]; then
      # 已安装但未指定协议 → 显示帮助
      showmode
      status_show
      exit
    else
      error "未指定任何协议。请至少设置一个：tup=1 hyp=1 nvp=1"
      echo ""
      showmode
      exit 1
    fi
  fi

  mkdir -p "$SB_HOME"
  # 目录内含证书私钥、uuid（即各协议连接密码）与订阅令牌，收敛到仅属主可读
  chmod 700 "$SB_HOME" 2>/dev/null
  v4v6
  install_deps
  # 重装即升级：upsingbox 内部会比对版本，已是最新则直接跳过，不会重复下载
  upsingbox
  installsb
  save_state

  # 仅生成并校验配置：产出服务端/客户端配置后退出，不动内核参数、不装服务。
  # CI 用它以真实内核跑 `sing-box check`，本地排障也可用。
  if [ -n "$SBBOX_CHECK_ONLY" ]; then
    gen_client
    info "SBBOX_CHECK_ONLY=1：配置已生成并校验，跳过调优与服务安装"
    exit 0
  fi

  apply_tuning
  apply_hy_hop
  install_service
  gen_client

  install_cmd
  setup_logrotate
  setup_autoupdate
  info "安装完成！可直接使用 sbbox 管理命令"
  echo ""
  showmode
}

# 安装常驻管理命令。
# 经 `bash <(curl ...)` 运行时 $0 是已读完的管道（/dev/fd/NN），拷不出内容，
# 因此优先复制本地文件，不可用时从仓库重新下载。
install_cmd() {
  local dest="$SB_BINDIR/sbbox" tmp="$SB_HOME/.sbbox.new"
  mkdir -p "$SB_BINDIR" 2>/dev/null

  if [ -f "$0" ] && [ -r "$0" ] && head -1 "$0" 2>/dev/null | grep -q '^#!'; then
    cp "$0" "$tmp" 2>/dev/null
  fi
  if [ ! -s "$tmp" ] || ! bash -n "$tmp" >/dev/null 2>&1; then
    (command -v curl >/dev/null 2>&1 && curl -fsSL "$SB_URL" -o "$tmp") || \
      (command -v wget >/dev/null 2>&1 && wget -qO "$tmp" "$SB_URL")
  fi

  if [ -s "$tmp" ] && bash -n "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$dest" && chmod +x "$dest"
    # ~/bin 不一定在 PATH 中（/usr/local/bin 一定在）
    if [ "$SB_BINDIR" != "/usr/local/bin" ]; then
      grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null || \
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null
      export PATH="$SB_BINDIR:$PATH"
      warn "$SB_BINDIR 已加入 PATH，当前会话生效；新会话请重连 SSH"
    fi
    info "sbbox 管理命令已安装：$dest"
  else
    rm -f "$tmp"
    warn "管理命令安装失败。可手动执行："
    warn "  curl -fsSL $SB_URL -o $SB_BINDIR/sbbox && chmod +x $SB_BINDIR/sbbox"
  fi
}

# 保存已启用协议与关键参数（供 list/status 恢复）
save_state() {
  # 先清空再按本次实际启用写入：重装若减少协议，旧标记必须消失，
  # 否则 list 会生成服务端已不存在的节点链接
  rm -f "$SB_HOME"/proto_tup "$SB_HOME"/proto_hyp "$SB_HOME"/proto_nvp 2>/dev/null
  [ -n "$tup" ] && touch "$SB_HOME/proto_tup"
  [ -n "$hyp" ] && touch "$SB_HOME/proto_hyp"
  [ -n "$nvp" ] && touch "$SB_HOME/proto_nvp"
  echo "$ym" > "$SB_HOME/ym"
  [ -n "$hyjpt" ] && echo "$hyjpt" > "$SB_HOME/hyjpt"
  # Brutal 带宽必须持久化：否则 rotate / 重新生成配置时静默退回 BBR，
  # 用户看不出配置为何变了
  if [ -n "$hyup" ] && [ -n "$hydown" ]; then
    echo "$hyup $hydown" > "$SB_HOME/hybw"
  else
    rm -f "$SB_HOME/hybw"
  fi
  [ -n "$sbrel" ] && echo "$sbrel" > "$SB_HOME/sbrel"
}

# 内核升级：备份 → 升级 → 用新内核校验配置 → 重启；任一步失败即回滚旧内核。
# 新版本偶尔会收紧配置 schema（本项目就被 1.12 的 DNS 格式变更打过），
# 没有回滚的话一次自动升级就能让所有节点掉线。
cmd_update() {
  # 优先级：本次显式指定 > 首装时持久化的通道 > 默认值。
  # cron 自动升级不带任何环境变量，走的就是持久化那一档。
  [ -z "$sbrel_explicit" ] && [ -f "$SB_HOME/sbrel" ] && sbrel=$(cat "$SB_HOME/sbrel")
  local bak="$SB_HOME/sing-box.bak" before after
  before=$(sb_installed_version)
  [ -x "$SB_BIN" ] && cp -f "$SB_BIN" "$bak" 2>/dev/null

  upsingbox || { warn "升级未执行"; return 1; }
  after=$(sb_installed_version)
  if [ "$before" = "$after" ]; then
    rm -f "$bak"; return 0
  fi

  if [ -f "$SB_CONF" ] && ! "$SB_BIN" check -c "$SB_CONF" 2>"$SB_HOME/check.err"; then
    error "新内核 $after 校验现有配置失败，回滚到 $before："
    cat "$SB_HOME/check.err" >&2
    [ -s "$bak" ] && mv -f "$bak" "$SB_BIN" && chmod +x "$SB_BIN"
    sbrestart
    error "已回滚。配置可能需要按新版本调整后再升级"
    return 1
  fi

  sbrestart
  sleep 2
  if pgrep -f "sing-box run -c $SB_CONF" >/dev/null 2>&1; then
    info "升级完成：${before:-无} → $after"
    rm -f "$bak"
  else
    error "新内核启动失败，回滚到 $before"
    [ -s "$bak" ] && mv -f "$bak" "$SB_BIN" && chmod +x "$SB_BIN"
    sbrestart
    return 1
  fi
}

# 日志轮转：sing-box 自身不做轮转，长期运行会把 sb.log 写到撑爆磁盘。
# 交给系统 logrotate（Debian/Ubuntu 默认每日触发），无该组件时跳过。
setup_logrotate() {
  [ -d /etc/logrotate.d ] || { warn "无 logrotate，日志不会自动轮转（注意 $SB_LOG 增长）"; return 0; }
  cat > /etc/logrotate.d/sbbox <<EOF 2>/dev/null || { warn "写入 logrotate 配置失败"; return 0; }
$SB_LOG {
    weekly
    rotate 4
    maxsize 10M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su root root
}
EOF
  info "已配置日志轮转（周轮转 / 单文件上限 10M / 保留 4 份）"
}

# 每周自动升级内核（带上面的回滚保护）
setup_autoupdate() {
  command -v crontab >/dev/null 2>&1 || return 0
  crontab -l > /tmp/sbbox_up_cron.tmp 2>/dev/null || true
  sed -i '/sbbox up/d' /tmp/sbbox_up_cron.tmp 2>/dev/null || true
  if [ -z "$noautoup" ]; then
    # 每周日 4 点，随机延迟避免整点打爆 GitHub
    echo "0 4 * * 0 sleep \$((RANDOM \\% 3600)); $SB_BINDIR/sbbox up >/dev/null 2>&1" >> /tmp/sbbox_up_cron.tmp
  fi
  crontab /tmp/sbbox_up_cron.tmp >/dev/null 2>&1
  rm -f /tmp/sbbox_up_cron.tmp
  [ -z "$noautoup" ] && info "已开启每周内核自动升级（关闭：noautoup=1 重装，或 crontab -e 删除该行）"
}

# 流控调优管理命令
cmd_tune() {
  local action="${1:-show}"
  case "$action" in
    show)        tune_show ;;
    on)          apply_tuning ;;
    off|rollback) tune_off ;;
    *) echo "用法: sbbox tune [show|on|off]" ;;
  esac
}

# 证书管理命令
cert_mgmt() {
  local action="${1:-status}"
  [ -n "$ym" ] || ym=$(cat "$SB_HOME/ym" 2>/dev/null || echo "")
  case "$action" in
    status)
      if cert_ready; then
        info "证书状态：已安装（域名：$ym）"
        openssl x509 -in "$CERT_DIR/fullchain.cer" -noout -dates -subject 2>/dev/null
      else
        warn "证书状态：未安装。如已设置 alns=1，请重新安装"
      fi
      ;;
    renew)
      if [ -n "$ym" ]; then
        v4v6
        if [ -f "$HOME/.acme.sh/acme.sh" ]; then
          "$HOME/.acme.sh/acme.sh" --renew -d "$ym" --force 2>/dev/null || true
        fi
        install_cert
        get_cert_paths
        if [ "$CERT_OK" = 1 ]; then
          info "证书续期完成"
          sbrestart
          gen_client
        fi
      else
        warn "未找到证书域名（安装时未设置 ym）。请手动执行 acme.sh 续期"
      fi
      ;;
    *) echo "用法: sbbox cert [status|renew]" ;;
  esac
}

# ======================================================
# 节点自检自愈：检查每个已启用协议端口是否监听/可连，
# 发现不通自动修复（重启服务 → 仍不通则重新生成配置再重启）
# ======================================================
port_listening() { # $1=port  $2=tcp|udp  → 0 监听中
  local p=$1 proto=${2:-tcp} flag
  # 必须显式给出短选项：拼接 "-${proto}ln" 会得到 -tcpln / -udpln，
  # 被解析成组合短选项（-t -c -p -l -n）。ss 无 -c 选项会直接失败，
  # 而 netstat 的 -c 是 continuous，会无限循环。
  case "$proto" in
    udp) flag="-uln" ;;
    *)   flag="-tln" ;;
  esac
  if command -v ss >/dev/null 2>&1; then
    ss "$flag" 2>/dev/null | grep -qE "[:.]${p}([[:space:]]|$)"
  elif command -v netstat >/dev/null 2>&1; then
    netstat "$flag" 2>/dev/null | grep -qE "[:.]${p}([[:space:]]|$)"
  elif [ "$proto" != udp ]; then
    # 无 ss/netstat 时退化为尝试 TCP 连接（UDP 无法这样探测）
    timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/$p" >/dev/null 2>&1
  else
    return 0   # 无工具且是 UDP，无法判定，不误报
  fi
}

# 握手探测：入站监听 "::"，纯 IPv6 栈上 127.0.0.1 连不通，两个回环都试
tcp_reachable() {
  timeout 3 bash -c "echo >/dev/tcp/127.0.0.1/$1" >/dev/null 2>&1 && return 0
  timeout 3 bash -c "echo >/dev/tcp/::1/$1" >/dev/null 2>&1
}

doctor() {
  detect_env
  load_state

  local issues=0 fixed=0 svc_down=0
  echo "========= sbbox 节点自检 ========="

  if ! pgrep -f "sing-box run -c $SB_CONF" >/dev/null 2>&1; then
    echo -e "sing-box 服务：${RED}未运行${NC} → 尝试重启"
    svc_down=1
  else
    echo -e "sing-box 服务：${GREEN}运行中${NC}"
  fi

  # 需要证书的协议（naive）若证书缺失或域名不匹配视为不通
  if [ "$nvp" = yes ]; then
    if [ "$CERT_OK" != 1 ]; then
      echo -e "Naiveproxy：${RED}证书缺失${NC}（naive 需要真实证书，不会启动）"
      issues=$((issues+1))
    elif [ -n "$ym" ] && ! cert_matches_ym "$ym"; then
      echo -e "Naiveproxy：${RED}证书与域名 $ym 不匹配${NC}"
      issues=$((issues+1))
    fi
  fi

  check_one() { # $1=名称 $2=端口 $3=tcp|udp
    local name=$1 p=$2 proto=${3:-tcp} rc=0
    if [ -z "$p" ]; then
      echo -e "  ${name}：${RED}端口未配置${NC}"
      issues=$((issues+1)); return
    fi
    if ! port_listening "$p" "$proto"; then
      echo -e "  ${name}（端口 $p）：${RED}未监听${NC}"
      issues=$((issues+1)); rc=1
    elif [ "$proto" = tcp ] && ! tcp_reachable "$p"; then
      echo -e "  ${name}（端口 $p）：${RED}端口监听但无法握手${NC}"
      issues=$((issues+1)); rc=1
    else
      echo -e "  ${name}（端口 $p）：${GREEN}正常${NC}"
    fi
  }

  [ "$tup" = yes ] && check_one Tuic "$port_tu" udp
  [ "$hyp" = yes ] && check_one Hysteria2 "$port_hy2" udp
  [ "$nvp" = yes ] && check_one Naiveproxy "$port_nv" tcp
  if [ "$sub" = 1 ] && [ -n "$subport" ]; then
    check_one "订阅服务" "$subport" tcp
  fi

  if [ "$issues" -eq 0 ] && [ "$svc_down" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}全部节点与服务正常${NC}"
    return 0
  fi

  # ---------- 自动修复 ----------
  echo ""
  echo "检测到 $issues 处问题，开始修复……"

  # 证书缺失或域名不匹配 → 尝试重新获取
  if [ -n "$ym" ] && ([ "$CERT_OK" != 1 ] || ! cert_matches_ym "$ym"); then
    install_cert && get_cert_paths
    if [ "$CERT_OK" = 1 ] && cert_matches_ym "$ym"; then
      echo -e "证书：${GREEN}已重新获取并匹配域名 $ym${NC}"
      fixed=$((fixed+1))
    fi
  fi

  # 修复订阅服务（若未运行）
  if [ "$sub" = 1 ] && [ -n "$subport" ]; then
    if ! port_listening "$subport" tcp; then
      echo "  订阅服务 未运行，正在重新拉起并放行防火墙……"
      start_sub_server >/dev/null 2>&1
      sleep 1
      if port_listening "$subport" tcp; then
        echo -e "  订阅服务：${GREEN}已修复${NC}"; fixed=$((fixed+1))
      else
        echo -e "  订阅服务：${RED}修复失败，请查看日志${NC}"
      fi
    fi
  fi


  # 先重启服务，覆盖「进程挂了 / 端口没起来」的情况
  if [ "$svc_down" -eq 1 ] || [ "$issues" -gt 0 ]; then
    sbrestart
    sleep 2
    # 重启后复查每个有问题的端口，仍未恢复则重新生成配置
    for spec in "Tuic:$port_tu:udp" "Hysteria2:$port_hy2:udp" "Naiveproxy:$port_nv:tcp"; do
      name=${spec%%:*}; rest=${spec#*:}; p=${rest%%:*}; proto=${rest##*:}
      case "$name" in
        Tuic)       [ "$tup" = yes ] || continue ;;
        Hysteria2)  [ "$hyp" = yes ] || continue ;;
        Naiveproxy) [ "$nvp" = yes ] || continue ;;
      esac
      if ! port_listening "$p" "$proto"; then
        echo "  ${name} 重启后仍不通，重新生成配置……"
        installsb >/dev/null 2>&1
        sbrestart >/dev/null 2>&1
        sleep 2
        if port_listening "$p" "$proto"; then
          echo -e "  ${name}：${GREEN}已修复${NC}"; fixed=$((fixed+1))
        else
          echo -e "  ${name}：${RED}修复失败，请查看日志 sbbox log${NC}"
        fi
      else
        echo -e "  ${name}：${GREEN}已恢复${NC}"; fixed=$((fixed+1))
      fi
    done
  fi

  echo ""
  echo "===== 修复完成：$fixed 项已处理，剩余 $((issues-fixed)) 项未解决 ====="
  [ "$issues" -le "$fixed" ] && echo -e "${GREEN}建议执行 sbbox list 核对节点信息${NC}"
}

# 从磁盘恢复已保存状态（用于 list）
load_state() {
  uuid=$(cat "$SB_HOME/uuid" 2>/dev/null || echo "")
  load_secrets
  ym=$(cat "$SB_HOME/ym" 2>/dev/null || echo "")
  [ -f "$SB_HOME/proto_tup" ] && tup=yes
  [ -f "$SB_HOME/proto_hyp" ] && hyp=yes
  [ -f "$SB_HOME/proto_nvp" ] && nvp=yes
  [ -f "$SB_HOME/port_tu" ] && port_tu=$(cat "$SB_HOME/port_tu")
  [ -f "$SB_HOME/port_hy2" ] && port_hy2=$(cat "$SB_HOME/port_hy2")
  [ -f "$SB_HOME/port_nv" ] && port_nv=$(cat "$SB_HOME/port_nv")
  [ -f "$SB_HOME/hyjpt" ] && hyjpt=$(cat "$SB_HOME/hyjpt")
  if [ -z "$hyup" ] && [ -z "$hydown" ] && [ -s "$SB_HOME/hybw" ]; then
    hyup=$(awk '{print $1}' "$SB_HOME/hybw"); hydown=$(awk '{print $2}' "$SB_HOME/hybw")
  fi
  [ -s "$SB_HOME/hyobfs_pw" ] && hyobfs_pw=$(cat "$SB_HOME/hyobfs_pw")
  [ -z "$sbrel_explicit" ] && [ -f "$SB_HOME/sbrel" ] && sbrel=$(cat "$SB_HOME/sbrel")
  # 订阅曾启用过就保持启用，令牌/端口沿用，避免 list 后订阅地址变化
  if [ -f "$SB_HOME/subtoken" ]; then
    sub=1
    subid=$(cat "$SB_HOME/subtoken")
    subport=$(cat "$SB_HOME/subport" 2>/dev/null)
  fi
  get_cert_paths
  if cert_ready; then CERT_OK=1; else CERT_OK=0; fi
  hostname_s=$(hostname 2>/dev/null || echo vps)
}

main "$@"

