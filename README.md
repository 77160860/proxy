agsb脚本基于 **Sing-box** 内核的多协议一键安装脚本，支持 Hysteria2、TUIC、VLESS-Reality、Vmess-WS 和 Trojan-WS 协议，并集成了 Cloudflare Argo 隧道功能，支持单协议及全协议。

### 1. 基础安装命令
该脚本通过环境变量来控制开启哪些协议。你需要在执行命令前设置对应的变量。

#### 常用协议变量说明：
*   `hypt`: 设置 Hysteria2 端口 (如 `hypt=20001`不设置则随机生成)
*   `tupt`: 设置 TUIC v5 端口 (如 `tupt=20002`不设置则随机生成)
*   `vlrt`: 设置 VLESS-Reality 端口 (如 `vlrt=20003`不设置则随机生成)
*   `vmpt`: 设置 Vmess-WS 端口 (配合 Argo 使用)
*   `trpt`: 设置 Trojan-WS 端口 (配合 Argo 使用)
*   `uuid`: 自定义 UUID/密码 (不设置则随机生成)
---

### 2. 常见使用示例

#### 示例 A：非隧道全协议安装 (自动分配端口及uuid)
```bash
hypt=1 tupt=1 vlrt=1 bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/agsb.sh)
```
#### 示例 B：隧道协议组合安装 (手动分配端口及uuid)
```bash
trpt="自定义端口" hypt="自定义端口" uuid="自定义uuid" argo="trpt" agn="cf域名" agk="隧道token" bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/agsb.sh)
```
*注：变量赋值为 1 表示启用并随机分配端口。使用argo才需要加入argo、agn、agk配置字段，系统必装：apk add openssl/apt install openssl *

### 3. 脚本特性说明
1.  **架构支持**：自动识别并支持 `x86_64` (amd64) 和 `aarch64` (arm64) 架构。
2.  **系统兼容**：支持 `systemd` (常见 Linux) 和 `OpenRC` (如 Alpine Linux) 初始化系统。
3.  **无交互安装**：所有参数通过环境变量传入，适合脚本自动化部署。
                                      

snell脚本(可指定端口及密码,不指定则随机生成):  
snellv5：port=自定义端口 psk=自定义密码 bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh)

查看：bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh) config

卸载：bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh) uninstall
