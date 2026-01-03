#!/usr/bin/env bash
set -euo pipefail

DEFAULT_VERSION="v5.0.1"
DEFAULT_USER="snell"
DEFAULT_SERVICE="snell"
DEFAULT_INSTALL_DIR="/usr/local/bin"
DEFAULT_CONF_DIR="/etc/snell"
DEFAULT_PORT_RANGE_START=30000
DEFAULT_PORT_RANGE_END=65000
DEFAULT_PSK_LEN=20

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  RESET=''
fi

msg()    { printf "${GREEN}%s${RESET}\n" "$*"; }
warn()   { printf "${YELLOW}%s${RESET}\n" "$*"; }
error()  { printf "${RED}%s${RESET}\n" "$*" >&2; }

require_cmd() { command -v "$1" >/dev/null || { error "Missing required command: $1"; exit 1; }; }
check_root() { [[ "$(id -u)" -eq 0 ]] || { error "Please run this script as root."; exit 1; }; }

get_system_type() {
  if [[ -f /etc/debian_version ]]; then echo "debian";
  elif [[ -f /etc/redhat-release ]]; then echo "centos";
  elif [[ -f /etc/alpine-release ]]; then echo "alpine";
  else echo "unknown"; fi
}

wait_for_package_manager() {
  local sys; sys=$(get_system_type)
  case "$sys" in
    debian)
      while fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
        || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
        || fuser /var/lib/apt/lists/lock-frontend >/dev/null 2>&1 \
        || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        warn "Another apt process is running, waiting..."
        sleep 1
      done
      ;;
    centos)
      while fuser /var/run/rpm.lock >/dev/null 2>&1; do
        warn "Another yum/dnf process is running, waiting..."
        sleep 1
      done
      ;;
    alpine) ;;
    *) error "Unsupported system type for lock waiting."; exit 1 ;;
  esac
}

install_required_packages() {
  local sys; sys=$(get_system_type)
  msg "Installing required packages..."
  case "$sys" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y wget unzip curl ca-certificates
      ;;
    centos)
      yum -y update
      yum -y install wget unzip curl ca-certificates
      ;;
    alpine)
      apk update
      apk add --no-cache wget unzip curl ca-certificates
      ;;
    *) error "Unsupported system type."; exit 1 ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64)   echo "amd64" ;;
    *) error "Unsupported CPU architecture: $(uname -m)"; exit 1 ;;
  esac
}

validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

pick_free_port() {
  local p
  for _ in {1..10}; do
    p=$(shuf -i "${DEFAULT_PORT_RANGE_START}-${DEFAULT_PORT_RANGE_END}" -n 1)
    if ! ss -ltn "sport = :$p" >/dev/null 2>&1; then echo "$p"; return; fi
  done
  error "Could not find a free port in the random range."
  exit 1
}

validate_psk() { (( ${#1} >= 8 )); }

generate_psk() { tr -dc A-Za-z0-9 </dev/urandom | head -c "${DEFAULT_PSK_LEN}"; }

ensure_user() {
  if ! id "${DEFAULT_USER}" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin "${DEFAULT_USER}"
  elif [[ "$(id -u "${DEFAULT_USER}")" -ge 1000 ]]; then
    warn "A regular user named ${DEFAULT_USER} already exists; please verify it is safe to use."
  fi
}

download_and_install_binary() {
  local arch url tmpdir
  arch=$(detect_arch)
  url="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${arch}.zip"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  msg "Downloading Snell binary from: $url"
  wget -qO "${tmpdir}/snell-server.zip" "$url"
  unzip -oq "${tmpdir}/snell-server.zip" -d "$tmpdir"
  [[ -f "${tmpdir}/snell-server" ]] || { error "snell-server not found after unzip."; exit 1; }
  install -m 0755 "${tmpdir}/snell-server" "${DEFAULT_INSTALL_DIR}/snell-server"
  msg "Installed snell-server to ${DEFAULT_INSTALL_DIR}/snell-server"
}

write_config_and_service() {
  local final_port final_psk host_ip ip_country
  mkdir -p "${DEFAULT_CONF_DIR}"
  if [[ -n "${port:-}" ]]; then
    if ! validate_port "$port"; then error "Invalid port supplied: $port"; exit 1; fi
    final_port=$port
    if ss -ltn "sport = :$final_port" >/dev/null 2>&1; then error "Port $final_port is already in use."; exit 1; fi
  else
    final_port=$(pick_free_port)
  fi
  if [[ -n "${psk:-}" ]]; then
    if ! validate_psk "$psk"; then error "PSK is too short (minimum 8 characters)."; exit 1; fi
    final_psk=$psk
  else
    final_psk=$(generate_psk)
  fi
  cat > "${DEFAULT_CONF_DIR}/snell-server.conf" <<EOF
[snell-server]
listen = 0.0.0.0:${final_port},:::${final_port}
psk = ${final_psk}
ipv6 = true
EOF
  cat > "/etc/systemd/system/${DEFAULT_SERVICE}.service" <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=${DEFAULT_USER}
Group=${DEFAULT_USER}
ExecStart=${DEFAULT_INSTALL_DIR}/snell-server -c ${DEFAULT_CONF_DIR}/snell-server.conf
LimitNOFILE=32768
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${DEFAULT_SERVICE}.service"
  host_ip=$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$host_ip" ]]; then host_ip=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true); fi
  ip_country=""
  if [[ -n "$host_ip" ]]; then ip_country=$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true); fi
  cat > "${DEFAULT_CONF_DIR}/config.txt" <<EOF
${ip_country} = snell, ${host_ip}, ${final_port}, psk = ${final_psk}, version = 5, reuse = true, tfo = true
EOF
  msg "Snell configuration written to ${DEFAULT_CONF_DIR}/snell-server.conf"
  msg "Systemd service unit created at ${DEFAULT_SERVICE}.service"
  msg "Client configuration line (saved to ${DEFAULT_CONF_DIR}/config.txt):"
  cat "${DEFAULT_CONF_DIR}/config.txt"
}

install_snell() {
  msg ">>> Installing Snell <<<"
  wait_for_package_manager
  install_required_packages
  ensure_user
  download_and_install_binary
  write_config_and_service
  systemctl restart "${DEFAULT_SERVICE}.service"
  sleep 2
  systemctl --no-pager --full status "${DEFAULT_SERVICE}.service" || true
  msg "Snell installation completed!"
}

update_snell() {
  msg ">>> Updating Snell <<<"
  if [[ ! -x "${DEFAULT_INSTALL_DIR}/snell-server" ]]; then warn "Snell is not installed; cannot update."; exit 1; fi
  wait_for_package_manager
  install_required_packages
  download_and_install_binary
  systemctl restart "${DEFAULT_SERVICE}.service"
  sleep 2
  journalctl -u "${DEFAULT_SERVICE}.service" -n 8 --no-pager || true
  msg "Update finished."
}

uninstall_snell() {
  msg ">>> Uninstalling Snell <<<"
  systemctl stop "${DEFAULT_SERVICE}.service" 2>/dev/null || true
  systemctl disable "${DEFAULT_SERVICE}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${DEFAULT_SERVICE}.service"
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true
  rm -f "${DEFAULT_INSTALL_DIR}/snell-server"
  rm -rf "${DEFAULT_CONF_DIR}"
  msg "Snell has been completely removed."
}

show_config() {
  if [[ -f "${DEFAULT_CONF_DIR}/config.txt" ]]; then cat "${DEFAULT_CONF_DIR}/config.txt"
  else error "Config file not found: ${DEFAULT_CONF_DIR}/config.txt"; exit 1; fi
}

print_usage() {
  cat <<EOF
Snell Server management script

Usage:
  $0 [options] <action>

Actions (required):
  install        Install Snell and start the service
  update         Update an existing Snell installation
  uninstall      Remove Snell completely
  start          Start the service
  stop           Stop the service
  status         Show service status
  show-config    Print the client configuration line

Options:
  -v|--version <ver>   Snell version to install (default: ${DEFAULT_VERSION})
  -p|--port   <num>    Listening port (1‑65535)
  -k|--psk    <str>    Pre-shared key (minimum 8 characters)
  -h|--help            Show this help message

Example:
  $0 -p 443 -k MyStrongPsk install
EOF
}

VERSION="${DEFAULT_VERSION}"
port=""
psk=""
action=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|update|uninstall|start|stop|status|show-config) action=$1; shift ;;
    -v|--version) VERSION=$2; shift 2 ;;
    -p|--port) port=$2; shift 2 ;;
    -k|--psk|--key) psk=$2; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    *) error "Unknown parameter: $1"; print_usage; exit 1 ;;
  esac
done

if [[ -z "$action" ]]; then error "No action specified."; print_usage; exit 1; fi

case "$action" in
  install)   check_root; install_snell ;;
  update)    check_root; update_snell ;;
  uninstall) check_root; uninstall_snell ;;
  start)     check_root; systemctl start "${DEFAULT_SERVICE}.service" ;;
  stop)      check_root; systemctl stop "${DEFAULT_SERVICE}.service" ;;
  status)    systemctl --no-pager --full status "${DEFAULT_SERVICE}.service" ;;
  show-config) show_config ;;
  *) error "Invalid action: $action"; print_usage; exit 1 ;;
esac
