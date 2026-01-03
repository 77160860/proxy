#!/usr/bin/env bash
set -euo pipefail

ENV_PORT="${port:-}"
ENV_PSK="${psk:-}"
VERSION="${VERSION:-v5.0.1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

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

install_required_packages() {
  echo -e "${GREEN}Detected System: ${SYSTEM_TYPE}${RESET}"
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
      echo -e "${RED}Unsupported System${RESET}"
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
    *) echo -e "${RED}Unsupported Arch: ${a}${RESET}"; exit 1 ;;
  esac
}

download_and_install() {
  if ! id "snell" &>/dev/null; then
    if [ "$SYSTEM_TYPE" = "alpine" ]; then
      useradd -r -s /sbin/nologin snell
    else
      useradd -r -s /usr/sbin/nologin snell
    fi
  fi

  local arch url tmpdir
  arch="$(detect_arch)"
  url="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${arch}.zip"

  tmpdir="$(mktemp -d)"
  echo -e "${GREEN}Downloading Snell...${RESET}"
  wget -qO "${tmpdir}/snell-server.zip" "${url}"
  unzip -oq "${tmpdir}/snell-server.zip" -d "${tmpdir}"
  install -m 0755 "${tmpdir}/snell-server" /usr/local/bin/snell-server
  rm -rf "${tmpdir}"
}

configure_service() {
  local c_port="\$1"
  local c_psk="\$2"

  mkdir -p /etc/snell
  
  # 注意：下面的 EOF 没有单引号，这样变量才能生效
  cat > /etc/snell/snell-server.conf <<EOF
[snell-server]
listen = :::${c_port}
psk = ${c_psk}
ipv6 = true
EOF

  if [ "$SYSTEM_TYPE" = "alpine" ]; then
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
    rc-service snell restart
  else
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
SyslogIdentifier=snell-server
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable snell
    systemctl restart snell
  fi
}

generate_link() {
  local l_port="\$1"
  local l_psk="\$2"
  local host_ip ip_country

  host_ip="$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "${host_ip}" ]; then
    ip_country="$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  if [ -z "${ip_country}" ]; then ip_country="UN"; fi

  # 注意：下面的 EOF 没有单引号
  cat > /etc/snell/config.txt <<EOF
${ip_country} = snell, ${host_ip}, ${l_port}, psk = ${l_psk}, version = 5, reuse = true, tfo = true
EOF
}

main() {
  install_required_packages
  download_and_install

  local final_port final_psk

  if [ -n "${ENV_PORT}" ]; then
    final_port="${ENV_PORT}"
  else
    final_port="$(shuf -i 30000-65000 -n 1)"
  fi

  if [ -n "${ENV_PSK}" ]; then
    final_psk="${ENV_PSK}"
  else
    final_psk="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)"
  fi

  configure_service "${final_port}" "${final_psk}"
  generate_link "${final_port}" "${final_psk}"

  sleep 2
  echo -e "${GREEN}Install Success!${RESET}"
  cat /etc/snell/config.txt || true
}

main
