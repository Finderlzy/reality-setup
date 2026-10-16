# reality-setup

在全新 VPS 上搭好 VLESS + Reality 节点（附带一个 Hysteria2 备用节点），分三步、每步一行命令：

| 步骤 | 脚本 | 做什么 |
|---|---|---|
| 1. 把服务器变成节点 | `install-xray.sh` | 安装 Xray，建好节点，自测后打印节点链接 |
| 2. 加住宅 IP（可选） | `add-isp-proxy.sh` | 给节点套住宅 / ISP 代理，运行时选只让 claude 相关的网站走，还是所有网站都走 |
| 3. 装面板（可选） | `install-panel.sh` | 安装 3x-ui 面板用来排查问题，节点原样交给面板管理，链接不变 |

第 2、3 步都要求先跑过第 1 步，两者先后随意。

配套教程：[如何订阅claude（纯操作版）](https://finderlzy.github.io/Writing/tech/subscribe-claude-quick/)

> 旧的一体化脚本 `setup.sh`（装 3x-ui 面板 + 节点 + 可选住宅代理一次做完）保留不动，已有教程链接的是 [v1.2.1 的 setup.sh](https://raw.githubusercontent.com/Finderlzy/reality-setup/v1.2.1/setup.sh)。新装请用上面的分步脚本。用分步脚本装过的服务器不能再运行 `setup.sh`（它会提示改用 `install-xray.sh`）。

## 第 1 步：把服务器变成节点

用 root 登录一台**全新**的 Debian 12 服务器，运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/install-xray.sh)
```

想固定用某个版本（不跟随 `main` 的最新改动），把链接里的 `main` 换成版本号，所有版本见[版本列表](https://github.com/Finderlzy/reality-setup/tags)。

按提示确认服务器 IP。脚本分三步走：`安装 Xray` → `自测（服务器自己连一次自己的节点）` → `打印节点链接`。看到 `节点自测 Reality：成功`、`节点自测 Hysteria2：成功` 和 `自测通过：节点能用`，最后会打印两个节点，节点名是服务器所在地，比如 `美国 洛杉矶（主节点）`（查不到所在地就只写 `（主节点）`）：

| 节点 | 用途 | 链接保存在 |
|---|---|---|
| VLESS + Reality（主节点） | 日常使用，走 TCP 443 | `/root/vless.txt` |
| Hysteria2（备用节点） | 主节点连不上或晚高峰很慢时用，走 UDP 443 | `/root/hy2.txt` |

Hysteria2 万一建不成（这个版本的 Xray 不接受、UDP 443 被占用等）会跳过，不影响主节点，只是最后只打印主节点。

- **v2rayN、Shadowrocket、Hiddify 等**：复制链接导入，手机可以直接扫打印出来的二维码。想再看二维码：`qrencode -t ANSIUTF8 < /root/vless.txt`（备用节点把 `vless.txt` 换成 `hy2.txt`）
- **Clash 系（Clash Verge、FlClash、Clash Meta）**：不能直接粘贴分享链接。运行 `cat /root/clash.yaml`，复制全部内容，在软件里新建一个本地配置粘贴进去。默认选中 Hysteria2（见下方「已知问题」）

节点链接就像钥匙，谁拿到谁就能用你的节点，不要发给别人。商家后台有防火墙 / 安全组的话，放行 **TCP 443 和 UDP 443**。

## 第 2 步（可选）：给节点套住宅 IP

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/add-isp-proxy.sh)
```

填住宅 / ISP 代理的 IP、端口、用户名、密码（只支持 SOCKS5；没有用户名就直接回车），再选哪些网站走住宅 IP：

- **1（默认）**：只让 Anthropic 相关域名（`geosite:anthropic`，包括 claude.ai、anthropic.com 等）和用来查出口 IP 的 `ipinfo.io` 走住宅 IP，其他网站照旧从服务器出去
- **2**：所有网站都走住宅 IP（路由规则放在最后，局域网地址和 BT 下载仍然直接拦掉）

脚本先测代理能不能连上，不通就什么都不改；通了再给 Xray 加一个住宅出站和对应的路由规则。改完自测，成功时会打印 `住宅 IP 加好了`，并列出出口 IP；改完节点连不上就自动退回原来的设置。装了面板的，改的是面板里的 Xray 设置。

节点链接不变，不用重新导入。想换别的住宅代理，或者改选走住宅 IP 的范围，再运行一次同一条命令，旧的会被替换。用旧的 `setup.sh` 装的服务器也能运行这一步。

## 第 3 步（可选）：装 3x-ui 面板排查问题

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/install-panel.sh)
```

安装 [3x-ui](https://github.com/MHSanaei/3x-ui) v3.9.0，然后把第 1 步建的节点**原样**交给面板管理：UUID、密钥、shortId、伪装网站、Hysteria2 证书和密码、住宅代理都照搬，所以节点链接不变，代理软件里不用重新导入。交接时节点会断几秒；交接后自测不通（交接前通的节点交接后不通）就自动退回由 Xray 直接管理，面板不启用。

- 面板只监听 `127.0.0.1`，外网访问不到：在自己电脑上运行 `ssh -L 8080:127.0.0.1:8080 root@服务器IP`，浏览器打开 `http://127.0.0.1:8080/panel`，用户名 `admin`，密码 `123456`（只能走 SSH 隧道，所以用了好记的固定账号）
- 装了面板以后，在面板里改节点会立刻生效；`/usr/local/etc/xray/config.json` 不再使用，`xray.service` 不再开机启动
- 3x-ui 面板固定安装 v3.9.0，本身不会自动更新。需要时可以运行 `x-ui` 用菜单更新，但脚本只在 v3.9.0 上测试过，新版本面板的接口变了的话，Xray 自动更新可能会失效

## 已经装过，想换成新版本

运行第 1 步的命令。脚本发现装过（本脚本装的、旧的 `setup.sh` 装的、别人装的 3x-ui 或 Xray）会先问你，回答 `y` 就删掉旧的（面板、节点、住宅代理设置、自动更新任务等）重新装，回答其他的什么都不动。重装后节点链接会变，客户端要重新导入；需要住宅 IP 或面板的，重装后再运行第 2、3 步。

**重装、加住宅代理、装面板之前，先关掉电脑上的代理软件（或关掉 TUN / 全局模式）再 SSH 连服务器。** 这几步都会停一下或重启节点，如果 SSH 是走这台服务器上的节点连进去的，会跟着断；脚本会检查出这种情况并提示你，不会往下做。

每个版本改了什么、装过的要不要重装，见 [CHANGELOG](CHANGELOG.md)。看服务器装的是哪个版本：`cat /etc/reality-setup/version`；节点现在由谁管：`cat /etc/reality-setup/mode`（`xray` 或 `panel`）。

## 第 1 步的脚本做了什么

1. 从 Xray 官方 GitHub 下载最新版 Xray（校验 SHA-256），装成 `xray.service`，配置在 `/usr/local/etc/xray/config.json`
2. 建 VLESS + Reality 入站（TCP 443，流控 `xtls-rprx-vision`），伪装网站从几个大站里挑满足要求（TLS 1.3、X25519、HTTP/2）且离服务器最近（握手最快）的
3. 建 Hysteria2 备用入站（UDP 443），用自签证书加证书指纹固定，客户端不需要打开“跳过证书验证”
4. 防火墙（ufw）只放行 SSH 端口和节点端口（TCP 443、UDP 443）
5. fail2ban 防 SSH 暴力破解：10 分钟内输错 5 次密码封 1 小时
6. 开启系统安全更新每天自动安装
7. 开启 BBR 网络优化（容器类 VPS 不允许改内核参数，开不了会跳过，不影响节点）
8. Xray 每周日凌晨 4 点到 6 点（服务器时间）之间自动检查更新，更新后自测不通会自动退回旧版本（装了面板后改为通过面板更新面板里的 Xray）
9. 服务器自己连自己的两个节点做一次自测（之后随时可以运行 `node-selftest` 再测；`node-selftest --ip` 还会打印走节点访问 `ipinfo.io` 和其他网站的出口 IP，用来确认住宅 IP 生效），最后打印链接和二维码

## 注意

- 只支持 Debian 12，x86_64 或 arm64
- Xray 自动更新的记录：`journalctl -u xray-autoupdate`；想立刻检查一次：`xray-autoupdate`
- 建议 SSH 改用密钥登录并关闭密码登录
- 被 fail2ban 误封：换个网络连上去，运行 `fail2ban-client set sshd unbanip 你的IP`

## 已知问题

- 本地测试中，Clash（mihomo 内核）连 Reality 节点报 `REALITY authentication failed`，同样的参数用 Xray 客户端可以连通，原因还在排查。所以 Clash 配置默认选中 Hysteria2；v2rayN 等 Xray 内核的软件用 Reality 不受影响
- 新版 Xray 会提示“用 www.microsoft.com 这类热门网站做伪装目标更容易被墙”，伪装网站的候选列表之后会调整
- 分步脚本（v1.3.0）还没有在真实服务器上完整跑过，见 CHANGELOG

## 免责声明

本脚本仅供学习和技术交流。请遵守你所在地区的法律法规，自行判断使用是否合规，并自行承担由此产生的风险和后果。
