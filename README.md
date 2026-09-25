# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box 2026 协议安全加固代理脚本

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**语言：** **简体中文** · [English](./README.en.md)

基于 **sing-box 1.14 单内核** 深度部署，落地 2026 年最新协议梯队：

| 梯队次序 | 协议方案 | 定位与核心特性 | 传输与伪装 | 证书需求 |
| :--- | :--- | :--- | :--- | :--- |
| 🥇 **高速主力** | **Hysteria2** | 极速高吞吐 / 抗恶劣丢包 / Brutal 拥塞控制 | QUIC (H3) + salamander 混淆 + 端口跳跃 | 真实证书 / 自签+指纹固定 |
| 🥈 **新一代 TCP 主力** | **AnyTLS** | 彻底消除 TLS-in-TLS 特征，抗深度主动探测与跨域延迟优化 | TCP + TLS 1.3 + 自适应 8 级填充 Padding | 真实证书 / 自签+指纹固定 |
| 🥉 **高伪装主力** | **NaiveProxy** | Chromium 原生网络栈内核级反探测伪装 | HTTP/3 (QUIC) & HTTP/2 双通道 | **强制真实证书** |
| 4 **QUIC 备选** | **TUIC v5** | 低延迟 UDP 加速 / 标准 QUIC 0-RTT | QUIC (H3) | 真实证书 / 自签+指纹固定 |
| 5 **兼容老客户端 (可选)** | **VLESS-Reality** | 全客户端直连兼容（免域名免证书；按需显式传 `reap=1` 开启） | TCP (XTLS Vision) | **免域名 / 免证书（借用官方 SNI）** |

> 默认使用 **官方正式版内核（stable）**，默认开启 **QUIC 与 BBR 拥塞控制**，入站最低兼容 **TLS 1.2 / HTTP 1.1**。

集成了：
- **内核级流控调优**（移植自 [`ShJChow/Xray-core-xhttp-cdn-tuned`](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned) 的 `xh tuning on`）：BBR、内存分档缓冲区、TFO、文件句柄等，安装期自动开启，可一键回滚
- **acme.sh 证书申请**：Naiveproxy / Hysteria2 / Tuic 使用真实 TLS 证书
- **OpenSSL 动态指纹与 SHA-256 锁定**：安装时自动通过 OpenSSL 提取证书的 HEX 指纹（`pcs`）、DER SHA256（`pinSHA256`）与 SPKI 公钥 Base64，默认注入 Tuic / Hysteria2 / Naive 节点及客户端配置，防中间人劫持

---

## 目录

- [一、前置准备材料（域名、Cloudflare 与证书）](#一前置准备材料)
  - [1. 域名解析配置](#1-域名解析配置)
  - [2. Cloudflare 控制台设置](#2-cloudflare-控制台设置)
  - [3. SSL 证书申请详细步骤（acme-yg / acme.sh）](#3-ssl-证书申请详细步骤)
- [二、安全与性能设计](#二安全与性能设计)
- [三、`DefaultLimitNOFILE` 与 `fs.nr_open` 的对齐](#三defaultlimitnofile-与-fsnr_open-的对齐)
- [四、快速开始与一键安装](#四快速开始与一键安装)
  - [1. 前置条件](#1-前置条件)
  - [2. 一键安装](#2-一键安装)
- [五、环境变量参考](#五环境变量参考)
- [六、管理命令 `sbbox`](#六管理命令-sbbox)
- [七、内核版本管理](#七内核版本管理)
- [八、v2rayN 订阅与客户端配置](#八v2rayn-订阅与客户端配置)
- [九、四条节点实测吞吐](#九四条节点实测吞吐)
- [十、版本迭代与核心调优演进记录 (v2.1 - v2.7.22)](#十版本迭代与核心调优演进记录-v21---v2722)
- [十一、免责声明](#十一免责声明)

---

## 一、前置准备材料

在运行部署脚本前，请准备好 **2 个解析到本机 VPS IP 的子域名**（推荐托管在 Cloudflare）：
- **域名 1（主域名 / 直连 / Reality 域名）**：例如 `reality.example.com`（或 `naive.example.com`）
- **域名 2（次域名 / CDN 域名）**：例如 `cdn.example.com`

>  **免费域名获取参考**：[DNSHE](https://my.dnshe.com) 或 [DigitalPlat](https://dash.domain.digitalplat.org)

---

### 1. 域名解析配置

在 Cloudflare DNS 控制台中添加两条 `A` 记录指向你的 VPS 公网 IP：

| 记录类型 | 域名名称 | 目标 IP | Cloudflare 代理状态（云朵颜色） | 用途 |
| :--- | :--- | :--- | :--- | :--- |
| **A 记录** | `reality.example.com` | `你的 VPS IP` |  **仅 DNS（灰色云朵）** | 用于证书申请与 Naiveproxy / Reality / Hy2 / Tuic 直连 |

>  **重要提示**：Naiveproxy (H3/H2)、Hysteria2 与 Tuic 均基于 UDP/QUIC 或专用端口直连，用于直连代理服务的主域名在 Cloudflare DNS 中**必须保持灰色云朵（仅 DNS）**，不要开启 CDN 代理，以保证极速低延迟与全协议兼容。

---

### 2. Cloudflare 控制台设置

在 Cloudflare 仪表盘中开启以下开关（若使用 Cloudflare 托管解析）：

1. **SSL/TLS** ➡️ **概述**：加密模式选择 **完全（严格）/ Full (strict)**；
2. **SSL/TLS** ➡️ **边缘证书**：最低 TLS 版本选择 **TLS 1.2**；
3. **网络（Network）**：
   -  开启 **gRPC**
   -  开启 **WebSockets**
   -  开启 **HTTP/3 (with QUIC)**
   -  开启 **0-RTT 连接恢复**
4. **规则（Rules） ➡️ Cache Rules（可选优化）**：
   - 对你的 XHTTP / 代理路径设置 **Bypass Cache**（绕过缓存，避免流式响应被分块缓冲）。

---

### 3. SSL 证书申请详细步骤

本方案在安装时会自动使用 acme.sh 申请证书（例如参数 `alns=1 ym=你的域名`）。如果你之前证书申请失败，或希望提前使用著名的 **`acme-yg` 一键脚本** 申请好证书，请按以下步骤操作：

#### 步骤 1：释放 80 端口（如果已有服务在运行）
```bash
systemctl stop nginx xray sing-box sbbox caddy apache2 2>/dev/null || true
```

#### 步骤 2：执行 acme-yg 证书申请脚本
```bash
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
```

#### 步骤 3：交互式菜单详细选型与操作
1. **进入菜单**：输入 `1` 选择 **【ACME 申请证书】**；
2. **选择申请模式**：
   - **推荐方式 A（80 端口模式）**：输入 `1`（Standalone 模式，需确保 80 端口未被占用且域名 1 已灰云直连解析到本机 IP）；
   - **推荐方式 B（Cloudflare API 模式）**：输入 `2`（无需停用 80 端口，输入 CF Global API Key 或 Token 即可全自动签发）；
3. **输入主域名与次域名（双域名 SAN 证书）**：
   - **主域名**：输入你的直连域名（如 `reality.example.com` 或 `naive.example.com`）
4. **安装并输出证书路径**： 申请成功后，证书会自动保存在 `/root/ygkkkca/` 目录下。



>  **提示**：部署脚本在安装时会自动优先复用 `/etc/ssl/private/`、`/root/ygkkkca/` 或 `~/.acme.sh/` 目录下已存在的匹配有效证书，无需重复申请。

---

## 二、安全与性能设计

| 加固项 | 说明 |
|--------|------|
| TLS 证书校验 | `insecure=0`（强制校验） |
| SHA-256 证书指纹锁定 | **默认安装即开启**：自动调用 OpenSSL 提取活动证书 HEX 指纹（`pcs`）、DER SHA256（`pinSHA256`）及 SPKI 公钥 Base64，全量注入 Tuic / Hysteria2 / Naiveproxy 节点与客户端配置，防中间人劫持 |
| Naiveproxy 证书 | **强制 acme 真实证书** |
| 最低协议兼容 | **TLS 1.2**（`min_version: "1.2"`）+ ALPN `["h3", "h2", "http/1.1"]`，兼顾旧客户端与极速新协议 |
| Hysteria2 伪装 | `masquerade` 反代真实站点（默认 www.bing.com），未认证探测拿到真实页面 |
| Hysteria2 拥塞控制 | `ignore_client_bandwidth: true` + `bbr_profile: standard`（服务端主导，稳定公平） |
| Hysteria2 混淆 | `obfs: salamander`（默认开启），混淆密码独立随机 |
| Tuic 极速握手 | `zero_rtt_handshake: true` + `congestion_control: bbr` |
| 文件句柄 | 1048576（写进主 unit，不依赖 drop-in） |
| systemd 默认句柄 | 调优时把 `DefaultLimitNOFILE` 对齐到 `fs.nr_open`，避免其他调优脚本留下的越界值让系统服务报 `205/LIMITS` |
| 协议凭据 | **每协议独立随机密钥**，任一泄露不牵连其他 |
| 出站 DNS | **DoT 加密**（1.1.1.1 / 9.9.9.9） |
| 内网访问 | `ip_is_private` 一律拒绝，防止内网与云元数据接口被穿透 |
| 垃圾邮件滥用 | 默认阻断出站 25/465/587 与 SMB 端口（`blkport=0` 关闭） |
| 服务端日志 | 默认 `error`；`sblevel=off` 完全不落盘 |

---

## 三、`DefaultLimitNOFILE` 与 `fs.nr_open` 的对齐

`fs.nr_open` 是单进程句柄数的内核硬上限，systemd 的 `DefaultLimitNOFILE` 无论写多大都越不过它。两者一旦倒挂（`DefaultLimitNOFILE > fs.nr_open`），systemd 拉起任何**没有自己声明 `LimitNOFILE`** 的服务时，都会在设限那一步直接失败：

```
Failed to adjust resource limit RLIMIT_NOFILE: Operation not permitted
Failed at step LIMITS spawning ...: Operation not permitted
Main process exited, code=exited, status=205/LIMITS
```

这个坑不是本脚本自己制造的，而是本脚本把 `fs.nr_open` 钉到 `1048576` 之后，**会让别的调优脚本早先写下的更大的 `DefaultLimitNOFILE` 变成非法值**。实测踩过：某第三方 TCP 调优脚本写了 `DefaultLimitNOFILE=2097152`，本脚本随后设 `fs.nr_open=1048576`，结果 `logrotate`、`apt-daily`、`systemd-timedated`、`netfilter-persistent` 等十个单元全部起不来；`sing-box` 反而幸免——因为它的主 unit 与 drop-in 自带 `LimitNOFILE=1048576`，压根没走默认值。**这类故障最难查的地方就在这里：代理本身一切正常，坏掉的是系统里其他所有服务。**

因此 `sbbox tune on`（安装期自动执行）设完 `fs.nr_open` 会检查一次实际生效的 `DefaultLimitNOFILE`，越界（含 `infinity`）就写：

```ini
# /etc/systemd/system.conf.d/10-sbbox-nofile.conf
[Manager]
DefaultLimitNOFILE=1048576
```

写 `system.conf.d/` 下的 drop-in 而不是改 `/etc/systemd/system.conf` 本体：drop-in 优先级更高，别的脚本以后再改主文件也覆盖不掉；`sbbox tune off` 删掉这一个文件即可干净回滚。

自查：

```bash
systemctl show -p DefaultLimitNOFILE --value   # 不得大于下一行
sysctl -n fs.nr_open
systemctl --failed                             # 有 205/LIMITS 就是踩了这个坑
```

---

## 四、快速开始与一键安装

### 1. 前置条件

- VPS：Ubuntu / Debian / CentOS / Alpine（amd64 或 arm64）
- **推荐 root 权限**（非 root 也可用，走 crontab 自启）
- 如需 Naiveproxy：需要域名并解析到 VPS，`alns=1` 自动申请证书（或提前放置好证书）

### 2. 一键安装

```bash
# 1. 推荐四大主力梯队一键安装（含高速 Hysteria2 + AnyTLS + NaiveProxy + Tuic，需域名解析）：
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  hyp=1 anyp=1 nvp=1 tup=1 alns=1 ym=your.domain.com

# 2. 全五协议完整安装（四大主力 + 兼容旧客户端的 VLESS-Reality TCP 节点）：
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  hyp=1 anyp=1 nvp=1 tup=1 reap=1 alns=1 ym=your.domain.com

# 3. 无域名极速安装（含 Hysteria2 + Tuic + Reality，免域名、免申请证书）：
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  hyp=1 tup=1 reap=1
```

> `alns=1` 时 acme.sh 走 standalone 模式，需要 **80 端口空闲**、域名 A 记录已解析到本机。
> 若未提供 `ym=域名`，脚本会**交互提示输入**（不写入命令行历史）。
> `reap=1`（VLESS-Reality TCP 节点）完全**免域名、免证书**，借用官方优质 SNI 伪装抗封锁，按需显式传 `reap=1` 启用（默认精简关闭）。

---

## 五、环境变量参考

| 变量 | 默认 | 说明 |
|------|------|------|
| `hyp` | 空 | 🥇 启用 Hysteria2 + TLS 节点（高速主力，支持端口跳跃与混淆，启用 `hyp=1`） |
| `anyp` | 空 | 🥈 启用 AnyTLS + TLS 节点（新一代 TCP 主力，抹除 TLS-in-TLS 特征与跨域延迟优化，启用 `anyp=1`） |
| `nvp` | 空 | 🥉 启用 NaiveProxy (H3+H2，Chromium 内核级反探测伪装，启用 `nvp=1`，需证书） |
| `tup` | 空 | 4 启用 TUIC v5 节点（低延迟 UDP 加速 / 标准 QUIC 0-RTT，启用 `tup=1`） |
| `reap` | 空 | 5 可选启用最新 VLESS-Reality TCP + XTLS-Vision 节点（免域名免证书；按需开启用 `reap=1`） |
| `reap_sni` | `gateway.icloud.com` | Reality 目标 SNI 伪装域名（支持任意合规 TLS 1.3 域名） |
| `port_any` | 随机 | 指定 AnyTLS 监听端口（默认 28443 或随机 10000-65535） |
| `port_hy2` / `port_nv` / `port_tu` / `port_rea` | 随机 | 指定各协议固定端口（10000-65535） |
| `alns` | 空 | 启用 acme 证书申请（`alns=1`） |
| `ym` | 空 | acme 证书域名（启用 alns 时必需） |
| `hyjpt` | 空 | Hysteria2 跳跃端口，如 `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1（默认开启）** | Hysteria2 混淆协议：可选 `salamander` 或 1.14 新增 `gecko`；关闭用 `hyobfs=0` |
| `hyobfs_pw` | 独立随机 | Hysteria2 混淆密码（与认证密码分离） |
| `hymask` | `https://www.bing.com` | Hysteria2 伪装：反代真实站点抗主动探测；静态 404 用 `hymask=none` |
| `sblevel` | `error` | 服务端日志级别，`off` 完全不落盘（日志会记录访问过的域名） |
| `blkport` | **1（默认开启）** | 阻断出站 25/465/587/SMB 端口，防凭据外泄后被拿去发垃圾邮件；关闭用 `blkport=0` |
| `hyup` / `hydown` | 空 | Hysteria2 上/下行 Mbps，**两个都设**才启用 Brutal 拥塞控制 |
| `sub` | **1（默认开启）** | 启用 v2rayN / 通用订阅服务（默认开启 1；关闭用 `sub=0` 或 `sbbox sub off`） |
| `subport` | 随机 | 订阅服务端口 |
| `subid` | 独立随机 | 订阅令牌（URL 路径，相当于密码） |
| `sub_nonaive` | 空 | 剔除 Naiveproxy 节点（客户端不支持 naive+ 链接时用 `sub_nonaive=1`） |
| `uuid` | 自动生成 | 自定义 UUID（Tuic / Reality 用；各协议密码独立随机，不再复用 UUID） |
| `name` | 空 | 节点名称前缀 |
| `noautoup` | 空 | 关闭每周内核自动升级（`noautoup=1`） |
| `sbrel` | **`stable`（默认）** | 内核版本通道：默认只取官方最新正式版（`stable`）；跟踪 beta/rc 用 `sbrel=pre` |
| `tuicuos` | **0（默认原生 UDP）** | Tuic UDP 中继模式：默认原生 UDP 防断流；QUIC 流用 `tuicuos=1` |
| `tuils` | **1（默认开启）** | Tuic TLS 加固（证书公钥 SHA-256 固定）；关闭用 `tuils=0` |
| `dns_optimistic` | **1（默认开启）** | sing-box 1.14 乐观 DNS 缓存并持久化到本地数据库，消除解析长尾延迟；关闭用 `dns_optimistic=0` |
| `api` | **1（默认开启）** | sing-box 1.14 原生 API 服务（监听 127.0.0.1 独立五位数随机端口），供 `sbbox status` 实时查看运行指标；关闭用 `api=0` |

---

## 六、管理命令 `sbbox`

安装完成后，直接在终端执行 `sbbox`：

| 命令 | 功能 |
|------|------|
| `sbbox list` | 显示全部节点链接 + 客户端配置 |
| `sbbox status` | 服务运行状态 + 流控状态 |
| `sbbox res` | 重启 sing-box |
| `sbbox tune show` | 查看内核流控参数 |
| `sbbox tune off` | 回滚全部内核调优 |
| `sbbox sub` | 显示订阅地址 |
| `sbbox sub off` | 关闭订阅服务 |
| `sbbox speed [上行] [下行]` | 配置客户端上/下行并激活 Hysteria2 与 TCP Brutal（如 `100 1000`） |
| `sbbox speed bbr` | 清空带宽限额，客户端与服务端统一切回 BBR（默认推荐，见第十一节第 2 条） |
| `sbbox brutal [show\|on\|off\|speed\|add\|del]` | 查看、开启/关闭 TCP Brutal (HyNetworks/tcp-brutal) 及管理限速规则（默认自适应本机最大带宽 95%） |
| `sbbox port [tu] [hy2] [nv]` | 更换节点端口（无参数自动分配 10000-65535 随机端口并同步配置与订阅） |
| `sbbox cert status` | 查看证书有效期 |

| `sbbox cert renew` | 强制续期证书 → 落地 → 重启 → 重生成客户端配置 |
| `sbbox cert sync` | 只做「续期之后」那半段：把已续期的证书落地、重启服务、按新指纹重生成客户端配置。不触发签发，证书未变时直接跳过 |
| `sbbox cert hook` | 把 `sbbox cert sync` 挂进 acme.sh 的 `reloadcmd`（保留其中原有命令，幂等）。**装完 sbbox 必做一次**，见第十一节第 1 条 |
| `sbbox up` | 升级 sing-box 内核（默认 stable 官方正式版；失败自动回滚） |
| `sbbox log [N]` | 查看最近 N 行日志（默认 20） |
| `sbbox rotate` | 轮换全部协议密码、混淆密码与订阅令牌（端口/UUID/证书不变，客户端需重新导入） |
| `sbbox doctor` | 自检并尝试修复 |
| `sbbox del` | 完全卸载 |

---

## 七、内核版本管理

安装与 `sbbox up` 默认从 **SagerNet 官方最新正式版（releases/latest）拉取内核**。

- **默认通道是 `stable`**：只跟踪稳定正式版。
- 若想体验最新测试特性，可用 `sbrel=pre` 跟踪 pre-release（beta/rc）：

```bash
sbrel=stable sbbox up     # 升级/切换到最新正式版（默认）
sbrel=pre sbbox up        # 升级/切换到 pre 通道
```

---

## 八、v2rayN 订阅与客户端配置

脚本默认开启订阅服务（`sub=1`），自动生成 base64 订阅并在本机启动 HTTP 静态托管服务；如需关闭可传 `sub=0` 或执行 `sbbox sub off`。

### 1. 证书指纹与 SHA-256 自动注入（默认开启）
脚本在安装与生成配置时，会自动调用 OpenSSL 从活动证书提取以下信息并注入：
- **Tuic 节点**：注入 `pcs=HEX指纹` 与 `pinSHA256=DER哈希`；Sing-box 客户端注入 `certificate_public_key_sha256`（Tuic 传输层基于 QUIC，严禁注入 uTLS `fp=chrome`，防止触发 `unsupported usage for uTLS` 断连）。
- **Hysteria2 节点**：注入 `pinSHA256=DER哈希` 与 `pcs=HEX指纹`；Sing-box 客户端注入 `certificate_public_key_sha256`。
- **Naiveproxy 节点**：注入 `pcs=HEX指纹` 与 `pinSHA256=DER哈希`，默认开启 QUIC (H3) 与 HTTP/2 双轨极速通道。

### 2. 节点排列与客户端配置文件
Naiveproxy 节点按 QUIC (H3) 优先排列：
- `naive+quic://` / `http3://`：QUIC (H3) 极速节点（默认推荐）
- `naive+https://` / `http2://`：HTTP/2 兼容节点（TCP 回退备用）

客户端聚合配置文件位于：
- sing-box 客户端：`~/sbbox/sbox_client.json`
- Clash / Mihomo：`~/sbbox/clmi.yaml`

### 3. 订阅二维码与图片直链
订阅展示命令（`sbbox sub` 或 `sbbox list`）会自动生成与展示订阅二维码：
- **终端字符二维码**：直接在终端渲染紧凑高对比度 ANSI UTF-8 字符二维码，手机客户端（Shadowrocket、sing-box、v2rayN、NekoBox）打开扫一扫即可秒导全部节点。
- **网页图片直链**：内置订阅服务器提供 `/qr.png` 路由直出 PNG 二维码图片（如 `http://<IP>:<PORT>/qr.png`），方便通过浏览器保存或扫码。

---

## 九、四条节点实测吞吐

在服务端本机为每条节点单独起一个 SOCKS 入口，**9 轮交替轮询**采样：每轮先测一次不走代理的直连基线，再依次测各节点，因此同一轮内所有条目共享同样的上游状态。下载取 `cachefly.cachefly.net/50mb.test`，握手取 `www.gstatic.com/generate_204`。表中为 **9 次采样的中位数（最小–最大）**。

| 节点 | 端口 | 传输 | 下载 MB/s 中位（范围） | 握手 ms 中位（范围） |
| :--- | :--- | :--- | ---: | ---: |
| *直连基线（不走代理）* | — | — | *681.6（277.8–714.2）* | *23（21–26）* |
| **Tuic** | 20011/UDP | QUIC (H3) | 92.9（63.1–107.9） | 24（21–47） |
| **Hysteria2** | 39259/UDP | QUIC (H3) + salamander | 31.0（29.5–37.6） | 24（20–67） |
| **Naiveproxy H3** | 47631/UDP | HTTP/3 (QUIC) | 59.6（49.9–79.5） | 25（22–34） |
| **Naiveproxy H2** | 47631/TCP | HTTP/2 | **169.7（144.6–192.3）** | 28（23–244） |

> 订阅里的 `naive+quic://` 与 `http3://` 是同一个 H3 入站的两种客户端写法，`naive+https://` 与 `http2://` 同理对应 H2，因此四条测试已覆盖全部六条订阅节点。

怎么读这张表：

- **测的是服务端侧的协议栈开销，不是你的实际网速。** 客户端跑在 VPS 本机、经公网 IP 回环，不含最后一公里。直连基线 681.6 MB/s 说明上游几乎不构成瓶颈，因此各节点的差距基本可归因于协议栈本身——但这也意味着**表里没有任何一个数字是你在真实跨境链路上能跑到的**。
- **必须看范围，不能只看中位数。** 早期用单次采样、且测速源本身抖动到数倍时，节点间的排名完全是噪声。换成快速稳定的源并取 9 次中位数后结论才立得住。
- **H2 是 H3 的近三倍（169.7 对 59.6）**，同一个 Naiveproxy 入站、同一个端口，差别只在承载。QUIC 在用户态收发包，零丢包环境下天然吃亏；内核态 TCP 在理想链路上占优是正常结果。**真实跨境链路一旦出现丢包，这个排序会反过来**——这正是订阅默认把 H3 排在首位的原因，不要照着这张表去选节点。
- **Hysteria2 是最慢也最稳的一档**（31.0 MB/s，波动最小）。瓶颈在协议自身的拥塞控制与用户态包处理，而非链路——同机直连有 681 MB/s 可作对照。它的价值在弱网丢包场景，本测试环境（零丢包）恰好是它最不占优的场景，**吞吐低于 Tuic 属预期行为，不是故障**。
- 三个协议的握手中位数都在 30 ms 以内，与直连基线的 23 ms 差距很小，说明 `zero_rtt_handshake` 与 BBR 均已生效。H2 那个 244 ms 的上界是单次离群，中位数未受影响。

逐条自检用 `sbbox doctor`；若某条节点在客户端不通而本机自测正常，问题在该设备到 VPS 的网络路径，而非服务端配置。

---

## 十、版本迭代与核心调优演进记录 (v2.1 - v2.7.22)

本项目经跨洋弱网环境（160ms+ / 1% 丢包）数十轮实测迭代，核心演进总结如下：

| 演进领域 | 涉及版本 | 核心技术方案与调优结论 |
| :--- | :--- | :--- |
| **四大主力协议收敛** | v2.7.0–v2.7.22 | 聚焦四大主力（Hysteria2 / AnyTLS / NaiveProxy / TUIC）；v2.7.22 彻底下线 Reality 并默认不安装，引入 `close_port` 自愈清理防火墙 |
| **AnyTLS / NaiveProxy 深度调优** | v2.7.1–v2.7.20 | AnyTLS 启用 8 级填充防 TLS-in-TLS，深度调优会话池复用；NaiveProxy 严格遵守 Cronet 禁忌（禁 insecure，禁 extra_headers Padding） |
| **流控加固与 QDoS 防御** | v2.1–v2.7.21 | 外置 Hy2 接收窗口升至 8M/20M 根治慢线上传限速；默认关闭大范围端口跳跃；Netfilter hashlimit 令牌桶抗洪；TUIC 严禁注入 uTLS |
| **客户端生态兼容与全自动 TUN** | v2.7.16–v2.7.21 | 剔除 1.15+ FATAL 阻断项（`download_detour`/`store_rdrc`）；客户端订阅原生内置 `tun-in` + FakeIP，解决首连远程 DNS 往返延迟 |
| **系统底层网络性能与安全** | v2.5.0–v2.7.20 | 协同 BBRv3 与 TCP Brutal；维持 64MB Socket 缓冲；网卡多队列 RPS/RFS 软中断均衡；`fs.suid_dumpable=0` 防内存转储；内置 WARP 解锁流媒体 |

---

## 十一、免责声明

本项目仅供网络技术研究与学习交流使用。使用者须自行遵守所在国家/地区的法律法规，因使用本脚本产生的一切后果由使用者自行承担。
