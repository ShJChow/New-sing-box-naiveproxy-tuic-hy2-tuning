# sbbox — Sing-box-Only 四协议安全加固代理脚本

[![validate](https://github.com/ShJChow/sbbox/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/sbbox/actions/workflows/validate.yml)

基于 [`yonggekkk/argosbx`](https://github.com/yonggekkk/argosbx) 架构精简而成的 **sing-box 单内核**部署脚本，只保留四个协议：

| 协议 | 用途 | 传输 |
|------|------|------|
| **Tuic** | 低延迟 UDP 加速 | QUIC (HTTP/3) |
| **Hysteria2** | 高吞吐 / 抗丢包 | QUIC (HTTP/3) |
| **Naiveproxy** | 高隐匿性 HTTP(S) 代理 | HTTP/2 + HTTP/3 |
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
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sbbox/main/sbbox.sh) \
  tup=1 hyp=1 vlp=1

# 装全部四个协议（需域名，自动申请 Let's Encrypt 证书）
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sbbox/main/sbbox.sh) \
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
| `sub` | 空 | 启用 v2rayN 订阅服务（`sub=1`） |
| `subport` | 随机 | 订阅服务端口 |
| `subid` | 同 uuid | 订阅令牌（URL 路径，相当于密码） |
| `uuid` | 自动生成 | 自定义密码 / UUID |
| `port_tu` / `port_hy2` / `port_nv` / `port_vl` | 随机 | 指定固定端口 |
| `name` | 空 | 节点名称前缀 |

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
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sbbox/main/sbbox.sh) \
  tup=1 hyp=1 vlp=1 sub=1
```

安装结束会打印订阅地址，形如 `http://<IP>:<端口>/<令牌>`。
在 v2rayN 中：**订阅 → 订阅设置 → 添加**，把该地址填入 URL，然后「更新订阅」。

随时用 `sbbox sub` 再次查看地址，`sbbox sub off` 关闭服务。

> ⚠️ **安全提示**：订阅经**明文 HTTP** 提供，URL 里的令牌就是唯一凭据。
> 请勿分享该地址；不使用时执行 `sbbox sub off`。若需长期开放，建议改用
> `subport=` 指定端口并在防火墙上限制来源 IP。
>
> Naiveproxy 节点（`naive+https://`）不会进入订阅：v2rayN 不支持该协议。
> sing-box 客户端同样用不了——它的 naive 出站依赖 Cronet 库，官方发行版
> 未内置。请使用 [官方 naiveproxy 客户端](https://github.com/klzgrad/naiveproxy)，
> 节点参数见 `~/sbbox/nodes.txt`。

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
