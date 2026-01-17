agsb支持4协议：vmess(vmpt)/trojan(trpt)+argo and hy2(hypt)/Realty(vlrt)

例trojan+hy2：trpt="自定义端口" hypt="自定义端口" uuid="自定义uuid" argo="trpt" agn="cf域名" agk="隧道token" bash <(curl -Ls https://raw.githubusercontent.com/77160860/proxy/main/agsb.sh)

系统必装：apk add openssl/apt install openssl       ！快捷命令首次使用需重连vps ！

snell：port=自定义端口 psk=自定义密码 bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh)

查看：bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh) config

卸载：bash <(curl -fsSL https://raw.githubusercontent.com/77160860/proxy/main/snell.sh) uninstall
