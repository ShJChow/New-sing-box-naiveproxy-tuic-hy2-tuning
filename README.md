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
- [十、版本迭代与核心调优演进记录 (v2.1 - v2.7.47)](#十版本迭代与核心调优演进记录-v21---v2747)
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
| 最低协议兼容 | **TLS 1.3**（`min_version: "1.3"`）+ ALPN `["h3", "h2"]`，全面剔除低效串行 HTTP/1.1，兼顾现代极速新协议 |
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
> 域名在 Cloudflare 上时建议追加 `CF_Token=<API Token>`（Zone.Zone 读 + Zone.DNS 编辑）：改用 DNS-01 签发与续期，不占 80 端口、不停服务；域名开了 CF 代理（橙云）时 standalone 续期必败，必须用 DNS-01。
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
| `sbrel` | **`stable`（默认，v2.7.34 起）** | 内核版本通道：默认只跟踪官方正式版；需要测试版新特性（含 alpha/beta/rc）用 `sbrel=pre` |
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
| `sbbox`（或 `sbbox menu`） | 进入交互式管理菜单 |
| `sbbox block cn\|ads on\|off` | 出站屏蔽回国 IP / 广告域名（默认关闭）；`sbbox block show` 查看 |
| `sbbox tune show` | 查看内核流控参数 |
| `sbbox tune win\|mac\|linux` | 输出 Windows / macOS / Linux 客户端本机调优命令 |
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
| `sbbox up [stable\|pre]` | 升级 sing-box 内核或切换通道（默认 stable 通道；支持 `sbbox up stable` / `pre` 一键切换，失败自动回滚） |
| `sbbox log [N]` | 查看最近 N 行日志（默认 20） |
| `sbbox rotate` | 轮换全部协议密码、混淆密码与订阅令牌（端口/UUID/证书不变，客户端需重新导入） |
| `sbbox doctor` | 自检并尝试修复 |
| `sbbox del` | 完全卸载 |

---

## 七、内核版本管理

安装与 `sbbox up` 默认采用 **`stable` 正式版通道**（v2.7.34 起；当前 `v1.14.2`）；需要跟踪 alpha/beta/rc 新特性时可切换 **`pre` 测试版通道**（当前 `v1.15.0-alpha.9`）。已安装机器以 `~/sbbox/sbrel` 里落盘的通道为准，不受默认值变化影响。

- **默认通道 `stable`**：仅从 `releases/latest` 获取官方稳定正式版。
- **测试通道 `pre`**：获取 GitHub 仓库最新 release，不论是否预发布（正式版发布时同样会自动获取最新正式版）。
- **一键切换与配置自愈（v2.7.26 新增）**：支持在两个通道间无缝切换，脚本自动处理 sing-box 1.14 与 1.15+ 之间的配置差异（如 `cache_file` 缓冲写入参数），避免校验 fatal 与误回滚，并持久化通道选择到磁盘：

```bash
# 切换与升级命令
sbbox up                  # 按当前已保存通道升级内核（默认 stable；已是最新则跳过）
sbbox up stable           # 一键切换至官方稳定正式版通道并升级/降级（自动固化为 stable）
sbbox up pre              # 一键切换至最新测试版通道并升级（自动固化为 pre）

# 也支持环境变量语法
sbrel=stable sbbox up     # 切换至稳定版通道
sbrel=pre sbbox up        # 切换至测试版通道
```

> **通道持久化说明**：通道配置固化保存在 `~/sbbox/sbrel` 中。每周日的 cron 自动更新任务将严格遵循已配置的通道执行升级，避免意外篡改版本策略。

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
- `naive+quic://`：QUIC (H3) 极速节点（默认推荐）
- `naive+https://`：HTTP/2 兼容节点（TCP 回退备用）

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

> 订阅里的 Naive 只有 `naive+quic://`（H3）与 `naive+https://`（H2）两条（v2.7.28 起不再下发 `http3://` / `http2://` 重复写法），四条测试已覆盖全部订阅节点。

怎么读这张表：

- **测的是服务端侧的协议栈开销，不是你的实际网速。** 客户端跑在 VPS 本机、经公网 IP 回环，不含最后一公里。直连基线 681.6 MB/s 说明上游几乎不构成瓶颈，因此各节点的差距基本可归因于协议栈本身——但这也意味着**表里没有任何一个数字是你在真实跨境链路上能跑到的**。
- **必须看范围，不能只看中位数。** 早期用单次采样、且测速源本身抖动到数倍时，节点间的排名完全是噪声。换成快速稳定的源并取 9 次中位数后结论才立得住。
- **H2 是 H3 的近三倍（169.7 对 59.6）**，同一个 Naiveproxy 入站、同一个端口，差别只在承载。QUIC 在用户态收发包，零丢包环境下天然吃亏；内核态 TCP 在理想链路上占优是正常结果。**真实跨境链路一旦出现丢包，这个排序会反过来**——这正是订阅默认把 H3 排在首位的原因，不要照着这张表去选节点。
- **Hysteria2 是最慢也最稳的一档**（31.0 MB/s，波动最小）。瓶颈在协议自身的拥塞控制与用户态包处理，而非链路——同机直连有 681 MB/s 可作对照。它的价值在弱网丢包场景，本测试环境（零丢包）恰好是它最不占优的场景，**吞吐低于 Tuic 属预期行为，不是故障**。
- 三个协议的握手中位数都在 30 ms 以内，与直连基线的 23 ms 差距很小，说明 `zero_rtt_handshake` 与 BBR 均已生效。H2 那个 244 ms 的上界是单次离群，中位数未受影响。

逐条自检用 `sbbox doctor`；若某条节点在客户端不通而本机自测正常，问题在该设备到 VPS 的网络路径，而非服务端配置。

---

## 十、版本迭代与核心调优演进记录 (v2.1 - v2.7.47)

本项目经跨洋弱网环境（160ms+ / 1% 丢包）数十轮实测迭代，核心演进总结如下：

| 演进领域 | 涉及版本 | 核心技术方案与调优结论 |
| :--- | :--- | :--- |
| **四大主力协议收敛** | v2.7.0–v2.7.22 | 聚焦四大主力（Hysteria2 / AnyTLS / NaiveProxy / TUIC）；v2.7.22 彻底下线 Reality 并默认不安装，引入 `close_port` 自愈清理防火墙 |
| **AnyTLS 客户端链接协议规范加固** | v2.7.31 | 针对 v2rayN（sing-box 内核）导入 AnyTLS 断连修复：在 `anytls://` 节点链接参数中显式补齐 `security=tls`，满足 v2rayN 内部 `_node.StreamSecurity` 强校验规则，彻底根治此前因缺少该参数导致客户端生成空 TLS 配置触发 `FATAL: TLS required` 的问题；补充证书指纹固定参数（`pcs` / `pinSHA256`）；服务端 `anytls-in` 移除冗余 TFO 规避黑洞惩罚；经真实出站与全矩阵 CI 验证，四大主力全通 |
| **AnyTLS 深度扩容会话池提速** | v2.7.30 | 针对 AnyTLS 作为主力节点的首屏与并发提速：空闲会话池由 2 深度扩容至 4（`min_idle_session: 4` / `min-idle-session: 4`），保持 4 条热温 TLS 1.3 会话待命，消除网页多资源加载时的握手 RTT 与 TCP 队头阻塞，实现真正 0-RTT 极速首屏开包；空闲会话超时延长至 5 分钟（`5m` / `300s`），消除频繁断开重连；巡检间隔收敛为 15 秒（`15s` / `15`），更快剔除死连接；sing-box 客户端补齐 `bind_address_no_port: true` 减少端口碰撞；Mihomo 移除已废弃的 `global-client-fingerprint` 告警项 |
| **AnyTLS / NaiveProxy 深度调优** | v2.7.1–v2.7.25 | AnyTLS 升级为纯 TLS 1.3，ALPN 收敛至 `["h2"]`（v2.7.27 修正：AnyTLS 走 TCP，此前误写入 QUIC 专属的 `h3`），彻底清除节点链接与模板中遗留的 HTTP/1.1 与 HTTP/1.2，杜绝队头阻塞；启用 8 级填充防 TLS-in-TLS，深度调优会话池复用；NaiveProxy 严格遵守 Cronet 禁忌；v2.7.23 对齐 klzgrad 官方规范，全面剔除 TFO（防 0.1% 罕见特征及丢包黑洞超时）；并发收敛（`insecure_concurrency=2`），根治多连接竞争缓冲与 ACK 饥饿，协同服务端 BBRv3 单流/双流精准流控与 64MB 缓冲：h2 下行飙升至 209 Mbps（+90%，0% 丢包达 391 Mbps）；h3 剥离冗余 TCP 参数，下行提速至 204 Mbps（+63%，1G 线下达 413 Mbps），上行达 92 Mbps |
| **内核双通道与配置自愈** | v2.7.7–v2.7.26 | 明确 pre（默认测试版）与 stable（稳定正式版）双通道规范；根治降级 stable 时因 1.15 专属字段（`buffer_size`/`flush_interval`）导致的校验 FATAL 回滚循环；新增 `sbbox up stable` 与 `sbbox up pre` 快捷切换与配置动态自愈适配机制；通道选择持久化至磁盘供每周自动升级严格遵守；`sbbox status` 补齐当前内核通道可视化指示 |
| **AnyTLS ALPN 修正** | v2.7.27 | AnyTLS 为纯 TCP 协议，服务端入站、`anytls://` 链接（`alpn=h2`）、sing-box 客户端与 Mihomo 模板四处 ALPN 由 `["h3","h2"]` 收敛为 `["h2"]`，保持 TLS 1.3 不降级、不加回 `http/1.1`。验证：稳定版 sing-box 1.14.2 `check` 通过并实测走流量；`openssl s_client -alpn h2` 协商为 h2。v2rayN 需重新更新订阅。新版 v2rayN 支持 Naive（内核选 sing-box），但只识别订阅中的 `naive+https://` 与 `naive+quic://`，`http2://` / `http3://` 两条请忽略 |
| **Naive 订阅去重** | v2.7.28 | 订阅与 `sbbox list` 不再输出 `http3://` / `http2://` 两条 Naive 链接：它们与 `naive+quic://` / `naive+https://` 指向同一入站，v2rayN 不识别、导入即 -1。验证：重新生成后 `nodes.txt` 中 Naive 仅剩 2 条 |
| **小火箭 Naive 按 UA 下发** | v2.7.29 | 订阅服务识别 `Shadowrocket` UA，把 `naive+quic://` / `naive+https://` 现场转换为小火箭识别的 `http3://` / `http2://`；其他客户端仍只收到 `naive+` 写法。验证：以小火箭 UA 拉取得到 `http3`/`http2`，以 v2rayN UA 拉取得到 `naive+quic`/`naive+https` |
| **流控加固与 QDoS 防御** | v2.1–v2.7.21 | 外置 Hy2 接收窗口升至 8M/20M 根治慢线上传限速；默认关闭大范围端口跳跃；Netfilter hashlimit 令牌桶抗洪；TUIC 严禁注入 uTLS |
| **客户端生态兼容与全自动 TUN** | v2.7.16–v2.7.21 | 剔除 1.15+ FATAL 阻断项（`download_detour`/`store_rdrc`）；客户端订阅原生内置 `tun-in` + FakeIP，解决首连远程 DNS 往返延迟 |
| **系统底层网络性能与安全** | v2.5.0–v2.7.20 | 协同 BBRv3 与 TCP Brutal；维持 64MB Socket 缓冲；网卡多队列 RPS/RFS 软中断均衡；`fs.suid_dumpable=0` 防内存转储；内置 WARP 解锁流媒体 |
| **网卡 fq 队列开机持久化** | v2.7.32 | 修复重启后 fq 失效：`net.core.default_qdisc=fq` 只对此后新建的 qdisc 生效，网卡在 sysctl 加载前就已建好，实测重启后出口网卡是 `mq` + `pfifo_fast`，QUIC 依赖的 fq pacing 丢失；此前 fq、收发环形队列、GRO/GSO/TSO、`txqueuelen`、RPS/RFS 都只在 `sbbox tune on` 时执行一次。现写成 `/usr/local/sbin/sbbox-nic-tune` + `sbbox-nic.service`（OpenRC 用 `/etc/local.d`）开机重设，`sbbox tune off` 与卸载时移除。fq 写法由单个 root fq 改为多队列网卡 `mq` 下每个 TX 队列挂 fq（参数 `limit 20480 flow_limit 4096 quantum 18028 initial_quantum 90140`），与同机 Xray 一致，谁后执行结果都相同，不再互相覆盖队列结构。核对：`tc qdisc show dev <网卡>`，不能只看 sysctl。同机 Xray 在 v4.9.44 同步加入 |
| **证书续期钩子自动挂载与 DNS-01** | v2.7.33 | 修复续期后 sbbox 仍用旧证书：`$CERT_DIR`（`~/sbbox/cert`）是 acme 证书的独立副本，此前安装时从不挂续期钩子，acme.sh 续期成功也不会更新它，证书到期当天 Naive / AnyTLS / TUIC / 外置 Hy2 同时失效。现安装末尾自动执行 `sbbox cert hook`（reloadcmd 追加 `sbbox cert sync`，保留原有落地路径；刻意不放在 `install_cert` 里——hook 会立即执行 reloadcmd，而 sync 又调 `install_cert`，会递归），`sbbox doctor` 新增「证书续期钩子」检查并自动修复。`alns=1` 时传 `CF_Token` 即用 `dns_cf` 签发，不再停 nginx / xray 让出 80 端口。注意：续期后叶证书指纹变化，开了 pinSHA256 / pcs 的客户端需重新导入订阅。同机 Xray 在 v4.9.45 同步加入 DNS-01 与 `xh cert` |
| **默认内核通道改为 stable 与 tcp-brutal 2.0.1 适配** | v2.7.34 | `sbrel` 默认值由 `pre` 改为 `stable`：手机 SFI/SFA、v2rayN 等客户端多为正式版内核，服务端同版更稳；已安装机器以 `~/sbbox/sbrel` 落盘值为准。实测切换（1.15.0-alpha.9 → 1.14.2，客户端固定 1.14.2，160ms/1% 丢包、300↓/50↑，N=3）五节点下行 / 上行范围全部重叠无退化：AnyTLS 180→171、Naive-H3 203→201、Naive-H2 173→167、TUIC 19→20 Mbps（外置 Hy2 对照 112→101）；1.14.2 对服务端与客户端配置 `check` 均无弃用警告，`cache_file.buffer_size` / `flush_interval` 由版本自愈逻辑自动移除。tcp-brutal 上游 2.0.1 已自带 `tso_segs` 适配（`BRUTAL_HAVE_TSO_SEGS`），本项目 `patch_tcp_brutal_tso_segs` 遇到上游已适配的源码一律跳过——该补丁把新钩子接到恒返回 2 的函数上，会在 7.1+ 内核把 TSO 限成每次 2 段。同机 Xray 在 v4.9.46 同步加入 tcp-brutal 补丁跳过 |
| **外置 Hysteria2 / tcp-brutal 新版本提醒与校验更新** | v2.7.35 | 每周 `sbbox up` 顺带**只检查**外置 Hysteria2（hysteria-sbbox）与 tcp-brutal 新版本：写入 `~/sbbox/updates-available`，root 登录时与 `sbbox status` 显示，**不自动安装**；日志 `journalctl -t sbbox-autoupdate`。手动更新：`sbbox hy2 update`——二进制 sha256 必须同时等于发布者 `hashes.txt` 与 GitHub 独立计算的资产 digest，新二进制自报版本须与目标一致，替换后重启 hysteria-sbbox（同一二进制若被 hysteria-server 使用则一并重启）并复核 UDP 端口，失败回滚；`sbbox brutal update`——同样双重校验，只编译进 DKMS（下次开机生效），与同机 xh 共用锁。实测（隔离路径模拟旧版）：正常更新、端口复核失败回滚、下载被篡改拒绝三种情况均符合预期。同机 Xray 在 v4.9.47 同步加入 nginx / tcp-brutal 的提醒与校验更新 |
| **TUIC 客户端拥塞控制改回 cubic** | v2.7.36 | 修复 TUIC 在同一条连接上大量上传后**下载塌到 ~20 Mbps 且一直不恢复**：此前客户端（`sbox_client.json` / `tuic://` 链接 / Mihomo）写死 `bbr`。sing-quic 与 Mihomo 的 BBR 把纯 ACK 包也计入 pacing，客户端做过大量发送后，其 BBR 状态拖慢回给服务端的 ACK，服务端下行被拖垮；TUIC 有 10s 心跳、连接长期存活，所以故障一直持续到重连。排查：与丢包无关（160ms/0% 也塌到 22），与测速顺序无关，服务端换 cubic / new_reno 下行只剩 6 / 25（按丢包降速），问题只随**客户端**算法变化。实测（160ms/1% 丢包、300↓/50↑，每轮下载 60MB 与上传 20MB 交替）：sing-box 客户端 bbr 下 19 / 上 8 → **cubic 下 111~121 / 上 39~41**（new_reno 114 / 39）；Mihomo 客户端 bbr 下 112→19→18 / 上 33~41 → **cubic 下 110 / 160 / 138 / 上 8~15**。客户端统一改回 TUIC 默认 `cubic`（Mihomo 的代价是高 RTT 丢包线路上传偏慢，但不会出现持续性的下行崩塌）；服务端 `tuic-in` 保持 `bbr`。已用 sing-box 1.14.2 `check` 与 `mihomo -t` 校验，并按 UA 核对订阅下发内容。**已导入订阅的客户端需更新订阅** |
| **网卡 MTU 高于 1500 时自动降到 1500（PMTU 黑洞兜底）** | v2.7.38 | 部分云厂商网卡默认 MTU 9000（巨帧），公网路径却只有 1500：服务端发出超过 1500 字节的 TCP 段（如 3.7KB 的 TLS 证书链）在公网出口被静默丢弃，表现为 TCP 握手成功、TLS 阶段超时或 RST，AnyTLS / Naive-H2 / Reality 全断，而 QUIC 节点（单包 <1280）完全正常。开机网卡调优脚本 `sbbox-nic-tune` 现在会在 MTU 大于 1500 时降到 1500，并补一条 `TCPMSS --clamp-mss-to-pmtu`（mangle POSTROUTING，v4/v6，已存在则不重复，落盘 `netfilter-persistent save`）；只在真的降过 MTU 时才动防火墙。本机 `enp0s6` 为 1480，不触发，行为不变（1480 至 1500 之间不动）。验证：netns 内 veth MTU 9000 → 1500，规则一条，二次执行不重复；MTU 1400 不被改动。 |
| **客户端调优命令移植（`sbbox tune win\|mac\|linux`）** | v2.7.39 | 移植自 xray-xhttp 的 `xh tuning client`：输出 Windows（netsh / 注册表）、macOS（sysctl + LaunchDaemon 开机守护）、Linux 客户端本机调优命令。Windows 的 BBR2 回退改为检查 `$LASTEXITCODE`（netsh 失败不抛异常，try/catch 捕获不到），仅 Win11 22H2+ 支持 bbr2，并覆盖全部 supplemental 模板；macOS 缓冲区自动调优开关用 `doautorcvbuf` / `doautosndbuf`，去掉未核实且对代理无收益的 mptcp 项 |
| **管理菜单（`sbbox`）** | v2.7.40 | 已安装后在终端直接输入 `sbbox`（或 `sbbox menu`）进入交互式管理菜单，风格同 xray-xhttp 的 `xh`：状态 / 节点 / 订阅 / 重启 / 日志 / 内核更新 / 流控调优 / TCP Brutal / 极速优化 / 证书 / 端口跳跃 / 更换端口 / WARP / 外置 Hy2 / 自检 / 凭据轮换 / 卸载。每个动作在子 shell 里执行，子命令内部的 exit 或失败只会回到菜单；轮换与卸载保留原有确认；非交互场景（管道、cron）仍输出帮助与状态，不会卡在菜单上 |
| **出站分流开关（`sbbox block`）** | v2.7.41 | 参考 zxcvos/Xray-script 的可选规则，新增默认**关闭**的 `sbbox block cn on\|off`（出站拒绝回国 IP，geoip-cn）与 `sbbox block ads on\|off`（拒绝广告域名，category-ads-all），`sbbox block show` 查看、`sbbox block update` 重新下载规则集；安装期也可用 `blockcn=1` / `blockads=1`。规则集下载到 `$SB_HOME/rules/` 并以 local 方式引用，不依赖启动时联网；下载或 `sing-box check` 校验失败即回滚，不写出坏配置。回国 IP 屏蔽会让依赖本代理访问国内站点的客户端断流，仅在落地机不需要回国流量时开启 |
| **Reality 对照 XTLS/REALITY README 设置** | v2.7.42 | 服务端 Reality 入站增加 `max_time_difference: 1m`（防重放；客户端系统时间偏差超过 1 分钟会连不上，需开启自动校时）。握手目标 `gateway.icloud.com` 核对符合 README 要求（境外、TLS 1.3、h2、不跳转）。启用方式：`sbbox.sh` 追加 `reap=1`（已安装机器用原有协议参数重跑即可，各协议密钥与端口沿用）；本机已启用 VLESS-Reality 节点 |
| **Reality 时间差校验改为默认关闭** | v2.7.43 | v2.7.42 起服务端 Reality 默认带 `max_time_difference: 1m`，客户端系统时间偏差超过 1 分钟就会连不上；改为默认**不设**，需要时安装期加 `reatd=1m`（时长，如 `30s` / `1m` / `5m`）。已安装机器的现有配置不受影响 |
| **Reality 入站只开 tcp_fast_open（关闭 tcp_multi_path）** | v2.7.44 | 服务端 Reality 入站此前同时开了 `tcp_fast_open` 与 `tcp_multi_path`：监听 MPTCP 对普通 TCP 客户端没有收益，而 v2.7.15 记录过 MPTCP + TFO 同时协商成功时建连超时的组合。改为只保留 `tcp_fast_open`。已安装机器重新生成配置（`sbbox rotate` / `sbbox port` 或重新运行安装）后生效 |
| **全部 TCP 节点统一为只开 TFO（不开 MPTCP）** | v2.7.45 | 对比测速（Reality 入站 4 种 tfo / mptcp 组合 × 客户端 3 种，延迟 160ms、每向 0.5% 丢包，经代理请求 `http://www.apple.com`）：服务端与客户端都开 `tfo+mptcp` 时 16/16 次超时；服务端含 `tfo` 的真连接延迟约 331ms，不含的约 491ms（差一个 RTT）；吞吐无可信差异，近距离下客户端开 MPTCP 更慢。据此 AnyTLS / Naive 入站由 `tcp_multi_path` 改为 `tcp_fast_open`，sing-box 客户端的 Naive-h2 出站同样只开 TFO（AnyTLS 出站不支持 TFO，两项都不设），mihomo 的 Reality 节点去掉 `mptcp: true`。已安装机器重新生成配置（`sbbox rotate` / `sbbox port` / `sbbox list`）后生效 |
| **云端端口清单与节点本机自测（`sbbox ports` / `sbbox selftest`）** | v2.7.46 | 新增 `sbbox ports`（列出需要在云厂商安全组放行的端口与协议，`sbbox doctor` 结束时也会列出）和 `sbbox selftest`（在服务器本机用自己的订阅配置起 sing-box 客户端，逐个节点经 127.0.0.1 真实握手并请求 `http://www.apple.com`，区分「服务端配置 / 证书 / Reality 密钥」问题与「云安全组、客户端网络」问题；失败时附去掉 IP / UUID 的客户端错误）；管理菜单新增第 19、20 项；修复 `sbbox doctor` 修复完成后「剩余 -N 项」出现负数。本机自检「正常」只代表进程在监听，不代表云端已放行 |
| **按平台自动选默认（ARM / AMD）并撤回未测试的 TFO 改动** | v2.7.47 | 安装开始时识别平台并打印：架构（aarch64 / x86_64）、CPU、核数、内存、内核、虚拟化、云厂商（读 DMI，Oracle / AWS / GCP / Azure / 阿里云）。内存 < 1.5GB（如 Oracle 免费 AMD 1GB）默认不安装 TCP Brutal（现场编译内核模块，占内存且拖慢安装；显式 `FEATURE_BRUTAL=true` 仍尊重），无 swap 时给出加 swap 的提示，并给 sing-box 设 `GOMEMLIMIT`（物理内存 60%）；依赖补装 `python3`，并在依赖安装失败时报出缺少的命令（此前 `deps_done` 仍会被标记、再不重试）；安装结束自动列出云安全组需放行的端口与各云的控制台路径。**撤回**：v2.7.45 对比测速只针对 Reality 入站，AnyTLS / Naive 的改动是顺带推广、没有测过，且 Naive 的 TFO 在 v2.7.23 被有意剔除（丢包时触发内核 tcp_fastopen_blackhole 惩罚），因此 AnyTLS / Naive 的入站与客户端出站恢复为原来的 `tcp_multi_path`，只保留 Reality 入站「只开 tfo」。已安装机器重新生成配置后生效 |
| **服务端 DNS 按 CDN 边缘远近重排 · 外置 Hysteria2 指定解析器 · 吸收第三方调优中的有效项** | v2.7.37 | **DNS**：sing-box 服务端 `dns-secure` 改为 `9.9.9.10`（Quad9 不拦截版，DoT），`dns-backup` 改为 `1.1.1.1`。解析耗时只在每个域名首次查询时付一次，返回的 CDN 边缘远近却决定之后每条连接的延迟：本机 32 个常用域名 × 各 3 次，比最优边缘慢 3ms 以上的，8.8.8.8 有 10 个、1.1.1.1 有 5 个、9.9.9.10 只有 1 个（Apple / iCloud / Microsoft 等 Akamai 系差 10~50ms）。**外置 Hysteria2**：`/etc/hysteria/sbbox.yaml` 原先没有 `resolver`，走系统 resolved（本机首选 8.8.8.8）。同一 sing-box 客户端经它取 generate_204，每次都比 Xray 内置 Hy2 慢约 28ms，抓包确认是服务端到目标的 RTT：拿到的是 14ms 外的 Google 边缘，Xray 那边是 0.8ms。现由 `hy2_external_sync_resolver` 追加 `resolver: udp 9.9.9.10:53`（已有 resolver 段原样保留），`sbbox doctor` 会检测并自动补上、重启 hysteria-sbbox。改后热连接 190 → 164ms（1.2 → 1.0 RTT，160ms 下），闲置 65s / 120s 后仍为 1.0 RTT。**系统调优**：`net.core.rmem_max / wmem_max` 由 128MB 收敛为 64MB（含千兆链路分支，与 `tcp_rmem / wmem` 上限一致）；新增 `vm.min_free_kbytes`（large 档 64MB / medium 档 32MB）与 `kernel.sched_autogroup_enabled = 0`；`nf_conntrack` 登记进 `/etc/modules-load.d/sbbox-conntrack.conf`——开机时 systemd-sysctl 早于 iptables / Docker 加载该模块，`nf_conntrack_max` 会被静默跳过（`tune off` 一并删除）；`kernel.core_pattern = core` 改由调优代码写入（此前只在注释里提到、靠手工补写，重跑 `tune on` 就会丢）。这几项吸收自第三方一键脚本（vps-tcp-tune）中与本项目不冲突的部分，其余因与已有取值冲突或实测无收益而不采纳（明细见同机 Xray v4.9.48）。**测过不采纳**：naive `insecure_concurrency` 取 1 与 2 的握手耗时无差异，维持 2；naive-h3 闲置约 30s 后 Cronet 会关掉 QUIC 连接，下次请求多 1 RTT，属客户端行为，服务端不可调。握手测量工具与全节点数据见同机 Xray 仓库 `tools/xray_handshake_bench.py`。同机 Xray 在 v4.9.48 同步加入 64MB 与三项系统调优，并把内置 DNS 同样改为 9.9.9.10 |

---

## 十一、免责声明

本项目仅供网络技术研究与学习交流使用。使用者须自行遵守所在国家/地区的法律法规，因使用本脚本产生的一切后果由使用者自行承担。
