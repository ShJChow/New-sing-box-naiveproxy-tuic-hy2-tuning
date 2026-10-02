# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box 2026 Secure Proxy Script

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**Language:** [简体中文](./README.md) · **English**

A **sing-box 1.14 single-core** deployment script, covering the 2026 protocol tiers:

| Priority | Protocol | Purpose & Key Features | Transport | Certificate Requirement |
| :--- | :--- | :--- | :--- | :--- |
| 🥇 **High-Speed** | **Hysteria2** | Extreme throughput / loss resistance / Brutal congestion control | QUIC (H3) + salamander obfuscation + port hopping | Real Cert / Self-signed + Pinning |
| 🥈 **Next-Gen TCP** | **AnyTLS** | Eliminates TLS-in-TLS fingerprinting, WAN latency optimized | TCP + TLS 1.3 + Adaptive 8-tier Padding | Real Cert / Self-signed + Pinning |
| 🥉 **Anti-Censorship** | **NaiveProxy** | Chromium Cronet native network stack camouflage | HTTP/3 (QUIC) & HTTP/2 dual channel | **Mandatory Real Cert** |
| 4 **QUIC Alternative** | **TUIC v5** | Low-latency UDP acceleration / standard QUIC 0-RTT | QUIC (H3) | Real Cert / Self-signed + Pinning |
| 5 **Legacy Compat (Optional)** | **VLESS-Reality** | Universal direct link (No domain/cert needed; enable with `reap=1`) | TCP (XTLS Vision) | **No Domain / No Cert required (SNI Steal)** |

> Defaults to the **official stable core (`stable`, since v2.7.34)**, with **QUIC and BBR congestion control** enabled by default, and backward compatibility down to **TLS 1.2 / HTTP 1.1**.

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
- [10. Release History & Core Tuning Evolution (v2.1 – v2.7.48)](#10-release-history--core-tuning-evolution-v21--v2747)
- [11. Disclaimer](#11-disclaimer)

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
| Minimum protocol compatibility | **TLS 1.3** (`min_version: "1.3"`) + ALPN `["h3", "h2"]`, fully eliminating inefficient serial HTTP/1.1 |
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
> If the domain is on Cloudflare, append `CF_Token=<API Token>` (Zone.Zone read + Zone.DNS edit) to issue and renew via DNS-01 without port 80 or stopping services; when the domain is proxied (orange cloud), standalone renewal always fails and DNS-01 is required.
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
| `sbrel` | **`stable` (default since v2.7.34)** | kernel release channel: official stable releases by default; `sbrel=pre` tracks pre-releases (alpha/beta/rc) |
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
| `sbbox` (or `sbbox menu`) | Open the interactive management menu |
| `sbbox block cn\|ads on\|off` | Reject outbound CN IPs / ad domains (default off); `sbbox block show` to inspect |
| `sbbox tune show` | Show kernel flow-tuning parameters |
| `sbbox tune win\|mac\|linux` | Print Windows / macOS / Linux client-side tuning commands |
| `sbbox tune off` | Roll back all kernel tuning |
| `sbbox sub` | Show subscription URL |
| `sbbox sub off` | Stop subscription server |
| `sbbox speed [up] [down]` | Set up/down bandwidth and enable Hysteria2 & TCP Brutal congestion control |
| `sbbox speed bbr` | Clear bandwidth limits and switch back to BBR |
| `sbbox brutal [show\|on\|off\|speed\|add\|del]` | Manage TCP Brutal (HyNetworks/tcp-brutal) congestion control and rules (defaults to 95% of max host bandwidth) |
| `sbbox port [tu] [hy2] [nv]` | Change node ports (no args assigns random ports 10000-65535 and syncs configs & subscription) |
| `sbbox cert status` | Show certificate validity |
| `sbbox cert renew` | Renew certificate and restart |
| `sbbox up [stable\|pre]` | Update sing-box kernel or switch channels (default stable channel; support `sbbox up stable` / `pre` one-command switch, rollback on failure) |
| `sbbox log [N]` | Show the last N log lines (default 20) |
| `sbbox rotate` | Rotate all protocol passwords and subscription token |
| `sbbox doctor` | Health-check and auto-repair |
| `sbbox del` | Full uninstall |

---

## 7. Kernel Version Management

Install and `sbbox up` follow the **`stable` channel** by default (since v2.7.34; currently `v1.14.2`). Switch to the **`pre` channel** (currently `v1.15.0-alpha.9`) to track alpha/beta/rc features. Existing installs keep the channel persisted in `~/sbbox/sbrel`.

- **Default channel `stable`**: Only pulls official stable releases from `releases/latest`.
- **Test channel `pre`**: Pulls the newest release from the GitHub repository, regardless of pre-release tag (automatically acquires the newest stable on release day as well).
- **One-Command Channel Switch & Self-Healing (New in v2.7.26)**: Seamlessly switch between channels. The script automatically handles schema differences between sing-box 1.14 and 1.15+ (such as `cache_file` buffer settings) to prevent validation fatal errors and erroneous rollbacks, and persists your channel selection to disk:

```bash
# Upgrade and switch commands
sbbox up                  # update kernel on currently saved channel (default stable; skip if latest)
sbbox up stable           # switch to official stable channel and update/downgrade (persists stable)
sbbox up pre              # switch to newest pre-release channel and update (persists pre)

# Environment variable syntax also supported
sbrel=stable sbbox up     # switch to stable channel
sbrel=pre sbbox up        # switch to pre-release channel
```

> **Channel Persistence**: The channel choice is stored in `~/sbbox/sbrel`. Weekly Sunday cron updates will strictly respect this channel.

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
- `naive+quic://`: QUIC (H3) fast node (recommended default)
- `naive+https://`: HTTP/2 compatibility node (fallback)

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

## 10. Release History & Core Tuning Evolution (v2.1 – v2.7.48)

After dozens of iterative rounds across high-latency cross-Pacific topologies (160ms+ / 1% packet loss), core technical milestones are summarized below:

| Area | Versions | Technical Strategy & Tuning Findings |
| :--- | :--- | :--- |
| **Four Pillars Convergence** | v2.7.0–v2.7.22 | Unified around Four Primary Pillars (Hysteria2 / AnyTLS / NaiveProxy / TUIC); v2.7.22 decommissioned Reality by default with self-healing `close_port` firewall cleanup. |
| **AnyTLS Client Link Spec Hardening** | v2.7.31 | Fix AnyTLS connection failure when importing into v2rayN (sing-box core): explicitly added `security=tls` into `anytls://` link parameters, satisfying v2rayN internal `_node.StreamSecurity` validation check and eliminating empty TLS outbound generation (`FATAL: TLS required`); added cert fingerprint pinning parameters (`pcs` / `pinSHA256`); removed redundant TFO from server `anytls-in` to avoid blackhole penalty; verified all primary pillars on live outbound fetch and matrix CI. |
| **AnyTLS Session Pool Scaling** | v2.7.30 | Speedup for AnyTLS as the primary node: enlarged idle session pool from 2 to 4 (`min_idle_session: 4` / `min-idle-session: 4`), keeping 4 warm TLS 1.3 tunnels on standby to eliminate handshake RTT and TCP head-of-line blocking under parallel browser requests, delivering true 0-RTT opening; extended idle session timeout to 5 minutes (`5m` / `300s`) to avoid recurring teardowns; tightened health check interval to 15s (`15s` / `15`) for rapid eviction of dead sockets; added `bind_address_no_port: true` in sing-box client outbound to reduce port pressure; removed deprecated `global-client-fingerprint` warning in Mihomo. |
| **AnyTLS & NaiveProxy Deep Tuning** | v2.7.1–v2.7.25 | AnyTLS upgraded to pure TLS 1.3 with ALPN converged to `["h2"]` (fixed in v2.7.27: AnyTLS runs over TCP, the QUIC-only `h3` was listed by mistake), completely eliminating serial HTTP/1.1 and head-of-line blocking; AnyTLS eliminates TLS-in-TLS with 8-tier random padding and tuned session pool; NaiveProxy enforces Cronet invariants; v2.7.23 aligns with klzgrad official guidelines: completely eliminates TFO (avoids 0.1% fingerprint & loss blackhole backoff); concurrency converged to `insecure_concurrency=2` eliminating socket buffer contention and ACK starvation, letting server BBRv3 maximize stream pacing with 64MB buffers: h2 download jumps to 209 Mbps (+90%, 391 Mbps @ 0% loss); h3 stripped of redundant TCP dial options, download boosted to 204 Mbps (+63%, 413 Mbps @ 1G line), upstream reaching 92 Mbps. |
| **Dual Kernel Channels & Self-Healing** | v2.7.7–v2.7.26 | Clarified `pre` (default pre-release) and `stable` (official release) dual channels; eliminated rollback loops when switching to `stable` caused by sing-box 1.15-specific fields (`buffer_size`/`flush_interval`); added `sbbox up stable` and `sbbox up pre` commands with automatic config adaptation; persisted channel selection to disk for weekly cron upgrades; added channel visibility in `sbbox status`. |
| **AnyTLS ALPN Fix** | v2.7.27 | AnyTLS is TCP-only: ALPN in the server inbound, `anytls://` link (`alpn=h2`), sing-box client and Mihomo templates changed from `["h3","h2"]` to `["h2"]`; TLS 1.3 kept, `http/1.1` not re-added. Verified: stable sing-box 1.14.2 `check` passes with real traffic; `openssl s_client -alpn h2` negotiates h2. v2rayN users must refresh the subscription. recent v2rayN supports Naive (with the sing-box core) but only parses `naive+https://` and `naive+quic://`; ignore the `http2://` / `http3://` entries |
| **Naive Subscription Dedup** | v2.7.28 | Subscription and `sbbox list` no longer emit the `http3://` / `http2://` Naive links: they point to the same inbound as `naive+quic://` / `naive+https://` and v2rayN cannot parse them (shows -1). Verified: after regeneration `nodes.txt` has only 2 Naive links |
| **Shadowrocket Naive by UA** | v2.7.29 | The subscription server detects the `Shadowrocket` UA and converts `naive+quic://` / `naive+https://` to the `http3://` / `http2://` form Shadowrocket understands; other clients still get `naive+` links. Verified: Shadowrocket UA receives `http3`/`http2`, v2rayN UA receives `naive+quic`/`naive+https` |
| **Flow Control & QDoS Hardening** | v2.1–v2.7.21 | External Hy2 receive window raised to 8M/20M curing transoceanic upload bottlenecks; port hopping disabled by default; Netfilter hashlimit anti-flood; TUIC strictly bans uTLS. |
| **Client Ecosystem & Seamless TUN** | v2.7.16–v2.7.21 | Purged 1.15+ fatal options (`download_detour`, `store_rdrc`); subscriptions ship out-of-the-box `tun-in` + FakeIP to eliminate remote DNS round-trips before connection. |
| **System Performance & Anti-Leak** | v2.5.0–v2.7.20 | Coordinated BBRv3 with TCP Brutal; maintained 64MB buffer ceiling; RPS/RFS softirq balancing; `fs.suid_dumpable=0`; built-in WARP streaming unlock. |
| **fq Qdisc Persisted Across Reboots** | v2.7.32 | Fixed fq being lost on reboot: `net.core.default_qdisc=fq` only applies to qdiscs created afterwards and the NIC exists before sysctl.d is loaded, so after a reboot the egress NIC was `mq` + `pfifo_fast` and QUIC lost fq pacing; fq, ring sizes, GRO/GSO/TSO, `txqueuelen` and RPS/RFS used to run only once during `sbbox tune on`. They now live in `/usr/local/sbin/sbbox-nic-tune` + `sbbox-nic.service` (OpenRC: `/etc/local.d`), re-applied at boot and removed by `sbbox tune off` / uninstall. fq changed from a single root fq to per-TX-queue fq under `mq` (`limit 20480 flow_limit 4096 quantum 18028 initial_quantum 90140`), matching the co-hosted Xray so whichever runs last yields the same qdisc tree. Verify with `tc qdisc show dev <nic>`, not with sysctl. The co-hosted Xray adds the same in v4.9.44. |
| **Auto Renewal Hook & DNS-01** | v2.7.33 | Fixed sbbox keeping the old certificate after renewal: `$CERT_DIR` (`~/sbbox/cert`) is a separate copy of the acme certificate and the installer never installed the renewal hook, so a successful acme.sh renewal never reached it and Naive / AnyTLS / TUIC / external Hy2 would all fail on expiry. The installer now runs `sbbox cert hook` at the end (appends `sbbox cert sync` to reloadcmd, keeping existing deploy paths; deliberately not inside `install_cert`, since the hook runs reloadcmd immediately and sync calls `install_cert`, which would recurse). `sbbox doctor` checks and auto-fixes a missing hook. With `alns=1`, passing `CF_Token` issues via `dns_cf` without stopping nginx / xray for port 80. Note: renewal changes the leaf fingerprint, so clients using pinSHA256 / pcs must re-import the subscription. The co-hosted Xray adds DNS-01 and `xh cert` in v4.9.45. |
| **Default Channel `stable` & tcp-brutal 2.0.1** | v2.7.34 | `sbrel` now defaults to `stable` instead of `pre`: mobile SFI/SFA and v2rayN mostly run stable cores, so a matching server is the safer default; existing installs keep the channel persisted in `~/sbbox/sbrel`. Measured switch (1.15.0-alpha.9 → 1.14.2, client fixed at 1.14.2, 160ms / 1% loss, 300↓/50↑, N=3): all five nodes overlap with no regression — AnyTLS 180→171, Naive-H3 203→201, Naive-H2 173→167, TUIC 19→20 Mbps (external Hy2 control 112→101). 1.14.2 `check` shows no deprecation warnings for server or client configs; `cache_file.buffer_size` / `flush_interval` are removed by the version self-heal. Upstream tcp-brutal 2.0.1 handles the `tso_segs` hook itself (`BRUTAL_HAVE_TSO_SEGS`), so `patch_tcp_brutal_tso_segs` now skips such sources — the patch wired the new hook to a function that always returns 2, capping TSO at 2 segments on 7.1+ kernels. The co-hosted Xray adds the same skip in v4.9.46. |
| **Update Notices & Verified Manual Updates (Hysteria2 / tcp-brutal)** | v2.7.35 | The weekly `sbbox up` now also **checks only** for new external Hysteria2 (hysteria-sbbox) and tcp-brutal releases: notices go to `~/sbbox/updates-available` and are shown at root login and in `sbbox status`; **nothing is installed automatically** (log: `journalctl -t sbbox-autoupdate`). Manual updates: `sbbox hy2 update` requires the binary's sha256 to match both the publisher's `hashes.txt` and GitHub's independently computed asset digest, checks the new binary reports the target version, restarts hysteria-sbbox (and hysteria-server if it shares the binary) and re-checks the UDP port, rolling back on failure. `sbbox brutal update` uses the same double check and only builds into DKMS (active on next boot), sharing a lock with the co-hosted xh. Tested in a sandbox path: normal update, rollback on failed port check, and rejection of a tampered download. The co-hosted Xray adds notices and verified updates for nginx / tcp-brutal in v4.9.47. |
| **TUIC Client Congestion Control Back to cubic** | v2.7.36 | Fixed TUIC **download collapsing to ~20 Mbps after a large upload on the same connection, and staying there**: clients (`sbox_client.json`, `tuic://` link, Mihomo) were hard-coded to `bbr`. The BBR in sing-quic and Mihomo counts ACK-only packets against pacing, so after the client has sent a lot, its BBR state slows the ACKs it returns and drags down the server's downlink; TUIC keeps the connection alive with a 10 s heartbeat, so the slowdown lasts until reconnect. Triage: not loss-related (collapses to 22 at 160ms/0% too), not bench ordering; switching the server to cubic / new_reno drops download to 6 / 25 (loss-based), and the problem follows only the **client** algorithm. Measured (160ms / 1% loss, 300↓/50↑, alternating 60MB download and 20MB upload): sing-box client bbr 19↓/8↑ → **cubic 111–121↓ / 39–41↑** (new_reno 114/39); Mihomo client bbr 112→19→18↓ / 33–41↑ → **cubic 110/160/138↓ / 8–15↑**. Clients now use the TUIC default `cubic` (on Mihomo, uploads over lossy high-RTT paths are slower, but there is no persistent download collapse); server `tuic-in` stays `bbr`. Validated with sing-box 1.14.2 `check`, `mihomo -t`, and per-UA subscription output. **Clients must refresh their subscription.** |
| **Cap NIC MTU at 1500 (PMTU black-hole safeguard)** | v2.7.38 | Some clouds default the NIC to MTU 9000 (jumbo frames) while the public path is 1500: the server emits TCP segments above 1500 bytes (e.g. a 3.7 KB TLS certificate chain) that are silently dropped at the edge, so the TCP handshake succeeds but TLS times out or resets — AnyTLS / Naive-H2 / Reality all fail while QUIC nodes (packets < 1280) work. The boot-time `sbbox-nic-tune` now lowers an MTU above 1500 to 1500 and adds `TCPMSS --clamp-mss-to-pmtu` (mangle POSTROUTING, v4/v6, not duplicated, saved via `netfilter-persistent save`); firewall is touched only when the MTU was actually lowered. This host's `enp0s6` is 1480, so nothing changes here. Verified in a netns: veth MTU 9000 → 1500 with a single rule, no duplicate on re-run, MTU 1400 left alone. |
| **Client tuning commands ported (`sbbox tune win\|mac\|linux`)** | v2.7.39 | Ported from xray-xhttp `xh tuning client`: prints Windows (netsh / registry), macOS (sysctl + LaunchDaemon persistence) and Linux client-side tuning commands. Windows BBR2 fallback now checks `$LASTEXITCODE` (netsh failures do not throw, so try/catch never fired), bbr2 needs Win11 22H2+, and all supplemental templates are covered; macOS buffer auto-tuning switches use `doautorcvbuf` / `doautosndbuf`, and the unverified, no-benefit mptcp item is dropped. |
| **Management menu (`sbbox`)** | v2.7.40 | Once installed, typing `sbbox` (or `sbbox menu`) in a terminal opens an interactive management menu in the style of xray-xhttp `xh`: status / nodes / subscription / restart / logs / core update / flow tuning / TCP Brutal / speed / certificates / port hopping / port change / WARP / external Hy2 / doctor / credential rotation / uninstall. Each action runs in a subshell, so an exit or failure inside a sub-command just returns to the menu; rotate and uninstall keep their confirmations; non-interactive use (pipes, cron) still prints help and status instead of blocking on the menu. |
| **Outbound filter switches (`sbbox block`)** | v2.7.41 | Modeled on the optional rules in zxcvos/Xray-script: new **default-off** `sbbox block cn on\|off` (reject outbound traffic to CN IPs, geoip-cn) and `sbbox block ads on\|off` (reject ad domains, category-ads-all); `sbbox block show` to inspect, `sbbox block update` to refresh rule sets; install-time `blockcn=1` / `blockads=1` also work. Rule sets are downloaded to `$SB_HOME/rules/` and referenced as local files, so startup never depends on the network; a failed download or `sing-box check` rolls back without writing a broken config. Blocking CN IPs breaks clients that use this proxy to reach mainland sites, so enable it only when the exit does not need that traffic. |
| **Reality set up per XTLS/REALITY README** | v2.7.42 | The server Reality inbound now sets `max_time_difference: 1m` (replay protection; clients whose clock is off by more than a minute cannot connect, so enable automatic time sync). The handshake target `gateway.icloud.com` was checked against the README (overseas, TLS 1.3, h2, no redirect). To enable, add `reap=1` to the installer (on an installed box re-run with the same protocol flags; per-protocol secrets and ports are kept). |
| **Reality time-difference check now off by default** | v2.7.43 | Since v2.7.42 the server Reality inbound carried `max_time_difference: 1m`, so clients whose clock was off by more than a minute could not connect. It is now **unset** by default; add `reatd=1m` (a duration such as `30s` / `1m` / `5m`) at install time to enable it. Existing installs are not changed. |
| **Reality inbound keeps only tcp_fast_open (tcp_multi_path off)** | v2.7.44 | The server Reality inbound used to enable both `tcp_fast_open` and `tcp_multi_path`: listening with MPTCP brings no benefit to plain TCP clients, and v2.7.15 recorded connection timeouts when MPTCP and TFO were both negotiated. Only `tcp_fast_open` is kept now. Existing installs pick it up once the config is regenerated (`sbbox rotate` / `sbbox port`, or re-running the installer). |
| **All TCP nodes unified to TFO-only (no MPTCP)** | v2.7.45 | A/B benchmark (4 tfo / mptcp server variants x 3 client variants on a Reality inbound, 160ms RTT with 0.5% loss per direction, fetching `http://www.apple.com` through the proxy): with `tfo+mptcp` on both ends 16/16 requests timed out; real-connection latency was about 331ms when the server had `tfo` and about 491ms without it (one RTT more); throughput showed no reliable difference, and an MPTCP client was slower on a short path. Accordingly the AnyTLS / Naive inbounds switch from `tcp_multi_path` to `tcp_fast_open`, the sing-box client Naive-h2 outbound keeps only TFO (the AnyTLS outbound does not support TFO, so it sets neither), and the mihomo Reality node drops `mptcp: true`. Existing installs pick it up after the config is regenerated (`sbbox rotate` / `sbbox port` / `sbbox list`). |
| **Cloud port list and local node self-test (`sbbox ports` / `sbbox selftest`)** | v2.7.46 | New `sbbox ports` (lists the ports and protocols that must be opened in the cloud security group; `sbbox doctor` prints it at the end too) and `sbbox selftest` (starts a sing-box client on the server from its own subscription config and, node by node, does a real handshake over 127.0.0.1 and fetches `http://www.apple.com`, separating server config / certificate / Reality key problems from cloud security group or client network problems; failures include the client error with IPs / UUIDs stripped). Menu items 19 and 20 added; `sbbox doctor` no longer prints a negative "remaining -N" count. A "normal" local check only means the process is listening, not that the cloud allows the port. |
| **Platform-aware defaults (ARM / AMD) and rollback of untested TFO changes** | v2.7.47 | At install time the platform is detected and printed: architecture (aarch64 / x86_64), CPU, cores, memory, kernel, virtualization and cloud provider (from DMI: Oracle / AWS / GCP / Azure / Alibaba). With under 1.5GB of RAM (e.g. Oracle free-tier AMD 1GB) TCP Brutal is not installed by default (it builds a kernel module on the spot, which is memory-hungry and slow; an explicit `FEATURE_BRUTAL=true` is still honored), a hint to add swap is shown when there is none, and sing-box gets a `GOMEMLIMIT` (60% of RAM). `python3` is now installed as a dependency and missing required commands are reported when the dependency install fails (previously `deps_done` was still written and never retried). The ports to open in the cloud security group, with each cloud's console path, are listed at the end of the install. **Rollback**: the v2.7.45 A/B benchmark only covered the Reality inbound; the AnyTLS / Naive changes were an untested extension, and Naive TFO was deliberately removed in v2.7.23 (kernel tcp_fastopen blackhole penalty on loss). AnyTLS / Naive inbounds and client outbounds therefore go back to `tcp_multi_path`; only the Reality inbound keeps "tfo only". Existing installs pick it up after the config is regenerated. |
| **AnyTLS: all parameters back to sing-box factory defaults** | v2.7.48 | The default AnyTLS node no longer writes any tuning option: the server drops `tcp_multi_path`, `udp_fragment`, TCP keep-alive, the custom `padding_scheme`, `min_version`, `alpn` and `handshake_timeout`; clients (sing-box, mihomo) drop `tcp_multi_path`, keep-alive, `idle_session_*`, `min_idle_session`, `bind_address_no_port`, the uTLS fingerprint, `alpn` and `udp`; the share link no longer carries `alpn=h2`. Only required fields remain (port, password, certificate, SNI, `insecure` and the cert-pin check). Existing installs pick it up after regenerating the config |
| **Server DNS Reordered by CDN Edge Proximity · Resolver for External Hysteria2 · Useful Bits of a Third-Party Tuner Absorbed** | v2.7.37 | **DNS**: the sing-box server's `dns-secure` is now `9.9.9.10` (Quad9 unfiltered, DoT) and `dns-backup` is `1.1.1.1`. Resolution time is paid once per domain, but the CDN edge it returns sets the latency of every later connection: 32 popular domains × 3 queries each, domains whose edge was more than 3 ms slower than the best: 8.8.8.8 10, 1.1.1.1 5, 9.9.9.10 only 1 (Akamai-hosted Apple / iCloud / Microsoft differ by 10–50 ms). **External Hysteria2**: `/etc/hysteria/sbbox.yaml` had no `resolver`, so it used the system resolver (8.8.8.8 first on this host). With the same sing-box client, every generate_204 fetch through it was ~28 ms slower than through Xray's built-in Hy2; a packet capture showed this was server-to-target RTT (a Google edge 14 ms away versus 0.8 ms for Xray). `hy2_external_sync_resolver` now appends `resolver: udp 9.9.9.10:53` (an existing resolver section is left untouched), and `sbbox doctor` detects a missing one, adds it and restarts hysteria-sbbox. Warm connections went from 190 to 164 ms (1.2 → 1.0 RTT at 160 ms) and stay at 1.0 RTT after 65 s / 120 s idle. **System tuning**: `net.core.rmem_max / wmem_max` reduced from 128 MB to 64 MB (including the gigabit-link branch; same as the `tcp_rmem / wmem` ceiling); new `vm.min_free_kbytes` (64 MB large tier / 32 MB medium) and `kernel.sched_autogroup_enabled = 0`; `nf_conntrack` is listed in `/etc/modules-load.d/sbbox-conntrack.conf`, because at boot systemd-sysctl runs before iptables / Docker load the module and `nf_conntrack_max` is silently skipped (removed by `tune off`); `kernel.core_pattern = core` is now written by the tuning code (it was only mentioned in comments and added by hand, so re-running `tune on` dropped it). These are the non-conflicting parts of a third-party one-click tuner (vps-tcp-tune); the rest conflicts with existing values or showed no gain (details in the co-hosted Xray v4.9.48). **Tested, not adopted**: naive `insecure_concurrency` 1 vs 2 makes no handshake difference, so it stays at 2; after ~30 s idle Cronet closes the naive-h3 QUIC connection and the next request costs one extra RTT, which is client behaviour the server cannot change. The handshake benchmark and full per-node data live in the co-hosted Xray repo (`tools/xray_handshake_bench.py`). The co-hosted Xray adds the 64 MB change and the three system settings in v4.9.48 and moves its built-in DNS to 9.9.9.10 as well. |

---

## 11. Disclaimer

This project is provided for network technology research and educational purposes only. Users are responsible for complying with local laws and regulations. Any consequences arising from using this script are solely the user's responsibility.
