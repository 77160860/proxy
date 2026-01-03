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
  echo -e "${GREEN}安装必要软件包 (${SYSTEM_TYPE})...${RESET}"

  case "$SYSTEM_TYPE" in
    alpine)
      # Alpine 需要 gcompat 来运行 glibc 的二进制文件
      apk update
      apk add bash wget curl unzip gcompat libstdc++ ca-certificates shadow
      ;;
    debian)
      wait_for_apt_lock
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

wait_for_apt_lock() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
    || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
    || fuser /var/lib/apt/lists/lock-frontend >/dev/null 2>&1 \
    || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
    sleep 1
  done
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

validate_port_psk() {
  if [ -n "${port}" ]; then
    if ! [[ "${port}" =~ ^[0-9]+$ ]] || [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
      echo -e "${RED}port 无效(1-65535): ${port}${RESET}"
      exit 1
    fi
  fi

  if [ -n "${psk}" ]; then
    if [ "${#psk}" -lt 8 ]; then
      echo -e "${RED}psk 太短(建议>=8位)${RESET}"
      exit 1
    fi
  fi
}

ensure_user() {
  if ! id "snell" &>/dev/null; then
    echo -e "${GREEN}创建 snell 用户...${RESET}"
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
  if [ ! -f "${tmpdir}/snell-server" ]; then
    echo -e "${RED}解压失败：未找到 snell-server${RESET}"
    exit 1
  fi

  install -m 0755 "${tmpdir}/snell-server" /usr/local/bin/snell-server
  rm -rf "${tmpdir}"
  trap - EXIT
}

# --- 服务管理抽象 ---

service_install() {
  local final_port="\$1"
  local final_psk="\$2"
  
  # 1. 写入配置文件
  mkdir -p /etc/snell
  cat > /etc/snell/snell-server.conf <<EOF
[snell-server]
listen = :::${final_port}
psk = ${final_psk}
ipv6 = true
EOF

  # 2. 根据系统类型配置服务
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    # OpenRC 配置
    cat > /etc/init.d/snell <<EOF
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
EOF
    chmod +x /etc/init.d/snell
    rc-update add snell default
  else
    # Systemd 配置
    cat > /etc/systemd/system/snell.service <<EOF
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
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable snell
  fi
}

service_start() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell start
  else
    systemctl start snell
  fi
}

service_stop() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell stop || true
  else
    systemctl stop snell || true
  fi
}

service_restart() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell restart
  else
    systemctl restart snell
  fi
}

service_status() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell status
  else
    systemctl --no-pager --full status snell
  fi
}

service_uninstall() {
  service_stop
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-update del snell default || true
    rm -f /etc/init.d/snell
  else
    systemctl disable snell || true
    rm -f /etc/systemd/system/snell.service
    systemctl daemon-reload
    systemctl reset-failed || true
  fi
}

generate_share_link() {
  local final_port="\$1"
  local final_psk="\$2"
  local host_ip ip_country

  host_ip="$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "${host_ip}" ]; then
    ip_country="$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true)"
  else
    ip_country=""
  fi

  cat > /etc/snell/config.txt <<EOF
${ip_country} = snell, ${host_ip}, ${final_port}, psk = ${final_psk}, version = 5, reuse = true, tfo = true
EOF
}

# --- 主逻辑 ---

install_snell() {
  install_required_packages
  validate_port_psk
  ensure_user
  download_and_install_binary

  local final_port final_psk
  if [ -z "${port}" ]; then
    final_port="$(shuf -i 30000-65000 -n 1)"
  else
    final_port="${port}"
  fi

  if [ -z "${psk}" ]; then
    final_psk="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)"
  else
    final_psk="${psk}"
  fi

  service_install "${final_port}" "${final_psk}"
  generate_share_link "${final_port}" "${final_psk}"
  service_restart
  
  sleep 2
  echo -e "${GREEN}Snell 安装成功${RESET}"
  cat /etc/snell/config.txt || true
}

update_snell() {
  if [ ! -x "/usr/local/bin/snell-server" ]; then
    echo -e "${YELLOW}Snell 未安装，无法更新${RESET}"
    exit 1
  fi
  echo -e "${GREEN}Snell 正在更新...${RESET}"
  install_required_packages
  download_and_install_binary
  service_restart
  sleep 2
  echo -e "${GREEN}更新完成${RESET}"
  cat /etc/snell/config.txt 2>/dev/null || true
}

uninstall_snell() {
  echo -e "${GREEN}正在卸载 Snell...${RESET}"
  service_uninstall
  rm -f /usr/local/bin/snell-server
  rm -rf /etc/snell
  echo -e "${GREEN}Snell 卸载成功${RESET}"
}

show_config() {
  if [ -f /etc/snell/config.txt ]; then
    cat /etc/snell/config.txt
  else
    echo -e "${RED}配置文件不存在${RESET}"
    exit 1
  fi
}

case "${action}" in
  install)
    check_root
    install_snell
    ;;
  update)
    check_root
    update_snell
    ;;
  uninstall)
    check_root
    uninstall_snell
    ;;
  start)
    check_root
    service_start
    ;;
  stop)
    check_root
    service_stop
    ;;
  status)
    service_status
    ;;
  show-config)
    show_config
    ;;
  *)
    echo -e "${RED}无效参数: ${action}${RESET}"
    echo "用法: action=[install|update|uninstall|start|stop|status|show-config] ./snell.sh"
    exit 1
    ;;
esac
