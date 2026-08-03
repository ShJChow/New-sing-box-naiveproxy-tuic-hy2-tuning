# sbbox — Sing-box-Only Secure Proxy Deployment Script

A **sing-box single-core** deployment script derived from [`yonggekkk/argosbx`](https://github.com/yonggekkk/argosbx), stripped down to four protocols:

| Protocol | Purpose | Transport |
|----------|---------|-----------|
| **Tuic** | Low-latency UDP acceleration | QUIC (HTTP/3) |
| **Hysteria2** | High throughput / loss resistance | QUIC (HTTP/3) |
| **Naiveproxy** | High-disguise HTTP(S) proxy | HTTP/2 + HTTP/3 |
| **Reality (VLESS)** | Zero-certificate anti-detection | TCP + Vision flow |

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
| Reality TLS version | unspecified | forced `min_version: "1.3"` |
| Reality client fingerprint | partial | forced uTLS `chrome` |
| Tuic 0-RTT | not explicitly disabled | `zero_rtt_handshake: false` (replay-resistant) |
| File handle limit | system default | 1048576 (systemd drop-in) |
| Kernel tuning | none | applied at install; `sbbox tune off` to roll back |

> **Transport-layer obfuscation note**: sing-box does not support the Xray-proprietary xpadding / VLESS Encryption / ECH extensions. This script uses native sing-box equivalents: the Reality protocol itself, Naiveproxy HTTP/2 padding, Hysteria2 QUIC + port hopping, and uTLS fingerprints.

---

## Quick Start

### Prerequisites

- VPS: Ubuntu / Debian / CentOS / Alpine (amd64 or arm64)
- **root is recommended** (non-root works via a crontab autostart)
- For Naiveproxy: you need a domain resolved to the VPS; `alns=1` issues the certificate automatically

### One-command install

```bash
# Tuic + Hysteria2 + Reality only (no domain; self-signed cert + SHA256 pinning)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sbbox/main/sbbox.sh) \
  tup=1 hyp=1 vlp=1

# All four protocols (domain required; auto-issue a Let's Encrypt certificate)
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sbbox/main/sbbox.sh) \
  tup=1 hyp=1 nvp=1 vlp=1 alns=1 ym=your.domain.com
```

> With `alns=1`, acme.sh uses standalone mode: **port 80 must be free** and the domain's A record must point to this VPS.
> If `ym=` is omitted, the script will **prompt you to enter the domain interactively** (kept out of shell history).

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tup` / `hyp` / `nvp` / `vlp` | empty | protocol toggles; any non-empty value enables |
| `alns` | empty | enable ACME certificate issuance (`alns=1`) |
| `ym` | empty | ACME certificate domain (required with `alns`) |
| `ym_vl_re` | `apple.com` | Reality fallback/handshake domain |
| `hyjpt` | empty | Hysteria2 port hopping, e.g. `hyjpt="20000 20001 20002"` |
| `sub` | empty | enable the v2rayN subscription server (`sub=1`) |
| `subport` | random | subscription server port |
| `subid` | same as uuid | subscription token (URL path — acts as the password) |
| `uuid` | auto-generated | custom password / UUID |
| `port_tu` / `port_hy2` / `port_nv` / `port_vl` | random | pin a fixed port |
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
bash <(curl -Ls https://raw.githubusercontent.com/ShJChow/sbbox/main/sbbox.sh) \
  tup=1 hyp=1 vlp=1 sub=1
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
> v2rayN does not support Naiveproxy nodes (`naive+https://`) — they are
> ignored on import. Use the sing-box client config at
> `~/sbbox/sbox_client.json` for that protocol.

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
