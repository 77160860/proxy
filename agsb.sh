#!/usr/bin/env bash
export LANG=en_US.UTF-8
[ -z "${trpt+x}" ] || { trp=yes; vmag=yes; }
[ -z "${hypt+x}" ] || hyp=yes
[ -z "${vmpt+x}" ] || { vmp=yes; vmag=yes; }
[ -z "${vlrt+x}" ] || vlr=yes
if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -q 'agsb/sing-box' || pgrep -f 'agsb/sing-box' >/dev/null 2>&1; then
    if [ "$1" = "rep" ]; then
        [ "$vlr" = yes ] || [ "$vmp" = yes ] || [ "$trp" = yes ] || [ "$hyp" = yes ] || { echo "提示：rep重置协议时，请在脚本前至少设置一个协议变量哦，再见！"; exit; }
    fi
else
    if [ "$1" != "del" ]; then
        [ "$vlr" = yes ] || [ "$vmp" = yes ] || [ "$trp" = yes ] || [ "$hyp" = yes ] || { echo "提示：未安装agsb脚本，请在脚本前至少设置一个协议变量哦，再见！"; exit; }
    fi
fi
export uuid=${uuid:-''}; export port_vm_ws=${vmpt:-''}; export port_tr=${trpt:-''}; export port_hy2=${hypt:-''}; export port_vlr=${vlrt:-''}; export cdnym=${cdnym:-''}; export argo=${argo:-''}; export ARGO_DOMAIN=${agn:-''}; export ARGO_AUTH=${agk:-''}; export ippz=${ippz:-''}; export name=${name:-''}; export oap=${oap:-''}
v46url="https://icanhazip.com"
agsburl="https://raw.githubusercontent.com/77160860/proxy/main/agsb.sh"
showmode(){
    echo "agsb脚本 (Singbox内核版)"
    echo "主脚本：bash <(curl -Ls ${agsburl}) 或 bash <(wget -qO- ${agsburl})"
    echo "显示节点信息命令：agsb list"
    echo "重置变量组命令： agsb rep"
    echo "更新Singbox内核命令：agsb ups"
    echo "重启脚本命令：agsb res"
    echo "卸载脚本命令：agsb del"
    echo "---------------------------------------------------------"
}
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"; echo "agsb一键无交互脚本 (Singbox内核版)"; echo "当前版本：26.1.18"; echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
hostname=$(uname -a | awk '{print $2}'); op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2); case $(uname -m) in aarch64) cpu=arm64;; x86_64) cpu=amd64;; *) echo "目前脚本不支持$(uname -m)架构" && exit; esac; mkdir -p "$HOME/agsb"
v4v6(){
    v4=$( (curl -s4m5 -k "$v46url" 2>/dev/null) || (wget -4 -qO- --tries=2 "$v46url" 2>/dev/null) )
    v6=$( (curl -s6m5 -k "$v46url" 2>/dev/null) || (wget -6 -qO- --tries=2 "$v46url" 2>/dev/null) )
}
set_sbyx(){
    if [ -n "$name" ]; then sxname=$name-; echo "$sxname" > "$HOME/agsb/name"; echo; echo "所有节点名称前缀：$name"; fi
    v4v6
    if (curl -s4m5 -k "$v46url" >/dev/null 2>&1) || (wget -4 -qO- --tries=2 "$v46url" >/dev/null 2>&1); then v4_ok=true; fi
    if (curl -s6m5 -k "$v46url" >/dev/null 2>&1) || (wget -6 -qO- --tries=2 "$v46url" >/dev/null 2>&1); then v6_ok=true; fi
    if [ "$v4_ok" = true ] && [ "$v6_ok" = true ]; then sbyx='prefer_ipv6'; elif [ "$v4_ok" = true ] && [ "$v6_ok" != true ]; then sbyx='ipv4_only'; elif [ "$v4_ok" != true ] && [ "$v6_ok" = true ]; then sbyx='ipv6_only'; else sbyx='prefer_ipv6'; fi
}
upsingbox(){
    url="https://github.com/77160860/proxy/releases/download/singbox/sing-box-$cpu"
    out="$HOME/agsb/sing-box"
    (curl -Lo "$out" -# --retry 2 "$url") || (wget -O "$out" --tries=2 "$url")
    chmod +x "$HOME/agsb/sing-box"
    sbcore=$("$HOME/agsb/sing-box" version 2>/dev/null | awk '/version/{print $NF}')
    echo "已安装Singbox正式版内核：$sbcore"
}
insuuid(){
    if [ ! -e "$HOME/agsb/sing-box" ]; then upsingbox; fi
    if [ -z "$uuid" ] && [ ! -e "$HOME/agsb/uuid" ]; then
        uuid=$("$HOME/agsb/sing-box" generate uuid)
        echo "$uuid" > "$HOME/agsb/uuid"
    elif [ -n "$uuid" ]; then
        echo "$uuid" > "$HOME/agsb/uuid"
    fi
    uuid=$(cat "$HOME/agsb/uuid")
    echo "UUID密码：$uuid"
}
installsb(){
    echo; echo "=========启用Singbox内核========="
    if [ ! -e "$HOME/agsb/sing-box" ]; then upsingbox; fi
    cat > "$HOME/agsb/sb.json" <<EOF
{
"log": { "disabled": false, "level": "info", "timestamp": true },
"inbounds": [
EOF
    insuuid
    openssl ecparam -genkey -name prime256v1 -out "$HOME/agsb/private.key" >/dev/null 2>&1
    openssl req -new -x509 -days 36500 -key "$HOME/agsb/private.key" -out "$HOME/agsb/cert.pem" -subj "/CN=www.bing.com" >/dev/null 2>&1
    if [ -n "$hyp" ]; then
        if [ -z "$port_hy2" ] && [ ! -e "$HOME/agsb/port_hy2" ]; then port_hy2=$(shuf -i 10000-65535 -n 1); echo "$port_hy2" > "$HOME/agsb/port_hy2"; elif [ -n "$port_hy2" ]; then echo "$port_hy2" > "$HOME/agsb/port_hy2"; fi
        port_hy2=$(cat "$HOME/agsb/port_hy2"); echo "Hysteria2端口：$port_hy2"
        cat >> "$HOME/agsb/sb.json" <<EOF
{"type": "hysteria2", "tag": "hy2-sb", "listen": "::", "listen_port": ${port_hy2},"users": [ { "password": "${uuid}" } ],"tls": { "enabled": true, "alpn": ["h3"], "certificate_path": "$HOME/agsb/cert.pem", "key_path": "$HOME/agsb/private.key" }},
EOF
    fi
    if [ -n "$trp" ]; then
        if [ -z "$port_tr" ] && [ ! -e "$HOME/agsb/port_tr" ]; then port_tr=$(shuf -i 10000-65535 -n 1); echo "$port_tr" > "$HOME/agsb/port_tr"; elif [ -n "$port_tr" ]; then echo "$port_tr" > "$HOME/agsb/port_tr"; fi
        port_tr=$(cat "$HOME/agsb/port_tr"); echo "Trojan端口(Argo本地使用)：$port_tr"
        cat >> "$HOME/agsb/sb.json" <<EOF
{"type": "trojan", "tag": "trojan-ws-sb", "listen": "::", "listen_port": ${port_tr},"users": [ { "password": "${uuid}" } ],"transport": { "type": "ws", "path": "/${uuid}-tr" }},
EOF
    fi
    if [ -n "$vmp" ]; then
        if [ -z "$port_vm_ws" ] && [ ! -e "$HOME/agsb/port_vm_ws" ]; then port_vm_ws=$(shuf -i 10000-65535 -n 1); echo "$port_vm_ws" > "$HOME/agsb/port_vm_ws"; elif [ -n "$port_vm_ws" ]; then echo "$port_vm_ws" > "$HOME/agsb/port_vm_ws"; fi
        port_vm_ws=$(cat "$HOME/agsb/port_vm_ws"); echo "Vmess-ws端口 (Argo本地使用)：$port_vm_ws"
        cat >> "$HOME/agsb/sb.json" <<EOF
{"type": "vmess", "tag": "vmess-sb", "listen": "::", "listen_port": ${port_vm_ws},"users": [ { "uuid": "${uuid}", "alterId": 0 } ],"transport": { "type": "ws", "path": "/${uuid}-vm" }},
EOF
    fi
    if [ -n "$vlr" ]; then
        if [ -z "$port_vlr" ] && [ ! -e "$HOME/agsb/port_vlr" ]; then port_vlr=$(shuf -i 10000-65535 -n 1); echo "$port_vlr" > "$HOME/agsb/port_vlr"; elif [ -n "$port_vlr" ]; then echo "$port_vlr" > "$HOME/agsb/port_vlr"; fi
        port_vlr=$(cat "$HOME/agsb/port_vlr"); echo "VLESS-Reality-Vision端口：$port_vlr"
        if [ ! -f "$HOME/agsb/reality.key" ]; then "$HOME/agsb/sing-box" generate reality-keypair > "$HOME/agsb/reality.key"; fi
        private_key=$(sed -n '1p' "$HOME/agsb/reality.key" | awk '{print $2}')
        [ -f "$HOME/agsb/short_id" ] && short_id=$(cat "$HOME/agsb/short_id") || { short_id=$(openssl rand -hex 4); echo "$short_id" > "$HOME/agsb/short_id"; }

        cat >> "$HOME/agsb/sb.json" <<EOF
{"type": "vless", "tag": "vless-reality-vision-sb", "listen": "::", "listen_port": ${port_vlr},"sniff": true,"users": [{"uuid": "${uuid}","flow": "xtls-rprx-vision"}],"tls": {"enabled": true,"server_name": "www.ua.edu","reality": {"enabled": true,"handshake": {"server": "www.ua.edu","server_port": 443},"private_key": "${private_key}","short_id": ["${short_id}"]}}},
EOF
    fi
}
sbbout(){
    if [ -e "$HOME/agsb/sb.json" ]; then
        sed -i '${s/,\s*$//}' "$HOME/agsb/sb.json"
        cat >> "$HOME/agsb/sb.json" <<EOF
],
"outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" } ],
"route": { "rules": [ { "action": "sniff" }, { "action": "resolve", "strategy": "${sbyx}" } ], "final": "direct" }
}
EOF
        if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
            cat > /etc/systemd/system/sb.service <<EOF
[Unit]
Description=sb service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
ExecStart=/root/agsb/sing-box run -c /root/agsb/sb.json
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload; systemctl enable sb; systemctl start sb
        elif command -v rc-service >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
            cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="sb service"
command="/root/agsb/sing-box"
command_args="run -c /root/agsb/sb.json"
command_background=yes
pidfile="/run/sing-box.pid"
depend() { need net; }
EOF
            chmod +x /etc/init.d/sing-box; rc-update add sing-box default; rc-service sing-box start
        else
            nohup "$HOME/agsb/sing-box" run -c "$HOME/agsb/sb.json" >/dev/null 2>&1 &
        fi
    fi
}
ins(){
    installsb; set_sbyx; sbbout
    if [ -n "$argo" ] && [ -n "$vmag" ]; then
        echo; echo "=========启用Cloudflared-argo内核========="
        if [ ! -e "$HOME/agsb/cloudflared" ]; then argocore=$({ curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared || wget -qO- https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared; } | grep -Eo '"[0-9.]+"' | sed -n 1p | tr -d '",'); echo "下载Cloudflared-argo最新正式版内核：$argocore"; url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu"; out="$HOME/agsb/cloudflared"; (curl -Lo "$out" -# --retry 2 "$url") || (wget -O "$out" --tries=2 "$url"); chmod +x "$HOME/agsb/cloudflared"; fi
        if [ "$argo" = "vmpt" ]; then argoport=$(cat "$HOME/agsb/port_vm_ws" 2>/dev/null); echo "Vmess" > "$HOME/agsb/vlvm"; elif [ "$argo" = "trpt" ]; then argoport=$(cat "$HOME/agsb/port_tr" 2>/dev/null); echo "Trojan" > "$HOME/agsb/vlvm"; fi; echo "$argoport" > "$HOME/agsb/argoport.log"
        if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
            argoname='固定'
            if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
                cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
ExecStart=/root/agsb/cloudflared tunnel --no-autoupdate --edge-ip-version auto run --token "${ARGO_AUTH}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload; systemctl enable argo; systemctl start argo
            elif command -v rc-service >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
                cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="/root/agsb/cloudflared tunnel"
command_args="--no-autoupdate --edge-ip-version auto run --token ${ARGO_AUTH}"
command_background=yes
pidfile="/run/argo.pid"
depend() { need net; }
EOF
                chmod +x /etc/init.d/argo; rc-update add argo default; rc-service argo start
            else
                nohup "$HOME/agsb/cloudflared" tunnel --no-autoupdate --edge-ip-version auto run --token "${ARGO_AUTH}" >/dev/null 2>&1 &
            fi
            echo "${ARGO_DOMAIN}" > "$HOME/agsb/sbargoym.log"; echo "${ARGO_AUTH}" > "$HOME/agsb/sbargotoken.log"
        else
            argoname='临时'
            nohup "$HOME/agsb/cloudflared" tunnel --url http://localhost:$(cat $HOME/agsb/argoport.log) --edge-ip-version auto --no-autoupdate > $HOME/agsb/argo.log 2>&1 &
        fi
        echo "申请Argo$argoname隧道中……请稍等"; sleep 8
        if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then argodomain=$(cat "$HOME/agsb/sbargoym.log" 2>/dev/null); else argodomain=$(grep -a trycloudflare.com "$HOME/agsb/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}'); fi
        if [ -n "${argodomain}" ]; then echo "Argo$argoname隧道申请成功"; else echo "Argo$argoname隧道申请失败"; fi
    fi
    sleep 5; echo
    if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsb/(sing-box|c)' || pgrep -f 'agsb/(sing-box|c)' >/dev/null 2>&1 ; then

        mkdir -p /usr/local/bin
        SCRIPT_PATH="/usr/local/bin/agsb"
        (curl -sL "$agsburl" -o "$SCRIPT_PATH") || (wget -qO "$SCRIPT_PATH" "$agsburl")
        chmod +x "$SCRIPT_PATH"

        crontab -l > /tmp/crontab.tmp 2>/dev/null
        if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
            sed -i '/agsb\/sing-box/d' /tmp/crontab.tmp
            echo '@reboot sleep 10 && nohup $HOME/agsb/sing-box run -c $HOME/agsb/sb.json >/dev/null 2>&1 &' >> /tmp/crontab.tmp
        fi
        sed -i '/agsb\/cloudflared/d' /tmp/crontab.tmp
        if [ -n "$argo" ] && [ -n "$vmag" ]; then
            if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
                if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
                    echo '@reboot sleep 10 && nohup $HOME/agsb/cloudflared tunnel --no-autoupdate --edge-ip-version auto run --token $(cat $HOME/agsb/sbargotoken.log) >/dev/null 2>&1 &' >> /tmp/crontab.tmp
                fi
            else
                echo '@reboot sleep 10 && nohup $HOME/agsb/cloudflared tunnel --url http://localhost:$(cat $HOME/agsb/argoport.log) --edge-ip-version auto --no-autoupdate > $HOME/agsb/argo.log 2>&1 &' >> /tmp/crontab.tmp
            fi
        fi
        crontab /tmp/crontab.tmp >/dev/null 2>&1; rm /tmp/crontab.tmp

        echo "agsb脚本进程启动成功，安装完毕" && sleep 2
    else
        echo "agsb脚本进程未启动，安装失败" && exit
    fi
}
agsbstatus(){
    echo "=========当前内核运行状态========="
    procs=$(find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null)
    if echo "$procs" | grep -Eq 'agsb/sing-box' || pgrep -f 'agsb/sing-box' >/dev/null 2>&1; then echo "Singbox (版本$("$HOME/agsb/sing-box" version 2>/dev/null | awk '/version/{print $NF}'))：运行中"; else echo "Sing-box：未启用"; fi
    if echo "$procs" | grep -Eq 'agsb/c' || pgrep -f 'agsb/c' >/dev/null 2>&1; then echo "Argo (版本$("$HOME/agsb/cloudflared" version 2>/dev/null | awk '{print $3}'))：运行中"; else echo "Argo：未启用"; fi
}
cip(){
    ipbest(){ serip=$((curl -s4m5 -k "$v46url" 2>/dev/null)|| (wget -4 -qO- --tries=2 "$v46url" 2>/dev/null)|| (curl -s6m5 -k "$v46url" 2>/dev/null)|| (wget -6 -qO- --tries=2 "$v46url" 2>/dev/null)); serip=$(echo "$serip"|tr -d '\r\n'|head -n1); if echo "$serip"|grep -q ':'; then server_ip="[$serip]"; else server_ip="$serip"; fi; echo "$server_ip" > "$HOME/agsb/server_ip.log"; }
    ipchange(){
        v4v6
        v4dq=$( (curl -s4m5 -k https://ip.fm 2>/dev/null | sed -E 's/.*Location: ([^,]+(, [^,]+)*),.*/\1/') || (wget -4 -qO- --tries=2 https://ip.fm 2>/dev/null | grep '<span class="has-text-grey-light">Location:' | tail -n1 | sed -E 's/.*>Location: <\/span>([^<]+)<.*/\1/') )
        v6dq=$( (curl -s6m5 -k https://ip.fm 2>/dev/null | sed -E 's/.*Location: ([^,]+(, [^,]+)*),.*/\1/') || (wget -6 -qO- --tries=2 https://ip.fm 2>/dev/null | grep '<span class="has-text-grey-light">Location:' | tail -n1 | sed -E 's/.*>Location: <\/span>([^<]+)<.*/\1/') )
        if [ -z "$v4" ]; then vps_ipv4='无IPV4'; vps_ipv6="$v6"; location=$v6dq; elif [ -n "$v4" ] && [ -n "$v6" ]; then vps_ipv4="$v4"; vps_ipv6="$v6"; location=$v4dq; else vps_ipv4="$v4"; vps_ipv6='无IPV6'; location=$v4dq; fi
        echo; agsbstatus; echo; echo "=========当前服务器本地IP情况========="; echo "本地IPV4地址：$vps_ipv4"; echo "本地IPV6地址：$vps_ipv6"; echo "服务器地区：$location"; echo; sleep 2
        if [ "$ippz" = "4" ]; then if [ -z "$v4" ]; then ipbest; else server_ip="$v4"; echo "$server_ip" > "$HOME/agsb/server_ip.log"; fi; elif [ "$ippz" = "6" ]; then if [ -z "$v6" ]; then ipbest; else server_ip="[$v6]"; echo "$server_ip" > "$HOME/agsb/server_ip.log"; fi; else ipbest; fi
    }
    ipchange; rm -rf "$HOME/agsb/jh.txt"; uuid=$(cat "$HOME/agsb/uuid"); server_ip=$(cat "$HOME/agsb/server_ip.log"); sxname=$(cat "$HOME/agsb/name" 2>/dev/null);
    echo "*********************************************************"; echo "agsb脚本输出节点配置如下："; echo;
    if grep -q "hy2-sb" "$HOME/agsb/sb.json"; then port_hy2=$(cat "$HOME/agsb/port_hy2"); hy2_link="hysteria2://$uuid@$server_ip:$port_hy2?security=tls&alpn=h3&insecure=1&sni=www.bing.com#${sxname}hy2-$hostname"; echo "【 Hysteria2 】(直连协议)"; echo "$hy2_link" | tee -a "$HOME/agsb/jh.txt"; echo; fi
    if grep -q "vless-reality-vision-sb" "$HOME/agsb/sb.json"; then
        port_vlr=$(cat "$HOME/agsb/port_vlr")
        public_key=$(sed -n '2p' "$HOME/agsb/reality.key" | awk '{print $2}')
        short_id=$(cat "$HOME/agsb/short_id")
        vless_link="vless://${uuid}@${server_ip}:${port_vlr}?encryption=none&security=reality&sni=www.ua.edu&fp=chrome&flow=xtls-rprx-vision&publicKey=${public_key}&shortId=${short_id}#${sxname}vless-reality-$hostname"
        echo "【 VLESS-Reality-Vision 】(直连协议)"; echo "$vless_link" | tee -a "$HOME/agsb/jh.txt"; echo;
    fi
    argodomain=$(cat "$HOME/agsb/sbargoym.log" 2>/dev/null); [ -z "$argodomain" ] && argodomain=$(grep -a trycloudflare.com "$HOME/agsb/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    if [ -n "$argodomain" ]; then
        vlvm=$(cat $HOME/agsb/vlvm 2>/dev/null); uuid=$(cat "$HOME/agsb/uuid")
        if [ "$vlvm" = "Vmess" ]; then
            vmatls_link1="vmess://$(echo "{\"v\":\"2\",\"ps\":\"${sxname}vmess-ws-tls-argo-$hostname-443\",\"add\":\"cdn.7zz.cn\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"host\":\"$argodomain\",\"path\":\"/${uuid}-vm\",\"tls\":\"tls\",\"sni\":\"$argodomain\"}" | base64 -w0)"
            tratls_link1=""
        elif [ "$vlvm" = "Trojan" ]; then
            tratls_link1="trojan://${uuid}@cdn.7zz.cn:443?security=tls&type=ws&host=${argodomain}&path=%2F${uuid}-tr&sni=${argodomain}&fp=chrome#${sxname}trojan-ws-tls-argo-$hostname-443"
            vmatls_link1=""
        fi
        sbtk=$(cat "$HOME/agsb/sbargotoken.log" 2>/dev/null); [ -n "$sbtk" ] && nametn="Argo固定隧道token:\n$sbtk"
        argoshow="Argo隧道信息 (使用 $vlvm-ws 端口: $(cat $HOME/agsb/argoport.log 2>/dev/null))\n---------------------------------------------------------\nArgo域名: ${argodomain}\n\n${nametn}\n\n 443端口Argo-TLS节点 (优选IP可替换):\n${vmatls_link1}${tratls_link1}"
        echo "---------------------------------------------------------"; echo -e "$argoshow"; echo "---------------------------------------------------------"
    fi
    echo; echo "聚合节点: cat $HOME/agsb/jh.txt"; echo "========================================================="; echo "相关快捷方式如下："; showmode
}
cleandel(){
    for P in /proc/[0-9]*; do if [ -L "$P/exe" ]; then TARGET=$(readlink -f "$P/exe" 2>/dev/null); if echo "$TARGET" | grep -qE '/agsb/c|/agsb/sing-box'; then kill "$(basename "$P")" 2>/dev/null; fi; fi; done
    kill -15 $(pgrep -f 'agsb/c' 2>/dev/null) $(pgrep -f 'agsb/sing-box' 2>/dev/null) >/dev/null 2>&1

    crontab -l > /tmp/crontab.tmp 2>/dev/null
    sed -i '/agsb/d' /tmp/crontab.tmp
    crontab /tmp/crontab.tmp >/dev/null 2>&1
    rm /tmp/crontab.tmp

    # Remove shortcut (new global path) + legacy location if it exists
    rm -f /usr/local/bin/agsb "$HOME/bin/agsb"

    if pidof systemd >/dev/null 2>&1; then
        for svc in sb argo; do systemctl stop "$svc" >/dev/null 2>&1; systemctl disable "$svc" >/dev/null 2>&1; done
        rm -f /etc/systemd/system/{sb.service,argo.service}
    elif command -v rc-service >/dev/null 2>&1; then
        for svc in sing-box argo; do rc-service "$svc" stop >/dev/null 2>&1; rc-update del "$svc" default >/dev/null 2>&1; done
        rm -f /etc/init.d/{sing-box,argo}
    fi
}
sbrestart(){
    kill -15 $(pgrep -f 'agsb/sing-box' 2>/dev/null) >/dev/null 2>&1
    if pidof systemd >/dev/null 2>&1; then
        systemctl restart sb
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box restart
    else
        nohup "$HOME/agsb/sing-box" run -c "$HOME/agsb/sb.json" >/dev/null 2>&1 &
    fi
}
argorestart(){
    kill -15 $(pgrep -f 'agsb/c' 2>/dev/null) >/dev/null 2>&1
    if pidof systemd >/dev/null 2>&1; then
        systemctl restart argo
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service argo restart
    else
        if [ -e "$HOME/agsb/sbargotoken.log" ]; then
            nohup "$HOME/agsb/cloudflared" tunnel --no-autoupdate --edge-ip-version auto run --token $(cat $HOME/agsb/sbargotoken.log) >/dev/null 2>&1 &
        else
            nohup "$HOME/agsb/cloudflared" tunnel --url http://localhost:$(cat $HOME/agsb/argoport.log) --edge-ip-version auto --no-autoupdate > $HOME/agsb/argo.log 2>&1 &
        fi
    fi
}
if [ "$1" = "del" ]; then cleandel; rm -rf "$HOME/agsb"; echo "卸载完成"; showmode; exit; fi
if [ "$1" = "rep" ]; then cleandel; rm -rf "$HOME/agsb"/{sb.json,sbargoym.log,sbargotoken.log,argo.log,argoport.log,cdnym,name}; echo "重置完成..."; sleep 2; fi
if [ "$1" = "list" ]; then cip; exit; fi
if [ "$1" = "ups" ]; then kill -15 $(pgrep -f 'agsb/sing-box' 2>/dev/null); upsingbox && sbrestart && echo "Sing-box内核更新完成" && sleep 2 && cip; exit; fi
if [ "$1" = "res" ]; then sbrestart; argorestart; sleep 5 && echo "重启完成" && sleep 3 && cip; exit; fi
if ! pgrep -f 'agsb/sing-box' >/dev/null 2>&1 && [ "$1" != "rep" ]; then
    cleandel
fi
if ! pgrep -f 'agsb/sing-box' >/dev/null 2>&1 || [ "$1" = "rep" ]; then
    if [ -z "$( (curl -s4m5 -k "$v46url") || (wget -4 -qO- --tries=2 "$v46url") )" ]; then echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf; fi
    echo "VPS系统：$op"; echo "CPU架构：$cpu"; echo "agsb脚本开始安装/更新…………" && sleep 1
    if [ -n "$oap" ]; then setenforce 0 >/dev/null 2>&1; iptables -F; iptables -P INPUT ACCEPT; netfilter-persistent save >/dev/null 2>&1; echo "iptables执行开放所有端口"; fi
    ins; cip
else
    echo "agsb脚本已安装"; echo; agsbstatus; echo; echo "相关快捷方式如下："; showmode; exit
fi
