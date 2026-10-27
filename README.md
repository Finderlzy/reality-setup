# reality-setup

一行命令在全新 VPS 上搭好 VLESS + Reality 节点（3x-ui 面板），附带一个 Hysteria2 备用节点，可选给节点套上住宅 IP。

配套教程：[如何订阅claude（纯操作版）](https://finderlzy.github.io/Writing/tech/subscribe-claude-quick/)

## 用法

用 root 登录一台**全新**的 Debian 服务器（建议 Debian 12），运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/setup.sh)
```

想固定用某个版本（不跟随 `main` 的最新改动），把链接里的 `main` 换成版本号，所有版本见[版本列表](https://github.com/Finderlzy/reality-setup/tags)：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/v2.0.0/setup.sh)
```

按提示确认服务器 IP；有住宅代理就填它的 IP、端口、用户名、密码，没有就直接回车跳过。几分钟后（Debian 11 会先自动升级到 Debian 12，多等 5～15 分钟）看到 `节点自测 Reality：成功` 和 `节点自测 Hysteria2：成功`，最后会打印两个节点，节点名是服务器所在地，比如 `美国 洛杉矶（主节点）`（查不到所在地就只写 `（主节点）`）：

| 节点 | 用途 | 链接保存在 |
|---|---|---|
| VLESS + Reality（主节点） | 日常使用，走 TCP 443 | `/root/vless.txt` |
| Hysteria2（备用节点） | 主节点连不上或晚高峰很慢时用，走 UDP 443 | `/root/hy2.txt` |

Hysteria2 万一没建成会跳过，不影响主节点，只是最后只打印主节点，也没有 Hysteria2 的自测结果。

- **v2rayN、Shadowrocket、Hiddify 等**：复制链接导入，手机可以直接扫打印出来的二维码。想再看二维码：`qrencode -t ANSIUTF8 < /root/vless.txt`（备用节点把 `vless.txt` 换成 `hy2.txt`）
- **Clash 系（Clash Verge、FlClash、Clash Meta）**：不能直接粘贴分享链接。运行 `cat /root/clash.yaml`，复制全部内容，在软件里新建一个本地配置粘贴进去。两个节点都在里面（Hysteria2 没建成时只有主节点），默认自动选择走得快的那个（见下方「Clash 开着代理上网慢」）。主节点能不能用取决于客户端版本和指纹，见下方「已知问题」

商家后台有防火墙 / 安全组的话，放行 **TCP 443 和 UDP 443**。

## 用 Clash 连不上主节点（Reality）

现象：在 Clash 系软件里切到主节点，测延迟很慢或者一直超时、网页打不开；同一个节点的 `vless://` 链接在 v2rayN、Shadowrocket 这类 Xray 内核的软件里却正常。

原因在两端对 Reality 的默认行为不一样。Xray 从 **v26.9.8** 起，服务端只认 TLS 握手带 `X25519MLKEM768` 密钥交换的客户端，没带的不当作 Reality，直接当普通网页转发（表现就是连不上、一直转圈）；而 mihomo 内核默认不带，要显式打开。

脚本生成的 `/root/clash.yaml` 已经写好了这一行：

```yaml
    reality-opts:
      public-key: "你原来的公钥"
      short-id: "你原来的 Short ID"
      support-x25519mlkem768: true
```

已经装好节点的服务器，不用重装，自己在 `/root/clash.yaml` 里加上 `support-x25519mlkem768: true` 这一行（在 `short-id` 下面）再重新导入即可。

还有两个限制，加完这一行仍然要满足：

- **指纹要用 `chrome`。** 这一行只是允许，真正发不发 ML-KEM 由指纹决定。实测 mihomo v1.19.33 里 `chrome` 会发，`firefox`、`safari` 即使写了这一行也不发，一样连不上。脚本建节点时固定用 `chrome`，配置里的 `client-fingerprint` 就是这个，不要改。
- **客户端要够新。** mihomo 官方（[wiki](https://wiki.metacubex.one/config/proxies/tls/#reality-opts)）写明不考虑兼容 Xray v26.7.11 及更新版本的 Reality；很老的 Clash 客户端（按 mihomo issue #3326 的说法，v1.19.33 之前可能一直没真正支持）仍然连不上，升级 Clash 客户端试试。

实在不行就在「节点选择」里手动切到 Hysteria2 备用节点。

## Clash 开着代理上网慢

现象：用 Clash 系软件（Clash Verge、FlClash、Clash Meta，内核是 mihomo）开着代理上网，每打开一个新网站都要先顿一下；国内网站也慢。同一个节点在 v2rayN 这类 Xray 内核的软件里不会。

原因有三个，按影响从大到小：

1. **配置里没有 `dns` 段，规则又只用 IP 匹配。** 老的 `/root/clash.yaml` 只有 `GEOIP,CN,DIRECT` 这种按 IP 的规则（还没有 `no-resolve`），所以每访问一个新域名，都要先用系统（运营商）DNS 把这个域名解析成 IP 才能判断走不走节点。境外域名的解析经常又慢又可能被污染，表现就是网页先卡一下才打开。新版配置加了 `dns` 段（fake-ip 模式，用阿里、腾讯的 DoH 解析），规则改成先按域名分流（`GEOSITE`）、再按 IP 分流且不解析（`no-resolve`），国内域名和境外域名在本地就直接分开了。
2. **默认选中 Hysteria2。** Hysteria2 走 UDP，国内运营商在晚高峰经常对 UDP 限速或丢包，测出来时快时慢。新版默认用「自动选择」，由客户端按延迟自动挑节点：UDP 被限速时自动换到走 TCP 的 Reality。
3. **地理库（geoip、geosite）从 GitHub 下载。** 国内经常失败或者很慢。新版把下载地址改成 jsdelivr 的镜像。

### 已经装好的怎么处理

不用重装，节点和服务端都没动。在服务器上运行 `cat /root/clash.yaml`，按下面的方式改完再重新导入（在 Clash 系软件里新建一个本地配置，粘贴进去保存）：

- **`proxies:` 这一段（两个节点的名字、密码、公钥等）原样不动。**
- 在配置最开头（`proxies:` 之前）加上全局设置和 `dns` 段：

```yaml
mixed-port: 7890
mode: rule
log-level: warning
unified-delay: true
tcp-concurrent: true
find-process-mode: "off"
geodata-mode: true
geo-auto-update: false
geox-url:
  geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country-lite.mmdb"
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter: ["*.lan", "+.local", "+.msftconnecttest.com", "+.msftncsi.com"]
  default-nameserver: [223.5.5.5, 119.29.29.29]
  nameserver: ["https://223.5.5.5/dns-query", "https://doh.pub/dns-query"]
  proxy-server-nameserver: ["https://223.5.5.5/dns-query"]
```

- 把末尾的 `proxy-groups:` 和 `rules:` 整段换成下面的。**节点名要和 `proxies:` 里的名字一字不差**（脚本按服务器所在地取名，比如 `美国 洛杉矶（主节点）`、`美国 洛杉矶（备用节点）`）；没有 Hysteria2 备用节点的，把两个列表里带「备用节点」的那一项删掉：

```yaml
proxy-groups:
  - name: "节点选择"
    type: select
    proxies: ["自动选择", "美国 洛杉矶（主节点）", "美国 洛杉矶（备用节点）", DIRECT]
  - name: "自动选择"
    type: url-test
    url: "https://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
    proxies: ["美国 洛杉矶（主节点）", "美国 洛杉矶（备用节点）"]
rules:
  - GEOSITE,private,DIRECT
  - GEOSITE,cn,DIRECT
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT,no-resolve
  - MATCH,节点选择
```

**先别改配置的话**：在软件里把「节点选择」手动切到主节点（Reality，走 TCP）通常就能明显变快，因为主要卡顿来自 UDP 被限速的 Hysteria2。客户端要够新，否则主节点连不上，见上面「用 Clash 连不上主节点（Reality）」。

## 已经装过，想换成新版本

运行同一条命令。脚本发现装过会先问你，回答 `y` 就删掉旧的（面板、节点、自动更新任务等）重新装，回答其他的什么都不动。如果面板不是本脚本装的，面板里你自己建的所有节点和设置也会一起删掉。重装后节点链接会变，客户端要重新导入。

**重装前先关掉电脑上的代理软件（或关掉 TUN / 全局模式）再 SSH 连服务器。** 如果 SSH 是走这台服务器上的节点连进去的，删旧节点时 SSH 会跟着断；脚本会检查出这种情况并提示你，不会往下删。安装途中 SSH 因为别的原因断了，重新连上再运行一次同一条命令就行。

每个版本改了什么、装过的要不要重装，见 [CHANGELOG](CHANGELOG.md)。看服务器装的是哪个版本：`cat /etc/reality-setup/version`（v1.1.0 及更早的版本没有这个文件）。

## 脚本做了什么

1. 检查系统：不是 Debian 就提示重装成 Debian 12 后退出；Debian 11 及更老把软件源换成存档源 `archive.debian.org`，Debian 11 再原地升级到 Debian 12（见下方「Debian 11 原地升级到 12」）
2. 安装 [3x-ui](https://github.com/MHSanaei/3x-ui) v3.9.0，面板只监听 `127.0.0.1`，外网访问不到，只能用 SSH 隧道打开
3. 通过面板接口创建 VLESS + Reality 入站（TCP 443，流控 `xtls-rprx-vision`），伪装网站从几个大站里挑可用且离服务器最近（握手最快）的
4. 创建 Hysteria2 备用入站（UDP 443），用自签证书加证书指纹固定，客户端不需要打开“跳过证书验证”；万一建不成会跳过，不影响主节点
5. 另外生成一份 Clash 配置 `/root/clash.yaml`：两个节点做成「节点选择」（默认「自动选择」，按延迟自动挑节点），自带 `dns` 段（fake-ip，DoH 解析）和按域名分流的规则，地理库从 jsdelivr 下载
6. 填了住宅代理时：装面板之前先测试代理，不通就直接退出；通了再添加住宅出站，只让 Anthropic 相关域名（以及用来查出口 IP 的 `ipinfo.io`）走住宅 IP
7. 防火墙（ufw）只放行 SSH 端口和节点端口（TCP 443、UDP 443）
8. fail2ban 防 SSH 暴力破解：10 分钟内输错 5 次密码封 1 小时
9. 开启系统安全更新每天自动安装（没能升级的 Debian 11 及更老的系统官方不再出安全更新，这一项没有实际效果）
10. 开启 BBR 网络优化（容器类 VPS 不允许改内核参数，开不了会跳过，不影响节点）
11. Xray 内核每周日凌晨 4 点到 6 点（服务器时间）之间自动检查更新，更新后自测不通会自动退回旧版本
12. 服务器自己连自己的两个节点做一次自测（之后随时可以运行 `node-selftest` 再测；填了住宅代理时，还会打印走节点访问的出口 IP，用来确认住宅 IP 生效），装完打印链接和二维码

## 注意

- 只支持 Debian，Ubuntu 等其他系统会提示去商家后台重装成 Debian 12（Ubuntu 有些命令和 Debian 不一样，照着跑容易出岔子）。建议用全新的服务器；装过 3x-ui 的服务器也能运行，但会先删掉旧面板（见上方「已经装过，想换成新版本」）
- Debian 11 及更老的系统官方已停止支持，原来的软件源会报 404。脚本会自动把源换成存档源 `archive.debian.org`（原来的备份在 `/etc/apt/sources.list.bak-reality-setup`），Debian 11 还会先自动原地升级到 Debian 12 再装节点（见下面「Debian 11 原地升级到 12」）
- 3x-ui 面板固定安装 v3.9.0，本身不会自动更新。需要时可以运行 `x-ui` 用菜单更新，但脚本只在 v3.9.0 上测试过，新版本面板的接口变了的话，Xray 自动更新可能会失效
- Xray 自动更新的记录：`journalctl -u xray-autoupdate`；想立刻检查一次：`xray-autoupdate`
- 建议 SSH 改用密钥登录并关闭密码登录
- 面板（排查用）：在自己电脑上运行 `ssh -L 8080:127.0.0.1:8080 root@服务器IP`（SSH 端口不是 22 的，加上 `-p 端口`），浏览器打开 `http://127.0.0.1:8080/panel`，用户名 `admin`，密码 `123456`。面板只监听本机，外网访问不到，所以用了好记的固定账号
- 被 fail2ban 误封：换个网络连上去，运行 `fail2ban-client set sshd unbanip 你的IP`

## Debian 11 原地升级到 12

商家只提供 Debian 11、没法重装成 12 时，**脚本会先自动把系统升级到 Debian 12**，升完接着装节点，多花 5～15 分钟。升级时不弹对话框，改过的配置（比如 SSH 端口）都保留。装完找个方便的时候 `reboot` 一次，让新内核生效。

以下情况脚本不升级，只把软件源换成存档源后照常装节点：容器类 VPS（OpenVZ、LXC，内核由商家管，升完可能开不了机）、硬盘剩余不到 2 GB。这两种情况系统不会再有安全更新。

建议升级前在商家后台做个快照，并确认后台的 VNC 网页控制台能打开，万一 SSH 连不上可以从那里进。

**已经装好节点、只想升级系统的**，可以手动升（节点不受影响）：

1. 运行 `systemd-detect-virt`：输出 `openvz` 或 `lxc` 的别升
2. 先把 Debian 11 更新到最新。系统很久没更新的话，软件源的钥匙里还没有 Debian 12 的，跳过这步直接换源会报 `NO_PUBKEY`：

   ```bash
   cat > /etc/apt/sources.list <<'EOF'
   deb http://archive.debian.org/debian bullseye main contrib non-free
   deb http://archive.debian.org/debian bullseye-updates main contrib non-free
   deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
   EOF
   apt update && apt full-upgrade -y
   ```

3. 换成 Debian 12 的源并升级：

   ```bash
   cat > /etc/apt/sources.list <<'EOF'
   deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
   deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
   deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
   EOF
   apt update && apt full-upgrade -y
   ```

   中途问要不要替换配置文件，直接回车（保留现在的，尤其是 `sshd_config`，换了 SSH 端口可能变回 22）；问要不要自动重启服务，选 Yes
4. `reboot`，重启后 `cat /etc/debian_version` 显示 `12.x` 就好了

想用得更久，之后可以用同样的方法升到 Debian 13（把 `bookworm` 换成 `trixie`）。不能从 11 直接跳到 13。

## 已知问题

- Clash 系软件连主节点（Reality）有额外要求：配置里要有 `support-x25519mlkem768: true`（脚本生成的 `/root/clash.yaml` 已经带上），客户端要够新，指纹要带 ML-KEM 的 `chrome`。原因和排查见上面「用 Clash 连不上主节点」。所以 Clash 配置默认用「自动选择」，Reality 连不上时自动落到 Hysteria2；v2rayN 等 Xray 内核的软件用 Reality 不受影响。另外，用旧配置时开着代理上网慢，原因和处理见上面「Clash 开着代理上网慢」
- 装完打印的面板 SSH 隧道命令没带 SSH 端口。SSH 端口不是 22 的服务器，照着运行会连不上，要自己加上 `-p 端口`
- Reality 节点的 SNI 用的是面板扫描伪装网站后得到的第一个域名，可能带前缀（比如挑中 `www.amazon.com`，链接里却是 `test-www.amazon.com`）。自测能通过，不影响使用
- 新版 Xray 会提示“用 www.microsoft.com 这类热门网站做伪装目标更容易被墙”，伪装网站的候选列表之后会调整

## 免责声明

本脚本仅供学习和技术交流。请遵守你所在地区的法律法规，自行判断使用是否合规，并自行承担由此产生的风险和后果。
