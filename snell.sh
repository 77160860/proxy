#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-v5.0.1}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

action="${1:-${action:-install}}"
port="${port:-}"
psk="${psk:-}"

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

get_init_system() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    echo "systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    echo "openrc"
  else
    echo "unknown"
  fi
}

check_root() {
  if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
    exit 1
  fi
}

wait_for_package_manager() {
  local system_type
  system_type="$(get_system_type)"
  if [ "$system_type" = "debian" ]; then
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
      || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
      || fuser /var/lib/apt/lists/lock-frontend >/dev/null 2>&1 \
      || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
      echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
      sleep 1
    done
  elif [ "$system_type" = "alpine" ]; then
    while fuser /var/lib/apk/db/lock >/dev/null 2>&1; do
      echo -e "${YELLOW}等待其他 apk 进程完成${RESET}"
      sleep 1
    done
  fi
}

install_required_packages() {
  local system_type
  system_type="$(get_system_type)"
  echo -e "${GREEN}安装必要软件包${RESET}"

  if [ "$system_type" = "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y wget unzip curl ca-certificates
  elif [ "$system_type" = "centos" ]; then
    yum -y update
    yum -y install wget unzip curl ca-certificates
  elif [ "$system_type" = "alpine" ]; then
    apk update
    apk add --no-cache wget unzip curl ca-certificates openrc
    update-ca-certificates >/dev/null 2>&1 || true
  else
    echo -e "${RED}不支持的系统类型${RESET}"
    exit 1
  fi
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
  local system_type
  system_type="$(get_system_type)"

  if id "snell" &>/dev/null; then
    return 0
  fi

  if [ "$system_type" = "alpine" ]; then
    adduser -S -D -H -s /sbin/nologin snell
  else
    useradd -r -s /usr/sbin/nologin snell
  fi
}

download_and_install_binary() {
  local arch url
  arch="$(detect_arch)"
  url="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${arch}.zip"

  local tmpdir
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

service_start() {
  local init_system
  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
    systemctl start snell
  elif [ "$init_system" = "openrc" ]; then
    rc-service snell start
  else
    echo -e "${RED}无法启动服务：未检测到 systemd/openrc${RESET}"
    exit 1
  fi
}

service_stop() {
  local init_system
  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
    systemctl stop snell
  elif [ "$init_system" = "openrc" ]; then
    rc-service snell stop
  else
    return 0
  fi
}

service_restart() {
  local init_system
  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
    systemctl restart snell
  elif [ "$init_system" = "openrc" ]; then
    rc-service snell restart
  else
    echo -e "${RED}无法重启服务：未检测到 systemd/openrc${RESET}"
    exit 1
  fi
}

service_enable() {
  local init_system
  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
    systemctl enable snell
  elif [ "$init_system" = "openrc" ]; then
    rc-update add snell default >/dev/null 2>&1 || true
  fi
}

service_disable() {
  local init_system
  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
    systemctl disable snell 2>/dev/null || true
  elif [ "$init_system" = "openrc" ]; then
    rc-update del snell default >/dev/null 2>&1 || true
  fi
}

service_status() {
  local init_system
  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
    systemctl --no-pager --full status snell
  elif [ "$init_system" = "openrc" ]; then
    rc-service snell status
  else
    echo -e "${RED}无法获取状态：未检测到 systemd/openrc${RESET}"
    exit 1
  fi
}

write_config_and_service() {
  local final_port final_psk init_system
  mkdir -p /etc/snell

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

  cat > /etc/snell/snell-server.conf <<EOF
[snell-server]
listen = :::${final_port}
psk = ${final_psk}
ipv6 = true
EOF

  init_system="$(get_init_system)"
  if [ "$init_system" = "systemd" ]; then
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
    service_enable
  elif [ "$init_system" = "openrc" ]; then
    cat > /etc/init.d/snell <<'EOF'
#!/sbin/openrc-run

name="snell"
description="Snell Proxy Service"

command="/usr/local/bin/snell-server"
command_args="-c /etc/snell/snell-server.conf"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"

output_log="/var/log/snell.log"
error_log="/var/log/snell.err"

depend() {
  need net
}
EOF
    chmod +x /etc/init.d/snell
    mkdir -p /run /var/log
    service_enable
  else
    echo -e "${RED}未检测到 systemd/openrc，无法创建服务${RESET}"
    exit 1
  fi

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

install_snell() {
  echo -e "${GREEN}正在安装 Snell${RESET}"
  wait_for_package_manager
  install_required_packages
  validate_port_psk
  ensure_user
  download_and_install_binary
  write_config_and_service
  service_restart
  sleep 2
  service_status || true
  echo -e "${GREEN}Snell 安装成功${RESET}"
  cat /etc/snell/config.txt || true
}

update_snell() {
  if [ ! -x "/usr/local/bin/snell-server" ]; then
    echo -e "${YELLOW}Snell 未安装，无法更新${RESET}"
    exit 1
  fi
  echo -e "${GREEN}Snell 正在更新${RESET}"
  wait_for_package_manager
  install_required_packages
  download_and_install_binary
  service_restart
  sleep 2
  if [ "$(get_init_system)" = "systemd" ]; then
    journalctl -u snell.service -n 8 --no-pager || true
  fi
  cat /etc/snell/config.txt 2>/dev/null || true
}

uninstall_snell() {
  echo -e "${GREEN}正在卸载 Snell${RESET}"
  service_stop 2>/dev/null || true
  service_disable 2>/dev/null || true

  if [ "$(get_init_system)" = "systemd" ]; then
    rm -f /etc/systemd/system/snell.service
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true
  elif [ "$(get_init_system)" = "openrc" ]; then
    rm -f /etc/init.d/snell
  fi

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
  show-config|config)
    show_config
    ;;
  *)
    echo -e "${RED}无效参数${RESET}"
    exit 1
    ;;
esac
