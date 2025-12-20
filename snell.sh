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

get_system_type() {
  if [ -f /etc/debian_version ]; then
    echo "debian"
  elif [ -f /etc/redhat-release ]; then
    echo "centos"
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
      || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
      echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
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
    apt-get install -y wget unzip curl
  elif [ "$system_type" = "centos" ]; then
    yum -y update
    yum -y install wget unzip curl
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
  if ! id "snell" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin snell
  fi
}

download_and_install_binary() {
  local arch url tmpdir
  arch="$(detect_arch)"
  url="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${arch}.zip"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  echo -e "${GREEN}下载: ${url}${RESET}"
  wget -qO "${tmpdir}/snell-server.zip" "${url}"

  unzip -oq "${tmpdir}/snell-server.zip" -d "${tmpdir}"
  if [ ! -f "${tmpdir}/snell-server" ]; then
    echo -e "${RED}解压失败：未找到 snell-server${RESET}"
    exit 1
  fi

  install -m 0755 "${tmpdir}/snell-server" /usr/local/bin/snell-server
}

write_config_and_service() {
  local final_port final_psk
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

  local host_ip ip_country
  host_ip="$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "${host_ip}" ]; then
    ip_country="$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true)"
  else
    ip_country=""
  fi

  cat > /etc/snell/config.txt <<EOF
${ip_country} = snell, ${host_ip}, ${final_port}, psk = ${final_psk}, version = 5, reuse = true
EOF

  echo -e "${GREEN}Snell 安装成功${RESET}"
  cat /etc/snell/config.txt || true
}

install_snell() {
  echo -e "${GREEN}正在安装 Snell${RESET}"
  wait_for_package_manager
  install_required_packages
  validate_port_psk
  ensure_user
  download_and_install_binary
  write_config_and_service
  systemctl restart snell
  sleep 2
  systemctl --no-pager --full status snell || true
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
  systemctl restart snell
  sleep 2
  journalctl -u snell.service -n 8 --no-pager || true
  cat /etc/snell/config.txt 2>/dev/null || true
}

uninstall_snell() {
  echo -e "${GREEN}正在卸载 Snell${RESET}"
  systemctl stop snell 2>/dev/null || true
  systemctl disable snell 2>/dev/null || true
  rm -f /etc/systemd/system/snell.service
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true
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
    systemctl start snell
    ;;
  stop)
    check_root
    systemctl stop snell
    ;;
  status)
    systemctl --no-pager --full status snell
    ;;
  show-config)
    show_config
    ;;
  *)
    echo -e "${RED}无效参数${RESET}"
    exit 1
    ;;
esac
