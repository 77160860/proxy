#!/bin/bash

VERSION="v5.0.1"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

get_system_type() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

wait_for_package_manager() {
    local system_type
    system_type=$(get_system_type)
    if [ "$system_type" = "debian" ]; then
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
            echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
            sleep 1
        done
    fi
}

install_required_packages() {
    local system_type
    system_type=$(get_system_type)
    echo -e "${GREEN}安装必要软件包${RESET}"

    if [ "$system_type" = "debian" ]; then
        apt update
        apt install -y wget unzip curl
    elif [ "$system_type" = "centos" ]; then
        yum -y update
        yum -y install wget unzip curl
    else
        echo -e "${RED}不支持的系统类型${RESET}"
        exit 1
    fi
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
        exit 1
    fi
}

trim_ws() {
    printf '%s' "\$1" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

digits_only() {
    printf '%s' "\$1" | tr -cd '0-9'
}

is_valid_port() {
    local p="\$1"

    [ -n "$p" ] || return 1

    case "$p" in
        *[!0-9]*)
            return 1
            ;;
    esac

    [ "$p" -ge 1 ] 2>/dev/null && [ "$p" -le 65535 ] 2>/dev/null
}

is_valid_psk() {
    local psk_value="\$1"
    [ -n "$psk_value" ]
}

is_port_in_use() {
    local p="\$1"
    if command -v ss >/dev/null 2>&1; then
        ss -lntu | awk '{print \$5}' | grep -qE "(:|\\])${p}$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lntu 2>/dev/null | awk '{print \$4}' | grep -qE "(:|\\])${p}$"
    else
        return 1
    fi
}

check_snell_installed() {
    if command -v snell-server &> /dev/null; then
        return 0
    else
        return 1
    fi
}

check_snell_running() {
    systemctl is-active --quiet "snell.service"
    return $?
}

start_snell() {
    systemctl start "snell.service"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 启动成功${RESET}"
    else
        echo -e "${RED}Snell 启动失败${RESET}"
    fi
}

stop_snell() {
    systemctl stop "snell.service"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 停止成功${RESET}"
    else
        echo -e "${RED}Snell 停止失败${RESET}"
    fi
}

prompt_update_config() {
    local current_listen current_psk current_port input_port input_psk yn

    if [ ! -f /etc/snell/snell-server.conf ]; then
        UPDATE_PORT=""
        UPDATE_PSK=""
        return 0
    fi

    current_listen="$(sed -n -E 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*//p' /etc/snell/snell-server.conf | head -n 1)"
    current_psk="$(sed -n -E 's/^[[:space:]]*psk[[:space:]]*=[[:space:]]*//p' /etc/snell/snell-server.conf | head -n 1)"
    current_port="$(printf '%s' "$current_listen" | awk -F: '{print $NF}')"

    echo -e "${CYAN}当前 listen: ${current_listen}${RESET}"
    echo -e "${CYAN}当前 psk: ${current_psk}${RESET}"
    echo ""

    read -r -p "是否修改端口/psk？(y/N): " yn
    yn="$(trim_ws "$yn")"
    case "$yn" in
        y|Y|yes|YES)
            ;;
        *)
            UPDATE_PORT=""
            UPDATE_PSK=""
            return 0
            ;;
    esac

    read -r -p "输入新端口(1-65535)，回车跳过 [当前: ${current_port}]: " input_port
    input_port="$(trim_ws "$input_port")"

    if [ -n "$input_port" ]; then
        if [ "$(digits_only "$input_port")" != "$input_port" ]; then
            echo -e "${RED}端口只能是纯数字: ${input_port}${RESET}"
            return 1
        fi
        if ! is_valid_port "$input_port"; then
            echo -e "${RED}端口无效: ${input_port}（应为 1-65535）${RESET}"
            return 1
        fi
        if is_port_in_use "$input_port"; then
            echo -e "${RED}端口已被占用: ${input_port}${RESET}"
            return 1
        fi
        UPDATE_PORT="$input_port"
    else
        UPDATE_PORT=""
    fi

    read -r -p "输入新 psk，回车跳过: " input_psk
    input_psk="$(trim_ws "$input_psk")"
    if [ -n "$input_psk" ]; then
        if ! is_valid_psk "$input_psk"; then
            echo -e "${RED}psk 无效（不能为空）${RESET}"
            return 1
        fi
        UPDATE_PSK="$input_psk"
    else
        UPDATE_PSK=""
    fi

    return 0
}

sync_snell_client_config() {
    local new_port="\$1"
    local new_psk="\$2"

    [ -f /etc/snell/config.txt ] || return 0

    if [ -n "$new_port" ]; then
        sed -i -E "s#,([[:space:]]*)[0-9]{1,5}([[:space:]]*),#,\1${new_port}\2,#g" /etc/snell/config.txt
    fi

    if [ -n "$new_psk" ]; then
        sed -i -E "s#(psk[[:space:]]*=[[:space:]]*).*(,|$)#\1${new_psk}\2#g" /etc/snell/config.txt
    fi

    return 0
}

install_snell() {
    echo -e "${GREEN}正在安装 Snell${RESET}"

    wait_for_package_manager
    install_required_packages || {
        echo -e "${RED}安装必要软件包失败${RESET}"
        exit 1
    }

    ARCH=$(arch)
    if [ "${ARCH}" = "aarch64" ]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi

    wget "${SNELL_URL}" -O snell-server.zip || {
        echo -e "${RED}下载 Snell 失败。${RESET}"
        exit 1
    }

    unzip -o snell-server.zip -d /usr/local/bin || {
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        exit 1
    }

    rm snell-server.zip
    chmod +x /usr/local/bin/snell-server

    RAW_PORT="$(trim_ws "${port}")"
    RAW_PSK="$(trim_ws "${psk}")"

    SELECTED_PORT="$(digits_only "${RAW_PORT}")"
    SELECTED_PSK="${RAW_PSK}"

    if [ -n "${RAW_PORT}" ] && [ "${SELECTED_PORT}" != "${RAW_PORT}" ]; then
        echo -e "${RED}端口只能是纯数字: ${RAW_PORT}${RESET}"
        exit 1
    fi

    if [ -n "$SELECTED_PORT" ]; then
        if ! is_valid_port "$SELECTED_PORT"; then
            echo -e "${RED}端口无效: ${SELECTED_PORT}（应为 1-65535）${RESET}"
            exit 1
        fi
        if is_port_in_use "$SELECTED_PORT"; then
            echo -e "${RED}端口已被占用: ${SELECTED_PORT}${RESET}"
            exit 1
        fi
        RANDOM_PORT="$SELECTED_PORT"
    else
        RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    fi

    if [ -n "$SELECTED_PSK" ]; then
        if ! is_valid_psk "$SELECTED_PSK"; then
            echo -e "${RED}psk 无效（不能为空）${RESET}"
            exit 1
        fi
        RANDOM_PSK="$SELECTED_PSK"
    else
        RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
    fi

    if ! id "snell" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin snell
    fi

    mkdir -p /etc/snell
    cat > /etc/snell/snell-server.conf << EOF
[snell-server]
listen = ::0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
ipv6 = true
EOF

    cat > /etc/systemd/system/snell.service << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
LimitNOFILE=32768
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}Snell 安装成功${RESET}"
    systemctl daemon-reload && systemctl enable snell && systemctl start snell
    sleep 3 && journalctl -u snell.service -n 8 --no-pager

    HOST_IP=$(curl -s http://checkip.amazonaws.com)
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)

    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/77160860/Snell${RESET}"
    cat << EOF > /etc/snell/config.txt
${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 5, reuse = true
EOF

    cat /etc/snell/config.txt
}

update_snell() {
    if [ ! -f "/usr/local/bin/snell-server" ]; then
        echo -e "${YELLOW}Snell 未安装，跳过更新${RESET}"
        return
    fi

    echo -e "${GREEN}Snell 正在更新${RESET}"
    systemctl stop snell

    wait_for_package_manager
    install_required_packages || {
        echo -e "${RED}安装必要软件包失败${RESET}"
        exit 1
    }

    ARCH=$(arch)
    if [ "${ARCH}" = "aarch64" ]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi

    wget "${SNELL_URL}" -O snell-server.zip || {
        echo -e "${RED}下载 Snell 失败。${RESET}"
        exit 1
    }
    unzip -o snell-server.zip -d /usr/local/bin || {
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        rm -f snell-server.zip
        exit 1
    }
    rm -f snell-server.zip
    chmod +x /usr/local/bin/snell-server

    RAW_PORT="$(trim_ws "${port}")"
    RAW_PSK="$(trim_ws "${psk}")"
    SELECTED_PORT="$(digits_only "${RAW_PORT}")"
    SELECTED_PSK="${RAW_PSK}"

    if [ -n "${RAW_PORT}" ] && [ "${SELECTED_PORT}" != "${RAW_PORT}" ]; then
        echo -e "${RED}端口只能是纯数字: ${RAW_PORT}${RESET}"
        exit 1
    fi

    if [ -z "$RAW_PORT" ] && [ -z "$SELECTED_PSK" ]; then
        if ! prompt_update_config; then
            echo -e "${RED}交互配置失败，已取消更新配置${RESET}"
            exit 1
        fi
        if [ -n "$UPDATE_PORT" ]; then
            SELECTED_PORT="$UPDATE_PORT"
        else
            SELECTED_PORT=""
        fi
        if [ -n "$UPDATE_PSK" ]; then
            SELECTED_PSK="$UPDATE_PSK"
        else
            SELECTED_PSK=""
        fi
    fi

    if [ -n "$SELECTED_PORT" ] || [ -n "$SELECTED_PSK" ]; then
        if [ ! -f /etc/snell/snell-server.conf ]; then
            echo -e "${RED}/etc/snell/snell-server.conf 不存在，无法更新配置${RESET}"
            exit 1
        fi

        if [ -n "$SELECTED_PORT" ]; then
            if ! is_valid_port "$SELECTED_PORT"; then
                echo -e "${RED}端口无效: ${SELECTED_PORT}（应为 1-65535）${RESET}"
                exit 1
            fi
            if is_port_in_use "$SELECTED_PORT"; then
                echo -e "${RED}端口已被占用: ${SELECTED_PORT}${RESET}"
                exit 1
            fi
            sed -i -E "s#^(listen[[:space:]]*=[[:space:]]*[^:]+:)[0-9]+#\\1${SELECTED_PORT}#g" /etc/snell/snell-server.conf
        fi

        if [ -n "$SELECTED_PSK" ]; then
            if ! is_valid_psk "$SELECTED_PSK"; then
                echo -e "${RED}psk 无效（不能为空）${RESET}"
                exit 1
            fi
            sed -i -E "s#^(psk[[:space:]]*=[[:space:]]*).*\$#\\1${SELECTED_PSK}#g" /etc/snell/snell-server.conf
        fi

        echo -e "${GREEN}已更新 /etc/snell/snell-server.conf${RESET}"
        grep -E '^(listen|psk)[[:space:]]*=' /etc/snell/snell-server.conf || true

        sync_snell_client_config "$SELECTED_PORT" "$SELECTED_PSK"

        if [ -f /etc/snell/config.txt ]; then
            echo -e "${GREEN}已同步 /etc/snell/config.txt${RESET}"
            cat /etc/snell/config.txt
        fi
    fi

    systemctl restart snell || {
        echo -e "${RED}Snell 重启失败，请查看日志${RESET}"
        journalctl -u snell.service -n 30 --no-pager
        exit 1
    }

    echo -e "${GREEN}Snell 更新成功${RESET}"
    sleep 2
    journalctl -u snell.service -n 8 --no-pager
}

uninstall_snell() {
    echo -e "${GREEN}正在卸载 Snell${RESET}"
    systemctl stop snell
    systemctl disable snell
    rm /etc/systemd/system/snell.service
    systemctl daemon-reload
    rm /usr/local/bin/snell-server
    rm -rf /etc/snell
    echo -e "${GREEN}Snell 卸载成功${RESET}"
}

show_menu() {
    clear
    check_snell_installed
    snell_installed=$?
    check_snell_running
    snell_running=$?

    if [ $snell_installed -eq 0 ]; then
        installation_status="${GREEN}已安装${RESET}"
        if version_output=$(/usr/local/bin/snell-server -version 2>&1); then
            snell_version=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
            if [ -n "$snell_version" ]; then
                version_status="${GREEN}${snell_version}${RESET}"
            else
                version_status="${RED}未知版本${RESET}"
            fi
        else
            version_status="${RED}未知版本${RESET}"
        fi

        if [ $snell_running -eq 0 ]; then
            running_status="${GREEN}已启动${RESET}"
        else
            running_status="${RED}未启动${RESET}"
        fi
    else
        installation_status="${RED}未安装${RESET}"
        running_status="${RED}未启动${RESET}"
        version_status="—"
    fi

    echo -e "${GREEN}=== Snell 管理工具 ===${RESET}"
    echo -e "安装状态: ${installation_status}"
    echo -e "运行状态: ${running_status}"
    echo -e "运行版本: ${version_status}"
    echo ""
    echo "1. 安装 Snell 服务"
    echo "2. 卸载 Snell 服务"
    if [ $snell_installed -eq 0 ]; then
        if [ $snell_running -eq 0 ]; then
            echo "3. 停止 Snell 服务"
        else
            echo "3. 启动 Snell 服务"
        fi
    fi
    echo "4. 更新 Snell 服务"
    echo "5. 查看 Snell 配置"
    echo "0. 退出"
    echo -e "${GREEN}======================${RESET}"
    read -p "请输入选项编号: " choice
    export choice
    echo ""
}

trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

main() {
    check_root

    while true; do
        show_menu
        case "${choice}" in
            1)
                install_snell
                ;;
            2)
                if [ $snell_installed -eq 0 ]; then
                    uninstall_snell
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                fi
                ;;
            3)
                if [ $snell_installed -eq 0 ]; then
                    if [ $snell_running -eq 0 ]; then
                        stop_snell
                    else
                        start_snell
                    fi
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                fi
                ;;
            4)
                update_snell
                ;;
            5)
                if [ -f /etc/snell/config.txt ]; then
                    cat /etc/snell/config.txt
                else
                    echo -e "${RED}配置文件不存在${RESET}"
                fi
                ;;
            0)
                echo -e "${GREEN}已退出 Snell 管理工具${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项${RESET}"
                ;;
        esac
        read -p "按 enter 键继续..."
    done
}

main
