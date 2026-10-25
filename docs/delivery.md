# 交付记录

## 未发布：修复 Clash 系软件连不上 Reality 主节点（2026-10-25）

**基线**：`74f2602`（v2.0.0）。

**范围**：只改生成的 `/root/clash.yaml` 里 Reality 节点的 `reality-opts`（新增 `support-x25519mlkem768: true`），以及 README「已知问题」和 CHANGELOG。不改编链接、不改编自测、不改面板版本。

**根因**：Xray 从 v26.9.8 起（[XTLS/Xray-core#6873](https://github.com/XTLS/Xray-core/issues/6873)、vendored `XTLS/reality@8cdf7bf`）服务端要求 ClientHello 的 key_share 里必须有 `X25519MLKEM768`，否则不当作 Reality，直接走回落（表现为连接超时/被放行为普通 TLS）。mihomo 的 `support-x25519mlkem768` 默认 false，需显式打开（[mihomo #3241](https://github.com/MetaCubeX/mihomo/issues/3241)、[mihomo wiki](https://wiki.metacubex.one/config/proxies/tls/)），3x-ui v3.9.0 自己的 Clash 订阅生成也是写 `true`（`internal/sub/clash_service.go`）。

实机验证时另外确认了两件此前没写进 README 的事实：

- 打开这一行还不够，客户端指纹必须本身带 ML-KEM。实测 mihomo v1.19.33：`chrome` + `true` 才会在 key_share 里发 `X25519MLKEM768`，`firefox`、`safari` 即使写了 `true` 也不发。脚本的 `client-fingerprint` 取分享链接里的 `fp`（脚本建入站时固定写 `chrome`），默认正好可用。
- Xray 在 v26.7.11 起把服务端默认 `minClientVer` 设为 26.3.27，mihomo 上报的 ClientVer 是 `1.8.2`，会被拒；这个默认值在 **v26.9.9** 被注释掉，所以「Xray v26.9.8 及更新」这个分界同时覆盖了「需要 ML-KEM」和「不再卡 minClientVer」两件事。

### 验收结果

| 场景 | 验证方式 | 结果 |
| --- | --- | --- |
| 生成逻辑覆盖全部分支（带/不带 Hysteria2 × 有/无 `sid`） | 从 `setup.sh` 抽出生成段，用模拟的 3x-ui v3.9.0 链接格式执行，四种组合都用 PyYAML 解析并断言 | 通过：`support-x25519mlkem768` 均为布尔 `true`，`reality-opts` 只有三个键，Hysteria2 仍在 `proxies` 下且默认选中项不变 |
| 真实客户端接受生成的配置 | mihomo v1.19.33 `-t` 校验（真实生成的 keypair） | 通过 |
| 老用户的补救步骤（README「自己加这一行」）有效 | 造一份 v2.0.0 时期的配置，按 README 原样插入该行，再用 `mihomo -t` 校验 | 通过（加之前/之后都能加载，说明只加一行不会破坏配置） |
| 选项真的改变握手内容 | 本地假 Reality 目标抓 mihomo 的 ClientHello，解析 key_share；四组（chrome/firefox/safari × true、chrome × false） | 通过：只有 `chrome` + `true` 出现 `X25519MLKEM768`（1789 字节）；其余为仅 X25519（517–663 字节） |
| **端到端连通（实机）**：真实 Xray 服务端 + 真实 mihomo 客户端，配置即脚本产出的形式 | 下载 Xray v26.10.21 与 v26.7.28 二进制，本地起 Reality 入站（dest 用 `www.cloudflare.com:443`），mihomo 走 socks 访问 `generate_204` | 通过：v26.10.21 + `chrome` + `true` → **HTTP 204**，服务端日志 `is using X25519MLKEM768 for TLS' communication: true`、`accepted tcp:www.gstatic.com:80`；重复跑两次都 204 |
| 对照组（证明不是碰巧） | 同上环境改一个变量 | 通过：`chrome` + `false` → 失败；`firefox` + `true` → 失败；Xray v26.7.28 默认 minClientVer → 失败，把 `minClientVer` 显式设为 `1.0.0` → **204**（与上面的版本分析一致） |
| `bash -n setup.sh` | 语法检查 | 通过 |

### 未验证

- 没有在真实 VPS 上用 3x-ui v3.9.0 实际装一遍再用 mihomo 连（本地用等价的 Reality 入站 + 同样的客户端配置复现并通过）。
- 较早的 mihomo 版本没有逐个验证；README 里「客户端太老可能不行」按 mihomo 官方 issue #3326 的描述写。

### 未解决

- 打开这一行后仍受限于客户端的指纹和版本：只有带 ML-KEM 的指纹（`chrome`）可用，mihomo 官方声明不考虑兼容 Xray v26.7.11+。README 已写明，并保持默认选中 Hysteria2。

## v2.0.0（2026-10-18）

**基线**：v2.0.0 标签。脚本行为和 v1.5.1（`a0115c9`）一样，只改了版本号；README、CHANGELOG 和本文件按实际行为更新。

**范围**：只支持 Debian；Debian 11 及更老换存档源；Debian 11 自动原地升级到 Debian 12 再装节点；系统升级时 apt 下载失败自动重试。其余功能（3x-ui、Reality、Hysteria2、住宅出站、防火墙、fail2ban、BBR、Xray 自动更新、自测）沿用 v1.2.2，这一轮没有改。

**交付物**：仓库根目录的 `setup.sh`，入口是 README 里的一行命令（`raw.githubusercontent.com/Finderlzy/reality-setup/<版本>/setup.sh`）。没有打包步骤。

### 验收结果

| 场景 | 验证方式 | 结果 |
| --- | --- | --- |
| Debian 11 新机器：升级到 12 后装节点 | 作者在一台新机器上用 v1.5.1 跑完整流程 | 通过（作者报告；机器配置、日志没有留存） |
| Debian 11 + 存档源，不升级，直接装节点 | 洛杉矶一台 Debian 11.3 KVM VPS 上用 v1.4.0 跑完整流程 | 通过：换存档源、装 3x-ui、Reality 和 Hysteria2 自测都成功 |
| 系统检测：Debian 12 / 11 放行；Ubuntu、Rocky、没有发行版名称的拦下并提示 | 抽出脚本里这一段，用假的 `os-release` 模拟运行 | 通过 |
| 换存档源：Debian 9 / 10 / 11 写对源，12 / 13 / Ubuntu 不动；重复运行不覆盖原备份；`sources.list.d` 里提到版本代号的移走 | 抽出这一段，在临时目录里模拟运行 | 通过 |
| 升级判断：KVM 升级；OpenVZ / LXC、硬盘不到 2 GB 跳过；Debian 10 / 12 不触发；升级的命令顺序 | 抽出这一段，用假的 `systemd-detect-virt`、`df`、`apt-get` 模拟运行 | 通过 |
| Debian 11.3 虚拟机（官方 20220503 云镜像，和上面那台 VPS 同一内核）上的完整升级 | 本机 qemu | 未完成：第一次在下载 `archive.debian.org` 的包时断网失败，于是加了下载重试；第二次跑到升级途中，测试会话中断，后来改由作者在新机器上验证 |
| `bash -n setup.sh` | 语法检查 | 通过 |

模拟测试脚本是一次性的，没有放进仓库。

### 未验证

- Debian 9 / 10 的真机安装（只做了换源的模拟测试）
- 容器类 VPS 跳过升级的真机表现

### 未解决

- 装完打印的面板 SSH 隧道命令没带 SSH 端口，SSH 端口不是 22 的服务器照着运行会连不上（README「已知问题」已写明）
- Reality 节点的 SNI 可能带前缀，比如 `test-www.amazon.com`（README「已知问题」已写明）
