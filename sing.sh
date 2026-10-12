#!/usr/bin/env bash
export LANG=en_US.UTF-8
check_deps() {
    local missing=0
    for cmd in curl wget openssl grep sed awk tr shuf pgrep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing=1
            break
        fi
    done
    if ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
        missing=1
    fi
    if [ "$missing" -eq 1 ]; then
        local OS=""
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
        else
            OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        fi
        install_pkg() {
            case "$OS" in
                debian|ubuntu)
                    apt-get update >/dev/null 2>&1
                    apt-get install -y curl wget openssl grep sed gawk coreutils procps util-linux iproute2 net-tools >/dev/null 2>&1
                    ;;
                centos|rhel|fedora|rocky|alma)
                    if command -v dnf >/dev/null 2>&1; then
                        dnf install -y curl wget openssl grep sed gawk coreutils procps util-linux iproute net-tools >/dev/null 2>&1
                    else
                        yum install -y curl wget openssl grep sed gawk coreutils procps util-linux iproute net-tools >/dev/null 2>&1
                    fi
                    ;;
                alpine)
                    apk add --no-cache curl wget openssl grep sed gawk coreutils procps util-linux iproute2 iproute2-tc kmod net-tools >/dev/null 2>&1
                    ;;
                arch|manjaro)
                    pacman -Sy --noconfirm curl wget openssl grep sed gawk coreutils procps util-linux iproute2 net-tools >/dev/null 2>&1
                    ;;
                opensuse*)
                    zypper install -y curl wget openssl grep sed gawk coreutils procps util-linux iproute2 net-tools >/dev/null 2>&1
                    ;;
            esac
        }
        if [ "$EUID" -ne 0 ]; then
            if command -v sudo >/dev/null 2>&1; then
                sudo bash -c "$(declare -f install_pkg); install_pkg" >/dev/null 2>&1
            fi
        else
            install_pkg >/dev/null 2>&1
        fi
    fi
}
check_deps

# 设置系统时区为 Asia/Shanghai (UTC+8)
if command -v timedatectl >/dev/null 2>&1; then
    ([ "$EUID" -eq 0 ] && timedatectl set-timezone Asia/Shanghai || sudo timedatectl set-timezone Asia/Shanghai) >/dev/null 2>&1 || true
else
    if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
        ([ "$EUID" -eq 0 ] && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime) 2>/dev/null || true
        ([ "$EUID" -eq 0 ] && echo "Asia/Shanghai" >/etc/timezone || sudo sh -c 'echo "Asia/Shanghai" >/etc/timezone') 2>/dev/null || true
    elif [ -f /etc/alpine-release ]; then
        ([ "$EUID" -eq 0 ] && apk add --no-cache tzdata >/dev/null 2>&1 || sudo apk add --no-cache tzdata >/dev/null 2>&1)
        [ -f /usr/share/zoneinfo/Asia/Shanghai ] && ([ "$EUID" -eq 0 ] && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime) 2>/dev/null || true
    fi
fi
export TZ=Asia/Shanghai

# ==================== BBR 优化（仅在安装或 sing bbr 时执行） ====================
MTU="${MTU:-1500}"
FQ_QUANTUM="${FQ_QUANTUM:-18028}"
FQ_INITIAL_QUANTUM="${FQ_INITIAL_QUANTUM:-90140}"
TCP_WMEM_MAX="${TCP_WMEM_MAX:-12582912}"
TCP_RMEM_MAX="${TCP_RMEM_MAX:-33554432}"
TCP_LIMIT_OUTPUT_BYTES="${TCP_LIMIT_OUTPUT_BYTES:-4194304}"
SYSCTL_FILE="${SYSCTL_FILE:-/etc/sysctl.d/99-bbr-optimization.conf}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/bbr-fq-optimization.service}"

need_cmd() {
        if ! command -v "$1" >/dev/null 2>&1; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update -qy >/dev/null 2>&1 || true
                apt-get install -y iproute2 python3 >/dev/null 2>&1 || true
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y iproute python3 >/dev/null 2>&1 || true
            elif command -v yum >/dev/null 2>&1; then
                yum install -y iproute python3 >/dev/null 2>&1 || true
            elif command -v apk >/dev/null 2>&1; then
                apk add --no-cache iproute2 iproute2-tc kmod python3 >/dev/null 2>&1 || true
            elif command -v pacman >/dev/null 2>&1; then
                pacman -Sy --noconfirm iproute2 python3 >/dev/null 2>&1 || true
            fi
        fi
    }

    detect_iface() {
        local detected
        detected="$(ip route show default 2>/dev/null | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
        [ -z "$detected" ] && detected="$(ip -6 route show default 2>/dev/null | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
        [ -z "$detected" ] && detected="eth0"
        echo "$detected"
    }

    verify_sysctl() {
        local cc qd wmem rmem lob ssai
        cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
        qd="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
        wmem="$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"
        rmem="$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
        lob="$(sysctl -n net.ipv4.tcp_limit_output_bytes 2>/dev/null)"
        ssai="$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null)"
        echo "  当前生效的网络参数:"
        echo "    tcp_congestion_control:    ${cc}"
        echo "    default_qdisc:             ${qd}"
        echo "    tcp_wmem:                  ${wmem}"
        echo "    tcp_rmem:                  ${rmem}"
        echo "    tcp_limit_output_bytes:    ${lob}"
        echo "    tcp_slow_start_after_idle: ${ssai}"
        [ "$cc" = "bbr" ] || echo "  ⚠️ 警告: 当前拥塞控制为 '${cc}', 不是 bbr; 请确认内核是否支持 bbr(可能需升级内核或加载 tcp_bbr 模块)"
        [ "$qd" = "fq" ] || echo "  ℹ️ 说明: default_qdisc=\"${qd}\" 仅影响新建网卡的默认队列; 实际 BBR pacing 以下方网卡 fq 状态为准"
    }

    write_sysctl() {
        cat > "${SYSCTL_FILE}" <<EOF
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_wmem = 4096 16384 ${TCP_WMEM_MAX}
net.ipv4.tcp_rmem = 4096 131072 ${TCP_RMEM_MAX}
net.ipv4.tcp_limit_output_bytes = ${TCP_LIMIT_OUTPUT_BYTES}
net.ipv4.tcp_slow_start_after_idle = 0
EOF
        sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1 || {
            sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
            sysctl -w net.core.default_qdisc=fq 2>/dev/null || true
            sysctl -w net.ipv4.tcp_wmem="4096 16384 ${TCP_WMEM_MAX}" 2>/dev/null || true
            sysctl -w net.ipv4.tcp_rmem="4096 131072 ${TCP_RMEM_MAX}" 2>/dev/null || true
            sysctl -w net.ipv4.tcp_limit_output_bytes="${TCP_LIMIT_OUTPUT_BYTES}" 2>/dev/null || true
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 2>/dev/null || true
        }
        verify_sysctl
    }

    apply_fq_qdisc() {
        local iface="$1"
        local tcbin; tcbin="$(command -v tc 2>/dev/null || echo /usr/sbin/tc)"
        if [ -d /run/systemd/system ]; then
            cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=BBR + fq qdisc optimization
After=network-online.target

[Service]
Type=oneshot
ExecStartPre=-${tcbin} qdisc del dev ${iface} root
ExecStart=${tcbin} qdisc add dev ${iface} root fq quantum ${FQ_QUANTUM} initial_quantum ${FQ_INITIAL_QUANTUM}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable --now "$(basename "${SERVICE_FILE}")" >/dev/null 2>&1 || true
        elif command -v rc-service >/dev/null 2>&1; then
            cat > /etc/init.d/bbr-optimization <<EOF
#!/sbin/openrc-run
description="BBR + fq qdisc optimization"
depend() { need net; after net; }
start() {
    sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1 || true
    ${tcbin} qdisc del dev ${iface} root 2>/dev/null || true
    ${tcbin} qdisc add dev ${iface} root fq quantum ${FQ_QUANTUM} initial_quantum ${FQ_INITIAL_QUANTUM} 2>/dev/null || true
    return 0
}
EOF
            chmod +x /etc/init.d/bbr-optimization
            rc-update add bbr-optimization default >/dev/null 2>&1 || true
            rc-service bbr-optimization restart >/dev/null 2>&1 || rc-service bbr-optimization start >/dev/null 2>&1 || true
        else
            "${tcbin}" qdisc del dev "${iface}" root 2>/dev/null || true
            "${tcbin}" qdisc add dev "${iface}" root fq quantum "${FQ_QUANTUM}" initial_quantum "${FQ_INITIAL_QUANTUM}" 2>/dev/null || true
        fi
        if "${tcbin}" qdisc show dev "${iface}" 2>/dev/null | grep -qw fq; then
            echo "  ✔ 已在网卡 ${iface} 启用 fq 队列(BBR + FQ 生效)"
        else
            echo "  ⚠️ 警告: 网卡 ${iface} 未能启用 fq 队列; 可能内核缺少 sch_fq 模块或未安装 tc(Alpine 需 iproute2-tc)。BBR 仍生效, 但缺少 fq 的 pacing 优化"
        fi
    }

apply_bbr() {
    [ "$EUID" -eq 0 ] || { echo "提示: 非 root 用户，跳过 BBR 优化"; return 0; }
    need_cmd ip; need_cmd tc; need_cmd sysctl
    # Alpine: tc 在 iproute2-tc 子包, 模块加载需 kmod; 补装以确保 fq 可用
    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache iproute2-tc kmod >/dev/null 2>&1 || true
    fi
    # 预加载内核模块: 部分精简内核/VPS 上 bbr 与 fq 为模块且未自动加载
    command -v depmod >/dev/null 2>&1 && depmod -a >/dev/null 2>&1 || true
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        echo "  ⚠️ 警告: 当前内核可用拥塞控制算法中未发现 bbr, 可能无法启用(建议升级内核)"
    fi
    local iface; iface=$(detect_iface)
    ip link set dev "${iface}" mtu "${MTU}" 2>/dev/null || true
    write_sysctl
    apply_fq_qdisc "$iface"
}

remove_bbr() {
    [ "$EUID" -eq 0 ] || return 0
    if [ -d /run/systemd/system ]; then
        systemctl disable --now "$(basename "${SERVICE_FILE}")" >/dev/null 2>&1 || true
        rm -f "${SERVICE_FILE}"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service bbr-optimization stop >/dev/null 2>&1 || true
        rc-update del bbr-optimization default >/dev/null 2>&1 || true
        rm -f /etc/init.d/bbr-optimization
    fi
    rm -f "${SYSCTL_FILE}"
}

# 进程检测: 优先 pgrep, 回退到读取 /proc/*/exe 链接(应对进程被改名的情况)
sb_running() { pgrep -x sing-box >/dev/null 2>&1 || { find /proc/*/exe -type l 2>/dev/null | xargs -r readlink 2>/dev/null | grep -q 'sing/sing-box'; }; }
cf_running() { pgrep -x cloudflared >/dev/null 2>&1 || { find /proc/*/exe -type l 2>/dev/null | xargs -r readlink 2>/dev/null | grep -q 'sing/cloudflared'; }; }
# ==================== BBR 优化定义结束 ====================

[ -z "${tr+x}" ] || trp=yes
[ -z "${hy+x}" ] || hyp=yes
[ -z "${vr+x}" ] || vrp=yes
[ -z "${sn+x}" ] || snp=yes
[ -z "${ss+x}" ] || ssp=yes
[ -z "${tu+x}" ] || tup=yes

# 只要设置 tr 就自动启用 Argo
if [ "$trp" = "yes" ]; then
    argo="tr"
fi

if [ "$1" = "list" ] || [ "$1" = "del" ] || [ "$1" = "res" ] || [ "$1" = "ups" ] || [ "$1" = "bbr" ]; then
    :
elif sb_running; then
    if [ "$1" = "rep" ]; then
        [ "$vrp" = yes ] || [ "$trp" = yes ] || [ "$hyp" = yes ] || [ "$snp" = yes ] || [ "$ssp" = yes ] || [ "$tup" = yes ] || { echo "提示:rep重置协议时,请在脚本前至少设置一个协议变量哦,再见!"; exit; }
    fi
else
    [ "$vrp" = yes ] || [ "$trp" = yes ] || [ "$hyp" = yes ] || [ "$snp" = yes ] || [ "$ssp" = yes ] || [ "$tup" = yes ] || { echo "提示:未安装sing脚本,请在脚本前至少设置一个协议变量哦,再见!"; exit; }
fi

export uuid=${uuid:-''}; export port_tr=${tr:-''}; export port_hy2=${hy:-''}; export port_vrp=${vr:-''}; export port_snell=${sn:-''}; export port_ss=${ss:-''}; export port_tuic=${tu:-''}; export cdnym=${cdnym:-''}; export argo=${argo:-''}; export ARGO_DOMAIN=${agn:-''}; export ARGO_AUTH=${agk:-''}; export ippz=${ippz:-''}; export name=${name:-''}; export oap=${oap:-''}
v46url="https://icanhazip.com"
singurl="https://raw.githubusercontent.com/77160860/proxy/main/sing.sh"

showmode(){
    echo "sing脚本 (singbox内核版)"
    echo "主脚本:bash <(curl -Ls ${singurl}) 或 bash <(wget -qO- ${singurl})"
    echo "显示节点命令:sing list"
    echo "重置变量命令:sing rep"
    echo "更新内核命令:sing ups"
    echo "重启脚本命令:sing res"
    echo "卸载脚本命令:sing del"
    echo "BBR优化命令:sing bbr"
    echo "---------------------------------------------------------"
}

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "sing一键无交互脚本 (singbox内核版)"
echo "当前版本:26.10.08"
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

# 统一的端口解析: $1=协议显示名 $2=用户请求的端口值 $3=端口缓存文件; 结果写入全局 REPLY_PORT
resolve_port(){
    local label="$1" want="$2" file="$3" p old
    if [ "$want" = "yes" ] || [[ ! "$want" =~ ^[0-9]+$ ]]; then want=""; fi
    if [ -n "$want" ]; then
        p="$want"
        if port_in_use "$p"; then old="$p"; p=$(get_free_port); echo "警告: ${label} 指定端口 $old 已被占用, 自动更换为新端口: $p"; fi
    elif [ -e "$file" ]; then
        p=$(cat "$file")
        if port_in_use "$p" || [[ ! "$p" =~ ^[0-9]+$ ]]; then old="$p"; p=$(get_free_port); echo "警告: ${label} 缓存端口 $old 异常或已被占用, 自动更换为新端口: $p"; fi
    else
        p=$(get_free_port)
    fi
    echo "$p" > "$file"
    REPLY_PORT="$p"
}

upsingbox(){
    url="https://github.com/77160860/proxy/releases/download/singbox/sing-box-$cpu"
    out="$HOME/sing/sing-box"
    (curl -Lo "$out" -# --retry 2 "$url") || (wget -O "$out" --tries=2 "$url")
    chmod +x "$HOME/sing/sing-box"
    sbcore=$("$HOME/sing/sing-box" version 2>/dev/null | awk '/version/{print $NF}')
    echo "已安装Singbox内核:$sbcore"
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
    [ -n "$name" ] && echo "$name" > "$HOME/sing/name"
    [ -n "$cdnym" ] && echo "$cdnym" > "$HOME/sing/cdnym"
    cat > "$HOME/sing/sb.json" <<EOF
{
"log": { "disabled": false, "level": "error", "timestamp": true, "output": "$HOME/sing/sing.log"},
"inbounds": [
EOF
    insuuid
    openssl ecparam -genkey -name prime256v1 -out "$HOME/sing/private.key" >/dev/null 2>&1
    openssl req -new -x509 -days 36500 -key "$HOME/sing/private.key" -out "$HOME/sing/cert.pem" -subj "/CN=www.icloud.com" >/dev/null 2>&1

    if [ -n "$hyp" ]; then
        resolve_port "Hysteria2" "$port_hy2" "$HOME/sing/port_hy2"; port_hy2="$REPLY_PORT"; echo "Hysteria2端口:$port_hy2"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "hysteria2", "tag": "hy2", "listen": "::", "listen_port": ${port_hy2},"users": [ { "password": "${uuid}" } ],"tls": { "enabled": true, "certificate_path": "$HOME/sing/cert.pem", "key_path": "$HOME/sing/private.key" }},
EOF
    fi

    if [ -n "$snp" ]; then
        resolve_port "Snell" "$port_snell" "$HOME/sing/port_snell"; port_snell="$REPLY_PORT"; echo "Snell端口:$port_snell"
        snell_psk="${uuid}"
        echo "$snell_psk" > "$HOME/sing/snell_psk"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "snell", "tag": "snell", "listen": "::", "listen_port": ${port_snell}, "psk": "${snell_psk}", "tcp_fast_open": true, "version": 6},
EOF
    fi

    if [ -n "$trp" ]; then
        resolve_port "Trojan" "$port_tr" "$HOME/sing/port_tr"; port_tr="$REPLY_PORT"; echo "Trojan端口(Argo本地使用):$port_tr"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "trojan", "tag": "trojan-ws", "listen": "::", "listen_port": ${port_tr}, "tcp_fast_open": true, "users": [ { "password": "${uuid}" } ],"transport": { "type": "ws", "path": "/tr" }},
EOF
    fi

    if [ -n "$vrp" ]; then
        resolve_port "VLESS-Reality" "$port_vrp" "$HOME/sing/port_vrp"; port_vrp="$REPLY_PORT"; echo "VLESS-Reality端口:$port_vrp"
        if [ ! -f "$HOME/sing/reality.key" ]; then "$HOME/sing/sing-box" generate reality-keypair > "$HOME/sing/reality.key"; fi
        private_key=$(sed -n '1p' "$HOME/sing/reality.key" | awk '{print $2}')
        [ -f "$HOME/sing/short_id" ] && short_id=$(cat "$HOME/sing/short_id") || { short_id=$(openssl rand -hex 4); echo "$short_id" > "$HOME/sing/short_id"; }
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "vless", "tag": "vless-reality", "listen": "::", "listen_port": ${port_vrp}, "tcp_fast_open": true, "users": [{"uuid": "${uuid}","flow": "xtls-rprx-vision"}],"tls": {"enabled": true,"server_name": "www.ua.edu","reality": {"enabled": true,"handshake": {"server": "www.ua.edu","server_port": 443},"private_key": "${private_key}","short_id": ["${short_id}"]}}},
EOF
    fi

    if [ -n "$ssp" ]; then
        resolve_port "ShadowTLS" "$port_ss" "$HOME/sing/port_ss"; port_ss="$REPLY_PORT"; echo "SS2022端口:$port_ss"
        st_password="${uuid}"
        ss_password=$(openssl rand -base64 16)
        echo "$st_password" > "$HOME/sing/st_password"
        echo "$ss_password" > "$HOME/sing/ss_password"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "shadowtls", "tag": "shadowtls", "listen": "::", "listen_port": ${port_ss}, "tcp_fast_open": true, "version": 3, "users": [ { "password": "${st_password}" } ], "handshake": { "server": "www.icloud.com", "server_port": 443 }, "strict_mode": true, "detour": "ss-in" },
{"type": "shadowsocks", "tag": "ss-in", "listen": "127.0.0.1", "listen_port": 0, "network": "tcp", "method": "2022-blake3-aes-128-gcm", "password": "${ss_password}", "multiplex": { "enabled": true } },
EOF
    fi

    if [ -n "$tup" ]; then
        resolve_port "TUIC" "$port_tuic" "$HOME/sing/port_tuic"; port_tuic="$REPLY_PORT"; echo "TUIC端口:$port_tuic"
        cat >> "$HOME/sing/sb.json" <<EOF
{"type": "tuic", "tag": "tuic", "listen": "::", "listen_port": ${port_tuic}, "users": [{"uuid": "${uuid}", "password": "${uuid}"}], "congestion_control": "bbr", "tls": {"enabled": true, "alpn": ["h3"], "certificate_path": "$HOME/sing/cert.pem", "key_path": "$HOME/sing/private.key"}},
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
        if [ -d /run/systemd/system ] && [ "$EUID" -eq 0 ]; then
            cat > /etc/systemd/system/sb.service <<EOF
[Unit]
Description=sb service
After=network.target
[Service]
Type=simple
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
    echo; echo "=========执行 BBR 网络优化========="; apply_bbr
    if [ "$trp" = "yes" ]; then
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
            if [ -d /run/systemd/system ] && [ "$EUID" -eq 0 ]; then
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
            elif command -v rc-service >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
                cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="$HOME/sing/cloudflared"
command_args="tunnel --no-autoupdate --edge-ip-version auto run --token ${ARGO_AUTH}"
command_background=yes
pidfile="/run/argo.pid"
depend() { need net; }
EOF
                chmod +x /etc/init.d/argo; rc-update add argo default; rc-service argo restart >/dev/null 2>&1 || rc-service argo start
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
    if sb_running || cf_running ; then
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
    if sb_running; then echo "Singbox (版本$("$HOME/sing/sing-box" version 2>/dev/null | awk '/version/{print $NF}')):运行中"; else echo "Sing-box:未启用"; fi
    if cf_running; then echo "Argo (版本$("$HOME/sing/cloudflared" version 2>/dev/null | awk '{print $3}')):运行中"; else echo "Argo:未启用"; fi
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
    ipchange; rm -rf "$HOME/sing/jh.txt"; uuid=$(cat "$HOME/sing/uuid"); sxname=$(cat "$HOME/sing/name" 2>/dev/null);
    # 构建待输出的服务器地址列表: 默认双栈同时输出 v4 和 v6; ippz=4/6 时只输出指定版本
    ip_list=(); ip_tags=()
    if [ "$ippz" = "4" ]; then
        if [ -n "$v4" ]; then ip_list+=("$v4"); ip_tags+=("v4"); else ip_list+=("$(cat "$HOME/sing/server_ip.log")"); ip_tags+=(""); fi
    elif [ "$ippz" = "6" ]; then
        if [ -n "$v6" ]; then ip_list+=("[$v6]"); ip_tags+=("v6"); else ip_list+=("$(cat "$HOME/sing/server_ip.log")"); ip_tags+=(""); fi
    else
        [ -n "$v4" ] && { ip_list+=("$v4"); ip_tags+=("v4"); }
        [ -n "$v6" ] && { ip_list+=("[$v6]"); ip_tags+=("v6"); }
        [ "${#ip_list[@]}" -eq 0 ] && { ip_list+=("$(cat "$HOME/sing/server_ip.log")"); ip_tags+=(""); }
    fi
    echo "*********************************************************"; echo "sing脚本输出节点配置如下:"; echo;
    if grep -q '"tag": "hy2"' "$HOME/sing/sb.json"; then port_hy2=$(cat "$HOME/sing/port_hy2"); echo "【 Hysteria2 】"; for i in "${!ip_list[@]}"; do server_ip="${ip_list[$i]}"; tag="${ip_tags[$i]}"; [ -n "$tag" ] && sfx="-$tag" || sfx=""; hy2_link="hysteria2://$uuid@$server_ip:$port_hy2?security=tls&insecure=1&sni=www.icloud.com#${sxname}hy2-$hostname$sfx"; echo "$hy2_link" | tee -a "$HOME/sing/jh.txt"; done; echo; fi
    if grep -q '"tag": "vless-reality"' "$HOME/sing/sb.json"; then
        port_vrp=$(cat "$HOME/sing/port_vrp")
        public_key=$(sed -n '2p' "$HOME/sing/reality.key" | awk '{print $2}')
        short_id=$(cat "$HOME/sing/short_id")
        echo "【 VLESS-Reality-Vision 】"
        for i in "${!ip_list[@]}"; do server_ip="${ip_list[$i]}"; tag="${ip_tags[$i]}"; [ -n "$tag" ] && sfx="-$tag" || sfx=""; vless_link="vless://${uuid}@${server_ip}:${port_vrp}/?type=tcp&encryption=none&flow=xtls-rprx-vision&sni=www.ua.edu&fp=chrome&security=reality&pbk=${public_key}&sid=${short_id}&tfo=true#${sxname}vless-reality-$hostname$sfx"; echo "$vless_link" | tee -a "$HOME/sing/jh.txt"; done; echo;
    fi
    if grep -q '"tag": "snell"' "$HOME/sing/sb.json"; then
        port_snell=$(cat "$HOME/sing/port_snell")
        snell_psk=$(cat "$HOME/sing/snell_psk")
        echo "【 Snell 】"
        for i in "${!ip_list[@]}"; do server_ip="${ip_list[$i]}"; tag="${ip_tags[$i]}"; [ -n "$tag" ] && sfx="-$tag" || sfx=""; snell_link="snell://${snell_psk}@${server_ip}:${port_snell}?version=6&reuse=true&tfo=true#${sxname}snell-$hostname$sfx"; echo "$snell_link" | tee -a "$HOME/sing/jh.txt"; done
        echo
    fi
    if grep -q '"tag": "shadowtls"' "$HOME/sing/sb.json"; then
        port_ss=$(cat "$HOME/sing/port_ss")
        st_password=$(cat "$HOME/sing/st_password" 2>/dev/null || echo "$uuid")
        ss_password=$(cat "$HOME/sing/ss_password" 2>/dev/null || echo "$uuid")
        echo "【 SS2022 】"
        for i in "${!ip_list[@]}"; do server_ip="${ip_list[$i]}"; tag="${ip_tags[$i]}"; [ -n "$tag" ] && sfx="-$tag" || sfx=""; ss_server="${server_ip#[}"; ss_server="${ss_server%]}"; echo "- {\"name\":\"SS2022-shadowtls$sfx\",\"type\":\"ss\",\"server\":\"${ss_server}\",\"port\":${port_ss},\"tfo\":true,\"cipher\":\"2022-blake3-aes-128-gcm\",\"password\":\"${ss_password}\",\"plugin\":\"shadow-tls\",\"client-fingerprint\":\"chrome\",\"plugin-opts\":{\"host\":\"www.icloud.com\",\"password\":\"${st_password}\",\"version\":3},\"smux\":{\"enabled\":true}}" | tee -a "$HOME/sing/jh.txt"; done
        echo
    fi
    if grep -q '"tag": "tuic"' "$HOME/sing/sb.json"; then
        port_tuic=$(cat "$HOME/sing/port_tuic")
        echo "【 TUIC 】"
        for i in "${!ip_list[@]}"; do server_ip="${ip_list[$i]}"; tag="${ip_tags[$i]}"; [ -n "$tag" ] && sfx="-$tag" || sfx=""; tuic_link="tuic://${uuid}:${uuid}@${server_ip}:${port_tuic}?congestion_control=bbr&udp_relay_mode=native&sni=www.icloud.com&insecure=1#${sxname}tuic-$hostname$sfx"; echo "$tuic_link" | tee -a "$HOME/sing/jh.txt"; done; echo;
    fi
    argodomain=$(cat "$HOME/sing/sbargoym.log" 2>/dev/null); [ -z "$argodomain" ] && argodomain=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$HOME/sing/argo.log" 2>/dev/null | head -n 1 | sed 's|https://||')
    if [ -n "$argodomain" ]; then
        vlvm=$(cat $HOME/sing/vlvm 2>/dev/null); uuid=$(cat "$HOME/sing/uuid")
        if [ "$vlvm" = "Trojan" ]; then
            cdn_host=$(cat "$HOME/sing/cdnym" 2>/dev/null); [ -z "$cdn_host" ] && cdn_host="saas.sin.fan"
            tratls_link1="trojan://${uuid}@${cdn_host}:443?security=tls&type=ws&host=${argodomain}&path=%2Ftr&sni=${argodomain}&fp=chrome&tfo=true#${sxname}trojan-ws-tls-argo-$hostname-443"
            sbtk=$(cat "$HOME/sing/sbargotoken.log" 2>/dev/null); [ -n "$sbtk" ] && nametn="Argo固定隧道token:\n$sbtk"
            argoshow="Argo隧道信息 (使用Trojan-ws端口: $(cat $HOME/sing/argoport.log 2>/dev/null))\n---------------------------------------------------------\nArgo域名: ${argodomain}\n\n${nametn}\n\n 【Argo-TLS节点】 (优选域名可替换):\n${tratls_link1}"
            echo "---------------------------------------------------------"; echo -e "$argoshow"; echo "---------------------------------------------------------"
        fi
    fi
    echo; echo "聚合节点: cat $HOME/sing/jh.txt"; echo "========================================================="; echo "相关快捷方式如下:"; showmode
}

cleandel(){
    if [ -d /run/systemd/system ] && [ "$EUID" -eq 0 ]; then
        for svc in sb argo; do systemctl stop "$svc" >/dev/null 2>&1; systemctl disable "$svc" >/dev/null 2>&1; done
        rm -f /etc/systemd/system/{sb.service,argo.service}
        systemctl daemon-reload >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>/dev/null && [ "$EUID" -eq 0 ]; then
        for svc in sing-box argo; do rc-service "$svc" stop >/dev/null 2>&1; rc-update del "$svc" default >/dev/null 2>&1; done
        rm -f /etc/init.d/{sing-box,argo}
    fi
    for P in /proc/[0-9]*; do if [ -L "$P/exe" ]; then TARGET=$(readlink -f "$P/exe" 2>/dev/null); if echo "$TARGET" | grep -qE '/sing/cloudflared|/sing/sing-box'; then kill -9 "$(basename "$P")" 2>/dev/null; fi; fi; done
    kill -9 $(pgrep -x cloudflared 2>/dev/null) $(pgrep -x sing-box 2>/dev/null) >/dev/null 2>&1
    rm -f /usr/local/bin/sing
}

sbrestart(){
    kill -15 $(pgrep -x sing-box 2>/dev/null) >/dev/null 2>&1
    if [ -d /run/systemd/system ]; then
        systemctl restart sb
    elif command -v rc-service >/dev/null 2>/dev/null; then
        rc-service sing-box restart
    else
        nohup "$HOME/sing/sing-box" run -c "$HOME/sing/sb.json" >/dev/null 2>&1 &
    fi
}

argorestart(){
    if [ -f "/etc/systemd/system/argo.service" ]; then
        kill -15 $(pgrep -x cloudflared 2>/dev/null) >/dev/null 2>&1
        systemctl restart argo
    elif [ -f "/etc/init.d/argo" ]; then
        kill -15 $(pgrep -x cloudflared 2>/dev/null) >/dev/null 2>&1
        rc-service argo restart
    elif [ -f "$HOME/sing/cloudflared" ]; then
        kill -15 $(pgrep -x cloudflared 2>/dev/null) >/dev/null 2>&1
        if [ -e "$HOME/sing/sbargotoken.log" ]; then
            nohup "$HOME/sing/cloudflared" tunnel --no-autoupdate --edge-ip-version auto run --token $(cat $HOME/sing/sbargotoken.log) >/dev/null 2>&1 &
        elif [ -e "$HOME/sing/argoport.log" ]; then
            nohup "$HOME/sing/cloudflared" tunnel --url http://localhost:$(cat $HOME/sing/argoport.log) --edge-ip-version auto --no-autoupdate > $HOME/sing/argo.log 2>&1 &
        fi
    fi
}

# ==================== 命令处理 ====================
if [ "$1" = "del" ]; then cleandel; remove_bbr; rm -rf "$HOME/sing"; echo "卸载完成"; showmode; exit; fi
if [ "$1" = "rep" ]; then cleandel; rm -rf "$HOME/sing"/{sb.json,sbargoym.log,sbargotoken.log,argo.log,argoport.log,cdnym,name,port_tr,port_vrp,port_snell,port_ss,port_tuic,reality.key,short_id,uuid,vlvm,server_ip.log,snell_psk,st_password,ss_password}; echo "重置完成..."; sleep 2; fi
if [ "$1" = "list" ]; then cip; exit; fi
if [ "$1" = "ups" ]; then kill -15 $(pgrep -x sing-box 2>/dev/null); upsingbox && sbrestart && echo "Sing-box内核更新完成" && sleep 2 && cip; exit; fi
if [ "$1" = "res" ]; then sbrestart; argorestart; sleep 5 && echo "重启完成" && sleep 3 && cip; exit; fi

# BBR 手动命令
if [ "$1" = "bbr" ]; then
    if [ "$EUID" -ne 0 ]; then echo "错误：请使用 root 权限运行 sing bbr"; exit 1; fi
    echo "正在应用 BBR 优化（接口: $(detect_iface)）..."
    apply_bbr
    echo "BBR 优化已完成"
    exit
fi

if ! sb_running && [ "$1" != "rep" ]; then cleandel; fi
if ! sb_running || [ "$1" = "rep" ]; then
    if [ -z "$( (curl -s4m5 -k "$v46url") || (wget -4 -qO- --tries=2 "$v46url") )" ]; then [ -f /etc/resolv.conf ] && cp -n /etc/resolv.conf /etc/resolv.conf.sing.bak 2>/dev/null; echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf; fi
    echo "VPS系统:$op"; echo "CPU架构:$cpu"; echo "sing脚本开始安装/更新…………" && sleep 1
    if [ -n "$oap" ]; then echo "⚠️ 警告: 检测到 oap 变量, 即将清空 iptables 规则并将 INPUT 策略设为 ACCEPT, 这会放通所有端口、关闭主机防火墙!"; setenforce 0 >/dev/null 2>&1; iptables -F; iptables -P INPUT ACCEPT; netfilter-persistent save >/dev/null 2>&1; echo "iptables执行开放所有端口"; fi
    ins; cip
else
    echo "sing脚本已安装"; echo; singstatus; echo; echo "相关快捷方式如下:"; showmode; exit
fi
