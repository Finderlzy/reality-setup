#!/usr/bin/env bash
set -euo pipefail

# 第三步（可选）：安装 3x-ui 面板，用来排查问题。要求先运行过 install-xray.sh
# 面板装好后，把 install-xray.sh 建的节点原样交给面板管理（密钥、端口、住宅代理都不变，节点链接不用重新导入）；
# 交接后自测不通就自动退回原来的样子
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/install-panel.sh)
XUI_VERSION=v3.9.0
PANEL_PORT=8080
# 面板固定账号，方便排查（面板只监听本机，外网访问不到，只能走 SSH 隧道）
PANEL_PATH=panel PANEL_USER=admin PANEL_PASS=123456
XRAY_CONF=/usr/local/etc/xray/config.json

if [ "$(id -u)" -ne 0 ]; then echo "请用 root 用户运行"; exit 1; fi
if ! command -v apt-get >/dev/null; then
  OS=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || true)
  echo "本脚本只支持 Debian / Ubuntu，这台服务器是 ${OS:-其他系统}。"
  echo "请在 VPS 商家后台把系统重装成 Debian 12（或 Ubuntu 22.04 / 24.04），再按教程从装 Xray 那一步开始。"
  exit 1
fi

panel_info() {
  . /etc/x-ui/install-result.env
  local ip
  ip=$(python3 -c 'import urllib.parse; print(urllib.parse.urlparse(open("/root/vless.txt").read().strip()).hostname)' 2>/dev/null || echo 服务器IP)
  echo "打开面板（面板只能通过 SSH 隧道打开，外网访问不到）："
  echo "  1. 在自己电脑上运行：ssh -L $XUI_PANEL_PORT:127.0.0.1:$XUI_PANEL_PORT root@$ip"
  echo "  2. 浏览器打开：http://127.0.0.1:$XUI_PANEL_PORT/$XUI_WEB_BASE_PATH"
  echo "  3. 用户名：$XUI_USERNAME  密码：$XUI_PASSWORD"
  echo "  忘了的话运行：cat /etc/x-ui/install-result.env"
}

# ---- 先确认装过节点 ----
MODE=$(cat /etc/reality-setup/mode 2>/dev/null || true)
if [ -z "$MODE" ] && [ -e /etc/x-ui/install-result.env ] && [ -e /root/vless.txt ]; then
  echo "这台服务器是用旧的一体化脚本（setup.sh）装的，面板已经装好了，不用再运行这个脚本。"
  panel_info
  exit 0
fi
if [ "$MODE" = panel ]; then
  echo "这台服务器已经装好面板了。"
  panel_info
  exit 0
fi
if [ "$MODE" != xray ] || [ ! -e "$XRAY_CONF" ] || [ ! -e /root/vless.txt ] || ! command -v node-selftest >/dev/null; then
  echo "这台服务器上没找到装好的节点。"
  echo "请先运行教程里安装 Xray 的那条命令（install-xray.sh），把服务器变成节点，再运行这个脚本。"
  exit 1
fi

# 交接时要停一下节点：SSH 如果是经这台服务器上的节点连进来的，会跟着断，脚本被中途杀掉
SRC=${SSH_CLIENT:-}
SRC=${SRC%% *}
if [ -n "$SRC" ] && { [ "$SRC" = 127.0.0.1 ] || [ "$SRC" = ::1 ] || ip -o addr | awk '{sub(/\/.*/, "", $4); print $4}' | grep -qxF "$SRC"; }; then
  echo "你现在的 SSH 是通过这台服务器上的节点连进来的，装面板时节点会停一下，SSH 会断开、安装会中途失败。"
  echo "请先关掉电脑上的代理软件（或把 TUN / 全局模式关掉），重新 SSH 连上再运行。"
  exit 1
fi

echo "这一步要做的：安装 3x-ui 面板，以后可以在网页上看节点的状态、排查问题。"
echo "装好后，原来的节点会交给面板管理，节点链接不变，代理软件里不用重新导入。"
echo

IP=$(python3 -c 'import urllib.parse; print(urllib.parse.urlparse(open("/root/vless.txt").read().strip()).hostname)')

# 上次装到一半失败留下的面板（节点已经退回给 Xray 管）：先删掉再装
if [ -e /etc/x-ui ] || [ -e /usr/local/x-ui ]; then
  systemctl disable --now x-ui >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/x-ui.service
  systemctl daemon-reload
  rm -rf /etc/x-ui /usr/local/x-ui /etc/default/x-ui /usr/bin/x-ui
fi

# 先自测一次，记下交接前哪些节点是通的，交接后要一样通
echo "== 第 1 步（共 3 步）：先确认节点现在是好的 =="
BEFORE=$(node-selftest || true)
echo "$BEFORE"
if ! grep -q "节点自测 Reality：成功" <<<"$BEFORE"; then
  echo "节点现在就连不上，先不装面板。可以运行 systemctl status xray 查看原因，或把上面的输出发给作者排查。"
  exit 1
fi

echo
echo "== 第 2 步（共 3 步）：安装 3x-ui 面板 =="
# 面板只监听本机，用 SSH 隧道访问。装好后面板会带一个自己的 Xray，先不放节点，不会和现在的 Xray 抢 443 端口
XUI_NONINTERACTIVE=1 XUI_PANEL_PORT=$PANEL_PORT XUI_WEB_BASE_PATH=$PANEL_PATH XUI_USERNAME=$PANEL_USER XUI_PASSWORD=$PANEL_PASS XUI_SSL_MODE=none XUI_SERVER_IP=$IP XUI_ENABLE_FAIL2BAN=false \
  bash <(curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/$XUI_VERSION/install.sh") "$XUI_VERSION" </dev/null
/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1 >/dev/null
systemctl restart x-ui
. /etc/x-ui/install-result.env
B="http://127.0.0.1:$PANEL_PORT/$XUI_WEB_BASE_PATH"
for _ in $(seq 1 30); do curl -s -o /dev/null "$B/" && break; sleep 1; done

echo
echo "== 第 3 步（共 3 步）：把节点交给面板管理，再自测一次 =="
rollback() {
  echo "交给面板管理没成功，正在把节点退回原来的样子……"
  systemctl disable --now x-ui >/dev/null 2>&1 || true
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray
  sleep 3
  node-selftest || true
  echo "节点已经退回装面板之前的样子，链接不变，可以照常用。"
  echo "面板没装成，请把上面的全部输出发给作者排查。再运行一次同一条命令会重新装面板。"
  exit 1
}

# 面板的 Xray 要用 443 端口，先停掉原来的（从这里到面板接手，节点会断几秒）
systemctl stop xray
export B XUI_API_TOKEN XRAY_CONF
if ! python3 - <<'PY'
import json, os, urllib.parse, urllib.request
E = os.environ
def api(path, form=None, body=None):
    data, headers = None, {"Authorization": "Bearer " + E["XUI_API_TOKEN"]}
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
    elif body is not None:
        data, headers["Content-Type"] = json.dumps(body).encode(), "application/json"
    req = urllib.request.Request(E["B"] + path, data=data, headers=headers, method="POST" if data is not None or path.endswith("/") else "GET")
    res = json.load(urllib.request.urlopen(req, timeout=120))
    if not res.get("success"):
        raise SystemExit(f"面板接口出错：{path} {res.get('msg')}")
    return res["obj"]

def link(path):
    u = urllib.parse.urlparse(open(path).read().strip())
    return u, dict(urllib.parse.parse_qsl(u.query)), urllib.parse.unquote(u.fragment)

conf = json.load(open(E["XRAY_CONF"]))
sniffing = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False, "routeOnly": True})
def add_inbound(remark, ib, settings, stream, ip):
    stream["externalProxy"] = [{"forceTls": "same", "dest": ip, "port": ib["port"], "remark": ""}]
    api("/panel/api/inbounds/add", body={"up": 0, "down": 0, "total": 0, "remark": remark, "enable": True,
                                         "expiryTime": 0, "listen": "", "port": ib["port"], "protocol": ib["protocol"],
                                         "settings": json.dumps(settings), "streamSettings": json.dumps(stream),
                                         "sniffing": sniffing})
def client(c):
    return {"limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": 0, "subId": os.urandom(8).hex(), "reset": 0,
            "comment": "", **c}

for ib in conf["inbounds"]:
    st = ib["streamSettings"]
    if ib["protocol"] == "vless":
        # 主节点：密钥、UUID、shortId、伪装网站都用原来的，链接不变
        u, q, name = link("/root/vless.txt")
        rs = st["realitySettings"]
        add_inbound(name, ib, {"clients": [client(c) for c in ib["settings"]["clients"]], "decryption": "none", "fallbacks": []},
                    {"network": "tcp", "security": "reality",
                     "realitySettings": {"show": False, "xver": 0, "target": rs["target"], "serverNames": rs["serverNames"],
                                         "privateKey": rs["privateKey"], "minClientVer": "", "maxClientVer": "",
                                         "maxTimediff": 0, "shortIds": rs["shortIds"],
                                         "settings": {"publicKey": q["pbk"], "fingerprint": q.get("fp", "chrome"),
                                                      "serverName": "", "spiderX": "/"}},
                     "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}}}, u.hostname)
        print(f"主节点已交给面板：{name}")
    elif ib["protocol"] == "hysteria":
        u, q, name = link("/root/hy2.txt")
        tls = st["tlsSettings"]
        cert = tls["certificates"][0]
        add_inbound(name, ib, {"version": 2, "clients": [client(c) for c in ib["settings"]["clients"]]},
                    {"network": "hysteria", "security": "tls",
                     "hysteriaSettings": {"version": 2, "auth": "", "udpIdleTimeout": st["hysteriaSettings"].get("udpIdleTimeout", 60)},
                     "tlsSettings": {"serverName": tls["serverName"], "minVersion": "1.3", "maxVersion": "1.3", "cipherSuites": "",
                                     "rejectUnknownSni": False, "disableSystemRoot": False, "enableSessionResumption": False,
                                     "certificates": [{"certificateFile": cert["certificateFile"], "keyFile": cert["keyFile"],
                                                       "ocspStapling": 0, "oneTimeLoading": False, "usage": "encipherment",
                                                       "buildChain": False}],
                                     "alpn": ["h3"], "echServerKeys": "",
                                     "settings": {"fingerprint": "", "echConfigList": "", "pinnedPeerCertSha256": [q["pinSHA256"]],
                                                  "verifyPeerCertByName": ""}}}, u.hostname)
        print(f"备用节点已交给面板：{name}")

# 住宅代理（运行过 add-isp-proxy.sh 的话）：出站和分流规则原样搬到面板的 Xray 设置里
res_out = [o for o in conf["outbounds"] if o.get("tag") == "residential"]
if res_out:
    x = json.loads(api("/panel/api/xray/"))["xraySetting"]
    x["outbounds"] = [o for o in x["outbounds"] if o.get("tag") != "residential"] + res_out
    rules = [r for r in conf["routing"]["rules"] if r.get("outboundTag") == "residential"]
    x["routing"]["rules"][1:1] = rules  # 第 0 条是面板自己的接口规则
    api("/panel/api/xray/update", form={"xraySetting": json.dumps(x)})
    print("住宅代理已交给面板")
api("/panel/api/server/restartXrayService", form={})
PY
then
  rollback
fi
sleep 3
AFTER=$(node-selftest || true)
echo "$AFTER"
for name in Reality Hysteria2; do
  if grep -q "节点自测 $name：成功" <<<"$BEFORE" && ! grep -q "节点自测 $name：成功" <<<"$AFTER"; then rollback; fi
done

# 交接成功：原来的 Xray 不再开机启动（程序留着给自测用），之后节点由面板管，Xray 自动更新也改走面板
systemctl disable xray >/dev/null 2>&1 || true
echo panel > /etc/reality-setup/mode

echo
echo "===== 面板装好了（3x-ui $XUI_VERSION）====="
echo "节点已经交给面板管理，节点链接没有变，代理软件里不用重新导入。"
echo
panel_info
echo
echo "注意："
echo "  在面板里改节点会立刻生效，改坏了节点就连不上。只是排查问题的话，看看就好，不要随手改。"
echo "  面板账号是固定的，所以面板只开在服务器本机，只能用上面的 SSH 隧道打开。"
echo "  Xray 仍然每周自动检查更新，现在改为通过面板更新面板里的 Xray。"
