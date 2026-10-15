#!/usr/bin/env bash
set -euo pipefail

# 第二步：给节点加上住宅 / ISP 代理，只让 claude 相关的网站（Anthropic 的域名，以及用来查出口 IP 的 ipinfo.io）
# 从住宅 IP 出去，其他网站照旧从服务器自己的 IP 出去。要求先运行过 install-xray.sh
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/add-isp-proxy.sh)
# 再运行一次可以换成别的住宅代理（旧的会被替换）
XRAY_CONF=/usr/local/etc/xray/config.json

if [ "$(id -u)" -ne 0 ]; then echo "请用 root 用户运行"; exit 1; fi
if ! command -v apt-get >/dev/null; then
  OS=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || true)
  echo "本脚本只支持 Debian / Ubuntu，这台服务器是 ${OS:-其他系统}。"
  echo "请在 VPS 商家后台把系统重装成 Debian 12（或 Ubuntu 22.04 / 24.04），再按教程从装 Xray 那一步开始。"
  exit 1
fi

# ---- 先确认装过节点：install-xray.sh 装的（xray / panel 两种），或旧的一体化脚本 setup.sh 装的（等同 panel）----
MODE=$(cat /etc/reality-setup/mode 2>/dev/null || true)
if [ -z "$MODE" ] && [ -e /etc/x-ui/install-result.env ] && [ -e /root/vless.txt ]; then MODE=panel; fi
if [ ! -e /root/vless.txt ] || ! command -v node-selftest >/dev/null ||
  { [ "$MODE" = xray ] && [ ! -e "$XRAY_CONF" ]; } || { [ "$MODE" != xray ] && [ "$MODE" != panel ]; }; then
  echo "这台服务器上没找到装好的节点。"
  echo "请先运行教程上一步的命令安装 Xray（install-xray.sh），把服务器变成节点，再运行这个脚本。"
  exit 1
fi

# 改完要重启 Xray：SSH 如果是经这台服务器上的节点连进来的，会跟着断，看不到结果
SRC=${SSH_CLIENT:-}
SRC=${SRC%% *}
if [ -n "$SRC" ] && { [ "$SRC" = 127.0.0.1 ] || [ "$SRC" = ::1 ] || ip -o addr | awk '{sub(/\/.*/, "", $4); print $4}' | grep -qxF "$SRC"; }; then
  echo "你现在的 SSH 是通过这台服务器上的节点连进来的，改完重启节点时 SSH 会断开。"
  echo "请先关掉电脑上的代理软件（或把 TUN / 全局模式关掉），重新 SSH 连上再运行。"
  exit 1
fi

IP=$(python3 -c 'import urllib.parse; print(urllib.parse.urlparse(open("/root/vless.txt").read().strip()).hostname)')

echo "这一步要做的：给节点加上住宅 IP。"
echo "加好之后，只有 claude 相关的网站会从住宅 IP 出去，其他网站照旧从服务器自己的 IP 出去。"
echo "住宅代理的信息在商家后台能找到。"
echo
read -rp "住宅代理 IP（或域名）: " RES_IP
read -rp "住宅代理端口: " RES_PORT
read -rp "住宅代理用户名（没有就直接回车）: " RES_USER
RES_PASS=
if [ -n "$RES_USER" ]; then read -rp "住宅代理密码: " RES_PASS; fi
if [ -z "$RES_IP" ] || ! [[ "$RES_PORT" =~ ^[0-9]+$ ]]; then echo "IP 和端口不能为空，端口只能是数字"; exit 1; fi

# ---- 先测住宅代理，不通就什么都不改 ----
echo
echo "== 第 1 步（共 3 步）：测试住宅代理能不能连上 =="
AUTH=()
if [ -n "$RES_USER" ]; then AUTH=(--proxy-user "$RES_USER:$RES_PASS"); fi
RES_OUT=$(curl -s -m 15 --socks5-hostname "$RES_IP:$RES_PORT" "${AUTH[@]}" https://ipinfo.io/ip || true)
if [ -z "$RES_OUT" ]; then
  echo "住宅代理连不上，什么都没改。去商家后台检查：端口、用户名密码、IP 白名单（把 $IP 加进去）、套餐是否生效。"
  echo "注意：本脚本只支持 SOCKS5 协议的住宅代理。"
  exit 1
fi
echo "住宅代理能用，它的出口 IP：$RES_OUT"

echo
echo "== 第 2 步（共 3 步）：让 claude 相关的网站走住宅 IP =="
export RES_IP RES_PORT RES_USER RES_PASS
# 改配置的小程序：xray 模式直接改配置文件，面板模式通过面板接口改（面板里“Xray 设置”的出站和路由）
EDIT_PY=$(mktemp)
cat > "$EDIT_PY" <<'PY'
import json, os, sys, urllib.parse, urllib.request
E = os.environ
out = {"tag": "residential", "protocol": "socks", "settings": {"servers": [{"address": E["RES_IP"], "port": int(E["RES_PORT"])}]}}
if E["RES_USER"]:
    out["settings"]["servers"][0]["users"] = [{"user": E["RES_USER"], "pass": E["RES_PASS"]}]
rule = {"type": "field", "outboundTag": "residential", "domain": ["geosite:anthropic", "domain:ipinfo.io"]}

def apply(x, rule_at):
    if any(o.get("tag") == "residential" for o in x["outbounds"]):
        print("原来的住宅代理会替换成这次填的")
    x["outbounds"] = [o for o in x["outbounds"] if o.get("tag") != "residential"] + [out]
    x["routing"]["rules"] = [r for r in x["routing"]["rules"] if r.get("outboundTag") != "residential"]
    x["routing"]["rules"].insert(rule_at, rule)

def api(path, form=None):
    req = urllib.request.Request(E["B"] + path, headers={"Authorization": "Bearer " + E["XUI_API_TOKEN"]},
                                 data=None if form is None else urllib.parse.urlencode(form).encode(),
                                 method="POST" if form is not None or path.endswith("/") else "GET")
    res = json.load(urllib.request.urlopen(req, timeout=120))
    if not res.get("success"):
        raise SystemExit(f"面板接口出错：{path} {res.get('msg')}")
    return res["obj"]

action = sys.argv[1]
if action == "file":      # file 旧配置 新配置
    x = json.load(open(sys.argv[2]))
    apply(x, 0)
    json.dump(x, open(sys.argv[3], "w"), indent=2, ensure_ascii=False)
elif action == "panel":
    x = json.loads(api("/panel/api/xray/"))["xraySetting"]
    open("/etc/reality-setup/xray-setting.bak", "w").write(json.dumps(x))
    apply(x, 1)  # 第 0 条是面板自己的接口规则
    api("/panel/api/xray/update", form={"xraySetting": json.dumps(x)})
    api("/panel/api/server/restartXrayService", form={})
elif action == "panel-restore":
    api("/panel/api/xray/update", form={"xraySetting": open("/etc/reality-setup/xray-setting.bak").read()})
    api("/panel/api/server/restartXrayService", form={})
PY

if [ "$MODE" = xray ]; then
  NEW=$(mktemp)
  python3 "$EDIT_PY" file "$XRAY_CONF" "$NEW"
  if ! XRAY_LOCATION_ASSET=/usr/local/share/xray /usr/local/bin/xray run -test -c "$NEW" >/dev/null 2>&1; then
    XRAY_LOCATION_ASSET=/usr/local/share/xray /usr/local/bin/xray run -test -c "$NEW" || true
    rm -f "$NEW" "$EDIT_PY"
    echo "Xray 不接受改好的配置，什么都没改。请把上面的输出发给作者排查。"
    exit 1
  fi
  cp "$XRAY_CONF" "$XRAY_CONF.bak"
  install -m 600 "$NEW" "$XRAY_CONF"
  rm -f "$NEW"
  systemctl restart xray
  restore() {
    cp "$XRAY_CONF.bak" "$XRAY_CONF"
    systemctl restart xray
  }
else
  . /etc/x-ui/install-result.env
  export B="http://127.0.0.1:$XUI_PANEL_PORT/$XUI_WEB_BASE_PATH" XUI_API_TOKEN
  mkdir -p /etc/reality-setup
  python3 "$EDIT_PY" panel
  restore() { python3 "$EDIT_PY" panel-restore || true; }
fi
sleep 3

echo
echo "== 第 3 步（共 3 步）：自测（服务器自己连一次自己的节点，看看出口 IP 对不对）=="
ST=$(node-selftest --ip || true)
echo "$ST"
if ! grep -q "节点自测 Reality：成功" <<<"$ST"; then
  echo "加上住宅代理后节点连不上了，正在退回原来的设置……"
  restore
  sleep 3
  node-selftest || true
  rm -f "$EDIT_PY"
  echo "已经退回原来的设置（不走住宅 IP）。请把上面的全部输出发给作者排查。"
  exit 1
fi
rm -f "$EDIT_PY"
CLAUDE_IP=$(sed -n 's/^== 走节点访问 ipinfo.io 的出口 IP：\(.*\) ==$/\1/p' <<<"$ST")
OTHER_IP=$(sed -n 's/^== 走节点访问其他网站的出口 IP：\(.*\) ==$/\1/p' <<<"$ST")

echo
if [ -n "$CLAUDE_IP" ] && [ "$CLAUDE_IP" != 取不到 ] && [ "$CLAUDE_IP" != "$OTHER_IP" ]; then
  echo "===== 住宅 IP 加好了 ====="
  echo "claude 相关的网站现在从住宅 IP（$CLAUDE_IP）出去，其他网站照旧从服务器的 IP（$OTHER_IP）出去。"
else
  echo "===== 住宅代理已经加上，但没确认到效果 ====="
  echo "走节点访问 ipinfo.io 的出口 IP 是 ${CLAUDE_IP:-取不到}，按理应该是住宅 IP（$RES_OUT）。"
  echo "可以过几分钟运行 node-selftest --ip 再看一次；还不对就把上面的全部输出发给作者排查。"
fi
echo "代理软件里的节点不用重新导入，节点链接没有变。"
echo "想换别的住宅代理，再运行一次同一条命令。"
