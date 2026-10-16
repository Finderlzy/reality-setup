#!/usr/bin/env bash
set -euo pipefail

# 第一步：在全新的 Debian 服务器上安装 Xray，把服务器变成节点
# 主节点 VLESS + Reality（TCP 443），备用节点 Hysteria2（UDP 443）；不装面板
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/install-xray.sh)
# 之后可选：add-isp-proxy.sh（给节点套住宅 IP）、install-panel.sh（装 3x-ui 面板排查问题）
VERSION=v2.0.0       # 发新版时和 git 标签一起改；装完写进 /etc/reality-setup/version
PORT=443             # Reality 用 TCP 443，Hysteria2 用 UDP 443
HY_SNI=www.bing.com  # Hysteria2 自签证书上写的域名
XRAY_CONF=/usr/local/etc/xray/config.json
HY_CERT=/root/cert/hy2.crt HY_KEY=/root/cert/hy2.key

if [ "$(id -u)" -ne 0 ]; then echo "请用 root 用户运行"; exit 1; fi
if ! command -v apt-get >/dev/null; then
  OS=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || true)
  echo "本脚本只支持 Debian，这台服务器是 ${OS:-其他系统}。"
  echo "请在 VPS 商家后台把系统重装成 Debian 12，再运行同一条命令。"
  exit 1
fi

echo "这一步要做的：在服务器上安装 Xray，把这台服务器变成节点。"
echo "装好后，服务器会自己连一次自己的节点，确认能用，再把节点链接打印出来。"
echo

# SSH 是经这台服务器上的节点连进来的（电脑开着代理 / TUN 模式）时，源地址会是本机自己的地址，
# 一停节点 SSH 就断，脚本跟着被杀，服务器停在删了一半的状态
ssh_via_node() {
  local src=${SSH_CLIENT:-}
  src=${src%% *}
  [ -n "$src" ] && { [ "$src" = 127.0.0.1 ] || [ "$src" = ::1 ] ||
    ip -o addr | awk '{sub(/\/.*/, "", $4); print $4}' | grep -qxF "$src"; }
}

# ---- 装过的服务器：先确认（真正删除放在所有问题问完之后）----
REINSTALL=
if [ -e /etc/x-ui ] || [ -e /etc/reality-setup ] || [ -e /usr/local/bin/xray ] || [ -e /usr/local/etc/xray ]; then
  if ssh_via_node; then
    echo "你现在的 SSH 是通过这台服务器上的节点连进来的，删旧节点时 SSH 会断开、重装会中途失败。"
    echo "请先关掉电脑上的代理软件（或把 TUN / 全局模式关掉），重新 SSH 连上再运行。"
    exit 1
  fi
  if [ -e /root/vless.txt ]; then
    OLD=$(cat /etc/reality-setup/version 2>/dev/null || echo "v1.1.0 或更早")
    echo "这台服务器用本脚本装过（版本：$OLD）。"
    [ -e /etc/x-ui ] && echo "上面装的 3x-ui 面板也会一起删掉，需要的话装完再运行装面板的脚本。"
    if grep -qs '"residential"' "$XRAY_CONF" /usr/local/x-ui/bin/config.json; then
      echo "住宅代理的设置也会删掉，需要的话装完再运行加住宅代理的脚本。"
    fi
  elif [ -e /etc/x-ui ]; then
    echo "这台服务器装过 3x-ui 面板（不是本脚本装的），面板里所有节点和设置都会被删掉。"
  else
    echo "这台服务器装过 Xray（不是本脚本装的），它原来的配置会被删掉。"
  fi
  read -rp "删掉旧的重新装吗？装完旧节点链接会失效，代理软件里要重新导入 [y/N]: " ANS
  [ "$ANS" = y ] || [ "$ANS" = Y ] || { echo "已取消，什么都没动"; exit 1; }
  REINSTALL=1
fi

DETECTED=$(curl -s4 -m 10 https://api.ipify.org || true)
read -rp "服务器 IP 是 ${DETECTED:-（没检测到）} 吗？对就直接回车，不对就输入你 SSH 连接用的 IP: " IP
IP=${IP:-$DETECTED}
if [ -z "$IP" ]; then echo "服务器 IP 不能为空"; exit 1; fi

if [ -n "$REINSTALL" ]; then
  systemctl disable --now x-ui xray xray-autoupdate.timer >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/x-ui.service /etc/systemd/system/xray.service /etc/systemd/system/xray@.service \
    /etc/systemd/system/xray-autoupdate.service /etc/systemd/system/xray-autoupdate.timer
  rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d
  systemctl daemon-reload
  rm -rf /etc/x-ui /usr/local/x-ui /etc/default/x-ui /usr/bin/x-ui /etc/reality-setup \
    /usr/local/bin/xray /usr/local/etc/xray /usr/local/share/xray /var/log/xray \
    /usr/local/bin/node-selftest /usr/local/bin/xray-autoupdate /usr/local/bin/xray-fetch \
    /root/vless.txt /root/hy2.txt /root/clash.yaml /root/xray.bak "$HY_CERT" "$HY_KEY"
  if command -v ufw >/dev/null; then ufw --force delete allow 8555/tcp >/dev/null 2>&1 || true; fi  # v1.0.0 及更早用的节点端口
  echo "== 旧的已删除，开始重新安装 =="
fi

echo
echo "== 第 1 步（共 3 步）：安装 Xray =="
apt update
apt install -y curl openssl ufw python3 unattended-upgrades fail2ban python3-systemd qrencode unzip

# ---- 系统安全补丁每天自动安装（只装安全更新，不会自动重启）----
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

# ---- 下载 Xray 的小工具（安装和每周自动更新共用）----
cat > /usr/local/bin/xray-fetch <<'EOF'
#!/usr/bin/env bash
# 从 Xray 官方 GitHub 下载并安装 Xray：xray-fetch [版本号]，不写版本号就装最新的
# xray-fetch --latest 只打印最新版本号（Xray 现在的新版本在 GitHub 上都标为预发布，所以预发布也算）
set -euo pipefail
latest() {
  curl -fsS -m 60 "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=30" |
    python3 -c 'import json, sys; print("\n".join(r["tag_name"] for r in json.load(sys.stdin) if not r["draft"]))' |
    sort -V | tail -1
}
if [ "${1:-}" = --latest ]; then latest; exit; fi
case $(uname -m) in
  x86_64 | amd64) ARCH=64 ;;
  aarch64 | arm64) ARCH=arm64-v8a ;;
  *) echo "不支持这台服务器的 CPU 架构：$(uname -m)"; exit 1 ;;
esac
V=${1:-}
[ -n "$V" ] || V=$(latest || true)
[ -n "$V" ] || { echo "查不到 Xray 的最新版本（连不上 GitHub），等一会儿再试"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
URL=https://github.com/XTLS/Xray-core/releases/download/$V/Xray-linux-$ARCH.zip
curl -fsSL -m 600 -o "$T/xray.zip" "$URL"
curl -fsSL -m 60 -o "$T/xray.dgst" "$URL.dgst"
if [ "$(awk '/^SHA2-256=/ {print $2}' "$T/xray.dgst")" != "$(sha256sum "$T/xray.zip" | cut -d' ' -f1)" ]; then
  echo "下载的 Xray 文件不完整（校验对不上），等一会儿再试"; exit 1
fi
unzip -qo "$T/xray.zip" xray geoip.dat geosite.dat -d "$T/x"
"$T/x/xray" version >/dev/null
install -d /usr/local/share/xray
install -m 644 "$T/x/geoip.dat" "$T/x/geosite.dat" /usr/local/share/xray/
install -m 755 "$T/x/xray" /usr/local/bin/.xray-new
mv -f /usr/local/bin/.xray-new /usr/local/bin/xray
echo "Xray $V 已安装"
EOF
chmod 755 /usr/local/bin/xray-fetch
xray-fetch

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray（节点程序）
After=network-online.target
Wants=network-online.target

[Service]
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
ExecStart=/usr/local/bin/xray run -c $XRAY_CONF
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# ---- Hysteria2 用的自签证书（有效期 10 年）----
mkdir -p /root/cert && chmod 700 /root/cert
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -subj "/CN=$HY_SNI" -addext "subjectAltName=DNS:$HY_SNI" -keyout "$HY_KEY" -out "$HY_CERT" 2>/dev/null

# ---- 生成节点配置、节点链接和 Clash 配置 ----
mkdir -p "$(dirname "$XRAY_CONF")"
export HY_CERT HY_KEY HY_SNI IP PORT XRAY_CONF
python3 - <<'PY'
import hashlib, json, os, secrets, ssl, subprocess, urllib.parse, urllib.request, uuid

E = os.environ

# 伪装网站：先确认它满足 Reality 的要求（TLS 1.3、X25519、HTTP/2），再挑服务器连过去 TLS 握手最快的（离得近，伪装更像真的）
# 候选都是国内能正常访问的大站：伪装成被墙的网站反而会被干扰
def handshake_ms(host, strict):
    times = []
    for _ in range(3):
        cmd = ["curl", "-so", "/dev/null", "-m", "5", "--tlsv1.3", "--http2", "-w", "%{http_version} %{time_appconnect}"]
        if strict:
            cmd += ["--curves", "X25519"]
        out = subprocess.run(cmd + [f"https://{host}"], capture_output=True, text=True).stdout.split()
        if len(out) == 2 and out[0] == "2" and float(out[1]) > 0:
            times.append(float(out[1]) * 1000)
    return min(times) if times else None

CANDIDATES = ["www.microsoft.com", "www.apple.com", "www.amazon.com", "www.nvidia.com",
              "www.amd.com", "www.samsung.com", "www.cisco.com", "www.oracle.com"]
best = None
for strict in (True, False):  # 老版本 curl 不认 --curves，全部失败时去掉它再挑一次
    for host in CANDIDATES:
        ms = handshake_ms(host, strict)
        if ms is not None and (best is None or ms < best[0]):
            best = (ms, host)
    if best:
        break
if best is None:
    raise SystemExit("几个伪装网站都连不上，检查一下这台服务器能不能正常上网")
ms, host = best
print(f"伪装网站：{host}（握手 {ms:.0f} ms）")

# 节点名用服务器 IP 所在地，比如“美国 洛杉矶（主节点）”；查不到就只写“主节点”
try:
    geo = json.load(urllib.request.urlopen(f"http://ip-api.com/json/{E['IP']}?lang=zh-CN&fields=status,country,city", timeout=10))
    place = " ".join(dict.fromkeys(v for v in (geo.get("country"), geo.get("city")) if v)) if geo.get("status") == "success" else ""
except Exception:
    place = ""
MAIN_NAME, HY_NAME = f"{place}（主节点）", f"{place}（备用节点）"

# 密钥：xray x25519 输出的前两行依次是私钥、公钥（新旧版本的字段名不一样，顺序一样）
out = subprocess.run(["/usr/local/bin/xray", "x25519"], capture_output=True, text=True, check=True).stdout
priv, pub = [line.split(":", 1)[1].strip() for line in out.splitlines() if ":" in line][:2]
uid, sid, hy_auth = str(uuid.uuid4()), secrets.token_hex(4), secrets.token_urlsafe(16)
pem = open(E["HY_CERT"]).read()
pin = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()
port = int(E["PORT"])

sniffing = {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False, "routeOnly": True}
conf = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        # 主节点：VLESS + Reality，走 TCP
        {"tag": "reality", "port": port, "protocol": "vless",
         "settings": {"clients": [{"id": uid, "flow": "xtls-rprx-vision", "email": "me"}], "decryption": "none"},
         "streamSettings": {"network": "tcp", "security": "reality",
                            "realitySettings": {"show": False, "xver": 0, "target": host + ":443", "serverNames": [host],
                                                "privateKey": priv, "shortIds": [sid]}},
         "sniffing": sniffing},
        # 备用节点：Hysteria2，走 UDP，和主节点共用 443 端口号。没有域名，用自签证书，
        # 客户端靠证书指纹（pin）只认这一张证书，不需要打开“跳过证书验证”
        {"tag": "hysteria2", "port": port, "protocol": "hysteria",
         "settings": {"version": 2, "clients": [{"auth": hy_auth, "email": "me-hy2"}]},
         "streamSettings": {"network": "hysteria", "security": "tls",
                            "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60},
                            "tlsSettings": {"serverName": E["HY_SNI"], "minVersion": "1.3", "maxVersion": "1.3", "alpn": ["h3"],
                                            "certificates": [{"certificateFile": E["HY_CERT"], "keyFile": E["HY_KEY"]}]}},
         "sniffing": sniffing},
    ],
    "outbounds": [{"tag": "direct", "protocol": "freedom"}, {"tag": "blocked", "protocol": "blackhole"}],
    "routing": {"domainStrategy": "AsIs", "rules": [
        {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
        {"type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked"}]},
}
fd = os.open(E["XRAY_CONF"], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(conf, f, indent=2, ensure_ascii=False)

addr = f"[{E['IP']}]" if ":" in E["IP"] else E["IP"]
q = urllib.parse.quote
link = (f"vless://{uid}@{addr}:{port}?type=tcp&encryption=none&security=reality&pbk={pub}&fp=chrome"
        f"&sni={host}&sid={sid}&spx=%2F&flow=xtls-rprx-vision#{q(MAIN_NAME)}")
hy_link = f"hysteria2://{q(hy_auth, safe='')}@{addr}:{port}?security=tls&sni={E['HY_SNI']}&alpn=h3&pinSHA256={pin}&insecure=0#{q(HY_NAME)}"
open("/root/vless.txt", "w").write(link + "\n")
open("/root/hy2.txt", "w").write(hy_link + "\n")

# Clash 系（Clash Verge、FlClash、Clash Meta）不能直接粘贴分享链接，另外生成一份配置
s = lambda v: json.dumps(v, ensure_ascii=False)  # JSON 字符串也是合法的 YAML 字符串，省去转义的麻烦
open("/root/clash.yaml", "w").write(f"""proxies:
  - name: {s(MAIN_NAME)}
    type: vless
    server: {s(E["IP"])}
    port: {port}
    uuid: {s(uid)}
    network: tcp
    udp: true
    tls: true
    flow: "xtls-rprx-vision"
    servername: {s(host)}
    client-fingerprint: "chrome"
    reality-opts:
      public-key: {s(pub)}
      short-id: {s(sid)}
  - name: {s(HY_NAME)}
    type: hysteria2
    server: {s(E["IP"])}
    port: {port}
    password: {s(hy_auth)}
    sni: {s(E["HY_SNI"])}
    fingerprint: {s(pin)}
    alpn: [h3]
proxy-groups:
  - name: {s("节点选择")}
    type: select
    proxies: [{s(HY_NAME)}, {s(MAIN_NAME)}, DIRECT]
rules:
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
""")
PY
chmod 600 /root/vless.txt /root/hy2.txt /root/clash.yaml

# 备用节点万一用不了（配置不被这个版本的 Xray 接受、UDP 443 被占用等），去掉它，不影响主节点
drop_hy2() {
  echo "Hysteria2 备用节点没建成，跳过（主节点不受影响）"
  python3 - "$XRAY_CONF" <<'PY'
import json, re, sys
c = json.load(open(sys.argv[1]))
c["inbounds"] = [i for i in c["inbounds"] if i["protocol"] != "hysteria"]
json.dump(c, open(sys.argv[1], "w"), indent=2, ensure_ascii=False)
y = open("/root/clash.yaml").read()
y = re.sub(r"\n  - name: [^\n]*\n    type: hysteria2\n(?:    [^\n]*\n)*", "\n", y, count=1)
y = re.sub(r"proxies: \[[^,\]]*, ", "proxies: [", y)  # 节点选择里去掉备用节点
open("/root/clash.yaml", "w").write(y)
PY
  rm -f /root/hy2.txt
}
xray_test() { XRAY_LOCATION_ASSET=/usr/local/share/xray /usr/local/bin/xray run -test -c "$XRAY_CONF" >/dev/null 2>&1; }
if ! xray_test; then drop_hy2; fi
if ! xray_test; then
  XRAY_LOCATION_ASSET=/usr/local/share/xray /usr/local/bin/xray run -test -c "$XRAY_CONF" || true
  echo "Xray 不接受生成的配置，没法继续。请把上面的输出发给作者排查。"
  exit 1
fi
systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 3
if ! systemctl is-active -q xray && [ -e /root/hy2.txt ]; then
  drop_hy2
  systemctl restart xray
  sleep 3
fi
if ! systemctl is-active -q xray; then
  journalctl -u xray -n 20 --no-pager || true
  echo "Xray 没有启动起来，请把上面的输出发给作者排查。"
  exit 1
fi
mkdir -p /etc/reality-setup
echo xray > /etc/reality-setup/mode   # 节点由谁管：xray（本脚本直接管）或 panel（装了面板后交给面板管）
echo "== Xray 已装好并运行 =="

# ---- 顺手做好安全设置 ----
echo "== 顺手做好安全设置：防火墙、防暴力破解、系统自动更新、网络加速 =="
# 防火墙：只放行 SSH 和节点端口
SSH_PORT=$(ss -tlnpH | awk '/sshd/ {sub(/.*:/, "", $4); print $4; exit}')
ufw allow "${SSH_PORT:-22}"/tcp
ufw allow "$PORT"/tcp
ufw allow "$PORT"/udp
ufw --force enable

# fail2ban：10 分钟内 SSH 密码输错 5 次，封这个 IP 1 小时
cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
backend = systemd
port = ${SSH_PORT:-22}
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban || true
sleep 2
if fail2ban-client status sshd >/dev/null 2>&1; then
  F2B="已开启（10 分钟内输错 5 次密码封 1 小时）"
else
  F2B="没开成，不影响节点使用，可运行 systemctl status fail2ban 查看原因"
fi
echo "== fail2ban：$F2B =="

# BBR 网络优化（容器类 VPS 改不了内核参数，开不了就跳过，不影响节点）
modprobe tcp_bbr 2>/dev/null || true
if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
  printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > /etc/sysctl.d/99-bbr.conf
  sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1 || true
fi
if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = bbr ]; then
  BBR="已开启"
else
  BBR="没开成（多半是容器类 VPS 不允许改内核参数），不影响节点使用"
fi
echo "== BBR：$BBR =="

# ---- 自测命令：服务器自己连自己的节点（Xray 自动更新、加住宅代理、装面板也用它）----
cat > /usr/local/bin/node-selftest <<'PY'
#!/usr/bin/env python3
# 服务器自己连自己的节点（Reality 和 Hysteria2 都测）：都通了退出码 0，否则 1；
# 带 --ip 时再打印走节点访问 ipinfo.io（加了住宅代理就走住宅 IP）和其他网站的出口 IP
import glob, json, os, subprocess, sys, tempfile, time, urllib.parse
def parse(path):
    u = urllib.parse.urlparse(open(path).read().strip())
    return u, dict(urllib.parse.parse_qsl(u.query))
u, q = parse("/root/vless.txt")
reality = {"tag": "reality", "protocol": "vless", "settings": {"vnext": [{"address": "127.0.0.1", "port": u.port,
              "users": [{"id": u.username, "encryption": "none", "flow": q.get("flow", "")}]}]},
           "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
               "serverName": q["sni"], "fingerprint": q.get("fp", "chrome"), "publicKey": q["pbk"],
               "shortId": q.get("sid", ""), "spiderX": q.get("spx", "")}}}
has_hy2 = os.path.exists("/root/hy2.txt")
u, q = parse("/root/hy2.txt") if has_hy2 else (None, None)
hy2 = None if not has_hy2 else {"tag": "hy2", "protocol": "hysteria", "settings": {"address": "127.0.0.1", "port": u.port, "version": 2},
       "streamSettings": {"network": "hysteria", "security": "tls",
           "hysteriaSettings": {"version": 2, "auth": urllib.parse.unquote(u.username), "udpIdleTimeout": 60},
           "tlsSettings": {"serverName": q["sni"], "alpn": ["h3"], "pinnedPeerCertSha256": q["pinSHA256"]}}}
client = {"inbounds": [{"tag": "in-reality", "port": 10899, "listen": "127.0.0.1", "protocol": "socks"},
                       {"tag": "in-hy2", "port": 10898, "listen": "127.0.0.1", "protocol": "socks"}],
          "outbounds": [o for o in (reality, hy2) if o],
          "routing": {"rules": [{"type": "field", "inboundTag": ["in-reality"], "outboundTag": "reality"},
                                {"type": "field", "inboundTag": ["in-hy2"], "outboundTag": "hy2"}][:2 if has_hy2 else 1]}}
fd, cfg = tempfile.mkstemp(suffix=".json")
with os.fdopen(fd, "w") as f:
    json.dump(client, f)
# 自测用的客户端：优先用本脚本装的 Xray，旧版一体化脚本装的服务器上只有面板自带的
xray = "/usr/local/bin/xray" if os.path.exists("/usr/local/bin/xray") else sorted(glob.glob("/usr/local/x-ui/bin/xray-linux-*"))[0]
p = subprocess.Popen([xray, "run", "-c", cfg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2)
def via(port, url, fmt):
    return subprocess.run(["curl", "-s", "-m", "15", "-x", f"socks5h://127.0.0.1:{port}", "-o", "/dev/null" if fmt else "-",
                           "-w", fmt, url], capture_output=True, text=True).stdout.strip()
results = []
for name, port in [("Reality", 10899), ("Hysteria2", 10898)][:2 if has_hy2 else 1]:
    ok = via(port, "https://www.google.com/generate_204", "%{http_code}") == "204"
    results.append(ok)
    print(f"== 节点自测 {name}：" + ("成功" if ok else "失败") + " ==")
if results[0] and "--ip" in sys.argv:
    print("== 走节点访问 ipinfo.io 的出口 IP：" + (via(10899, "https://ipinfo.io/ip", "") or "取不到") + " ==")
    print("== 走节点访问其他网站的出口 IP：" + (via(10899, "https://api.ipify.org", "") or "取不到") + " ==")
p.terminate(); p.wait(); os.remove(cfg)
sys.exit(0 if all(results) else 1)
PY
chmod 755 /usr/local/bin/node-selftest

# ---- Xray 每周自动更新：更新后自测，不通就退回旧版本 ----
cat > /usr/local/bin/xray-autoupdate <<'EOF'
#!/usr/bin/env bash
# 检查 Xray：有新版本就更新，更新后自测不通就退回旧版本
# 节点由面板管（装了 3x-ui 面板）时，通过面板接口更新面板自带的 Xray
set -uo pipefail
MODE=$(cat /etc/reality-setup/mode 2>/dev/null || echo xray)

if [ "$MODE" = panel ]; then
  . /etc/x-ui/install-result.env
  API="http://127.0.0.1:$XUI_PANEL_PORT/$XUI_WEB_BASE_PATH/panel/api/server"
  XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* | head -1)
  CUR=v$("$XRAY" version | awk 'NR==1 {print $2}')
  # 版本列表和面板里“切换 Xray 版本”看到的一样
  NEW=$(curl -fsS -m 60 -H "Authorization: Bearer $XUI_API_TOKEN" "$API/getXrayVersion" \
    | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["obj"]))' | sort -V | tail -1)
else
  XRAY=/usr/local/bin/xray
  CUR=v$("$XRAY" version | awk 'NR==1 {print $2}')
  NEW=$(xray-fetch --latest)
fi
[ -n "$NEW" ] || { echo "查不到最新版本，下次再试"; exit 0; }
if [ "$(printf '%s\n%s\n' "$CUR" "$NEW" | sort -V | tail -1)" = "$CUR" ]; then echo "Xray $CUR 已是最新"; exit 0; fi

echo "Xray $CUR -> $NEW"
cp "$XRAY" /root/xray.bak
if [ "$MODE" = panel ]; then
  RES=$(curl -s -m 600 -X POST -H "Authorization: Bearer $XUI_API_TOKEN" "$API/installXray/$NEW")
  if ! echo "$RES" | grep -q '"success":true'; then echo "面板接口返回：$RES"; fi
else
  if ! xray-fetch "$NEW"; then echo "新版本下载失败，仍是 $CUR"; rm -f /root/xray.bak; exit 0; fi
  systemctl restart xray
fi
sleep 3
if node-selftest; then
  AFTER=v$("$XRAY" version | awk 'NR==1 {print $2}')
  if [ "$AFTER" = "$CUR" ]; then echo "没有更新成功，仍是 $CUR"; else echo "更新成功：$AFTER"; fi
  rm -f /root/xray.bak
  exit 0
fi

echo "新版本自测不通，退回 $CUR"
cp /root/xray.bak "$(dirname "$XRAY")/.xray-restore" && mv -f "$(dirname "$XRAY")/.xray-restore" "$XRAY"
if [ "$MODE" = panel ]; then
  curl -s -m 60 -X POST -H "Authorization: Bearer $XUI_API_TOKEN" "$API/restartXrayService" >/dev/null
else
  systemctl restart xray
fi
sleep 3
node-selftest
exit 1
EOF
chmod 755 /usr/local/bin/xray-autoupdate
cat > /etc/systemd/system/xray-autoupdate.service <<'EOF'
[Unit]
Description=Xray 自动更新（更新后自测，不通就回滚）
After=network-online.target xray.service x-ui.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xray-autoupdate
EOF
cat > /etc/systemd/system/xray-autoupdate.timer <<'EOF'
[Unit]
Description=每周检查一次 Xray 新版本

[Timer]
OnCalendar=Sun 04:00
RandomizedDelaySec=2h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now xray-autoupdate.timer >/dev/null 2>&1 || true

echo "$VERSION" > /etc/reality-setup/version

echo
echo "== 第 2 步（共 3 步）：自测（服务器自己连一次自己的节点）=="
sleep 2
if node-selftest; then
  echo "== 自测通过：节点能用 =="
elif node-selftest >/dev/null 2>&1; then
  echo "== 第二次自测通过：节点能用 =="
else
  echo "== 自测没有全部通过 =="
  echo "主节点（Reality）失败的话，节点多半用不了：请把上面的全部输出发给作者排查。"
  echo "只有备用节点（Hysteria2）失败的话，主节点照样能用。"
fi

echo
echo "== 第 3 步（共 3 步）：打印节点链接 =="
echo
echo "===== 装好了（版本 $VERSION）====="
echo "这台服务器现在是你的节点了。下面的节点链接就是连接这个节点要用的东西。"
echo
echo "【主节点 Reality】复制下面这行导入代理软件（也存在 /root/vless.txt），手机可以直接扫码："
cat /root/vless.txt
qrencode -t ANSIUTF8 -m 2 < /root/vless.txt
echo
if [ -f /root/hy2.txt ]; then
  echo "【备用节点 Hysteria2】主节点连不上或晚高峰很慢时用（也存在 /root/hy2.txt）："
  cat /root/hy2.txt
  qrencode -t ANSIUTF8 -m 2 < /root/hy2.txt
  echo
fi
echo "用 Clash 系软件（Clash Verge、FlClash、Clash Meta）的：运行 cat /root/clash.yaml，复制全部内容，"
echo "  在软件里新建一个本地配置，把内容粘贴进去保存（节点都在里面）"
echo "想再看二维码：qrencode -t ANSIUTF8 < /root/vless.txt"
echo
echo "下一步：把上面的节点链接导入代理软件。"
echo "注意：节点链接就像钥匙，谁拿到谁就能用你的节点。不要发给别人，也不要截图发到网上或群里。"
echo
echo "商家后台有防火墙 / 安全组的话，放行 TCP 443 和 UDP 443"
echo
echo "顺手做好的安全设置："
echo "  BBR 网络加速：$BBR"
echo "  系统安全更新：已设为每天自动安装"
echo "  Xray：每周日自动检查更新，更新后自测不通会自动退回旧版本（日志：journalctl -u xray-autoupdate）"
echo "  SSH 防暴力破解（fail2ban）：$F2B"
echo "    自己被误封了：换个网络连上去，运行 fail2ban-client set sshd unbanip 你的IP"
