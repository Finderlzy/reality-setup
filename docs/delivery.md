# 交付记录

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
