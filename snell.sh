#!/usr/bin/env bash
# ------------------------------------------------------------
# Snell Server 安装/管理脚本（改进版）
# 支持：Debian/Ubuntu、CentOS/RHEL、Alpine
# 功能：install / update / uninstall / start / stop / status / show-config
# ------------------------------------------------------------
set -euo pipefail

# ==========================
#   常量 & 默认配置
# ==========================
DEFAULT_VERSION="v5.0.1"
DEFAULT_USER="snell"
DEFAULT_SERVICE="snell"
DEFAULT_INSTALL_DIR="/usr/local/bin"
DEFAULT_CONF_DIR="/etc/snell"
DEFAULT_PORT_RANGE_START=30000
DEFAULT_PORT_RANGE_END=65000
DEFAULT_PSK_LEN=20

# 颜色（如果输出不是终端则不使用颜色）
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

# ==========================
#   辅助函数
# ==========================
msg()    { printf "${GREEN}%s${RESET}\n" "$*"; }
warn()   { printf "${YELLOW}%s${RESET}\n" "$*"; }
error()  { printf "${RED}%s${RESET}\n" "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null || { error "缺少必备命令: $1"; exit 1; }
}

check_root() {
  [[ "$(id -u)" -eq 0 ]] || { error "请以 root 身份运行此脚本。"; exit 1; }
}

get_system_type() {
  if [[ -f /etc/debian_version ]]; then echo "debian";
  elif [[ -f /etc/redhat-release ]]; then echo "centos";
  elif [[ -f /etc/alpine-release ]]; then echo "alpine";
  else echo "unknown"; fi
}

wait_for_package_manager() {
  local sys
  sys=$(get_system_type)
  case "$sys" in
    debian)
      while fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
        || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
        || fuser /var/lib/apt/lists/lock-frontend >/dev/null 2>&1 \
        || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        warn "检测到其他 apt 进程正在运行，等待中..."
        sleep 1
      done
      ;;
    centos)
      while fuser /var/run/rpm.lock >/dev/null 2>&1; do
        warn "检测到其他 yum/dnf 进程正在运行，等待中..."
        sleep 1
      done
      ;;
    alpine) ;;   # apk 没有锁文件
    *) error "未知系统类型，无法等待包管理器"; exit 1 ;;
  esac
}

install_required_packages() {
  local sys
  sys=$(get_system_type)
  msg "安装必要的软件包..."
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
    *) error "不支持的系统类型"; exit 1 ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    aarch64|arm64) echo "aarch64" ;;
    x86_64|amd64)   echo "amd64" ;;
    *) error "不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
  esac
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

pick_free_port() {
  local p
  for _ in {1..10}; do
    p=$(shuf -i "${DEFAULT_PORT_RANGE_START}-${DEFAULT_PORT_RANGE_END}" -n 1)
    # 检查是否被占用
    if ! ss -ltn "sport = :$p" >/dev/null 2>&1; then
      echo "$p"
      return
    fi
  done
  error "无法在随机范围内找到空闲端口"
  exit 1
}

validate_psk() {
  (( ${#1} >= 8 ))
}

generate_psk() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c "${DEFAULT_PSK_LEN}"
}

ensure_user() {
  if ! id "${DEFAULT_USER}" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin "${DEFAULT_USER}"
  elif [[ "$(id -u "${DEFAULT_USER}")" -ge 1000 ]]; then
    warn "已存在同名普通用户 ${DEFAULT_USER}，请自行确认其是否可用。"
  fi
}

download_and_install_binary() {
  local arch url tmpdir
  arch=$(detect_arch)
  url="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${arch}.zip"

  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  msg "下载 Snell 二进制文件: $url"
  wget -qO "${tmpdir}/snell-server.zip" "$url"

  # ----- 可选的 SHA256 校验（若官方提供 .sha256 文件） -----
  # wget -qO "${tmpdir}/snell-server.zip.sha256" "${url}.sha256"
  # (cd "$tmpdir" && sha256sum -c snell-server.zip.sha256)

  unzip -oq "${tmpdir}/snell-server.zip" -d "$tmpdir"
  [[ -f "${tmpdir}/snell-server" ]] || { error "解压后未找到 snell-server 可执行文件"; exit 1; }

  install -m 0755 "${tmpdir}/snell-server" "${DEFAULT_INSTALL_DIR}/snell-server"
  msg "已将 snell-server 安装至 ${DEFAULT_INSTALL_DIR}/snell-server"
}

write_config_and_service() {
  local final_port final_psk host_ip ip_country

  mkdir -p "${DEFAULT_CONF_DIR}"

  # ----- 端口 -----
  if [[ -n "${port:-}" ]]; then
    if ! validate_port "$port"; then
      error "提供的端口非法: $port"
      exit 1
    fi
    final_port=$port
    if ss -ltn "sport = :$final_port" >/dev/null 2>&1; then
      error "端口 $final_port 已被占用"
      exit 1
    fi
  else
    final_port=$(pick_free_port)
  fi

  # ----- PSK -----
  if [[ -n "${psk:-}" ]]; then
    if ! validate_psk "$psk"; then
      error "PSK 太短（至少 8 位）"
      exit 1
    fi
    final_psk=$psk
  else
    final_psk=$(generate_psk)
  fi

  # ----- Snell 配置文件 -----
  cat > "${DEFAULT_CONF_DIR}/snell-server.conf" <<EOF
[snell-server]
listen = 0.0.0.0:${final_port},:::${final_port}
psk = ${final_psk}
ipv6 = true
EOF

  # ----- systemd service -----
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

  # ----- 为客户端生成一行可直接复制的配置 -----
  host_ip=$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$host_ip" ]]; then
    host_ip=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
  fi

  ip_country=""
  if [[ -n "$host_ip" ]]; then
    ip_country=$(curl -fsSL --max-time 5 "https://ipinfo.io/${host_ip}/country" 2>/dev/null | tr -d '[:space:]' || true)
  fi

  cat > "${DEFAULT_CONF_DIR}/config.txt" <<EOF
${ip_country} = snell, ${host_ip}, ${final_port}, psk = ${final_psk}, version = 5, reuse = true, tfo = true
EOF

  msg "Snell 配置文件已写入 ${DEFAULT_CONF_DIR}/snell-server.conf"
  msg "Systemd 服务已创建 ${DEFAULT_SERVICE}.service"
  msg "客户端使用的配置行如下（已保存至 ${DEFAULT_CONF_DIR}/config.txt）："
  cat "${DEFAULT_CONF_DIR}/config.txt"
}

install_snell() {
  msg ">>> 开始安装 Snell <<<"
  wait_for_package_manager
  install_required_packages
  ensure_user
  download_and_install_binary
  write_config_and_service
  systemctl restart "${DEFAULT_SERVICE}.service"
  sleep 2
  systemctl --no-pager --full status "${DEFAULT_SERVICE}.service" || true
  msg "Snell 安装完成！"
}

update_snell() {
  msg ">>> 更新 Snell <<<"
  if [[ ! -x "${DEFAULT_INSTALL_DIR}/snell-server" ]]; then
    warn "Snell 尚未安装，无法执行更新."
    exit 1
  fi
  wait_for_package_manager
  install_required_packages
  download_and_install_binary
  systemctl restart "${DEFAULT_SERVICE}.service"
  sleep 2
  journalctl -u "${DEFAULT_SERVICE}.service" -n 8 --no-pager || true
  msg "更新完成"
}

uninstall_snell() {
  msg ">>> 卸载 Snell <<<"
  systemctl stop "${DEFAULT_SERVICE}.service" 2>/dev/null || true
  systemctl disable "${DEFAULT_SERVICE}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${DEFAULT_SERVICE}.service"
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true
  rm -f "${DEFAULT_INSTALL_DIR}/snell-server"
  rm -rf "${DEFAULT_CONF_DIR}"
  msg "Snell 已彻底移除"
}

show_config() {
  if [[ -f "${DEFAULT_CONF_DIR}/config.txt" ]]; then
    cat "${DEFAULT_CONF_DIR}/config.txt"
  else
    error "配置文件不存在：${DEFAULT_CONF_DIR}/config.txt"
    exit 1
  fi
}

print_usage() {
  cat <<EOF
Snell Server 管理脚本

用法：
  $0 [选项] <动作>

动作（必选）：
  install        安装 Snell 并启动服务
  update         更新已安装的 Snell
  uninstall      完全卸载 Snell
  start          启动服务
  stop           停止服务
  status         查看服务状态
  show-config    输出可直接复制的客户端配置行

选项：
  -v|--version <ver>   指定 Snell 版本（默认: ${DEFAULT_VERSION})
  -p|--port   <num>    手动指定监听端口 (1‑65535)
  -k|--psk    <str>    手动指定 PSK（至少 8 位）
  -h|--help            显示本帮助信息

示例：
  $0 -p 443 -k MyStrongPsk install
EOF
}

# ==========================
#   参数解析
# ==========================
VERSION="${DEFAULT_VERSION}"
port=""
psk=""
action=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|update|uninstall|start|stop|status|show-config)
      action=$1
      shift
      ;;
    -v|--version)
      VERSION=$2
      shift 2
      ;;
    -p|--port)
      port=$2
      shift 2
      ;;
    -k|--psk|--key)
      psk=$2
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      error "未知参数: $1"
      print_usage
      exit 1
      ;;
  esac
done

if [[ -z "$action" ]]; then
  error "未指定动作 (install|update|... )"
  print_usage
  exit 1
fi

# ==========================
#   主入口分发
# ==========================
case "$action" in
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
    systemctl start "${DEFAULT_SERVICE}.service"
    ;;
  stop)
    check_root
    systemctl stop "${DEFAULT_SERVICE}.service"
    ;;
  status)
    systemctl --no-pager --full status "${DEFAULT_SERVICE}.service"
    ;;
  show-config)
    show_config
    ;;
  *)
    error "无效的动作: $action"
    print_usage
    exit 1
    ;;
esac
