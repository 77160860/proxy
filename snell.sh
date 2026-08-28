#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS/Debian/Ubuntu/Alpine
#	Description: Snell Server 管理脚本
#=================================================

sh_ver="2.0.3"
snell_v2_version="2.0.6"
snell_v3_version="3.0.1"
snell_v4_version="4.1.1"
snell_v5_version="5.0.1"
snell_v6_version="6.0.0rc2"
script_dir=$(cd "$(dirname "$0")"; pwd)
snell_dir="/etc/snell/"
snell_bin="/usr/local/bin/snell-server"
snell_conf="/etc/snell/config.conf"
snell_version_file="/etc/snell/ver.txt"
sysctl_conf="/etc/sysctl.d/99-snell.conf"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[警告]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[提示]${Font_color_suffix}"

# ==================== 服务管理器兼容层 ====================
SERVICE_TYPE=""

checkServiceManager(){
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_TYPE="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        SERVICE_TYPE="openrc"
    else
        echo -e "${Error} 未检测到支持的服务管理器 (systemd/openrc)，无法继续。"
        exit 1
    fi
}

service_start(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl start snell-server
    else
        rc-service snell-server start
    fi
}

service_stop(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl stop snell-server
    else
        rc-service snell-server stop
    fi
}

service_restart(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl restart snell-server
    else
        rc-service snell-server restart
    fi
}

service_enable(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl enable snell-server >/dev/null 2>&1
    else
        rc-update add snell-server default >/dev/null 2>&1
    fi
}

service_daemon_reload(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl daemon-reload
    fi
}

service_is_active(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl is-active --quiet snell-server
    else
        # OpenRC 更可靠的检测方式
        rc-service snell-server status 2>/dev/null | grep -q "started"
    fi
}
# ========================================================

checkRoot(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限。" && exit 1
}

checkSys(){
	if [[ -f /etc/alpine-release ]]; then
		release="alpine"
	elif [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	fi
}

checkDependencies(){
    local deps=("wget" "unzip" "ss")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${Error} 缺少依赖: $cmd，正在尝试安装..."
            if [[ ${release} == "alpine" ]]; then
                apk add --no-cache "$cmd"
            elif [[ -f /etc/debian_version ]]; then
                apt-get update && apt-get install -y "$cmd"
            elif [[ -f /etc/redhat-release ]]; then
                yum install -y "$cmd"
            else
                echo -e "${Error} 不支持的系统，无法自动安装 $cmd"
                exit 1
            fi
        fi
    done
}

installDependencies(){
	if [[ ${release} == "alpine" ]]; then
		apk add --no-cache gzip wget curl unzip
	elif [[ ${release} == "centos" ]]; then
		yum update -y
		yum install -y gzip wget curl unzip
	else
		apt-get update
		apt-get install -y gzip wget curl unzip
	fi
	sysctl -w net.core.rmem_max=26214400 2>/dev/null || true
	sysctl -w net.core.rmem_default=26214400 2>/dev/null || true
	\cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
	echo -e "${Info} 依赖安装完成"
}

sysArch() {
    uname=$(uname -m)
    if [[ "$uname" == "i686" ]] || [[ "$uname" == "i386" ]]; then
        arch="i386"
    elif [[ "$uname" == *"armv7"* ]] || [[ "$uname" == "armv6l" ]]; then
        arch="armv7l"
    elif [[ "$uname" == *"armv8"* ]] || [[ "$uname" == "aarch64" ]]; then
        arch="aarch64"
    else
        arch="amd64"
    fi
}

enableTCPFastOpen() {
	kernel=$(uname -r | awk -F . '{print $1}')
	if [ "$kernel" -ge 3 ]; then
		echo 3 >/proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || true
		cat > "$sysctl_conf" << EOF
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
		sysctl --system >/dev/null 2>&1 || true
		echo -e "${Info} TCP Fast Open 和网络优化配置已启用！"
	else
		echo -e "${Error} 系统内核版本过低，无法支持 TCP Fast Open！"
	fi
}

checkInstalledStatus(){
	[[ ! -e ${snell_bin} ]] && echo -e "${Error} Snell Server 没有安装，请检查！" && exit 1
}

checkStatus(){
    if service_is_active; then
        status="running"
    else
        status="stopped"
    fi
}

# ==================== 以下为原脚本所有函数（完整保留） ====================

compareVersions(){
    local version1="$1"
    local version2="$2"
    version1=$(echo "$version1" | sed 's/^v//')
    version2=$(echo "$version2" | sed 's/^v//')
    if [[ "$version1" == "$version2" ]]; then
        return 1
    fi
    local base_version1=$(echo "$version1" | sed 's/[a-z].*//')
    local base_version2=$(echo "$version2" | sed 's/[a-z].*//')
    local is_beta1=false
    local is_beta2=false
    [[ "$version1" =~ [a-z] ]] && is_beta1=true
    [[ "$version2" =~ [a-z] ]] && is_beta2=true
    if [[ "$base_version1" == "$base_version2" ]]; then
        if [[ "$is_beta1" == true && "$is_beta2" == false ]]; then
            return 2
        elif [[ "$is_beta1" == false && "$is_beta2" == true ]]; then
            return 0
        fi
        if printf '%s\n' "$version1" "$version2" | sort -V | head -1 | grep -q "^$version1$"; then
            return 2
        else
            return 0
        fi
    fi
    if printf '%s\n' "$base_version1" "$base_version2" | sort -V | head -1 | grep -q "^$base_version1$"; then
        return 2
    else
        return 0
    fi
}

validateVersionUrl(){
    local version="$1"
    getSnellDownloadUrl "$version"
    if curl -I -s --max-time 10 "$snell_url" | head -1 | grep -qE "200 OK|HTTP/2 200|HTTP/[0-9.]+ 200"; then
        return 0
    else
        return 1
    fi
}

checkVersionUpdate(){
    local show_info=${1:-false}
    update_available=false
    current_installed_version=""
    latest_available_version=""
    best_version=""

    if [[ -n "$TARGET_UPDATE_VERSION" ]]; then
        update_available=true
        best_version="$TARGET_UPDATE_VERSION"
        latest_available_version="$TARGET_UPDATE_VERSION"
        version_source="命令行指定"
        if [[ -e ${snell_version_file} ]]; then
            current_installed_version=$(cat ${snell_version_file} | sed 's/^v//')
        fi
        return 0
    fi

    if [[ -e ${snell_bin} && -e ${snell_conf} ]]; then
        current_ver=$(cat ${snell_conf}|grep 'version = '|awk -F 'version = ' '{print $NF}')

        if [[ "$current_ver" != "6" && -z "$TARGET_UPDATE_VERSION" ]]; then
            update_available=false
            return 0
        fi

        if [[ -e ${snell_version_file} ]]; then
            installed_version=$(cat ${snell_version_file} | sed 's/^v//')

            if command -v timeout >/dev/null 2>&1 && [[ -x ${snell_bin} ]]; then
                bin_version=$(timeout 1 ${snell_bin} --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-_ ]?[a-zA-Z0-9]*' | sed 's/[-_ ]//g' | head -1)
                [[ -z "$bin_version" ]] && bin_version=$(timeout 1 ${snell_bin} -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-_ ]?[a-zA-Z0-9]*' | sed 's/[-_ ]//g' | head -1)
                [[ -z "$bin_version" ]] && bin_version=$(timeout 1 ${snell_bin} --help 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-_ ]?[a-zA-Z0-9]*' | sed 's/[-_ ]//g' | head -1)

                if [[ -n "$bin_version" && "$bin_version" != "$installed_version" ]]; then
                    if [[ "$installed_version" != "$bin_version"* ]]; then
                        installed_version="$bin_version"
                        echo "v${installed_version}" > "${snell_version_file}"
                    fi
                fi
            fi

            current_installed_version="$installed_version"

            case "$current_ver" in
                "4")
                    script_version=${snell_v4_version}
                    web_version=$(getLatestVersionFromWeb "v4")
                    ;;
                "5")
                    script_version=${snell_v5_version}
                    web_version=$(getLatestVersionFromWeb "v5")
                    ;;
                "6")
                    script_version=${snell_v6_version}
                    web_version=$(getLatestVersionFromWeb "v6")
                    ;;
                *)
                    script_version=""
                    web_version=""
                    ;;
            esac

            best_version="$installed_version"
            version_source="已安装"

            if [[ -n "$script_version" ]]; then
                compareVersions "$best_version" "$script_version"
                case $? in
                    2)
                        if validateVersionUrl "$script_version"; then
                            best_version="$script_version"
                            version_source="脚本内置"
                        else
                            [[ "$show_info" == true ]] && echo -e "${Tip} 脚本内置版本 v${script_version} 的下载链接无效，跳过"
                        fi
                        ;;
                esac
            fi

            if [[ -n "$web_version" ]]; then
                compareVersions "$best_version" "$web_version"
                case $? in
                    2)
                        if validateVersionUrl "$web_version"; then
                            best_version="$web_version"
                            version_source="官方网页"
                        else
                            [[ "$show_info" == true ]] && echo -e "${Tip} 网页版本 Snell v${web_version} 的下载链接无效，使用脚本内置版本"
                        fi
                        ;;
                esac
            fi

            latest_available_version="$best_version"

            compareVersions "$installed_version" "$best_version"
            if [[ $? -eq 2 ]]; then
                update_available=true
                if [[ "$show_info" == true ]]; then
                    echo -e "${Info} 发现更新：当前版本 Snell v${installed_version} -> 最新版本 Snell v${best_version}"
                    echo -e "${Info} 更新版本来源：${version_source}"
                fi
            fi
        fi
    fi
}

getSnellDownloadUrl(){
	sysArch
	local version=$1
	snell_url="https://dl.nssurge.com/snell/snell-server-v${version}-linux-${arch}.zip"
}

downloadSnellV2() {
    downloadSnellFromGitHub "${snell_v2_version}" "Snell v2 GitHub 备份源版" || downloadSnellFromGitee "${snell_v2_version}" "Snell v2 Gitee 备份源版"
}

downloadSnellV3() {
    downloadSnellFromGitHub "${snell_v3_version}" "Snell v3 GitHub 备份源版" || downloadSnellFromGitee "${snell_v3_version}" "Snell v3 Gitee 备份源版"
}

downloadSnellFromBackup(){
    local version=$1
    local version_type=$2
    local backup_url=$3
    echo -e "${Info} 试图请求 ${Yellow_font_prefix}${version_type}${Font_color_suffix} Snell Server ……"
    wget --no-check-certificate -N "${backup_url}"
    if [[ ! -e "snell-server-v${version}-linux-${arch}.zip" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 下载失败！"
        return 1
    fi
    unzip -o "snell-server-v${version}-linux-${arch}.zip"
    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 解压失败！"
        return 1
    fi
    rm -rf "snell-server-v${version}-linux-${arch}.zip"
    chmod +x snell-server
    mv -f snell-server "${snell_bin}"
    echo "v${version}" > "${snell_version_file}"
    echo -e "${Info} Snell Server 主程序下载安装完毕！"
    return 0
}

downloadSnellFromGitHub(){
    local version=$1
    local version_type=$2
    local backup_url="https://raw.githubusercontent.com/xOS/Others/master/snell/v${version}/snell-server-v${version}-linux-${arch}.zip"
    downloadSnellFromBackup "$version" "$version_type" "$backup_url"
}

downloadSnellFromGitee(){
    local version=$1
    local version_type=$2
    local backup_url="https://gitee.com/ten/Others/raw/master/snell/v${version}/snell-server-v${version}-linux-${arch}.zip"
    downloadSnellFromBackup "$version" "$version_type" "$backup_url"
}

downloadSnellV4(){
	downloadSnell "${snell_v4_version}" "Snell v4 官网源版" || downloadSnellFromGitHub "${snell_v4_version}" "Snell v4 GitHub 备份源版" || downloadSnellFromGitee "${snell_v4_version}" "Snell v4 Gitee 备份源版"
}

downloadSnellV5(){
	downloadSnell "${snell_v5_version}" "Snell v5 官网源版" || downloadSnellFromGitHub "${snell_v5_version}" "Snell v5 GitHub 备份源版" || downloadSnellFromGitee "${snell_v5_version}" "Snell v5 Gitee 备份源版"
}

downloadSnell(){
	local version=$1
	local version_type=$2
	local allow_fallback=${3:-false}
	local fallback_version=$4
	echo -e "${Info} 试图请求 ${Yellow_font_prefix}${version_type}${Font_color_suffix} Snell Server ……"
	getSnellDownloadUrl "${version}"
	if ! curl -I -s --max-time 10 "$snell_url" | head -1 | grep -qE "200 OK|HTTP/2 200|HTTP/[0-9.]+ 200"; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 下载链接无效 (404)！"
		if [[ "$allow_fallback" == true && -n "$fallback_version" ]]; then
			echo -e "${Info} 尝试回退到已安装版本 v${fallback_version}..."
			getSnellDownloadUrl "${fallback_version}"
			if curl -I -s --max-time 10 "$snell_url" | head -1 | grep -qE "200 OK|HTTP/2 200|HTTP/[0-9.]+ 200"; then
				version="$fallback_version"
				echo -e "${Info} 回退成功，使用版本 v${version}"
			else
				echo -e "${Error} 回退版本也无法下载！"
				return 1
			fi
		else
			return 1
		fi
	fi
	wget --no-check-certificate -N "${snell_url}"
	if [[ ! -e "snell-server-v${version}-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 下载失败！"
		return 1 && exit 1
	else
		unzip -o "snell-server-v${version}-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 解压失败！"
		return 1 && exit 1
	else
		rm -rf "snell-server-v${version}-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${snell_bin}"
		echo "v${version}" > ${snell_version_file}
		echo -e "${Info} Snell Server 主程序下载安装完毕！"
		return 0
	fi
}

installSnell() {
	if [[ ! -e "${snell_dir}" ]]; then
		mkdir "${snell_dir}"
	else
		[[ -e "${snell_bin}" ]] && rm -rf "${snell_bin}"
	fi
	echo -e "选择安装版本${Yellow_font_prefix}[2-6]${Font_color_suffix}
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2  ${Green_font_prefix} 3.${Font_color_suffix} v3  ${Green_font_prefix} 4.${Font_color_suffix} v4  ${Green_font_prefix} 5.${Font_color_suffix} v5  ${Green_font_prefix} 6.${Font_color_suffix} v6
=================================="
	read -e -p "(默认：4.v4)：" ver
	[[ -z "${ver}" ]] && ver="4"
	if [[ ${ver} == "2" ]]; then
		installSnellV2
	elif [[ ${ver} == "3" ]]; then
		installSnellV3
	elif [[ ${ver} == "4" ]]; then
		installSnellV4
	elif [[ ${ver} == "5" ]]; then
		installSnellV5
	elif [[ ${ver} == "6" ]]; then
		installSnellV6
	else
		installSnellV4
	fi
}

setupService(){
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        cat > /etc/systemd/system/snell-server.service << EOF
[Unit]
Description=Snell Service
After=network.target
[Service]
LimitNOFILE=32767
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/snell-server -c /etc/snell/config.conf
[Install]
WantedBy=multi-user.target
EOF
        service_daemon_reload
        service_enable
    else
        cat > /etc/init.d/snell-server << EOF
#!/sbin/openrc-run
command="/usr/local/bin/snell-server"
command_args="-c /etc/snell/config.conf"
pidfile="/run/snell-server.pid"
command_background="yes"
depend() { need net; }
EOF
        chmod +x /etc/init.d/snell-server
        service_enable
    fi
    echo -e "${Info} Snell Server 服务配置完成！"
}

checkPskForV6(){
    if [[ ${#psk} -lt 16 ]] || [[ ${#psk} -gt 255 ]]; then
        echo -e "${Error} 检测到当前密钥 (${psk}) 长度不符合 16-255 位要求，Snell v6 要求升级密钥！"
        echo -e "请选择处理方式："
        echo -e " 1. 自动生成安全的随机长密钥（推荐）"
        echo -e " 2. 手动输入新的长密钥"
        read -e -p "(默认: 1):" psk_choice
        [[ -z "${psk_choice}" ]] && psk_choice="1"
        if [[ "${psk_choice}" == "2" ]]; then
            while true; do
                read -e -p "请输入新的密钥(16-255位): " new_psk
                if [[ ${#new_psk} -ge 16 ]] && [[ ${#new_psk} -le 255 ]]; then
                    psk=$new_psk
                    break
                else
                    echo -e "${Error} 密钥长度必须在 16 到 255 位之间！"
                fi
            done
        else
            psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
            echo -e "${Info} 已自动生成新密钥: ${Green_font_prefix}${psk}${Font_color_suffix}"
        fi
    fi
}

writeConfig(){
    local config_content="[snell-server]
listen = ${listen_val}
$(if [[ ${ver} != "6" ]]; then echo "ipv6 = ${ipv6}"; else echo "# ipv6 = ${ipv6}"; fi)
psk = ${psk}
$(if [[ ${ver} != "6" ]]; then echo "obfs = ${obfs}"; else echo "# obfs = ${obfs}"; fi)"

    if [[ ${ver} != "6" && ${obfs} != "off" ]]; then
        config_content+=$'\n'"obfs-host = ${host}"
    elif [[ ${ver} == "6" && ${obfs} != "off" ]]; then
        config_content+=$'\n'"# obfs-host = ${host}"
    fi

    config_content+=$'\n'"tfo = ${tfo}
dns = ${dns}"

    if [[ ${ver} == "6" ]]; then
        if [[ -n "${dns_ip_pref}" ]]; then
            config_content+=$'\n'"dns-ip-preference = ${dns_ip_pref}"
        else
            config_content+=$'\n'"dns-ip-preference = default"
        fi
        if [[ -n "${mode}" ]]; then
            config_content+=$'\n'"mode = ${mode}"
        else
            config_content+=$'\n'"mode = default"
        fi
    else
        if [[ -n "${dns_ip_pref}" ]]; then
            config_content+=$'\n'"# dns-ip-preference = ${dns_ip_pref}"
        fi
        if [[ -n "${mode}" ]]; then
            config_content+=$'\n'"# mode = ${mode}"
        fi
    fi

    if [[ -n "${egress_interface}" ]]; then
        config_content+=$'\n'"egress-interface = ${egress_interface}"
    fi

    config_content+=$'\n'"version = ${ver}"

    if [[ -f "${snell_conf}" ]]; then
        local custom_configs=$(awk -F '=' '{
            key = $1
            sub(/^[[:space:]]+/, "", key)
            sub(/[[:space:]]+$/, "", key)
            if (key != "listen" && key != "ipv6" && key != "psk" && key != "obfs" && key != "obfs-host" && key != "tfo" && key != "dns" && key != "dns-ip-preference" && key != "mode" && key != "version" && key != "egress-interface" && key != "[snell-server]" && $0 !~ /^[[:space:]]*#/) {
                if (NF > 0 && $0 !~ /^[[:space:]]*$/) {
                    print $0
                }
            }
        }' "${snell_conf}")

        if [[ -n "${custom_configs}" ]]; then
            config_content+=$'\n\n# Custom Configs\n'"${custom_configs}"
        fi
    fi

    echo "${config_content}" > "${snell_conf}"
}

readConfig(){
	[[ ! -e ${snell_conf} ]] && echo -e "${Error} Snell Server 配置文件不存在！" && exit 1
	listen_val=$(grep -m 1 -E '^listen\s*=' ${snell_conf} | sed -E 's/^listen\s*=\s*//' | xargs)
	port=$(echo "$listen_val" | awk -F',' '{print $1}' | awk -F':' '{print $NF}' | xargs)
	ipv6=$(cat ${snell_conf}|grep -m 1 'ipv6 = '|awk -F 'ipv6 = ' '{print $NF}')
	psk=$(cat ${snell_conf}|grep -m 1 'psk = '|awk -F 'psk = ' '{print $NF}')
	obfs=$(cat ${snell_conf}|grep -m 1 'obfs = '|awk -F 'obfs = ' '{print $NF}')
	host=$(cat ${snell_conf}|grep -m 1 'obfs-host = '|awk -F 'obfs-host = ' '{print $NF}')
	tfo=$(cat ${snell_conf}|grep -m 1 'tfo = '|awk -F 'tfo = ' '{print $NF}')
	dns=$(cat ${snell_conf}|grep -m 1 'dns = '|awk -F 'dns = ' '{print $NF}')
	ver=$(cat ${snell_conf}|grep -m 1 'version = '|awk -F 'version = ' '{print $NF}')
	dns_ip_pref=$(cat ${snell_conf}|grep -m 1 'dns-ip-preference = '|awk -F 'dns-ip-preference = ' '{print $NF}')
	[[ -z "$dns_ip_pref" && "$ver" == "6" ]] && dns_ip_pref="default"
	mode=$(cat ${snell_conf}|grep -m 1 'mode = '|awk -F 'mode = ' '{print $NF}')
	[[ -z "$mode" && "$ver" == "6" ]] && mode="default"
	egress_interface=$(cat ${snell_conf}|grep -m 1 'egress-interface = '|awk -F 'egress-interface = ' '{print $NF}')
}

setPort(){
    local orig_port="$port"
    while true; do
        echo -e "${Tip} 本步骤不涉及系统防火墙端口操作，请手动放行相应端口！"
        echo -e "请输入 Snell Server 端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
        local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}: 2345):"
        [[ -n "$port" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${port} | ${Green_font_prefix}默认${Font_color_suffix}: 2345):"
        echo -e -n "${p_prompt}"
        read -e input_port
        [[ -z "${input_port}" ]] && input_port="2345"
        port=$input_port
        if [[ "${ver}" == "6" || "$current_installed_ver" == "6" ]]; then
            listen_val="0.0.0.0:${port},[::]:${port}"
        else
            listen_val="::0:${port}"
        fi
        if [[ $port =~ ^[0-9]+$ ]] && [[ $port -ge 1 && $port -le 65535 ]]; then
            if [[ "$port" != "$orig_port" ]] && ss -tuln | grep -q ":$port "; then
                echo -e "${Error} 端口 $port 已被占用，请选择其他端口。"
            else
                echo && echo "=============================="
                echo -e "端口 : ${Red_background_prefix} ${port} ${Font_color_suffix}"
                echo "==============================" && echo
                break
            fi
        else
            echo "输入错误, 请输入正确的端口号。"
			sleep 2s
			setPort
        fi
    done
}

setIpv6(){
	echo -e "是否开启 IPv6 解析？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	local current_opt="2"
	[[ "$ipv6" == "true" ]] && current_opt="1"
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}：2.关闭)："
	[[ -n "$ipv6" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${current_opt}.${ipv6} | ${Green_font_prefix}默认${Font_color_suffix}：2.关闭)："
	echo -e -n "${p_prompt}"
	read -e input_ipv6
	[[ -z "${input_ipv6}" ]] && input_ipv6="2"
	if [[ ${input_ipv6} == "1" ]]; then
		ipv6=true
	else
		ipv6=false
	fi
	echo && echo "=================================="
	echo -e "IPv6 解析 开启状态：${Red_background_prefix} ${ipv6} ${Font_color_suffix}"
	echo "==================================" && echo
}

setPSK(){
	echo "请输入 Snell Server 密钥 [0-9][a-z][A-Z] "
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}: 随机生成):"
	[[ -n "$psk" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${psk} | ${Green_font_prefix}默认${Font_color_suffix}: 随机生成):"
	if [[ "$ver" == "6" || "$current_installed_ver" == "6" ]]; then
	    echo -e "${Tip} 当前目标协议为 Snell v6，密钥长度要求在 16-255 位之间"
	    while true; do
	        echo -e -n "${p_prompt}"
	        read -e input_psk
	        if [[ -z "${input_psk}" ]]; then
	            psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
	            break
	        else
	            if [[ ${#input_psk} -ge 16 ]] && [[ ${#input_psk} -le 255 ]]; then
	                psk=$input_psk
	                break
	            else
	                echo -e "${Error} Snell v6 密钥长度必须在 16 到 255 位之间，请重新输入！"
	            fi
	        fi
	    done
	else
	    echo -e -n "${p_prompt}"
	    read -e input_psk
	    if [[ -z "${input_psk}" ]]; then
	        psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
	    else
	        psk=$input_psk
	    fi
	fi
	echo && echo "=============================="
	echo -e "密钥 : ${Red_background_prefix} ${psk} ${Font_color_suffix}"
	echo "==============================" && echo
}

setObfs(){
    echo -e "配置 OBFS，${Tip} 无特殊作用不建议启用该项。
==================================
${Green_font_prefix} 1.${Font_color_suffix} TLS  ${Green_font_prefix} 2.${Font_color_suffix} HTTP ${Green_font_prefix} 3.${Font_color_suffix} 关闭
=================================="
    local current_opt="3"
    if [[ "$obfs" == "tls" ]]; then current_opt="1"; elif [[ "$obfs" == "http" ]]; then current_opt="2"; fi
    local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}：3.关闭)："
    [[ -n "$obfs" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${current_opt}.${obfs} | ${Green_font_prefix}默认${Font_color_suffix}：3.关闭)："
    echo -e -n "${p_prompt}"
    read -e input_obfs
    [[ -z "${input_obfs}" ]] && input_obfs="3"
    obfs=$input_obfs
    if [[ ${obfs} == "1" ]]; then
        obfs="tls"
        setHost
    elif [[ ${obfs} == "2" ]]; then
        obfs="http"
        setHost
    elif [[ ${obfs} == "3" ]]; then
        obfs="off"
        host=""
    else
        obfs="off"
        host=""
    fi
    echo && echo "=================================="
    echo -e "OBFS 状态：${Red_background_prefix} ${obfs} ${Font_color_suffix}"
    if [[ ${obfs} != "off" ]]; then
        echo -e "OBFS 域名：${Red_background_prefix} ${host} ${Font_color_suffix}"
    fi
    echo "==================================" && echo
}

setVer(){
	echo -e "配置 Snell Server 协议版本${Yellow_font_prefix}[2-6]${Font_color_suffix}
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2 ${Green_font_prefix} 3.${Font_color_suffix} v3 ${Green_font_prefix} 4.${Font_color_suffix} v4 ${Green_font_prefix} 5.${Font_color_suffix} v5 ${Green_font_prefix} 6.${Font_color_suffix} v6
=================================="
	local current_ver_display=""
	[[ -n "$ver" ]] && current_ver_display="${ver}.v${ver}"
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}：4.v4)："
	[[ -n "$ver" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${current_ver_display} | ${Green_font_prefix}默认${Font_color_suffix}：4.v4)："
	echo -e -n "${p_prompt}"
	read -e input_ver
	[[ -z "${input_ver}" ]] && input_ver="4"
	ver=$input_ver
	if [[ ${ver} == "2" ]]; then
		ver=2
	elif [[ ${ver} == "3" ]]; then
		ver=3
	elif [[ ${ver} == "4" ]]; then
		ver=4
	elif [[ ${ver} == "5" ]]; then
		ver=5
	elif [[ ${ver} == "6" ]]; then
		ver=6
	else
		ver=4
	fi
	echo && echo "=================================="
	echo -e "Snell Server 协议版本：${Red_background_prefix} ${ver} ${Font_color_suffix}"
	echo "==================================" && echo
}

setHost(){
	echo "请输入 Snell Server 域名，Snell v4 版本及以上如无特别需求可忽略。"
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}: www.wechat.com):"
	[[ -n "$host" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${host} | ${Green_font_prefix}默认${Font_color_suffix}: www.wechat.com):"
	echo -e -n "${p_prompt}"
	read -e input_host
	[[ -z "${input_host}" ]] && input_host="www.wechat.com"
	host=$input_host
	echo && echo "=============================="
	echo -e "域名 : ${Red_background_prefix} ${host} ${Font_color_suffix}"
	echo "==============================" && echo
}

setTFO(){
	echo -e "是否开启 TCP Fast Open？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	local current_opt="1"
	if [[ "$tfo" == "false" ]]; then current_opt="2"; fi
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}：1.开启)："
	[[ -n "$tfo" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${current_opt}.${tfo} | ${Green_font_prefix}默认${Font_color_suffix}：1.开启)："
	echo -e -n "${p_prompt}"
	read -e input_tfo
	[[ -z "${input_tfo}" ]] && input_tfo="1"
	tfo=$input_tfo
	if [[ ${tfo} == "1" ]]; then
		tfo=true
		enableTCPFastOpen
	else
		tfo=false
	fi
	echo && echo "=================================="
	echo -e "TCP Fast Open 开启状态：${Red_background_prefix} ${tfo} ${Font_color_suffix}"
	echo "==================================" && echo
}

setDNS(){
	echo -e "${Tip} 请输入正确格式的 DNS，多条记录以英文逗号隔开，仅支持Snell v4.1.0b1 版本及以上。"
	local p_prompt="(${Green_font_prefix}默认值${Font_color_suffix}：1.1.1.1, 8.8.8.8, 2001:4860:4860::8888)："
	[[ -n "$dns" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${dns} | ${Green_font_prefix}默认值${Font_color_suffix}：1.1.1.1, 8.8.8.8, 2001:4860:4860::8888)："
	echo -e -n "${p_prompt}"
	read -e input_dns
	[[ -z "${input_dns}" ]] && input_dns="1.1.1.1, 8.8.8.8, 2001:4860:4860::8888"
	dns=$input_dns
	echo && echo "=================================="
	echo -e "当前 DNS 为：${Red_background_prefix} ${dns} ${Font_color_suffix}"
	echo "==================================" && echo
}

setDNSIPPref(){
	echo -e "配置 DNS IP 偏好 (Snell v6 专属)
==================================
${Green_font_prefix} 1.${Font_color_suffix} default  ${Green_font_prefix} 2.${Font_color_suffix} prefer-ipv4 ${Green_font_prefix} 3.${Font_color_suffix} prefer-ipv6 ${Green_font_prefix} 4.${Font_color_suffix} ipv4-only ${Green_font_prefix} 5.${Font_color_suffix} ipv6-only
=================================="
	local current_opt="1"
	if [[ "$dns_ip_pref" == "prefer-ipv4" ]]; then current_opt="2"; elif [[ "$dns_ip_pref" == "prefer-ipv6" ]]; then current_opt="3"; elif [[ "$dns_ip_pref" == "ipv4-only" ]]; then current_opt="4"; elif [[ "$dns_ip_pref" == "ipv6-only" ]]; then current_opt="5"; fi
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}：1.default)："
	[[ -n "$dns_ip_pref" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${current_opt}.${dns_ip_pref} | ${Green_font_prefix}默认${Font_color_suffix}：1.default)："
	echo -e -n "${p_prompt}"
	read -e input_pref
	[[ -z "${input_pref}" && -n "$dns_ip_pref" ]] && input_pref=$current_opt
	[[ -z "${input_pref}" && -z "$dns_ip_pref" ]] && input_pref="1"
	dns_ip_pref_opt=$input_pref
	if [[ ${dns_ip_pref_opt} == "2" ]]; then
		dns_ip_pref="prefer-ipv4"
	elif [[ ${dns_ip_pref_opt} == "3" ]]; then
		dns_ip_pref="prefer-ipv6"
	elif [[ ${dns_ip_pref_opt} == "4" ]]; then
		dns_ip_pref="ipv4-only"
	elif [[ ${dns_ip_pref_opt} == "5" ]]; then
		dns_ip_pref="ipv6-only"
	else
		dns_ip_pref="default"
	fi
	echo && echo "=================================="
	echo -e "DNS IP 偏好 状态：${Red_background_prefix} ${dns_ip_pref} ${Font_color_suffix}"
	echo "==================================" && echo
}

setMode(){
	echo -e "配置 混淆模式
==================================
${Green_font_prefix} 1.${Font_color_suffix} default  ${Green_font_prefix} 2.${Font_color_suffix} unshaped ${Green_font_prefix} 3.${Font_color_suffix} unsafe-raw
=================================="
	local current_opt="1"
	if [[ "$mode" == "unshaped" ]]; then current_opt="2"; elif [[ "$mode" == "unsafe-raw" ]]; then current_opt="3"; fi
	local p_prompt="(${Green_font_prefix}默认${Font_color_suffix}：1.default)："
	[[ -n "$mode" ]] && p_prompt="(${Yellow_font_prefix}当前${Font_color_suffix}: ${current_opt}.${mode} | ${Green_font_prefix}默认${Font_color_suffix}：1.default)："
	echo -e -n "${p_prompt}"
	read -e input_pref
	[[ -z "${input_pref}" && -n "$mode" ]] && input_pref=$current_opt
	[[ -z "${input_pref}" && -z "$mode" ]] && input_pref="1"
	mode_opt=$input_pref
	if [[ ${mode_opt} == "2" ]]; then
		mode="unshaped"
	elif [[ ${mode_opt} == "3" ]]; then
		mode="unsafe-raw"
	else
		mode="default"
	fi
	echo && echo "=================================="
	echo -e "混淆模式：${Red_background_prefix} ${mode} ${Font_color_suffix}"
	echo "==================================" && echo
}

switchBinary(){
    local old_ver=$1
    local new_ver=$2
    echo -e "${Info} 开始下载 Snell v${new_ver} 版本..."
    service_stop
    if [[ -e "${snell_bin}" ]]; then
        echo -e "${Info} 备份当前程序文件..."
        cp "${snell_bin}" "${snell_bin}.v${old_ver}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    local target_full_version=""
    local web_version=$(getLatestVersionFromWeb "v${new_ver}")
    local script_version=""
    case "$new_ver" in
        "2") script_version=${snell_v2_version} ;;
        "3") script_version=${snell_v3_version} ;;
        "4") script_version=${snell_v4_version} ;;
        "5") script_version=${snell_v5_version} ;;
        "6") script_version=${snell_v6_version} ;;
    esac
    if [[ -n "$web_version" ]]; then
        if validateVersionUrl "$web_version"; then
            target_full_version="$web_version"
            echo -e "${Info} 使用网页获取的 Snell v${new_ver} 版本: v${target_full_version}"
        fi
    fi
    if [[ -z "$target_full_version" && -n "$script_version" ]]; then
        if validateVersionUrl "$script_version"; then
            target_full_version="$script_version"
            echo -e "${Info} 使用脚本内置的 Snell v${new_ver} 版本: v${target_full_version}"
        fi
    fi
    if [[ -z "$target_full_version" ]]; then
        target_full_version="$script_version"
    fi
    if [[ -n "$target_full_version" ]]; then
        downloadSnell "${target_full_version}" "Snell v${new_ver} 版本" true "$old_ver"
        if [[ $? -eq 0 ]]; then
            echo -e "${Info} Snell v${new_ver} 核心切换成功！"
            return 0
        else
            echo -e "${Error} Snell v${new_ver} 下载失败，正在回滚..."
        fi
    else
        echo -e "${Error} 无法找到 Snell v${new_ver} 的下载链接，切换失败！"
    fi
    backup_file=$(ls -t "${snell_bin}".v${old_ver}.backup.* 2>/dev/null | head -1)
    if [[ -n "$backup_file" && -e "$backup_file" ]]; then
        cp "$backup_file" "${snell_bin}"
        echo "v${old_ver}" > ${snell_version_file}
        echo -e "${Info} 已回滚到 Snell v${old_ver} 版本"
    fi
    service_start
    return 1
}

setConfig(){
    checkInstalledStatus
    local current_installed_ver=$(cat ${snell_version_file} | sed 's/^v//' | awk -F. '{print $1}')
    [[ -z "$current_installed_ver" ]] && current_installed_ver=$ver
    echo && echo -e "请输入要操作配置项的序号，然后回车
=============================="
    echo -e " ${Green_font_prefix}1.${Font_color_suffix} 修改 端口"
    echo -e " ${Green_font_prefix}2.${Font_color_suffix} 修改 密钥"
    if [[ "$current_installed_ver" != "6" ]]; then
        echo -e " ${Green_font_prefix}3.${Font_color_suffix} 配置 OBFS"
        echo -e " ${Green_font_prefix}4.${Font_color_suffix} 配置 OBFS 域名"
        echo -e " ${Green_font_prefix}5.${Font_color_suffix} 开关 IPv6 解析"
    fi
    echo -e " ${Green_font_prefix}6.${Font_color_suffix} 开关 TCP Fast Open"
    echo -e " ${Green_font_prefix}7.${Font_color_suffix} 配置 DNS"
    echo -e " ${Green_font_prefix}8.${Font_color_suffix} 配置 Snell 协议版本"
    if [[ "$current_installed_ver" == "6" ]]; then
        echo -e " ${Green_font_prefix}9.${Font_color_suffix} 配置 DNS IP 偏好"
        echo -e "${Green_font_prefix}10.${Font_color_suffix} 配置 混淆模式"
    fi
    echo -e "=============================="
    echo -e "${Green_font_prefix}11.${Font_color_suffix} 修改 全部配置" && echo
    read -e -p "(默认: 取消):" modify
    [[ -z "${modify}" ]] && echo "已取消..." && exit 1
    if [[ "${modify}" == "1" ]]; then
        readConfig
        setPort
        writeConfig
        service_restart
    elif [[ "${modify}" == "2" ]]; then
        readConfig
        setPSK
        writeConfig
        service_restart
    elif [[ "${modify}" == "3" ]]; then
        readConfig
        setObfs
        writeConfig
        service_restart
    elif [[ "${modify}" == "4" ]]; then
        readConfig
        if [[ ${obfs} == "off" ]]; then
            echo -e "${Error} OBFS 当前为 off，无法修改 OBFS 域名。"
        else
            setHost
            writeConfig
            service_restart
        fi
    elif [[ "${modify}" == "5" ]]; then
        readConfig
        setIpv6
        writeConfig
        service_restart
    elif [[ "${modify}" == "6" ]]; then
        readConfig
        setTFO
        writeConfig
        service_restart
    elif [[ "${modify}" == "7" ]]; then
        readConfig
        setDNS
        writeConfig
        service_restart
    elif [[ "${modify}" == "8" ]]; then
        readConfig
        local current_installed_ver=$(cat ${snell_version_file} | sed 's/^v//' | awk -F. '{print $1}')
        [[ -z "$current_installed_ver" ]] && current_installed_ver=$ver
        setVer
        if [[ "$ver" != "$current_installed_ver" ]]; then
            if [[ "$ver" -gt "$current_installed_ver" ]]; then
                echo -e "${Info} 协议版本将从 Snell v${current_installed_ver} 升级到 Snell v${ver}"
                echo -e "确定要升级吗？(y/N)"
            else
                echo -e "${Info} 协议版本将从 Snell v${current_installed_ver} 降级到 Snell v${ver}"
                echo -e "确定要降级吗？(y/N)"
            fi
            read -e -p "(默认: n):" confirm
            [[ -z "${confirm}" ]] && confirm="n"
            if [[ ${confirm} == [Yy] ]]; then
                if [[ "$ver" == "6" ]]; then
                    setDNSIPPref
                    setMode
                    checkPskForV6
                else
                    setObfs
                fi
                switchBinary "$current_installed_ver" "$ver"
                if [[ $? -ne 0 ]]; then
                    ver=$current_installed_ver
                else
                    writeConfig
                    service_restart
                    for ((i=0; i<10; i++)); do
                        sleep 1
                        checkStatus
                        if [[ "$status" == "running" ]]; then
                            break
                        fi
                    done
                    if [[ "$status" != "running" ]]; then
                        echo -e "${Error} 协议切换后服务启动失败，以下为错误日志："
                        if [[ "$SERVICE_TYPE" == "systemd" ]]; then
                            journalctl -u snell-server -n 20 --no-pager
                        fi
                        echo -e "${Error} 正在回滚到原版本..."
                        backup_file=$(ls -t "${snell_bin}".v${current_installed_ver}.backup.* 2>/dev/null | head -1)
                        if [[ -n "$backup_file" && -e "$backup_file" ]]; then
                            cp "$backup_file" "${snell_bin}"
                            echo "v${current_installed_ver}" > ${snell_version_file}
                            ver=$current_installed_ver
                            writeConfig
                            service_start
                            echo -e "${Info} 已回滚到 Snell v${current_installed_ver} 版本并恢复配置"
                        fi
                    else
                        echo -e "${Info} Snell Server 重启完毕！"
                    fi
                    sleep 3s
                    startMenu
                    return
                fi
            else
                echo -e "${Info} 已取消切换，保持原配置"
                ver=$current_installed_ver
            fi
        else
            echo -e "${Info} 版本未发生改变"
        fi
        writeConfig
        service_restart
    elif [[ "${modify}" == "9" ]]; then
        readConfig
        if [[ "$current_installed_ver" != "6" ]]; then
            echo -e "${Error} 当前版本不是 Snell v6，不支持 DNS IP 偏好配置！"
            sleep 2s; setConfig; return
        fi
        setDNSIPPref
        writeConfig
        service_restart
    elif [[ "${modify}" == "10" ]]; then
        readConfig
        if [[ "$current_installed_ver" != "6" ]]; then
            echo -e "${Error} 当前版本不是 Snell v6，不支持 混淆模式配置！"
            sleep 2s; setConfig; return
        fi
        setMode
        writeConfig
        service_restart
    elif [[ "${modify}" == "11" ]]; then
        readConfig
        local current_installed_ver=$(cat ${snell_version_file} | sed 's/^v//' | awk -F. '{print $1}')
        [[ -z "$current_installed_ver" ]] && current_installed_ver=$ver
        setVer
        if [[ "$ver" != "$current_installed_ver" ]]; then
            if [[ "$ver" -gt "$current_installed_ver" ]]; then
                echo -e "${Info} 协议版本将从 Snell v${current_installed_ver} 升级到 Snell v${ver}"
                echo -e "确定要升级吗？(y/N)"
            else
                echo -e "${Info} 协议版本将从 Snell v${current_installed_ver} 降级到 Snell v${ver}"
                echo -e "确定要降级吗？(y/N)"
            fi
            read -e -p "(默认: n):" confirm
            [[ -z "${confirm}" ]] && confirm="n"
            if [[ ${confirm} != [Yy] ]]; then
                echo -e "${Info} 已取消切换，保持原版本"
                ver=$current_installed_ver
            fi
        fi
        setPort
        setPSK
        if [[ "$ver" != "6" ]]; then
            setIpv6
        fi
        setTFO
        setDNS
        if [[ "$ver" == "6" ]]; then
            setDNSIPPref
            setMode
            checkPskForV6
        else
            setObfs
        fi
        if [[ "$ver" != "$current_installed_ver" ]]; then
            switchBinary "$current_installed_ver" "$ver"
            if [[ $? -ne 0 ]]; then
                ver=$current_installed_ver
                writeConfig
                service_restart
            else
                writeConfig
                service_restart
                for ((i=0; i<10; i++)); do
                    sleep 1
                    checkStatus
                    if [[ "$status" == "running" ]]; then
                        break
                    fi
                done
                if [[ "$status" != "running" ]]; then
                    echo -e "${Error} 协议切换后服务启动失败，以下为错误日志："
                    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
                        journalctl -u snell-server -n 20 --no-pager
                    fi
                    echo -e "${Error} 正在回滚到原版本..."
                    backup_file=$(ls -t "${snell_bin}".v${current_installed_ver}.backup.* 2>/dev/null | head -1)
                    if [[ -n "$backup_file" && -e "$backup_file" ]]; then
                        cp "$backup_file" "${snell_bin}"
                        echo "v${current_installed_ver}" > ${snell_version_file}
                        ver=$current_installed_ver
                        writeConfig
                        service_start
                        echo -e "${Info} 已回滚到 v${current_installed_ver} 版本并恢复配置"
                    fi
                else
                    echo -e "${Info} Snell Server 重启完毕！"
                fi
                sleep 3s
                startMenu
                return
            fi
        else
            writeConfig
            service_restart
        fi
    else
        echo -e "${Error} 请输入正确数字${Yellow_font_prefix}[1-11]${Font_color_suffix}"
        sleep 2s
        setConfig
    fi
    sleep 3s
    startMenu
}

installSnellV2(){
	checkRoot
	[[ -e ${snell_bin} ]] && echo -e "${Error} 检测到 Snell Server 已安装！" && exit 1
	echo -e "${Info} 开始设置 配置..."
	setPort
	setPSK
	setObfs
	setIpv6
	setTFO
	echo -e "${Info} 开始安装/配置 依赖..."
	checkDependencies
	installDependencies
	echo -e "${Info} 开始下载/安装..."
	downloadSnellV2
	echo -e "${Info} 开始安装 服务脚本..."
	setupService
	echo -e "${Info} 开始写入 配置文件..."
	writeConfig
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	startSnell
	echo -e "${Info} 启动完成，查看配置..."
    viewConfig
}

installSnellV3(){
	checkRoot
	[[ -e ${snell_bin} ]] && echo -e "${Error} 检测到 Snell Server 已安装！" && exit 1
	echo -e "${Info} 开始设置 配置..."
	setPort
	setPSK
	setObfs
	setIpv6
	setTFO
	echo -e "${Info} 开始安装/配置 依赖..."
	checkDependencies
	installDependencies
	echo -e "${Info} 开始下载/安装..."
	downloadSnellV3
	echo -e "${Info} 开始安装 服务脚本..."
	setupService
	echo -e "${Info} 开始写入 配置文件..."
	writeConfig
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	startSnell
	echo -e "${Info} 启动完成，查看配置..."
    viewConfig
}

installSnellV4(){
	checkRoot
	[[ -e ${snell_bin} ]] && echo -e "${Error} 检测到 Snell Server 已安装，请先卸载旧版再安装新版!" && exit 1
	echo -e "${Info} 开始设置 配置..."
	setPort
	setPSK
	setObfs
	setIpv6
	setTFO
	setDNS
	echo -e "${Info} 开始安装/配置 依赖..."
	checkDependencies
	installDependencies
	echo -e "${Info} 开始下载/安装..."
	downloadSnellV4
	echo -e "${Info} 开始安装 服务脚本..."
	setupService
	echo -e "${Info} 开始写入 配置文件..."
	writeConfig
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	startSnell
	echo -e "${Info} 启动完成，查看配置..."
    viewConfig
}

installSnellV5(){
	checkRoot
	[[ -e ${snell_bin} ]] && echo -e "${Error} 检测到 Snell Server 已安装，请先卸载旧版再安装新版!" && exit 1
	echo -e "${Info} 开始设置 配置..."
	setPort
	setPSK
	setObfs
	setIpv6
	setTFO
	setDNS
	echo -e "${Info} 开始安装/配置 依赖..."
	checkDependencies
	installDependencies
	echo -e "${Info} 开始下载/安装..."
	downloadSnellV5
	echo -e "${Info} 开始安装 服务脚本..."
	setupService
	echo -e "${Info} 开始写入 配置文件..."
	writeConfig
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	startSnell
	echo -e "${Info} 启动完成，查看配置..."
    viewConfig
}

downloadSnellV6(){
	downloadSnell "${snell_v6_version}" "Snell v6 官网源版"
}

installSnellV6(){
	checkRoot
	[[ -e ${snell_bin} ]] && echo -e "${Error} 检测到 Snell Server 已安装，请先卸载旧版再安装新版!" && exit 1
	echo -e "${Info} 开始设置 配置..."
	setPort
	setPSK
	setTFO
	setDNS
	setDNSIPPref
	setMode
	echo -e "${Info} 开始安装/配置 依赖..."
	checkDependencies
	installDependencies
	echo -e "${Info} 开始下载/安装..."
	downloadSnellV6
	echo -e "${Info} 开始安装 服务脚本..."
	setupService
	echo -e "${Info} 开始写入 配置文件..."
	writeConfig
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	startSnell
	echo -e "${Info} 启动完成，查看配置..."
    viewConfig
}

startSnell(){
    checkInstalledStatus
    checkStatus
    if [[ "$status" == "running" ]]; then
        echo -e "${Info} Snell Server 已在运行！"
    else
        echo -e "${Info} 正在启动 Snell Server..."
        service_start
        local timeout=12
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            sleep 1
            checkStatus
            if [[ "$status" == "running" ]]; then
                echo -e "${Info} Snell Server 启动成功！"
                return 0
            fi
            ((elapsed++))
        done
        checkStatus
        if [[ "$status" == "running" ]]; then
            echo -e "${Info} Snell Server 启动成功！"
        else
            echo -e "${Error} Snell Server 启动失败！"
            echo -e "${Error} 请使用以下命令查看详细错误："
            if [[ "$SERVICE_TYPE" == "systemd" ]]; then
                echo "journalctl -u snell-server -n 30 --no-pager"
            else
                echo "rc-service snell-server status"
                echo "cat /var/log/snell-server.log  (如有)"
            fi
            exit 1
        fi
    fi
}

stopSnell(){
	checkInstalledStatus
	checkStatus
	[[ "$status" != "running" ]] && echo -e "${Error} Snell Server 没有运行，请检查！" && exit 1
	service_stop
	echo -e "${Info} Snell Server 停止成功！"
    sleep 3s
    startMenu
}

restartSnell(){
	checkInstalledStatus
	service_restart
	echo -e "${Info} Snell Server 重启完毕!"
	sleep 3s
    startMenu
}

updateSnell(){
	checkInstalledStatus
	echo -e "${Info} Snell Server 更新完毕！"
    sleep 3s
    startMenu
}

updateV2toV3(){
	checkInstalledStatus
	readConfig
	if [[ "$ver" != "2" ]]; then
		echo -e "${Error} 当前版本不是 Snell v2，无法使用此功能！当前版本：Snell v${ver}"
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 即将将 Snell Server 从 Snell v2 更新到 Snell v3 版本"
	echo -e "确定要更新吗？(y/N)"
	read -e -p "(默认: n):" confirm
	[[ -z "${confirm}" ]] && confirm="n"
	if [[ ${confirm} != [Yy] ]]; then
		echo -e "${Info} 已取消更新"
		sleep 2s
		startMenu
		return 0
	fi
	echo -e "${Info} 开始更新 Snell v2 到 Snell v3..."
	service_stop
	if [[ -e "${snell_bin}" ]]; then
		echo -e "${Info} 备份当前程序文件..."
		cp "${snell_bin}" "${snell_bin}.v2.backup.$(date +%Y%m%d_%H%M%S)"
	fi
	echo -e "${Info} 开始下载 Snell v3 版本..."
	downloadSnellV3
	if [[ $? -eq 0 ]]; then
        echo -e "${Info} 更新配置文件版本号..."
        sed -i "s/version = 2/version = 3/g" "${snell_conf}"
		echo -e "${Info} 重启 Snell Server 服务..."
		service_daemon_reload
		service_start
		sleep 2
		checkStatus
		if [[ "$status" == "running" ]]; then
			echo -e "${Info} Snell v2 到 Snell v3 更新成功！"
			echo -e "${Info} 当前版本：Snell v3"
		else
			echo -e "${Error} 服务启动失败，正在回滚..."
			backup_file=$(ls -t "${snell_bin}".v2.backup.* 2>/dev/null | head -1)
			if [[ -n "$backup_file" && -e "$backup_file" ]]; then
				cp "$backup_file" "${snell_bin}"
				sed -i "s/version = 3/version = 2/g" "${snell_conf}"
				service_start
				echo -e "${Info} 已回滚到 Snell v2 版本"
			fi
		fi
	else
		echo -e "${Error} Snell v3 下载失败，保持 Snell v2 版本"
		service_start
	fi
	sleep 3s
	startMenu
}

updateV3toV4(){
	checkInstalledStatus
	readConfig
	if [[ "$ver" != "3" ]]; then
		echo -e "${Error} 当前版本不是 Snell v3，无法使用此功能！当前版本：Snell v${ver}"
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 即将将 Snell Server 从 Snell v3 更新到 Snell v4 版本"
	echo -e "确定要更新吗？(y/N)"
	read -e -p "(默认: n):" confirm
	[[ -z "${confirm}" ]] && confirm="n"
	if [[ ${confirm} != [Yy] ]]; then
		echo -e "${Info} 已取消更新"
		sleep 2s
		startMenu
		return 0
	fi
	echo -e "${Info} 开始更新 Snell v3 到 Snell v4..."
	service_stop
	if [[ -e "${snell_bin}" ]]; then
		echo -e "${Info} 备份当前程序文件..."
		cp "${snell_bin}" "${snell_bin}.v3.backup.$(date +%Y%m%d_%H%M%S)"
	fi
	current_v3_version=$(cat ${snell_version_file} | sed 's/^v//')
	web_v4_version=$(getLatestVersionFromWeb "v4")
	script_v4_version="${snell_v4_version}"
	target_v4_version=""
	if [[ -n "$web_v4_version" ]] && validateVersionUrl "$web_v4_version"; then
		target_v4_version="$web_v4_version"
		echo -e "${Info} 使用网页获取的 Snell v4 版本: v${target_v4_version}"
	elif [[ -n "$script_v4_version" ]] && validateVersionUrl "$script_v4_version"; then
		target_v4_version="$script_v4_version"
		echo -e "${Info} 使用脚本内置的 Snell v4 版本: v${target_v4_version}"
	fi
	if [[ -z "$target_v4_version" ]]; then
		echo -e "${Error} 无法找到有效的 Snell v4 版本进行更新"
		service_start
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 开始下载 Snell v4 版本..."
	downloadSnell "${target_v4_version}" "Snell v4 版本" true "3.0.1"
	if [[ $? -eq 0 ]]; then
        actual_version=$(cat ${snell_version_file} | sed 's/^v//')
        if [[ "$actual_version" =~ ^4\. ]]; then
            echo -e "${Info} 更新配置文件版本号..."
            sed -i "s/version = 3/version = 4/g" "${snell_conf}"
        else
            echo -e "${Tip} 注意：由于 Snell v4 下载链接问题，已回退重新安装 Snell v${actual_version} 版本"
        fi
		echo -e "${Info} 重启 Snell Server 服务..."
		service_daemon_reload
		service_start
		sleep 2
		checkStatus
		if [[ "$status" == "running" ]]; then
            if [[ "$actual_version" =~ ^4\. ]]; then
			    echo -e "${Info} Snell v3 到 Snell v4 更新成功！"
			    echo -e "${Info} 当前版本：Snell v${actual_version}"
            fi
		else
			echo -e "${Error} 服务启动失败，正在回滚..."
			backup_file=$(ls -t "${snell_bin}".v3.backup.* 2>/dev/null | head -1)
			if [[ -n "$backup_file" && -e "$backup_file" ]]; then
				cp "$backup_file" "${snell_bin}"
				echo "v3.0.1" > ${snell_version_file}
				sed -i "s/version = 4/version = 3/g" "${snell_conf}"
				service_start
				echo -e "${Info} 已回滚到 Snell v3 版本"
			fi
		fi
	else
		echo -e "${Error} Snell v4 下载失败，保持 Snell v3 版本"
		service_start
	fi
	sleep 3s
	startMenu
}

updateV4toV5(){
	checkInstalledStatus
	readConfig
	if [[ "$ver" != "4" ]]; then
		echo -e "${Error} 当前版本不是 Snell v4，无法使用此功能！当前版本：Snell v${ver}"
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 即将将 Snell Server 从 Snell v4 更新到 Snell v5 版本"
	echo -e "确定要更新吗？(y/N)"
	read -e -p "(默认: n):" confirm
	[[ -z "${confirm}" ]] && confirm="n"
	if [[ ${confirm} != [Yy] ]]; then
		echo -e "${Info} 已取消更新"
		sleep 2s
		startMenu
		return 0
	fi
	echo -e "${Info} 开始更新 Snell v4 到 Snell v5..."
	service_stop
	if [[ -e "${snell_bin}" ]]; then
		echo -e "${Info} 备份当前程序文件..."
		cp "${snell_bin}" "${snell_bin}.v4.backup.$(date +%Y%m%d_%H%M%S)"
	fi
	current_v4_version=$(cat ${snell_version_file} | sed 's/^v//')
	web_v5_version=$(getLatestVersionFromWeb "v5")
	script_v5_version="${snell_v5_version}"
	target_v5_version=""
	if [[ -n "$web_v5_version" ]]; then
		if validateVersionUrl "$web_v5_version"; then
			target_v5_version="$web_v5_version"
			echo -e "${Info} 使用网页获取的 Snell v5 版本: v${target_v5_version}"
		fi
	fi
	if [[ -z "$target_v5_version" && -n "$script_v5_version" ]]; then
		if validateVersionUrl "$script_v5_version"; then
			target_v5_version="$script_v5_version"
			echo -e "${Info} 使用脚本内置的 Snell v5 版本: v${target_v5_version}"
		fi
	fi
	if [[ -z "$target_v5_version" ]]; then
		echo -e "${Error} 无法找到有效的 Snell v5 版本进行更新"
		service_start
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 开始下载 Snell v5 版本..."
	downloadSnell "${target_v5_version}" "Snell v5 版本" true "${current_v4_version}"
	if [[ $? -eq 0 ]]; then
        actual_version=$(cat ${snell_version_file} | sed 's/^v//')
        if [[ "$actual_version" =~ ^5\. ]]; then
            echo -e "${Info} 更新配置文件版本号..."
            sed -i "s/version = 4/version = 5/g" "${snell_conf}"
        else
            echo -e "${Tip} 注意：由于 Snell v5 下载链接问题，已回退重新安装 Snell v${actual_version} 版本"
        fi
		echo -e "${Info} 重启 Snell Server 服务..."
		service_daemon_reload
		service_start
		sleep 2
		checkStatus
		if [[ "$status" == "running" ]]; then
            if [[ "$actual_version" =~ ^5\. ]]; then
			    echo -e "${Info} Snell v4 到 Snell v5 更新成功！"
			    echo -e "${Info} 当前版本：Snell v${actual_version}"
            fi
		else
			echo -e "${Error} 服务启动失败，正在回滚..."
			backup_file=$(ls -t "${snell_bin}".v4.backup.* 2>/dev/null | head -1)
			if [[ -n "$backup_file" && -e "$backup_file" ]]; then
				cp "$backup_file" "${snell_bin}"
				echo "v${current_v4_version}" > ${snell_version_file}
				sed -i "s/version = 5/version = 4/g" "${snell_conf}"
				service_start
				echo -e "${Info} 已回滚到 Snell v4 版本"
			fi
		fi
	else
		echo -e "${Error} Snell v5 下载失败，保持 Snell v4 版本"
		service_start
	fi
	sleep 3s
	startMenu
}

updateV5toV6(){
	checkInstalledStatus
	readConfig
	if [[ "$ver" != "5" ]]; then
		echo -e "${Error} 当前版本不是 Snell v5，无法使用此功能！当前版本：Snell v${ver}"
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 即将将 Snell Server 从 Snell v5 更新到 Snell v6 版本"
	echo -e "确定要更新吗？(y/N)"
	read -e -p "(默认: n):" confirm
	[[ -z "${confirm}" ]] && confirm="n"
	if [[ ${confirm} != [Yy] ]]; then
		echo -e "${Info} 已取消更新"
		sleep 2s
		startMenu
		return 0
	fi
	echo -e "${Info} 开始更新 Snell v5 到 Snell v6..."
	service_stop
	if [[ -e "${snell_bin}" ]]; then
		echo -e "${Info} 备份当前程序文件..."
		cp "${snell_bin}" "${snell_bin}.v5.backup.$(date +%Y%m%d_%H%M%S)"
	fi
	current_v5_version=$(cat ${snell_version_file} | sed 's/^v//')
	web_v6_version=$(getLatestVersionFromWeb "v6")
	script_v6_version="${snell_v6_version}"
	target_v6_version=""
	if [[ -n "$web_v6_version" ]]; then
		if validateVersionUrl "$web_v6_version"; then
			target_v6_version="$web_v6_version"
			echo -e "${Info} 使用网页获取的 Snell v6 版本: v${target_v6_version}"
		fi
	fi
	if [[ -z "$target_v6_version" && -n "$script_v6_version" ]]; then
		if validateVersionUrl "$script_v6_version"; then
			target_v6_version="$script_v6_version"
			echo -e "${Info} 使用脚本内置的 Snell v6 版本: v${target_v6_version}"
		fi
	fi
	if [[ -z "$target_v6_version" ]]; then
		echo -e "${Error} 无法找到有效的 Snell v6 版本进行更新"
		service_start
		sleep 3s
		startMenu
		return 1
	fi
	echo -e "${Info} 开始下载 Snell v6 版本..."
	downloadSnell "${target_v6_version}" "Snell v6 版本" true "${current_v5_version}"
	if [[ $? -eq 0 ]]; then
        actual_version=$(cat ${snell_version_file} | sed 's/^v//')
        if [[ "$actual_version" =~ ^6\. ]]; then
            echo -e "${Info} 更新配置文件版本号..."
            ver=6
            setDNSIPPref
            setMode
            checkPskForV6
            writeConfig
        else
            echo -e "${Tip} 注意：由于 Snell v6 下载链接问题，已回退重新安装 Snell v${actual_version} 版本"
        fi
		service_daemon_reload
		service_start
		for ((i=0; i<10; i++)); do
			sleep 1
			checkStatus
			if [[ "$status" == "running" ]]; then
				break
			fi
		done
		if [[ "$status" == "running" ]]; then
            if [[ "$actual_version" =~ ^6\. ]]; then
			    echo -e "${Info} Snell v5 到 Snell v6 更新成功！"
			    echo -e "${Info} 当前版本：Snell v${actual_version}"
            fi
		else
			echo -e "${Error} 升级后服务启动失败，以下为错误日志："
			if [[ "$SERVICE_TYPE" == "systemd" ]]; then
			    journalctl -u snell-server -n 20 --no-pager
			fi
			echo -e "${Error} 正在回滚..."
			backup_file=$(ls -t "${snell_bin}".v5.backup.* 2>/dev/null | head -1)
			if [[ -n "$backup_file" && -e "$backup_file" ]]; then
				cp "$backup_file" "${snell_bin}"
				echo "v${current_v5_version}" > ${snell_version_file}
				ver=5
				writeConfig
				service_start
				echo -e "${Info} 已回滚到 Snell v5 版本"
			fi
		fi
	else
		echo -e "${Error} Snell v6 下载失败，保持 Snell v5 版本"
		service_start
	fi
	sleep 3s
	startMenu
}

updateSnellServer(){
    checkInstalledStatus
    readConfig
    echo -e "${Info} 准备更新 Snell Server..."
    if [[ -n "$TARGET_UPDATE_VERSION" ]]; then
        local target_major=$(echo "$TARGET_UPDATE_VERSION" | awk -F. '{print $1}')
        if [[ "$ver" != "$target_major" ]]; then
             echo -e "${Warning} 注意：你正在尝试跨大版本更新 (从 v${ver} 到 v${target_major})！"
             echo -e "${Warning} 跨大版本更新可能会导致原有配置文件不兼容，从而引发服务启动失败。"
             read -e -p "是否确定继续？[y/N] (默认: n): " force_cross
             [[ -z "${force_cross}" ]] && force_cross="n"
             if [[ "${force_cross}" != [Yy]* ]]; then
                 echo -e "${Info} 已取消操作。"
                 exit 0
             fi
        fi
    fi
    if [[ -z "$current_installed_version" && -e ${snell_version_file} ]]; then
        current_installed_version=$(cat ${snell_version_file} | sed 's/^v//')
    fi
    force_checked=false
    if [[ "$update_available" != true ]]; then
        echo -e "${Info} 当前已是最新版本，无需更新！"
        echo -e "${Info} 当前版本: ${Green_font_prefix}v${current_installed_version}${Font_color_suffix}"
        echo
        echo -e "${Tip} 是否要强制重新检查最新版本？(y/N)"
        read -e -p "(默认: n):" force_check
        [[ -z "${force_check}" ]] && force_check="n"
        if [[ ${force_check} == [Yy] ]]; then
            echo -e "${Info} 强制重新检查最新版本..."
            rm -f /tmp/snell_version_cache
            updateBuiltinVersions true
            checkVersionUpdate true
            force_checked=true
            if [[ "$update_available" == true ]]; then
                echo -e "${Info} 检测到新版本，继续更新流程..."
            else
                echo -e "${Info} 重新检查后仍为最新版本"
                sleep 3s
                unset TARGET_UPDATE_VERSION
                startMenu
                return 0
            fi
        else
            sleep 3s
            unset TARGET_UPDATE_VERSION
            startMenu
            return 0
        fi
    fi
    echo -e "${Info} 当前版本: ${Yellow_font_prefix}v${current_installed_version}${Font_color_suffix}"
    if [[ -n "$TARGET_UPDATE_VERSION" ]]; then
        echo -e "${Info} 目标版本: ${Green_font_prefix}v${latest_available_version}${Font_color_suffix}"
    else
        echo -e "${Info} 最新版本: ${Green_font_prefix}v${latest_available_version}${Font_color_suffix}"
    fi
    echo -e "确定要更新吗？(Y/n)"
    read -e -p "(默认: y):" confirm
    [[ -z "${confirm}" ]] && confirm="y"
    if [[ ${confirm} == [Nn] ]]; then
        echo -e "${Info} 已取消更新"
        sleep 2s
        startMenu
        return 0
    fi
    if [[ -n "$TARGET_UPDATE_VERSION" ]]; then
        echo -e "${Info} 开始部署并更新 Snell Server 到 v${TARGET_UPDATE_VERSION}..."
    else
        echo -e "${Info} 开始更新 Snell Server 到最新版本..."
    fi
    echo -e "${Info} 停止 Snell Server 服务..."
    service_stop
    if [[ -e "${snell_bin}" ]]; then
        echo -e "${Info} 备份当前程序文件..."
        cp "${snell_bin}" "${snell_bin}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    echo -e "${Info} 开始下载最新版本文件..."
    case "$ver" in
        "6")
            downloadSnell "${latest_available_version}" "Snell v6 最新版" true "${current_installed_version}"
            ;;
        *)
            echo -e "${Error} 不支持的版本: Snell v${ver}"
            service_start
            sleep 3s
            unset TARGET_UPDATE_VERSION
            startMenu
            return 1
            ;;
    esac
    if [[ $? -eq 0 ]]; then
        echo -e "${Info} 重启 Snell Server 服务..."
        service_daemon_reload
        service_start
        sleep 2
        checkStatus
        if [[ "$status" == "running" ]]; then
            actual_version=$(cat ${snell_version_file} | sed 's/^v//')
            echo -e "${Info} Snell Server 更新成功！"
            echo -e "${Info} 当前版本：v${actual_version}"
            if [[ "$actual_version" != "$latest_available_version" ]]; then
                echo -e "${Tip} 注意：由于下载链接问题，已回退到 v${actual_version} 版本"
            fi
        else
            echo -e "${Error} 服务启动失败，正在回滚..."
            backup_file=$(ls -t "${snell_bin}".backup.* 2>/dev/null | head -1)
            if [[ -n "$backup_file" && -e "$backup_file" ]]; then
                cp "$backup_file" "${snell_bin}"
                echo "v${current_installed_version}" > ${snell_version_file}
                service_start
                echo -e "${Info} 已回滚到备份版本 v${current_installed_version}"
            fi
        fi
    else
        echo -e "${Error} 下载失败，启动原版本"
        service_start
    fi
    sleep 3s
    unset TARGET_UPDATE_VERSION
    startMenu
}

getLatestVersionFromWeb(){
    local version_type=$1
    local release_page="https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell"
    page_content=$(curl -s -L --max-time 10 "$release_page" 2>/dev/null)
    if [[ -z "$page_content" ]]; then
        return 1
    fi
    local max_version=""
    local versions=""
    if [[ "$version_type" == "v4" ]]; then
        versions=$(echo "$page_content" | grep -oE "snell-server-v4\.[0-9]+\.[0-9]+-linux" | sed 's/snell-server-v//g' | sed 's/-linux//g')
    elif [[ "$version_type" == "v5" ]]; then
        versions=$(echo "$page_content" | grep -oE "snell-server-v5\.[0-9]+\.[0-9]+[a-z]*[0-9]*-linux" | sed 's/snell-server-v//g' | sed 's/-linux//g')
    elif [[ "$version_type" == "v6" ]]; then
        versions=$(echo "$page_content" | grep -oE "snell-server-v6\.[0-9]+\.[0-9]+[a-z]*[0-9]*-linux" | sed 's/snell-server-v//g' | sed 's/-linux//g')
    fi
    if [[ -n "$versions" ]]; then
        for ver in $versions; do
            if [[ -z "$max_version" ]]; then
                max_version="$ver"
            else
                compareVersions "$ver" "$max_version"
                if [[ $? -eq 0 ]]; then
                    max_version="$ver"
                fi
            fi
        done
    fi
    if [[ -n "$max_version" ]]; then
        echo "$max_version"
        return 0
    fi
    return 1
}

updateBuiltinVersions(){
    local show_info=${1:-false}
    local cache_file="/tmp/snell_version_cache"
    local cache_time=3600
    local current_time=$(date +%s)
    web_v2_newer=false
    web_v3_newer=false
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
        if [[ -n "$cache_timestamp" && $((current_time - cache_timestamp)) -lt $cache_time ]]; then
            local cached_v4=$(sed -n '2p' "$cache_file" 2>/dev/null)
            local cached_v5=$(sed -n '3p' "$cache_file" 2>/dev/null)
            local cached_v6=$(sed -n '4p' "$cache_file" 2>/dev/null)
            if [[ -n "$cached_v4" && -n "$cached_v5" && -n "$cached_v6" ]]; then
                compareVersions "${snell_v4_version}" "$cached_v4"
                [[ $? -eq 2 ]] && web_v4_newer=true || web_v4_newer=false
                compareVersions "${snell_v5_version}" "$cached_v5"
                [[ $? -eq 2 ]] && web_v5_newer=true || web_v5_newer=false
                compareVersions "${snell_v6_version}" "$cached_v6"
                [[ $? -eq 2 ]] && web_v6_newer=true || web_v6_newer=false
                return 0
            fi
        fi
    fi
    [[ "$show_info" == true ]] && echo -e "${Info} 正在检查官方最新版本..."
    local latest_v4_web
    latest_v4_web=$(getLatestVersionFromWeb "v4")
    if [[ $? -eq 0 && -n "$latest_v4_web" ]]; then
        compareVersions "${snell_v4_version}" "$latest_v4_web"
        [[ $? -eq 2 ]] && web_v4_newer=true || web_v4_newer=false
    else
        web_v4_newer=false
        latest_v4_web="${snell_v4_version}"
    fi
    local latest_v5_web
    latest_v5_web=$(getLatestVersionFromWeb "v5")
    if [[ $? -eq 0 && -n "$latest_v5_web" ]]; then
        compareVersions "${snell_v5_version}" "$latest_v5_web"
        [[ $? -eq 2 ]] && web_v5_newer=true || web_v5_newer=false
    else
        web_v5_newer=false
        latest_v5_web="${snell_v5_version}"
    fi
    local latest_v6_web
    latest_v6_web=$(getLatestVersionFromWeb "v6")
    if [[ $? -eq 0 && -n "$latest_v6_web" ]]; then
        compareVersions "${snell_v6_version}" "$latest_v6_web"
        [[ $? -eq 2 ]] && web_v6_newer=true || web_v6_newer=false
    else
        web_v6_newer=false
        latest_v6_web="${snell_v6_version}"
    fi
    echo "$current_time" > "$cache_file"
    echo "$latest_v4_web" >> "$cache_file"
    echo "$latest_v5_web" >> "$cache_file"
    echo "$latest_v6_web" >> "$cache_file"
}

forceCheckVersions(){
    echo -e "${Info} 强制检查 Snell 最新版本..."
    rm -f "/tmp/snell_version_cache"
    updateBuiltinVersions true
    echo -e "${Info} 版本检查完成！"
    echo -e "${Info} 脚本内置 Snell v4 版本: ${Green_font_prefix}${snell_v4_version}${Font_color_suffix}"
    echo -e "${Info} 脚本内置 Snell v5 版本: ${Green_font_prefix}${snell_v5_version}${Font_color_suffix}"
    echo -e "${Info} 脚本内置 Snell v6 版本: ${Green_font_prefix}${snell_v6_version}${Font_color_suffix}"
    web_v4=$(getLatestVersionFromWeb "v4")
    web_v5=$(getLatestVersionFromWeb "v5")
    web_v6=$(getLatestVersionFromWeb "v6")
    if [[ -n "$web_v4" ]]; then
        echo -e "${Info} 网页获取 Snell v4 版本: ${Yellow_font_prefix}${web_v4}${Font_color_suffix}"
        compareVersions "${snell_v4_version}" "$web_v4"
        case $? in
            1) echo -e "${Info} Snell v4 版本状态: 脚本内置版本与网页版本相同" ;;
            0) echo -e "${Info} Snell v4 版本状态: 脚本内置版本比网页版本更新" ;;
            2) echo -e "${Tip} Snell v4 版本状态: 网页版本比脚本内置版本更新" ;;
        esac
    fi
    if [[ -n "$web_v5" ]]; then
        echo -e "${Info} 网页获取 Snell v5 版本: ${Yellow_font_prefix}${web_v5}${Font_color_suffix}"
        compareVersions "${snell_v5_version}" "$web_v5"
        case $? in
            1) echo -e "${Info} Snell v5 版本状态: 脚本内置版本与网页版本相同" ;;
            0) echo -e "${Info} Snell v5 版本状态: 脚本内置版本比网页版本更新" ;;
            2) echo -e "${Tip} Snell v5 版本状态: 网页版本比脚本内置版本更新" ;;
        esac
    fi
    if [[ -n "$web_v6" ]]; then
        echo -e "${Info} 网页获取 Snell v6 版本: ${Yellow_font_prefix}${web_v6}${Font_color_suffix}"
        compareVersions "${snell_v6_version}" "$web_v6"
        case $? in
            1) echo -e "${Info} Snell v6 版本状态: 脚本内置版本与网页版本相同" ;;
            0) echo -e "${Info} Snell v6 版本状态: 脚本内置版本比网页版本更新" ;;
            2) echo -e "${Tip} Snell v6 版本状态: 网页版本比脚本内置版本更新" ;;
        esac
    fi
    sleep 3s
    startMenu
}

uninstallSnell(){
	checkInstalledStatus
	echo "确定要卸载 Snell Server ? (y/N)"
	echo
	read -e -p "(默认: n):" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
		echo -e "${Info} 停止并禁用服务..."
		service_stop
		if [[ "$SERVICE_TYPE" == "systemd" ]]; then
            systemctl disable snell-server 2>/dev/null
            rm -f /etc/systemd/system/snell-server.service
        else
            rc-update del snell-server default 2>/dev/null
            rm -f /etc/init.d/snell-server
        fi
        service_daemon_reload
		echo -e "${Info} 移除主程序..."
		rm -rf "${snell_bin}"
		if [[ -f "${sysctl_conf}" ]]; then
			echo -e "${Tip} 由于网络优化配置可能被其他程序共用，卸载过程未移除网络优化配置，如需彻底移除可手动删除：${sysctl_conf}"
		fi
		echo -e "${Info} 移除配置文件及版本记录..."
		rm -rf /etc/snell
		echo && echo "Snell Server 卸载完成！" && echo
	else
		echo && echo "卸载已取消..." && echo
	fi
    sleep 3s
    startMenu
}

getIpv4(){
	ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip)
	if [[ -z "${ipv4}" ]]; then
		ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip)
		if [[ -z "${ipv4}" ]]; then
			ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip)
			if [[ -z "${ipv4}" ]]; then
				ipv4="IPv4_Error"
			fi
		fi
	fi
}

getIpv6(){
	ip6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
	if [[ -z "${ip6}" ]]; then
		ip6="IPv6_Error"
	fi
}

viewConfig(){
    checkInstalledStatus
    readConfig
    getIpv4
    getIpv6
    clear && echo
    echo -e "Snell Server 配置信息："
    echo -e "——————————————————————————————————————————————————"
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        echo -e " IPv4 地址\t: ${Green_font_prefix}${ipv4}${Font_color_suffix}"
    fi
    if [[ "${ip6}" != "IPv6_Error" ]]; then
        echo -e " IPv6 地址\t: ${Green_font_prefix}${ip6}${Font_color_suffix}"
    fi
    echo -e " 端口\t\t: ${Green_font_prefix}${port}${Font_color_suffix}"
    echo -e " 密钥\t\t: ${Green_font_prefix}${psk}${Font_color_suffix}"
    if [[ "$ver" != "6" ]]; then
        echo -e " OBFS\t\t: ${Green_font_prefix}${obfs}${Font_color_suffix}"
        if [[ "$obfs" != "off" && -n "$host" ]]; then
            echo -e " 域名\t\t: ${Green_font_prefix}${host}${Font_color_suffix}"
        fi
        echo -e " IPv6\t\t: ${Green_font_prefix}${ipv6}${Font_color_suffix}"
    fi
    echo -e " TFO\t\t: ${Green_font_prefix}${tfo}${Font_color_suffix}"
    echo -e " DNS\t\t: ${Green_font_prefix}${dns}${Font_color_suffix}"
    if [[ -n "${egress_interface}" ]]; then
        echo -e " 出口网卡\t: ${Green_font_prefix}${egress_interface}${Font_color_suffix}"
    fi
    if [[ "$ver" == "6" && -n "$dns_ip_pref" ]]; then
        echo -e " DNS IP 偏好\t: ${Green_font_prefix}${dns_ip_pref}${Font_color_suffix}"
    fi
    if [[ "$ver" == "6" && -n "$mode" ]]; then
        echo -e " 混淆模式\t: ${Green_font_prefix}${mode}${Font_color_suffix}"
    fi
    echo -e " 版本\t\t: ${Green_font_prefix}${ver}${Font_color_suffix}"
    echo -e "——————————————————————————————————————————————————"
    if [[ "$ver" == "6" ]]; then
        echo -e "${Tip} 如有监听多 IP 多端口需求，请手动编辑配置文件。"
        echo -e "——————————————————————————————————————————————————"
    fi
    echo -e "${Info} Surge 配置："
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        if [[ "${obfs}" == "off" || "${ver}" == "6" ]]; then
            if [[ "${ver}" == "6" && -n "${mode}" ]]; then
                echo -e "$(uname -n) = snell, ${ipv4}, ${port}, psk=${psk}, version=${ver}, tfo=${tfo}, mode=${mode}, reuse=true, ecn=true"
            else
                echo -e "$(uname -n) = snell, ${ipv4}, ${port}, psk=${psk}, version=${ver}, tfo=${tfo}, reuse=true, ecn=true"
            fi
        else
            echo -e "$(uname -n) = snell, ${ipv4}, ${port}, psk=${psk}, version=${ver}, tfo=${tfo}, obfs=${obfs}, obfs-host=${host}, reuse=true, ecn=true"
        fi
    elif [[ "${ip6}" != "IPv6_Error" ]]; then
        if [[ "${obfs}" == "off" || "${ver}" == "6" ]]; then
            if [[ "${ver}" == "6" && -n "${mode}" ]]; then
                echo -e "$(uname -n) = snell, [${ip6}], ${port}, psk=${psk}, version=${ver}, tfo=${tfo}, mode=${mode}, reuse=true, ecn=true"
            else
                echo -e "$(uname -n) = snell, [${ip6}], ${port}, psk=${psk}, version=${ver}, tfo=${tfo}, reuse=true, ecn=true"
            fi
        else
            echo -e "$(uname -n) = snell, [${ip6}], ${port}, psk=${psk}, version=${ver}, tfo=${tfo}, obfs=${obfs}, obfs-host=${host}, reuse=true, ecn=true"
        fi
    else
        echo -e "${Error} 无法获取 IP 地址！"
    fi
    echo -e "——————————————————————————————————————————————————"
    beforeStartMenu
}

viewStatus(){
    echo -e "${Info} 获取 Snell Server 活动日志 ……"
    if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        systemctl status snell-server --no-pager
    else
        rc-service snell-server status
    fi
    echo
    read -n 1 -s -r -p "按任意键返回主菜单..."
    startMenu
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://dash.cloudflare.com/cdn-cgi/trace https://cf-ns.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s $url 2>/dev/null)"
        if echo "$text" | grep -qw 'CN'; then
            isCN=true
            break
        fi
    done
}

updateShell(){
    geo_check
    if [ ! -z "$isCN" ]; then
        shell_url="https://gitee.com/ten/Snell/raw/master/Snell.sh"
    else
        shell_url="https://raw.githubusercontent.com/xOS/Snell/master/Snell.sh"
    fi
    echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
    sh_new_ver=$(wget --no-check-certificate -qO- "$shell_url"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
    [[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败！" && startMenu
    if [[ ${sh_new_ver} != ${sh_ver} ]]; then
        echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
        read -p "(默认: y):" yn
        [[ -z "${yn}" ]] && yn="y"
        if [[ ${yn} == [Yy] ]]; then
            wget -O snell.sh --no-check-certificate "$shell_url" && chmod +x snell.sh
            echo -e "脚本已更新为最新版本[ ${sh_new_ver} ]！"
            echo -e "3s后执行新脚本"
            sleep 3s
            exec bash snell.sh
        else
            echo && echo "	已取消..." && echo
            sleep 3s
            startMenu
        fi
    else
        echo -e "当前已是最新版本[ ${sh_new_ver} ]！"
        sleep 3s
        startMenu
    fi
}

beforeStartMenu() {
    echo && echo -n -e "${Yellow_font_prefix}* 按回车返回主菜单 *${Font_color_suffix}" && read temp
    startMenu
}

startMenu(){
    clear
    checkRoot
    checkSys
    sysArch
    action=$1
    if [[ -z "$action" ]]; then
        if [[ -e ${snell_bin} && -e ${snell_conf} ]]; then
            updateBuiltinVersions false >/dev/null 2>&1
            checkVersionUpdate false >/dev/null 2>&1
        fi
    fi
    show_update_option=false
    major_upgrade_text=""
    major_upgrade_func=""
    if [[ -e ${snell_bin} && -e ${snell_conf} ]]; then
        current_ver=$(cat ${snell_conf}|grep 'version = '|awk -F 'version = ' '{print $NF}')
        if [[ "$current_ver" == "2" ]]; then
            major_upgrade_text="Snell v2 更新到 Snell v3"
            major_upgrade_func="updateV2toV3"
        elif [[ "$current_ver" == "3" ]]; then
            major_upgrade_text="Snell v3 更新到 Snell v4"
            major_upgrade_func="updateV3toV4"
        elif [[ "$current_ver" == "4" ]]; then
            major_upgrade_text="Snell v4 更新到 Snell v5"
            major_upgrade_func="updateV4toV5"
        elif [[ "$current_ver" == "5" ]]; then
            major_upgrade_text="Snell v5 更新到 Snell v6"
            major_upgrade_func="updateV5toV6"
        elif [[ "$current_ver" == "6" ]]; then
            show_update_option=true
        fi
    fi
    echo && echo -e "
==============================
Snell Server 管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
==============================
 ${Green_font_prefix} 0.${Font_color_suffix} 更新脚本
——————————————————————————————
 ${Green_font_prefix} 1.${Font_color_suffix} 安装 Snell Server
 ${Green_font_prefix} 2.${Font_color_suffix} 卸载 Snell Server"
    if [[ "$show_update_option" == true ]]; then
        if [[ "$update_available" == true ]]; then
            echo -e " ${Green_font_prefix} 3.${Font_color_suffix} 更新 Snell Server ${Yellow_font_prefix}(可更新)${Font_color_suffix}"
        else
            echo -e " ${Green_font_prefix} 3.${Font_color_suffix} 更新 Snell Server"
        fi
        echo -e "——————————————————————————————
 ${Green_font_prefix} 4.${Font_color_suffix} 启动 Snell Server
 ${Green_font_prefix} 5.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix} 6.${Font_color_suffix} 重启 Snell Server
——————————————————————————————
 ${Green_font_prefix} 7.${Font_color_suffix} 设置 配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix} 9.${Font_color_suffix} 查看 运行状态
——————————————————————————————
 ${Green_font_prefix}00.${Font_color_suffix} 退出脚本"
        menu_max=9
    elif [[ -n "$major_upgrade_text" ]]; then
        echo -e " ${Green_font_prefix} 3.${Font_color_suffix} ${major_upgrade_text}"
        echo -e "——————————————————————————————
 ${Green_font_prefix} 4.${Font_color_suffix} 启动 Snell Server
 ${Green_font_prefix} 5.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix} 6.${Font_color_suffix} 重启 Snell Server
——————————————————————————————
 ${Green_font_prefix} 7.${Font_color_suffix} 设置 配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix} 9.${Font_color_suffix} 查看 运行状态
——————————————————————————————
 ${Green_font_prefix}00.${Font_color_suffix} 退出脚本"
        menu_max=9
    else
        echo -e "——————————————————————————————
 ${Green_font_prefix} 3.${Font_color_suffix} 启动 Snell Server
 ${Green_font_prefix} 4.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix} 5.${Font_color_suffix} 重启 Snell Server
——————————————————————————————
 ${Green_font_prefix} 6.${Font_color_suffix} 设置 配置信息
 ${Green_font_prefix} 7.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看 运行状态
——————————————————————————————
 ${Green_font_prefix}00.${Font_color_suffix} 退出脚本"
        menu_max=8
    fi
    echo "==============================" && echo
    if [[ -e ${snell_bin} ]]; then
        checkStatus
        if [[ "$status" == "running" ]]; then
            echo -e " 当前状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${snell_conf}|grep 'version = '|awk -F 'version = ' '{print $NF}')]${Font_color_suffix}且${Green_font_prefix}已启动${Font_color_suffix}"
        else
            echo -e " 当前状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${snell_conf}|grep 'version = '|awk -F 'version = ' '{print $NF}')]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
        fi
    else
        echo -e " 当前状态: ${Red_font_prefix}未安装${Font_color_suffix}"
    fi
    echo
    if [[ -n "$action" ]]; then
        num=$action
        echo -e " 自动选择选项: ${Green_font_prefix}${num}${Font_color_suffix}"
    else
        if [[ "$show_update_option" == true || -n "$major_upgrade_text" ]]; then
            read -e -p " 请输入数字[0-9]:" num
        else
            read -e -p " 请输入数字[0-8]:" num
        fi
    fi
    if [[ "$show_update_option" == true ]]; then
        case "$num" in
            0) updateShell ;;
            1) installSnell ;;
            2) uninstallSnell ;;
            3) updateSnellServer ;;
            4) startSnell ;;
            5) stopSnell ;;
            6) restartSnell ;;
            7) setConfig ;;
            8) viewConfig ;;
            9) viewStatus ;;
            00) exit 1 ;;
            *) echo -e "请输入正确数字${Yellow_font_prefix}[0-9]${Font_color_suffix}"; sleep 2s; startMenu ;;
        esac
    elif [[ -n "$major_upgrade_func" ]]; then
        case "$num" in
            0) updateShell ;;
            1) installSnell ;;
            2) uninstallSnell ;;
            3) ${major_upgrade_func} ;;
            4) startSnell ;;
            5) stopSnell ;;
            6) restartSnell ;;
            7) setConfig ;;
            8) viewConfig ;;
            9) viewStatus ;;
            00) exit 1 ;;
            *) echo -e "请输入正确数字${Yellow_font_prefix}[0-9]${Font_color_suffix}"; sleep 2s; startMenu ;;
        esac
    else
        case "$num" in
            0) updateShell ;;
            1) installSnell ;;
            2) uninstallSnell ;;
            3) startSnell ;;
            4) stopSnell ;;
            5) restartSnell ;;
            6) setConfig ;;
            7) viewConfig ;;
            8) viewStatus ;;
            00) exit 1 ;;
            *) echo -e "请输入正确数字${Yellow_font_prefix}[0-8]${Font_color_suffix}"; sleep 2s; startMenu ;;
        esac
    fi
}

# ==================== 脚本入口 ====================
checkServiceManager
if [[ -n "$1" ]]; then
    if [[ "$1" =~ ^[0-9]$ ]] || [[ "$1" == "00" ]]; then
        startMenu "$1"
        exit 0
    fi
    target_ver="$1"
    target_ver=$(echo "$target_ver" | sed 's/^v//')
    major_ver=$(echo "$target_ver" | awk -F. '{print $1}')
    if [[ "$major_ver" != "4" && "$major_ver" != "5" && "$major_ver" != "6" ]]; then
        echo -e "${Error} 提供的版本号格式不正确，或不支持该主版本！"
        exit 1
    fi
    if ! validateVersionUrl "$target_ver"; then
        echo -e "${Error} 未找到 Snell v${target_ver} 版本的下载链接，请确认拼写完全正确！"
        exit 1
    fi
    if [[ "$major_ver" == "4" ]]; then snell_v4_version="$target_ver"; fi
    if [[ "$major_ver" == "5" ]]; then snell_v5_version="$target_ver"; fi
    if [[ "$major_ver" == "6" ]]; then snell_v6_version="$target_ver"; fi
    if [[ -e ${snell_bin} && -e ${snell_conf} ]]; then
        TARGET_UPDATE_VERSION="$target_ver"
        checkVersionUpdate true
        updateSnellServer
        exit 0
    else
        echo -e "${Info} 检测到尚未安装 Snell，进入全新安装流程 (v${target_ver})..."
        if [[ "$major_ver" == "4" ]]; then installSnellV4; fi
        if [[ "$major_ver" == "5" ]]; then installSnellV5; fi
        if [[ "$major_ver" == "6" ]]; then installSnellV6; fi
        checkStatus
        if [[ "$status" == "running" ]]; then
            echo -e "${Info} Snell Server v${target_ver} 已成功安装并启动。"
        else
            echo -e "${Error} 安装遇到问题，服务未能启动，请通过 viewStatus 检查日志。"
        fi
        exit 0
    fi
fi

startMenu
