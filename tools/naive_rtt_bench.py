#!/usr/bin/env python3
"""NaiveProxy 真实 RTT 基准。
客户端跑在独立网络命名空间 nbench 里，经 veth 连本机服务端 10.200.0.1:10489，
netem 在两端各加一半延迟，丢包只加在下行方向（服务端→客户端）。
不经公网、无发夹路径，也不碰生产流量。
用法: naive_rtt_bench.py <rtt_ms> <loss_pct> <variants.json> [N]
  variants.json 每项形如 {"name":"...", "base":"naive-h2"|"naive-h3", "set":{...}, "unset":[...]}，
  以 /root/sbbox/sbox_client.json 中同名出站为底，覆盖/删除字段后测试；不写 set/unset 即测线上模板原样。
  环境变量 NEED=单次下载字节数（默认 100000000，RTT 高时 50MB 不足以越过慢启动）。
为什么需要它：本机回环 RTT 不到 1ms，接收窗口偏小的问题完全测不出来。
"""
import json, subprocess, sys, time, statistics, copy, os, re
S = os.environ.get("BENCH_TMP", "/tmp")   # 临时客户端配置与日志的落点
RTT, LOSS, VARFILE = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
N = int(sys.argv[4]) if len(sys.argv) > 4 else 5
NS, BIN = "nbench", "/root/sbbox/sing-box"
URLS = ["https://speedtest.fremont.linode.com/100MB-fremont.bin",
        "https://sjo-ca-us-ping.vultr.com/vultr.com.100MB.bin"]
NEED = int(os.environ.get("NEED", "100000000"))

def sh(c, check=True): return subprocess.run(c, shell=True, capture_output=True, text=True, check=check)

def ns_up():
    sh(f"ip netns del {NS}", check=False); sh("ip link del vh", check=False)
    for c in [f"ip netns add {NS}", "ip link add vh type veth peer name vc", f"ip link set vc netns {NS}",
              "ip addr add 10.200.0.1/30 dev vh", "ip link set vh up",
              f"ip -n {NS} addr add 10.200.0.2/30 dev vc", f"ip -n {NS} link set vc up",
              f"ip -n {NS} link set lo up", f"ip -n {NS} route add default via 10.200.0.1"]:
        sh(c)
    half = RTT / 2
    if RTT > 0 or LOSS > 0:
        sh(f"tc qdisc add dev vh root netem delay {half}ms loss {LOSS}% limit 400000")
        sh(f"ip netns exec {NS} tc qdisc add dev vc root netem delay {half}ms limit 400000")

def kill_clients():
    # 只杀命令行以 sing-box 二进制开头、且引用本脚本客户端配置的进程；
    # 不用 pkill -f，那会匹配到调用方 shell 自己的命令行。
    me = os.getpid()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == me: continue
        try: argv = open(f"/proc/{pid}/cmdline","rb").read().split(b"\0")
        except OSError: continue
        if argv and argv[0].endswith(b"sing-box") and any(a.endswith(b"nb_client.json") for a in argv):
            try: os.kill(int(pid), 15)
            except OSError: pass

def ns_down():
    sh(f"ip netns del {NS}", check=False); sh("ip link del vh", check=False)

base = json.load(open("/root/sbbox/sbox_client.json"))
tmpl = {o["tag"]: o for o in base["outbounds"] if o.get("type") == "naive"}

def build(variants):
    outs, ins, rules = [], [], []
    for i, v in enumerate(variants):
        o = copy.deepcopy(tmpl[v["base"]])
        o["tag"] = v["name"]; o["server"] = "10.200.0.1"
        for k, val in v.get("set", {}).items(): o[k] = val
        for k in v.get("unset", []): o.pop(k, None)
        outs.append(o)
        ins.append({"type": "socks", "tag": f"in{i}", "listen": "127.0.0.1", "listen_port": 12900 + i})
        rules.append({"inbound": [f"in{i}"], "outbound": v["name"]})
    cfg = {"log": {"level": "error"}, "inbounds": ins,
           "outbounds": outs + [{"type": "direct", "tag": "direct"}],
           "route": {"rules": rules, "final": "direct"}}
    p = f"{S}/nb_client.json"; json.dump(cfg, open(p, "w"), indent=1); return p

def curl_ns(port, args):
    return sh(f"ip netns exec {NS} curl -s -o /dev/null --socks5-hostname 127.0.0.1:{port} {args}", check=False).stdout.split()

variants = json.load(open(VARFILE))
ns_up()
try:
    cfg = build(variants)
    chk = sh(f"{BIN} check -c {cfg}", check=False)
    if chk.returncode: print("CONFIG CHECK FAILED:", chk.stderr); sys.exit(1)
    p = subprocess.Popen(f"ip netns exec {NS} {BIN} run -c {cfg}", shell=True,
                         stdout=subprocess.DEVNULL, stderr=open(f"{S}/nb_client.log", "w"))
    time.sleep(5)
    ping = sh(f"ip netns exec {NS} ping -c 3 -i 0.2 -q 10.200.0.1", check=False).stdout
    rtt = re.search(r"= [\d.]+/([\d.]+)/", ping)
    print(f"\n### RTT 设定 {RTT}ms（实测 ping {rtt.group(1) if rtt else '?'}ms）  下行丢包 {LOSS}%   每项 {N}×{NEED//1000000}MB")
    print(f"{'变体':<34}{'吞吐中位':>9}{'最低':>7}{'最高':>7}{'无效':>5}{'首字节中位':>11}")
    for i, v in enumerate(variants):
        port = 12900 + i
        curl_ns(port, f"--max-time 40 -r 0-1048575 {URLS[0]}")                 # 预热建连
        lat = [float(o[1])*1000 for o in (curl_ns(port, "-w '%{http_code} %{time_starttransfer}' --max-time 10 http://www.gstatic.com/generate_204") for _ in range(8)) if len(o)==2 and o[0]=="204"]
        bw, bad = [], 0
        for k in range(N):
            o = curl_ns(port, f"-w '%{{http_code}} %{{size_download}} %{{speed_download}}' --max-time 90 -r 0-{NEED-1} {URLS[k%2]}")
            if len(o)==3 and o[0] in ("200","206") and int(o[1])>=NEED: bw.append(float(o[2])*8/1e6)
            else: bad += 1
        L = f"{statistics.median(lat):.0f}ms" if lat else "—"
        if bw: print(f"{v['name']:<34}{statistics.median(bw):>9.0f}{min(bw):>7.0f}{max(bw):>7.0f}{bad:>5}{L:>11}")
        else:  print(f"{v['name']:<34}{'全部无效':>9}{'':>14}{bad:>5}{L:>11}")
        sys.stdout.flush()
    p.terminate(); p.wait(timeout=5)
finally:
    kill_clients(); ns_down()
