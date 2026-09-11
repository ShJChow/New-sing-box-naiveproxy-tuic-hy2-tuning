# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box 2026 六协议安全加固代理脚本

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**语言：** **简体中文** · [English](./README.en.md)

基于 **sing-box 1.14 单内核** 深度部署，落地 2026 年最新六层协议梯队：

| 梯队次序 | 协议方案 | 定位与核心特性 | 传输与伪装 | 证书需求 |
| :--- | :--- | :--- | :--- | :--- |
| 🥇 **高速主力** | **Hysteria2** | 极速高吞吐 / 抗恶劣丢包 / Brutal 拥塞控制 | QUIC (H3) + salamander 混淆 + 端口跳跃 | 真实证书 / 自签+指纹固定 |
| 🥈 **兼容主力** | **VLESS-Reality** | 全客户端极速直连（默认必开） | TCP (XTLS Vision) | **免域名 / 免证书（借用官方 SNI）** |
| 🥉 **新一代候选** | **AnyTLS** | 彻底消除 TLS-in-TLS 特征，抗深度主动探测 | TCP + TLS + 自适应填充 Padding | 真实证书 / 自签+指纹固定 |
| 4 **特殊形态** | **NaiveProxy** | Chromium 原生网络栈内核级伪装 | HTTP/3 (QUIC) & HTTP/2 双通道 | **强制真实证书** |
| 5 **QUIC 备选** | **TUIC v5** | 低延迟 UDP 加速 / 标准 QUIC 0-RTT | QUIC (H3) | 真实证书 / 自签+指纹固定 |

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
- [十、v2.1.0 实测诊断与修复记录](#十v210-实测诊断与修复记录)
- [十一、v2.2.0 实测诊断与修复记录](#十一v220-实测诊断与修复记录)
- [十二、v2.3.2 实测诊断与修复记录](#十二v232-实测诊断与修复记录)
- [十三、v2.3.3 密钥轮换与外置 Hysteria2 修复记录](#十三v233-密钥轮换与外置-hysteria2-修复记录)
- [十四、v2.5.0 握手提速与「全部采用最新特性」](#十四v250-握手提速与全部采用最新特性)
- [十五、v2.5.1 ECN 与 BBR 版本查明](#十五v251-ecn-与-bbr-版本查明)
- [十六、v2.5.2 tcp-brutal 在内核 7.1+ 上的静默失效修复](#十六v252-tcp-brutal-在内核-71-上的静默失效修复)
- [十七、v2.5.4 BBRv3 上的 25 样本回归基线](#十七v254-bbrv3-上的-25-样本回归基线)
- [十八、v2.5.5 large 档 tcp_rmem/tcp_wmem 上限补齐到 64MB](#十八v255-large-档-tcp_rmemtcp_wmem-上限补齐到-64mb)
- [十九、v2.5.6 回滚 v2.5.5 的 64MB 缓冲上限](#十九v256-回滚-v255-的-64mb-缓冲上限)
- [二十、v2.6.x sing-box 1.14 AnyTLS 落地与全客户端订阅自适应](#二十v26x-sing-box-114-anytls-落地与全客户端订阅自适应)
- [二十一、v2.7.0 架构精简：剔除 ShadowTLS 全面回归五大稳固主力梯队](#二十一v270-架构精简剔除-shadowtls-全面回归五大稳固主力梯队)
- [二十二、免责声明](#二十二免责声明)

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
   - **泛域名 / 附加域名**：输入你的 CDN 域名（如 `cdn.example.com`）
4. **安装并输出证书路径**： 申请成功后，证书会自动保存在 `/root/ygkkkca/` 目录下。

#### 步骤 4：将证书部署到标准路径（一键复制）
```bash
mkdir -p /etc/ssl/private
cp -f /root/ygkkkca/reality.example.com/fullchain.cer /etc/ssl/private/fullchain.cer 2>/dev/null || cp -f /root/ygkkkca/cert.crt /etc/ssl/private/fullchain.cer 2>/dev/null || true
cp -f /root/ygkkkca/reality.example.com/private.key /etc/ssl/private/private.key 2>/dev/null || cp -f /root/ygkkkca/private.key /etc/ssl/private/private.key 2>/dev/null || true
chmod 600 /etc/ssl/private/*.key /etc/ssl/private/*.cer 2>/dev/null || true
```

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
# 推荐全协议一键安装（含最新 TCP Reality + Tuic + Hysteria2 + Naiveproxy）：
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  reap=1 tup=1 hyp=1 nvp=1 alns=1 ym=your.domain.com

# 无域名极速安装（含最新 TCP Reality + Tuic + Hysteria2，免申请证书）：
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  reap=1 tup=1 hyp=1
```

> `alns=1` 时 acme.sh 走 standalone 模式，需要 **80 端口空闲**、域名 A 记录已解析到本机。
> 若未提供 `ym=域名`，脚本会**交互提示输入**（不写入命令行历史）。
> `reap=1`（VLESS-Reality TCP 节点）完全**免域名、免证书**，借用官方优质 SNI 伪装抗封锁，默认安装即一并启用。

---

## 五、环境变量参考

| 变量 | 默认 | 说明 |
|------|------|------|
| `reap` | **1（默认开启）** | 启用最新 VLESS-Reality TCP + XTLS-Vision 节点（免域名免证书；关闭用 `reap=0`） |
| `reap_sni` | `gateway.icloud.com` | Reality 目标 SNI 伪装域名（支持任意合规 TLS 1.3 域名） |
| `tup` / `hyp` / `nvp` | 空 | 协议开关，非空即启用（至少显式指定一个协议才会进入安装流程）|
| `alns` | 空 | 启用 acme 证书申请（`alns=1`） |
| `ym` | 空 | acme 证书域名（启用 alns 时必需） |
| `hyjpt` | 空 | Hysteria2 跳跃端口，如 `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1（默认开启）** | Hysteria2 混淆协议：可选 `salamander` 或 1.14 新增 `gecko`；关闭用 `hyobfs=0` |
| `hyobfs_pw` | 独立随机 | Hysteria2 混淆密码（与认证密码分离） |
| `hymask` | `https://www.bing.com` | Hysteria2 伪装：反代真实站点抗主动探测；静态 404 用 `hymask=none` |
| `sblevel` | `error` | 服务端日志级别，`off` 完全不落盘（日志会记录访问过的域名） |
| `blkport` | **1（默认开启）** | 阻断出站 25/465/587/SMB 端口，防凭据外泄后被拿去发垃圾邮件；关闭用 `blkport=0` |
| `hyup` / `hydown` | 空 | Hysteria2 上/下行 Mbps，**两个都设**才启用 Brutal 拥塞控制 |
| `sub` | 空 | 启用 v2rayN 订阅服务（`sub=1`） |
| `subport` | 随机 | 订阅服务端口 |
| `subid` | 独立随机 | 订阅令牌（URL 路径，相当于密码） |
| `sub_nonaive` | 空 | 剔除 Naiveproxy 节点（客户端不支持 naive+ 链接时用 `sub_nonaive=1`） |
| `uuid` | 自动生成 | 自定义 UUID（Tuic / Reality 用；各协议密码独立随机，不再复用 UUID） |
| `port_tu` / `port_hy2` / `port_nv` / `port_rea` | 随机 | 指定各协议固定端口 |
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

安装时加 `sub=1`，脚本会生成 base64 订阅并在本机启动 HTTP 静态托管服务。

### 1. 证书指纹与 SHA-256 自动注入（默认开启）
脚本在安装与生成配置时，会自动调用 OpenSSL 从活动证书提取以下信息并注入：
- **Tuic 节点**：注入 `fp=chrome`、`pcs=HEX指纹` 与 `pinSHA256=DER哈希`；Sing-box 客户端注入 `certificate_public_key_sha256`。
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

## 十、v2.1.0 实测诊断与修复记录

本节记录一次在 **Oracle ARM (4 核 24G) / Ubuntu 26.04 / kernel 7.0** 上的完整诊断。
**每一条都有实测数据支撑，包括两条"测了但结论与预期相反"的项目。**

### 1.〔严重·安全〕私有地址防护对「域名目标」完全失效

`sb.json` 里原有的拦截规则本意是挡住客户端打内网服务与 `169.254.169.254` 云元数据接口：

```json
{ "action": "reject", "ip_is_private": true }
```

**但 `ip_is_private` 只比对目标 IP。客户端只要把目标写成域名，规则就不匹配、直接放行。**

实测（经 naive 节点，`--socks5-hostname` 表示把域名交给服务端解析）：

| 目标写法 | 修复前 | 修复后 |
| :--- | :--- | :--- |
| `http://127.0.0.1/`（字面 IP） | 被阻断 ✅ | 被阻断 ✅ |
| `http://127.0.0.1.nip.io/`（域名） | **301（打通了本机 nginx）** ❌ | 被阻断 ✅ |
| `https://www.cloudflare.com/`（正常流量） | 200 ✅ | 200 ✅ |

`301` 是本机 nginx 80 端口的应答——**任意客户端都能借此访问服务器的回环与内网服务**，
包括 sing-box 自己的 API 端口、同机其他代理的本地入站、Docker 容器网段，以及云厂商元数据接口。

**修复**：改用 sing-box 1.11+ 的 `resolve` action，**先解析成 IP 再判定**：

```json
"rules": [
    { "action": "resolve", "strategy": "ipv4_only" },
    { "action": "reject",  "ip_is_private": true },
    ...
]
```

> 同机 Xray 侧实测**不存在**此绕过（其 Reality 节点修复前就能拦住同一测试），这是 sing-box 侧特有的问题。

### 2.〔严重〕基础端口被同机其他脚本的跳跃段劫持

**现象**：`nodes.txt` 里发布的 `hysteria2://...@域名:44116` 完全连不上（客户端报
`connect error: timeout: no recent network activity`），但同一节点的跳跃段 `25000-38000` 能正常连；
**本机 hysteria 服务端日志里没有任何记录**。

**根因**：同机另一套脚本安装了一条按**范围**匹配的 nat 规则

```
-A PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 8443
```

本脚本随机分配的 Hysteria2 基础端口 `44116` 正好落在 `40000-50000` 内，
于是所有直连 44116 的包被改写投递给对方的 8443 实例；两边 obfs 密码不同，握手包被**静默丢弃**。

**验证**（用对方实例的凭据连本端口，能连通即证明劫持）：实测返回 `200`，且**对方**服务端日志出现
`client connected`，本端日志为空 —— 劫持确认。

**修复（三处）**：

1. `assign_port` 随机分配端口时，**跳过已被 nat 端口段规则劫持的区间**（最多重试 50 次）：

   ```bash
   port_hijacked_by_nat "$val" >/dev/null 2>&1 || break
   ```

2. `apply_hy_hop` 在装完跳跃规则后，为基础端口插入 `RETURN` 例外（幂等），
   保证直连基础端口的包不被任何端口段规则改写：

   ```bash
   iptables -t nat -I PREROUTING 1 -p udp --dport "$port_hy2" -j RETURN
   ```

3. 检出冲突时明确告警，指出是哪个段、导向哪个端口。

修复后实测：直连 `44116` 返回 `200`，本机 hysteria 日志正常出现 `client connected`。

> 原逻辑只排除了**自己的**跳跃段（`hyjpt`），无法感知同机其他脚本占用的范围——这是同机共存多套代理脚本时最难排查的一类故障。

### 3. 无全局 IPv6 的机器仍在尝试 IPv6 出站

本机只有链路本地 `fe80::`、无全局 IPv6，但配置用的是 `"strategy": "prefer_ipv4"` ——
sing-box 仍会发 AAAA 查询并尝试 v6 连接。实测日志：

```
ERROR ... dial tcp [2a03:2880:f382:5:face:b00c:0:79f4]:443: connect: network is unreachable
ERROR ... lookup zt.huya.com: (exchange6: NXDOMAIN | exchange4: NXDOMAIN)
```

每次失败都白白多耗一个 RTT。**修复**：新增 `detect_ip_strategy()`，安装时探测本机是否有全局 IPv6，
无则自动使用 `ipv4_only`（有则保持 `prefer_ipv4`），并同步应用到 `default_domain_resolver`。

### 4. 单网卡服务器上的 MPTCP 只有代价没有收益

服务端 `direct` 出站原本开着 `tcp_multi_path: true`。内核计数器实测：

| 计数器 | 值 | 含义 |
| :--- | ---: | :--- |
| `MPCapableSYNTX` | 11188 | 发起 MPTCP 协商的次数 |
| `MPCapableSYNACKRX` | 33 | 对端接受的次数 |
| `MPCapableFallbackSYNACK` | 11129 | **回退成普通 TCP（99.7%）** |
| `MPCapableSYNTXDrop` | 14 | 带 MPTCP 选项的 SYN 被中间设备直接丢弃 |

服务器只有一张网卡，MPTCP 本就不可能带来多路径收益；而 `SYNTXDrop` 说明部分路径上它反而**增加连接失败风险**。
**修复**：服务端 `direct` 出站移除 `tcp_multi_path`。

### 5. sing-box 1.14 已移除出站的 `domain_strategy`

1.14.0 起，outbound 的 `domain_strategy` 会直接导致启动失败：

```
FATAL legacy domain strategy options is deprecated in sing-box 1.12.0 and will be removed in sing-box 1.14.0
```

改由 `route` 侧统一指定（`resolve` action 的 `strategy` + `default_domain_resolver.strategy`）。本版已完成迁移。

### 6.〔实测〕salamander 混淆的吞吐代价约 2.4 倍

同一台机器、同一条 loopback 路径、同一 Hysteria2 服务端二进制，仅切换是否启用 salamander 混淆：

| 配置 | 吞吐 |
| :--- | ---: |
| 带 salamander 混淆（默认） | 571 Mbps |
| 关闭混淆 | **1378 Mbps** |
| 对照：TUIC（无混淆） | 1490 Mbps |

**混淆是逐包做的用户态加扰，这是它的固有成本，不是配置错误。** 关掉后 Hysteria2 的吞吐与 TUIC 持平，
说明此前"Hysteria2 比 TUIC 慢一半"的现象**完全由混淆造成**。

这是一个需要你自己权衡的取舍：混淆换的是 UDP 特征抵抗（对抗运营商 QoS 与协议识别）。
默认仍保持开启；确认所在网络不做 UDP 协议识别时，可用 `hyobfs=0` 关闭以换取约 2.4 倍吞吐。

### 7.〔实测后推翻〕Hysteria2 的带宽声明不是瓶颈

一度怀疑 `up_mbps/down_mbps` 与 Brutal 拥塞控制限制了吞吐。**扫描后证明无关**（loopback，服务端 `up/down` 均 1000mbps）：

| 客户端声明 | 吞吐 |
| :--- | ---: |
| `up100/down1000`（当前默认） | 601 Mbps |
| `up1000/down1000` | 569 Mbps |
| `up2000/down3000`（超服务端上限） | 570 Mbps |
| 省略声明（客户端 BBR） | 600 Mbps |
| 服务端 `ignoreClientBandwidth: true` + BBR | 605 Mbps |

**任何带宽/拥塞控制组合都稳定在 ~570-605 Mbps**，天花板另有其因（见上一条：混淆）。
`sbbox speed` 的带宽设置在弱网上仍有意义，但在高质量链路上不要指望靠调它提速。

### 8. 关于本机回环测速的口径（重要）

在服务端本机经公网 IP 回环测速时，**UDP 会额外经过云厂商的发夹（hairpin）路径，吞吐大约减半**，TCP 则不受同等影响：

| 路径 | 裸 UDP 吞吐 |
| :--- | ---: |
| 纯 loopback（127.0.0.1） | 1189 Mbps |
| 经公网 IP 发夹 | 603 Mbps |

同一实例对比：Hysteria2 loopback 593 / 发夹 312 Mbps；TUIC loopback 1490 / 发夹 748 Mbps。

**因此本机自测出的 QUIC 类节点数字系统性偏低，不能据此判断"UDP 节点比 TCP 节点慢"**——
要比较协议本身，必须固定在同一条路径上比。

### 9. 修复前后节点连通性对照

| 节点 | 修复前 | 修复后 |
| :--- | :--- | :--- |
| `hy2`（基础端口 44116） | **完全不通** ❌ | 通，310 Mbps ✅ |
| `tuic` | 通，695 Mbps | 通，731 Mbps |
| `naive-h3` | 通，450 Mbps | 通，440 Mbps |
| `naive-h2` | 通，1422 Mbps | 通，1421 Mbps |
| 私有地址防护（域名目标） | **被绕过** ❌ | 已阻断 ✅ |

> 吞吐数字均为经公网 IP 回环的测量值，受第 8 条所述发夹路径影响而偏低，仅用于横向对比。

---

## 十一、v2.2.0 实测诊断与修复记录

同一台 **Oracle ARM (4 核 24G) / Ubuntu 26.04 / kernel 7.0** 上的第二轮诊断，主题是**兼容性与连接速度**。
延续第十节的口径：每条都给实测数据，**包括两条"查了但根本不存在的问题"和一条"改了但并不提速"的项目**。

体检基线（改动前）：sing-box 1.14.0 连续运行 1 天 3 小时、`NRestarts=0`、CPU 0.1%、句柄 17/1048576，
`sing-box check` 与 `sbbox doctor` 全绿，网卡收发零丢包。**服务本身没有故障**，本节修的是三个会在未来某天才发作的问题。

### 1.〔严重·定时炸弹〕acme.sh 自动续期不会通知 sbbox，且会作废所有客户端的证书指纹

`acme.sh --cron` 每天跑，但它只执行自己 `reloadcmd` 里登记的命令。本机原值是：

```
nginx -t && systemctl restart nginx && { systemctl restart xray || true; }
```

只管 nginx 和 xray。而 sbbox 的证书是 `$CERT_DIR`（`/root/sbbox/cert/`）下的**独立副本**，
不是 `/etc/ssl/private/` 那份的软链。于是续期当天会连锁发生两件事：

| # | 后果 | 触发时刻 |
| :--- | :--- | :--- |
| 1 | sing-box 与 hysteria 仍加载旧证书，无人重启 | 续期日 |
| 2 | 旧证书到期，**tuic / naive / hy2 三协议同时全断** | 旧证书 `notAfter` |
| 3 | 就算手工补上证书，`nodes.txt` / `clmi.yaml` 里的 `pinSHA256` 与 `pcs=` 锁的是叶证书指纹，**换证即失配，所有开启固定证书校验的客户端一起连不上** | 补证书那一刻 |

第 3 条最隐蔽：它不是"忘了重启"，而是**修得越及时、客户端断得越早**。

脚本里原本就有 `sbbox cert renew` 走完了正确流程（`install_cert → sbrestart → gen_client`，
`gen_client` 会用 `_cert_sha256()` 重新计算指纹），但它只能手工触发，而真正会自动跑的是 acme 那条路。

**修复**：新增 `sbbox cert sync` 与 `sbbox cert hook` 两个子命令。

- `cert sync` 只做续期之后的半段——落地新证书、重启 sing-box 与外置 hysteria、按新指纹重生成三份客户端配置。
  **它不触发签发**，所以可以安全地挂在 `reloadcmd` 上（`cert renew` 会 `--force` 再签一次，挂上去等于每次续期签两遍，不能用）。
  比对叶证书指纹，未变化时直接跳过重启：

  ```
  $ sbbox cert sync
  [+] 证书未变化（指纹 24c2529f44c805ae…），无需重启
  ```

- `cert hook` 把 `cert sync` **追加**进 `reloadcmd`，保留其中原有命令，幂等：

  ```
  $ sbbox cert hook
  [+] 续期钩子已安装
    reloadcmd: nginx -t && systemctl restart nginx && { systemctl restart xray || true; }; /usr/local/bin/sbbox cert sync
  $ sbbox cert hook
  [+] 续期钩子已存在，无需重复安装
  ```

**验证命令**：

```bash
sbbox cert hook                      # 幂等，第二次应报"已存在"
sbbox cert sync                      # 证书未变时应报"无需重启"且不重启任何服务
# 确认钩子真的落进了 acme 的域名配置（值是 base64 包装的）
ym=$(cat /root/sbbox/ym)
grep Le_ReloadCmd ~/.acme.sh/${ym}_ecc/${ym}.conf \
  | sed -e 's/.*START_//' -e 's/__ACME_BASE64__END_.*//' | base64 -d; echo
```

> 顺带：`cert sync` 复用 `install_cert`，会把证书链从 acme 给的 4 张裁到 3 张
> （4841 → 3243 字节，每次 TLS 握手少传 1598 字节）。裁掉的是客户端本地已有的根证书。

### 2.〔改了，但在好链路上并不提速〕Hysteria2 的 Brutal 参数改回 BBR

订阅链接里原本写死 `upmbps=100&downmbps=1000`，服务端 `ignoreClientBandwidth: false`。

**先说清楚它不是提速改动。** 第十节第 7 条已经实测过：Brutal 与 BBR 在本机各种组合下
稳定在 ~570–605 Mbps，**任何带宽/拥塞控制组合都测不出差别**，天花板在 salamander 混淆（第十节第 6 条）。
本次也没有复测出新的差异，不要指望改完变快。

改它的真正理由是**一份订阅要发给链路各异的客户端**：Brutal 不看丢包反馈，按链接里写死的数字硬发。
`upmbps=100` 对一条真实上行 20 Mbps 的客户端，多出来的 80 Mbps 全是重传；
`downmbps=1000` 则让服务端不管对端什么链路都按 1 Gbps 下发。
**填错方向只有一个：比真实带宽大**——而一份全局订阅必然对一部分人填错。
这个代价在服务端本机是测不出来的（零丢包、本地回环），只会出现在客户端的真实链路上。

BBR 没有这个失配面：它自己探测。代价是在**高丢包跨境链路**上，Brutal 填对了确实比 BBR 猛
（这正是 Brutal 存在的意义），所以改动只换默认值，不删能力。

**修复**：

- 服务端 `/etc/hysteria/sbbox.yaml` 改 `ignoreClientBandwidth: true`（`bandwidth:` 段保留但不再参与拥塞控制，便于回滚）；
- `sbbox speed` 新增 `bbr` / `off` / `none` / `auto` / `0` 参数，清空 `hybw` 并重生成不带 `upmbps/downmbps` 的链接。

```bash
sbbox speed bbr        # 切回 BBR（本次采用）
sbbox speed 100 1000   # 明确知道自己链路带宽时，切回 Brutal
sbbox speed            # 查看当前档位
```

**验证命令**：

```bash
grep ignoreClientBandwidth /etc/hysteria/sbbox.yaml   # 应为 true
grep -c 'upmbps\|downmbps' /root/sbbox/nodes.txt      # 应为 0
grep -n 'up:\|down:' /root/sbbox/clmi.yaml            # 应无输出
journalctl -u hysteria-sbbox --since '10 min ago' | grep 'client connected'
```

改完后 hy2 在公网侧握手正常（日志可见真实客户端 `client connected`）。

> **注意 loopback 测不了 hy2。** 本机经 `127.0.0.1:44116` 起客户端会 15 s 超时，
> 而服务端日志里**连一条记录都没有**（包根本没到）——这是回环路径的问题，不是服务故障。
> 判断 hy2 死活请看 `journalctl -u hysteria-sbbox | grep 'client connected'`，
> 不要用本机自测的结果下结论。参见第十节第 8 条关于回环口径的说明。

### 3.〔兼容性〕Clash/Mihomo 配置里两个 naive 节点是同一个节点

`clmi.yaml` 原本并排生成 `naive-h3-*` 与 `naive-h2-*` 两条，**逐字节完全相同**：同端口、同 `type: http`。

```yaml
  - name: naive-h3-instance-xxx     # 和下面这条一模一样
    port: 10489
    type: http
    udp: true
  - name: naive-h2-instance-xxx
    port: 10489
    type: http
    udp: true
```

两个问题：

1. **Mihomo 的 `http` 类型是 TCP 上的 HTTPS 代理，不走 QUIC。** "h3" 只是个名字，
   `url-test` 组里等于放了两个同一节点，测速组因此失去意义。
2. **`http` 类型不支持 UDP 中继，`udp: true` 在 Mihomo 里是空写。** 真按它分流，UDP 流量会静默失败。
   要在 Mihomo 上走 QUIC，得用 tuic 或 hy2 节点。

**修复**：Clash 侧只生成一条 `naive-*`（TCP/H2），并去掉误导性的 `udp: true`。

这**不影响 `nodes.txt`**：v2rayN / NekoBox / Shadowrocket 走的是 `naive+quic://`、`http3://` 等链接，
那些客户端确实认 QUIC，六条链接原样保留。

**验证命令**：

```bash
grep -c 'name: naive' /root/sbbox/clmi.yaml    # 应为 1（原为 2）
grep -n 'udp: true' /root/sbbox/clmi.yaml      # 应无输出
```

### 4.〔顺带修复〕`mport` 重复：跳跃端口链接被拼成 `44116,44116,25000-38000,25000-38000`

`gen_client` 原先靠解析 `iptables -t nat -nL` 的输出来还原跳跃段：

```bash
hy2_ports=$(iptables -t nat -nL --line | grep -w "$port_hy2" | awk '{print $8}' | ...)
```

自 v2.1.0 修掉「基础端口被跳跃段劫持」（第十节第 2 条）后，nat 表里匹配基础端口的规则**变成了三条**——
基础端口的 `RETURN`、跳跃段的 `DNAT`、本机回环的 `REDIRECT`——逐行拼接就拼出了重复值：

```
mport=44116,44116,25000-38000,25000-38000     # 错
mport=44116,25000-38000                       # 对
```

这个 bug 自 v2.1.0 起就存在，只是 `nodes.txt` 一直没重新生成，直到本次改动触发 `gen_client` 才显形。

**修复**：跳跃段直接取自 `hyjpt`（当初用来下发 iptables 规则的那份状态，`gen_client_clash` 一直是这么做的），
不再回头解析 iptables 输出。

**验证命令**：

```bash
grep -o 'mport=[^&]*' /root/sbbox/nodes.txt   # 应为 mport=44116,25000-38000
grep -n 'ports:' /root/sbbox/clmi.yaml        # 应为 ports: 44116,25000-38000
```

### 5.〔已知交互〕外置 Hysteria2 与 `installsb` 的端口冲突（本次加了保护）

本机 hy2 是**外置形态**：官方 `hysteria` 二进制 + `hysteria-sbbox.service` + `/etc/hysteria/sbbox.yaml`，
`sb.json` 里**没有** hy2 入站（这样才能用 salamander 混淆与端口跳跃）。
但 `proto_hyp` 状态文件仍在，`load_state` 因此设 `hyp=yes`。

于是任何会调用 `installsb` 重写 `sb.json` 的路径（原先的 `sbbox speed`），
都会给 sing-box 补出一个 `hy2-in` 入站、监听同一个 44116，
**与已占用该端口的 hysteria 进程抢绑定，导致 sing-box 起不来**。

**修复**：新增 `hy2_external()` 判定（`sb.json` 无 `hy2-in` 且 `hysteria-sbbox` 在运行），
命中时 `cmd_speed` 跳过 `installsb`，只重启外置 hysteria 并重生成客户端配置：

```
[!] 检测到外置 Hysteria2（hysteria-sbbox.service），已跳过 sb.json 重写
[!] 服务端侧请同时确认 /etc/hysteria/sbbox.yaml 内 ignoreClientBandwidth: true
```

`cert renew` / `cert sync` 也一并调用 `hy2_external_restart()`，否则换证后外置 hysteria 不会加载新证书。

> **周更 cron 是安全的**：`sbbox up`（`cmd_update`）只升级内核二进制 + 重启，不重写 `sb.json`，不受此影响。

### 6.〔查了但不存在〕UDP 接收缓冲丢包

一度怀疑 QUIC 类节点受 UDP 收包丢弃拖累。**读错字段导致的假警报**：

`/proc/net/snmp` 的 `Udp:` 行字段序是 `InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors …`，
用 `awk '{print $5}'` 取到的是 **OutDatagrams（出站报文数）**，不是 `RcvbufErrors`。
按它算出的"50 次/秒丢包"其实是正常的出站流量计数。

正确口径下的三项独立验证：

| 方法 | 结果 |
| :--- | :--- |
| `nstat` 30 秒增量 | `UdpRcvbufErrors` 增量 **0** |
| `bpftrace` 挂 `udp_fail_queue_rcv_skb` 探针 15 分钟 | **零命中** |
| `ss -uanpm` 全部 UDP socket | 队列 `r0`、丢弃 `d0`，sing-box 两个入站 socket 的 `rb` 均为 16 MB |

累计的 `UdpRcvbufErrors=218465` 摊到 3 天 20 小时是 0.66 次/秒，且当前不再增长。**无需处理。**

```bash
# 正确读法：不要用 awk 数字段
nstat -az | grep UdpRcvbufErrors
```

### 7.〔查了但改不了〕virtio 网卡不支持 UDP GSO

`ethtool -k` 显示 `tx-udp-segmentation: off [fixed]`——`[fixed]` 表示硬件/驱动不支持，无法开启。
QUIC 因此只能逐包 `sendmsg`，高吞吐时 CPU 开销偏高。网卡 ring buffer 也已是硬件上限（RX/TX 各 256）。

这是虚拟化平台的固有限制，**记录备查，无可调项**。实测未构成瓶颈（见下表）。

### 8. 改动前后端到端对照

本机 SOCKS 客户端 → sbbox 入站 → 公网，**纯 `127.0.0.1` 路径**（不经公网 IP 发夹，
避开第十节第 8 条所述的吞吐减半），下载源 `speed.cloudflare.com/__down?bytes=50000000`：

| 节点 | 改动前 | 改动后 |
| :--- | ---: | ---: |
| *直连基线* | *~270 MB/s* | — |
| **Naiveproxy H2** | 185 MB/s | 179 MB/s |
| **Tuic** | 160 MB/s | 145 MB/s |
| **Hysteria2** | 见下 | 见下 |

- 三项改动**都不是吞吐改动**，差异在采样噪声范围内（同一节点单轮极差可达 ±25%）。
- **hy2 不在表内**：本机回环打不通它（见第 2 条注意事项），公网侧以服务端日志确认正常。
- 两条 QUIC/TCP 节点都在 1.1 Gbps 以上，**服务端协议栈不是瓶颈**，
  真实体感取决于客户端到 VPS 的跨境链路。

出口链路质量（供对照）：`1.1.1.1` RTT 0.9 ms、`www.google.com` 0.35 ms、`github.com` 15.3 ms。

### 9. 改动后连通性与幂等性核对

| 检查项 | 结果 |
| :--- | :--- |
| `sing-box check -c sb.json` | 通过 |
| `sbbox doctor` | tuic / hy2 / naive / 订阅 四项全绿 |
| tuic、naive 端到端（本机 SOCKS） | HTTP 200，UDP/DNS 通 |
| hy2 公网客户端 | 日志 `client connected` ×2 |
| `sb.json` 是否被误改写 | **未改动**（外置 hy2 保护生效） |
| `sbbox cert hook` 重复执行 | 报"已存在"，不重复追加 |
| `sbbox cert sync` 证书未变时 | 报"无需重启"，不重启服务 |
| 服务端下发证书链 | 3 张（叶 → YE2 → Root YE） |

一句话回归验证：

```bash
sbbox doctor && \
grep -c 'upmbps' /root/sbbox/nodes.txt && \
grep -c 'name: naive' /root/sbbox/clmi.yaml && \
grep -o 'mport=[^&]*' /root/sbbox/nodes.txt
# 期望：全绿 / 0 / 1 / mport=44116,25000-38000
```

---

## 十二、v2.3.2 实测诊断与修复记录

第三轮诊断的口径与前两节一致：先跑全量连通性与自检，再针对**跑得好好的、但存在风险**的地方下手。

体检基线（改动前）：`xh diag` 14 项全绿、`sbbox doctor` 全绿、`sing-box check` 与 `xray -test` 均 OK，
11 条节点（Xray 7 条 + sbbox 4 条）SOCKS 实测 **11/11 全通**：

```
Xray  n0-h2-cdn              PASS  421.9ms   TCP/H2 + Cloudflare CDN
Xray  n1-h3-cdn              PASS  151.8ms   QUIC/H3 + Cloudflare CDN
Xray  n2-h3-direct           PASS  105.1ms   QUIC/H3 + VLESS Direct
Xray  n3-hy2-obfs            PASS   29.7ms   Hysteria 2 + Salamander
Xray  n4-reality-vision      PASS    7.6ms   VLESS + Reality + Vision
Xray  n5-reality-xhttp       PASS    9.6ms   VLESS + Reality + XHTTP
Xray  n6-reality-up-cdn-down PASS   44.7ms   Reality Up + CDN Down
sbbox tuic                   PASS    2.2ms   TUIC v5 + BBR
sbbox hysteria2              PASS    4.6ms   Hysteria 2 + Hop + Brutal
sbbox naive-h3               PASS    3.2ms   NaiveProxy + QUIC/H3 + BBR
sbbox naive-h2               PASS    5.4ms   NaiveProxy + TCP/H2 TLS
```

**服务本身没有任何故障**，本节修的是订阅服务里的一个可被公网利用的漏洞。

### 1.〔严重·安全漏洞〕订阅服务存在未授权路径穿越，可从公网读取本机任意文件

`sub_server.py` 用请求路径直接拼文件名：

```python
token_path = self.path.lstrip("/").split("?")[0]
token_file = os.path.join(WEB_DIR, token_path)      # WEB_DIR=/root/sbbox/websub
```

`lstrip("/")` 只去掉开头的斜杠，`..` 原样保留，`os.path.join` 又会老老实实往上走。
订阅端口监听的是 `0.0.0.0` 且防火墙已放行，于是**任何人只要知道端口号**（不需要 token）
就能读走这台机器上 root 可读的任意文件。

**实测复现（修复前，本机 50934 端口）：**

```bash
P=$(cat /root/sbbox/subport)
printf 'GET /../../../etc/passwd HTTP/1.0\r\n\r\n' | nc 127.0.0.1 $P | head -3
# 修复前：HTTP/1.0 200 OK ... root:x:0:0:root:/root:/bin/bash
printf 'GET /../uuid HTTP/1.0\r\n\r\n'              | nc 127.0.0.1 $P | tail -1
# 修复前：b1bacb9c-...（节点 UUID 直接泄露）
```

公网侧同样成立（`curl -o /dev/null -w '%{http_code}' http://<VPS_IP>:<subport>/<token>` 返回 `200`，
说明该端口对外可达，不是只在环回上开着）。

危害不止 `/etc/passwd`：`/root/sbbox/uuid`、`hyobfs_pw`、`sec`、`cert/private.key`、
`/root/.ssh/*` 全部在射程内 —— 拿到这些等于拿到全部节点凭据。

**还有第二层放大**：token 校验其实是靠"文件存在"来做的，而穿越路径同样能让
`os.path.isfile()` 为真。所以带 `User-Agent: clash` 请求 `/../uuid`，
服务端会直接吐出**完整的 `clmi.yaml`（含所有协议的密码）**，全程不需要正确 token。

**根因**：把未经校验的 URL 路径当作文件名使用，且用"文件是否存在"代替鉴权。

**修复方式**（`sub_server.py` 与 `sbbox.sh` 内嵌的那份**同时**改）：

1. 先 `unquote()` 再取路径，堵住 `%2e%2e` / `..%2f` 这类编码绕过；
2. 白名单校验 `^[A-Za-z0-9._-]{1,128}$`，任何含 `/` 或以 `.` 开头的路径直接 404；
3. `os.path.realpath()` 解析后再确认结果确实落在 `WEB_DIR` 之内（防软链逃逸）。

**另一处配套修复**：`start_sub_server()` 原来是

```bash
if [ ! -f "$SB_HOME/sub_server.py" ]; then      # ← 老安装永远不会被刷新
```

这意味着**已经装过的机器升级脚本后，磁盘上仍是那份带漏洞的旧文件**，补丁等于没打。
现改为无条件重写（该文件是脚本生成物，不存在用户手改的语义）。

**修复后实测：**

```
/../../../etc/passwd      -> HTTP/1.0 404 Not Found
/../uuid                  -> HTTP/1.0 404 Not Found
/%2e%2e/uuid              -> HTTP/1.0 404 Not Found
/..%2fuuid                -> HTTP/1.0 404 Not Found
/subdir/../../uuid        -> HTTP/1.0 404 Not Found
/../uuid  (UA: clash)     -> HTTP/1.0 404 Not Found
正常订阅：plain=200 clash=200 singbox=200 v2rayn=200 根路径=200
```

一句话回归验证：

```bash
P=$(cat /root/sbbox/subport); T=$(cat /root/sbbox/subtoken)
printf 'GET /../../../etc/passwd HTTP/1.0\r\n\r\n' | nc 127.0.0.1 $P | head -1
curl -s -o /dev/null -w '%{http_code}\n' -A clash "http://127.0.0.1:$P/$T"
# 期望：404 / 200
```

> **已装机器请务必 `sbbox sub off && sbbox sub on`（或重启 `sbbox-sub`）**，
> 让新版 `sub_server.py` 真正落盘生效；并考虑轮换 `uuid` 与各协议密码。

### 2.〔默认值调整〕端口跳跃明确为「默认关闭」

`hyjpt` 本来就默认为空（不开跳跃），但 `sbbox hop` 无参数时会提示"**推荐执行** `sbbox hop 25000:38000`"，
帮助里也没写默认状态，实际效果是在鼓励用户打开它。**同机跑着第二套代理脚本时，
一个上万端口的 DNAT 段是最容易吃掉对方随机端口的东西**（见第十节的事故），
不该由脚本主动推荐。本版把措辞与注释统一为"默认关闭，需要时再手动开"：

| 位置 | 改动 |
| :--- | :--- |
| `hyjpt` 变量注释 | 注明"默认关闭（空）" |
| 帮助行 `端口跳跃：` | `【关闭】` → `【默认关闭】` |
| `hyjpt=` 环境变量说明 | 加"默认关闭；同机有其他代理脚本时慎开" |
| `sbbox hop`（无参数） | "推荐执行" → "当前未开启端口跳跃（默认关闭）。需要时执行：" |

行为本身未变：`sbbox hop 25000:38000` 照常开启，`sbbox hop off` 照常关闭。
本机同时执行了 `sbbox hop off`，并清掉了 Xray 项目遗留的 `40000:50000` REDIRECT 残留规则
（该项目的 `FEATURE_PORT_HOPPING` 已是 `false`，订阅文件里 `mport` 出现 0 次，属于早期开启后没撤干净的规则）：

```bash
iptables -t nat -S PREROUTING     # 期望：只剩 DOCKER 一条，无任何端口段 DNAT/REDIRECT
iptables -S INPUT | grep ':'      # 期望：无输出（无端口段放行）
```

### 3.〔查了但不是问题〕两套项目的 UDP 端口跳跃段没有互相劫持

按第十一节留下的怀疑方向复查了同机共存的 Xray 项目与 sbbox 的 nat 规则：

```
-A PREROUTING -p udp --dport 44116 -j RETURN                      # sbbox 自保
-A PREROUTING -p udp --dport 25000:38000 -j DNAT --to :44116      # sbbox 跳跃段
-A PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to 8443    # Xray 跳跃段
```

Xray 的 `40000:50000` 确实覆盖了 sbbox 的 hy2 端口 `44116`，但排在它前面的 `RETURN` 已经把
`44116` 摘出去了，规则顺序正确。sbbox 的 `25000:38000` 未覆盖 Xray 的 `443 / 8003 / 8443 / 8446`。
`xh diag` 的"UDP 端口段劫持检测"同样报无劫持。**本轮未发现劫持，不需要改动。**

### 4.〔查了但不予处理〕`sb.log` 里的 ERROR 多数不是故障

```
dns: lookup failed for status-ipv6.jpush.cn: empty result      # 客户端查 IPv6 无记录
router: lookup ...invalid: NXDOMAIN                            # 就是不存在的域名
connection: connection upload closed: H3 error (0x0)           # H3 正常关流
```

三类都是**客户端行为的正常回声**，不是服务端异常。判据：`NRestarts=0`、
`journalctl -p warning` 三天零条、11/11 节点全通。把它们当 bug 去"修"只会引入噪音。

---

## 十三、v2.3.3 密钥轮换与外置 Hysteria2 修复记录

第十二节的路径穿越漏洞意味着 **uuid 与各协议密码曾长期可被公网读取**，必须轮换。
执行 `sbbox rotate` 时暴露出三个连环 bug，本节记录。

### 1.〔严重〕`sbbox rotate` 不换 UUID，等于只换了一半凭据

原实现的注释写得很明白：「UUID、端口、证书保持不变」。但 **UUID 是 Tuic 的用户标识，
和密码一样是凭据**，随订阅或节点链接一起泄露。只轮换密码而留着 UUID，
攻击者手里那半份凭据仍然有效。

**修复**：`cmd_rotate` 在 `load_state` 之后重新生成 UUID（必须在其后，
否则会被 `load_state` 读回的旧值覆盖），`insuuid` 见到非空 `$uuid` 即落盘新值。

### 2.〔严重〕轮换会让 sing-box 崩溃启动失败，Tuic 与 Naive 一并陪葬

本机 Hysteria2 是**外置形态**：官方 `hysteria` 二进制 + `hysteria-sbbox.service` +
`/etc/hysteria/sbbox.yaml`，`sb.json` 里**没有** `hy2-in` 入站。
`cmd_rotate` 直接调用 `installsb` 重写 `sb.json`，就补出了一个同端口的 `hy2-in`：

```
FATAL start service: start inbound/hysteria2[hy2-in]:
      listen udp 0.0.0.0:44116: bind: address already in use
```

sing-box 进入 crash-loop（`restart counter` 一路上涨），**Tuic 与 Naiveproxy 两个
完全无关的协议同时下线**——它们和 hy2 在同一个进程里。

脚本里其实早有 `hy2_external()` 这个判定函数，注释也写了「凡是要重写配置的路径都先问一句」，
`sbbox speed` / `sbbox brutal` 三处都问了，**唯独 `cmd_rotate` 没问**。

**修复**：判定挪进 `installsb` 开头，对所有重写路径统一生效。
注意 `hy2_external()` 是靠读现有 `sb.json` 判断的，而 `installsb` 马上要重写它——
**判完再问就永远是"内置"**，所以必须在截断前捕获成 `HY2_EXTERNAL_MODE`。

### 3.〔严重·第一次修复引入的新 bug〕跳过整个 hy2 分支会丢掉 obfs 密码

第一版修复把守卫加在了外层 `if [ -n "$hyp" ]` 上，结果连 obfs 密码的生成一起跳过了：
`hyobfs_pw` 文件消失，节点链接不再带 `obfs-password`，而服务端 `sbbox.yaml`
里 salamander 混淆仍然开着 —— **客户端全部连不上，且服务端不报错**。

**修复**：守卫只包住 `cat >> "$SB_CONF"` 那一段入站落盘，
前面的 obfs / 带宽 / 伪装状态照常生成（节点链接与 `sbbox.yaml` 都要用）。

### 4.〔严重〕外置 Hysteria2 的密码不在 `sb.json` 里，轮换后静默失配

真正在 44116 上做认证的是 `/etc/hysteria/sbbox.yaml`，`rotate` 只改 `sb.json` 与订阅。
实测轮换后：

```
nodes.txt   hysteria2://9fc153fdea9bb0fb840492275cbc3fef@...   ← 新密码
sbbox.yaml  password: "a3814e463ded84b5dc2e7db114708a89"       ← 旧密码
```

`sbbox doctor` 全绿（端口在听、进程在跑），但所有客户端认证失败。
这类"服务端无日志的静默失配"正是最难排查的一类。

**修复**：新增 `hy2_external_sync_secrets()`，把 `sec/hy2_pw` 与 `hyobfs_pw`
写回 `sbbox.yaml` 并重启 `hysteria-sbbox`。两处都是 `password:` 行，靠缩进区分
（`auth` 段两空格、`salamander` 段四空格），改前自动备份 `sbbox.yaml.bak`。

### 轮换后的验证

```bash
# 1. 三份凭据必须完全一致
cat /root/sbbox/sec/hy2_pw
grep -A2 '^auth:' /etc/hysteria/sbbox.yaml | tail -1
grep -o 'hysteria2://[^@]*' /root/sbbox/nodes.txt

# 2. obfs 同理（缺任一侧都会静默连不上）
cat /root/sbbox/hyobfs_pw
grep -A3 '^obfs:' /etc/hysteria/sbbox.yaml | tail -1
grep -o 'obfs-password=[^&#]*' /root/sbbox/nodes.txt

# 3. 外置形态下 sb.json 不该有 hy2-in
grep -c hy2-in /root/sbbox/sb.json          # 期望 0
systemctl is-active sbbox hysteria-sbbox    # 期望 active active
```

实测结果：三处密码逐字一致、`hy2-in` 计数 0、两服务 active，
11/11 节点（Xray 7 + sbbox 4）用新凭据全部通过。

---

## 十四、v2.5.0 握手提速与「全部采用最新特性」

与同机的 Xray 项目同一轮改动。sbbox 这边的证书链裁剪（`trim_cert_chain`）在 v2.4.x 就已经有了，
所以本版只剩一处配置改动，但把「为什么不能靠删行来要最新特性」这条坑记下来。

### 1.〔最新特性〕`min_version` 由 1.2 提到 1.3

`sb.json` 里两处 `tls.min_version`（`vless-reality-in` 与 `naive-in`）改为 `"1.3"`。

**注意：不能靠「删掉 `min_version` 这行」来要最新特性**——删掉后 sing-box 会退回它自己的
默认下限（更低），方向正好相反。要最新就得**显式写死 `"1.3"`**。

**验证命令**：

```bash
grep -n min_version /root/sbbox/sb.json          # 期望两处都是 "1.3"
/root/sbbox/sing-box check -c /root/sbbox/sb.json
systemctl restart sbbox && systemctl is-active sbbox
```

**实测**：改后 `sing-box check` 通过，13 节点全量回归（含本项目 5 条：tuic / hysteria2 /
naive-h3 / naive-h2 / vless-reality）**全部 PASS**：

```
sbbox    tuic          PASS    2.6ms    TUIC v5 + BBR
sbbox    hysteria2     PASS   19.2ms    Hysteria 2 + Hop + Brutal
sbbox    naive-h3      PASS    3.4ms    NaiveProxy + QUIC/H3 + BBR
sbbox    naive-h2      PASS    4.1ms    NaiveProxy + TCP/H2 TLS
sbbox    vless-reality PASS    8.8ms    VLESS + Reality + Vision
```

### 2.〔核对无需改动〕证书链已是最短可验证链

`trim_cert_chain` 已经把 `/root/sbbox/cert/fullchain.cer` 裁到 **3 张 / 3243 字节**。
本轮拿同一域名的原始 4 张链复核，结论一致——**3 张就是下限**，
只留 `leaf + YE2` 时系统信任库验不过（`Root YE` 尚未进主流信任库）：

```bash
$ openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt -untrusted YE2.pem leaf.pem
error 20 at 1 depth lookup: unable to get local issuer certificate
```

同机 Xray 项目本轮才补上同一套裁剪（4 → 3 张，每次握手少传 1598 字节），
裁剪结果与 sbbox 这边**逐字节相同**——这也反过来给该链长做了一次交叉验证：
sbbox 用这条 3 张链稳定服务已久。

### 3.〔核对无需改动〕DNS 已按延迟排好

`dns-secure`（DoT 1.1.1.1）本来就在第一位。本机实测冷域名解析
1.1.1.1 约 4ms、8.8.8.8 与 9.9.9.9 均约 14ms，顺序无需调整。
（同机 Xray 项目那边第一位曾是 8.8.8.8，本轮已改。）

### 4.〔实测后不采纳〕把 Reality 握手目标从 `gateway.icloud.com` 改到本机

本项目 `reality.handshake.server` 是远端 `gateway.icloud.com:443`。
原以为远端目标会给每次握手加一整个 RTT，实测不成立：

```
$ curl -s -o /dev/null -w "connect=%{time_connect} appconnect=%{time_appconnect}\n" https://gateway.icloud.com/
connect=0.001609 appconnect=0.013412
connect=0.001563 appconnect=0.012547
```

TCP 建连只要 **1.6ms**（Apple 边缘就在同区），换成本机省不出可测差值，
反而要动客户端 SNI 与订阅。**未改动。**

---

## 十五、v2.5.1 ECN 与 BBR 版本查明

与同机 Xray 项目同一轮改动。本项目只有一处配置改动，但把「查明的事实」写下来，
省得下次再查一遍。

### 1.〔已开启，但当前内核上无提速〕`tcp_ecn` 2 → 1

`try_sysctl net.ipv4.tcp_ecn` 由 `2`（只被动应答）改为 `1`（主动发起协商）。

**为什么两个项目必须一起改**：两者都往 `/etc/sysctl.d/` 写自己的文件
（`99-sbbox.conf` 与 `99-xray-xhttp.conf`），文件名排序后写者胜。
只改一边的话，实际生效值取决于文件名而不是任一项目的预期——这正是本机
既有的踩坑模式。

**验证命令**（关键是**按对端 IP 过滤**，否则会把自己作为服务端回的 SYN-ACK
误判成「对端接受」）：

```bash
IP=$(getent ahostsv4 speed.cloudflare.com | awk 'NR==1{print $1}')
tcpdump -i <网卡> -n "host $IP and tcp port 443 and tcp[tcpflags] & tcp-syn != 0" -w /tmp/e.pcap &
curl -s -o /dev/null --resolve "speed.cloudflare.com:443:$IP" https://speed.cloudflare.com/
tcpdump -r /tmp/e.pcap -n | grep 'Flags \[S'
# 我方 SYN 应为 [SEW]；对端 SYN-ACK 带 E（[S.E]）= 接受
grep -H 'tcp_ecn =' /etc/sysctl.d/99-sbbox.conf /etc/sysctl.d/99-xray-xhttp.conf
```

**实测 7 个对端**：Cloudflare / GitHub / Bing / Microsoft / 1.1.1.1 / 9.9.9.9 接受，
Google 拒绝，**无一例连接失败**。

**但它在当前内核上不提速**：本机 `bbr` 是 **BBRv1**，控制环路不消费 ECN 标记。
A/B 实测（12 轮交错）首字节 44.8ms vs 47.5ms、吞吐 1212 vs 1373 Mbps，
差异完全落在 CF 边缘波动里，**无可测差异**。设成 1 只是为将来换 ECN 敏感的
拥塞控制预留协商能力。

**另外**：本项目 4 条节点里有 3 条是 QUIC（TUIC / Hysteria2 / naive-h3），
它们的拥塞控制在**用户态**，内核 TCP 的 CC 与 ECN 设置对它们**完全无效**。
这一项实际只影响 naive-h2 与出站的 TCP 直连。

### 2.〔查明·当前做不到〕内核里的 `bbr` 是 BBRv1，不是 BBRv3

判据与结论同 Xray 项目 README 第九节第 3 条：`bbr_lt_bw_sampling`（v1 专属）、
`ss` 打印 v1 的 info 字段、`/sys/module/tcp_bbr/parameters/` 为空。
本机是 **arm64**，archive 里所有内核都带这份 BBRv1，而常见的预编译 BBRv3 内核
（XanMod 一类）**只出 x86_64**。DKMS 外挂 `tcp_bbr3` 模块是风险最低的一条路
（`tcp_brutal` 就是这么装的），本版**未执行**。

---

## 十六、v2.5.2 tcp-brutal 在内核 7.1+ 上的静默失效修复

与同机 Xray 项目同一轮。**本条与是否升级 BBRv3 无关——任何人把机器升到 7.1
以上都会踩到，而且是静默的。**

### 1.〔严重·静默降级〕tcp-brutal 编译失败 → 自动降级到 BBR

**现象**：`dkms` 编译 tcp-brutal 报

```
error: 'struct tcp_congestion_ops' has no member named 'min_tso_segs'; did you mean 'tso_segs'?
```

本项目在这种情况下会走 `try_fallback_bbr` **自动降级到 BBR+FQ**——这是设计内的
容灾，但你不看日志就不会知道 Brutal 根本没启用，只会觉得"限速功能好像没生效"。

**根因**：内核 7.1 起改了拥塞控制回调签名，上游 tcp-brutal 至今未适配：

```c
旧 (≤7.0): u32 (*min_tso_segs)(struct sock *sk);
新 (7.1+): u32 (*tso_segs)(struct sock *sk, unsigned int mss_now);
```

**验证命令**：

```bash
sysctl -n net.ipv4.tcp_available_congestion_control   # 期望含 brutal
dkms status | grep tcp-brutal                          # 每个内核各一份 installed
tail -20 /var/lib/dkms/tcp-brutal/*/build/make.log     # 失败时看这里
sbbox status                                           # 看是否已降级到 BBR
```

**修复方式**（v2.5.2 起自动执行）：安装流程改为先 `dkms ldtarball` 把源码摊到
`/usr/src`，打完补丁再 `dkms install`——原来的 `dkms install <tarball>` 是
「解包+编译」一步走，中间插不进补丁。补丁的判别式**直接 grep 目标内核的
`include/net/tcp.h`**，不用 `LINUX_VERSION_CODE` 猜版本边界。

写探测踩的三个坑（注释里都有）：Makefile 会被 kbuild 二次读取（那时只有
`srctree` 没有 `KERNEL_DIR`，只看后者会静默不定义宏）；`$(shell ...)` 里不能用
反斜杠续行；**make 匹配 `$(shell ...)` 右括号时不认引号**，grep 模式里不能出现
`)`，因此改用无括号的 `tso_segs.*mss_now`。

**实测**：补丁后的源码对 `7.2.3-joeyblog-bbrv3` 与 `7.0.0-1010-oracle` **都能编出
`brutal.ko`**，两个内核下 `brutal` 均在可用 CC 列表里；补丁函数幂等。

### 2.〔适配〕`sbbox` 状态输出新增 BBR 版本识别

BBR 有 v1 / v3 两代，`sysctl net.ipv4.tcp_congestion_control` **两代都叫 `bbr`**，
只看名字分不出来 —— 这正是 v2.5.1 里误判的起点。状态输出现在多一行：

```
  net.ipv4.tcp_congestion_control  bbr
    └─ BBR 版本                     v3
```

判据：`/proc/kallsyms` 有 `bbr_start_bw_probe_down` 等 v3 符号 → v3；
有 v1 专属的 `bbr_lt_bw_sampling` → v1。拿不到 kallsyms 才兜底看
`ss -tin` 的 **`pacing_gain`**（v1 STARTUP=2.88672，v3=2.77344），
并加 `?` 后缀表示不确定；命中不了就报 `unknown`，不猜。

> **v2.5.3 更正**：v2.5.2 曾把 `cwnd_gain`（v1=2.88672、v3=2）写成版本指纹，
> **这是错的**。**BBRv1 进入 PROBE_BW 后 `cwnd_gain` 同样是 2** —— 它区分的是
> 连接状态而不是 BBR 版本，拿它判长连接会给出错误答案。判版本以 kallsyms 符号为准。

### 3.〔核对〕BBRv3 上线后本项目 5 条节点全通

同机内核已换成 `7.2.3-joeyblog-bbrv3`。13 节点全量回归 13/13 PASS，
其中本项目 5 条：tuic 2.4ms / hysteria2 2.5ms / naive-h3 3.1ms /
naive-h2 5.8ms / vless-reality 7.9ms（中位）。

**提醒**：本项目 4 条节点里 3 条是 QUIC（TUIC / Hysteria2 / naive-h3），
拥塞控制在**用户态**，换内核 CC 对它们无效。BBRv3 实际只影响 naive-h2
与出站 TCP 直连。

### 4.〔更正 v2.5.1〕ECN 无收益的真正原因

v2.5.1 把 ECN 无收益归因为「BBRv1 不消费 ECN 标记」。**那句没错，但不是全部原因。**
换上会消费 ECN 的 BBRv3 后仍然没有差异，真正原因是**路径上压根没有标记**：

```bash
nstat -az | grep -iE 'DeliveredCE|InCEPkts'   # 自开机以来全为 0
```

**判断 ECN 有没有用，要先量 CE 计数，而不是直接跑吞吐 A/B。**
`tcp_ecn=1` 保留（零成本，将来路径上出现 L4S/AQM 时能立刻吃到）。

> **测量口径警告**：`speed.cloudflare.com` 会对频繁测速返回 **HTTP 429**，
> 此时 `%{speed_download}` 变成 0 而 **curl 退出码仍是 0**，极易被误读成
> 「吞吐掉到 0」。做吞吐基准要用 cachefly 一类不限流的源，并显式检查
> `http_code` 与 `size_download`。

---

## 十七、v2.5.4 BBRv3 上的 25 样本回归基线

同机内核换到 `7.2.3-joeyblog-bbrv3` 后的完整回归，**每条节点 25 个样本**。
本项目 5 条节点的部分：

```
sbbox    tuic            PASS   中位 2.6ms   p95  6.6ms   抖动  2.9x
sbbox    hysteria2       PASS   中位 2.9ms   p95  6.8ms   抖动  4.5x
sbbox    naive-h3        PASS   中位 2.6ms   p95  6.8ms   抖动 16.5x
sbbox    naive-h2        PASS   中位 3.9ms   p95  7.2ms   抖动  2.7x
sbbox    vless-reality   PASS   中位 7.3ms   p95 15.9ms   抖动  8.1x
直连基线                  BASE   中位 1.8ms   p95  3.4ms   抖动  2.1x
13 节点整体 13/13 PASS
```

### 1.〔读法〕抖动倍率会随样本量变大，它不代表变差了

**抖动 = max ÷ 中位。样本越多越容易抓到极端值，这一列必然随 n 增大而增大。**
判断稳定性看 **p95**，不要看抖动倍率。同一台机器同一配置，样本量 9 → 25：

| 节点 | n=9 的 p95 / 抖动 | n=25 的 p95 / 抖动 |
|---|---|---|
| tuic | 447.5ms / **153.7x** | 6.6ms / **2.9x** |
| naive-h3 | 40.4ms / 12.2x | 6.8ms / 16.5x |
| 直连基线 | 18.3ms / 9.6x | 3.4ms / 2.1x |

`tuic` 那个 153.7x 完全是单枪离群，样本量一上来就没了；`naive-h3` 的倍率反而
从 12.2x 涨到 16.5x，但 p95 从 40.4ms 降到 6.8ms —— **倍率涨了而实际更稳**，
这正说明倍率不能单独用来判断好坏。

### 2.〔范围〕本项目 4 条节点里 3 条用不到 BBRv3

TUIC / Hysteria2 / naive-h3 都是 QUIC，拥塞控制在**用户态**，内核换 CC 对它们无效。
BBRv3 实际只影响 **naive-h2** 与出站 TCP 直连。上表里 tuic/hysteria2/naive-h3
的数字好看，跟换内核没有因果关系，别归错功。

---

## 十八、v2.5.5 large 档 tcp_rmem/tcp_wmem 上限补齐到 64MB

`sbbox tune` 的 large 档（内存 ≥ 16GB）此前 `TCP_MEM_MAX=33554432`（32MB），
而同档的 `SOCK_MEM_MAX`（即 `net.core.rmem_max`）已经是 64MB —— 单条 TCP 连接
永远吃不满全局上限。v2.5.5 把 large 档补齐到 `67108864`：

```diff
-TUNE_TIER="large";  SOCK_MEM_MAX=67108864; TCP_MEM_MAX=33554432; ...
+TUNE_TIER="large";  SOCK_MEM_MAX=67108864; TCP_MEM_MAX=67108864; ...
```

medium / entry / small 三档**不变**。另外注意 `sbbox.sh` 里那条
"千兆以上链路 + 16GB 以上内存 → 128M/64M" 的放宽分支（`large+<速率>M` 档）
**在虚拟机上通常走不到**：virtio 网卡的 `/sys/class/net/*/speed` 返回 `-1` 或空，
被归零后判断不成立，于是落回 large 档。这也正是本次要改 large 档本身的原因。

验证：

```bash
sbbox tune on
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem
# 期望：4096  131072  67108864
```

**未采纳的两项**（来自社区流传的 "BBR Blast Smooth" 一键脚本）：

| 该脚本的做法 | 为什么不采纳 |
| --- | --- |
| `net.ipv4.tcp_fin_timeout=8` | 本项目用 `15`；8 秒省下的内存在 16GB+ 机器上没有意义，却会让半关连接提前失去 socket。 |
| 把参数 `>>` 追加进 `/etc/sysctl.conf` | Ubuntu 24.04+ 默认没有该文件；systemd-sysctl 把它排在 `/etc/sysctl.d/*.conf` **之后**应用，会静默盖掉 `sbbox tune` 与 `xh tuning` 的值，而 `sbbox tune off` 只删自己的 `/etc/sysctl.d/99-sbbox.conf`、**回滚不掉**；`>>` 还会在重复执行时堆叠多份。 |

该脚本其余参数（`fq`/`bbr`、`rmem_max`/`wmem_max=64M`、`tcp_tw_reuse`、
`tcp_no_metrics_save`，以及内核本就默认开启的 `tcp_window_scaling`/`tcp_timestamps`/`tcp_sack`）
本项目**均已包含**，且本项目另有该脚本完全没有的 UDP 侧参数
（`udp_rmem_min`/`udp_wmem_min`/`udp_mem`）—— 对 hysteria2 / tuic 这类 QUIC 协议才是关键项。

---

## 十九、v2.5.6 回滚 v2.5.5 的 64MB 缓冲上限

v2.5.5 把 large 档的 `tcp_rmem`/`tcp_wmem` 上限从 32MB 提到 64MB，
**实测连接速度显著下降**，本版回滚到 v2.5.4 的行为（`TCP_MEM_MAX=33554432`）。

**教训：v2.5.5 的验证是不充分的。** 当时只用 `sysctl` 回读确认了参数
「写进去了」，**没有做任何吞吐或延迟的前后对比**。参数写成功 ≠ 变快。

回滚方法（若你已装 v2.5.5）：

```bash
sbbox tune off && sbbox tune on      # 用 v2.5.6 的 sbbox 重跑
sysctl net.ipv4.tcp_rmem             # 期望 4096 131072 33554432
```

> **本项目的调优参数今后不接受"没有前后对比数据"的改动。**
> 判据是同一台机、同一配置下的吞吐/延迟对比，不是参数是否写入成功。

---

## 二十、v2.6.x sing-box 1.14 AnyTLS 落地与全客户端订阅自适应

### 1. 2026 年最新 AnyTLS + TLS 协议落地
基于 sing-box 1.14 架构重构，引入新一代 **AnyTLS** 协议（端口 28443），消除 TLS-in-TLS 特征，抗深度主动探测与流量识别。

### 2. AnyTLS 全客户端参数适配
- **Shadowrocket 专属兼容**：Shadowrocket 的 AnyTLS 解析器强依赖 `peer=`（指定 SNI）和 `hpkp=`（证书 SHA256 指纹）以及 `udp=1`，单靠 `sni=` 会被直接忽略。现已全面升级为多轨并存参数（`peer=` + `sni=` + `hpkp=` + `pinSHA256=`），Shadowrocket 扫码即通，实测握手时延 < 280ms。
- **全客户端智能订阅体系与二维码**：
  - **终端字符二维码直显**：执行 `sbbox sub` 或 `sbbox list` 终端直接输出 ANSI UTF-8 字符二维码，手机客户端扫码即导。
  - **图片直链**：内置服务提供 `/qr.png` 路由直出图片二维码。
  - **客户端专属直链参数**：
    - Clash / Mihomo 订阅直链：`http://<IP>:<PORT>/<TOKEN>?clash=1`
    - sing-box 客户端订阅直链：`http://<IP>:<PORT>/<TOKEN>?singbox=1`

---

## 二十一、v2.7.0 架构精简：剔除 ShadowTLS 全面回归五大稳固主力梯队

在 v2.6.x 实践与现网多客户端（v2rayN、Shadowrocket、sing-box、Mihomo）回归测试中，ShadowTLS 暴露出不可回避的生态碎片化与协议脆弱性：
1. **主流客户端原生不支持**：v2rayN（Windows）官方底层仅支持普通 Shadowsocks，导入 `ss://?plugin=shadow-tls...` 会直接丢弃插件参数裸发密文，引发服务端断连；
2. **握手状态机版本割裂**：ShadowTLS v3（Challenge-Response 挑战应答）与第三方客户端（如 Shadowrocket 仅支持 v2）存在协议级握手死锁，排查与维护成本高；
3. **定位重复且已有更优解**：AnyTLS 原生解决了 TLS 拟态与 TLS-in-TLS 指纹消除问题，VLESS-Reality 原生解决了免证书伪装问题，ShadowTLS 的伪装收益已被 AnyTLS 完全覆盖。

因此在 **v2.7.0** 中，果断移除 ShadowTLS 协议支持，系统回归到纯粹、稳固、全客户端秒连的 **五大核心梯队**：
1. 🥇 **Hysteria2 + TLS**（高速主力，端口 44116，salamander 混淆 + 端口跳跃）
2. 🥈 **VLESS-Reality**（兼容主力，端口 23106，XTLS Vision）
3. 🥉 **AnyTLS + TLS**（新一代 TCP 候选，端口 28443，彻底消除 TLS-in-TLS 特征）
4. 4 **NaiveProxy**（HTTPS/流量形态特殊需求，端口 10489，Chromium 原生指纹）
5. 5 **TUIC v5**（QUIC 备选，端口 18793，标准 0-RTT）

---

## 二十二、免责声明

本项目仅供网络技术研究与学习交流使用。使用者须自行遵守所在国家/地区的法律法规，因使用本脚本产生的一切后果由使用者自行承担。
