# reality-setup

把一台全新的 Debian 12 VPS 变成自己的翻墙节点：主节点 VLESS + Reality，附带一个 Hysteria2 备用节点；需要的话再给节点套上住宅 IP、装一个 3x-ui 面板。每一步都只要一行命令，改完会自测，不通就自动退回。

配套教程：[如何订阅claude（纯操作版）](https://finderlzy.github.io/Writing/tech/subscribe-claude-quick/)

## 快速开始

用 root 登录服务器，按顺序运行（第 2、3 步可选，先后随意，但都要先跑过第 1 步）：

| 步骤 | 命令 | 做什么 |
|---|---|---|
| 1. 装 Xray | `bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/install-xray.sh)` | 安装 Xray、建好两个节点、自测、打印节点链接 |
| 2. 套住宅 IP | `bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/add-isp-proxy.sh)` | 让 claude 相关网站（或所有网站）从住宅 / ISP 代理出去 |
| 3. 装面板 | `bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/install-panel.sh)` | 装 3x-ui 面板方便排查，节点原样交给面板，链接不变 |

想固定某个版本（不跟随 `main` 的最新改动），把链接里的 `main` 换成版本号，比如 `v2.0.0`，所有版本见[版本列表](https://github.com/Finderlzy/reality-setup/tags)。

**要求**：Debian 12（x86_64 或 arm64），root 用户。其他系统脚本一开始就会提示去商家后台重装系统，什么都不动。

**运行任何一步之前，先关掉电脑上的代理软件（或关掉 TUN / 全局模式）再 SSH 连服务器。** 这几步都会重启节点，SSH 如果正是走这台服务器的节点连进来的，会跟着断。脚本发现这种情况会提示你，不会往下做。

## 第 1 步：装 Xray，把服务器变成节点

运行后先确认服务器 IP（检测到的对就直接回车），之后脚本分三段：`安装 Xray` → `自测（服务器自己连一次自己的节点）` → `打印节点链接`。看到 `自测通过：节点能用` 就成了，最后打印两个节点和二维码，节点名是服务器所在地，比如 `美国 洛杉矶（主节点）`：

| 节点 | 用途 | 链接保存在 |
|---|---|---|
| VLESS + Reality（主节点） | 日常使用，TCP 443 | `/root/vless.txt` |
| Hysteria2（备用节点） | 主节点连不上或晚高峰很慢时用，UDP 443 | `/root/hy2.txt` |

Hysteria2 万一建不成（Xray 版本不接受、UDP 443 被占用等）会自动跳过，只打印主节点，不影响使用。

导入代理软件：

- **v2rayN、Shadowrocket、Hiddify 等**：复制链接导入，手机直接扫码。想再看二维码：`qrencode -t ANSIUTF8 < /root/vless.txt`（备用节点换成 `hy2.txt`）
- **Clash 系（Clash Verge、FlClash、Clash Meta）**：不能直接粘贴分享链接。运行 `cat /root/clash.yaml`，复制全部内容，在软件里新建本地配置粘贴进去。默认选中 Hysteria2（见[已知问题](#已知问题)）

节点链接就像钥匙，谁拿到谁就能用你的节点，不要发给别人。商家后台有防火墙 / 安全组的话，放行 **TCP 443 和 UDP 443**。

<details>
<summary>这一步具体做了什么</summary>

1. 从 Xray 官方 GitHub 下载最新版（校验 SHA-256），装成 `xray.service`，配置在 `/usr/local/etc/xray/config.json`
2. 建 VLESS + Reality 入站（TCP 443，流控 `xtls-rprx-vision`）。伪装网站从几个国内能正常访问的大站里挑：先确认满足 Reality 的要求（TLS 1.3、X25519、HTTP/2），再选握手最快（离服务器最近）的
3. 建 Hysteria2 入站（UDP 443），用自签证书加证书指纹固定，客户端不用打开“跳过证书验证”
4. 防火墙（ufw）只放行 SSH 端口和 TCP / UDP 443
5. fail2ban 防 SSH 暴力破解：10 分钟内输错 5 次密码封 1 小时
6. 系统安全更新每天自动安装（不会自动重启）
7. 开启 BBR（容器类 VPS 不允许改内核参数，开不了就跳过）
8. Xray 每周日凌晨 4～6 点（服务器时间）自动检查更新，更新后自测不通就退回旧版本
9. 装好自测命令 `node-selftest`，自测一次，打印链接和二维码

</details>

## 第 2 步（可选）：给节点套住宅 IP

依次填住宅 / ISP 代理的 IP（或域名）、端口、用户名、密码（只支持 **SOCKS5**；IP 白名单认证没有用户名，直接回车），再选哪些网站走住宅 IP：

| 选项 | 走住宅 IP 的 | 适合 |
|---|---|---|
| **1（默认）** | Anthropic 相关域名（`geosite:anthropic`，包括 claude.ai、anthropic.com 等），以及用来查出口 IP 的 `ipinfo.io` | 只为用 claude，省住宅代理流量，其他网站网速不受影响 |
| **2** | 所有网站（局域网地址和 BT 下载仍然直接拦掉） | 希望所有网站看到的都是住宅 IP |

脚本先测住宅代理能不能连上，不通就什么都不改；通了才给 Xray 加住宅出站和路由规则。改完自测并对比出口 IP，成功会打印 `住宅 IP 加好了`；改完节点连不上就自动退回原来的设置。

- 节点链接不变，代理软件里不用重新导入
- 想换住宅代理、或改选 1 / 2，再运行一次同一条命令，旧的会被替换
- 装了面板的，改的是面板里的 Xray 设置；旧版 `setup.sh` 装的服务器也能运行这一步
- 之后随时可以运行 `node-selftest --ip` 看出口 IP

## 第 3 步（可选）：装 3x-ui 面板排查问题

安装 [3x-ui](https://github.com/MHSanaei/3x-ui) v3.9.0，然后把第 1 步建的节点**原样**交给面板管理：UUID、密钥、shortId、伪装网站、Hysteria2 证书和密码、住宅代理都照搬，节点链接不变。交接时节点会断几秒；交接前通的节点交接后不通，就自动退回由 Xray 直接管理，面板不启用。

打开面板（面板只监听 `127.0.0.1`，外网访问不到，只能走 SSH 隧道，所以用了好记的固定账号）：

1. 在自己电脑上运行 `ssh -L 8080:127.0.0.1:8080 root@服务器IP`
2. 浏览器打开 `http://127.0.0.1:8080/panel`
3. 用户名 `admin`，密码 `123456`

注意：

- 在面板里改节点会立刻生效，改坏了节点就连不上。只是排查问题的话，看看就好
- 装了面板以后，`/usr/local/etc/xray/config.json` 不再使用，`xray.service` 不再开机启动，Xray 自动更新改为通过面板更新面板里的 Xray
- 面板本身固定 v3.9.0、不自动更新。可以运行 `x-ui` 用菜单更新，但脚本只在 v3.9.0 上测试过，新版面板接口变了的话 Xray 自动更新可能失效

## 装好以后

| 想做什么 | 命令 |
|---|---|
| 测一下节点通不通 | `node-selftest` |
| 看走节点的出口 IP（确认住宅 IP 生效） | `node-selftest --ip` |
| 再看一次节点链接 / 二维码 | `cat /root/vless.txt`、`qrencode -t ANSIUTF8 < /root/vless.txt` |
| 立刻检查一次 Xray 更新 | `xray-autoupdate` |
| 看 Xray 自动更新的记录 | `journalctl -u xray-autoupdate` |
| 看装的是哪个版本 | `cat /etc/reality-setup/version` |
| 看节点现在由谁管 | `cat /etc/reality-setup/mode`（`xray` 或 `panel`） |
| 被 fail2ban 误封了 | 换个网络连上去，运行 `fail2ban-client set sshd unbanip 你的IP` |

建议 SSH 改用密钥登录并关闭密码登录。

## 重装 / 换成新版本

运行第 1 步的命令。脚本发现装过（本脚本装的、旧的 `setup.sh` 装的、别人装的 3x-ui 或 Xray）会先说明要删什么并问你，回答 `y` 才会删掉旧的（面板、节点、住宅代理设置、自动更新任务等）重新装，其他回答什么都不动。所有问题都问完才开始删。

重装后节点链接会变，代理软件要重新导入；需要住宅 IP 或面板的，重装后再运行第 2、3 步。每个版本改了什么、装过的要不要重装，见 [CHANGELOG](CHANGELOG.md)。

## 旧的一体化脚本 setup.sh

v1.x 的 `setup.sh` 一次装好 3x-ui 面板 + 节点 + 可选住宅代理，现在保留不动、不再更新，已有教程链接的是 [v1.2.1 的 setup.sh](https://raw.githubusercontent.com/Finderlzy/reality-setup/v1.2.1/setup.sh)。新装请用上面的分步脚本。

- `setup.sh` 装的服务器可以直接运行第 2 步加住宅代理；运行第 3 步会提示面板已经装好
- 用分步脚本装过的服务器不能再运行 `setup.sh`（它会提示改用 `install-xray.sh`）

## 已知问题

- 本地测试中，Clash（mihomo 内核）连 Reality 节点报 `REALITY authentication failed`，同样的参数用 Xray 客户端可以连通，原因还在排查。所以 Clash 配置默认选中 Hysteria2；v2rayN 等 Xray 内核的软件用 Reality 不受影响
- 新版 Xray 会提示“用 www.microsoft.com 这类热门网站做伪装目标更容易被墙”，伪装网站的候选列表之后会调整
- 分步脚本还没有在真实服务器上完整跑过

## 免责声明

本脚本仅供学习和技术交流。请遵守你所在地区的法律法规，自行判断使用是否合规，并自行承担由此产生的风险和后果。
