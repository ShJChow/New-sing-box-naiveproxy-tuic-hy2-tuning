# sing-box-naiveproxy — Sing-box 五协议安全加固代理脚本

[![validate](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml)

基于架构 **sing-box 单内核**部署脚本，只保留五个协议：

| 协议 | 用途 | 传输 |
|------|------|------|
| **Tuic** | 低延迟 UDP 加速 | QUIC (HTTP/3) |
| **Hysteria2** | 高吞吐 / 抗丢包 | QUIC (HTTP/3) |
| **Naiveproxy H2** | 高隐匿性 HTTP/2 代理 | HTTP/2 |
| **Naiveproxy H3** | 高隐匿性 HTTP/3 代理 | HTTP/3 (QUIC) |
| **Reality (VLESS)** | 零证书抗检测 | TCP + Vision 流控 |

集成了：
- **内核级流控调优**（移植自 [`ShJChow/Xray-core-xhttp-cdn-tuned`](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned) 的 `xh tuning on`）：BBR、内存分档缓冲区、TFO、文件句柄等，安装期自动开启，可一键回滚
- **acme.sh 证书申请**：Naiveproxy / Hysteria2 / Tuic 使用真实 TLS 证书 ：若证书申请失败，可使用acme：
- bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)

---

## 安全设计

| 加固项 | argosbx 原值 | sbbox 新值 |
|--------|-------------|-----------|
| TLS 证书校验 | `insecure=1`（自签绕过） | `insecure=0`（强制验证） |
| Naiveproxy 证书 | 允许自签回退 | **强制 acme 真实证书** |
| Hysteria2 伪装 | 无 | `masquerade` 反代真实站点（默认 www.bing.com），未认证探测拿到真实页面 |
| Hysteria2 带宽声明 | 信任客户端 | `ignore_client_bandwidth: true`（服务端主导） |
| Hysteria2 SNI | 固定 `www.bing.com` | 用户自定义（证书域名） |
| Reality TLS 版本 | 未指定 | 强制 `min_version: "1.3"` |
| Reality 客户端指纹 | 部分有 | 强制 uTLS `chrome` |
| Tuic 0-RTT | 未显式关闭 | `zero_rtt_handshake: false`（防重放） |
| 文件句柄 | 系统默认 | 1048576（systemd drop-in） |
| 内核调优 | 未配置 | 安装期自动应用，`sbbox tune off` 可回滚 |
| 协议凭据 | 全部复用同一 uuid | **每协议独立随机密钥**（v1.8.0），任一泄露不牵连其他 |
| Hysteria2 obfs 密码 | 同认证密码 | 独立随机值，混淆层与认证层不共用秘密 |
| 出站 DNS | 跟随系统（明文 UDP，VPS 侧可见全部查询） | **DoT 加密**（1.1.1.1 / 9.9.9.9） |
| 内网访问 | 未限制，可拿服务器当跳板打内网与云元数据接口 | `ip_is_private` 一律拒绝 |
| 垃圾邮件滥用 | 未限制 | 默认阻断出站 25/465/587 与 SMB 端口（`blkport=0` 关闭） |
| 服务端日志 | `warn`，失败连接的目标域名落盘 | 默认 `error`；`sblevel=off` 完全不落盘 |

> **传输层混淆说明**：sing-box 不支持 xray 的 xpadding / VLESS Encryption / ECH 专有扩展。本脚本使用 sing-box 原生等价方案：Reality 协议本身即抗检测混淆、Naiveproxy HTTP/2 padding、Hysteria2 QUIC + 跳跃端口、uTLS 指纹。

---

## 快速开始

### 前置条件

- VPS：Ubuntu / Debian / CentOS / Alpine（amd64 或 arm64）
- **推荐 root 权限**（非 root 也可用，走 crontab 自启）
- 如需 Naiveproxy：需要域名并解析到 VPS，`alns=1` 自动申请证书

### 一键安装

```bash
# 只装 Tuic + Hysteria2 + Reality（无域名，自签证书 + SHA256 固定指纹）
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 vlp=1

# 装全部五个协议（需域名，自动申请 Let's Encrypt 证书）
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 nvp=1 vlp=1 alns=1 ym=your.domain.com
```

> `alns=1` 时 acme.sh 走 standalone 模式，需要 **80 端口空闲**、域名 A 记录已解析到本机。
> 若未提供 `ym=域名`，脚本会**交互提示输入**（不写入命令行历史）。

---

## 环境变量参考

| 变量 | 默认 | 说明 |
|------|------|------|
| `tup` / `hyp` / `nvp` / `vlp` | 空 | 协议开关，非空即启用 |
| `alns` | 空 | 启用 acme 证书申请（`alns=1`） |
| `ym` | 空 | acme 证书域名（启用 alns 时必需） |
| `ym_vl_re` | `www.apple.com` | Reality 回落目标域名 |
| `hyjpt` | 空 | Hysteria2 跳跃端口，如 `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1（默认开启）** | Hysteria2 salamander 混淆，抗协议识别；关闭用 `hyobfs=0` |
| `hyobfs_pw` | 独立随机 | Hysteria2 混淆密码（与认证密码分离） |
| `hymask` | `https://www.bing.com` | Hysteria2 伪装：反代真实站点抗主动探测；静态 404 用 `hymask=none` |
| `sblevel` | `error` | 服务端日志级别，`off` 完全不落盘（日志会记录访问过的域名） |
| `blkport` | **1（默认开启）** | 阻断出站 25/465/587/SMB 端口，防凭据外泄后被拿去发垃圾邮件；关闭用 `blkport=0` |
| `hyup` / `hydown` | 空 | Hysteria2 上/下行 Mbps，**两个都设**才启用 Brutal 拥塞控制 |
| `sub` | 空 | 启用 v2rayN 订阅服务（`sub=1`） |
| `subport` | 随机 | 订阅服务端口 |
| `subid` | 独立随机 | 订阅令牌（URL 路径，相当于密码） |
| `sub_nonaive` | 空 | 剔除 Naiveproxy 节点（客户端不支持 naive+ 链接时用 `sub_nonaive=1`） |
| `uuid` | 自动生成 | 自定义 UUID（VLESS/Tuic 用；各协议密码自 v1.8.0 起独立随机，不再复用 UUID） |
| `port_tu` / `port_hy2` / `port_nv` / `port_vl` | 随机 | 指定固定端口 |
| `name` | 空 | 节点名称前缀 |
| `noautoup` | 空 | 关闭每周内核自动升级（`noautoup=1`） |
| `sbrel` | **`pre`（默认）** | 内核版本通道：默认取最新 release（含 beta/rc）；只要正式版用 `sbrel=stable` |
| `tuicuos` | **1（默认开启）** | Tuic UDP over QUIC 流；退回原生 UDP 用 `tuicuos=0` |

---

## 协议参数调优

默认配置已选取「安全且稳妥」的一组参数：

| 协议 | 默认参数 | 理由 |
|------|---------|------|
| Tuic | `congestion_control: bbr`、`zero_rtt_handshake: false`、`auth_timeout: 3s`、`heartbeat: 10s` | 关 0-RTT 牺牲 1 个 RTT 换取抗重放；心跳保活 NAT 映射 |
| Hysteria2 | **`obfs: salamander`（默认开启）**、`ignore_client_bandwidth: true`（客户端统一走 BBR）、`masquerade` 反代真实站点 | 混淆抗协议识别；BBR 稳定公平，无需预知带宽；反代伪装让主动探测拿到真实页面 |
| Naiveproxy | `tcp_fast_open: true`、`min_version: "1.3"`、强制真实证书 | TFO 省 1 个 RTT；仅 TLS 1.3 可用，杜绝降级 |
| Reality | `tcp_fast_open: true`、TLS 1.3、uTLS chrome 指纹 | Vision 流控自带 splice 高性能路径 |

### 客户端嗅探（默认开启）

客户端路由首条为 `{"action": "sniff", "timeout": "300ms"}`。

没有它，`geosite-cn` 直连规则**按域名匹配**，而以纯 IP 抵达的连接
（TUN/透明代理常见）根本匹配不上——国内直连规则等于半失效。
`inbound.sniff` 已在 sing-box 1.11+ 废弃，现统一用路由动作。

### Tuic UDP 中继模式

| 模式 | 配置 | 特点 |
|---|---|---|
| **UDP over QUIC 流**（默认） | `udp_over_stream: true` | 可靠有序，适合中继 QUIC 类流式流量 |
| 原生 UDP | `tuicuos=0` → `udp_relay_mode: native` | 保留 UDP 语义，不保证可靠 |

> ⚠️ 两者**互斥**，脚本只会生成其中之一（CI 已断言）。
> sing-box 官方文档对 `udp_over_stream` 的原话是：该模式
> **「在正常 UDP 代理场景下没有正面效果」**，只应用于中继流式 UDP 流量。
> 对普通 UDP 会引入队头阻塞。若你的 UDP 以游戏、实时音视频为主，
> 建议用 `tuicuos=0` 退回原生模式。

### 系统层：QUIC 相关调优（安装期自动生效）

| 项 | 做法 | 为什么需要 |
|---|---|---|
| `fq` 队列规则 | `tc qdisc replace dev <网卡> root fq` | QUIC 强依赖 pacing。`net.core.default_qdisc=fq` **只影响此后新建的 qdisc**，已存在的网卡不会自动切换，必须显式设置 |
| UDP GRO/GSO | `ethtool -K <网卡> gro/gso/tso on` | 让内核合并/分片 UDP 段，高速 QUIC 下明显降低 CPU |
| UDP 缓冲区 | 大内存档 `rmem_max/wmem_max` 提到 **128MB** | QUIC 的 UDP socket 不像 TCP 自动扩缩，quic-go 直接按 `rmem_max` 申请，上限偏小会打印 `failed to sufficiently increase receive buffer size` 并压低吞吐 |

`sbbox tune show` 会显示当前网卡的队列规则与卸载状态，`sbbox tune off` 把队列规则交还系统默认。

> 容器 / OpenVZ 等受限环境下 `tc` 与 `ethtool` 可能无权限，脚本会告警并跳过，不影响其余调优。

### 进一步提速：Hysteria2 Brutal 拥塞控制

跨境高丢包链路上 Brutal 的吞吐通常显著高于 BBR，但需要**填写接近真实的带宽**：

```bash
hyup=200 hydown=1000 sbbox list   # 上行 200Mbps / 下行 1000Mbps
```

> ⚠️ 两个值必须**同时设置**才生效。官方文档明确二者互斥：一旦设定带宽上限，
> 就不再允许客户端使用 BBR。**填错会比 BBR 更慢**，且 Brutal 会激进抢占带宽、
> 流量特征更明显。不确定自己带宽时，保持默认的 BBR 更稳妥。

### 默认已启用：Hysteria2 salamander 混淆

打乱 QUIC 握手特征，显著提高主动探测与协议识别的难度。**自 v1.2.0 起默认开启**，
混淆密码默认取 uuid：

```bash
hyobfs_pw=你的密码 sbbox list   # 自定义混淆密码
hyobfs=0 sbbox list             # 关闭混淆
```

> 服务端开启后**客户端必须同步配置**，否则握手失败。脚本已自动把 obfs 参数
> 写入分享链接、sing-box 客户端配置与 Clash/Mihomo 配置，
> **客户端更新一次订阅即可**，无需手工填写。代价是轻微 CPU 开销。
>
> ⚠️ 从旧版本升级后，务必让所有客户端**重新拉取订阅**，否则旧节点会连不上。

混淆 + Brutal 同时使用：

```bash
hyup=600 hydown=600 sbbox list
```

---

## 管理命令

安装完成后（重连 SSH 或 `source ~/.bashrc`），使用 `sbbox` 命令：

| 命令 | 功能 |
|------|------|
| `sbbox list` | 显示全部节点链接 + 客户端配置 |
| `sbbox status` | 服务运行状态 + 流控状态 |
| `sbbox res` | 重启 sing-box |
| `sbbox tune show` | 查看内核流控参数 |
| `sbbox tune off` | 回滚全部内核调优 |
| `sbbox sub` | 显示订阅地址 |
| `sbbox sub off` | 关闭订阅服务 |
| `sbbox cert status` | 查看证书有效期 |
| `sbbox cert renew` | 续期证书并重启 |
| `sbbox up` | 升级 sing-box 内核（默认 pre 通道，取最新 release；失败自动回滚） |
| `sbbox log [N]` | 查看最近 N 行日志（默认 20） |
| `sbbox rotate` | 轮换全部协议密码、混淆密码与订阅令牌（端口/UUID/证书不变，客户端需重新导入） |
| `sbbox doctor` | 自检并尝试修复 |
| `sbbox del` | 完全卸载 |

---

## 内核版本管理

安装与 `sbbox up` 都从 **SagerNet 官方 release 拉取内核**，
仅在官方源不可达时才回退到镜像源（版本可能滞后，会有告警）。

**默认通道是 `pre`**：取仓库里最新的一个 release，不论它是否标记为预发布。
正式版本身也在这个列表里，所以「pre」的实际含义是「永远最新」，
而不是「只要 beta」——正式版发布当天它拿到的就是正式版。

只想跟正式版就用 `sbrel=stable`，GitHub 的 `releases/latest` 端点不返回预发布版：

```bash
# 安装时指定通道（安装是无子命令形式，协议变量必须带上）
tup=1 hyp=1 nvp=1 vlp=1 bash sbbox.sh                # 默认 pre 通道
sbrel=stable tup=1 hyp=1 nvp=1 vlp=1 bash sbbox.sh   # 只跟正式版

# 安装后
sbbox up                  # 按首装时记住的通道升级；已是最新则跳过
sbrel=stable sbbox up     # 临时切到正式版通道升级一次
sbrel=pre sbbox up        # 临时切到 pre 通道升级一次
```

通道选择会写进 `$SB_HOME/sbrel` 持久化，每周的 cron 自动升级遵守它。
优先级是 **本次显式指定 > 首装时记住的通道 > 默认值**。

> ⚠️ 从旧版本升级上来的用户请注意：旧版默认跟正式版，且只有显式传过 `sbrel` 才会落盘。
> 没有那个文件的话，下次升级会按新默认走 pre 通道。要保持正式版，跑一次
> `sbrel=stable sbbox up` 把选择固化下来。

升级流程带回滚保护：**备份旧内核 → 下载新版 → 用新内核校验现有配置 → 重启**，
任一步失败自动还原旧内核并重启。新版本偶尔会收紧配置 schema
（本项目就被 sing-box 1.12 的 DNS 格式变更打过），没有回滚会让所有节点掉线。

默认启用**每周日自动升级**（含上述回滚保护，带随机延迟避免整点集中请求）。
关闭方式：安装时加 `noautoup=1`，或 `crontab -e` 删掉含 `sbbox up` 的行。

---

## v2rayN 订阅

安装时加 `sub=1`，脚本会生成 base64 订阅并在本机启动 HTTP 服务：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 vlp=1 sub=1
```

安装结束会打印订阅地址，形如 `http://<IP>:<端口>/<令牌>`。
在 v2rayN 中：**订阅 → 订阅设置 → 添加**，把该地址填入 URL，然后「更新订阅」。

随时用 `sbbox sub` 再次查看地址，`sbbox sub off` 关闭服务。

> ⚠️ **安全提示**：订阅经**明文 HTTP** 提供，URL 里的令牌就是唯一凭据。
> 请勿分享该地址；不使用时执行 `sbbox sub off`。若需长期开放，建议改用
> `subport=` 指定端口并在防火墙上限制来源 IP。
>
> **默认订阅包含全部节点（含 Naiveproxy H2/H3）**。
> Naiveproxy 会生成**两套链接**，因为各客户端认的 scheme 不同：
>
> | 链接 scheme | 节点名后缀 | 适用客户端 |
> |---|---|---|
> | `naive+https://` / `naive+quic://` | `naive-h2` / `naive-h3` | v2rayN、NekoBox |
> | `http2://` / `http3://` | `naive-h2-rocket` / `naive-h3-rocket` | Shadowrocket |
>
> 两套都在订阅里，客户端各取所需——**用不了的那套忽略即可**。
> 完全不想要 Naiveproxy 可用 `sub_nonaive=1 sbbox list` 重新生成（两套一起剔除）。
>
> **sing-box 客户端也能用 Naiveproxy**：`~/sbbox/sbox_client.json` 已包含 naive 出站。
> 前提是客户端的 `libcronet.so` 与 sing-box 二进制**放在同一目录**——官方 release
> tarball 本来就一并提供，解压时别只取二进制。自行编译的精简内核若缺该库，
> 会以 `cronet: library not found` 启动失败，此时删掉这条出站即可。

---

## 生成的文件

| 文件 | 用途 |
|------|------|
| `~/sbbox/sb.json` | sing-box 服务端配置 |
| `~/sbbox/sbox_client.json` | sing-box 客户端聚合配置（可直接导入 sing-box） |
| `~/sbbox/clmi.yaml` | Clash / Mihomo 客户端配置 |
| `~/sbbox/nodes.txt` | 纯文本节点分享链接 |
| `~/sbbox/cert/` | acme 证书（fullchain.cer + private.key） |
| `~/sbbox/sec/` | 各协议独立密钥（0600，`sbbox rotate` 轮换） |
| `/etc/sysctl.d/99-sbbox.conf` | 内核流控调优参数（`sbbox tune off` 删除） |
| `/etc/systemd/system/sbbox.service` | systemd 服务 |

---

## 常见问题

**Naiveproxy 报错"需要有效 TLS 证书"**
→ Naiveproxy 基于 HTTPS，必须有真实证书。安装时加 `alns=1 ym=你的域名`。

**Hysteria2 / Tuic 节点连不上**
→ 确认客户端已正确配置 `sni`。无域名时使用自签证书，客户端必须固定 `pinSHA256`（Hysteria2）或设置 `insecure=1` 并校验指纹（Tuic）。

**证书申请失败**
→ 确认：域名 A 记录指向本机 IP、80 端口空闲、未使用 CF 橙色云朵代理。

**非 root 环境**
→ 脚本自动走 crontab + nohup 自启；管理命令同样可用。

---

## 致谢

- [yonggekkk/argosbx](https://github.com/yonggekkk/argosbx) — 原脚本架构与协议配置参考
- [ShJChow/Xray-core-xhttp-cdn-tuned](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned) — 内核级流控调优（`xh tuning`）实现移植
- [sagernet/sing-box](https://github.com/SagerNet/sing-box) — 代理内核
