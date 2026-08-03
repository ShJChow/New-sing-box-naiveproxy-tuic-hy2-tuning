# sing-box-naiveproxy — Sing-box 五协议安全加固代理脚本

[![validate](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml)

基于 [`yonggekkk/argosbx`](https://github.com/yonggekkk/argosbx) 架构精简而成的 **sing-box 单内核**部署脚本，只保留五个协议：

| 协议 | 用途 | 传输 |
|------|------|------|
| **Tuic** | 低延迟 UDP 加速 | QUIC (HTTP/3) |
| **Hysteria2** | 高吞吐 / 抗丢包 | QUIC (HTTP/3) |
| **Naiveproxy H2** | 高隐匿性 HTTP/2 代理 | HTTP/2 |
| **Naiveproxy H3** | 高隐匿性 HTTP/3 代理 | HTTP/3 (QUIC) |
| **Reality (VLESS)** | 零证书抗检测 | TCP + Vision 流控 |

集成了：
- **内核级流控调优**（移植自 [`ShJChow/Xray-core-xhttp-cdn-tuned`](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned) 的 `xh tuning on`）：BBR、内存分档缓冲区、TFO、文件句柄等，安装期自动开启，可一键回滚
- **acme.sh 证书申请**：Naiveproxy / Hysteria2 / Tuic 使用真实 TLS 证书

---

## 安全设计

| 加固项 | argosbx 原值 | sbbox 新值 |
|--------|-------------|-----------|
| TLS 证书校验 | `insecure=1`（自签绕过） | `insecure=0`（强制验证） |
| Naiveproxy 证书 | 允许自签回退 | **强制 acme 真实证书** |
| Hysteria2 伪装 | 无 | `masquerade` 返回 404 页面 |
| Hysteria2 带宽声明 | 信任客户端 | `ignore_client_bandwidth: true`（服务端主导） |
| Hysteria2 SNI | 固定 `www.bing.com` | 用户自定义（证书域名） |
| Reality TLS 版本 | 未指定 | 强制 `min_version: "1.3"` |
| Reality 客户端指纹 | 部分有 | 强制 uTLS `chrome` |
| Tuic 0-RTT | 未显式关闭 | `zero_rtt_handshake: false`（防重放） |
| 文件句柄 | 系统默认 | 1048576（systemd drop-in） |
| 内核调优 | 未配置 | 安装期自动应用，`sbbox tune off` 可回滚 |

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
| `ym_vl_re` | `apple.com` | Reality 回落目标域名 |
| `hyjpt` | 空 | Hysteria2 跳跃端口，如 `hyjpt="20000 20001 20002"` |
| `hyobfs` | 空 | Hysteria2 salamander 混淆（`hyobfs=1`），抗协议识别 |
| `hyobfs_pw` | 同 uuid | 混淆密码 |
| `hyup` / `hydown` | 空 | Hysteria2 上/下行 Mbps，**两个都设**才启用 Brutal 拥塞控制 |
| `sub` | 空 | 启用 v2rayN 订阅服务（`sub=1`） |
| `subport` | 随机 | 订阅服务端口 |
| `subid` | 同 uuid | 订阅令牌（URL 路径，相当于密码） |
| `sub_nonaive` | 空 | 剔除 Naiveproxy 节点（客户端不支持 naive+ 链接时用 `sub_nonaive=1`） |
| `uuid` | 自动生成 | 自定义密码 / UUID |
| `port_tu` / `port_hy2` / `port_nv` / `port_vl` | 随机 | 指定固定端口 |
| `name` | 空 | 节点名称前缀 |

---

## 协议参数调优

默认配置已选取「安全且稳妥」的一组参数：

| 协议 | 默认参数 | 理由 |
|------|---------|------|
| Tuic | `congestion_control: bbr`、`zero_rtt_handshake: false`、`auth_timeout: 3s` | 关 0-RTT 牺牲 1 个 RTT 换取抗重放攻击 |
| Hysteria2 | `ignore_client_bandwidth: true`（客户端统一走 BBR）、`masquerade` 404 伪装 | BBR 稳定公平，无需预知带宽 |
| Naiveproxy | `tcp_fast_open: true`、强制真实证书 | TFO 省 1 个 RTT，与内核 `tcp_fastopen=3` 配套 |
| Reality | `tcp_fast_open: true`、TLS 1.3、uTLS chrome 指纹 | Vision 流控自带 splice 高性能路径 |

### 进一步提速：Hysteria2 Brutal 拥塞控制

跨境高丢包链路上 Brutal 的吞吐通常显著高于 BBR，但需要**填写接近真实的带宽**：

```bash
hyup=200 hydown=1000 sbbox list   # 上行 200Mbps / 下行 1000Mbps
```

> ⚠️ 两个值必须**同时设置**才生效。官方文档明确二者互斥：一旦设定带宽上限，
> 就不再允许客户端使用 BBR。**填错会比 BBR 更慢**，且 Brutal 会激进抢占带宽、
> 流量特征更明显。不确定自己带宽时，保持默认的 BBR 更稳妥。

### 进一步加固：Hysteria2 salamander 混淆

打乱 QUIC 握手特征，显著提高主动探测与协议识别的难度：

```bash
hyobfs=1 sbbox list                        # 混淆密码默认用 uuid
hyobfs=1 hyobfs_pw=你的密码 sbbox list      # 自定义密码
```

> 服务端开启后**客户端必须同步配置**，否则握手失败。脚本已自动把 obfs 参数
> 写入分享链接、sing-box 客户端配置与 Clash/Mihomo 配置，客户端更新订阅即可。
> 代价是轻微 CPU 开销。

两项可同时开启：

```bash
hyobfs=1 hyup=200 hydown=1000 sbbox list
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
| `sbbox up` | 更新 sing-box 内核 |
| `sbbox log [N]` | 查看最近 N 行日志（默认 20） |
| `sbbox del` | 完全卸载 |

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

---

## 生成的文件

| 文件 | 用途 |
|------|------|
| `~/sbbox/sb.json` | sing-box 服务端配置 |
| `~/sbbox/sbox_client.json` | sing-box 客户端聚合配置（可直接导入 sing-box） |
| `~/sbbox/clmi.yaml` | Clash / Mihomo 客户端配置 |
| `~/sbbox/nodes.txt` | 纯文本节点分享链接 |
| `~/sbbox/cert/` | acme 证书（fullchain.cer + private.key） |
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
