# reality-setup

一行命令在全新 VPS 上搭好 VLESS + Reality 节点（3x-ui 面板），附带一个 Hysteria2 备用节点，可选给节点套上住宅 IP。只支持 Debian。

## 用法

用 root 登录一台**全新**的 Debian 服务器（建议 Debian 12），运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/setup.sh)
```

按提示确认服务器 IP；有住宅代理就填 IP、端口、用户名、密码，没有就直接回车。几分钟后（Debian 11 会先自动升级到 12，多等 5～15 分钟）会打印两个节点，节点名是服务器所在地，比如 `美国 洛杉矶（主节点）`：

| 节点 | 用途 | 链接保存在 |
|---|---|---|
| VLESS + Reality（主节点） | 日常使用，走 TCP 443 | `/root/vless.txt` |
| Hysteria2（备用节点） | 走 UDP 443，没建成时只有主节点 | `/root/hy2.txt` |

复制链接导入 v2rayN、Shadowrocket、Hiddify 等客户端，手机扫打印出来的二维码。再看二维码：`qrencode -t ANSIUTF8 < /root/vless.txt`

Clash 系（Clash Verge、FlClash、Clash Meta）不能直接粘贴分享链接：运行 `cat /root/clash.yaml`，复制全部内容，在软件里新建一个本地配置粘贴进去，默认自动选节点。

商家后台有防火墙 / 安全组的话，放行 **TCP 443 和 UDP 443**。想固定用某个版本，把命令里的 `main` 换成版本号，见[版本列表](https://github.com/Finderlzy/reality-setup/tags)。

## 已经装过的

运行同一条命令，脚本会先问你：回答 `y` 删掉旧的（面板、节点、自动更新任务）重新装，回答别的什么都不动；节点链接会变，客户端要重新导入。**重装前先关掉电脑上的代理软件再 SSH**，否则删旧节点时 SSH 会断（脚本会检查出来并停下）。每个版本改了什么见 [CHANGELOG](CHANGELOG.md)，装的版本：`cat /etc/reality-setup/version`。

## 服务器上的东西

- 面板只监听本机，要用 SSH 隧道：`ssh -L 8080:127.0.0.1:8080 root@服务器IP`（SSH 端口不是 22 的加 `-p 端口`），浏览器开 `http://127.0.0.1:8080/panel`，账号 `admin`，密码 `123456`。面板固定装 3x-ui v3.9.0，不自动更新
- 面板里自己建的节点和设置，脚本不会保留（重装时会一起删掉）
- 开了 BBR、fail2ban（10 分钟内输错 5 次密码封 1 小时，误封了换个网络运行 `fail2ban-client set sshd unbanip 你的IP`）、每天自动装系统安全更新
- Xray 内核每周日自动检查更新，更新后自测不通会自动退回旧版本：`journalctl -u xray-autoupdate`；想立刻查一次：`xray-autoupdate`
- 随时可以再自测节点：`node-selftest`
- 建议用 SSH 密钥登录并关掉密码登录

## 系统与已知问题

- Ubuntu 等其他系统会直接提示去商家后台重装成 Debian 12，什么都不动
- Debian 11 会被自动原地升级到 Debian 12（容器类 VPS 和硬盘剩余不到 2 GB 的只换存档源、不升级）。商家不能重装、想自己升的：运行 `systemd-detect-virt`，输出不是 openvz / lxc 就可以升级，步骤见[之前版本](https://github.com/Finderlzy/reality-setup/blob/v2.0.1/README.md#debian-11-%E5%8E%9F%E5%9C%B0%E5%8D%87%E7%BA%A7%E5%88%B0-12)
- 装完打印的面板隧道命令没带 SSH 端口，端口不是 22 的自己加 `-p 端口`
- Reality 节点的 SNI 可能带前缀（比如挑中 `www.amazon.com`，链接里却是 `test-www.amazon.com`），自测能通过，不影响使用
- 新版 Xray 会提示热门网站做伪装目标更容易被墙，候选列表之后会调整

## 免责声明

本脚本仅供学习和技术交流。请遵守你所在地区的法律法规，自行判断使用是否合规，并自行承担由此产生的风险和后果。
