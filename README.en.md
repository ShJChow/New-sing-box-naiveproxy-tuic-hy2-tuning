# New-sing-box-naiveproxy-tuic-hy2-tuning — Sing-box Four-Protocol Secure Proxy Script

[![validate](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/actions/workflows/validate.yml)

**Language:** [简体中文](./README.md) · **English**

A **sing-box single-core** deployment script, covering four major protocols:

| Protocol | Purpose | Transport | Certificate |
|----------|---------|-----------|-------------|
| **VLESS-Reality** | Latest anti-censorship direct link (Default) | TCP (XTLS Vision) | **No Domain / No Cert required (SNI Steal)** |
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
# Recommended All-in-One Installation (includes latest TCP Reality + Tuic + Hysteria2 + Naiveproxy):
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  reap=1 tup=1 hyp=1 nvp=1 alns=1 ym=your.domain.com

# No-Domain Fast Installation (includes latest TCP Reality + Tuic + Hysteria2, no cert application needed):
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning/main/sbbox.sh) \
  reap=1 tup=1 hyp=1
```

> `reap=1` (VLESS-Reality TCP node) requires **no domain and no certificate**, using official TLS 1.3 SNI camouflage to resist censorship. Enabled by default during installation.

---

## 5. Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `reap` | **1 (default)** | enable latest VLESS-Reality TCP + XTLS-Vision node (no domain/cert needed; disable with `reap=0`) |
| `reap_sni` | `gateway.icloud.com` | Reality target camouflage SNI domain |
| `tup` / `hyp` / `nvp` | empty | protocol toggles (at least one must be specified) |
| `alns` | empty | enable ACME certificate issuance (`alns=1`) |
| `ym` | empty | ACME certificate domain (required with `alns`) |
| `hyjpt` | empty | Hysteria2 port hopping, e.g. `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1 (default)** | Hysteria2 obfuscation: `salamander` or 1.14 `gecko`; disable with `hyobfs=0` |
| `hyobfs_pw` | independent | Hysteria2 obfuscation password |
| `hymask` | `https://www.bing.com` | Hysteria2 masquerade target URL |
| `sblevel` | `error` | server log level (`off` disables disk logs) |
| `blkport` | **1 (default)** | block outbound SMTP/SMB ports |
| `hyup` / `hydown` | empty | Hysteria2 up/down Mbps (set both for Brutal CC) |
| `sub` | empty | enable v2rayN subscription server (`sub=1`) |
| `subport` | random | subscription server port |
| `subid` | independent | subscription token |
| `sub_nonaive` | empty | omit Naiveproxy nodes from subscription |
| `uuid` | auto-generated | custom UUID for Tuic and Reality |
| `port_tu` / `port_hy2` / `port_nv` / `port_rea` | random | fixed port assignment |
| `sbrel` | **`stable` (default)** | kernel release channel: default official stable (`stable`); beta/rc with `sbrel=pre` |
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

## 13. Disclaimer

This project is provided for network technology research and educational purposes only. Users are responsible for complying with local laws and regulations.

