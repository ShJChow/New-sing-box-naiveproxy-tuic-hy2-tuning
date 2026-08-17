# sing-box-naiveproxy — Sing-box Four-Protocol Secure Proxy Script

[![validate](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml/badge.svg)](https://github.com/ShJChow/sing-box-naiveproxy/actions/workflows/validate.yml)

A **sing-box single-core** deployment script derived from [`yonggekkk/argosbx`](https://github.com/yonggekkk/argosbx), covering four protocols:

| Protocol | Purpose | Transport |
|----------|---------|-----------|
| **Tuic** | Low-latency UDP acceleration | QUIC (HTTP/3) |
| **Hysteria2** | High throughput / loss resistance | QUIC (HTTP/3) |
| **Naiveproxy H2** | High-disguise HTTP/2 proxy | HTTP/2 |
| **Naiveproxy H3** | High-disguise HTTP/3 proxy | HTTP/3 (QUIC) |
| **VLESS-REALITY-Vision** | Fallback without a domain / low-latency TCP | TCP |

> **On removing and then restoring Reality.** v1.9.0 dropped Reality (VLESS) arguing it overlapped
> with Naive and only added TCP attack surface. **v1.10.0 brings it back, enabled by default.**
> That call was only half right: what overlaps is the *disguise*; what does not overlap is the
> *dependency on your own domain and certificate*. Reality completes its TLS handshake against a
> third-party site, so when your domain is blocked or ACME issuance fails, it is the one protocol
> still able to come up — and that is exactly the situation in which the other three fail together.
>
> The cost is real (extra plain-TCP attack surface, a separate key set), so it listens on its own
> port and can be disabled with `rlp=0`. Machines upgrading from v1.8.x **reuse their existing
> Reality keypair**, so old clients do not need to be re-imported.

Bundled with:
- **Kernel-level flow tuning** (ported from the `xh tuning on` of [`ShJChow/Xray-core-xhttp-cdn-tuned`](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned)): BBR, memory-tiered buffers, TCP Fast Open, file-handle limits — applied automatically at install, one-command rollback
- **acme.sh certificate issuance**: real TLS certificates for Naiveproxy / Hysteria2 / Tuic

---

## Security Hardening

| Item | argosbx original | sbbox new |
|------|------------------|-----------|
| TLS cert validation | `insecure=1` (self-signed bypass) | `insecure=0` (mandatory) |
| Naiveproxy certificate | self-signed fallback allowed | **real ACME certificate required** |
| Hysteria2 masquerade | none | returns a 404 page to non-Hy2 probes |
| Hysteria2 bandwidth claim | trusts client | `ignore_client_bandwidth: true` (server-authoritative) |
| Hysteria2 SNI | hard-coded `www.bing.com` | user-defined (certificate domain) |
| Tuic 0-RTT | not explicitly disabled | `zero_rtt_handshake: false` (replay-resistant) |
| File handle limit | system default | 1048576 (systemd drop-in) |
| Kernel tuning | none | applied at install; `sbbox tune off` to roll back |

> **Transport-layer obfuscation note**: sing-box does not support the Xray-proprietary xpadding / VLESS Encryption / ECH extensions. This script uses native sing-box equivalents: Naiveproxy HTTP/2 padding, Hysteria2 salamander obfuscation + QUIC port hopping, and uTLS fingerprints.

---

## Quick Start

### Prerequisites

- VPS: Ubuntu / Debian / CentOS / Alpine (amd64 or arm64)
- **root is recommended** (non-root works via a crontab autostart)
- For Naiveproxy: you need a domain resolved to the VPS; `alns=1` issues the certificate automatically

### One-command install

```bash
# Tuic + Hysteria2 only (no domain; self-signed cert + SHA256 pinning)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1

# All protocols (domain required; auto-issue a Let's Encrypt certificate)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 nvp=1 alns=1 ym=your.domain.com
```

> With `alns=1`, acme.sh uses standalone mode: **port 80 must be free** and the domain's A record must point to this VPS.
> If `ym=` is omitted, the script will **prompt you to enter the domain interactively** (kept out of shell history).

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tup` / `hyp` / `nvp` | empty | protocol toggles; any non-empty value enables (at least one must be given explicitly to enter the install flow) |
| `rlp` | **1 (on by default)** | VLESS-REALITY-Vision node; disable with `rlp=0`. Needs no domain and no certificate |
| `rlsni` | auto-selected | Reality handshake target. If unset, the installer measures apple / microsoft / cloudflare / amazon and picks the fastest one that negotiates TLS1.3 + h2; the choice is persisted and never changes afterwards |
| `alns` | empty | enable ACME certificate issuance (`alns=1`) |
| `ym` | empty | ACME certificate domain (required with `alns`) |
| `hyjpt` | empty | Hysteria2 port hopping, e.g. `hyjpt="20000 20001 20002"` |
| `hyobfs` | **1 (on by default)** | Hysteria2 salamander obfuscation — resists protocol fingerprinting; disable with `hyobfs=0` |
| `hyobfs_pw` | same as uuid | obfuscation password |
| `hyup` / `hydown` | empty | Hysteria2 up/down Mbps; **set both** to switch to Brutal congestion control |
| `sub` | empty | enable the v2rayN subscription server (`sub=1`) |
| `subport` | random | subscription server port |
| `subid` | same as uuid | subscription token (URL path — acts as the password) |
| `sub_nonaive` | empty | drop Naiveproxy nodes (use `sub_nonaive=1` if your client cannot parse `naive+` links) |
| `uuid` | auto-generated | custom password / UUID |
| `port_tu` / `port_hy2` / `port_nv` / `port_vl` | random | pin a fixed port |
| `sbrel` | **`pre` (default)** | kernel release channel: takes the newest release including beta/rc; use `sbrel=stable` for stable-only |
| `name` | empty | node name prefix |

---

## Management Commands

After install (reconnect SSH or `source ~/.bashrc`), use the `sbbox` command:

| Command | Function |
|---------|----------|
| `sbbox list` | Show all node links + client configs |
| `sbbox status` | Service status + flow-tuning status |
| `sbbox res` | Restart sing-box |
| `sbbox tune show` | Show kernel flow-tuning parameters |
| `sbbox tune off` | Roll back all kernel tuning |
| `sbbox sub` | Show the subscription URL |
| `sbbox sub off` | Stop the subscription server |
| `sbbox cert status` | Show certificate validity |
| `sbbox cert renew` | Renew the certificate and restart |
| `sbbox up` | Update the sing-box kernel |
| `sbbox log [N]` | Show the last N log lines (default 20) |
| `sbbox del` | Full uninstall |

---

## v2rayN Subscription

Pass `sub=1` at install time and the script generates a base64 subscription
and serves it over HTTP from the VPS:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sing-box-naiveproxy/main/sbbox.sh) \
  tup=1 hyp=1 sub=1
```

The install prints a URL of the form `http://<IP>:<port>/<token>`.
In v2rayN: **Subscription → Subscription settings → Add**, paste the URL,
then "Update subscription".

Run `sbbox sub` any time to reprint the URL, `sbbox sub off` to stop serving it.

> ⚠️ **Security note**: the subscription is served over **plain HTTP** and the
> token in the URL is the only credential. Do not share the address, and run
> `sbbox sub off` when you are done. For long-lived use, pin the port with
> `subport=` and restrict source IPs at the firewall.
>
> **By default the subscription includes every node, Naiveproxy H2/H3
> included.** Naiveproxy emits **two sets of links** because clients
> disagree on the URL scheme:
>
> | Scheme | Node name suffix | Clients |
> |---|---|---|
> | `naive+https://` / `naive+quic://` | `naive-h2` / `naive-h3` | v2rayN, NekoBox |
> | `http2://` / `http3://` | `naive-h2-rocket` / `naive-h3-rocket` | Shadowrocket |
>
> Both sets ship in the subscription — just ignore the set your client
> cannot use. To drop Naiveproxy entirely (both sets), regenerate with
> `sub_nonaive=1 sbbox list`.
>
> **A sing-box client can use Naiveproxy too**: `~/sbbox/sbox_client.json`
> includes a naive outbound. It requires `libcronet.so` to sit in the same
> directory as the sing-box binary — the official release tarball ships it
> alongside, so do not extract the binary alone. A trimmed self-built kernel
> without the library fails to start with `cronet: library not found`; drop
> that outbound in that case.

---

## Generated Files

| File | Purpose |
|------|---------|
| `~/sbbox/sb.json` | sing-box server config |
| `~/sbbox/sbox_client.json` | sing-box client aggregate config (importable) |
| `~/sbbox/clmi.yaml` | Clash / Mihomo client config |
| `~/sbbox/nodes.txt` | Plain-text share links |
| `~/sbbox/cert/` | ACME certificate (fullchain.cer + private.key) |
| `/etc/sysctl.d/99-sbbox.conf` | kernel flow-tuning params (removed by `sbbox tune off`) |
| `/etc/systemd/system/sbbox.service` | systemd unit |

---

## FAQ

**Naiveproxy reports "valid TLS certificate required"**
→ Naiveproxy is HTTPS-based and needs a real certificate. Install with `alns=1 ym=your.domain`.

**Hysteria2 / Tuic node won't connect**
→ Make sure the client `sni` is correct. Without a domain (self-signed cert), pin `pinSHA256` (Hysteria2) or set `insecure=1` and verify the fingerprint (Tuic).

**Certificate issuance fails**
→ Check: the A record points to this VPS IP, port 80 is free, and the Cloudflare proxy (orange cloud) is off.

**Non-root environment**
→ The script automatically uses crontab + nohup autostart; management commands work the same.

---

## Credits

- [yonggekkk/argosbx](https://github.com/yonggekkk/argosbx) — original script architecture and protocol config reference
- [ShJChow/Xray-core-xhttp-cdn-tuned](https://github.com/ShJChow/Xray-core-xhttp-cdn-tuned) — kernel-level flow tuning (`xh tuning`) implementation port
- [sagernet/sing-box](https://github.com/SagerNet/sing-box) — proxy core

---

## Disclaimer

This project is provided for **network technology research and educational purposes only**.

- You are responsible for complying with the laws and regulations of your country/region.
  All consequences arising from the use of this script are borne solely by the user; the author
  accepts no liability for any direct or indirect damages.
- Do not use this project for any unlawful purpose.
- The project comes with **no warranty of any kind**, express or implied, including but not limited
  to warranties of fitness, reliability, or availability. The code is provided "as is".
- You are responsible for the server you deploy, including credential hygiene, abuse prevention,
  and compliance with your provider's terms of service.

If you do not accept these terms, do not use this project.
