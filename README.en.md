# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box 2026 Secure Proxy Script (Four Major Protocols + Optional Reality)

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**Language:** [简体中文](./README.md) · **English**

A **sing-box 1.14 single-core** deployment script, covering the 2026 protocol tiers (Four Major Protocols + Optional Reality):

| Priority | Protocol | Purpose & Key Features | Transport | Certificate Requirement |
| :--- | :--- | :--- | :--- | :--- |
| 🥇 **High-Speed** | **Hysteria2** | Extreme throughput / loss resistance / Brutal congestion control | QUIC (H3) + salamander obfuscation + port hopping | Real Cert / Self-signed + Pinning |
| 🥈 **Next-Gen TCP** | **AnyTLS** | Eliminates TLS-in-TLS fingerprinting, WAN latency optimized | TCP + TLS 1.3 + Adaptive 8-tier Padding | Real Cert / Self-signed + Pinning |
| 🥉 **Anti-Censorship** | **NaiveProxy** | Chromium Cronet native network stack camouflage | HTTP/3 (QUIC) & HTTP/2 dual channel | **Mandatory Real Cert** |
| 4 **QUIC Alternative** | **TUIC v5** | Low-latency UDP acceleration / standard QUIC 0-RTT | QUIC (H3) | Real Cert / Self-signed + Pinning |
| 5 **Legacy Compat (Optional)** | **VLESS-Reality** | Universal direct link (No domain/cert needed; enable with `reap=1`) | TCP (XTLS Vision) | **No Domain / No Cert required (SNI Steal)** |

> Defaults to the **latest pre-release test core (`pre`, e.g. v1.15.0-alpha.2)**, with **QUIC and BBR congestion control** enabled by default, and backward compatibility down to **TLS 1.2 / HTTP 1.1**.

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
- [10. What's new in v2.5.0 — handshake latency and "newest settings everywhere"](#10-whats-new-in-v250--handshake-latency-and-newest-settings-everywhere)
- [11. What's new in v2.5.1 — ECN, and what the kernel's BBR actually is](#11-whats-new-in-v251--ecn-and-what-the-kernels-bbr-actually-is)
- [12. What's new in v2.5.2 — tcp-brutal silently breaks on kernels 7.1+](#12-whats-new-in-v252--tcp-brutal-silently-breaks-on-kernels-71)
- [13. v2.5.4 — 25-sample regression baseline on the BBRv3 kernel](#13-v254--25-sample-regression-baseline-on-the-bbrv3-kernel)
- [14. v2.5.5 — `tcp_rmem`/`tcp_wmem` ceiling on the `large` tier raised to 64MB](#14-v255--tcp_rmemtcp_wmem-ceiling-on-the-large-tier-raised-to-64mb)
- [15. v2.5.6 — reverts the 64MB buffer ceiling from v2.5.5](#15-v256--reverts-the-64mb-buffer-ceiling-from-v255)
- [16. v2.7.4 — Canonical Installation Commands & Documentation Alignment](#16-v274--canonical-installation-commands--documentation-alignment)
- [17. v2.7.5 — NaiveProxy & AnyTLS Stability and Handshake Latency Optimization](#17-v275--naiveproxy--anytls-stability-and-handshake-latency-optimization)
- [18. v2.7.6 — Hysteria2 Port Hopping Disabled by Default & End-to-End QDoS Mitigation](#18-v276--hysteria2-port-hopping-disabled-by-default--end-to-end-qdos-mitigation)
- [19. v2.7.7 — sing-box Defaults to Latest Pre-Release & New Features Adoption](#19-v277--sing-box-defaults-to-latest-pre-release--new-features-adoption)
- [20. v2.7.8 — Kernel Upgrade to 1.15.0-alpha.5 with Before/After Measurements](#20-v278--kernel-upgrade-to-1150-alpha5-with-beforeafter-measurements)
- [21. v2.7.9 — NaiveProxy Flow-Control Windows: h2 Was Hard-Capped at ~90 Mbps](#21-v279--naiveproxy-flow-control-windows-h2-was-hard-capped-at-90-mbps)
- [22. v2.7.10 — External Hysteria2 Initial Windows Raised: Upload 109→141, Slow Line 3→30](#22-v2710--external-hysteria2-initial-windows-raised-upload-109141-slow-line-330)
- [23. v2.7.11 – v2.7.13 — Subscription Service On by Default; Reserved-Port Changes](#23-v2711--v2713--subscription-service-on-by-default-reserved-port-changes)
- [24. v2.7.14 — AnyTLS Node Re-introduced & Full-Stack Parameter Tuning](#24-v2714--anytls-node-re-introduced--full-stack-parameter-tuning)
- [25. v2.7.15 — sing-box alpha.7 / Hysteria 2.12.3, No MPTCP on the vless-reality Client, naive-h2 Diagnosis](#25-v2715--sing-box-alpha7--hysteria-2123-no-mptcp-on-the-vless-reality-client-naive-h2-diagnosis)
- [26. v2.7.16 — Fix: Stable sing-box Could Not Load the Subscription; the Mihomo Subscription Failed to Load](#26-v2716--fix-stable-sing-box-could-not-load-the-subscription-the-mihomo-subscription-failed-to-load)
- [27. v2.7.17 — Firewall Accept Rules No Longer Jump to the Top; fs.suid_dumpable = 0](#27-v2717--firewall-accept-rules-no-longer-jump-to-the-top-fssuid_dumpable--0)
- [28. v2.7.18 — Stop Sending ICMP Redirects (send_redirects = 0 on the Uplink)](#28-v2718--stop-sending-icmp-redirects-send_redirects--0-on-the-uplink)
- [29. Disclaimer](#29-disclaimer)

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
# 1. Recommended Four Major Protocols Installation (High-speed Hysteria2 + AnyTLS + NaiveProxy + Tuic, requires domain):
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  hyp=1 anyp=1 nvp=1 tup=1 alns=1 ym=your.domain.com

# 2. Full Five-Protocol Installation (Four Major Protocols + Legacy Client Compatible VLESS-Reality TCP):
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  hyp=1 anyp=1 nvp=1 tup=1 reap=1 alns=1 ym=your.domain.com

# 3. No-Domain Fast Installation (Hysteria2 + Tuic + Reality, no domain and no cert application needed):
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  hyp=1 tup=1 reap=1
```

> `alns=1` uses acme.sh in standalone mode, requiring **port 80 to be free** and the domain's A record resolved to this host.
> If `ym=your.domain.com` is omitted, the script prompts interactively (keeps it out of shell history).
> `reap=1` (VLESS-Reality TCP node) requires **no domain and no certificate**, borrowing official TLS 1.3 SNI camouflage to bypass censorship; enabled on demand via `reap=1` (default is disabled for minimal overhead).

---

## 5. Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `hyp` | empty | 🥇 Enable Hysteria2 + TLS node (High-speed主力, supports port hopping and obfuscation, enable with `hyp=1`) |
| `anyp` | empty | 🥈 Enable AnyTLS + TLS node (Next-gen TCP主力, eliminates TLS-in-TLS fingerprinting and WAN latency optimization, enable with `anyp=1`) |
| `nvp` | empty | 🥉 Enable NaiveProxy (H3+H2, Chromium Cronet stack anti-probing camouflage, enable with `nvp=1`, requires real cert) |
| `tup` | empty | 4 Enable TUIC v5 node (Low-latency UDP acceleration / standard QUIC 0-RTT, enable with `tup=1`) |
| `reap` | empty | 5 Optional: enable VLESS-Reality TCP + XTLS-Vision node (no domain/cert needed; enable with `reap=1`) |
| `reap_sni` | `gateway.icloud.com` | Reality target camouflage SNI domain (supports any compliant TLS 1.3 domain) |
| `port_any` | random | Specify AnyTLS listening port (default 28443 or random 10000-65535) |
| `port_hy2` / `port_nv` / `port_tu` / `port_rea` | random | Fixed port assignments (10000-65535) |
| `alns` | empty | enable ACME certificate issuance (`alns=1`) |
| `ym` | empty | ACME certificate domain (required with `alns`) |
| `hyjpt` | empty | Hysteria2 port hopping, e.g. `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1 (default)** | Hysteria2 obfuscation: `salamander` or 1.14 `gecko`; disable with `hyobfs=0` |
| `hyobfs_pw` | independent | Hysteria2 obfuscation password |
| `hymask` | `https://www.bing.com` | Hysteria2 masquerade target URL |
| `sblevel` | `error` | server log level (`off` disables disk logs) |
| `blkport` | **1 (default)** | block outbound SMTP/SMB ports |
| `hyup` / `hydown` | empty | Hysteria2 up/down Mbps (set both for Brutal CC) |
| `sub` | **1 (default)** | enable v2rayN / universal subscription server (enabled by default; disable with `sub=0` or `sbbox sub off`) |
| `subport` | random | subscription server port |
| `subid` | independent | subscription token |
| `sub_nonaive` | empty | omit Naiveproxy nodes from subscription |
| `uuid` | auto-generated | custom UUID for Tuic and Reality |
| `name` | empty | node name prefix |
| `noautoup` | empty | disable weekly automatic kernel update (`noautoup=1`) |
| `sbrel` | **`pre` (default)** | kernel release channel: default latest pre-release (`pre`, e.g. `v1.15.0-alpha.2`); official stable with `sbrel=stable` |
| `tuicuos` | **0 (default native UDP)** | Tuic UDP relay mode: native UDP (default); QUIC stream with `tuicuos=1` |
| `tuils` | **1 (default)** | Tuic TLS hardening (certificate SHA-256 pinning); disable with `tuils=0` |
| `dns_optimistic` | **1 (default)** | sing-box 1.14 optimistic DNS cache with persistent storage |
| `api` | **1 (default)** | sing-box 1.14 native API service (127.0.0.1 independent 5-digit random port) for live telemetry in `sbbox status` |

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
| `sbbox speed [up] [down]` | Set up/down bandwidth and enable Hysteria2 & TCP Brutal congestion control |
| `sbbox speed bbr` | Clear bandwidth limits and switch back to BBR |
| `sbbox brutal [show\|on\|off\|speed\|add\|del]` | Manage TCP Brutal (HyNetworks/tcp-brutal) congestion control and rules (defaults to 95% of max host bandwidth) |
| `sbbox port [tu] [hy2] [nv]` | Change node ports (no args assigns random ports 10000-65535 and syncs configs & subscription) |
| `sbbox cert status` | Show certificate validity |
| `sbbox cert renew` | Renew certificate and restart |
| `sbbox up` | Update sing-box kernel (default pre-release channel; rollback on failure) |
| `sbbox log [N]` | Show the last N log lines (default 20) |
| `sbbox rotate` | Rotate all protocol passwords and subscription token |
| `sbbox doctor` | Health-check and auto-repair |
| `sbbox del` | Full uninstall |

---

## 7. Kernel Version Management

Install and `sbbox up` pull the latest pre-release test version by default (`sbrel=pre`, e.g. `v1.15.0-alpha.2`).

```bash
sbbox up                  # update to latest pre-release (default, sbrel=pre)
sbrel=stable sbbox up     # switch to official stable channel
```

---

## 8. Subscription & Client Configs

The built-in subscription server is enabled by default (`sub=1`); disable with `sub=0` or `sbbox sub off`.

### 8.1 Certificate Fingerprint & SHA-256 Injection (Enabled by Default)
During installation and configuration generation, the script automatically uses OpenSSL to extract and inject:
- **Tuic**: Injects `pcs=HEX_Fingerprint` and `pinSHA256=DER_Hash`; injects `certificate_public_key_sha256` into sing-box client configs (Tuic uses QUIC transport, so uTLS `fp=chrome` is strictly excluded to prevent `unsupported usage for uTLS` fatal errors).
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

## 10. What's new in v2.5.0 — handshake latency and "newest settings everywhere"

- **TLS floor raised to 1.3.** Both `tls.min_version` sites in `sb.json`
  (`vless-reality-in` and `naive-in`) now say `"1.3"`. Note that *deleting*
  `min_version` does the opposite of what it looks like — sing-box then falls
  back to its own, lower default — so the newest behaviour must be stated
  explicitly. Verify with `grep -n min_version /root/sbbox/sb.json` and
  `sing-box check -c /root/sbbox/sb.json`.
- **Certificate chain: already minimal, no change needed.** `trim_cert_chain`
  (added in v2.4.x) had already cut `fullchain.cer` to 3 certificates / 3243
  bytes. Re-checked this round against the original 4-cert chain: **3 is the
  floor** — with only leaf + YE2, `openssl verify` fails because Root YE is not
  yet in mainstream trust stores. The sibling Xray project on the same host
  gained the same trimming this round and produced a **byte-identical** chain.
- **DNS: already ordered correctly.** `dns-secure` (DoT 1.1.1.1) was already
  first. Measured on cold random subdomains: 1.1.1.1 **4 ms**, 8.8.8.8 14 ms,
  9.9.9.9 14 ms.
- **Tested and rejected:** moving Reality's `handshake.server` from
  `gateway.icloud.com:443` to a local target. The remote target costs only
  **1.6 ms** to connect (Apple's edge is in the same region), so there is no
  measurable win, and it would force a client SNI and subscription change.

Regression after the change: 13/13 nodes pass, including all five sbbox nodes
(tuic 2.6 ms, hysteria2 19.2 ms, naive-h3 3.4 ms, naive-h2 4.1 ms,
vless-reality 8.8 ms).

## 11. What's new in v2.5.1 — ECN, and what the kernel's BBR actually is

- **`net.ipv4.tcp_ecn` 2 → 1.** Both projects on this host must change together:
  each writes its own file under `/etc/sysctl.d/` (`99-sbbox.conf` and
  `99-xray-xhttp.conf`) and the later filename wins, so changing only one side
  makes the effective value depend on filename ordering rather than on either
  project's intent. Verified with tcpdump on the SYN/SYN-ACK flags, **filtered
  by peer IP** — without that filter our own server's SYN-ACK to inbound
  connections is misread as "the peer accepted". 6 of 7 peers accept
  (Cloudflare, GitHub, Bing, Microsoft, 1.1.1.1, 9.9.9.9); only Google refuses;
  no connection failures.
- **It does not speed anything up on this kernel.** The `bbr` here is BBRv1,
  whose control loop does not consume ECN marks. A 12-round interleaved A/B
  showed no measurable difference (44.8 ms / 1212 Mbps vs 47.5 ms / 1373 Mbps,
  the spread being Cloudflare edge variance). It is set to 1 purely as a
  zero-cost prerequisite for a future ECN-reactive congestion control.
- **Note on scope:** 3 of this project's 4 nodes are QUIC (TUIC, Hysteria2,
  naive-h3) and carry their congestion control in **userspace** — the kernel's
  TCP congestion control and ECN settings do not apply to them at all. This
  change only touches naive-h2 and plain outbound TCP.
- **The kernel's `bbr` is BBRv1, not v3**: `bbr_lt_bw_sampling` in kallsyms is
  v1-only, `ss` prints v1's info layout, `/sys/module/tcp_bbr/parameters/` is
  empty. This box is **arm64** and every kernel in the archive carries the same
  BBRv1, while prebuilt BBRv3 kernels (XanMod and similar) ship x86_64 only.
  A DKMS `tcp_bbr3` module is the low-risk route (it is how `tcp_brutal` is
  already built here) but was **not taken in this release**.

## 12. What's new in v2.5.2 — tcp-brutal silently breaks on kernels 7.1+

**This is independent of BBRv3 — anyone moving past kernel 7.0 hits it, silently.**

- **`tcp-brutal` no longer builds on 7.1+.** The kernel renamed the callback
  (`u32 (*min_tso_segs)(struct sock *sk)` → `u32 (*tso_segs)(struct sock *sk,
  unsigned int mss_now)`) and upstream has not adapted. This project then takes
  its `try_fallback_bbr` path and **silently degrades to BBR+FQ** — by design,
  but you will not know Brutal is off unless you read the logs.
- **Fix (automatic from v2.5.2):** install now runs `dkms ldtarball` first,
  patches, then `dkms install` — the old `dkms install <tarball>` unpacks and
  compiles in one step with nowhere to insert a patch. The patch's test
  **greps the target kernel's `include/net/tcp.h`** instead of guessing a
  `LINUX_VERSION_CODE` boundary. Three traps are documented in the comments:
  the Makefile is read twice (kbuild's re-read has only `srctree`, not
  `KERNEL_DIR`, so testing the latter leaves the macro silently undefined);
  `$(shell ...)` cannot use backslash continuations; and **make matches the
  closing paren of `$(shell ...)` without respecting quotes**, so a `)` in the
  grep pattern closes it early — hence the paren-free `tso_segs.*mss_now`.
  Verified building `brutal.ko` against both 7.2.3 and 7.0.0-1010-oracle;
  the patch function is idempotent.
- **Verify with:** `sysctl -n net.ipv4.tcp_available_congestion_control`,
  `dkms status | grep tcp-brutal`, and
  `tail -20 /var/lib/dkms/tcp-brutal/*/build/make.log`.
- **Regression on the BBRv3 kernel: 13/13 PASS**, including all five sbbox
  nodes. Note 3 of this project's 4 nodes are QUIC (TUIC, Hysteria2, naive-h3)
  and carry congestion control in **userspace**, so the kernel CC change only
  affects naive-h2 and plain outbound TCP.
- **Correction to v2.5.2 (in v2.5.3):** v2.5.2 documented `cwnd_gain` as the
  quick BBRv1-vs-v3 fingerprint (`2.88672` vs `2`). **That is wrong** —
  BBRv1's `cwnd_gain` is also `2` once a connection leaves STARTUP for
  PROBE_BW, so the value tracks the connection's *state*, not the BBR version,
  and misreports long-lived connections. Use the kallsyms symbols as the
  authority; `detect_bbr_version()` now falls back to `pacing_gain`
  (v1 STARTUP `2.88672` vs v3 `2.77344`) only when kallsyms is unreadable,
  marks it with a `?`, and otherwise returns `unknown`.
- **Correction to v2.5.1:** ECN's lack of benefit was blamed on "BBRv1 does not
  consume ECN marks". True, but not the whole story — BBRv3 does consume them
  and there is still no difference, because **nothing on these paths marks
  packets** (`nstat -az | grep -iE 'DeliveredCE|InCEPkts'` is 0 since boot).
  Judge ECN by CE counters, not by a throughput A/B.
- **Measurement warning:** `speed.cloudflare.com` returns HTTP 429 under
  repeated benchmarking; `%{speed_download}` then reads 0 while curl still
  exits 0, which is trivially misread as a throughput collapse.

## 13. v2.5.4 — 25-sample regression baseline on the BBRv3 kernel

Full run with `SAMPLES=25` on `7.2.3-joeyblog-bbrv3`; this project's five nodes:
tuic median 2.6 ms / p95 6.6, hysteria2 2.9 / 6.8, naive-h3 2.6 / 6.8,
naive-h2 3.9 / 7.2, vless-reality 7.3 / 15.9; no-proxy baseline 1.8 / 3.4.
**13/13 PASS** overall.

- **The jitter column (max ÷ median) necessarily grows with sample count** —
  more samples, more chances to catch an outlier. Judge stability by **p95**.
  Going from 9 to 25 samples on the same host: tuic went from p95 447.5 ms /
  **153.7x** to 6.6 ms / **2.9x** (that 153.7x was one outlier), while
  naive-h3's ratio *rose* from 12.2x to 16.5x even as its p95 *fell* from
  40.4 ms to 6.8 ms — ratio up, behaviour steadier. Read the no-proxy baseline
  row first; anything within it is the path, not the node.
- **Scope:** 3 of this project's 4 nodes are QUIC (TUIC, Hysteria2, naive-h3)
  and carry congestion control in **userspace** — the kernel CC swap does not
  affect them. BBRv3 only governs **naive-h2** and plain outbound TCP, so do
  not credit those three nodes' numbers to the new kernel.

## 14. v2.5.5 — `tcp_rmem`/`tcp_wmem` ceiling on the `large` tier raised to 64MB

The `large` tier (RAM >= 16GB) shipped `TCP_MEM_MAX=33554432` (32MB) while its
`SOCK_MEM_MAX` (`net.core.rmem_max`) was already 64MB, so a single TCP connection
could never reach the global ceiling. It is now `67108864`; **medium / entry /
small are unchanged**.

Note that the "link >= 1Gb and RAM >= 16GB -> 128M/64M" widening branch in
`sbbox.sh` (the `large+<speed>M` tier) **usually does not fire on a VM**: virtio
NICs report `-1` or an empty string in `/sys/class/net/*/speed`, which is
normalised to `0`, so the check fails and the host falls back to `large`. That is
precisely why the `large` tier itself needed fixing.

Verify:

```bash
sbbox tune on
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem
# expect: 4096  131072  67108864
```

**Two things deliberately NOT adopted** from the widely circulated
"BBR Blast Smooth" one-liner script:

- `net.ipv4.tcp_fin_timeout=8` — this project keeps `15`. The memory an 8s
  FIN_WAIT2 saves is meaningless on a 16GB+ host, while it drops the socket early
  on half-closed connections.
- Appending settings to `/etc/sysctl.conf` — Ubuntu 24.04+ has no such file by
  default, and systemd-sysctl applies `/etc/sysctl.conf` **after**
  `/etc/sysctl.d/*.conf`, so it silently overrides both `sbbox tune` and
  `xh tuning` values while `sbbox tune off` (which only removes its own
  `/etc/sysctl.d/99-sbbox.conf`) **cannot roll them back**. `>>` also stacks
  duplicates on re-run.

Everything else in that script is already covered here, and this project also
sets the UDP-side parameters it omits entirely (`udp_rmem_min`, `udp_wmem_min`,
`udp_mem`) — the ones that actually matter for QUIC protocols like hysteria2 and
tuic.

## 15. v2.5.6 — reverts the 64MB buffer ceiling from v2.5.5

v2.5.5 raised the `large`-tier `tcp_rmem`/`tcp_wmem` ceiling from 32MB to 64MB.
It **measurably slowed connections down**, so this release returns to the v2.5.4
behaviour (`TCP_MEM_MAX=33554432`).

**Lesson: the v2.5.5 verification was inadequate.** It only confirmed via a
`sysctl` read-back that the value had been *written*, and never compared
throughput or latency before and after. A parameter being set is not the same as
it being faster.

To roll back if you installed v2.5.5:

```bash
sbbox tune off && sbbox tune on      # with the v2.5.6 sbbox
sysctl net.ipv4.tcp_rmem             # expect 4096 131072 33554432
```

> **Tuning changes in this project will no longer be accepted without
> before/after measurements** — the bar is a throughput/latency comparison on the
> same host and config, not whether the parameter was written successfully.

## 16. v2.7.4 — Canonical Installation Commands & Documentation Alignment

In **v2.7.4**, the installation commands and documentation parameters have been comprehensively audited and standardized to resolve inconsistencies accumulated across rapid iterations (from early default Reality to v2.7.2 establishing the Four Major Protocols with Reality becoming optional):

### 1. Phenomenon & Root Cause
- **Outdated Install Command Missing AnyTLS**: AnyTLS was promoted to the 🥈 Next-Gen TCP protocol in v2.7.2, yet Section 4 in documentation still used the legacy `reap=1 tup=1 hyp=1 nvp=1` one-liner, causing users who copied the command to miss AnyTLS.
- **Inconsistent Environment Variable Defaults**: Code logic had already switched `reap` to optional/disabled by default (`reap=""`), but the environment variable table still displayed `reap: 1 (default)`, and omitted `anyp` and `port_any` entirely.
- **Legacy Terminology Inconsistencies**: Since v2.7.0 completely removed ShadowTLS, the script supports Four Major Protocols + Optional Reality (total 5 protocols). Historical references were unified.

### 2. Canonical Installation Commands
Three standard deployment scenarios strictly 1:1 aligned with script logic:
1. **Recommended Four Major Protocols (2026 Recommended: High-speed + Anti-blocking + Anti-active-probing)**:
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
     hyp=1 anyp=1 nvp=1 tup=1 alns=1 ym=your.domain.com
   ```
2. **Full Five-Protocol Installation (Four Major Protocols + Legacy Client Compatible VLESS-Reality TCP)**:
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
     hyp=1 anyp=1 nvp=1 tup=1 reap=1 alns=1 ym=your.domain.com
   ```
3. **No-Domain Fast Installation (Zero Cert Application, Self-signed + Cert Pinning)**:
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
     hyp=1 tup=1 reap=1
   ```

### 3. CI Automated Validation Matrix Alignment
- Updated `.github/workflows/validate.yml` to include `anyp=1` and inbound assertions (`select(.type=="anytls")`), ensuring CI covers both the Four Major Protocols and the Full Five-Protocol combinations.

---

## 17. v2.7.5 — NaiveProxy & AnyTLS Stability and Handshake Latency Optimization

In **v2.7.5**, extensive cross-ocean WAN real-world testing resolved throughput jitter, cold-start latency, and stream stalling across **AnyTLS** and **NaïveProxy**:
- **AnyTLS**: Adopted standardized 8-step MD5 ladder padding scheme, 30s TCP keep-alive, client idle session pool preheating (`min_idle_session: 2`) achieving 0-RTT instant requests, and disabled TFO to prevent middlebox SYN drops.
- **NaïveProxy**: Quad-multiplexing tunnels (`insecure_concurrency: 4`) eliminating HOL blocking, stream receive window expanded to 8MB (`stream_receive_window: 8388608`) to break BDP caps, QUIC session window enlarged to 16MB (`quic_session_receive_window: 16777216`), and ruleset download detoured to direct.
- **Empirical Results**: AnyTLS jitter dropped to 2.59 ms with 98+ MB/s line-rate throughput; NaïveProxy stabilized at 83 MB/s.

---

## 18. v2.7.6 — Hysteria2 Port Hopping Disabled by Default & End-to-End QDoS Mitigation

In **v2.7.6**, Hysteria 2 (hy2) received architecture-level hardening for coexistence safety and QDoS defenses:

### 1. Port Hopping Disabled by Default (Clean Single Port)
- **Elimination of Cross-Talk & Scanning**: Port hopping opened 10,000+ UDP ports (`25000:38000`), causing port collisions with coexisting proxy daemons (e.g. Xray) and exposing the host to internet-wide UDP port scanning and conntrack table exhaustion.
- **Single Port Default**: The installer defaults to single fixed port (e.g. `44116`). Hopping can still be enabled optionally via `sbbox hop 25000:38000`.
- **Thorough Netfilter Purge**: `sbbox hop off` and `sbbox del` comprehensively purge `PREROUTING`, `OUTPUT`, and `INPUT` rules for hopped ports.

### 2. Comprehensive QDoS (QUIC Denial of Service) Defenses
1. **QUIC Window & Stream Bounding (Server YAML & Inbound)**:
   - `initStreamReceiveWindow: 524288` (512 KB, 16x reduction from 8MB), `maxStreamReceiveWindow: 8388608` (8 MB);
   - `initConnReceiveWindow: 1048576` (1 MB, 20x reduction from 20MB), `maxConnReceiveWindow: 20971520` (20 MB);
   - `maxIncomingStreams: 512` (bounds stream resource consumption);
   - `maxIdleTimeout: 30s` & `ignoreClientBandwidth: true` (guards against fake client bandwidth exhaustion).
2. **sing-box 1.14 Inbound Hardening (`hy2-in`)**:
   - `"tcp_fast_open": true` & `"udp_fragment": true` (resolves cloud VPS MTU 1480 packet fragmentation drops);
   - `"udp_timeout": "60s"` (rapid reaping of stale UDP conntrack states);
   - Strict TLS 1.3 lockdown (`min_version: "1.3"`, `max_version: "1.3"`).
3. **Hardware-Level Netfilter / iptables Dual-Stack Anti-Flood**:
   - Fast-path for `RELATED,ESTABLISHED` packets ensures 1000Mbps+ line-rate with 0 overhead;
   - Immediate drop for `INVALID` UDP states;
   - Per-source-IP token-bucket rate limiting (`--hashlimit-above 50/sec --hashlimit-burst 100`) on `NEW` connections directly at the ingress boundary.

### 3. Before & After Parameter Hardening Matrix

| Layer | Component / Config File | Before Optimization | After QDoS Hardening | Mechanism & Benefits |
| :--- | :--- | :--- | :--- | :--- |
| **QUIC Buffer Layer** | `/etc/hysteria/sbbox.yaml` | 20MB / 8MB initial windows | `initConnReceiveWindow: 1048576` (1MB)<br>`initStreamReceiveWindow: 524288` (512KB)<br>`maxIncomingStreams: 512`<br>`ignoreClientBandwidth: true` | Lowers per-connection initial memory reservation **16–20x**; eliminates server memory exhaustion from bogus client bandwidth declarations |
| **Kernel Inbound Layer** | `sing-box` 1.14 inbound<br>`hy2-in` | `udp_timeout: "300s"` | `"udp_timeout": "60s"`<br>`"udp_fragment": true`<br>`"tcp_fast_open": true`<br>`"ignore_client_bandwidth": true`<br>Strict `min_version: "1.3"`, `max_version: "1.3"` | Rapid 60s reaping of dead UDP sessions, preventing conntrack exhaustion; fixes MTU 1480 fragmentation drops; blocks TLS downgrade attacks |
| **Hardware Netfilter** | `iptables` / `ip6tables`<br>INPUT Chain | Bare single port ACCEPT | **1. Top-priority ESTABLISHED fast-path** (1000M+ zero-loss)<br>**2. Immediate drop for INVALID states**<br>**3. NEW connection hashlimit rate limiting** (`--hashlimit-above 50/sec --hashlimit-burst 100`) | Drops handshake floods and malicious probe packets directly at the network interface ingress |

### 4. Empirical Verification Results (7-Sample Benchmark)
Verified via the automated multi-protocol benchmark suite:
- **sbbox Hysteria 2 (44116)**: Median latency **3.8 ms**, p95 **5.9 ms**, jitter **1.5x**;
- **Full 13-Node Suite**: 13/13 nodes PASS.

---

## 19. v2.7.7 — sing-box Defaults to Latest Pre-Release & New Features Adoption

In **v2.7.7**, following project guidelines and bleeding-edge networking protocol advances, the sing-box kernel release channel has switched default from `stable` to **`pre` (defaults to latest pre-release test build, currently `v1.15.0-alpha.2`)**, alongside full adoption of new engine features and clean deprecation migrations:

### 1. Rationale & Architecture Strategy
- **Pre-Release by Default (`sbrel=pre`)**: sing-box develops at a rapid pace. Key performance enhancements (such as I/O write buffering `buffer_size` & `flush_interval`, Android `auto_redirect`, WireGuard `on_demand`, etc.) are delivered and battle-tested first in pre-release channels (alpha/beta/rc).
- **Default Installation & Upgrades**:
  - `sbrel="${sbrel:-pre}"` defaults to pre-release everywhere (while `sbrel=stable` remains available for conservative setups);
  - `sbbox up` automatically fetches the newest pre-release build from GitHub Releases (currently upgraded smoothly to `v1.15.0-alpha.2`, compiled with Go 1.26.7).

### 2. New Features Applied & Breaking Deprecation Migrations
1. **`experimental.cache_file` Write Buffering & Periodic Flushing (sing-box 1.15 Feature)**:
   - Configured `"buffer_size": "1MB"` and `"flush_interval": "1m"`;
   - DNS cache and routing database write operations are transformed from immediate synchronous disk writes to buffered memory aggregation, flushed in batches when hitting 1MB or every minute. This dramatically reduces cloud SSD I/O wear and eliminates write latency spikes under high concurrent loads.
2. **Clean Migration of Breaking Deprecation: `download_detour` Replaced by `http_clients`**:
   - Starting with sing-box 1.14, `download_detour` in remote `rule_set` was deprecated; in 1.15+, it triggers a FATAL startup error.
   - Refactored client and rule_set architecture to declare a top-level `http_clients: [{ "tag": "direct-http", "detour": "direct" }]` block and `"default_http_client": "direct-http"` in `route`, completely eliminating fatal startup aborts.
3. **Client `sbox_client.json` Write-Buffer Cache Alignment**:
   - Injected `experimental.cache_file` with `store_fakeip: true`, `store_dns: true`, `buffer_size: "1MB"`, `flush_interval: "1m"` into client configuration templates, speeding up repeat queries and cold-boot handshakes.
4. **Maintained 1.14 Native API Telemetry & Optimistic DNS**:
   - Preserved localhost REST API telemetry (`sbbox status` displays real-time memory, connections, and traffic metrics);
   - Preserved `optimistic: true` for zero-wait optimistic DNS resolution.

### 3. Empirical Verification Results (7-Sample Benchmark)
Verified under `sing-box v1.15.0-alpha.2` via `/root/run_test.py`:
- **sbbox NaiveProxy H3 (10489)**: Median latency **2.6 ms**, p95 **10.7 ms**;
- **sbbox AnyTLS (28443)**: Median latency **2.7 ms**, p95 **9.3 ms**;
- **sbbox TUIC v5 (18793)**: Median latency **3.0 ms**;
- **sbbox Hysteria 2 (44116)**: Median latency **3.5 ms**, p95 **6.9 ms**;
- **Full 13-Node Benchmark**: **13/13 Nodes ALL PASS**.

---

## 20. v2.7.8 — Kernel Upgrade to 1.15.0-alpha.5 with Before/After Measurements

- **Upgrade path.** `v1.15.0-alpha.5` was the newest build on the pre-release
  channel. Before swapping, the new binary was dry-run with `sing-box check`
  against both the live server config and the client template shipped to
  users — both passed with no deprecation warnings — then `sbbox up` (which
  rolls back on a failed check or a failed start) took it from alpha.2 to alpha.5.
- **What the "new features" actually are.** Of the 50 commits between alpha.2
  and alpha.5, the ones that touch this project's nodes are: **AnyTLS migrated
  to sing-box's own library** (the biggest behavioural change, watched most
  closely), a cronet-go fix (NaiveProxy H2/H3), DNS deduplication after a failed
  exchange, no crash on a corrupted cache file, idle-connection management, and
  Go 1.26.8. **No new server-side option needs enabling**, so `sb.json` is
  unchanged and the improvements arrive with the kernel. The new TUN TCP/IP
  stack (alpha.3) is client-side: this project's client template never set
  `stack`, so clients on 1.15 pick it up automatically (`stack` is removed in
  1.17 — delete it if you set it by hand). Tailcat (alpha.5) is a WireGuard +
  DERP peer-to-peer mesh, not a proxy protocol, and is **not** added to subscriptions.
- **Before → after, same host and method** (latency `SAMPLES=25`, median/p95 ms;
  throughput 6 × 50 MB, median Mbps): tuic 2.3/3.1 → 2.5/3.4, 649 → 736;
  hysteria2 3.5/4.2 → 3.6/4.9, 265 → 307; naive-h3 2.9/10.0 → 2.9/10.6,
  470 → 477; naive-h2 4.2/13.5 → 4.1/11.3, 1055 → 1175; **anytls 2.4/6.9 →
  2.5/3.5**, 1326 → 1273. After the library swap AnyTLS's p95 halved with
  throughput flat (ranges overlap). The other +10–16% throughput shifts sit
  inside 6-sample noise, so no speed-up is claimed — only no regression.
  Full regression 12/12 PASS. UDP nodes' absolute numbers are depressed by the
  loopback hairpin path; the comparison is like-for-like, not real client speed.
- **Benchmark trap: cachefly returns HTTP 200 with 24 bytes when it throttles**
  (`I just served you 10mb`). Status and curl exit code look healthy, and on
  the first throughput pass 4 of 5 nodes came back "all invalid" because of it —
  nearly misread as node failures. The earlier advice to use cachefly is
  withdrawn. Alternate near-VPS sources with ample direct throughput
  (`speedtest.fremont.linode.com`, `sjo-ca-us-ping.vultr.com` from SJC), fetch a
  fixed byte range, and discard any sample whose `size_download` is short.

## 21. v2.7.9 — NaiveProxy Flow-Control Windows: h2 Was Hard-Capped at ~90 Mbps

- **The bug, invisible on loopback.** The client template pinned
  `"stream_receive_window": 8388608` on both naive outbounds. Per the sing-box
  docs, **in HTTP/2 mode this is the session window, each stream gets half, and
  the upstream default is 128 MB** — so each stream had 4 MB, 32x below default.
  At a realistic 160 ms RTT naive-h2 topped out at **~90 Mbps with a 88–100
  range across 5 runs**; a range that narrow is a hard ceiling, not network
  noise. Loopback benchmarks never showed it: at sub-millisecond RTT a 4 MB
  window drains instantly. **Window parameters must be validated under RTT.**
- **Method.** `tools/naive_rtt_bench.py` runs the client in a separate network
  namespace connected over veth to the local server, adds half the delay on
  each side with netem and loss on the download direction only — no public
  path (no hairpin), no production traffic, cleaned up afterwards. Downloads
  are 100 MB each (50 MB at 160 ms is mostly slow start); the namespace
  inherits the host's 32 MB `tcp_rmem` on this kernel, so client TCP buffers are
  not the limit; sources are linode-fremont / vultr-sjc, short downloads discarded.
- **A/B at 160 ms RTT, median Mbps of 5×100 MB (clean / 1% download loss):**
  h2 8 MB 90 / 81; **h2 field removed (default 128 MB) 308 / 221**; h2 32 MB 235.
  h3 8/16 MB 157 / 133; h3 upstream default 6/15 MB 127; **h3 32/64 MB 284 / 251**;
  h3 64/128 MB 277 / 260. So: **h2 drops the field** (a custom 32 MB was worse
  than default); **h3 uses 32 MB / 64 MB** (here upstream default is worse than
  the old value, and 64/128 MB buys nothing extra).
- **Tested and rejected: server QUIC congestion control `cubic`.** The server's
  `quic_congestion_control` governs h3 download (`bbr2` exists only on the
  outbound, i.e. upload). With client 32/64 MB: bbr 284 / 251 vs **cubic 121 and
  all five 100 MB downloads timing out at 1% loss**. bbr stays.
- **Unchanged: `insecure_concurrency` (4).** Upstream warns that concurrent
  tunnel connections make traffic analysis easier, defeating NaiveProxy's
  purpose; it only affects parallel streams, not single-stream downloads.
- **Verified after rollout** with the live template as-is: RTT 0 h2 1467 → 1456,
  h3 792 → 801 (within noise — larger windows do not hurt low latency);
  160 ms h2 90 → **306**, h3 157 → **284**; 160 ms + 1% loss h2 81 → **259**,
  h3 133 → **251**. `SAMPLES=25 run_test.py` 12/12 PASS. The windows live on the
  client — **users must re-pull the sing-box subscription** (`sbox_client.json`).
  Clash/Mihomo have no naive type and receive a plain HTTPS proxy, so they are unaffected.

## 22. v2.7.10 — External Hysteria2 Initial Windows Raised: Upload 109→141, Slow Line 3→30

Applies to the **external** Hysteria2 deployment (official hysteria binary + `hysteria-sbbox.service` + `/etc/hysteria/sbbox.yaml`); sing-box's built-in `hy2-in` does not expose these options.

- **Problem.** v2.7.6's QDoS hardening shrank the QUIC initial receive windows to 512 KB (stream) / 1 MB (connection). **Server receive windows govern upload.** In a network namespace at 160 ms RTT on a 1000↓/300↑ line (median of 5, sing-box / Xray client, Mbps): old 512K,1M init with 16M,64M max → 5 MB upload 34 / 31, 40 MB upload 109 / 129; hysteria defaults 8M,20M / 8M,20M → 61 / 58, 161 / 177; **new 8M,20M init with 16M,64M max → 50 / 63, 152 / 161**. Starting from 512 KB climbs too slowly at high RTT and even long uploads never catch up; on a 300↓/50↑ line a 5 MB upload managed only **3 Mbps** with the old windows.
- **Why this does not weaken QDoS protection.** Windows are QUIC flow-control credit; filling them to exhaust server memory first requires completing a QUIC handshake. This node enforces salamander, and a negative control confirmed that with a wrong obfs password, or none, **the connection cannot be established at all**. The per-source 50/s hashlimit, `maxIncomingStreams: 512` and `maxIdleTimeout: 30s` all stay.
- **Tested and rejected: `ignoreClientBandwidth: false`.** Current subscription links declare no bandwidth, so the switch has no effect for existing users anyway. With client declarations of none / 300 / 1000 on a 300↓/50↑ line (download Mbps, clean / 1% loss): `true` 198/115, 189/112, 149/127; `false` 178/108, 184/123, 174/115. No measurable gain, and `true` stops a password holder from forcing the server to blast at a forged rate. **Stays `true`.**
- **Applied live** to `/etc/hysteria/sbbox.yaml` (max windows unchanged at 16 MB / 64 MB) and re-verified: fast-line 5 MB upload 34/31 → 61/55, 40 MB 109/129 → 141/194, slow-line 5 MB 3 → 30, unshaped RTT 0 645↓/406↑ with no regression; `SAMPLES=25 run_test.py` 12/12 PASS. **Script:** `hy2_external_sync_secrets` (run by `sbbox rotate`) writes the new values into a fresh quic block and migrates the old hardened values by exact match, leaving user-customised values alone. Other external deployments can apply it by hand: `sed -i -E 's/^(  initStreamReceiveWindow: )524288$/\18388608/; s/^(  initConnReceiveWindow: )1048576$/\120971520/' /etc/hysteria/sbbox.yaml && systemctl restart hysteria-sbbox`.
- **Benchmark caveat: shaping queues must be bounded.** An outer tbf with an inner netem whose queue limit is huge emulates a ~1 s buffer (ping during uploads ~1000 ms), where Brutal fills the buffer and BBR is misled into wrong conclusions. All numbers here come from the corrected harness (netem `rate` with a bounded `limit`).

## 23. v2.7.11 – v2.7.13 — Subscription Service On by Default; Reserved-Port Changes

- **v2.7.11:** the HTTP subscription service is enabled by default (`sub=1`): installing or running `sbbox list` allocates a port, generates a token and starts the service. Disable with `sub=0` or `sbbox sub off` (persisted as a `sub_disabled` marker); `sbbox sub [on]` re-enables it. Port allocation avoids ports already in use and NAT port-range hijacks.
- **v2.7.12:** this host no longer runs the AnyTLS node (still supported; re-enable with `anyp=1`), so the tuning no longer adds 28443 to `net.ipv4.ip_local_reserved_ports`, returning it to the ephemeral pool. Verify with `sysctl -n net.ipv4.ip_local_reserved_ports`. If you still run AnyTLS, the only effect is that an outbound short-lived connection could in theory briefly take the port; a server that binds first is unaffected, and you can add 28443 back by hand if you ever hit a conflict.
- **v2.7.13:** the reserved range 10800-10806 is widened to 10800-10809. The co-located Xray project's (v4.9.29) regression test added local socks ports 10807 and 10808; once, a TIME-WAIT connection from the previous run held 10808 as its ephemeral port and the next run's client failed to bind (`bind: address already in use`), timing out every Xray node. Both projects write the same sysctl (last writer wins), so the lists must match. Verify with `sysctl -n net.ipv4.ip_local_reserved_ports`.


## 24. v2.7.14 — AnyTLS Node Re-introduced & Full-Stack Parameter Tuning

- **Background & Objective:** To combine strong anti-censorship camouflage with high network throughput and stability, v2.7.14 re-introduces and activates the **AnyTLS** node (TCP port `28443`) on the sing-box core, applying full-stack parameter optimization for high-bandwidth links, long session keepalive, active-probing resistance, and 0-RTT/1-RTT handshake speed.
- **Kernel & Local Port Reservation:** Port `28443` is restored to `net.ipv4.ip_local_reserved_ports`, aligning with the co-located Xray configuration and preventing ephemeral connection port collisions during TIME-WAIT.
- **Server-Side (`anytls-in`) Hardening:**
  - Listens on TCP `28443` with `tcp_fast_open: true`, `tcp_multi_path: true`, and `udp_fragment: true`.
  - Enforces TCP KeepAlive (`disable_tcp_keep_alive: false`, `tcp_keep_alive: 30s`, `tcp_keep_alive_interval: 5s`) to prevent silent carrier NAT gateway timeouts (60–120s drops).
  - Pinned TLS 1.3 security standards (`min_version: 1.3`, `alpn: ["h2", "http/1.1"]`, `handshake_timeout: 15s`).
  - Full 8-stage adaptive padding scheme (`padding_scheme` levels 0–7 matched with client MD5 hashing), eliminating TLS-in-TLS fingerprints and secondary control frame round-trips.
- **Client sing-box (`sbox_client.json`) Session Pool & KeepAlive:**
  - Connection pre-warming: `min_idle_session: 2` keeps 2 warm sessions ready for 0-RTT initial request forwarding.
  - Long session keepalive: `idle_session_timeout: 10m` and `idle_session_check_interval: 30s` maintain elevated TCP congestion window (`cwnd`), preventing speed collapse and throughput fluctuation.
  - Outbound excludes `tcp_fast_open: true` to prevent client core fatal errors.
  - Certificate SPKI public key pinning via `certificate_public_key_sha256` for hardware-grade MITM prevention.
- **Client Clash/Mihomo (`clmi.yaml`) Compatibility:**
  - Added `idle-session-timeout: 10m`, `min-idle-session: 2`, and `idle-session-check-interval: 30s`.
  - Dropped `tfo: true` to avoid middlebox SYN data drop retransmission penalties.
- **Empirical Benchmark Verification:**
  - **Handshake & RTT Latency:** Initial handshake ~11.69ms, pooled warm connection 6.89ms (average 9.92ms).
  - **Throughput:** Single-stream 10MB test finished in 0.12s, reaching **641.90 Mbps** sustained bandwidth.

## 25. v2.7.15 — sing-box alpha.7 / Hysteria 2.12.3, No MPTCP on the vless-reality Client, naive-h2 Diagnosis

Measured in a netns at 160 ms RTT / 1% download loss (Mbps down/up, 3 runs unless noted), using the outbounds from `sbox_client.json` with only `server` pointed at the veth peer.

- **sing-box 1.15.0-alpha.6 → alpha.7.** Relevant fixes only (HTTP/2 stream-error leakage and transport data races — the path naive-h2's server uses; read loops spinning on persistent errors; half-close propagation; dial contexts cancelled while connections are in use; crash on a corrupted cache file). No new server-side fields, so `sb.json` is unchanged. Both `sb.json` and `sbox_client.json` pass `sing-box check` with the new binary before `sbbox up`.
- **External Hysteria 2.12.2 → 2.12.3** (quic-go v0.62.0). SHA-256 matches the official `hashes.txt`; since Hysteria has no config-check subcommand, the current config was started once on a local test port before the swap.
- **Fix: no `tcp_multi_path` on the sing-box `vless-reality` client outbound.** With MPTCP and TFO both on, and the server also MPTCP-capable, connections time out (3/3). Dropping MPTCP gives 144/69, dropping TFO 126/60, so TFO is kept. The regression test never caught it because it goes through the public IP, where NAT strips the MPTCP option; a real client on a network that passes MPTCP would fail to connect. naive (Cronet has its own stack) and AnyTLS (MPTCP only) are unaffected. The Mihomo template has the same `tfo` + `mptcp` pair; tested in v2.7.16 with the official mihomo v1.19.31 over a direct netns link (3/3 connect, normal download) — unaffected, unchanged.
- **naive-h2 diagnosis.** The wide download spread without shaping (48–439) comes from BBR racing up on a bottleneck-free path (server `ss -ti`: cwnd ~40k packets, 3.8 Gbps pacing, 173 MB client window); shaped lines are steadier (174 at 300↓/50↑, 317 at 1000↓/200↑). Server-side MPTCP/TFO make no difference (test instance, 5 runs; all ranges overlap), so the server is unchanged. **Upload is capped at ~30 Mbps at 160 ms and cannot be fixed by configuration:** the naive inbound serves HTTP/2 through Go's standard library with a zero-value `http2.Server{}`, i.e. Go's default 1 MB per-stream receive window (1 MB ÷ 160 ms ≈ 52 Mbps theoretical); sing-box does not expose it and this project does not patch the core. The ceiling scales as ~1 MB ÷ RTT; use naive-h3 (QUIC) for upload-heavy use. Tested and **not adopted**: `tcp_notsent_lowat` 256 KB / 1 MB / 4 MB — per-run variance (23 to 343 within one setting, with the Reality-Vision control also dipping to 19–33) swamps any effect.
- **TCP buffer ceiling kept at 64 MB.** A 32 MB A/B (300↓/50↑ with loss) gave vless-reality 128 vs 32, naive-h2 120 vs 111, AnyTLS 201 vs 202, with identical ping-under-load; the 9-08 slowdown changed 64 MB and MTU 1500 together, and the data points at MTU.
- **Before → after** (alpha.6 + hy 2.12.2 → alpha.7 + hy 2.12.3): hysteria2 109/138 → 114/148, naive-h3 165/63 → 164/59, tuic 116/83 → 119/105, vless-reality 144/69 → 155/62, AnyTLS 347/126 → 323/153 — all within noise, no regression.

## 26. v2.7.16 — Fix: Stable sing-box Could Not Load the Subscription; the Mihomo Subscription Failed to Load

Earlier releases only validated client configs with this host's pre-release sing-box, never with a stable build or with mihomo.

- **sing-box subscription FATAL on stable 1.14.x** (`experimental.cache_file.buffer_size: json: unknown field "buffer_size"`). The client config carried the 1.15-only `buffer_size` / `flush_interval`, so SFI / SFA / v2rayN's sing-box core (usually stable) failed to load the whole file — every node down. Removed from the client config (no client-side benefit); the server's `sb.json` keeps them.
- **Mihomo subscription (`?clash=1` / `clmi.yaml`) failed to load entirely** (`cannot parse 'idle-session-check-interval' as int ... "30s"`). v2.7.14 copied sing-box's duration strings for AnyTLS; mihomo wants integer seconds. Now `30` / `600`.
- **naive dropped from the Mihomo subscription.** mihomo has no native naive outbound; the `type: http` + TLS stand-in is rejected by sing-box's naive inbound, which requires NaïveProxy padding (`missing naive padding` / `unexpected EOF`). Same result on alpha.6 and alpha.7 test instances — it never worked and was not caused by the upgrade. Use the sing-box client (Cronet) or the official NaïveProxy client for naive.
- **Verified:** sing-box 1.14.1 `check` plus a real download through all six nodes (hysteria2 240, AnyTLS 297, naive-h3 239, naive-h2 248, tuic 281, vless-reality 274 Mbps at 40 ms); alpha.7 `check`; mihomo v1.19.31 `-t` plus per-node delay and download for the four remaining nodes (hysteria2 271, AnyTLS 1300, tuic 663, reality 489). Run `sbbox list` to regenerate client configs; clients must re-pull.

## 27. v2.7.17 — Firewall Accept Rules No Longer Jump to the Top; fs.suid_dumpable = 0

- **Fix: `open_port` inserted every accept rule at INPUT position 1**, ahead of `lo`, `RELATED,ESTABLISHED` and the `INVALID` drop — v2.7.14's `tcp 28443 ACCEPT` became the first INPUT rule in both iptables and ip6tables. Worse, for a UDP port the accept landed **before its own QDoS hashlimit drop**, silently disabling the rate limit. The new `fw_accept_rule` inserts just before a catch-all `-j REJECT|DROP` (one without port/state matches, as shipped by Oracle's stock image), or appends if there is none, keeping `lo → ESTABLISHED → INVALID → rate limits → port accepts → catch-all`. Tested in a throwaway netns with and without a trailing REJECT (correct placement, no duplicates on repeat calls). On the live host 28443 was appended first and the top copy then deleted (no gap), then saved with `netfilter-persistent`; AnyTLS measured 298/72 Mbps afterwards.
- **`fs.suid_dumpable = 0`** is now written by the tuning (it was the kernel default 2 on the live host), so a crashing privileged process cannot dump memory holding keys, UUIDs or decrypted traffic; complements `kernel.core_pattern = core` and `* hard core 0`. The co-located Xray project adds the same key in v4.9.32.

## 28. v2.7.18 — Stop Sending ICMP Redirects (send_redirects = 0 on the Uplink)

With Docker installed `ip_forward = 1`, so the kernel sends ICMP redirects when it forwards a packet back out its ingress interface, leaking routing information to the local segment. Sending is on if **either** `all` or the interface is 1; `all`/`default` were 0 but the uplink `enp0s6` — present before boot, so untouched by `default` — was 1, so redirects were being sent. Negative control (host bridge plus two netns, A forced via the host to reach B, ICMP type 5 captured on A): `all=0` with the bridge at 1 → **2 redirects**; bridge at 0 → **0**. The tuning now writes `send_redirects = 0` for `all`, `default` and the current default-route interface (a `.` in a VLAN name becomes `/`); systemd's udev rule re-applies per-interface keys from `sysctl.d` when the NIC appears, so it persists across reboots. Receive side unchanged: with forwarding on, `accept_redirects` requires both `all` and the interface, and `all = 0` is enough. Matches the co-located Xray project's v4.9.33. Regression 13/13 PASS.

## 29. Disclaimer

This project is provided for network technology research and educational purposes only. Users are responsible for complying with local laws and regulations.


