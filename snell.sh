# 1. 创建脚本文件
cat > snell_fix.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-v5.0.1}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

action="${action:-install}"
port="${port:-}"
psk="${psk:-}"

# --- 系统检测 ---
get_system_type() {
  if [ -f /etc/alpine-release ]; then
    echo "alpine"
  elif [ -f /etc/debian_version ]; then
    echo "debian"
  elif [ -f /etc/redhat-release ]; then
    echo "centos"
  else
    echo "unknown"
  fi
}

SYSTEM_TYPE="$(get_system_type)"

check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
    exit 1
  fi
}

# --- 依赖安装 ---
install_required_packages() {
  echo -e "${GREEN}检测系统: ${SYSTEM_TYPE}${RESET}"
  echo -e "${GREEN}安装必要软件包...${RESET}"

  case "$SYSTEM_TYPE" in
    alpine)
      apk update
      apk add bash wget curl unzip gcompat libstdc++ ca-certificates shadow
      ;;
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y wget unzip curl ca-certificates
      ;;
    centos)
      yum -y update
      yum -y install wget unzip curl ca-certificates
      ;;
    *)
      echo -e "${RED}不支持的系统类型${RESET}"
      exit 1
      ;;
  esac
}

detect_arch() {
  local a
  a="$(uname -m)"
  case "$a" in
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64) echo "amd64" ;;
    *)
      echo -e "${RED}不支持的架构: ${a}${RESET}"
      exit 1
      ;;
  esac
}

ensure_user() {
  if ! id "snell" &>/dev/null; then
    if [ "$SYSTEM_TYPE" = "alpine" ]; then
      useradd -r -s /sbin/nologin snell
    else
      useradd -r -s /usr/sbin/nologin snell
    fi
  fi
}

download_and_install_binary() {
  local arch url tmpdir
  arch="$(detect_arch)"
  url="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${arch}.zip"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir:-}"' EXIT

  echo -e "${GREEN}下载: ${url}${RESET}"
  wget -qO "${tmpdir}/snell-server.zip" "${url}"

  unzip -oq "${tmpdir}/snell-server.zip" -d "${tmpdir}"
  install -m 0755 "${tmpdir}/snell-server" /usr/local/bin/snell-server
  rm -rf "${tmpdir}"
  trap - EXIT
}

service_install() {
  local final_port="\$1"
  local final_psk="\$2"
  
  mkdir -p /etc/snell
  cat > /etc/snell/snell-server.conf <<CONF
[snell-server]
listen = :::${final_port}
psk = ${final_psk}
ipv6 = true
CONF

  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    # OpenRC 配置 (Alpine 专用)
    cat > /etc/init.d/snell <<INIT
#!/sbin/openrc-run

name="snell"
description="Snell Proxy Service"
command="/usr/local/bin/snell-server"
command_args="-c /etc/snell/snell-server.conf"
command_background=true
pidfile="/run/snell.pid"
command_user="snell:snell"

depend() {
    need net
    after firewall
}
INIT
    chmod +x /etc/init.d/snell
    rc-update add snell default
  else
    # Systemd 配置
    cat > /etc/systemd/system/snell.service <<SERVICE
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
LimitNOFILE=32768
Restart=on-failure
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload
    systemctl enable snell
  fi
}

service_restart() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell restart
  else
    systemctl restart snell
  fi
}

generate_share_link() {
  local p_port="\$1"
  local p_psk="\$2"
  local host_ip ip_country

  host_ip="$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "${host_ip}" ]; then
    ip_country="$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  if [ -z "${ip_country}" ]; then ip_country="UN"; fi

  cat > /etc/snell/config.txt <<INFO
${ip_country} = snell, ${host_ip}, ${p_port}, psk = ${p_psk}, version = 5, reuse = true, tfo = true
INFO
}

install_snell() {
  install_required_packages
  ensure_user
  download_and_install_binary

  local final_port final_psk
  # 优先使用环境变量，否则随机生成
  if [ -n "${port}" ]; then final_port="${port}"; else final_port="$(shuf -i 30000-65000 -n 1)"; fi
  if [ -n "${psk}" ]; then final_psk="${psk}"; else final_psk="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)"; fi

  service_install "${final_port}" "${final_psk}"
  generate_share_link "${final_port}" "${final_psk}"
  service_restart
  
  sleep 2
  echo -e "${GREEN}Snell 安装成功${RESET}"
  cat /etc/snell/config.txt || true
}

install_snell
EOF

# 2. 赋予权限
chmod +x snell_fix.sh

# 3. 运行脚本 (带上你的端口和密码)
port=36818 psk=8c3f2083-62e8-56ad-fe13-872a266a8ed8 ./snell_fix.sh
