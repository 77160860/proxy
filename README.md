脚本基于**Sing-box**内核的多协议一键安装脚本，支持 Hysteria2、TUIC、VLESS-Reality、Trojan-WS 协议，并集成了 Cloudflare Argo 隧道功能搭配Trojan使用，支持单协议及全协议一键安装。

### 1. 基础安装命令
该脚本通过环境变量来控制开启哪些协议。你需要在执行命令前设置对应的变量。

#### 常用协议变量说明：
*   `hy`: 设置 Hysteria2 端口 (如 `hy=20001`不设置则随机生成)
*   `tu`: 设置 TUIC v5 端口 (如 `tu=20002`不设置则随机生成)
*   `sn`: 设置 Snell v5 端口 (如 `vr=20003`不设置则随机生成)
*   `vr`: 设置 VLESS-Reality 端口 (如 `vr=20004`不设置则随机生成)
*   `tr`: 设置 Trojan-WS 端口 (配合 Argo 使用)
*   `uuid`: 自定义 UUID/密码 (不设置则随机生成)

### 2. 常见使用示例

#### 示例 A：非隧道全协议安装 (自动分配端口及uuid)
```bash
hy="yes" tu="yes" sn="yes" vr="yes" bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/sing.sh)
```
#### 示例 B：隧道协议组合安装 (手动分配端口及uuid)
```bash
tr="自定义端口" hy="自定义端口" uuid="自定义uuid" argo="trpt" agn="cf域名" agk="隧道token" bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/sing.sh)
```
*注：变量赋值为 yes 表示启用并随机分配端口。使用argo才需要加入argo、agn、agk配置字段，系统必装：apk add openssl/apt install openssl *
### 3. 管理命令
脚本安装完成后，可以直接使用 `sing` 命令进行管理：

sing：查看当前内核的运行状态。
sing list：输出当前所有已安装节点的配置链接，并显示已生成的聚合文件（cat $HOME/sing/jh.txt）。
sing res：重启 Sing-box 内核与 Argo 隧道。
sing ups：一键更新 Sing-box 内核至最新正式版。
sing rep：重置配置。会清理旧配置文件及所有缓存的端口和密钥，方便您传入新参数重新安装。
sing del：一键彻底卸载。停止所有后台服务，删除系统启动项，彻底清空 $HOME/sing 目录。
### 4. 脚本特性说明
1.  **架构支持**：自动识别并支持 `x86_64` (amd64) 和 `aarch64` (arm64) 架构。
2.  **系统兼容**：支持 `systemd` (常见 Linux) 和 `OpenRC` (如 Alpine Linux) 初始化系统。
3.  **无交互安装**：所有参数通过环境变量传入，适合脚本自动化部署。
                                      
---


**snellv5**脚本(可指定端口及密码,不指定则随机生成):  

示例：port=自定义端口 psk=自定义密码 bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh)

查看：bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh) config

卸载：bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh) uninstall
