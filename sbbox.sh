#!/usr/bin/env bash
# ======================================================
# sing-box-naiveproxy (sbbox.sh) — Sing-box 五协议安全加固代理脚本
#
# 基于 yonggekkk/argosbx 架构，剥离为 sing-box 单内核，
# 仅保留 Tuic / Hysteria2 / Naiveproxy(H2+H3) / Reality 五协议。
# 集成内核级流控调优 (xh tuning on) + acme.sh 证书申请。
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
#   3. Reality 强制 uTLS chrome 指纹 + TLS 1.3
#   4. 内核流控调优全部 best-effort，写入独立文件可整体回滚
#   5. 只写自己的文件，不修改用户既有 /etc/sysctl.conf 与官方 unit
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
SBBOX_VERSION="v1.1.0"
SB_URL="https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh"
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
ym_vl_re="${ym_vl_re:-apple.com}"          # Reality 回落目标域名
ym="${ym:-}"                                # acme 证书域名（启用 alns 时必需）
alns="${alns:-}"                            # 申请 acme 证书：alns=1
tup="${tup:-}" hyp="${hyp:-}" nvp="${nvp:-}" vlp="${vlp:-}"
hyjpt="${hyjpt:-}"                          # Hysteria2 跳跃端口，如 "20000:30000"
ippz="${ippz:-}"                            # 4 / 6 / 双栈
name="${name:-}"
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
  echo "sbbox $SBBOX_VERSION — Sing-box-Only 五协议安全代理脚本"
  echo "支持协议：Tuic / Hysteria2 / Naiveproxy(H2+H3) / Reality"
  echo "-----------------------------------------------------------"
  echo "主脚本：bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh)"
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
  echo "环境变量（安装期）：tup=1 hyp=1 nvp=1 vlp=1"
  echo "  alns=1   启用 acme 证书（需 ym=你的域名）"
  echo "  ym=域名  acme 证书域名（Hysteria2/Tuic/Naive 使用）"
  echo "  ym_vl_re=域名  Reality 回落目标域名（默认 apple.com）"
  echo "  hyjpt=20000:30000  Hysteria2 跳跃端口"
  echo "  sub=1    启用 v2rayN 订阅服务（subport=端口 subid=令牌 可选）"
  echo "  uuid=自定义密码"
  echo "==========================================================="
}

# ---------- 依赖安装 ----------
install_deps() {
  if [ ! -f "$SB_HOME/deps_done" ]; then
    info "安装系统依赖……"
    if command -v apk >/dev/null 2>&1; then
      apk update >/dev/null 2>&1 && apk add --no-cache bash coreutils curl wget openssl iptables ip6tables ca-certificates >/dev/null 2>&1
    elif command -v apt >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt update >/dev/null 2>&1 && apt install -y curl wget openssl ca-certificates iptables iptables-persistent net-tools >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl wget openssl ca-certificates iptables >/dev/null 2>&1
    fi
    touch "$SB_HOME/deps_done"
  fi
}

# ---------- sing-box 内核下载/更新 ----------
upsingbox() {
  info "下载 sing-box 内核 (linux-$cpu)……"
  local url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/sing-box-$cpu"
  (command -v curl >/dev/null 2>&1 && curl -Lo "$SB_BIN" -# --retry 2 "$url") || \
    (command -v wget >/dev/null 2>&1 && timeout 3 wget -O "$SB_BIN" --tries=2 "$url")
  if [ ! -s "$SB_BIN" ]; then
    # 回退到官方 release
    local ver sbtgz
    ver=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    [ -z "$ver" ] && ver="1.11.8"
    sbtgz="$SB_HOME/sing-box-$ver.tar.gz"
    curl -Lo "$sbtgz" "https://github.com/SagerNet/sing-box/releases/download/$ver/sing-box-$ver-linux-$cpu.tar.gz" 2>/dev/null || return 1
    tar -xzf "$sbtgz" -C "$SB_HOME" "sing-box-$ver-linux-$cpu/sing-box" 2>/dev/null
    mv "$SB_HOME/sing-box-$ver-linux-$cpu/sing-box" "$SB_BIN" 2>/dev/null
    rm -rf "$SB_HOME/sing-box-$ver-linux-$cpu" "$sbtgz" 2>/dev/null
  fi
  chmod +x "$SB_BIN"
  if [ -x "$SB_BIN" ]; then
    local ver
    ver=$("$SB_BIN" version 2>/dev/null | awk '/version/{print $NF}')
    info "sing-box 内核版本：${ver:-未知}"
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
  info "UUID/密码：$uuid"
}

# ---------- Reality 密钥生成 ----------
gen_reality_keys() {
  if [ -n "$vlp" ]; then
    if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
    echo "$ym_vl_re" > "$SB_HOME/ym_vl_re"
    mkdir -p "$SB_HOME/rk"
    if [ ! -e "$SB_HOME/rk/private_key" ]; then
      local kp
      kp=$("$SB_BIN" generate reality-keypair 2>/dev/null)
      private_key_s=$(echo "$kp" | awk '/PrivateKey/ {print $2}' | tr -d '"')
      public_key_s=$(echo "$kp" | awk '/PublicKey/ {print $2}' | tr -d '"')
      short_id_s=$("$SB_BIN" generate rand --hex 4 2>/dev/null)
      [ -z "$private_key_s" ] || echo "$private_key_s" > "$SB_HOME/rk/private_key"
      [ -z "$public_key_s" ]  || echo "$public_key_s"  > "$SB_HOME/rk/public_key"
      [ -z "$short_id_s" ]    || echo "$short_id_s"    > "$SB_HOME/rk/short_id"
    fi
    private_key_s=$(cat "$SB_HOME/rk/private_key" 2>/dev/null)
    public_key_s=$(cat "$SB_HOME/rk/public_key" 2>/dev/null)
    short_id_s=$(cat "$SB_HOME/rk/short_id" 2>/dev/null)
    info "Reality 域名：$ym_vl_re"
  fi
}

# ---------- 证书状态 ----------
cert_ready() { [ -s "$CERT_DIR/fullchain.cer" ] && [ -s "$CERT_DIR/private.key" ]; }

get_cert_paths() {
  if cert_ready; then
    cert_path="$CERT_DIR/fullchain.cer"
    key_path="$CERT_DIR/private.key"
    CERT_OK=1
  else
    cert_path="$SB_HOME/selfsigned.crt"
    key_path="$SB_HOME/selfsigned.key"
    CERT_OK=0
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
install_cert() {
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

  local acme_home="$HOME/.acme.sh/${ym}_ecc"
  if [ -f "$acme_home/fullchain.cer" ] && [ -f "$acme_home/${ym}.key" ]; then
    info "检测到已存在证书，直接复用"
  else
    info "开始申请证书：$ym (需 80 端口空闲)……"
    if [ -n "$v6" ] && [ -z "$v4" ]; then
      "$HOME/.acme.sh/acme.sh" --issue -d "$ym" --standalone --listen-v6 --keylength ec-256
    else
      "$HOME/.acme.sh/acme.sh" --issue -d "$ym" --standalone --listen-v4 --keylength ec-256
    fi
  fi

  if [ -f "$acme_home/fullchain.cer" ] && [ -f "$acme_home/${ym}.key" ]; then
    mkdir -p "$CERT_DIR"
    cp "$acme_home/fullchain.cer" "$CERT_DIR/fullchain.cer"
    cp "$acme_home/${ym}.key" "$CERT_DIR/private.key"
    info "证书已落地：$CERT_DIR/fullchain.cer"
    # Hysteria2 用 SHA256 固定指纹（配合真实证书双保险）
    sha=$(openssl x509 -in "$CERT_DIR/fullchain.cer" -outform DER | sha256sum | awk '{print $1}')
    echo "$sha" > "$SB_HOME/SHA256.txt"
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

  if [ "$MEM_MB" -ge 16384 ]; then
    TUNE_TIER="large";  SOCK_MEM_MAX=67108864; TCP_MEM_MAX=33554432; NETDEV_BACKLOG=65536; CONNTRACK_MAX=1048576; NETDEV_BUDGET=6000
  elif [ "$MEM_MB" -ge 4096 ]; then
    TUNE_TIER="medium"; SOCK_MEM_MAX=33554432; TCP_MEM_MAX=16777216; NETDEV_BACKLOG=32768; CONNTRACK_MAX=262144; NETDEV_BUDGET=6000
  else
    TUNE_TIER="small";  SOCK_MEM_MAX=16777216; TCP_MEM_MAX=8388608;  NETDEV_BACKLOG=16384; CONNTRACK_MAX=0; NETDEV_BUDGET=""
  fi
  info "机型: ${CPU_CORES} 核 / ${MEM_MB} MB / ${ARCH} → 调优档位 ${TUNE_TIER}"

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
  try_sysctl net.core.rmem_default 1048576
  try_sysctl net.core.wmem_default 1048576
  try_sysctl net.ipv4.tcp_rmem "4096 262144 ${TCP_MEM_MAX}"
  try_sysctl net.ipv4.tcp_wmem "4096 262144 ${TCP_MEM_MAX}"
  try_sysctl net.ipv4.tcp_adv_win_scale -2
  try_sysctl net.ipv4.tcp_mem "$(( MEM_PAGES * 6 / 100 )) $(( MEM_PAGES * 8 / 100 )) $(( MEM_PAGES * 12 / 100 ))"
  # QUIC / HTTP3：Hysteria2 / Tuic 关键
  try_sysctl net.core.optmem_max 65536
  try_sysctl net.ipv4.udp_rmem_min 8192
  try_sysctl net.ipv4.udp_wmem_min 8192

  # ---------- 队列与并发 ----------
  try_sysctl net.core.netdev_max_backlog "$NETDEV_BACKLOG"
  if [ -n "$NETDEV_BUDGET" ]; then
    try_sysctl net.core.netdev_budget "$NETDEV_BUDGET"
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
  try_sysctl net.ipv4.tcp_notsent_lowat 16384
  try_sysctl net.ipv4.tcp_syncookies 1
  try_sysctl net.ipv4.tcp_tw_reuse 1
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
    install -d -m 755 "/etc/systemd/system/${SB_SERVICE}.service.d" 2>/dev/null || true
    cat > "/etc/systemd/system/${SB_SERVICE}.service.d/override.conf" <<'DROPINEOF' 2>/dev/null || warn "写入 ${SB_SERVICE} drop-in 失败"
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
DROPINEOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    info "已为 sing-box 写入 systemd drop-in（LimitNOFILE=1048576）"
  elif [ -d /etc/conf.d ]; then
    grep -q '^rc_ulimit=' /etc/conf.d/sing-box 2>/dev/null || \
      echo 'rc_ulimit="-n 1048576"' >> /etc/conf.d/sing-box 2>/dev/null || true
    info "已为 sing-box 写入 rc_ulimit"
  fi

  # ---------- Before / After ----------
  echo ""
  echo -e "${YELLOW}[+] 流控调优 Before / After${NC}"
  printf '  %-28s %-18s -> %s\n' "net.core.default_qdisc"          "${BEFORE_QDISC:-n/a}" "$(sysctl_get net.core.default_qdisc)"
  printf '  %-28s %-18s -> %s\n' "net.ipv4.tcp_congestion_control" "${BEFORE_CC:-n/a}"    "$(sysctl_get net.ipv4.tcp_congestion_control)"
  printf '  %-28s %-18s -> %s\n' "net.core.rmem_max"               "${BEFORE_RMEM:-n/a}"  "$(sysctl_get net.core.rmem_max)"
  printf '  %-28s %-18s -> %s\n' "net.ipv4.tcp_fastopen"           "-"                    "$(sysctl_get net.ipv4.tcp_fastopen)"
  printf '  %-28s %-18s -> %s\n' "ulimit -n (当前 shell)"          "${BEFORE_NOFILE}"     "重新登录后生效: 1048576"
  echo ""
  info "BBR: ${TUNING_BBR_OK}；回滚请执行 sbbox tune off"
}

tune_off() {
  info "回滚 sbbox 流控调优……"
  rm -f "$SYSCTL_CONF" 2>/dev/null
  rm -f "$LIMITS_CONF" 2>/dev/null
  rm -rf "/etc/systemd/system/${SB_SERVICE}.service.d" 2>/dev/null
  sysctl --system >/dev/null 2>&1 || true
  [ "$SERVICE_TYPE" = "systemd" ] && systemctl daemon-reload >/dev/null 2>&1 || true
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
  if [ -f "$SYSCTL_CONF" ]; then
    printf '  %-32s %s\n' "调优配置文件" "$SYSCTL_CONF（已启用）"
  else
    printf '  %-32s %s\n' "调优配置文件" "未启用（安装期默认已开启，如被移除请 sbbox res 重装）"
  fi
}

# ======================================================
# sing-box 服务端配置生成（五协议，Naiveproxy 服务端单入站同时支持 H2+H3）
# ======================================================
installsb() {
  echo ""
  echo "========= 启用 Sing-box 内核 ========="
  if [ ! -e "$SB_BIN" ]; then upsingbox; fi
  insuuid
  gen_reality_keys

  # ---------- 证书准备 ----------
  if [ -n "$nvp" ] && [ -z "$alns" ]; then
    error "Naiveproxy 需要有效 TLS 证书。请设置 alns=1 与 ym=你的域名后再安装"
    exit 1
  fi
  if [ -n "$alns" ]; then
    if cert_ready; then
      # 重装 / 加装协议时不重复签发，避免撞上 Let's Encrypt 的签发频率限制
      info "检测到已有证书，跳过申请（如需续期请执行 sbbox cert renew）"
    else
      if [ -z "$ym" ]; then
        # 交互式输入域名，避免出现在命令行历史记录中
        if [ -t 0 ]; then
          printf '%s' "请输入证书域名（申请 Let's Encrypt 证书，需已解析到本机）：" >&2
          read -r ym
        fi
      fi
      if [ -z "$ym" ]; then
        error "启用 alns=1 需要提供证书域名。请在安装时输入，或用 ym=你的域名 指定"
        exit 1
      fi
      install_cert
    fi
    get_cert_paths
    if [ "$CERT_OK" != 1 ]; then
      warn "证书未就绪，Hysteria2/Tuic 将回退自签证书；Naive 不会启用"
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
  [ -n "$tup" ] && { assign_port tu "$port_tu"; echo "Tuic 端口：$port_tu"; }
  [ -n "$hyp" ] && { assign_port hy2 "$port_hy2"; echo "Hysteria2 端口：$port_hy2"; }
  [ -n "$nvp" ] && { assign_port nv "$port_nv"; echo "Naiveproxy 端口：$port_nv"; }
  [ -n "$vlp" ] && { assign_port vl "$port_vl"; echo "Reality 端口：$port_vl"; }

  # ---------- 生成 sb.json ----------
  cat > "$SB_CONF" <<EOF
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true,
        "output": "$SB_LOG"
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
                { "uuid": "$uuid", "password": "$uuid" }
            ],
            "congestion_control": "bbr",
            "zero_rtt_handshake": false,
            "auth_timeout": "3s",
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
    cat >> "$SB_CONF" <<EOF
        {
            "type": "hysteria2",
            "tag": "hy2-in",
            "listen": "::",
            "listen_port": $port_hy2,
            "users": [
                { "password": "$uuid" }
            ],
            "ignore_client_bandwidth": true,
            "masquerade": {
                "type": "string",
                "status_code": 404,
                "headers": { "Content-Type": "text/html" },
                "content": "<html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center></body></html>"
            },
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
            "users": [
                { "username": "$uuid", "password": "$uuid" }
            ],
            "tls": {
                "enabled": true,
                "certificate_path": "$CERT_DIR/fullchain.cer",
                "key_path": "$CERT_DIR/private.key"
            }
        },
EOF
  fi

  # Reality (vless)
  if [ -n "$vlp" ]; then
    cat >> "$SB_CONF" <<EOF
        {
            "type": "vless",
            "tag": "vless-reality-in",
            "listen": "::",
            "listen_port": $port_vl,
            "users": [
                { "uuid": "$uuid", "flow": "xtls-rprx-vision" }
            ],
            "tls": {
                "enabled": true,
                "min_version": "1.3",
                "server_name": "$ym_vl_re",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$ym_vl_re",
                        "server_port": 443
                    },
                    "private_key": "$private_key_s",
                    "short_id": [ "$short_id_s" ]
                }
            }
        },
EOF
  fi

  # 收尾：outbounds + route
  sed -i '${s/,$//}' "$SB_CONF"
  cat >> "$SB_CONF" <<EOF
    ],
    "outbounds": [
        { "type": "direct", "tag": "direct" }
    ],
    "route": {
        "final": "direct"
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
}

# ======================================================
# 客户端节点链接生成 + 聚合订阅
# ======================================================
gen_client() {
  # add：有真实证书用域名（TLS 校验通过），否则用 IP
  if [ "$CERT_OK" = 1 ] && [ -n "$ym" ]; then add="$ym"; else add="$server_ip"; fi
  # sni：有证书用证书域名，否则用伪装域名
  if [ "$CERT_OK" = 1 ] && [ -n "$ym" ]; then sni="$ym"; else sni="www.bing.com"; fi
  if [ "$CERT_OK" = 1 ]; then msins=false; jhins=0; else msins=true; jhins=1; fi

  sxname="${name:+${name}-}"
  : > "$SB_LINK"

  if [ -n "$tup" ]; then
    tuic_link="tuic://$uuid:$uuid@$add:$port_tu?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&insecure=$jhins&allowInsecure=$jhins&allow_insecure=$jhins#${sxname}tuic-$hostname_s"
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
    hy2_link="hysteria2://$uuid@$add:$port_hy2?security=tls&alpn=h3&insecure=$jhins&allowInsecure=$jhins$hyps&sni=$sni$pinsha#${sxname}hy2-$hostname_s"
    echo "$hy2_link" >> "$SB_LINK"
    echo "💣【 Hysteria2 】节点信息如下："
    echo "$hy2_link"; echo
  fi

  if [ -n "$nvp" ] && [ "$CERT_OK" = 1 ]; then
    # Naiveproxy 同一入站同时服务 H2 与 H3，但不同客户端认的 URL scheme 不同：
    #   naive+https:// / naive+quic://  —— v2rayN、NekoBox 等
    #   http2://       / http3://       —— Shadowrocket（认不出 naive+ 前缀）
    # 两套都放进订阅，各客户端各取所需。
    nv1_link="naive+https://$uuid:$uuid@$add:$port_nv?security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1#${sxname}naive-h2-$hostname_s"
    nv2_link="naive+quic://$uuid:$uuid@$add:$port_nv?congestion_control=bbr&security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1#${sxname}naive-h3-$hostname_s"
    nv3_link="http2://$uuid:$uuid@$add:$port_nv?security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1#${sxname}naive-h2-rocket-$hostname_s"
    nv4_link="http3://$uuid:$uuid@$add:$port_nv?security=tls&sni=$sni&insecure=0&allowInsecure=0&padding=1&tfo=1#${sxname}naive-h3-rocket-$hostname_s"
    for l in "$nv1_link" "$nv2_link" "$nv3_link" "$nv4_link"; do
      echo "$l" >> "$SB_LINK"
    done
    echo "💣【 Naiveproxy 】节点信息如下（前两条 v2rayN/NekoBox，后两条 Shadowrocket）："
    echo "$nv1_link"; echo "$nv2_link"; echo "$nv3_link"; echo "$nv4_link"; echo
  fi

  if [ -n "$vlp" ]; then
    vl_link="vless://$uuid@$add:$port_vl?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_s&sid=$short_id_s&type=tcp&headerType=none#${sxname}reality-$hostname_s"
    echo "$vl_link" >> "$SB_LINK"
    echo "💣【 Reality (VLESS) 】节点信息如下："
    echo "$vl_link"; echo
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

  # 订阅令牌：默认用 UUID，可用 subid= 自定义。URL 靠它保密，勿外泄
  local token="${subid:-$uuid}"
  echo "$token" > "$SB_HOME/subtoken"

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
  warn "订阅经明文 HTTP 提供，令牌即密码，请勿外泄；不用时执行 sbbox sub off"
}

start_sub_server() {
  # 先确定命令与进程标记（标记 = 完整命令串，避免 exec -a 的 dash 兼容问题），
  # 再检查是否已在运行——SUB_MARK 不能是空串，否则 pgrep -f "" 匹配一切。
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
  pgrep -f "$SUB_MARK" >/dev/null 2>&1 && return 0
  nohup $runner >/dev/null 2>&1 &
  echo $! > "$SB_HOME/sub.pid"
  sleep 1
  if [ "$SERVICE_TYPE" = "cron" ] || [ "$IS_ROOT" != 1 ]; then
    crontab -l > /tmp/sbbox_sub_cron.tmp 2>/dev/null || true
    sed -i '/sbbox-sub\|http.server\|httpd -f/d' /tmp/sbbox_sub_cron.tmp 2>/dev/null || true
    echo "@reboot sleep 12 && nohup $runner >/dev/null 2>&1 &" >> /tmp/sbbox_sub_cron.tmp
    crontab /tmp/sbbox_sub_cron.tmp >/dev/null 2>&1
    rm -f /tmp/sbbox_sub_cron.tmp
  elif [ "$SERVICE_TYPE" = "systemd" ]; then
    cat > /etc/systemd/system/sbbox-sub.service <<EOF
[Unit]
Description=sbbox subscription server
After=network.target
[Service]
Type=simple
ExecStart=$runner
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable sbbox-sub >/dev/null 2>&1
    systemctl restart sbbox-sub >/dev/null 2>&1
  fi
  # 确认真的起来了，没起来则给出端口冲突等线索
  if pgrep -f "$SUB_MARK" >/dev/null 2>&1 || [ -f "$SB_HOME/sub.pid" ]; then
    info "订阅服务已启动（端口 $subport）"
  else
    warn "订阅服务启动可能失败（端口 $subport 可能被占用），执行 sbbox log 排查"
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
  rm -f /tmp/sbbox_sub_cron.tmp /tmp/sbbox_sub_cron.tmp
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
      case "$subhost" in *:*) subhost="[$subhost]" ;; esac
      if pgrep -f "http.server $port" >/dev/null 2>&1 || pgrep -f "httpd -f -p $port" >/dev/null 2>&1; then
        info "订阅服务：运行中"
      else
        warn "订阅服务：未运行（执行 sub=1 sbbox list 重新拉起）"
      fi
      echo "http://$subhost:$port/$token"
      ;;
    off) stop_sub_server ;;
    *) echo "用法: sbbox sub [show|off]" ;;
  esac
}

gen_client_sbox() {
  local ob=() tags=() json_file="$SB_HOME/sbox_client.json"

  if [ -n "$tup" ]; then
    ob+=('{
        "type": "tuic",
        "tag": "tuic",
        "server": "'"$add"'",
        "server_port": '"$port_tu"',
        "uuid": "'"$uuid"'",
        "password": "'"$uuid"'",
        "congestion_control": "bbr",
        "udp_relay_mode": "native",
        "zero_rtt_handshake": false,
        "heartbeat": "10s",
        "tls": { "enabled": true, "server_name": "'"$sni"'", "insecure": '"$msins"', "alpn": ["h3"] }
    }')
    tags+=("tuic")
  fi

  if [ -n "$hyp" ]; then
    ob+=('{
        "type": "hysteria2",
        "tag": "hysteria2",
        "server": "'"$add"'",
        "server_port": '"$port_hy2"',
        "password": "'"$uuid"'",
        "tls": { "enabled": true, "server_name": "'"$sni"'", "insecure": '"$msins"', "alpn": ["h3"] }
    }')
    tags+=("hysteria2")
  fi

  # 不生成 naive 出站：sing-box 的 naive 出站依赖 Cronet 库，官方发行版未内置，
  # 加进去会让整份客户端配置以 "cronet: library not found" 启动失败。
  # 服务端 naive 入站不受影响（无此依赖），客户端请用官方 naiveproxy。

  if [ -n "$vlp" ]; then
    ob+=('{
        "type": "vless",
        "tag": "reality",
        "server": "'"$add"'",
        "server_port": '"$port_vl"',
        "uuid": "'"$uuid"'",
        "flow": "xtls-rprx-vision",
        "tls": {
            "enabled": true,
            "server_name": "'"$ym_vl_re"'",
            "utls": { "enabled": true, "fingerprint": "chrome" },
            "reality": { "enabled": true, "public_key": "'"$public_key_s"'", "short_id": "'"$short_id_s"'" }
        }
    }')
    tags+=("reality")
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
    "log": { "level": "info", "timestamp": true },
    "dns": {
        "servers": [
            { "tag": "remote", "type": "https", "server": "1.1.1.1", "detour": "auto" },
            { "tag": "local", "type": "udp", "server": "223.5.5.5", "detour": "direct" }
        ],
        "rules": [ { "rule_set": "geosite-cn", "server": "local" } ],
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
    password: $uuid
    alpn: [h3]
    reduce-rtt: true
    congestion-controller: bbr
    sni: $sni
    skip-cert-verify: $msins"
    groups="$groups
      - tuic-$hostname_s"
  fi
  if [ -n "$hyp" ]; then
    proxies="$proxies
  - name: hysteria2-$hostname_s
    server: $add
    port: $port_hy2
    type: hysteria2
    password: $uuid
    alpn: [h3]
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
    username: $uuid
    password: $uuid
    tls: true
    sni: $sni
    skip-cert-verify: false"
    groups="$groups
      - naive-$hostname_s"
  fi
  if [ -n "$vlp" ]; then
    proxies="$proxies
  - name: reality-$hostname_s
    server: $add
    port: $port_vl
    type: vless
    uuid: $uuid
    flow: xtls-rprx-vision
    network: tcp
    udp: true
    tls: true
    servername: $ym_vl_re
    client-fingerprint: chrome
    reality-opts:
      public-key: $public_key_s
      short-id: $short_id_s"
    groups="$groups
      - reality-$hostname_s"
  fi
  cat > "$SB_HOME/clmi.yaml" <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://1.1.1.1/dns-query
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
  if [ "$SERVICE_TYPE" = "systemd" ] && [ "$IS_ROOT" = 1 ]; then
    cat > /etc/systemd/system/${SB_SERVICE}.service <<EOF
[Unit]
Description=sbbox sing-box service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$SB_BIN run -c $SB_CONF
Restart=on-failure
RestartSec=5s
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
    up)     upsingbox; sbrestart; exit ;;
    log)    sblog "$2"; exit ;;
    tune)   shift; cmd_tune "$@"; exit ;;   # 安装期已自动 on，off 用于回滚
    cert)   shift; cert_mgmt "$@"; exit ;;
    sub)    shift; cmd_sub "$@"; exit ;;
    doctor) doctor; exit ;;
    del)    cleandel; exit ;;
    help|-h|--help) showmode; exit ;;
  esac

  # 安装流程
  if [ -z "$tup" ] && [ -z "$hyp" ] && [ -z "$nvp" ] && [ -z "$vlp" ]; then
    if [ -x "$SB_BIN" ]; then
      # 已安装但未指定协议 → 显示帮助
      showmode
      status_show
      exit
    else
      error "未指定任何协议。请至少设置一个：tup=1 hyp=1 nvp=1 vlp=1"
      echo ""
      showmode
      exit 1
    fi
  fi

  mkdir -p "$SB_HOME"
  v4v6
  install_deps
  [ -x "$SB_BIN" ] || upsingbox
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
  [ -n "$tup" ] && touch "$SB_HOME/proto_tup"
  [ -n "$hyp" ] && touch "$SB_HOME/proto_hyp"
  [ -n "$nvp" ] && touch "$SB_HOME/proto_nvp"
  [ -n "$vlp" ] && touch "$SB_HOME/proto_vlp"
  echo "$ym" > "$SB_HOME/ym"
  [ -n "$hyjpt" ] && echo "$hyjpt" > "$SB_HOME/hyjpt"
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
        install_cert
        get_cert_paths
        [ "$CERT_OK" = 1 ] && { info "证书续期完成"; sbrestart; }
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
  local p=$1 proto=${2:-tcp}
  if command -v ss >/dev/null 2>&1; then
    ss -"$proto"ln 2>/dev/null | grep -q ":${p}[[:space:]]"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -"$proto"ln 2>/dev/null | grep -q ":${p}[[:space:]]"
  else
    # 无 ss/netstat 时退化为尝试 TCP 连接
    timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/$p" >/dev/null 2>&1
  fi
}

tcp_reachable() { timeout 3 bash -c "echo >/dev/tcp/127.0.0.1/$1" >/dev/null 2>&1; }

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

  # 需要证书的协议（naive）若证书缺失视为不通
  if [ "$nvp" = yes ] && [ "$CERT_OK" != 1 ]; then
    echo -e "Naiveproxy：${RED}证书缺失${NC}（naive 需要真实证书，不会启动）"
    issues=$((issues+1))
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

  [ "$tup" = yes ] && check_one Tuic "$port_tu" tcp
  [ "$hyp" = yes ] && check_one Hysteria2 "$port_hy2" udp
  [ "$nvp" = yes ] && check_one Naiveproxy "$port_nv" tcp
  [ "$vlp" = yes ] && check_one Reality "$port_vl" tcp

  if [ "$issues" -eq 0 ] && [ "$svc_down" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}全部节点正常${NC}"
    return 0
  fi

  # ---------- 自动修复 ----------
  echo ""
  echo "检测到 $issues 处问题，开始修复……"

  # 证书缺失 → 尝试申请（有 ym 时）
  if [ "$nvp" = yes ] && [ "$CERT_OK" != 1 ] && [ -n "$ym" ]; then
    install_cert && get_cert_paths
    [ "$CERT_OK" = 1 ] && echo -e "证书：${GREEN}已重新获取${NC}" && fixed=$((fixed+1))
  fi

  # 先重启服务，覆盖「进程挂了 / 端口没起来」的情况
  if [ "$svc_down" -eq 1 ] || [ "$issues" -gt 0 ]; then
    sbrestart
    sleep 2
    # 重启后复查每个有问题的端口，仍未恢复则重新生成配置
    for spec in "Tuic:$port_tu:tcp" "Hysteria2:$port_hy2:udp" "Naiveproxy:$port_nv:tcp" "Reality:$port_vl:tcp"; do
      name=${spec%%:*}; rest=${spec#*:}; p=${rest%%:*}; proto=${rest##*:}
      case "$name" in
        Tuic)       [ "$tup" = yes ] || continue ;;
        Hysteria2)  [ "$hyp" = yes ] || continue ;;
        Naiveproxy) [ "$nvp" = yes ] || continue ;;
        Reality)    [ "$vlp" = yes ] || continue ;;
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
  ym_vl_re=$(cat "$SB_HOME/ym_vl_re" 2>/dev/null || echo "apple.com")
  ym=$(cat "$SB_HOME/ym" 2>/dev/null || echo "")
  [ -f "$SB_HOME/proto_tup" ] && tup=yes
  [ -f "$SB_HOME/proto_hyp" ] && hyp=yes
  [ -f "$SB_HOME/proto_nvp" ] && nvp=yes
  [ -f "$SB_HOME/proto_vlp" ] && vlp=yes
  [ -f "$SB_HOME/port_tu" ] && port_tu=$(cat "$SB_HOME/port_tu")
  [ -f "$SB_HOME/port_hy2" ] && port_hy2=$(cat "$SB_HOME/port_hy2")
  [ -f "$SB_HOME/port_nv" ] && port_nv=$(cat "$SB_HOME/port_nv")
  [ -f "$SB_HOME/port_vl" ] && port_vl=$(cat "$SB_HOME/port_vl")
  [ -f "$SB_HOME/rk/public_key" ] && public_key_s=$(cat "$SB_HOME/rk/public_key")
  [ -f "$SB_HOME/rk/short_id" ] && short_id_s=$(cat "$SB_HOME/rk/short_id")
  [ -f "$SB_HOME/rk/private_key" ] && private_key_s=$(cat "$SB_HOME/rk/private_key")
  [ -f "$SB_HOME/hyjpt" ] && hyjpt=$(cat "$SB_HOME/hyjpt")
  # 订阅曾启用过就保持启用，令牌/端口沿用，避免 list 后订阅地址变化
  if [ -f "$SB_HOME/subtoken" ]; then
    sub=1
    subid=$(cat "$SB_HOME/subtoken")
    subport=$(cat "$SB_HOME/subport" 2>/dev/null)
  fi
  if cert_ready; then CERT_OK=1; ym=$(cat "$SB_HOME/ym" 2>/dev/null || echo ""); else CERT_OK=0; fi
  hostname_s=$(hostname 2>/dev/null || echo vps)
}

main "$@"

