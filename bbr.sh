#!/usr/bin/env bash
set -Eeuo pipefail

MTU="${MTU:-1500}"
FQ_QUANTUM="${FQ_QUANTUM:-18028}"
FQ_INITIAL_QUANTUM="${FQ_INITIAL_QUANTUM:-90140}"
TCP_WMEM_MAX="${TCP_WMEM_MAX:-33554432}"
TCP_RMEM_MAX="${TCP_RMEM_MAX:-33554432}"
TCP_LIMIT_OUTPUT_BYTES="${TCP_LIMIT_OUTPUT_BYTES:-4194304}"
SYSCTL_FILE="${SYSCTL_FILE:-/etc/sysctl.d/99-singleflow-tcp-optimization.conf}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/singleflow-fq-quantum.service}"
NETPLAN_FILE="${NETPLAN_FILE:-}"
INTERFACES_FILE="${INTERFACES_FILE:-}"
IFACE="${IFACE:-}"

QDISC_SERVICE_NAME="singleflow-fq-quantum"
INIT_SYSTEM=""
APT_UPDATED=false

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "错误：请使用 root 权限运行此脚本。" >&2
    exit 1
  fi
}

detect_init() {
  if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
  elif command -v rc-update >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
  else
    INIT_SYSTEM="unknown"
  fi
}

resolve_and_install() {
  local cmd="$1"
  local pm=""

  if command -v apt-get >/dev/null 2>&1; then pm="apt"
  elif command -v dnf >/dev/null 2>&1; then pm="dnf"
  elif command -v yum >/dev/null 2>&1; then pm="yum"
  elif command -v pacman >/dev/null 2>&1; then pm="pacman"
  elif command -v apk >/dev/null 2>&1; then pm="apk"
  fi

  if [[ -z "$pm" ]]; then
    echo "错误：未检测到支持的包管理器，无法自动安装 ${cmd}。" >&2
    exit 1
  fi

  local pkg=""
  case "$cmd" in
    ip|tc) pkg="iproute2" ;;
    sysctl)
      if [[ "$pm" == "apk" ]]; then pkg="busybox"
      elif [[ "$pm" == "apt" ]]; then pkg="procps"
      else pkg="procps-ng"; fi ;;
    systemctl)
      if [[ "$pm" == "apk" ]]; then
        echo "检测到 Alpine 系统，使用 OpenRC。"
        return 0
      else
        pkg="systemd"
      fi ;;
    python3) pkg="python3" ;;
    *) pkg="$cmd" ;;
  esac

  echo "正在安装依赖: ${cmd} ..."

  case "$pm" in
    apt)
      if [[ "$APT_UPDATED" = false ]]; then
        apt-get update -qy || true
        APT_UPDATED=true
      fi
      apt-get install -y "${pkg}" ;;
    dnf) dnf install -y "${pkg}" ;;
    yum)
      if [[ "$cmd" == "tc" ]]; then
        yum install -y iproute-tc || yum install -y iproute
      else
        yum install -y "${pkg}"
      fi ;;
    pacman) pacman -Sy --noconfirm "${pkg}" ;;
    apk) apk add --no-cache "${pkg}" ;;
  esac

  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ "$cmd" == "systemctl" && "$pm" == "apk" ]]; then return 0; fi
    echo "错误：自动安装 ${cmd} 失败，请手动安装。" >&2
    exit 1
  fi
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    resolve_and_install "$1"
  fi
}

detect_iface() {
  if [[ -n "${IFACE}" ]]; then echo "${IFACE}"; return; fi
  local detected
  detected="$(ip route show default 2>/dev/null | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  if [[ -z "${detected}" ]]; then
    echo "错误：无法检测默认网络接口。请设置 IFACE=xxx" >&2
    exit 1
  fi
  echo "${detected}"
}

detect_netplan_file() {
  if [[ -n "${NETPLAN_FILE}" ]]; then echo "${NETPLAN_FILE}"; return; fi
  local file
  file="$(find /etc/netplan -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort | head -n 1)"
  echo "${file:-}"
}

detect_interfaces_file() {
  if [[ -n "${INTERFACES_FILE}" ]]; then echo "${INTERFACES_FILE}"; return; fi
  [[ -f "/etc/network/interfaces" ]] && echo "/etc/network/interfaces" || echo ""
}

backup_file() {
  local file="$1"
  [[ -f "${file}" ]] && cp -a "${file}" "${file}.bak.singleflow.$(date +%Y%m%d%H%M%S)"
}

set_netplan_mtu() {
  local iface="$1" file="$2" mac=""
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "未找到 netplan 文件。仅应用运行时 MTU。"
    ip link set dev "${iface}" mtu "${MTU}" 2>/dev/null || true
    return
  fi
  backup_file "${file}"
  [[ -r "/sys/class/net/${iface}/address" ]] && mac="$(tr '[:upper:]' '[:lower:]' < "/sys/class/net/${iface}/address")"

  python3 - "$file" "$iface" "$MTU" "$mac" <<'PY'
import pathlib
import re
import sys
path = pathlib.Path(sys.argv[1])
iface = sys.argv[2]
mtu = sys.argv[3]
runtime_mac = sys.argv[4].lower()
text = path.read_text()
lines = text.splitlines()
def indent_of(line): return len(line) - len(line.lstrip(" "))
def block_end(start, indent):
    end = len(lines)
    for i in range(start + 1, len(lines)):
        stripped = lines[i].strip()
        if not stripped or stripped.startswith("#"): continue
        if indent_of(lines[i]) <= indent: end = i; break
    return end

ethernets_line = None
for i, line in enumerate(lines):
    if re.match(r"^\s*ethernets:\s*$", line):
        ethernets_line = i; break
if ethernets_line is None: raise SystemExit("未找到 ethernets:")

ethernets_end = block_end(ethernets_line, indent_of(lines[ethernets_line]))
candidates = []
i = ethernets_line + 1
while i < ethernets_end:
    stripped = lines[i].strip()
    if not stripped or stripped.startswith("#"): i += 1; continue
    indent = indent_of(lines[i])
    m = re.match(r"^\s*([^#\s][^:]*):\s*$", lines[i])
    if m and indent > indent_of(lines[ethernets_line]):
        key = m.group(1).strip().strip("'\"")
        end = block_end(i, indent)
        block = "\n".join(lines[i+1:end])
        candidates.append((key, i, indent, end, block))
        i = end; continue
    i += 1

if not candidates: raise SystemExit("未找到以太网接口配置")

def block_has_set_name(block, name):
    return re.search(r"(?m)^\s*set-name:\s*['\"]?" + re.escape(name) + r"['\"]?\s*$", block) is not None

def block_has_mac(block, mac):
    if not mac: return False
    for m in re.finditer(r"(?im)^\s*macaddress:\s*['\"]?([0-9a-f:.-]+)['\"]?\s*$", block):
        if m.group(1).lower() == mac: return True
    return False

chosen = None
for c in candidates:
    if c[0] == iface: chosen = c; break
if chosen is None:
    for c in candidates:
        if block_has_set_name(c[4], iface): chosen = c; break
if chosen is None:
    for c in candidates:
        if block_has_mac(c[4], runtime_mac): chosen = c; break
if chosen is None and len(candidates) == 1:
    chosen = candidates[0]
if chosen is None:
    raise SystemExit("无法匹配运行时接口")

_, iface_line, iface_indent, end, _ = chosen
for i in range(iface_line + 1, len(lines)):
    if lines[i].strip() and not lines[i].strip().startswith("#") and indent_of(lines[i]) <= iface_indent:
        end = i; break

mtu_idx = None
for i in range(iface_line + 1, end):
    if re.match(r"^\s*mtu:\s*", lines[i]): mtu_idx = i; break

child_indent = iface_indent + 2
for i in range(iface_line + 1, end):
    if lines[i].strip() and not lines[i].strip().startswith("#"):
        child_indent = indent_of(lines[i]); break

new_line = " " * child_indent + f"mtu: {mtu}"
if mtu_idx is not None:
    lines[mtu_idx] = new_line
else:
    lines.insert(end, new_line)

path.write_text("\n".join(lines) + "\n")
PY
  chmod 600 "${file}" || true
  netplan generate 2>/dev/null || true
  netplan apply 2>/dev/null || true
}

set_interfaces_mtu() {
  local iface="$1" file="$2"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    ip link set dev "${iface}" mtu "${MTU}" 2>/dev/null || true
    return
  fi
  backup_file "${file}"

  python3 - "$file" "$iface" "$MTU" <<'PY'
import sys, re, pathlib
path = pathlib.Path(sys.argv[1])
iface, mtu = sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines()
target_idx = -1
for i, line in enumerate(lines):
    if re.match(r"^\s*iface\s+" + re.escape(iface) + r"\b", line):
        target_idx = i; break
if target_idx == -1:
    lines += ["", f"auto {iface}", f"iface {iface} inet dhcp", f"    mtu {mtu}"]
else:
    mtu_idx = -1
    insert_idx = target_idx + 1
    for i in range(target_idx + 1, len(lines)):
        if re.match(r"^\s*mtu\b", lines[i]): mtu_idx = i; break
        if re.match(r"^\s*(iface|auto|allow-)\b", lines[i]): insert_idx = i; break
    if mtu_idx != -1:
        indent = len(lines[mtu_idx]) - len(lines[mtu_idx].lstrip()) or 4
        lines[mtu_idx] = " " * indent + f"mtu {mtu}"
    else:
        indent = 4
        if target_idx + 1 < len(lines) and lines[target_idx+1].strip():
            indent = len(lines[target_idx+1]) - len(lines[target_idx+1].lstrip())
        lines.insert(insert_idx, " " * indent + f"mtu {mtu}")
path.write_text("\n".join(lines) + "\n")
PY
  ip link set dev "${iface}" mtu "${MTU}" 2>/dev/null || true
}

write_sysctl() {
  cat > "${SYSCTL_FILE}" <<EOF
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_wmem = 4096 16384 ${TCP_WMEM_MAX}
net.ipv4.tcp_rmem = 4096 131072 ${TCP_RMEM_MAX}
net.ipv4.tcp_limit_output_bytes = ${TCP_LIMIT_OUTPUT_BYTES}
EOF
  sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1 || {
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
    sysctl -w net.ipv4.tcp_wmem="4096 16384 ${TCP_WMEM_MAX}" 2>/dev/null || true
    sysctl -w net.ipv4.tcp_rmem="4096 131072 ${TCP_RMEM_MAX}" 2>/dev/null || true
    sysctl -w net.ipv4.tcp_limit_output_bytes=${TCP_LIMIT_OUTPUT_BYTES} 2>/dev/null || true
  }
}

write_qdisc_service() {
  local iface="$1"
  detect_init

  if [[ "${INIT_SYSTEM}" == "systemd" ]]; then
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Set fq qdisc quantum for single-flow throughput
After=network-online.target

[Service]
Type=oneshot
ExecStartPre=-/usr/sbin/tc qdisc del dev ${iface} root
ExecStart=/usr/sbin/tc qdisc add dev ${iface} root fq quantum ${FQ_QUANTUM} initial_quantum ${FQ_INITIAL_QUANTUM}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$(basename "${SERVICE_FILE}")" >/dev/null 2>&1 || true
  elif [[ "${INIT_SYSTEM}" == "openrc" ]]; then
    local openrc_file="/etc/init.d/${QDISC_SERVICE_NAME}"
    cat > "${openrc_file}" <<'EOC'
#!/sbin/openrc-run
depend() { after net; }
start() {
    ebegin "Applying fq qdisc quantum"
    /sbin/tc qdisc del dev $IFACE root 2>/dev/null || true
    /sbin/tc qdisc add dev $IFACE root fq quantum $FQ_QUANTUM initial_quantum $FQ_INITIAL_QUANTUM
    eend $?
}
stop() {
    ebegin "Removing qdisc"
    /sbin/tc qdisc del dev $IFACE root 2>/dev/null || true
    eend 0
}
EOC
    sed -i "s/\$IFACE/${iface}/g" "${openrc_file}"
    sed -i "s/\$FQ_QUANTUM/${FQ_QUANTUM}/g" "${openrc_file}"
    sed -i "s/\$FQ_INITIAL_QUANTUM/${FQ_INITIAL_QUANTUM}/g" "${openrc_file}"
    chmod +x "${openrc_file}"
    rc-update add "${QDISC_SERVICE_NAME}" default 2>/dev/null || true
    if rc-service "${QDISC_SERVICE_NAME}" status >/dev/null 2>&1; then
      rc-service "${QDISC_SERVICE_NAME}" restart >/dev/null 2>&1 || true
    else
      rc-service "${QDISC_SERVICE_NAME}" start >/dev/null 2>&1 || true
    fi
  else
    tc qdisc del dev "${iface}" root 2>/dev/null || true
    tc qdisc add dev "${iface}" root fq quantum "${FQ_QUANTUM}" initial_quantum "${FQ_INITIAL_QUANTUM}"
  fi
}

restart_network() {
  if [[ -d "/etc/netplan" ]]; then
    netplan apply 2>/dev/null || true
  elif [[ "${INIT_SYSTEM}" != "openrc" ]]; then
    systemctl restart networking 2>/dev/null || true
  fi
}

show_status() {
  local iface="$1"
  echo
  echo "========== BBR优化应用成功 =========="
  echo "接口: ${iface}"
  echo "MTU: ${MTU}"
  echo "拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
  echo "队列规则:"
  tc qdisc show dev "${iface}"
  echo "========================================"
  echo
}

check_current_status() {
  need_root
  local iface
  iface="$(detect_iface)"
  echo
  echo "========== 当前网络状态 =========="
  echo "网络接口: ${iface}"
  echo "MTU: $(ip link show dev "${iface}" | grep -o 'mtu [0-9]*' | awk '{print $2}' || echo '未设置')"
  echo "TCP 拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
  echo "TCP 写缓冲: $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo '未知')"
  echo "TCP 读缓冲: $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo '未知')"
  echo
  echo "队列规则:"
  tc qdisc show dev "${iface}"
  echo "======================================"
  echo
}

install_optimization() {
  need_root
  need_cmd ip
  need_cmd tc
  need_cmd sysctl
  need_cmd python3
  detect_init

  local iface netplan_file interfaces_file
  iface="$(detect_iface)"
  netplan_file="$(detect_netplan_file)"
  interfaces_file="$(detect_interfaces_file)"

  echo
  echo "========== 优化配置参数 =========="
  echo "接口: ${iface}  Init: ${INIT_SYSTEM}"
  echo "=================================="

  if [[ -n "${netplan_file}" ]]; then
    set_netplan_mtu "${iface}" "${netplan_file}"
  elif [[ -n "${interfaces_file}" ]]; then
    set_interfaces_mtu "${iface}" "${interfaces_file}"
  else
    ip link set dev "${iface}" mtu "${MTU}" 2>/dev/null || true
  fi

  write_sysctl
  write_qdisc_service "${iface}"

  if [[ "${INIT_SYSTEM}" != "openrc" ]]; then
    restart_network
  fi

  show_status "${iface}"
}

uninstall_optimization() {
  need_root
  local iface netplan_file interfaces_file
  iface="$(detect_iface)"
  netplan_file="$(detect_netplan_file)"
  interfaces_file="$(detect_interfaces_file)"
  detect_init

  if [[ "${INIT_SYSTEM}" == "systemd" && -f "${SERVICE_FILE}" ]]; then
    systemctl disable --now "$(basename "${SERVICE_FILE}")" 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
  elif [[ "${INIT_SYSTEM}" == "openrc" ]]; then
    local f="/etc/init.d/${QDISC_SERVICE_NAME}"
    if [[ -f "$f" ]]; then
      rc-service "${QDISC_SERVICE_NAME}" stop 2>/dev/null || true
      rc-update del "${QDISC_SERVICE_NAME}" default 2>/dev/null || true
      rm -f "$f"
    fi
  fi

  tc qdisc del dev "${iface}" root 2>/dev/null || true

  if [[ -f "${SYSCTL_FILE}" ]]; then
    rm -f "${SYSCTL_FILE}"
    sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null || true
  fi

  for cf in "$netplan_file" "$interfaces_file"; do
    if [[ -n "$cf" ]]; then
      local bk
      bk="$(find "$(dirname "$cf")" -maxdepth 1 -name "$(basename "$cf").bak.singleflow.*" 2>/dev/null | sort | tail -n1)"
      [[ -f "$bk" ]] && cp -pf "$bk" "$cf"
    fi
  done

  ip link set dev "${iface}" mtu 1500 2>/dev/null || true
  echo "卸载完成"
}

show_menu() {
  echo
  echo "╔═══════════════════════════════════╗"
  echo "            BBR性能优化工具           "
  echo "╚═══════════════════════════════════╝"
  echo "  1. 安装应用优化"
  echo "  2. 卸载并还原"
  echo "  3. 查看当前状态"
  echo "  4. 退出"
}

main() {
  while true; do
    show_menu
    read -p "请输入序号 [1-4]: " choice
    case $choice in
      1) install_optimization ;;
      2) uninstall_optimization ;;
      3) check_current_status ;;
      4) echo "退出"; exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

main "$@"
