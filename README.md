# sing-box-naiveproxy — Sing-box 三协议安全加固代理脚本

[![validate](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml)

基于 **sing-box 单内核** 部署脚本，保留三个主流协议：

| 协议 | 用途 | 传输 | 证书 |
|------|------|------|------|
| **Tuic** | 低延迟 UDP 加速 | QUIC (HTTP/3) | 真实证书 / 自签+指纹固定 |
| **Hysteria2** | 高吞吐 / 抗丢包 | QUIC (HTTP/3) | 真实证书 / 自签+指纹固定 |
| **Naiveproxy H3** | 高隐匿性 HTTP/3 代理（默认） | HTTP/3 (QUIC) | **强制真实证书** |
| **Naiveproxy H2** | 高隐匿性 HTTP/2 代理（兼容） | HTTP/2 | **强制真实证书** |

> 默认使用 **官方正式版内核（stable）**，默认开启 **QUIC 与 BBR 拥塞控制**，入站最低兼容 **TLS 1.2 / HTTP 1.1**。

集成了：
- **内核级流控调优**（移植自 [`ShJChow/Xray-core-xhttp-cdn-tuned`](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned) 的 `xh tuning on`）：BBR、内存分档缓冲区、TFO、文件句柄等，安装期自动开启，可一键回滚
- **acme.sh 证书申请**：Naiveproxy / Hysteria2 / Tuic 使用真实 TLS 证书

---

## 安全与性能设计

| 加固项 | 说明 |
|--------|------|
| TLS 证书校验 | `insecure=0`（强制校验） |
| Naiveproxy 证书 | **强制 acme 真实证书** |
| 最低协议兼容 | **TLS 1.2**（`min_version: "1.2"`）+ ALPN `["h3", "h2", "http/1.1"]`，兼顾旧客户端与极速新协议 |
| Hysteria2 伪装 | `masquerade` 反代真实站点（默认 www.bing.com），未认证探测拿到真实页面 |
| Hysteria2 拥塞控制 | `ignore_client_bandwidth: true` + `bbr_profile: standard`（服务端主导，稳定公平） |
| Hysteria2 混淆 | `obfs: salamander`（默认开启），混淆密码独立随机 |
| Tuic 极速握手 | `zero_rtt_handshake: true` + `congestion_control: bbr` |
| 文件句柄 | 1048576（写进主 unit，不依赖 drop-in） |
| 协议凭据 | **每协议独立随机密钥**，任一泄露不牵连其他 |
| 出站 DNS | **DoT 加密**（1.1.1.1 / 9.9.9.9） |
| 内网访问 | `ip_is_private` 一律拒绝，防止内网与云元数据接口被穿透 |
| 垃圾邮件滥用 | 默认阻断出站 25/465/587 与 SMB 端口（`blkport=0` 关闭） |
| 服务端日志 | 默认 `error`；`sblevel=off` 完全不落盘 |

---

## 快速开始

### 前置条件

- VPS：Ubuntu / Debian / CentOS / Alpine（amd64 或 arm64）
- **推荐 root 权限**（非 root 也可用，走 crontab 自启）
- 如需 Naiveproxy：需要域名并解析到 VPS，`alns=1` 自动申请证书

### 一键安装

```bash
# Tuic + Hysteria2（无域名，自签证书 + SHA256 固定指纹）
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1

# 装全部三协议（需域名，自动申请 Let's Encrypt 证书，默认正式版 + 默认开启 QUIC）
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 nvp=1 alns=1 ym=your.domain.com
```

> `alns=1` 时 acme.sh 走 standalone 模式，需要 **80 端口空闲**、域名 A 记录已解析到本机。
> 若未提供 `ym=域名`，脚本会**交互提示输入**（不写入命令行历史）。

---

## 环境变量参考

| 变量 | 默认 | 说明 |
|------|------|------|
| `tup` / `hyp` / `nvp` | 空 | 协议开关，非空即启用（至少显式指定一个才会进入安装流程）|
| `alns` | 空 | 启用 acme 证书申请（`alns=1`） |
| `ym` | 空 | acme 证书域名（启用 alns 时必需） |
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
| `uuid` | 自动生成 | 自定义 UUID（Tuic 用；各协议密码独立随机，不再复用 UUID） |
| `port_tu` / `port_hy2` / `port_nv` | 随机 | 指定固定端口 |
| `name` | 空 | 节点名称前缀 |
| `noautoup` | 空 | 关闭每周内核自动升级（`noautoup=1`） |
| `sbrel` | **`stable`（默认）** | 内核版本通道：默认只取官方最新正式版（`stable`）；跟踪 beta/rc 用 `sbrel=pre` |
| `tuicuos` | **1（默认开启）** | Tuic UDP over QUIC 流；退回原生 UDP 用 `tuicuos=0` |

---

## 管理命令

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
| `sbbox cert status` | 查看证书有效期 |
| `sbbox cert renew` | 续期证书并重启 |
| `sbbox up` | 升级 sing-box 内核（默认 stable 官方正式版；失败自动回滚） |
| `sbbox log [N]` | 查看最近 N 行日志（默认 20） |
| `sbbox rotate` | 轮换全部协议密码、混淆密码与订阅令牌（端口/UUID/证书不变，客户端需重新导入） |
| `sbbox doctor` | 自检并尝试修复 |
| `sbbox del` | 完全卸载 |

---

## 内核版本管理

安装与 `sbbox up` 默认从 **SagerNet 官方最新正式版（releases/latest）拉取内核**。

- **默认通道是 `stable`**：只跟踪稳定正式版。
- 若想体验最新测试特性，可用 `sbrel=pre` 跟踪 pre-release（beta/rc）：

```bash
sbrel=stable sbbox up     # 升级/切换到最新正式版（默认）
sbrel=pre sbbox up        # 升级/切换到 pre 通道
```

---

## v2rayN 订阅与客户端配置

安装时加 `sub=1`，脚本会生成 base64 订阅并在本机启动 HTTP 静态托管服务。

Naiveproxy 节点按 QUIC (H3) 优先排列：
- `naive+quic://` / `http3://`：QUIC (H3) 极速节点（默认推荐）
- `naive+https://` / `http2://`：HTTP/2 兼容节点（TCP 回退备用）

客户端聚合配置文件位于：
- sing-box 客户端：`~/sbbox/sbox_client.json`
- Clash / Mihomo：`~/sbbox/clmi.yaml`

---

## 免责声明

本项目仅供网络技术研究与学习交流使用。使用者须自行遵守所在国家/地区的法律法规，因使用本脚本产生的一切后果由使用者自行承担。
