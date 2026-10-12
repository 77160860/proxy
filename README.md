# sing 一键无交互脚本（sing-box 内核版）

基于 **Sing-box** 内核的多协议一键安装脚本，支持 Hysteria2、Snell v6、TUIC v5、VLESS-Reality-Vision、SS2022-ShadowTLS、Trojan-WS 六种协议，并集成 Cloudflare Argo 隧道（配合 Trojan 使用）。所有参数通过环境变量传入，**全程无交互**，支持单协议或全协议一键部署，安装时自动开启 BBR + FQ 网络优化。

- 当前版本：`26.10.08`
- 主脚本地址：`https://raw.githubusercontent.com/77160860/proxy/main/sing.sh`

---

## 1. 支持的协议

| 协议 | 说明 |
|------|------|
| Hysteria2 | 基于 QUIC，自签证书（sni=www.icloud.com） |
| VLESS-Reality-Vision | Reality 免证书，flow=xtls-rprx-vision |
| Snell v6 | 兼容官方与第三方客户端 |
| TUIC v5 | congestion_control=bbr，native UDP 中继 |
| SS2022-ShadowTLS | 2022-blake3-aes-128-gcm + ShadowTLS v3 |
| Trojan-WS | WebSocket + TLS，配合 Cloudflare Argo 隧道 |

---

## 2. 环境变量说明

脚本通过环境变量控制开启哪些协议及其参数，在执行命令前设置即可。

### 2.1 协议端口变量

设为具体端口号则使用该端口；设为 `yes`（或任意非数字值）则启用并随机分配端口；留空则不启用该协议。

| 变量 | 协议 | 示例 |
|------|------|------|
| `hy` | Hysteria2 | `hy=20002` |
| `vr` | VLESS-Reality-Vision | `vr=8443` |
| `sn` | Snell v6 | `sn=20001` |
| `tu` | TUIC v5 | `tu=20000` |
| `ss` | SS2022-ShadowTLS | `ss=443` |
| `tr` | Trojan-WS（自动启用 Argo） | `tr=20003` |

> 设置 `tr` 会自动启用 Cloudflare Argo 隧道。

### 2.2 Argo 隧道变量（仅固定隧道需要）

| 变量 | 说明 |
|------|------|
| `agn` | Argo 固定隧道域名（Cloudflare 域名） |
| `agk` | Argo 固定隧道 Token |
| `cdnym` | Trojan 连接用的 CDN 优选域名（默认 `saas.sin.fan`） |

> 不设置 `agn`/`agk` 时使用临时隧道（Try Cloudflare）；固定隧道需同时提供 `agn` 和 `agk`。

### 2.3 通用与输出变量

| 变量 | 说明 |
|------|------|
| `uuid` | 自定义 UUID / 密码，不设置则随机生成 |
| `name` | 自定义节点名称前缀，便于区分不同机器 |
| `ippz` | 节点输出 IP 偏好：`4`=仅 IPv4，`6`=仅 IPv6，不设置=**双栈同时输出** |
| `oap` | ⚠️ 设置后清空 iptables 并放通所有端口（关闭主机防火墙） |

---

## 3. 安装示例

### 示例 A：非隧道全协议安装（自动分配端口及 UUID）
```bash
hy=yes tu=yes sn=yes vr=yes ss=yes bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/sing.sh)
```

### 示例 B：Argo 固定隧道组合安装（手动指定端口及 UUID）
```bash
tr="自定义端口" hy="自定义端口" uuid="自定义uuid" agn="cf域名" agk="隧道token" bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/sing.sh)
```

### 示例 C：指定端口 + 仅输出 IPv4 节点
```bash
hy=20002 vr=8443 ippz=4 bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/sing.sh)
```

> 变量赋值为 `yes` 表示启用并随机分配端口；仅使用固定隧道时才需要 `agn`、`agk`。

## 4. 节点输出说明

- **默认双栈输出**：若机器同时具备公网 IPv4 和 IPv6，每个协议会**同时**生成 v4 与 v6 两条链接，节点名分别带 `-v4` / `-v6` 后缀。
- **自助切换**：`ippz=4` 只输出 IPv4 节点，`ippz=6` 只输出 IPv6 节点。
- 所有链接会写入聚合文件，可用 `cat $HOME/sing/jh.txt` 查看（SS2022-ShadowTLS 以 Clash/mihomo 片段形式写入）。

---

## 5. 管理命令

脚本安装完成后，可直接使用 `sing` 命令管理。

| 命令 | 功能 |
|------|------|
| `sing` | 查看当前内核运行状态 |
| `sing list` | 输出所有节点链接，并显示聚合文件 `cat $HOME/sing/jh.txt` |
| `sing res` | 重启 Sing-box 内核与 Argo 隧道 |
| `sing ups` | 更新 Sing-box 内核至最新正式版 |
| `sing rep` | 重置配置：清理旧配置、端口与密钥缓存，便于传入新参数重装 |
| `sing del` | 彻底卸载：停止服务、删除启动项、清空 `$HOME/sing`，并移除 BBR 优化 |
| `sing bbr` | 单独执行 BBR + FQ 网络优化 |

> **重置协议**：需在设置新的协议变量后，于命令末尾加上 `rep`，且至少设置一个协议变量，例如：
> ```bash
> hy=yes vr=yes sing rep
> ```

## 6. BBR 网络优化

安装协议时（以及执行 `sing bbr` 时）会**立即生效并永久写入** `/etc/sysctl.d/99-bbr-optimization.conf`：

```ini
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_wmem = 4096 16384 12582912
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_limit_output_bytes = 4194304
net.ipv4.tcp_slow_start_after_idle = 0
```

- **IPv4 / IPv6 同时生效**：以上为内核共享的 TCP 参数，v4 与 v6 连接均适用；fq 队列挂在出口网卡上，不区分 IP 版本。
- **开机自持久**：qdisc 通过 systemd 服务或 OpenRC 启动脚本在重启后自动恢复。
- **Alpine 适配**：自动补装 `iproute2-tc`、`kmod` 并加载 `sch_fq` 模块。
- 应用后会回显实际生效参数；若 bbr/fq 未成功启用会给出明确提示。

---

## 7. 脚本特性

1. **架构支持**：自动识别 `x86_64`(amd64) 与 `aarch64`(arm64)。
2. **系统兼容**：支持 `systemd`（常见 Linux）与 `OpenRC`（如 Alpine Linux）。
3. **无交互安装**：所有参数经环境变量传入，适合自动化部署。
4. **双栈友好**：节点默认同时输出 IPv4/IPv6，并可用 `ippz` 自助切换。
5. **网络优化**：安装即自动开启 BBR + FQ，并立即/永久写入 TCP 调优参数。
6. **Argo 集成**：支持临时隧道与固定隧道，配合 Trojan-WS 使用。

---

## 8. 卸载

```bash
sing del
```

停止所有后台服务、删除系统启动项、移除 BBR 优化配置，并彻底清空 `$HOME/sing` 目录。
