# reality-setup

一行命令在全新 VPS 上搭好 VLESS + Reality 节点（3x-ui 面板），可选给节点套上住宅 IP。

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

按提示确认服务器 IP；有住宅代理就填它的 IP、端口、用户名、密码，没有就直接回车跳过。几分钟后看到 `节点自测：成功`，复制打印出来的 `vless://` 链接导入代理软件即可（链接也存在 `/root/vless.txt`）。

Clash 系软件（Clash Verge、FlClash、Clash Meta）不能直接粘贴 `vless://` 链接。脚本另外生成了 `/root/clash.yaml`：运行 `cat /root/clash.yaml`，复制全部内容，在软件里新建一个本地配置粘贴进去即可。

商家后台有防火墙 / 安全组的话，放行 **TCP 8555**。

## 脚本做了什么

1. 安装 [3x-ui](https://github.com/MHSanaei/3x-ui) v3.9.0，面板只监听 `127.0.0.1`，外网访问不到，只能用 SSH 隧道打开
2. 通过面板接口创建 VLESS + Reality 入站，伪装网站自动扫描挑选
3. 填了住宅代理时：先测试代理是否可用，再添加住宅出站，只让 Anthropic 相关域名走住宅 IP
4. 防火墙（ufw）只放行 SSH 端口和节点端口
5. fail2ban 防 SSH 暴力破解：10 分钟内输错 5 次密码封 1 小时
6. 开启系统安全更新每天自动安装
7. 开启 BBR 网络优化
8. Xray 内核每周日自动检查更新，更新后自测不通会自动退回旧版本
9. 服务器自己连自己的节点做一次自测（之后随时可以运行 `node-selftest` 再测）

## 注意

- 只支持 Debian / Ubuntu，只能在没装过 3x-ui 的服务器上运行
- 3x-ui 面板本身不会自动更新，需要时运行 `x-ui` 用菜单更新
- Xray 自动更新的记录：`journalctl -u xray-autoupdate`；想立刻检查一次：`xray-autoupdate`
- 建议 SSH 改用密钥登录并关闭密码登录
- 面板账号密码忘了：`cat /etc/x-ui/install-result.env`
- 被 fail2ban 误封：换个网络连上去，运行 `fail2ban-client set sshd unbanip 你的IP`

## 免责声明

本脚本仅供学习和技术交流。请遵守你所在地区的法律法规，自行判断使用是否合规，并自行承担由此产生的风险和后果。
