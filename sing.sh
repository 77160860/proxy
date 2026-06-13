#!/usr/bin/env bash
export LANG=en_US.UTF-8
[ -z "${tr+x}" ] || trp=yes
[ -z "${hy+x}" ] || hyp=yes
[ -z "${vr+x}" ] || vlr=yes
[ -z "${tu+x}" ] || tup=yes
[ -z "${sn+x}" ] || snp=yes
[ -z "${st+x}" ] || stp=yes
if [ "$1" = "list" ] || [ "$1" = "del" ] || [ "$1" = "res" ] || [ "$1" = "ups" ]; then
    :
elif find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -q 'sing/sing-box' || pgrep -x sing-box >/dev/null 2>&1; then
    if [ "$1" = "rep" ]; then
        [ "$vlr" = yes ] || [ "$trp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$snp" = yes ] || [ "$stp" = yes ] || { echo "提示:rep重置协议时,请在脚本前至少设置一个协议变量哦,再见!"; exit; }
    fi
else
    [ "$vlr" = yes ] || [ "$trp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$snp" = yes ] || [ "$stp" = yes ] || { echo "提示:未安装sing脚本,请在脚本前至少设置一个协议变量哦,再见!"; exit; }
fi
export uuid=${uuid:-''}; export port_tr=${tr:-''}; export port_hy2=${hy:-''}; export port_vlr=${vr:-''}; export port_tuic=${tu:-''}; export port_snell=${sn:-''}; export port_st=${st:-''}; export cdnym=${cdnym:-''}; export argo=${argo:-''}; export ARGO_DOMAIN=${agn:-''}; export ARGO_AUTH=${agk:-''}; export ippz=${ippz:-''}; export name=${name:-''}; export oap=${oap:-''}
v46url="https://icanhazip.com"
singurl="https://raw.githubusercontent.com/77160860/proxy/main/sing.sh"
showmode(){
    echo "sing脚本 (Singbox内核版)"
    echo "主脚本:bash <(curl -Ls ${singurl}) 或 bash <(wget -qO- ${singurl})"
    echo "显示节点命令:sing list"
    echo "重置变量命令:sing rep"
    echo "更新内核命令:sing ups"
    echo "重启脚本命令:sing res"
    echo "卸载脚本命令:sing del"
    echo "---------------------------------------------------------"
}
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "sing一键无交互脚本 (Singbox内核版)"
echo "当前版本:26.06.08"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
hostname=$(uname -a | awk '{print $2}'); op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2); case $(uname -m) in aarch64) cpu=arm64;; x86_64) cpu=amd64;; *) echo "目前脚本不支持$(uname -m)架构" && exit; esac; mkdir -p "$HOME/sing"
v4v6(){
    v4=$( (curl -s4m5 -k "$v46url" 2>/dev/null) || (wget -4 -qO- --tries=2 "$v46url" 2>/dev/null) )
    v6=$( (curl -s6m5 -k "$v46url" 2>/dev/null) || (wget -6 -qO- --tries=2 "$v46url" 2>/dev/null) )
}
port_in_use(){
    local p="$1"
    [ -z "$p" ] && return 1
    if command -v ss >/dev/null 2>&1; then
        ss -H -lntup 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]${p}$" && return 0
        return 1
    fi
    if command -v netstat >/dev/null 2>/dev/null; then
        netstat -lntup 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && return 0
        return 1
    fi
    return 1
}
get_free_port(){
    local p
    while true; do
        p=$(shuf -i 10000-65535 -n 1)
        if ! port_in_use "$p"; then
            echo "$p"
            break
        fi
    done
}
upsingbox(){
    url="https://github.com/77160860/proxy/releases/download/singbox/sing-box-$cpu"
    out="$HOME/sing/sing-box"
    (curl -Lo "$out" -# --retry 2 "$url") || (wget -O "$out" --tries=2 "$url")
    chmod +x "$HOME/sing/sing-box"
    sbcore=$("$HOME/sing/sing-box" version 2>/dev/null | awk '/version/{print $NF}')
    echo "已安装Singbox正式版内核:$sbcore"
}
insuuid(){
    if [ ! -e "$HOME/sing/sing-box" ]; then upsingbox; fi
    if [ -z "$uuid" ] && [ ! -e "$HOME/sing/uuid" ]; then
        uuid=$("$HOME/sing/sing-box" generate uuid)
        echo "$uuid" > "$HOME/sing/uuid"
    elif [ -n "$uuid" ]; then
        echo "$uuid" > "$HOME/sing/uuid"
    fi
    uuid=$(cat "$HOME/sing/uuid")
    echo "UUID密码:$uuid"
}
installsb(){
    echo; echo "=========启用Singbox内核========="
    if [ ! -e "$HOME/sing/sing-box" ]; then upsingbox; fi
    cat > "$HOME/sing/sb.json" <<EOF
{
"log": { "disabled": false, "level": "error", "timestamp": true },
"inbounds": [
EOF
    insuuid
    openssl ecparam -genkey -name prime256v1 -out "$HOME/sing/private.key" >/dev/null 2>&1
    openssl req -new -x509 -days 36500 -key "$HOME/sing/private.key" -out "$HOME/sing/cert.pem" -subj "/CN=www.icloud.com" >/dev/null 2>&1
    # Hysteria2
    if [ -n "$hyp" ]; then
        if [ "$port_hy2" = "yes" ] || [[ ! "$port_hy2" =~ ^[0-9]+$ ]]; then port_hy2=""; fi
        if [ -n "$port_hy2" ]; then
            if port_in_use "$port_hy2"; then old_port="$port_hy2"; port_hy2=$(get_free_port); echo "警告: Hysteria2 指定端口 $old_port 已被占用, 自动更换为新端口: $port_hy2"; fi
            echo "$port_hy2" > "$HOME/sing/port_hy2"
        elif [ -e "$HOME/sing/port_hy2" ]; then
            port_hy2=$(cat "$HOME/sing/port_hy2")
            if port_in_use "$port_hy2" || [[ ! "$port_hy2" =~ ^[0-9]+$ ]]; then old_port="$port_hy2"; port_hy2=$(get_free_port); echo "警告: Hysteria2 缓存端口 $old_port 异常或已被占用, 自动更换为新端口: $port_hy2"; echo "$port_hy2" > "$HOME/sing/port_hy2"; fi
        else
            port_hy2=$(get_free_port); echo "$port_hy2" > "$HOME/sing/port_hy2"
        fi
        port_hy2=$(cat "$HOME/sing/port_hy2"); echo "Hysteria2端口:$port_hy2"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "hysteria2", "tag": "hy2", "listen": "::", "listen_port": ${port_hy2},"users": [ { "password": "${uuid}" } ],"tls": { "enabled": true, "certificate_path": "$HOME/sing/cert.pem", "key_path": "$HOME/sing/private.key" }},
EOF
    fi
    # TUIC
    if [ -n "$tup" ]; then
        if [ "$port_tuic" = "yes" ] || [[ ! "$port_tuic" =~ ^[0-9]+$ ]]; then port_tuic=""; fi
        if [ -n "$port_tuic" ]; then
            if port_in_use "$port_tuic"; then old_port="$port_tuic"; port_tuic=$(get_free_port); echo "警告: TUIC 指定端口 $old_port 已被占用, 自动更换为新端口: $port_tuic"; fi
            echo "$port_tuic" > "$HOME/sing/port_tuic"
        elif [ -e "$HOME/sing/port_tuic" ]; then
            port_tuic=$(cat "$HOME/sing/port_tuic")
            if port_in_use "$port_tuic" || [[ ! "$port_tuic" =~ ^[0-9]+$ ]]; then old_port="$port_tuic"; port_tuic=$(get_free_port); echo "警告: TUIC 缓存端口 $old_port 异常或已被占用, 自动更换为新端口: $port_tuic"; echo "$port_tuic" > "$HOME/sing/port_tuic"; fi
        else
            port_tuic=$(get_free_port); echo "$port_tuic" > "$HOME/sing/port_tuic"
        fi
        port_tuic=$(cat "$HOME/sing/port_tuic"); echo "TUIC端口:$port_tuic"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "tuic", "tag": "tuic", "listen": "::", "listen_port": ${port_tuic}, "users": [{"uuid": "${uuid}", "password": "${uuid}"}], "congestion_control": "bbr", "heartbeat": "10s", "tls": {"enabled": true, "certificate_path": "$HOME/sing/cert.pem", "key_path": "$HOME/sing/private.key"}},
EOF
    fi
    # Snell
    if [ -n "$snp" ]; then
        if [ "$port_snell" = "yes" ] || [[ ! "$port_snell" =~ ^[0-9]+$ ]]; then port_snell=""; fi
        if [ -n "$port_snell" ]; then
            if port_in_use "$port_snell"; then old_port="$port_snell"; port_snell=$(get_free_port); echo "警告: Snell 指定端口 $old_port 已被占用, 自动更换为新端口: $port_snell"; fi
            echo "$port_snell" > "$HOME/sing/port_snell"
        elif [ -e "$HOME/sing/port_snell" ]; then
            port_snell=$(cat "$HOME/sing/port_snell")
            if port_in_use "$port_snell" || [[ ! "$port_snell" =~ ^[0-9]+$ ]]; then old_port="$port_snell"; port_snell=$(get_free_port); echo "警告: Snell 缓存端口 $old_port 异常或已被占用, 自动更换为新端口: $port_snell"; echo "$port_snell" > "$HOME/sing/port_snell"; fi
        else
            port_snell=$(get_free_port); echo "$port_snell" > "$HOME/sing/port_snell"
        fi
        port_snell=$(cat "$HOME/sing/port_snell"); echo "Snell端口:$port_snell"
        snell_psk="${uuid}"
        echo "$snell_psk" > "$HOME/sing/snell_psk"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "snell", "tag": "snell", "listen": "::", "listen_port": ${port_snell}, "psk": "${snell_psk}", "tcp_fast_open": true, "version": 5},
EOF
    fi
    # Trojan
    if [ -n "$trp" ]; then
        if [ "$port_tr" = "yes" ] || [[ ! "$port_tr" =~ ^[0-9]+$ ]]; then port_tr=""; fi
        if [ -n "$port_tr" ]; then
            if port_in_use "$port_tr"; then old_port="$port_tr"; port_tr=$(get_free_port); echo "警告: Trojan 指定端口 $old_port 已被占用, 自动更换为新端口: $port_tr"; fi
            echo "$port_tr" > "$HOME/sing/port_tr"
        elif [ -e "$HOME/sing/port_tr" ]; then
            port_tr=$(cat "$HOME/sing/port_tr")
            if port_in_use "$port_tr" || [[ ! "$port_tr" =~ ^[0-9]+$ ]]; then old_port="$port_tr"; port_tr=$(get_free_port); echo "警告: Trojan 缓存端口 $old_port 异常或已被占用, 自动更换为新端口: $port_tr"; echo "$port_tr" > "$HOME/sing/port_tr"; fi
        else
            port_tr=$(get_free_port); echo "$port_tr" > "$HOME/sing/port_tr"
        fi
        port_tr=$(cat "$HOME/sing/port_tr"); echo "Trojan端口(Argo本地使用):$port_tr"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "trojan", "tag": "trojan-ws", "listen": "::", "listen_port": ${port_tr}, "tcp_fast_open": true, "users": [ { "password": "${uuid}" } ],"transport": { "type": "ws", "path": "/tr" }},
EOF
    fi
    # VLESS-Reality
    if [ -n "$vlr" ]; then
        if [ "$port_vlr" = "yes" ] || [[ ! "$port_vlr" =~ ^[0-9]+$ ]]; then port_vlr=""; fi
        if [ -n "$port_vlr" ]; then
            if port_in_use "$port_vlr"; then old_port="$port_vlr"; port_vlr=$(get_free_port); echo "警告: VLESS-Reality 指定端口 $old_port 已被占用, 自动更换为新端口: $port_vlr"; fi
            echo "$port_vlr" > "$HOME/sing/port_vlr"
        elif [ -e "$HOME/sing/port_vlr" ]; then
            port_vlr=$(cat "$HOME/sing/port_vlr")
            if port_in_use "$port_vlr" || [[ ! "$port_vlr" =~ ^[0-9]+$ ]]; then old_port="$port_vlr"; port_vlr=$(get_free_port); echo "警告: VLESS-Reality 缓存端口 $old_port 异常或已被占用, 自动更换为新端口: $port_vlr"; echo "$port_vlr" > "$HOME/sing/port_vlr"; fi
        else
            port_vlr=$(get_free_port); echo "$port_vlr" > "$HOME/sing/port_vlr"
        fi
        port_vlr=$(cat "$HOME/sing/port_vlr"); echo "VLESS-Reality-Vision端口:$port_vlr"
        if [ ! -f "$HOME/sing/reality.key" ]; then "$HOME/sing/sing-box" generate reality-keypair > "$HOME/sing/reality.key"; fi
        private_key=$(sed -n '1p' "$HOME/sing/reality.key" | awk '{print $2}')
        [ -f "$HOME/sing/short_id" ] && short_id=$(cat "$HOME/sing/short_id") || { short_id=$(openssl rand -hex 4); echo "$short_id" > "$HOME/sing/short_id"; }
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "vless", "tag": "vless-reality", "listen": "::", "listen_port": ${port_vlr}, "tcp_fast_open": true, "users": [{"uuid": "${uuid}","flow": "xtls-rprx-vision"}],"tls": {"enabled": true,"server_name": "www.icloud.com","reality": {"enabled": true,"handshake": {"server": "www.icloud.com","server_port": 443},"private_key": "${private_key}","short_id": ["${short_id}"]}}},
EOF
    fi
    if [ -n "$stp" ]; then
        if [ "$port_st" = "yes" ] || [[ ! "$port_st" =~ ^[0-9]+$ ]]; then port_st=""; fi
        if [ -n "$port_st" ]; then
            if port_in_use "$port_st"; then old_port="$port_st"; port_st=$(get_free_port); echo "警告: ShadowTLS 指定端口 $old_port 已被占用, 自动更换为新端口: $port_st"; fi
            echo "$port_st" > "$HOME/sing/port_st"
        elif [ -e "$HOME/sing/port_st" ]; then
            port_st=$(cat "$HOME/sing/port_st")
            if port_in_use "$port_st" || [[ ! "$port_st" =~ ^[0-9]+$ ]]; then old_port="$port_st"; port_st=$(get_free_port); echo "警告: ShadowTLS 缓存端口 $old_port 异常或已被占用, 自动更换为新端口: $port_st"; echo "$port_st" > "$HOME/sing/port_st"; fi
        else
            port_st=$(get_free_port); echo "$port_st" > "$HOME/sing/port_st"
        fi
        port_st=$(cat "$HOME/sing/port_st"); echo "SS2022端口:$port_st"
        st_password="${uuid}"
        ss_password=$(openssl rand -base64 16)
        echo "$st_password" > "$HOME/sing/st_password"
        echo "$ss_password" > "$HOME/sing/ss_password"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "shadowtls", "tag": "shadowtls", "listen": "::", "listen_port": ${port_st}, "tcp_fast_open": true, "version": 3, "users": [ { "password": "${st_password}" } ], "handshake": { "server": "www.icloud.com", "server_port": 443 }, "strict_mode": true, "detour": "ss-in" },
{"type": "shadowsocks", "tag": "ss-in", "listen": "127.0.0.1", "listen_port": 0, "network": "tcp", "method": "2022-blake3-aes-128-gcm", "password": "${ss_password}", "multiplex": { "enabled": true } },
EOF
    fi
}
sbbout(){
    if [ -e "$HOME/sing/sb.json" ]; then
        sed -i '${s/,\s*$//}' "$HOME/sing/sb.json"
        cat >> "$HOME/sing/sb.json" <<EOF
],
"outbounds": [ { "type": "direct", "tag": "direct" } ],
"route": { "final": "direct" }
}
EOF
        if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
            cat > /etc/systemd/system/sb.service <<EOF
[Unit]
Description=sb service
After=network.target
[Service]
Type:simple
NoNewPrivileges=yes
ExecStart=$HOME/sing/sing-box run -c $HOME/sing/sb.json
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload; systemctl enable sb; systemctl start sb
        elif command -v rc-service >/dev/null 2>/dev/null && [ "$EUID" -eq 0 ]; then
            cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="sb service"
command="$HOME/sing/sing-box"
command_args="run -c $HOME/sing/sb.json"
command_background=yes
pidfile="/run/sing-box.pid"
depend() { need net; }
EOF
            chmod +x /etc/init.d/sing-box; rc-update add sing-box default; rc-service sing-box start
        else
            if pgrep -x sing-box >/dev/null 2>&1; then
                echo "Sing-box 已在运行,跳过重复 nohup 启动"
            else
                nohup "$HOME/sing/sing-box" run -c "$HOME/sing/sb.json" >/dev/null 2>&1 &
            fi
        fi
    fi
}
ins(){
    installsb; sbbout
    if [ "$argo" = "tr" ] && [ "$trp" = "yes" ]; then
        echo; echo "=========启用Cloudflared-argo内核========="
        if [ ! -e "$HOME/sing/cloudflared" ]; then
            argocore=$({ curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared || wget -qO- https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared; } | grep -Eo '"[0-9.]+"' | sed -n 1p | tr -d '",')
            echo "下载Cloudflared-argo最新正式版内核:$argocore"
            url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu"
            out="$HOME/sing/cloudflared"
            (curl -Lo "$out" -# --retry 2 "$url") || (wget -O "$out" --tries=2 "$url")
            chmod +x "$HOME/sing/cloudflared"
        fi
        argoport=$(cat "$HOME/sing/port_tr" 2>/dev/null); echo "Trojan" > "$HOME/sing/vlvm"; echo "$argoport" > "$HOME/sing/argoport.log"
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
ExecStart=$HOME/sing/cloudflared tunnel --no-autoupdate --edge-ip-version auto run --token "${ARGO_AUTH}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload; systemctl enable argo; systemctl start argo
            else
                nohup "$HOME/sing/cloudflared" tunnel --no-autoupdate --edge-ip-version auto run --token "${ARGO_AUTH}" >/dev/null 2>&1 &
            fi
            echo "${ARGO_DOMAIN}" > "$HOME/sing/sbargoym.log"; echo "${ARGO_AUTH}" > "$HOME/sing/sbargotoken.log"
        else
            argoname='临时'
            nohup "$HOME/sing/cloudflared" tunnel --url http://localhost:$(cat $HOME/sing/argoport.log) --edge-ip-version auto --no-autoupdate > $HOME/sing/argo.log 2>&1 &
        fi
        echo "申请Argo$argoname隧道中……请稍等"; sleep 8
        if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
            argodomain=$(cat "$HOME/sing/sbargoym.log" 2>/dev/null)
        else
            argodomain=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$HOME/sing/argo.log" 2>/dev/null | head -n 1 | sed 's|https://||')
        fi
        if [ -n "${argodomain}" ]; then echo "Argo$argoname隧道申请成功"; else echo "Argo$argoname隧道申请失败"; fi
    fi
    sleep 5; echo
    if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'sing/(sing-box|cloudflared)' || pgrep -x sing-box >/dev/null 2>&1 ; then
        mkdir -p /usr/local/bin
        SCRIPT_PATH="/usr/local/bin/sing"
        (curl -sL "$singurl" -o "$SCRIPT_PATH") || (wget -qO "$SCRIPT_PATH" "$singurl")
        chmod +x "$SCRIPT_PATH"
        echo "sing脚本进程启动成功,安装完毕" && sleep 2
    else
        echo "sing脚本进程未启动,安装失败" && exit
    fi
}
singstatus(){
    echo "=========当前内核运行状态========="
    procs=$(find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null)
    if echo "$procs" | grep -Eq 'sing/sing-box' || pgrep -x sing-box >/dev/null 2>&1; then echo "Singbox (版本$("$HOME/sing/sing-box" version 2>/dev/null | awk '/version/{print $NF}')):运行中"; else echo "Sing-box:未启用"; fi
    if echo "$procs" | grep -Eq 'sing/cloudflared' || pgrep -x cloudflared >/dev/null 2>&1; then echo "Argo (版本$("$HOME/sing/cloudflared" version 2>/dev/null | awk '{print $3}')):运行中"; else echo "Argo:未启用"; fi
}
cip(){
    ipbest(){ serip=$((curl -s4m5 -k "$v46url" 2>/dev/null)|| (wget -4 -qO- --tries=2 "$v46url" 2>/dev/null)|| (curl -s6m5 -k "$v46url" 2>/dev/null)|| (wget -6 -qO- --tries=2 "$v46url" 2>/dev/null)); serip=$(echo "$serip"|tr -d '\r\n'|head -n1); if echo "$serip"|grep -q ':'; then server_ip="[$serip]"; else server_ip="$serip"; fi; echo "$server_ip" > "$HOME/sing/server_ip.log"; }
    ipchange(){
        v4v6
        v4dq=$( (curl -s4m5 -k https://ip.fm 2>/dev/null | sed -E 's/.*Location: ([^,]+(, [^,]+)*),.*/\1/') || (wget -4 -qO- --tries=2 https://ip.fm 2>/dev/null | grep '<span class="has-text-grey-light">Location:' | tail -n1 | sed -E 's/.*>Location: <\/span>([^<]+)<.*/\1/') )
        v6dq=$( (curl -s6m5 -k https://ip.fm 2>/dev/null | sed -E 's/.*Location: ([^,]+(, [^,]+)*),.*/\1/') || (wget -6 -qO- --tries=2 https://ip.fm 2>/dev/null | grep '<span class="has-text-grey-light">Location:' | tail -n1 | sed -E 's/.*>Location: <\/span>([^<]+)<.*/\1/') )
        if [ -z "$v4" ]; then vps_ipv4='无IPV4'; vps_ipv6="$v6"; location=$v6dq; elif [ -n "$v4" ] && [ -n "$v6" ]; then vps_ipv4="$v4"; vps_ipv6="$v6"; location=$v4dq; else vps_ipv4="$v4"; vps_ipv6='无IPV6'; location=$v4dq; fi
        echo; singstatus; echo; echo "=========当前服务器本地IP情况========="; echo "本地IPV4地址:$vps_ipv4"; echo "本地IPV6地址:$vps_ipv6"; echo "服务器地区:$location"; echo; sleep 2
        if [ "$ippz" = "4" ]; then if [ -z "$v4" ]; then ipbest; else server_ip="$v4"; echo "$server_ip" > "$HOME/sing/server_ip.log"; fi; elif [ "$ippz" = "6" ]; then if [ -z "$v6" ]; then ipbest; else server_ip="[$v6]"; echo "$server_ip" > "$HOME/sing/server_ip.log"; fi; else ipbest; fi
    }
    ipchange; rm -rf "$HOME/sing/jh.txt"; uuid=$(cat "$HOME/sing/uuid"); server_ip=$(cat "$HOME/sing/server_ip.log"); sxname=$(cat "$HOME/sing/name" 2>/dev/null);
    echo "*********************************************************"; echo "sing脚本输出节点配置如下:"; echo;
    if grep -q '"tag": "hy2"' "$HOME/sing/sb.json"; then port_hy2=$(cat "$HOME/sing/port_hy2"); hy2_link="hysteria2://$uuid@$server_ip:$port_hy2?security=tls&insecure=1&sni=www.icloud.com#${sxname}hy2-$hostname"; echo "【 Hysteria2 】"; echo "$hy2_link" | tee -a "$HOME/sing/jh.txt"; echo; fi
    if grep -q '"tag": "tuic"' "$HOME/sing/sb.json"; then port_tuic=$(cat "$HOME/sing/port_tuic"); tuic_link="tuic://${uuid}:${uuid}@${server_ip}:${port_tuic}?congestion_control=bbr&udp_relay_mode=native&sni=www.icloud.com&allow_insecure=1#${sxname}tuic-$hostname"; echo "【 TUIC 】"; echo "$tuic_link" | tee -a "$HOME/sing/jh.txt"; echo; fi
    if grep -q '"tag": "vless-reality"' "$HOME/sing/sb.json"; then
        port_vlr=$(cat "$HOME/sing/port_vlr")
        public_key=$(sed -n '2p' "$HOME/sing/reality.key" | awk '{print $2}')
        short_id=$(cat "$HOME/sing/short_id")
        vless_link="vless://${uuid}@${server_ip}:${port_vlr}?encryption=none&security=reality&sni=www.icloud.com&fp=chrome&flow=xtls-rprx-vision&publicKey=${public_key}&shortId=${short_id}&tfo=true#${sxname}vless-reality-$hostname"
        echo "【 VLESS-Reality-Vision 】"; echo "$vless_link" | tee -a "$HOME/sing/jh.txt"; echo;
    fi
    if grep -q '"tag": "snell"' "$HOME/sing/sb.json"; then
        port_snell=$(cat "$HOME/sing/port_snell")
        snell_psk=$(cat "$HOME/sing/snell_psk")
        snell_link="snell://${snell_psk}@${server_ip}:${port_snell}?version=5&reuse=true&tfo=true#${sxname}snell-$hostname"
        echo "【 Snell 】"
        echo "$snell_link" | tee -a "$HOME/sing/jh.txt"
        echo
    fi
    if grep -q '"tag": "shadowtls"' "$HOME/sing/sb.json"; then
        port_st=$(cat "$HOME/sing/port_st")
        st_password=$(cat "$HOME/sing/st_password" 2>/dev/null || echo "$uuid")
        ss_password=$(cat "$HOME/sing/ss_password" 2>/dev/null || echo "$uuid")
        echo "【 SS2022 】"
        cat <<EOF | tee -a "$HOME/sing/jh.txt"
- {"name":"SS2022-shadowtls","type":"ss","server":"${server_ip}","port":${port_st},"tfo":true,"cipher":"2022-blake3-aes-128-gcm","password":"${ss_password}","plugin":"shadow-tls","client-fingerprint":"chrome","plugin-opts":{"host":"www.icloud.com","password":"${st_password}","version":3},"h2mux":{"enabled":true}}
EOF
        echo
    fi
    argodomain=$(cat "$HOME/sing/sbargoym.log" 2>/dev/null); [ -z "$argodomain" ] && argodomain=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$HOME/sing/argo.log" 2>/dev/null | head -n 1 | sed 's|https://||')
    if [ -n "$argodomain" ]; then
        vlvm=$(cat $HOME/sing/vlvm 2>/dev/null); uuid=$(cat "$HOME/sing/uuid")
        if [ "$vlvm" = "Trojan" ]; then
            tratls_link1="trojan://${uuid}@saas.sin.fan:443?security=tls&type=ws&host=${argodomain}&path=%2Ftr&sni=${argodomain}&fp=chrome&tfo=true#${sxname}trojan-ws-tls-argo-$hostname-443"
            sbtk=$(cat "$HOME/sing/sbargotoken.log" 2>/dev/null); [ -n "$sbtk" ] && nametn="Argo固定隧道token:\n$sbtk"
            argoshow="Argo隧道信息 (使用Trojan-ws端口: $(cat $HOME/sing/argoport.log 2>/dev/null))\n---------------------------------------------------------\nArgo域名: ${argodomain}\n\n${nametn}\n\n 【Argo-TLS节点】 (优选域名可替换):\n${tratls_link1}"
            echo "---------------------------------------------------------"; echo -e "$argoshow"; echo "---------------------------------------------------------"
        fi
    fi
    echo; echo "聚合节点: cat $HOME/sing/jh.txt"; echo "========================================================="; echo "相关快捷方式如下:"; showmode
}
cleandel(){
    if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
        for svc in sb argo; do systemctl stop "$svc" >/dev/null 2>&1; systemctl disable "$svc" >/dev/null 2>&1; done
        rm -f /etc/systemd/system/{sb.service,argo.service}
        systemctl daemon-reload >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>/dev/null && [ "$EUID" -eq 0 ]; then
        for svc in sing-box argo; do rc-service "$svc" stop >/dev/null 2>&1; rc-update del "$svc" default >/dev/null 2>&1; done
        rm -f /etc/init.d/{sing-box,argo}
    fi
    for P in /proc/[0-9]*; do if [ -L "$P/exe" ]; then TARGET=$(readlink -f "$P/exe" 2>/dev/null); if echo "$TARGET" | grep -qE '/sing/cloudflared|/sing/sing-box'; then kill -9 "$(basename "$P")" 2>/dev/null; fi; fi; done
    kill -9 $(pgrep -x cloudflared 2>/dev/null) $(pgrep -x sing-box 2>/dev/null) >/dev/null 2>&1
    rm -f /usr/local/bin/sing "$HOME/bin/sing"
}
sbrestart(){
    kill -15 $(pgrep -x sing-box 2>/dev/null) >/dev/null 2>&1
    if pidof systemd >/dev/null 2>&1; then
        systemctl restart sb
    elif command -v rc-service >/dev/null 2>/dev/null; then
        rc-service sing-box restart
    else
        nohup "$HOME/sing/sing-box" run -c "$HOME/sing/sb.json" >/dev/null 2>&1 &
    fi
}
argorestart(){
    kill -15 $(pgrep -x cloudflared 2>/dev/null) >/dev/null 2>&1
    if pidof systemd >/dev/null 2>&1; then
        systemctl restart argo
    elif command -v rc-service >/dev/null 2>/dev/null; then
        rc-service argo restart
    else
        if [ -e "$HOME/sing/sbargotoken.log" ]; then
            nohup "$HOME/sing/cloudflared" tunnel --no-autoupdate --edge-ip-version auto run --token $(cat $HOME/sing/sbargotoken.log) >/dev/null 2>&1 &
        else
            nohup "$HOME/sing/cloudflared" tunnel --url http://localhost:$(cat $HOME/sing/argoport.log) --edge-ip-version auto --no-autoupdate > $HOME/sing/argo.log 2>&1 &
        fi
    fi
}
if [ "$1" = "del" ]; then cleandel; rm -rf "$HOME/sing"; echo "卸载完成"; showmode; exit; fi
if [ "$1" = "rep" ]; then cleandel; rm -rf "$HOME/sing"/{sb.json,sbargoym.log,sbargotoken.log,argo.log,argoport.log,cdnym,name,port_tuic,port_hy2,port_tr,port_vlr,port_snell,port_st,reality.key,short_id,uuid,vlvm,server_ip.log,snell_psk,st_password,ss_password}; echo "重置完成..."; sleep 2; fi
if [ "$1" = "list" ]; then cip; exit; fi
if [ "$1" = "ups" ]; then kill -15 $(pgrep -x sing-box 2>/dev/null); upsingbox && sbrestart && echo "Sing-box内核更新完成" && sleep 2 && cip; exit; fi
if [ "$1" = "res" ]; then sbrestart; argorestart; sleep 5 && echo "重启完成" && sleep 3 && cip; exit; fi
if ! pgrep -x sing-box >/dev/null 2>&1 && [ "$1" != "rep" ]; then cleandel; fi
if ! pgrep -x sing-box >/dev/null 2>&1 || [ "$1" = "rep" ]; then
    if [ -z "$( (curl -s4m5 -k "$v46url") || (wget -4 -qO- --tries=2 "$v46url") )" ]; then echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf; fi
    echo "VPS系统:$op"; echo "CPU架构:$cpu"; echo "sing脚本开始安装/更新…………" && sleep 1
    if [ -n "$oap" ]; then setenforce 0 >/dev/null 2>&1; iptables -F; iptables -P INPUT ACCEPT; netfilter-persistent save >/dev/null 2>&1; echo "iptables执行开放所有端口"; fi
    ins; cip
else
    echo "sing脚本已安装"; echo; singstatus; echo; echo "相关快捷方式如下:"; showmode; exit
fi