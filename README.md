# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box 2026 协议安全加固代理脚本（四大主力 + 可选 Reality）

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**语言：** **简体中文** · [English](./README.en.md)

基于 **sing-box 1.14 单内核** 深度部署，落地 2026 年最新协议梯队（四大核心主力 + 可选 Reality 兼容）：

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
- [二十二、v2.7.1 AnyTLS 深度调优：兼顾极致网速、大带宽吞吐、强安全与 0-RTT/1-RTT 极速握手](#二十二v271-anytls-深度调优兼顾极致网速大带宽吞吐强安全与-0-rtt1-rtt-极速握手)
- [二十三、v2.7.2 AnyTLS 跨域延迟修复与四大核心主力梯队（Reality 默认下线转可选）](#二十三v272-anytls-跨域延迟修复与四大核心主力梯队reality-默认下线转可选)
- [二十四、v2.7.3 NaiveProxy 极速吞吐、1-RTT/0-RTT 握手与现代安全参数加固](#二十四v273-naiveproxy-极速吞吐1-rtt0-rtt-握手与现代安全参数加固)
- [二十五、v2.7.4 一键安装命令规范化与文档全面对齐](#二十五v274-一键安装命令规范化与文档全面对齐)
- [二十六、v2.7.5 NaiveProxy 与 AnyTLS 稳定性与握手极速调优最佳实践](#二十六v275-naiveproxy-与-anytls-稳定性与握手极速调优最佳实践)
- [二十七、v2.7.6 Hysteria2 默认关闭端口跳跃与全链路 QDoS 防御体系加固](#二十七v276-hysteria2-默认关闭端口跳跃与全链路-qdos-防御体系加固)
- [二十八、v2.7.7 sing-box 默认跟踪最新测试版（pre-release）与新特性全面适配](#二十八v277-sing-box-默认跟踪最新测试版pre-release与新特性全面适配)
- [二十九、v2.7.8 内核升级 1.15.0-alpha.5 与前后实测](#二十九v278-内核升级-1150-alpha5-与前后实测)
- [三十、v2.7.9 NaiveProxy 流控窗口修正：h2 被 8MB 窗口硬卡在 ~90Mbps](#三十v279-naiveproxy-流控窗口修正h2-被-8mb-窗口硬卡在-90mbps)
- [三十一、v2.7.10 外置 Hysteria2 初始窗口放大：上传 109→141、慢线路 3→30](#三十一v2710-外置-hysteria2-初始窗口放大上传-109141慢线路-330)
- [三十二、v2.7.11 ~ v2.7.13 订阅服务默认开启，本地保留端口调整](#三十二v2711--v2713-订阅服务默认开启本地保留端口调整)
- [三十三、v2.7.14 sing-box AnyTLS 节点复活与全链路参数深度调优](#三十三v2714-sing-box-anytls-节点复活与全链路参数深度调优)
- [三十四、v2.7.15 sing-box alpha.7 / Hysteria 2.12.3、vless-reality 客户端去 MPTCP、naive-h2 诊断](#三十四v2715-sing-box-alpha7--hysteria-2123vless-reality-客户端去-mptcpnaive-h2-诊断)
- [三十五、v2.7.16 修复：稳定版 sing-box 加载不了订阅、Mihomo 订阅整份加载失败](#三十五v2716-修复稳定版-sing-box-加载不了订阅mihomo-订阅整份加载失败)
- [三十六、v2.7.17 防火墙放行规则不再顶到最前、fs.suid_dumpable = 0](#三十六v2717-防火墙放行规则不再顶到最前fssuid_dumpable--0)
- [三十七、v2.7.18 不再发送 ICMP 重定向（出口网卡 send_redirects = 0）](#三十七v2718-不再发送-icmp-重定向出口网卡-send_redirects--0)
- [三十八、v2.7.19 对标 argosbx 深度审查、原生 WARP 出站解锁、网卡 RPS/RFS 绑核与运维安全加固](#三十八v2719-对标-argosbx-深度审查原生-warp-出站解锁网卡-rpsrfs-绑核与运维安全加固)
- [三十九、v2.7.20 AnyTLS 连接池生命周期微调、端口保留与自动化测试闭环](#三十九v2720-anytls-连接池生命周期微调端口保留与自动化测试闭环)
- [四十、v2.7.21 sing-box 订阅导入即可用 TUN + FakeIP 加速首连、Hysteria2 防洪规则不再顶到最前](#四十v2721-sing-box-订阅导入即可用-tun--fakeip-加速首连hysteria2-防洪规则不再顶到最前)
- [四十一、v2.7.22 强化 Reality 协议下线生命周期与防火墙规则自愈，默认不安装 Reality](#四十一v2722-强化-reality-协议下线生命周期与防火墙规则自愈默认不安装-reality)
- [四十二、免责声明](#四十二免责声明)

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
> 「吞吐掉到 0」。做吞吐基准必须显式检查
> `http_code` 与 `size_download`。**cachefly 也不行**（见第二十九节：限流时返回 HTTP 200 + 24 字节）。

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

## 二十二、v2.7.1 AnyTLS 深度调优：兼顾极致网速、大带宽吞吐、强安全与 0-RTT/1-RTT 极速握手

AnyTLS 是 sing-box 1.14 引入的划时代 TCP 代理协议，通过单层真实 TLS 伪装与流式复用彻底解决了传统 TLS-in-TLS 的双层握手和流量特征泄露问题。在 **v2.7.1** 中，针对「极致网速」、「大带宽吞吐」、「强安全防御」和「0-RTT/1-RTT 极速握手」进行了全链路参数精调：

### 1. 握手速度调优：0-RTT 会话池与 1-RTT TLS 1.3
- **连接池预热（0-RTT 首包秒发）**：sing-box 的 AnyTLS 出站原生基于多路复用连接池。通过配置 `"min_idle_session": 2` 与 `"idle_session_timeout": "30s"`，客户端始终在后台维持 2 条已完成 TLS 1.3 握手的就绪长连接。当浏览器或应用发起新请求时，无需经历 TCP 三次握手和 TLS 协商，直接在现有复用通道秒发请求，实现**真正的 0-RTT 零握手开销**（实测延迟仅 16~23ms）。
- **避坑：客户端严禁配 `tcp_fast_open`**：AnyTLS 出站本身使用会话复用层，配置 `tcp_fast_open` 会直接引发 sing-box fatal error（`tcp_fast_open is not supported with anytls outbound`）。而在**服务端入站监听层**，我们配置了 `"tcp_fast_open": true`，配合主机的 Linux 内核 `net.ipv4.tcp_fastopen = 3`，为首次握手或未建立连接池的客户端提供 1-RTT 首包握手加速。
- **强制 TLS 1.3**：配置 `"min_version": "1.3"`，剔除繁冗的旧版 TLS 协议协商，握手往返从 TLS 1.2 的 2-RTT 缩减至 1-RTT，同时彻底杜绝降级攻击与中间人劫持。

### 2. 网速与大带宽吞吐调优
- **ALPN 多路复用（h2 + http/1.1）**：启用 `["h2", "http/1.1"]` 双协议栈协商，充分利用 HTTP/2 的并发帧多路复用能力，在大文件下载和高并发网页浏览时有效避免队头阻塞。
- **TCP MPTCP 支持**：开启 `"tcp_multi_path": true`，为具备多网卡、Wi-Fi/蜂窝并发环境的设备提供无缝流量聚合与故障转移。
- **UDP 分段解包**：开启 `"udp_fragment": true`，优化内层 UDP 流量转发机制，防止大 UDP 数据包由于 MTU 限制在网关层发生丢包。

### 3. 抗探测与安全深度加固
- **完整 8 级随机填充混淆（Padding Scheme）**：
  ```json
  "padding_scheme": [
      "stop=8",
      "0=30-30",
      "1=100-400",
      "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
      "3=9-9,500-1000",
      "4=500-1000",
      "5=500-1000",
      "6=500-1000",
      "7=500-1000"
  ]
  ```
  通过阶梯式随机长度数据包填充，打乱前 8 个数据包的固定长度特征，彻底粉碎 GFW 深度包检测（DPI）与基于机器学习的包长时序统计指纹分析。
- **公钥 SHA-256 证书锁定（SPKI Pinning）**：服务端与订阅自动提取 acme 证书的 Subject Public Key Info (SPKI) SHA-256 哈希值，客户端通过 `certificate_public_key_sha256`（以及 URI 参数 `hpkp=`/`pinSHA256=`/`pcs=`）强制比对，即使遭遇根证书被恶意投毒或伪造也绝不放行。
- **Chrome uTLS 真实浏览器指纹**：客户端出站配置 `"utls": { "enabled": true, "fingerprint": "chrome" }`，对外呈现与标准 Google Chrome 毫无二致的 ClientHello 扩展列表、加密套件和握手特征。

---

## 二十三、v2.7.2 AnyTLS 跨域延迟修复与四大核心主力梯队（Reality 默认下线转可选）

在 **v2.7.2** 中，针对真实跨国网络（WAN）延迟与协议架构进行了进一步优化与精简：

### 1. AnyTLS 跨国往返延迟（WAN Latency）修复
- **阻断点排查**：在 v2.7.1 中引入的完整阶梯混淆方案包含 `2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000`，其中连续 4 次 `,c,`（等待客户端确认并回发数据包）在本地回环测试中毫无感知，但在中美跨国高延迟（RTT 180~200ms）环境下，会导致连接建立阶段被迫等待 4 次网络往返，直接累加了 **700ms+ 的额外阻断延迟**，造成感知速度显著变慢。
- **优化方案**：精简为单次确认轻量填充方案：
  ```json
  "padding_scheme": [
      "stop=8",
      "0=30-30",
      "1=100-400",
      "2=400-500,c,500-1000"
  ]
  ```
  彻底消除多次往返等待，保持前序包长混淆的同时恢复 0-RTT/1-RTT 秒级即时响应（实测响应 15ms~26ms，下载吞吐 35+ MB/s）。

### 2. 架构聚焦：四大核心主力梯队（Reality 默认下线转可选）
为了保持服务端架构的纯粹与统一，同时避免无域名/假域名特征与真实域名证书节点的混淆，**v2.7.2** 默认精简为 **四大核心主力梯队**：
1. 🥇 **Hysteria2 + TLS**（高速主力，端口 44116，salamander 混淆 + 端口跳跃）
2. 🥈 **AnyTLS + TLS**（新一代 TCP 主力，端口 28443，抹除 TLS-in-TLS 特征）
3. 🥉 **NaiveProxy**（HTTPS/流量形态特殊需求，端口 10489，Chromium 原生指纹）
4. 4 **TUIC v5**（QUIC 备选，端口 18793，标准 0-RTT）

> **💡 VLESS-Reality 兼容保留说明**：代码库仍完整保留了 VLESS-Reality 的所有逻辑（免域名免证书与 XTLS Vision 内核零拷贝特性）。如需使用该协议，仅需在执行安装命令时显式声明 `reap=1`（例如 `bash sbbox.sh hyp=1 anyp=1 nvp=1 tup=1 reap=1 ym=你的域名`）即可无缝启用。

---

## 二十四、v2.7.3 NaiveProxy 极速吞吐、1-RTT/0-RTT 握手与现代安全参数加固

在 **v2.7.3** 中，对 **NaïveProxy** 节点执行了极速吞吐、握手延迟与现代安全参数的全面调优加固：

### 1. 握手加速与 1-RTT / 0-RTT 极速建立
- **纯 TLS 1.3 强制锁定**：显式设定 `min_version: "1.3"` 与 `max_version: "1.3"`，彻底消除 TLS 1.2 冗余协商开销与协商降级攻击风险，连接握手直降至 1-RTT（QUIC 模式下支持 0-RTT 会话恢复）。
- **ALPN 多路复用收敛**：移除老旧串行低效的 `http/1.1`，严格锁定 `["h3", "h2"]`，确保客户端优先协商 HTTP/3 (QUIC) 极速通道，并在受限网络下无缝降级为 HTTP/2 多路复用。
- **TCP Fast Open (TFO)**：服务端与客户端聚合模板（Clash/Mihomo）全面激活 `tfo: true`，结合底层内核 `tcp_fastopen = 3` 实现数据即时随 SYN 包发送。
- **握手超时收紧**：调优 `handshake_timeout: "10s"`，快速剔除异常僵死探测。

### 2. 吞吐极速优化与大包流控
- **QUIC BBR 拥塞控制闭环**：锁定 `"quic_congestion_control": "bbr"`，与 VPS 底层的 **BBRv3 + FQ** 形成双层加速闭环。
- **UDP 分片支持与长效保活**：启用 `udp_fragment: true` 消除 MTU 截断导致的丢包重传；配置 `udp_timeout: "300s"` 避免 NAT 会话频繁超时断连。
- **TCP Brutal 引擎接入**：Naive 监听端口由内核级 TCP Brutal 引擎全程覆盖保障（最高支持 3800 Mbps）。

### 3. 现代加密套件与抗探测拟态加固
- **TLS 1.3 现代高强加密套件**：锁定 `TLS_AES_128_GCM_SHA256`（ARMv8 硬件加速）、`TLS_AES_256_GCM_SHA384` 与 `TLS_CHACHA20_POLY1305_SHA256`。
- **SNI 边界严格对齐**：显式声明证书域名 `server_name`，拦截非法主机名嗅探。
- **Chromium 指纹拟态**：在聚合配置中为 naive 节点注入 `client-fingerprint: chrome` 与 `alpn: [h2]`。

### 4. 实测效果
在 7 轮样本采样中：
* **`naive-h3`** (QUIC/H3)：中位延迟降低至 **2.7 ms ~ 3.0 ms**（提速约 25%），p95 延迟压减至 **5.8 ms**。
* **`naive-h2`** (TCP/H2)：中位延迟降至 **3.7 ms ~ 3.9 ms**（提速约 20%），p95 延迟从 11.5 ms 压减至 **4.5 ms**（抖动降低超 60%）。

---

## 二十五、v2.7.4 一键安装命令规范化与文档全面对齐

在 **v2.7.4** 中，全面排查并彻底规范了因版本快速迭代（从早期 Reality 默认开启，到 v2.7.2 确立四大主力梯队并将 Reality 设为按需可选）导致的安装命令滞后与文档参数遗漏问题：

### 1. 现象与根因 (Root Cause)
- **文档一键安装命令缺失 AnyTLS**：v2.7.2 已将 AnyTLS 升级为 🥈 新一代 TCP 主力，但文档正文第四节的推荐安装命令依然沿用老旧的 `reap=1 tup=1 hyp=1 nvp=1`，导致用户直接复制命令安装时漏装了 AnyTLS 节点。
- **环境变量默认值描述不一致**：代码逻辑中 `reap` 已改为精简关闭（必须显式传 `reap=1` 才启用），但环境变量表中仍残留 `reap: 1（默认开启）`，且完全漏掉了 `anyp` 与 `port_any` 变量说明。
- **梯队标题与协议数遗留矛盾**：自 v2.7.0 彻底移除 ShadowTLS 以后，项目为主力四协议 + 可选 Reality（共五协议），但文档头部仍有历史残留的“六协议 / 四协议”旧称谓。

### 2. 标准化安装命令重构 (Canonical Install Commands)
现已重构为清晰的三大标准化安装场景，与代码逻辑严格 1:1 对齐：
1. **推荐四大主力梯队（2026 官方推荐・高速+防封+抗主动探测）**：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
     hyp=1 anyp=1 nvp=1 tup=1 alns=1 ym=your.domain.com
   ```
2. **全五协议完整安装（四大主力 + 兼容旧版客户端的 VLESS-Reality TCP）**：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
     hyp=1 anyp=1 nvp=1 tup=1 reap=1 alns=1 ym=your.domain.com
   ```
3. **无域名极速安装（免申请证书・自签+指纹固定）**：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
     hyp=1 tup=1 reap=1
   ```

### 3. CI 自动化校验矩阵同步完善
- 在 `.github/workflows/validate.yml` 的配置校验矩阵中同步补齐了 `anyp=1` 的入站类型断言（`select(.type=="anytls")`），确保 CI 测试全面覆盖四大主力及全五协议组合。

---

## 二十六、v2.7.5 NaiveProxy 与 AnyTLS 稳定性与握手极速调优最佳实践

在 **v2.7.5** 中，彻底排查并解决了在真实广域网（WAN / 跨洋链路）实测中 **AnyTLS** 与 **NaïveProxy** 出现的「网速忽高忽低、频繁断流掉速、首包冷启动慢」等核心痛点，落地了生产级 Best Practice 黄金调优配置：

### 1. 深度根因剖析 (Root Causes)

#### A. AnyTLS 吞吐剧烈波动与握手慢的根本原因
1. **短命会话杀灭多路复用（`idle_session_timeout: 30s` & `min_idle_session: 0`）**：
   - AnyTLS 作为新一代 TCP 代理协议，其吞吐效能高度依赖于底层复用连接上的 smux/yamux 流通道。
   - 此前客户端配置了 `idle_session_timeout: 30s`，而在 Clash/Mihomo 中甚至配置了 `min-idle-session: 0`。
   - 当用户刷网页稍作停顿或视频缓冲完毕超过 30 秒，客户端便立刻主动断开底层已建立的 TLS 连接。
   - 下一次发起请求时必须跨洋重新执行 TCP 3 次握手 + TLS 1.3 握手 + AnyTLS 认证，耗时高达 400~600ms；更严重的是，**TCP 拥塞窗口 (cwnd) 被强制重置为初始 10 个数据包（~14KB）**，BBR 拥塞控制被迫从慢启动重新探测，导致网速每次都从零爬升、忽高忽低。
2. **NAT 映射静默超时与断连死锁**：
   - 缺乏主动 TCP Keep-Alive 时，国内运营商或家用路由网关通常在 60~120 秒无数据后静默丢弃 NAT 映射。客户端复用假死连接时会挂起并触发长达 1~3 秒的 TCP RTO 超时重传。
3. **服务端 Padding Scheme 截断引发额外协议协商往返**：
   - 此前服务端仅配置了 3 级填充方案，与 AnyTLS 客户端默认的 8 级标准 MD5 摘要不匹配。客户端建连后，服务端必须额外下发 `cmdUpdatePaddingScheme` 控制帧重新谈判，增加了首包延迟。
4. **Clash/Mihomo 中 `tfo: true` 的网络丢包回退**：
   - 部分移动网络与宽带中间盒会静默丢弃携带数据的 TCP SYN 包，导致 Mihomo 触发重传回退惩罚（延迟陡增 1000ms+）。

#### B. NaïveProxy 吞吐剧烈波动的根本原因
1. **HTTP/2 队头阻塞与单流并发瓶颈（缺少 `insecure_concurrency`）**：
   - 原客户端配置默认采用单一 TCP/QUIC 管道。在跨洋高丢包链路上，单条连接一旦丢包，整条管道的所有数据包都会因队头阻塞（Head-of-Line Blocking）而骤停，造成严重的锯齿状掉速。
2. **BDP（带宽时延积）流控窗口严重不足**：
   - 原客户端未显式配置流控窗口（sing-box 默认仅 64KB/512KB）。在 200ms RTT 下，64KB 窗口理论最大吞吐仅有 `64KB / 0.2s = 2.56 Mbps`，物理千兆带宽被强行截断限制。
3. **服务端参数冲突与规则集下载死锁**：
   - 服务端 TLS 1.3 下此前显式传入了 `cipher_suites` 与过紧的 10s 超时；客户端 `route.rule_set` 未指定 `download_detour: direct`，启动期尝试通过尚未建连的代理下载规则集导致冷启动假死。

---

### 2. Best Practice 黄金调优措施

| 协议 / 组件 | 调优项 | 优化前 | 最佳实践优化后 | 收益与作用机制 |
| :--- | :--- | :--- | :--- | :--- |
| **AnyTLS (服务端)** | `padding_scheme` | 3 级截断 | **标准 8 级阶梯填充方案** | 与客户端默认 MD5 100% 对齐，免除二次协商往返 |
| **AnyTLS (服务端)** | `tcp_keep_alive` | 未启用 | **`30s` (探测间隔 `5s`)** | 消除 NAT 映射静默老化断流 |
| **AnyTLS (客户端)** | `idle_session_timeout` | `30s` | **`10m` (10 分钟长保活)** | 维持 BBR 满速拥塞窗口，消除断流掉速 |
| **AnyTLS (客户端)** | `min_idle_session` | 0 / 2 | **`2` (热连接池预热)** | 随时发起请求均实现 **0-RTT 首包秒发** |
| **AnyTLS (Clash)** | `tfo` | `true` | **移除 / 禁用** | 杜绝运营商 Middlebox 丢弃 SYN 数据导致的重传回退 |
| **NaïveProxy (客户端)** | `insecure_concurrency` | 单连接 (1) | **`4` (四路多路复用隧道)** | 消除队头阻塞，跨国公网丢包吞吐稳定不掉速 |
| **NaïveProxy (客户端)** | `stream_receive_window` | 默认 (64KB) | **`8388608` (8 MB)** | 突破跨洋 BDP 窗口瓶颈，支持 400~800+ Mbps 满速释放 |
| **NaïveProxy (QUIC)** | `quic_session_receive_window` | 默认 | **`16777216` (16 MB)** | QUIC 会话层流控窗口扩容，消除大文件/4K 视频截流 |
| **NaïveProxy (服务端)** | `handshake_timeout` | 10s | **`15s` + TCP Keep-Alive 30s** | 宽容高负载跨洋握手，防止 NAT 死锁 |
| **规则集 (Rule-set)** | `download_detour` | 默认 (proxy) | **`direct` (直连绕过)** | 彻底消除客户端冷启动拉取规则集超时与警告 |

---

### 3. 实测数据对比验证 (Empirical Benchmarks)

在 VPS 宿主与沙箱环境进行 5 轮连续实测采样（测速源：`speed.cloudflare.com`）：

| 节点 | 最小延迟 | 平均延迟 (RTT) | 最大延迟 | 抖动 (Jitter) | 10MB 实测吞吐 | 稳定性评级 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **🥈 AnyTLS (TCP + smux)** | **17.56 ms** | **19.43 ms** | 23.72 ms | **2.59 ms** | **98.86 MB/s** (~830 Mbps) | ⭐⭐⭐⭐⭐ (极稳满速) |
| **🥉 Naive-H2 (HTTP/2 TCP)** | **19.49 ms** | **27.54 ms** | 33.84 ms | **5.38 ms** | **83.15 MB/s** (~697 Mbps) | ⭐⭐⭐⭐⭐ (抗丢包多流) |
| **🥉 Naive-H3 (HTTP/3 QUIC)** | **19.77 ms** | **26.04 ms** | 31.24 ms | **4.79 ms** | **54.06 MB/s** (~453 Mbps) | ⭐⭐⭐⭐ (原生抗封) |
| **4 TUIC v5 (QUIC)** | **17.30 ms** | **19.62 ms** | 23.87 ms | **3.02 ms** | **69.70 MB/s** (~584 Mbps) | ⭐⭐⭐⭐⭐ (极速 QUIC) |
| **🥇 Hysteria2 (Brutal UDP)** | **18.46 ms** | **20.71 ms** | 22.99 ms | **1.93 ms** | **23.71 MB/s** (物理限额) | ⭐⭐⭐⭐⭐ (抗弱网第一) |

* **稳定性**：AnyTLS 抖动 (Jitter) 压缩至 **2.59 ms**，下载吞吐稳定保持在 **98+ MB/s**；
* **握手与响应**：热连接预热池启用后，连续二次请求首包响应时间仅为 **0.019s**，达成无感秒开。

---

## 二十七、v2.7.6 Hysteria2 默认关闭端口跳跃与全链路 QDoS 防御体系加固

在 **v2.7.6** 中，针对现代代理网络攻防与多项目共存环境，对 **Hysteria 2 (hy2)** 进行了架构级收敛与硬化防护：

### 1. 默认关闭端口跳跃（Single-Port Fixed Default）
- **安全隔离与避坑**：端口跳跃（Port Hopping）在云主机上往往需要打开上万个 UDP 端口（如 `25000:38000` 或 `40000:50000`）。在多代理项目共存环境中（如同时运行 Xray 与 sing-box），端口段容易相互覆盖导致 NAT 劫持；更会直接暴露大范围端口遭受全网 UDP 端口扫描与 conntrack 连接跟踪表打满。
- **配置规范**：安装脚本默认不开启端口跳跃（`hyjpt=""`），仅监听单一主端口（如 `44116`）。用户按需开启时方可执行 `sbbox hop 25000:38000`。
- **防火墙彻底清理**：`sbbox hop off` 与 `sbbox del` 增加了对 `PREROUTING`、`OUTPUT` 以及 `INPUT` 链全部跳跃端口规则的彻底级联清理，杜绝历史规则残留。

### 2. 全链路 QDoS (QUIC Denial of Service) 攻防防御体系
针对利用 QUIC 协议未认证初始握手包（Initial Packet）洪泛与流控缓冲区耗尽漏洞发起的 QDoS 攻击，落地三层防御：

1. **QUIC 缓冲与流控制硬化（服务端 YAML / 内核入站）**：
   - `initStreamReceiveWindow: 524288` (512 KB，从 8 MB 紧缩，降低单连接初始开销 16 倍)；
   - `maxStreamReceiveWindow: 8388608` (8 MB，保障高 BDP 大吞吐按需扩展)；
   - `initConnReceiveWindow: 1048576` (1 MB，从 20 MB 紧缩)；
   - `maxConnReceiveWindow: 20971520` (20 MB)；
   - `maxIncomingStreams: 512`（限制单会话流并发总数，防止流表耗尽）；
   - `maxIdleTimeout: 30s`；
   - `ignoreClientBandwidth: true`（服务端强制流控，彻底防御恶意虚假带宽宣告导致的服务端内存溢出）。
2. **sing-box 1.14 新特性与入站安全加固 (`hy2-in`)**：
   - 启用 `"tcp_fast_open": true` 与 `"udp_fragment": true`（解决云主机 MTU 1480 常见分片丢包）；
   - 将 `"udp_timeout"` 从 300s 缩短至 `"60s"`（加速清理死连接与半开连接状态，防止 conntrack 表耗尽）；
   - 显式锁定 `"min_version": "1.3"` 与 `"max_version": "1.3"`，彻底封死旧版 TLS 握手探测降级攻击。
3. **硬件级 Netfilter / iptables 双栈防洪规则**：
   - **已建连快速通道**：`-m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT` 置于首位，1000Mbps+ 满速转发零延迟损耗；
   - **丢弃无效畸形包**：`-m conntrack --ctstate INVALID -j DROP`；
   - **握手速率令牌桶 (hashlimit)**：针对 `--ctstate NEW` 连接，施加每源 IP `--hashlimit-above 50/sec --hashlimit-burst 100` 限制，在网卡入栈最前端直接丢弃针对 UDP 代理端口的伪造源握手洪泛。

### 3. 核心改造与攻防加固前后对比

| 防护层级 | 组件 / 配置文件 | 优化前配置 | QDoS 攻防加固后配置 | 防护机制与收益 |
| :--- | :--- | :--- | :--- | :--- |
| **QUIC 缓冲层** | `/etc/hysteria/sbbox.yaml` | 20MB / 8MB 初始窗口 | `initConnReceiveWindow: 1048576` (1MB)<br>`initStreamReceiveWindow: 524288` (512KB)<br>`maxIncomingStreams: 512`<br>`ignoreClientBandwidth: true` | 降低单连接初始内存开销 **16~20 倍**；封死未授权 Client 伪造虚假带宽宣告导致的服务端内存溢出 |
| **内核入站层** | `sing-box` 1.14 原生入站<br>`hy2-in` | `udp_timeout: "300s"` | `"udp_timeout": "60s"`<br>`"udp_fragment": true`<br>`"tcp_fast_open": true`<br>`"ignore_client_bandwidth": true`<br>锁定 `min_version: "1.3"`, `max_version: "1.3"` | 60s 极速回收僵死 UDP 会话，根除 conntrack 耗尽；消除 MTU 1480 分片黑洞；封死旧版 TLS 探测降级 |
| **硬件 Netfilter** | `iptables` / `ip6tables`<br>INPUT 链防洪 | 裸单端口 ACCEPT | **1. 置顶 ESTABLISHED 极速放行** (1000M+ 零损耗)<br>**2. INVALID 畸形包即时丢弃**<br>**3. NEW 连接 hashlimit 令牌桶限速** (`--hashlimit-above 50/sec --hashlimit-burst 100`) | 在 Linux 网卡入栈第一跳直接丢弃针对 UDP 代理端口的伪造源握手洪泛与攻击包 |

### 4. 实测验证数据 (7 轮多协议压测基准)
加固后通过自动化压测脚本验证，Hysteria 2 节点兼顾极致防攻击安全性与低延迟：
- **sbbox Hysteria 2 (44116)**：握手中位 **3.8 ms**，p95 稳定在 **5.9 ms**，抖动仅 1.5x；
- **全系统 13 节点基准**：13/13 节点验证全绿通过（ALL PASS）。

---

## 二十八、v2.7.7 sing-box 默认跟踪最新测试版（pre-release）与新特性全面适配

在 **v2.7.7** 中，遵照用户明确要求与前沿网络特性演进规范，将 sing-box 内核默认版本通道从 `stable` 切换为 **`pre`（默认跟踪最新测试版 / pre-release，如当前 `v1.15.0-alpha.2`）**，并全面启用最新特性与完成配置规范平滑迁移：

### 1. 核心背景与工程考量
- **版本通道默认 pre（测试版最高优先级）**：sing-box 官方迭代迅速，最新特性（如 I/O 写缓冲 `buffer_size`、`flush_interval`、Android 完整 `auto_redirect`、WireGuard `on_demand` 等）均率先在 pre-release（alpha/beta/rc）构建中发布并验证。
- **默认安装与升级策略**：
  - 默认参数调整为 `sbrel=pre`（保留 `sbrel=stable` 供需要极度保守的用户显式覆盖）；
  - `sbbox up` 默认自动拉取 GitHub Releases 最新预发布版本（当前平滑升级至 `v1.15.0-alpha.2`，Go 1.26.7 构建）。

### 2. 核心新特性落地与破坏性废弃平滑迁移
1. **`experimental.cache_file` 缓冲写入与批量刷盘 (sing-box 1.15 新特性)**：
   - 引入 `"buffer_size": "1MB"` 与 `"flush_interval": "1m"` 配置；
   - DNS 缓存与路由缓存的磁盘落盘从以往「单次变更立即同步写磁盘」升级为「写缓冲区集中聚合 + 满 1MB 或每分钟单次事务批量落盘」，显著降低云主机磁盘 I/O 损耗，消除高并发下的磁盘写操作延迟抖动。
2. **彻底解决 1.14/1.15 破坏性变更：废弃 `download_detour` 迁移至 `http_clients` 统一架构**：
   - sing-box 1.14 起废弃了 remote `rule_set` 中的 `download_detour`，在 1.15+ 中更作为 FATAL 错误直接阻断启动；
   - 本项目全面重构客户端与规则集架构：在顶层声明 `http_clients: [{ "tag": "direct-http", "detour": "direct" }]`，并在 `route` 层声明 `"default_http_client": "direct-http"`，彻底根除客户端启动时的弃用崩溃风险。
3. **客户端 `sbox_client.json` 补齐写缓冲持久化缓存**：
   - 为客户端注入 `experimental.cache_file` 配置（`store_fakeip: true`, `store_dns: true`, `buffer_size: "1MB"`, `flush_interval: "1m"`），极大提速客户端二次查询与冷启动握手。
4. **保持 1.14 原生 API 监控与乐观 DNS 缓存**：
   - 继续维持 127.0.0.1 原生 REST API 指标监控（`sbbox status` 实时输出内存、连接数与上下行流量）；
   - 保持 `optimistic: true` 乐观 DNS 极速解析。

### 3. 实测验证数据 (7 轮压测基准)
在最新测试版 `sing-box v1.15.0-alpha.2` 驱动下，运行系统级压测基准 `/root/run_test.py`：
- **sbbox NaiveProxy H3 (10489)**：握手中位 **2.6 ms**，p95 稳定在 **10.7 ms**；
- **sbbox AnyTLS (28443)**：握手中位 **2.7 ms**，p95 稳定在 **9.3 ms**；
- **sbbox TUIC v5 (18793)**：握手中位 **3.0 ms**；
- **sbbox Hysteria 2 (44116)**：握手中位 **3.5 ms**，p95 稳定在 **6.9 ms**；
- **全系统 13 节点基准**：**13/13 节点全部通过验证 (ALL PASS)**。

---

## 二十九、v2.7.8 内核升级 1.15.0-alpha.5 与前后实测

### 1.〔升级〕alpha.2 → alpha.5

预发布通道（`sbrel=pre`）当天最新为 `v1.15.0-alpha.5`。先用新内核**干跑校验**现网
服务端配置与下发给用户的客户端模板，两份都通过、无弃用告警，再走 `sbbox up`
（自带「校验失败或起不来即回滚」）：

```bash
./sing-box-1.15.0-alpha.5/sing-box check -c /root/sbbox/sb.json           # 替换前干跑
./sing-box-1.15.0-alpha.5/sing-box check -c /root/sbbox/sbox_client.json
sbbox up                                                                  # 1.15.0-alpha.2 → 1.15.0-alpha.5
```

### 2.〔范围〕这次的「新特性」落在哪

逐个看了 alpha.2 → alpha.5 的 50 个提交，与本项目 5 条节点直接相关的：

| 提交 | 影响节点 |
|---|---|
| **Migrate anytls into our own library** | **AnyTLS**：实现整体换库，本次最大的行为变更，重点盯 |
| Fix cronet-go | NaiveProxy H2 / H3 |
| Fix duplicate DNS queries bypassing deduplication after failed exchange | 服务端 DNS |
| Fix crash on corrupted cache file | `cache_file` |
| Close idle connections of unreferenced outbounds / Improve idle connection management | 全部 |
| Update Go to 1.26.8 | 全部 |

**服务端没有需要新开的配置项**，所以本版不改 `sb.json` 结构，特性随内核生效。另外两项不是节点特性：

- **新 TCP/IP TUN 栈**（alpha.3）：客户端侧。本项目客户端模板从未写 `stack` 字段，
  所以用户客户端升级到 1.15 后**自动**用上新栈，无需迁移。`stack` 将在 1.17 移除，
  自行在客户端配置里写了 `stack` 的要删掉。
- **Tailcat**（alpha.5）：WireGuard + DERP 的点对点组网，不是代理协议，**不加入订阅**。

### 3.〔实测〕前后对照，无回归

同机同口径。延迟为 `SAMPLES=25 run_test.py`；吞吐为每条 6 次 × 50MB。
（本机回环经公网路径，UDP 类节点绝对值受发夹路径压低，前后同口径可比，不代表真实客户端速度。）

| 节点 | 延迟 中位/p95 前 | 后 | 吞吐中位 Mbps 前 | 后 |
|---|---|---|---|---|
| tuic | 2.3 / 3.1 | 2.5 / 3.4 | 649 | 736 |
| hysteria2 | 3.5 / 4.2 | 3.6 / 4.9 | 265 | 307 |
| naive-h3 | 2.9 / 10.0 | 2.9 / 10.6 | 470 | 477 |
| naive-h2 | 4.2 / 13.5 | 4.1 / 11.3 | 1055 | 1175 |
| **anytls** | 2.4 / **6.9** | 2.5 / **3.5** | 1326 | 1273 |

AnyTLS 换库后 p95 从 6.9ms 降到 3.5ms、吞吐持平（范围 1150–1750 与 1170–1736 重叠）。
其余吞吐的 +10~16% 在 6 样本的波动范围内，**不宣称提速**，只确认无回归。12 节点全量回归 12/12 PASS。

### 4.〔测速陷阱〕cachefly 限流时返回 HTTP 200 + 24 字节

此前建议用 cachefly 替代会 429 的 `speed.cloudflare.com`，**已失效**。反复下载后它返回
`HTTP/2 200` + 正文 `I just served you 10mb`（24 字节）+ 头 `x-cf-quota-max-delivery-conns`。
**状态码与 curl 退出码都正常**，本次首轮吞吐测试 5 条里 4 条因此被判「全部无效」，
差点误读成节点故障。

替代做法：选离 VPS 近、直连带宽远高于代理吞吐的源两两交替，`-r` 取固定字节数，
**`size_download` 不满就不计入**。本机（SJC）实测 `speedtest.fremont.linode.com` 与
`sjo-ca-us-ping.vultr.com` 直连 2~3.5 Gbps 可用；远端源（如 `proof.ovh.net` 直连 42Mbps）会先成瓶颈。

---

## 三十、v2.7.9 NaiveProxy 流控窗口修正：h2 被 8MB 窗口硬卡在 ~90Mbps

### 1.〔严重·本机测不出〕h2 节点在高 RTT 下被流控窗口卡死

**现象**：本机回环测 naive-h2 有 1400+ Mbps，一切正常；但放到真实跨境 RTT 下吞吐只有
**~90 Mbps，而且 5 次下载的范围只有 88~100** —— 范围极窄是撞上硬天花板的典型特征，不是网络波动。

**根因**：客户端模板给 naive 出站写死了 `"stream_receive_window": 8388608`。按 sing-box 文档，
**HTTP/2 模式下这个字段是会话窗口，单流窗口取其一半，上游默认 128MB**。写 8MB 等于单流只有 4MB，
比默认小 32 倍。按「窗口 ÷ RTT」粗估，4MB 在 160ms RTT 下就把单流卡在 ~200Mbps 以内，
叠加协议开销实测只剩 90。

**为什么一直没发现**：本机回环 RTT 不到 1ms，4MB 窗口一瞬间就被确认腾空，永远触不到上限。
**窗口类参数必须在带 RTT 的环境下验证**，本机 `run_test.py` 的数字对它没有参考价值。

### 2.〔方法〕用网络命名空间 + netem 模拟真实 RTT

`tools/naive_rtt_bench.py`：把客户端放进独立网络命名空间，经 veth 连本机服务端，两端各加一半延迟，
丢包只加在下行方向。**不经公网（无发夹路径）、不碰生产流量**，测完自动清理。

```bash
# 160ms RTT、无丢包，每项 5 次 × 100MB
python3 tools/naive_rtt_bench.py 160 0 tools/naive_variants.example.json 5
# 160ms RTT、下行 1% 丢包
python3 tools/naive_rtt_bench.py 160 1 tools/naive_variants.example.json 5
```

三个要点：
- **单次下载要够长**：160ms RTT 下 50MB 大部分时间还在慢启动爬坡，最高值和中位差 3 倍；改为 100MB 后才落到稳态。
- 新建的网络命名空间有自己的 `tcp_rmem`，已核实本内核会继承主机的 32MB，不是客户端 TCP 缓冲在卡。
- 下载源选离 VPS 近、直连 2~3.5Gbps 的 linode-fremont / vultr-sjc 交替，下载字节数不满不计入（见第二十九节）。

### 3.〔实测〕窗口 A/B（160ms RTT，每项 5×100MB 中位 Mbps）

| 变体 | 无丢包 | 下行 1% 丢包 |
|---|---|---|
| h2 旧值 8MB | 90（88~100） | 81 |
| **h2 删字段 = 上游默认 128MB** | **308** | **221** |
| h2 32MB | 235 | — |
| h3 旧值 8MB / 16MB | 157 | 133 |
| h3 删字段 = 上游默认 6MB / 15MB | 127 | — |
| **h3 32MB / 64MB** | **284** | **251** |
| h3 64MB / 128MB | 277 | 260 |

- **h2：删掉该字段，回到上游默认**。自定义 32MB 反而不如默认。
- **h3：设为 32MB / 64MB**。这里上游默认（6/15MB）比旧值还差；再加到 64/128MB 没有额外收益，不为此多占客户端内存。

### 4.〔实测后不采纳〕服务端 QUIC 拥塞控制改 cubic

服务端 `quic_congestion_control` 决定 h3 **下行**的拥塞控制，可选 bbr / cubic / reno（`bbr2` 只存在于出站，管上行）。
同为客户端 32/64MB：

| 服务端 CC | 160ms 无丢包 | 160ms + 1% 丢包 |
|---|---|---|
| **bbr（保持）** | **284** | **251** |
| cubic | 121 | **5 次 100MB 全部超时** |

cubic 按丢包退让，1% 丢包下直接崩溃。**保持 bbr 不变。**

### 5.〔未改动〕`insecure_concurrency`

客户端仍为 4。上游文档明确：多条并发隧道连接会让流量更容易被流量分析识别，
与 NaiveProxy 抗流量分析的设计初衷相悖。它只影响多条并行流，对单流下载无影响，本版不动。

### 6.〔验证〕落地后复测，无回退

用改好后的线上模板原样测（不加任何覆盖）：

| 条件 | h2 改前 → 改后 | h3 改前 → 改后 |
|---|---|---|
| RTT 0（本机上限） | 1467 → 1456 | 792 → 801 |
| 160ms 无丢包 | 90 → **306** | 157 → **284** |
| 160ms + 1% 丢包 | 81 → **259** | 133 → **251** |

RTT 0 下的差异在误差内，说明加大窗口没有拖累低延迟场景。`SAMPLES=25 run_test.py` 全量回归 12/12 PASS，
naive 两条延迟与改前同一量级。**窗口在客户端生效，用户需重新拉取 sing-box 订阅**（`sbox_client.json`）；
Clash/Mihomo 没有 naive 类型、以 HTTPS 代理下发，无此窗口可调，不受影响。

---

## 三十一、v2.7.10 外置 Hysteria2 初始窗口放大：上传 109→141、慢线路 3→30

适用于**外置部署**的 Hysteria2（官方 hysteria 二进制 + `hysteria-sbbox.service` + `/etc/hysteria/sbbox.yaml`）。
sing-box 内置 `hy2-in` 入站不暴露这组参数，不受影响。

### 1.〔问题〕QDoS 加固时收紧的初始窗口在拖上行

v2.7.6 为防 QDoS 把 QUIC 初始接收窗口收紧到 `initStreamReceiveWindow 524288`（512KB）/
`initConnReceiveWindow 1048576`（1MB）。**服务端接收窗口决定的是上行**（客户端发、服务端收）。

测试方法：客户端进独立网络命名空间，160ms RTT，按需加线路限速，每项 5 次中位；工具为 Xray 项目的
`tools/xray_rtt_bench.py`。每换一组窗口重启一次 `hysteria-sbbox`：

| 服务端窗口（初始 / 上限） | 快线路 1000↓/300↑ 上传 5MB | 上传 40MB |
|---|---|---|
| **512KB,1MB / 16MB,64MB（旧）** | **34 / 31** | **109 / 129** |
| 8MB,20MB / 8MB,20MB（hysteria 默认） | 61 / 58 | 161 / 177 |
| **8MB,20MB / 16MB,64MB（新）** | **50 / 63** | **152 / 161** |

（每格为 sing-box 客户端 / Xray 客户端，单位 Mbps）

160ms RTT 下从 512KB 起步爬坡太慢，连 40MB 的长上传都追不回来。慢上行线路（300↓/50↑）下，
5MB 小上传在旧窗口下只有 **3 Mbps**。

### 2.〔为什么放大不削弱 QDoS 防护〕

窗口是 QUIC 层的流控额度。攻击者要按初始窗口灌数据、占服务端内存，前提是**完成 QUIC 握手**。
本节点强制 salamander 混淆，负对照实测：

| 客户端 | 结果 |
|---|---|
| 正确混淆密码 | 546↓ / 194↑ Mbps |
| 错误混淆密码 | 连接建不起来 |
| 不带混淆 | 连接建不起来 |

没有混淆密码的人到不了 QUIC 这一层。以下其余防护全部保留：每源 IP 50/s 的 hashlimit、
`maxIncomingStreams: 512`、`maxIdleTimeout: 30s`。

### 3.〔实测后不采纳〕关闭 `ignoreClientBandwidth`

它决定服务端是否按客户端声明的下行带宽用 Brutal 发送。现有订阅链接本来不声明带宽，
所以这个开关对现有用户**本来就无效**。要回答的问题是放开后有没有收益。线路 300↓/50↑，下行 Mbps：

| | 客户端不声明 | 声明 ↓300 | 声明 ↓1000 |
|---|---|---|---|
| `true`（保持）无丢包 / 1% | 198 / 115 | 189 / 112 | 149 / 127 |
| `false` 无丢包 / 1% | 178 / 108 | 184 / 123 | 174 / 115 |

放开没有可测收益，而保持 `true` 能防止持有密码的客户端靠伪造高下行声明让服务端硬发。**保持 `true`。**

### 4.〔修改方式〕

**线上已改**：`/etc/hysteria/sbbox.yaml` 两处初始窗口改为新值，上限维持 16MB / 64MB，已重启并复测。

| 复测场景 | 改前 | 改后 |
|---|---|---|
| 快线路 5MB 上传 | 34 / 31 | 61 / 55 |
| 快线路 40MB 上传 | 109 / 129 | 141 / 194 |
| 慢线路 5MB 上传 | 3 | 30 |
| 不限速 RTT 0 | — | 645↓406↑，无回退 |

12 节点 `SAMPLES=25 run_test.py` 回归 12/12 PASS。

**脚本**：`hy2_external_sync_secrets`（`sbbox rotate` 时同步外置配置）新写入的 quic 块用新值；
遇到旧版本写入的收紧值会**精确匹配后迁移**，用户自己改过的值原样保留。

**其他外置部署的用户**可手动改：

```bash
sed -i -E 's/^(  initStreamReceiveWindow: )524288$/\18388608/; s/^(  initConnReceiveWindow: )1048576$/\120971520/' /etc/hysteria/sbbox.yaml
systemctl restart hysteria-sbbox
```

### 5.〔测试环境提醒〕限速队列必须有界

模拟用户线路时如果用「tbf 外层 + netem 内层」且内层队列上限很大，tbf 的 `latency` 管不到内层，
实际模拟出的是 1 秒级缓冲：上传期间并行 ping 飙到 ~1000ms，Brutal 把它灌满、BBR 被严重误导，会得出错误结论。
本节数据均来自修正后的有界队列环境（netem `rate` + 按在途包数与约 100ms 排队算出的 `limit`）。

---

## 三十二、v2.7.11 ~ v2.7.13 订阅服务默认开启，本地保留端口调整

### v2.7.11：订阅服务默认开启

- 安装或执行 `sbbox list` 时自动分配端口、生成 token 并拉起 HTTP 订阅服务（`sub=1` 为默认）。
- 需要关闭时用 `sub=0` 或 `sbbox sub off`，会持久化 `sub_disabled` 标记；`sbbox sub [on]` 解除禁用并重新拉起。
- 订阅端口分配会避开已占用端口与 NAT 端口段劫持范围。

### v2.7.12：释放 AnyTLS 端口 28443 的内核本地保留

本机不再启用 AnyTLS 节点（脚本仍支持，`anyp=1` 可重新开启），调优写入的
`net.ipv4.ip_local_reserved_ports` 不再保留 28443，让它回到临时端口池。

```bash
sysctl -n net.ipv4.ip_local_reserved_ports   # 不应再含 28443
```

> 若你**仍在用 AnyTLS**，保留列表里少了 28443 只意味着出向短连接理论上可能临时占用该端口；
> 服务端先起监听时不受影响。确有冲突时可手动把 28443 加回该 sysctl。

### v2.7.13：保留端口 10800-10806 扩到 10800-10809

同机 Xray 项目（v4.9.29）的回归测试新增了两个本地 socks 端口 10807、10808。它们原先不在保留列表里，
实测出现过一次：上一轮测试留下的 TIME-WAIT 连接恰好用 10808 做了本地临时端口，
下一轮测试客户端绑定 10808 失败（`bind: address already in use`），整组 Xray 节点全部超时。
扩到 10809，与 Xray 项目写入的列表保持一致（两边写同一个 sysctl，谁后写谁生效，所以必须相同）。

```bash
sysctl -n net.ipv4.ip_local_reserved_ports   # 应含 10800-10809
```


---

## 三十三、v2.7.14 sing-box AnyTLS 节点复活与全链路参数深度调优

### 1. 变更背景与目标
为兼顾抗审查特征抹除与极致网速，v2.7.14 正式在 sing-box 内核中复活并激活 **AnyTLS** 节点（TCP 端口 `28443`），并针对高带宽、长会话保活、抗探测和 0-RTT/1-RTT 极速握手进行全栈黄金参数调优。

### 2. 核心调优与黄金参数矩阵
- **内核网络栈保留端口保护**：`net.ipv4.ip_local_reserved_ports` 加回 `28443`，与同机 Xray 保持完全一致，杜绝短连接 TIME_WAIT 随机碰撞导致启动绑定失败。
- **服务端 (`anytls-in`) 深度加固**：
  - 监听 TCP `28443`，启用 `tcp_fast_open: true`、`tcp_multi_path: true`、`udp_fragment: true`；
  - 强制 TCP KeepAlive：`disable_tcp_keep_alive: false`，`tcp_keep_alive: 30s`，`tcp_keep_alive_interval: 5s`，有效防止运营商 NAT 网关 60~120 秒静默老化断流；
  - 锁定 TLS 1.3 现代安全规范（`min_version: 1.3`，`alpn: ["h2", "http/1.1"]`，`handshake_timeout: 15s`）；
  - 配置完整 8 级自适应填充方案（`padding_scheme`，0~7 级阶梯范围与客户端 MD5 算法严格对齐，彻底抹除 TLS-in-TLS 特征并免除二次控制帧往返）。
- **客户端 sing-box (`sbox_client.json`) 会话池与长保活**：
  - 启用连接池预热：`min_idle_session: 2`，常驻 2 条热连接，实现首包 0-RTT 秒发；
  - 会话保活：`idle_session_timeout: 10m`，`idle_session_check_interval: 30s`，维持拥塞窗口（cwnd）高位，杜绝断流与网速剧烈波动；
  - 客户端外发严禁配置 `tcp_fast_open: true`（避免客户端内核不支持或报错退出）；
  - 证书公钥指纹绑定：`certificate_public_key_sha256` 硬件级防中间人劫持。
- **客户端 Clash/Mihomo (`clmi.yaml`) 兼容优化**：
  - 注入 `idle-session-timeout: 10m`、`min-idle-session: 2`、`idle-session-check-interval: 30s`；
  - 移除 `tfo: true`，消除部分宽带 Middlebox 丢弃 SYN 数据包引发的超时重传惩罚。

### 3. 客观实测性能验证
在真实内核与隔离沙箱环境下，对该 AnyTLS 节点进行握手与传输性能实测：
- **握手与 RTT 延迟**：首包冷启动握手 ~11.69ms，热连接池复用 6.89ms（平均 9.92ms）；
- **数据吞吐速率**：单流 10MB 压测 0.12s 完成，瞬时吞吐达 **641.90 Mbps**，长连接平稳无波动。

---

## 三十四、v2.7.15 sing-box alpha.7 / Hysteria 2.12.3、vless-reality 客户端去 MPTCP、naive-h2 诊断

测试条件（除特别说明）：netns + netem，RTT 160ms、下行 1% 丢包，每项 3 次（↓60MB / ↑20MB），
sing-box 客户端直接取 `sbox_client.json` 里的出站（只把 server 换成 veth 对端）。单位 Mbps，写作「下行 / 上行」。

### 1.〔升级〕sing-box 1.15.0-alpha.6 → alpha.7

与本机节点相关的是一批修复，没有需要写进服务端配置的新字段，`sb.json` 不改：
HTTP/2 流错误泄漏到嵌套读取器与传输层数据竞争（naive-h2 服务端用的正是这条 H2 路径）、持续错误时读循环空转、
半关闭在连接包装层不传播、连接仍在使用时拨号上下文被取消、缓存文件损坏时崩溃。

替换前用新二进制对 `sb.json` 与 `sbox_client.json` 各跑一次 `sing-box check`（均通过），再 `sbbox up`（自带校验失败 / 起不来回滚）。

### 2.〔升级〕外置 Hysteria 2.12.2 → 2.12.3

主要是 quic-go 升到 v0.62.0；另修复了端口跳跃规则误重定向出站 UDP（本项目默认关闭端口跳跃，不受影响）。
二进制 SHA-256 与官方 `hashes.txt` 一致；Hysteria 没有「只检查配置」的子命令，所以复制一份配置、只把 `listen` 改到本地临时端口，
用新二进制实际起一次确认 `server up and running`，再替换。

### 3.〔修复〕sing-box 客户端 `vless-reality` 去掉 `tcp_multi_path`

**现象**：netns 直连测吞吐时，`vless-reality` 出站 **3/3 建连超时**（`context deadline exceeded`）。

| 客户端出站 | 结果 |
|---|---|
| MPTCP + TFO（v2.7.14） | 建连失败 |
| 只去 MPTCP | **144 / 69** |
| 只去 TFO | 126 / 60 |

sing-box 自己的拨号器在 MPTCP 与 TFO 同开、且两端真的协商成 MPTCP（服务端 `vless-reality-in` 开着 `tcp_multi_path`）时建不起连接。
回归测试一直 PASS 是因为它走公网 IP，NAT 剥掉了 MPTCP 选项、退回普通 TCP；**真实客户端若所在网络不剥 MPTCP 选项就会连不上**。
本版客户端出站保留 TFO、去掉 MPTCP（按上表去 MPTCP 更快）。

- naive-h3 / naive-h2 也两项都开，但走 Cronet 自己的网络栈（不用 sing-box 拨号器），实测正常，不改；
- AnyTLS 客户端只开 MPTCP（sing-box 1.14+ 禁止 AnyTLS 出站开 TFO），不受影响；
- **Mihomo** 模板里 `vless-reality` 同样是 `tfo: true` + `mptcp: true`：v2.7.16 用官方 mihomo v1.19.31 在 netns 直连实测，原样 3/3 通、正常下载，**不受影响**，不改。

### 4.〔诊断〕naive-h2

**下行的大幅波动是测试条件放大的。** 不限速时范围 48–439。服务端采样 `ss -ti`：下载连接的 cwnd 冲到约 4 万个包（约 57MB 在途）、
pacing 3.8 Gbps，客户端通告的接收窗口 173MB，窗口与缓冲都不设限——是 BBR 在没有瓶颈的链路上一路冲高，碰上集中丢包就提前退出启动阶段。
真实线路总有带宽上限，限速后稳定得多（300↓/50↑：174，1000↓/200↑：317）。

**服务端 MPTCP / TFO 对 naive-h2 没有影响**（另起测试实例、同证书同参数只改端口，不动生产节点；每项 5 次）：

| naive-in | 300↓/50↑ | 1000↓/200↑ |
|---|---|---|
| 原样 MPTCP + TFO | 174 / 27 | 317 / 32 |
| 去 MPTCP | 195 / 26 | 315 / 30 |
| 去 MPTCP + TFO | 169 / 28 | 310 / 29 |

范围全部重叠，服务端保持原样。

**上行在 160ms RTT 下被卡在 ~30 Mbps，配置里改不了。** 上行不随线路变化（50↑ 与 200↑ 都是 ~30），范围极窄——典型的流控窗口天花板。
sing-box 的 naive 入站在 TLS 路径上用 Go 标准库的 HTTP/2 服务端，且没有传任何流控参数（`protocol/naive/inbound.go`：`&http2.Server{}`），
每条流的上传接收窗口是 Go 默认的 1MB：1MB ÷ 160ms ≈ 52 Mbps 理论上限，加 1% 丢包实测约 30。sing-box 未暴露该参数，
本项目不自行打补丁编译内核。RTT 越低上限越高（约 1MB ÷ RTT）；**上传量大时用 naive-h3**（QUIC，不受此窗口限制，本轮同条件上行 59–94）。

**测过、不采纳：`tcp_notsent_lowat`**（现为 256KB，临时切换，每档 5 次，限速 300↓/50↑ 与 1000↓/200↑）：

| naive-h2 下行 | 300↓/50↑ | 1000↓/200↑ |
|---|---|---|
| 256KB（现状） | 174（114–205） | 55（47–312） |
| 1MB | 23（19–186） | 343（136–407） |
| 4MB | 171（111–211） | 233（138–327） |

同一档内中位数能从 23 跳到 343，单次之间的波动远大于参数效应；对照的 Reality-Vision 也会偶发跌到 19–33，
说明偶发低值更可能来自测速源一侧（公网段 / 静默限流），而不是这个参数。上传期间 ping 三档一致。维持 256KB。

### 5.〔复核〕TCP 缓冲上限 64MB 维持不变

临时切到 32MB 对比（不持久化，限速 300↓/50↑ + 1% 丢包，下行）：vless-reality **128** vs 32，naive-h2 120 vs 111，AnyTLS 201 vs 202；
不限速时 AnyTLS 382 vs 296。上传期间并行 ping 两组一致，64MB 没有带来额外缓冲膨胀。9-08 那次变慢是 64MB 与 MTU 1500 同时改的，
数据指向 MTU 才是元凶。

### 6.〔升级前后〕同条件对比

| 节点 | alpha.6 / hy 2.12.2 | alpha.7 / hy 2.12.3 |
|---|---|---|
| hysteria2 | 109 / 138 | 114 / 148 |
| naive-h3 | 165 / 63 | 164 / 59 |
| naive-h2 | 148 / 27（9–235） | 102 / 30（48–439，6 次） |
| tuic | 116 / 83 | 119 / 105 |
| vless-reality | 144 / 69（去 MPTCP） | 155 / 62 |
| AnyTLS | 347 / 126 | 323 / 153 |

均在波动范围内，无回归（naive-h2 两边范围都极宽，见上节，不作为升降判断）。

---

## 三十五、v2.7.16 修复：稳定版 sing-box 加载不了订阅、Mihomo 订阅整份加载失败

v2.7.15 之前的测试只用本机的 sing-box（pre-release）跑客户端配置，没有用稳定版、也没有用 mihomo 实测过，三处问题都是在客户端才暴露的。

### 1.〔严重〕sing-box 订阅在稳定版 1.14.x 上整份 FATAL

```
experimental.cache_file.buffer_size: json: unknown field "buffer_size"
```

客户端配置的 `cache_file` 写了 `buffer_size` / `flush_interval`——这是 **1.15 才有的字段**。手机上的 SFI / SFA、v2rayN 的 sing-box 内核多为稳定版，
拿到订阅直接加载失败，**所有节点一起不可用**。客户端开写缓冲本来就没有收益（它是给服务端减少写盘用的），客户端配置去掉这两项；
服务端 `sb.json`（跑 pre-release）保留。

### 2.〔严重〕Mihomo 订阅（`?clash=1` / `clmi.yaml`）整份加载失败

```
proxy 1: cannot parse 'idle-session-check-interval' as int ... "30s"
```

v2.7.14 给 AnyTLS 加的 `idle-session-check-interval: 30s` / `idle-session-timeout: 10m` 照抄了 sing-box 的写法，
但 mihomo 这两个字段是**整数秒**。mihomo 拒绝加载整份配置，同样是所有节点一起不可用。改为 `30` / `600`。

### 3.〔清理〕Mihomo 订阅不再包含 naive

mihomo 没有原生 naive 出站，此前用 `type: http` + TLS 冒充。但 sing-box 的 naive 入站强制要求 NaïveProxy 填充头，
普通 HTTP CONNECT 一律被拒（服务端 `missing naive padding`，客户端 `unexpected EOF`）。用 alpha.6 与 alpha.7 两个测试实例分别验证，
结果相同——**这个节点在 mihomo 里从来不通**，不是本次升级引入的，只会在「自动选择」组里占位。
naive 请用 sing-box 客户端（`sbox_client.json`，走 Cronet）或 NaïveProxy 官方客户端。

### 4.〔验证〕

| 客户端 | 结果 |
|---|---|
| sing-box **1.14.1 稳定版**：`check` + 6 个节点逐个下载 | 全部通过（hysteria2 240、AnyTLS 297、naive-h3 239、naive-h2 248、tuic 281、vless-reality 274；40ms RTT，↓20MB） |
| sing-box 1.15.0-alpha.7：`check` | 通过 |
| mihomo v1.19.31：`-t` + 4 个节点逐个延迟与下载 | 全部通过（hysteria2 271、AnyTLS 1300、tuic 663、reality 489） |

```bash
sing-box check -c sbox_client.json          # 用稳定版跑，不要只用服务端那份 pre-release
mihomo -t -f clmi.yaml                       # 语法；能否连通要实际走一次流量
```

**升级已有安装**：`sbbox list` 重新生成客户端配置，客户端重新拉取订阅。

---

## 三十六、v2.7.17 防火墙放行规则不再顶到最前、fs.suid_dumpable = 0

### 1.〔修复〕`open_port` 把放行规则插到 INPUT 第一条

此前每开一个端口都执行 `iptables -I INPUT 1 ... -j ACCEPT`，新规则排到 `lo` / `RELATED,ESTABLISHED` / `INVALID` 丢弃之前。
v2.7.14 重开 AnyTLS 时，`tcp 28443 ACCEPT` 就成了 INPUT 的第一条（iptables 与 ip6tables 都是）：

- 每个新包都要先比对这一条，已建立连接的快速放行不再是首条命中；
- **更危险的是 UDP 端口**：放行规则会排到它自己的 QDoS hashlimit 丢弃规则**前面**，限速直接失效。本机 44116 当时恰好是另一次整理后的顺序，没中招，但重装时就会。

现在由 `fw_accept_rule` 决定位置：若 INPUT 里有「兜底拒绝」（不带端口 / 状态匹配的 `-j REJECT|DROP`，Oracle 原厂镜像自带
`-j REJECT --reject-with icmp-host-prohibited`）就插在它前面，否则追加到末尾。顺序保持
`lo → ESTABLISHED → INVALID 丢弃 → 限速丢弃 → 端口放行 → 兜底拒绝`。已存在的规则不重复添加。

**验证**：在独立 netns（独立的 iptables）里分别搭「无兜底拒绝」与「末尾 REJECT」两种链，调用两次放行 28443 与 44116——
两种情况下放行都落在限速规则之后、兜底拒绝之前，且不重复。线上把 28443 先追加到末尾、再删掉顶部那条（全程不断），
`netfilter-persistent save` 持久化；AnyTLS 实测 298 / 72 Mbps。

```bash
iptables -S INPUT | sed -n 2,4p     # 应依次是 -i lo / RELATED,ESTABLISHED / INVALID DROP
ip6tables -S INPUT | sed -n 2,4p
```

### 2.〔安全〕调优写入 `fs.suid_dumpable = 0`

代理进程内存里有私钥、UUID 与解密后的流量；内核默认 2（suidsafe）时，setuid / 切换过身份的进程崩溃仍可能转储 core。
设为 0 一律不转储，配合已有的 `kernel.core_pattern = core` 与 `* hard core 0`。线上核实此前为 2（没有任何地方写它）。
同机 Xray 项目在 v4.9.32 同步加入，两个项目写的 sysctl 键值集合保持一致。

---

## 三十七、v2.7.18 不再发送 ICMP 重定向（出口网卡 send_redirects = 0）

**问题**：装了 Docker 的机器 `ip_forward = 1`，转发「同口进、同口出」的包时内核会发 ICMP 重定向，向同网段暴露本机路由信息。
发送侧按「`all` 与网卡**任一**为 1 即生效」：线上 `all` / `default` 是 0，但开机前就已存在的出口网卡 `enp0s6` 是 1（`default` 管不到它），
所以实际一直在发。

**负对照**：宿主网桥 + 两个 netns，A 用 `/32` 路由强制经宿主到 B，在 A 上抓 ICMP type 5——
`all=0`、网桥 `send_redirects=1` 时收到 **2 个**重定向；网桥改为 0 后 **0 个**。

**修复**：调优写入 `all` / `default` / 当前出口网卡三处 `send_redirects = 0`（出口网卡按默认路由识别，VLAN 名里的 `.` 转为 `/`）。
网卡级的键写进 `sysctl.d` 后，systemd 的 udev 规则在网卡出现时会按网卡名重新套用，重启后保持。
接收侧不改：`ip_forward = 1` 时 `accept_redirects` 要求 all 与网卡同时为 1，`all = 0` 已足够。

```bash
sysctl net.ipv4.conf.all.send_redirects net.ipv4.conf.default.send_redirects \
       net.ipv4.conf.$(cat /root/sbbox/nic 2>/dev/null || ip route show default | awk '{print $5; exit}').send_redirects
```

同机 Xray 项目在 v4.9.33 同步加入，两边 sysctl 键值集合保持一致。回归测试 13/13 PASS。

---

## 三十八、v2.7.19 对标 argosbx 深度审查、原生 WARP 出站解锁、网卡 RPS/RFS 绑核与运维安全加固

对标业界知名一键脚本 `yonggekkk/argosbx` 进行全链路源码级深度审查（参见详细对比报告），取其长处（流媒体落地解锁与救砖思维），摒弃其短板与安全隐患（硬编码公共私钥、暴力清空防火墙、无内核网络调优、订阅明文传输、二进制非官方构建），实现针对性升级：

### 1.〔新特性〕原生 Cloudflare WARP 出站与 AI/流媒体智能分流 (`sbbox warp`)
- **根除 argosbx 的公共私钥风控隐患**：argosbx 接口失败时直接回退到硬编码的静态公用私钥，导致海量用户共用同一账号被 Cloudflare 风控。本项目内置调用 Cloudflare 官方 API（动态生成 X25519 密钥对），为当前机器注册**独立唯一的专属 WARP 账户**，专属 IPv6 与保留字段严格保存在 `0600` 权限的 `warp.json`。
- **智能分流设计**：在 `sb.json` 中配置原生 `wireguard` endpoint（tag: `warp-out`）。默认 `ai` 模式仅将 OpenAI/ChatGPT、Claude、Netflix、Disney+、Spotify 等常用 AI 与流媒体域名牵引至 WARP 出站，普通流量依然走原生网卡 Direct 出站，完美保留 BBRv3 / TCP Brutal 的极限带宽与低延迟！
- **管理命令**：
  - `sbbox warp on [ai|all]`：开启 WARP 出站（`ai` 智能分流 / `all` 全量出站）；
  - `sbbox warp off`：一键无缝回滚 Direct 直连；
  - `sbbox warp status`：查看 WARP 账户与当前分流模式；
  - `sbbox warp rotate`：重新申请并轮换全新 WARP 账户。
  - 安装期支持传入环境变量 `warp=ai` 或 `warp=all` 自动激活。

### 2.〔性能〕网卡层软中断 RPS/RFS 多核队列均衡补齐
- **短板修复**：此前仅在 sysctl 中设置了全局 `rps_sock_flow_entries`，若机器未安装过 Xray 项目，网卡队列文件未真正写入 `rps_cpus` 掩码，软中断仍扎堆单核。
- **加固**：在 `apply_nic_tuning` 中自动识别 CPU 核心数，计算多核掩码，遍历网卡各 `rx-*/rps_cpus` 队列写入核心掩码，并将 `rps_flow_cnt = 16384` 均匀分配至各队列，彻底释放 4 核/多核机器的网络软中断吞吐上限。

### 3.〔安全〕防火墙精准卸载治理与 QDoS 放行顺序修复
- **根治暴力 PREROUTING 清空**：`cleandel()` 卸载中此前存在遗留的 `iptables -t nat -F PREROUTING`，会连带清空同机 Docker 及其他代理服务的端口映射规则。现已升级为按端口与特征精准删除 sbbox 规则，杜绝破坏同机环境。
- **修复端口跳跃放行排位**：`apply_hy_hop()` 中此前使用的 `iptables -I INPUT 1` 修正为调用 `fw_accept_rule`，确保放行规则永远排在 `INVALID` 丢弃与 `QDoS hashlimit` 令牌桶限速之后，杜绝高频 UDP 握手穿透限速防护。

### 4.〔运维〕外置 Hysteria2 运维生命周期闭环
- `sbbox res` 重启服务时自动联动重启 `hysteria-sbbox.service`；
- `sbbox doctor` 自检与自动修复完整覆盖外置 Hysteria 2 进程与 UDP 44116 端口监听；
- `sbbox status` 显式标出外置 Hysteria 2.12.3 的运行状态与端口占用。

### 5.〔健壮〕订阅服务高并发与防挂死改造 (`sub_server.py`)
- Python 订阅服务端升级为 `ThreadingHTTPServer`（多线程并发模型），彻底解决单线程阻塞导致客户端拉取订阅超时的隐患。

---

## 三十九、v2.7.20 AnyTLS 连接池生命周期微调、端口保留与自动化测试闭环

基于真实跨洋高延迟（RTT 160ms+）网络实测与最佳实践反馈，在 **v2.7.20** 中对 **AnyTLS** 客户端连接池生命周期、本地端口保留及全链路自动化验证回路完成深度微调与收敛：

### 1.〔客户端〕AnyTLS 连接池生命周期微调（`idle_session_timeout` 10m → 2m）
- **根因分析与权衡**：此前设置的 `10m` 虽然实现了极长周期的 warm cwnd 保活，但在移动端设备（手机/平板）频繁切网（如 Wi-Fi $\leftrightarrow$ 5G）或长时间熄屏待机时，过长的空闲超时易累积失效连接，导致恢复唤醒后的首包探测偶发挂起。
- **参数收敛**：
  - **sing-box 客户端**（`sbox_client.json` 与订阅生成逻辑）：`idle_session_timeout` 调整为 `"2m"`（120秒），保留 `min_idle_session: 2`（预留 2 条活跃连接，秒开网页）与 `idle_session_check_interval: "30s"`；
  - **Mihomo / Clash 客户端**（`clmi.yaml` 与订阅生成逻辑）：`idle-session-timeout` 调整为 `120`（秒），保留 `min-idle-session: 2` 与 `idle-session-check-interval: 30`；
  - 既兼顾了桌面端与网页浏览的 0-RTT 极速复用秒开，又彻底解决了移动端闲置死连接堆积隐患。

### 2.〔网络〕内核本地保留端口扩容（`11801-11806`）与双项目严格对齐
- **端口碰撞防护**：将 `net.ipv4.ip_local_reserved_ports` 中的 sbbox 端口范围由 `11801-11805` 扩展为 `11801-11806`，覆盖 AnyTLS 测试端口，阻断本地短连接随机分配到测试端口造成 `bind: address already in use`。
- **双仓库完全对齐**：同机部署的 Xray 项目在 `06-tuning-lib.sh` 与 `/etc/sysctl.d/99-xray-xhttp.conf` 同步加入，两项目保持 100% sysctl 键值一致性。

### 3.〔测试〕全量测试回路补齐 AnyTLS 节点（14/14 ALL PASS）
- 自动化诊断脚本全面接入 AnyTLS（11806 端口）进行本地 SOCKS5 代理循环探测。
- 现场 7 轮预热采样实测：**中位 3.1ms，p95 14.8ms，抖动仅 1.1x**，全系统 14 个测试节点（1 个直连基线 + 8 个 Xray 节点 + 6 个 sbbox 协议节点）全绿通过！

---

## 四十、v2.7.21 sing-box 订阅导入即可用 TUN + FakeIP 加速首连、Hysteria2 防洪规则不再顶到最前

### 1.〔TUN〕客户端配置自带入站

此前 `sbox_client.json`（`?singbox=1` 订阅）只有出站和路由，**没有任何 `inbounds`**。SFI / SFA / v2rayN 导入后没有入口接管流量，TUN 模式形同虚设。现在自带：

| 入站 | 设置 |
|---|---|
| `tun-in` | `auto_route` + `strict_route`（防 DNS / 路由泄漏），MTU 9000；**不写 `stack`**：1.14 默认即 mixed，1.15+ 默认用新的 Go TUN 栈（写了会报弃用警告，1.17 移除） |
| `mixed-in` | `127.0.0.1:2080`，给不开 TUN 的场景 |

路由补上 TUN 必需的 `hijack-dns`，以及私有地址直连（顺序：sniff → hijack-dns → 私有地址直连 → geosite-cn 直连）。

### 2.〔握手〕FakeIP 省掉新连接前的远程 DNS 往返

TUN 下非国内域名的 A / AAAA 查询直接返回 FakeIP（`198.18.0.0/15`、`fc00::/18`），连接按域名经代理发出，
**不必先经代理做一次远程 DNS、再建连**，每条新连接少一轮往返。国内域名仍走本地 DNS、直连。
（`cache_file.store_fakeip` 早已开着，只是一直没配 fakeip 服务器。）

### 3.〔安全〕Hysteria2 防洪规则插入位置

`apply_hy_qdos` 此前把「该端口的 ESTABLISHED / INVALID / 限速」三条固定插到 INPUT 第 1–3 位，排到 `lo` 之前；
而全局 ESTABLISHED / INVALID 本来就有，这两条是多余的（9-25 重分配 hy2 端口时就这样顶到了最前）。
现在只保留限速丢弃规则，插在全局 INVALID 丢弃之后（仍在端口放行之前）；全局规则缺失时才补、补在 `lo` 之后；并清掉旧版本留下的两条端口专属规则。

### 4.〔验证〕

- 稳定版 sing-box **1.14.1** 与 1.15.0-alpha.7 对新配置 `check` 均通过（无弃用警告）；
- 在独立 netns 里用 1.14.1 真实起 TUN（`auto_route` 只作用于该 netns，不影响宿主 SSH）：
  国外域名解析为 FakeIP（`198.18.0.2`）、国内域名为真实地址；经 TUN 访问返回 204，连接复用后首字节约 4ms；经 TUN 下载 30MB 约 278 Mbps（走公网回环，仅作连通参考）；
- 防火墙函数在独立 netns 里分别从「旧版残留」与「空链」两种状态演练：顺序均为 `lo → ESTABLISHED → INVALID → 限速 → 放行`，重复调用不重复添加。

```bash
sing-box check -c sbox_client.json    # 用稳定版跑
iptables -S INPUT | sed -n 2,6p
```

**升级已有安装**：`sbbox list` 重新生成客户端配置，客户端重新拉取 `?singbox=1` 订阅。

---

## 四十一、v2.7.22 强化 Reality 协议下线生命周期与防火墙规则自愈，默认不安装 Reality

针对同机共存架构下（Xray 已承载全套 Reality 矩阵）对轻量纯净度的需求，v2.7.22 完善了 **VLESS-Reality** 兼容节点的生命周期下线与防火墙自愈机制：

### 1. 架构明确：四大核心主力梯队，默认不安装 Reality
- 默认一键安装与维护聚焦四大核心主力（**Hysteria2** / **AnyTLS** / **NaiveProxy** / **TUIC**），Reality 保持纯可选兼容模式（仅显式传 `reap=1` 开启）；
- 若未启用 Reality（默认行为）或传 `reap=0`，安装器与配置重载阶段自动下线 Reality，杜绝后台占用端口。

### 2. 状态文件与防火墙规则自愈清理闭环
- **新增 `close_port()` 机制**：协议停用或重构时，精准清理 `iptables` / `ip6tables` 中残留的放行规则，并通过 `netfilter-persistent save` 永久固化，防止孤儿端口暴露在公网扫描风险下；
- **状态持久化防踩踏修复**：修复了 `save_state` 与 `cmd_port` 在未启用协议时未清除对应端口文件（如 `port_rea`）和标记文件（如 `proto_rea`）的问题，杜绝后续执行 `sbbox port` 或 `sbbox doctor` 时意外复活已下线协议；
- **秘钥安全清理**：下线时安全回收不再使用的 `reality_priv`、`reality_pub`、`reality_sid` 等临时凭据文件；
- **CI 全绿通过**：同步更新 GitHub Actions 测试断言（兼容 AnyTLS TLS 1.2 向下兼容配置），自动化流水线全部 PASS。

---

## 四十二、免责声明

本项目仅供网络技术研究与学习交流使用。使用者须自行遵守所在国家/地区的法律法规，因使用本脚本产生的一切后果由使用者自行承担。


