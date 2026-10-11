# reality-setup

一行命令在全新 VPS 上搭好 VLESS + Reality 节点（3x-ui 面板），附带一个 Hysteria2 备用节点，可选给节点套上住宅 IP。

配套教程：[如何订阅claude（纯操作版）](https://finderlzy.github.io/Writing/tech/subscribe-claude-quick/)

## 用法

用 root 登录一台**全新**的 Debian / Ubuntu 服务器，运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/main/setup.sh)
```

想固定用某个版本（不跟随 `main` 的最新改动），把链接里的 `main` 换成版本号，所有版本见[版本列表](https://github.com/Finderlzy/reality-setup/tags)：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Finderlzy/reality-setup/v1.0.0/setup.sh)
```

按提示确认服务器 IP；有住宅代理就填它的 IP、端口、用户名、密码，没有就直接回车跳过。几分钟后看到 `节点自测 Reality：成功` 和 `节点自测 Hysteria2：成功`，最后会打印两个节点：

| 节点 | 用途 | 链接保存在 |
|---|---|---|
| Reality（主节点） | 日常使用，走 TCP 443 | `/root/vless.txt` |
| Hysteria2（备用节点） | 主节点连不上或晚高峰很慢时用，走 UDP 443 | `/root/hy2.txt` |

- **v2rayN、Shadowrocket、Hiddify 等**：复制链接导入，手机可以直接扫打印出来的二维码。想再看二维码：`qrencode -t ANSIUTF8 < /root/vless.txt`
- **Clash 系（Clash Verge、FlClash、Clash Meta）**：不能直接粘贴分享链接。运行 `cat /root/clash.yaml`，复制全部内容，在软件里新建一个本地配置粘贴进去。两个节点都在里面，默认选中 Hysteria2（见下方「已知问题」）

商家后台有防火墙 / 安全组的话，放行 **TCP 443 和 UDP 443**。

## 脚本做了什么

1. 安装 [3x-ui](https://github.com/MHSanaei/3x-ui) v3.9.0，面板只监听 `127.0.0.1`，外网访问不到，只能用 SSH 隧道打开
2. 通过面板接口创建 VLESS + Reality 入站（TCP 443），伪装网站从几个大站里挑可用且离服务器最近（握手最快）的
3. 创建 Hysteria2 备用入站（UDP 443），用自签证书加证书指纹固定，客户端不需要打开“跳过证书验证”；万一建不成会跳过，不影响主节点
4. 填了住宅代理时：先测试代理是否可用，再添加住宅出站，只让 Anthropic 相关域名走住宅 IP
5. 防火墙（ufw）只放行 SSH 端口和节点端口
6. fail2ban 防 SSH 暴力破解：10 分钟内输错 5 次密码封 1 小时
7. 开启系统安全更新每天自动安装
8. 开启 BBR 网络优化
9. Xray 内核每周日自动检查更新，更新后自测不通会自动退回旧版本
10. 服务器自己连自己的两个节点做一次自测（之后随时可以运行 `node-selftest` 再测），装完打印链接和二维码

## 注意

- 只支持 Debian / Ubuntu，只能在没装过 3x-ui 的服务器上运行
- 3x-ui 面板本身不会自动更新，需要时运行 `x-ui` 用菜单更新
- Xray 自动更新的记录：`journalctl -u xray-autoupdate`；想立刻检查一次：`xray-autoupdate`
- 建议 SSH 改用密钥登录并关闭密码登录
- 面板账号密码忘了：`cat /etc/x-ui/install-result.env`
- 被 fail2ban 误封：换个网络连上去，运行 `fail2ban-client set sshd unbanip 你的IP`

## 已知问题

- 本地测试中，Clash（mihomo 内核）连 Reality 节点报 `REALITY authentication failed`，同样的参数用 Xray 客户端可以连通，原因还在排查。所以 Clash 配置默认选中 Hysteria2；v2rayN 等 Xray 内核的软件用 Reality 不受影响
- 新版 Xray 会提示“用 www.microsoft.com 这类热门网站做伪装目标更容易被墙”，伪装网站的候选列表之后会调整

## 免责声明

本脚本仅供学习和技术交流。请遵守你所在地区的法律法规，自行判断使用是否合规，并自行承担由此产生的风险和后果。
