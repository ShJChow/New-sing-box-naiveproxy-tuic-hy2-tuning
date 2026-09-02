# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box Three-Protocol Secure Proxy Script

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**Language:** [简体中文](./README.md) · **English**

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
- **OpenSSL Dynamic Fingerprinting & SHA-256 Pinning**: automatically extracts the active certificate's HEX fingerprint (`pcs`), DER SHA-256 (`pinSHA256`), and SPKI public key Base64 via OpenSSL during install, injecting them into Tuic / Hysteria2 / Naiveproxy configs to prevent MITM attacks

---

## Table of Contents

- [1. Prerequisites (Domains, Cloudflare & Certificates)](#1-prerequisites)
  - [1.1 DNS Resolution Setup](#11-dns-resolution-setup)
  - [1.2 Cloudflare Dashboard Settings](#12-cloudflare-dashboard-settings)
  - [1.3 SSL Certificate Issuance (acme-yg / acme.sh)](#13-ssl-certificate-issuance)
- [2. Security & Performance](#2-security--performance)
- [3. `DefaultLimitNOFILE` and `fs.nr_open` Alignment](#3-defaultlimitnofile-and-fsnr_open-alignment)
- [4. Quick Start & One-Command Install](#4-quick-start--one-command-install)
  - [4.1 Prerequisites Check](#41-prerequisites-check)
  - [4.2 One-Command Installation](#42-one-command-installation)
- [5. Environment Variables](#5-environment-variables)
- [6. Management Commands `sbbox`](#6-management-commands-sbbox)
- [7. Kernel Version Management](#7-kernel-version-management)
- [8. Subscription & Client Configs](#8-subscription--client-configs)
- [9. Benchmark Throughput](#9-benchmark-throughput)
- [10. Disclaimer](#10-disclaimer)

---

## 1. Prerequisites

Before running the deployment script, please prepare **2 subdomains resolving to your VPS IP** (Cloudflare recommended):
- **Domain 1 (Direct / Reality / Primary Domain)**: e.g. `reality.example.com` (or `naive.example.com`)
- **Domain 2 (CDN / Secondary Domain)**: e.g. `cdn.example.com`

>  **Free Domain Reference**: [DNSHE](https://my.dnshe.com) or [DigitalPlat](https://dash.domain.digitalplat.org)

---

### 1.1 DNS Resolution Setup

In the Cloudflare DNS console, add two `A` records pointing to your VPS public IP:

| Record Type | Domain Name | Target IP | Cloudflare Proxy Status (Cloud Color) | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **A Record** | `reality.example.com` | `Your VPS IP` |  **DNS Only (Grey Cloud)** | Used for cert issuance & Naiveproxy / Reality / Hy2 / Tuic direct connection |
| **A Record** | `cdn.example.com` | `Your VPS IP` |  **Proxied (Orange Cloud) / DNS Only** | Used for dual-domain SAN cert, CDN fallback, or traffic diversion |

>  **Important Note**: Naiveproxy (H3/H2), Hysteria2, and Tuic all rely on direct UDP/QUIC or custom TCP port connections. The primary domain used for direct proxy service **must remain DNS Only (Grey Cloud)** without Cloudflare CDN proxying enabled.

---

### 1.2 Cloudflare Dashboard Settings

Enable the following settings in your Cloudflare dashboard (if using Cloudflare):

1. **SSL/TLS** ➡️ **Overview**: Set encryption mode to **Full (strict)**;
2. **SSL/TLS** ➡️ **Edge Certificates**: Set Minimum TLS Version to **TLS 1.2**;
3. **Network**:
   -  Enable **gRPC**
   -  Enable **WebSockets**
   -  Enable **HTTP/3 (with QUIC)**
   -  Enable **0-RTT Connection Resumption**
4. **Rules** ➡️ **Cache Rules (Optional Optimization)**:
   - Set **Bypass Cache** for your proxy paths.

---

### 1.3 SSL Certificate Issuance

The installer automatically requests certificates using `acme.sh` (`alns=1 ym=your.domain.com`). If you prefer to issue certificates beforehand using the **`acme-yg` one-click script**, follow these steps:

#### Step 1: Release port 80 (if services are running)
```bash
systemctl stop nginx xray sing-box sbbox caddy apache2 2>/dev/null || true
```

#### Step 2: Run acme-yg script
```bash
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
```

#### Step 3: Interactive Menu Options
1. **Enter Menu**: Choose `1` for **【ACME 申请证书】**;
2. **Choose Mode**:
   - **Method A (Port 80 Standalone)**: Input `1` (requires port 80 free and Domain 1 resolved with grey cloud);
   - **Method B (Cloudflare API Mode)**: Input `2` (no need to stop port 80, uses CF Global API Key or Token);
3. **Enter Primary and Secondary Domains (Dual-domain SAN)**:
   - **Primary Domain**: Enter your direct domain (e.g. `reality.example.com` or `naive.example.com`)
   - **Secondary Domain**: Enter your CDN domain (e.g. `cdn.example.com`)
4. **Certificate Output**: Certificates are saved under `/root/ygkkkca/`.

#### Step 4: Deploy Certificate to Standard Path
```bash
mkdir -p /etc/ssl/private
cp -f /root/ygkkkca/reality.example.com/fullchain.cer /etc/ssl/private/fullchain.cer 2>/dev/null || cp -f /root/ygkkkca/cert.crt /etc/ssl/private/fullchain.cer 2>/dev/null || true
cp -f /root/ygkkkca/reality.example.com/private.key /etc/ssl/private/private.key 2>/dev/null || cp -f /root/ygkkkca/private.key /etc/ssl/private/private.key 2>/dev/null || true
chmod 600 /etc/ssl/private/*.key /etc/ssl/private/*.cer 2>/dev/null || true
```

>  **Tip**: The installer will automatically detect and reuse existing valid certificates from `/etc/ssl/private/`, `/root/ygkkkca/`, or `~/.acme.sh/`.

---

## 2. Security & Performance

| Item | Description |
|------|-------------|
| TLS cert validation | `insecure=0` (mandatory validation) |
| SHA-256 Cert Pinning | **Enabled by default on install**: OpenSSL extracts HEX fingerprint (`pcs`), DER SHA-256 (`pinSHA256`), and SPKI public key Base64 for Tuic / Hysteria2 / Naiveproxy configs against MITM |
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

## 3. `DefaultLimitNOFILE` and `fs.nr_open` Alignment

`fs.nr_open` is the kernel hard limit for file descriptors per process. Systemd's `DefaultLimitNOFILE` cannot exceed it. If inverted (`DefaultLimitNOFILE > fs.nr_open`), systemd will fail when launching any service without its own `LimitNOFILE`:

```
Failed to adjust resource limit RLIMIT_NOFILE: Operation not permitted
Failed at step LIMITS spawning ...: Operation not permitted
Main process exited, code=exited, status=205/LIMITS
```

`sbbox tune on` sets a drop-in `/etc/systemd/system.conf.d/10-sbbox-nofile.conf` ensuring `DefaultLimitNOFILE=1048576` aligns with `fs.nr_open`.

---

## 4. Quick Start & One-Command Install

### 4.1 Prerequisites Check

- VPS: Ubuntu / Debian / CentOS / Alpine (amd64 or arm64)
- **root is recommended** (non-root works via crontab autostart)
- For Naiveproxy: domain resolved to the VPS; `alns=1` issues certificate automatically

### 4.2 One-Command Installation

```bash
# Tuic + Hysteria2 (no domain; self-signed cert + SHA256 pinning)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  tup=1 hyp=1

# All three protocols (domain required; auto-issues Let's Encrypt cert; default stable + QUIC)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  tup=1 hyp=1 nvp=1 alns=1 ym=your.domain.com
```

---

## 5. Environment Variables

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
| `tuicuos` | **0 (default native UDP)** | Tuic UDP relay mode: native UDP (default); QUIC stream with `tuicuos=1` |
| `tuils` | **1 (default)** | Tuic TLS hardening (certificate SHA-256 pinning); disable with `tuils=0` |

---

## 6. Management Commands `sbbox`

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

## 7. Kernel Version Management

Install and `sbbox up` pull the official stable release by default.

```bash
sbrel=stable sbbox up     # update to latest stable (default)
sbrel=pre sbbox up        # switch to pre-release channel
```

---

## 8. Subscription & Client Configs

Run `sub=1` to enable the built-in subscription server.

### 8.1 Certificate Fingerprint & SHA-256 Injection (Enabled by Default)
During installation and configuration generation, the script automatically uses OpenSSL to extract and inject:
- **Tuic**: Injects `fp=chrome`, `pcs=HEX_Fingerprint`, and `pinSHA256=DER_Hash`; injects `certificate_public_key_sha256` into sing-box client configs.
- **Hysteria2**: Injects `pinSHA256=DER_Hash` and `pcs=HEX_Fingerprint`; injects `certificate_public_key_sha256` into sing-box client configs.
- **Naiveproxy**: Injects `pcs=HEX_Fingerprint` and `pinSHA256=DER_Hash`, supporting both QUIC (H3) and HTTP/2 paths.

### 8.2 Node Ordering & Client Config Files
Naiveproxy links are ordered with QUIC (H3) first:
- `naive+quic://` / `http3://`: QUIC (H3) fast node (recommended default)
- `naive+https://` / `http2://`: HTTP/2 compatibility node (fallback)

Client configs:
- sing-box: `~/sbbox/sbox_client.json`
- Clash / Mihomo: `~/sbbox/clmi.yaml`

---

## 9. Benchmark Throughput

Benchmark measured locally on VPS over 9 iterations showing median (min–max):

| Node | Port | Transport | Download MB/s Median (Range) | Handshake ms Median (Range) |
| :--- | :--- | :--- | ---: | ---: |
| *Direct Baseline (No Proxy)* | — | — | *681.6 (277.8–714.2)* | *23 (21–26)* |
| **Tuic** | 20011/UDP | QUIC (H3) | 92.9 (63.1–107.9) | 24 (21–47) |
| **Hysteria2** | 39259/UDP | QUIC (H3) + salamander | 31.0 (29.5–37.6) | 24 (20–67) |
| **Naiveproxy H3** | 47631/UDP | HTTP/3 (QUIC) | 59.6 (49.9–79.5) | 25 (22–34) |
| **Naiveproxy H2** | 47631/TCP | HTTP/2 | **169.7 (144.6–192.3)** | 28 (23–244) |

---

## 10. Disclaimer

This project is provided for network technology research and educational purposes only. Users are responsible for complying with local laws and regulations.

