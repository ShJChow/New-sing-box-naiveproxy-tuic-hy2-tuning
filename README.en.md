# sing-box-naiveproxy — Sing-box Three-Protocol Secure Proxy Script

[![validate](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml)

A **sing-box single-core** deployment script, covering three main protocols:

| Protocol | Purpose | Transport | Certificate |
|----------|---------|-----------|-------------|
| **Tuic** | Low-latency UDP acceleration | QUIC (HTTP/3) | Real Cert / Self-signed + Pinning |
| **Hysteria2** | High throughput / loss resistance | QUIC (HTTP/3) | Real Cert / Self-signed + Pinning |
| **Naiveproxy H3** | High-disguise HTTP/3 proxy (Default) | HTTP/3 (QUIC) | **Mandatory Real Cert** |
| **Naiveproxy H2** | High-disguise HTTP/2 proxy (Fallback) | HTTP/2 | **Mandatory Real Cert** |

> Defaults to the **official stable release core (`stable`)**, with **QUIC and BBR congestion control** enabled by default, and backward compatibility down to **TLS 1.2 / HTTP 1.1**.

Bundled with:
- **Kernel-level flow tuning** (ported from the `xh tuning on` of [`ShJChow/Xray-core-xhttp-cdn-tuned`](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned)): BBR, memory-tiered buffers, TCP Fast Open, file-handle limits — applied automatically at install, one-command rollback
- **acme.sh certificate issuance**: real TLS certificates for Naiveproxy / Hysteria2 / Tuic

---

## Security & Performance

| Item | Description |
|------|-------------|
| TLS cert validation | `insecure=0` (mandatory validation) |
| Naiveproxy certificate | **Mandatory ACME real certificate** |
| Minimum protocol compatibility | **TLS 1.2** (`min_version: "1.2"`) + ALPN `["h3", "h2", "http/1.1"]` |
| Hysteria2 masquerade | `masquerade` reverse-proxies real sites (default www.bing.com) against probes |
| Hysteria2 congestion control | `ignore_client_bandwidth: true` + `bbr_profile: standard` (server-authoritative BBR) |
| Hysteria2 obfuscation | `obfs: salamander` (enabled by default with independent random secret) |
| Tuic fast handshake | `zero_rtt_handshake: true` + `congestion_control: bbr` |
| File handle limit | 1048576 (systemd unit setting) |
| Protocol secrets | **Independent random secret per protocol** |
| Outbound DNS | **DoT encrypted** (1.1.1.1 / 9.9.9.9) |
| Private network isolation | `ip_is_private` rejected to prevent intranet penetration |
| Spam protection | Block outbound ports 25/465/587 and SMB |
| Server logging | Default `error`; `sblevel=off` completely disables disk logs |

---

## Quick Start

### Prerequisites

- VPS: Ubuntu / Debian / CentOS / Alpine (amd64 or arm64)
- **root is recommended** (non-root works via crontab autostart)
- For Naiveproxy: domain resolved to the VPS; `alns=1` issues certificate automatically

### One-command install

```bash
# Tuic + Hysteria2 (no domain; self-signed cert + SHA256 pinning)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1

# All three protocols (domain required; auto-issues Let's Encrypt cert; default stable + QUIC)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 nvp=1 alns=1 ym=your.domain.com
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tup` / `hyp` / `nvp` | empty | protocol toggles (at least one must be specified) |
| `alns` | empty | enable ACME certificate issuance (`alns=1`) |
| `ym` | empty | ACME certificate domain (required with `alns`) |
| `hyjpt` | empty | Hysteria2 port hopping, e.g. `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1 (default)** | Hysteria2 salamander obfuscation; disable with `hyobfs=0` |
| `hyobfs_pw` | independent | Hysteria2 obfuscation password |
| `hymask` | `https://www.bing.com` | Hysteria2 masquerade target URL |
| `sblevel` | `error` | server log level (`off` disables disk logs) |
| `blkport` | **1 (default)** | block outbound SMTP/SMB ports |
| `hyup` / `hydown` | empty | Hysteria2 up/down Mbps (set both for Brutal CC) |
| `sub` | empty | enable v2rayN subscription server (`sub=1`) |
| `subport` | random | subscription server port |
| `subid` | independent | subscription token |
| `sub_nonaive` | empty | omit Naiveproxy nodes from subscription |
| `uuid` | auto-generated | custom UUID for Tuic |
| `port_tu` / `port_hy2` / `port_nv` | random | fixed port assignment |
| `sbrel` | **`stable` (default)** | kernel release channel: default official stable (`stable`); beta/rc with `sbrel=pre` |
| `tuicuos` | **1 (default)** | Tuic UDP over QUIC stream |

---

## Management Commands

| Command | Function |
|---------|----------|
| `sbbox list` | Show all node links + client configs |
| `sbbox status` | Service status + flow-tuning status |
| `sbbox res` | Restart sing-box |
| `sbbox tune show` | Show kernel flow-tuning parameters |
| `sbbox tune off` | Roll back all kernel tuning |
| `sbbox sub` | Show subscription URL |
| `sbbox sub off` | Stop subscription server |
| `sbbox cert status` | Show certificate validity |
| `sbbox cert renew` | Renew certificate and restart |
| `sbbox up` | Update sing-box kernel (default stable channel; rollback on failure) |
| `sbbox log [N]` | Show the last N log lines (default 20) |
| `sbbox rotate` | Rotate all protocol passwords and subscription token |
| `sbbox doctor` | Health-check and auto-repair |
| `sbbox del` | Full uninstall |

---

## Subscription & Client Configs

Run `sub=1` to enable the built-in subscription server.

Naiveproxy links are ordered with QUIC (H3) first:
- `naive+quic://` / `http3://`: QUIC (H3) fast node (recommended default)
- `naive+https://` / `http2://`: HTTP/2 compatibility node (fallback)

Client configs:
- sing-box: `~/sbbox/sbox_client.json`
- Clash / Mihomo: `~/sbbox/clmi.yaml`

---

## Disclaimer

This project is provided for network technology research and educational purposes only.

