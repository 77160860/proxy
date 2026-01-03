cat > snell.sh << 'EOF'
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
      apk update
      # 安装 bash, curl, unzip, gcompat (运行 glibc 程序), shadow (useradd)
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

# --- 服务配置 ---

service_install() {
  local final_port="\$1"
  local final_psk="\$2"
  
  mkdir -p /etc/snell
  cat > /etc/snell/snell-server.conf <<EOF
[snell-server]
listen = :::${final_port}
psk = ${final_psk}
ipv6 = true
EOF

  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    # OpenRC
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
    # Systemd
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

service_restart() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell restart
  else
    systemctl restart snell
  fi
}

service_stop() {
  if [ "$SYSTEM_TYPE" = "alpine" ]; then
    rc-service snell stop || true
  else
    systemctl stop snell || true
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

# --- 关键修复：正确生成配置文本 ---
generate_share_link() {
  local p_port="\$1"
  local p_psk="\$2"
  local host_ip ip_country

  # 获取IP
  host_ip="$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  
  # 获取国家代码，如果失败默认为 UN
  if [ -n "${host_ip}" ]; then
    ip_country="$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  if [ -z "${ip_country}" ]; then
    ip_country="UN"
  fi

  # 写入文件，注意这里使用的是变量 p_port 和 p_psk
  cat > /etc/snell/config.txt <<EOF
${ip_country} = snell, ${host_ip}, ${p_port}, psk = ${p_psk}, version = 5, reuse = true, tfo = true
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

  # 1. 安装服务配置
  service_install "${final_port}" "${final_psk}"
  
  # 2. 生成分享链接 (修复了这里)
  generate_share_link "${final_port}" "${final_psk}"
  
  # 3. 启动服务
  service_restart
  
  sleep 2
  echo -e "${GREEN}Snell 安装成功${RESET}"
  # 4. 显示配置
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
    if [ "$SYSTEM_TYPE" = "alpine" ]; then rc-service snell start; else systemctl start snell; fi
    ;;
  stop)
    check_root
    service_stop
    ;;
  status)
    if [ "$SYSTEM_TYPE" = "alpine" ]; then rc-service snell status; else systemctl status snell; fi
    ;;
  show-config)
    show_config
    ;;
  *)
    echo -e "${RED}无效参数: ${action}${RESET}"
    exit 1
    ;;
esac
EOF
chmod +x snell.sh
bash snell.sh
