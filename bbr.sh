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

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root, for example: sudo bash $0" >&2
    exit 1
  fi
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

detect_iface() {
  if [[ -n "${IFACE}" ]]; then
    echo "${IFACE}"
    return
  fi
  local detected
  detected="$(ip route show default 2>/dev/null | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  if [[ -z "${detected}" ]]; then
    echo "Could not detect default network interface. Set IFACE=enp0s6 and rerun." >&2
    exit 1
  fi
  echo "${detected}"
}

detect_netplan_file() {
  if [[ -n "${NETPLAN_FILE}" ]]; then
    echo "${NETPLAN_FILE}"
    return
  fi
  local file
  file="$(find /etc/netplan -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort | head -n 1)"
  if [[ -z "${file}" ]]; then
    echo ""
    return
  fi
  echo "${file}"
}

detect_interfaces_file() {
  if [[ -n "${INTERFACES_FILE}" ]]; then
    echo "${INTERFACES_FILE}"
    return
  fi
  if [[ -f "/etc/network/interfaces" ]]; then
    echo "/etc/network/interfaces"
    return
  fi
  echo ""
}

backup_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    cp -a "${file}" "${file}.bak.singleflow.$(date +%Y%m%d%H%M%S)"
  fi
}

set_netplan_mtu() {
  local iface="$1"
  local file="$2"
  local mac=""
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "No netplan file found. Applying runtime MTU only." >&2
    ip link set dev "${iface}" mtu "${MTU}"
    return
  fi
  backup_file "${file}"
  if [[ -r "/sys/class/net/${iface}/address" ]]; then
    mac="$(tr '[:upper:]' '[:lower:]' < "/sys/class/net/${iface}/address")"
  fi
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
def indent_of(line):
    return len(line) - len(line.lstrip(" "))
def block_end(start, indent):
    end = len(lines)
    for i in range(start + 1, len(lines)):
        stripped = lines[i].strip()
        if not stripped or stripped.startswith("#"):
            continue
        if indent_of(lines[i]) <= indent:
            end = i
            break
    return end
ethernets_line = None
ethernets_indent = None
for i, line in enumerate(lines):
    if re.match(r"^\s*ethernets:\s*$", line):
        ethernets_line = i
        ethernets_indent = indent_of(line)
        break
if ethernets_line is None:
    raise SystemExit(f"No 'ethernets:' section was found in {path}")
ethernets_end = block_end(ethernets_line, ethernets_indent)
candidates = []
i = ethernets_line + 1
while i < ethernets_end:
    stripped = lines[i].strip()
    if not stripped or stripped.startswith("#"):
        i += 1
        continue
    indent = indent_of(lines[i])
    m = re.match(r"^\s*([^#\s][^:]*):\s*$", lines[i])
    if m and indent > ethernets_indent:
        key = m.group(1).strip().strip("'\"")
        end = block_end(i, indent)
        block = "\n".join(lines[i + 1:end])
        candidates.append((key, i, indent, end, block))
        i = end
        continue
    i += 1
if not candidates:
    raise SystemExit(f"No ethernet interface stanza was found in {path}")
def block_has_set_name(block, name):
    pat = r"(?m)^\s*set-name:\s*['\"]?" + re.escape(name) + r"['\"]?\s*$"
    return re.search(pat, block) is not None
def block_has_mac(block, mac):
    if not mac:
        return False
    for m in re.finditer(r"(?im)^\s*macaddress:\s*['\"]?([0-9a-f:.-]+)['\"]?\s*$", block):
        if m.group(1).lower() == mac:
            return True
    return False
chosen = None
for candidate in candidates:
    if candidate[0] == iface:
        chosen = candidate
        break
if chosen is None:
    for candidate in candidates:
        if block_has_set_name(candidate[4], iface):
            chosen = candidate
            break
if chosen is None:
    for candidate in candidates:
        if block_has_mac(candidate[4], runtime_mac):
            chosen = candidate
            break
if chosen is None and len(candidates) == 1:
    chosen = candidates[0]
if chosen is None:
    found = ", ".join(c[0] for c in candidates)
    raise SystemExit(
        f"Could not match runtime interface {iface!r} in {path}. "
        f"Found netplan stanzas: {found}."
    )
_, iface_line, iface_indent, end, _ = chosen
for i in range(iface_line + 1, len(lines)):
    stripped = lines[i].strip()
    if not stripped or stripped.startswith("#"):
        continue
    indent = indent_of(lines[i])
    if indent <= iface_indent:
        end = i
        break
mtu_idx = None
for i in range(iface_line + 1, end):
    if re.match(r"^\s*mtu:\s*", lines[i]):
        mtu_idx = i
        break
child_indent = None
for i in range(iface_line + 1, end):
    stripped = lines[i].strip()
    if stripped and not stripped.startswith("#"):
        indent = indent_of(lines[i])
        if indent > iface_indent:
            child_indent = indent
            break
if child_indent is None:
    child_indent = iface_indent + 2
new_line = " " * child_indent + f"mtu: {mtu}"
if mtu_idx is not None:
    lines[mtu_idx] = new_line
else:
    lines.insert(end, new_line)
path.write_text("\n".join(lines) + "\n")
PY
  chmod 600 "${file}" || true
}

set_interfaces_mtu() {
  local iface="$1"
  local file="$2"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "No interfaces file found. Applying runtime MTU only." >&2
    ip link set dev "${iface}" mtu "${MTU}"
    return
  fi
  backup_file "${file}"
  python3 - "$file" "$iface" "$MTU" <<'PY'
import sys
import re
import pathlib
path = pathlib.Path(sys.argv[1])
iface = sys.argv[2]
mtu = sys.argv[3]
text = path.read_text()
lines = text.splitlines()
target_idx = -1
for i, line in enumerate(lines):
    if re.match(r"^\s*iface\s+" + re.escape(iface) + r"\b", line):
        target_idx = i
        break
if target_idx == -1:
    lines.append("")
    lines.append(f"auto {iface}")
    lines.append(f"iface {iface} inet dhcp")
    lines.append(f"    mtu {mtu}")
else:
    mtu_idx = -1
    insert_idx = target_idx + 1
    for i in range(target_idx + 1, len(lines)):
        line_str = lines[i].strip()
        if not line_str:
            continue
        if re.match(r"^\s*(iface|auto|allow-|source|source-directory)\b", lines[i]):
            insert_idx = i
            break
        if re.match(r"^\s*mtu\b", lines[i]):
            mtu_idx = i
            break
    else:
        insert_idx = len(lines)
    if mtu_idx != -1:
        indent = len(lines[mtu_idx]) - len(lines[mtu_idx].lstrip())
        if indent == 0: indent = 4
        lines[mtu_idx] = " " * indent + f"mtu {mtu}"
    else:
        indent = 4
        if target_idx + 1 < len(lines) and lines[target_idx + 1].strip() and not re.match(r"^\s*(iface|auto|allow-|source)\b", lines[target_idx + 1]):
            indent = len(lines[target_idx + 1]) - len(lines[target_idx + 1].lstrip())
        lines.insert(insert_idx, " " * indent + f"mtu {mtu}")
path.write_text("\n".join(lines) + "\n")
PY
  ip link set dev "${iface}" mtu "${MTU}"
}

write_sysctl() {
  cat > "${SYSCTL_FILE}" <<EOF
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_wmem = 4096 16384 ${TCP_WMEM_MAX}
net.ipv4.tcp_rmem = 4096 131072 ${TCP_RMEM_MAX}
net.ipv4.tcp_limit_output_bytes = ${TCP_LIMIT_OUTPUT_BYTES}
EOF
  sysctl --system >/tmp/singleflow-sysctl.log
}

write_qdisc_service() {
  local iface="$1"
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Set fq qdisc quantum for single-flow throughput
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStartPre=-/usr/sbin/tc qdisc del dev ${iface} root
ExecStart=/usr/sbin/tc qdisc add dev ${iface} root fq quantum ${FQ_QUANTUM} initial_quantum ${FQ_INITIAL_QUANTUM}
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$(basename "${SERVICE_FILE}")" >/dev/null
  systemctl restart "$(basename "${SERVICE_FILE}")"
}

restart_network() {
  echo "Restarting network service..."
  if [[ -d "/etc/netplan" ]]; then
    netplan generate
    netplan apply
  else
    systemctl restart networking
  fi
  echo "Network service restarted."
}

show_status() {
  local iface="$1"
  local config_type="$2"
  local config_file="$3"
  echo
  echo "Applied single-flow tuning."
  echo
  echo "Interface:"
  ip link show dev "${iface}" | head -n 1
  echo
  echo "TCP sysctl:"
  sysctl net.ipv4.tcp_congestion_control \
         net.core.default_qdisc \
         net.ipv4.tcp_wmem \
         net.ipv4.tcp_rmem \
         net.ipv4.tcp_limit_output_bytes
  echo
  echo "qdisc:"
  tc qdisc show dev "${iface}"
  echo
  echo "systemd:"
  systemctl is-enabled "$(basename "${SERVICE_FILE}")"
  systemctl is-active "$(basename "${SERVICE_FILE}")"
  echo
  if [[ "${config_type}" != "none" ]]; then
    echo "Config Method: ${config_type}"
    echo "Config file: ${config_file}"
    echo "Backup files: ${config_file}.bak.singleflow.*"
  else
    echo "Config Method: Runtime Only"
  fi
  echo "Sysctl file: ${SYSCTL_FILE}"
  echo "Service file: ${SERVICE_FILE}"
}

main() {
  need_root
  need_cmd ip
  need_cmd tc
  need_cmd sysctl
  need_cmd systemctl
  need_cmd python3
  local iface
  local netplan_file
  local interfaces_file
  local config_type="none"
  local config_file=""
  iface="$(detect_iface)"
  netplan_file="$(detect_netplan_file)"
  interfaces_file="$(detect_interfaces_file)"
  if [[ ! -d "/sys/class/net/${iface}" ]]; then
    echo "Interface does not exist: ${iface}" >&2
    exit 1
  fi
  if [[ -n "${netplan_file}" ]]; then
    config_type="netplan"
    config_file="${netplan_file}"
  elif [[ -n "${interfaces_file}" ]]; then
    config_type="interfaces"
    config_file="${interfaces_file}"
  fi
  echo "Interface: ${iface}"
  echo "MTU: ${MTU}"
  echo "fq quantum: ${FQ_QUANTUM}"
  echo "fq initial_quantum: ${FQ_INITIAL_QUANTUM}"
  echo "tcp_wmem max: ${TCP_WMEM_MAX}"
  echo "tcp_rmem max: ${TCP_RMEM_MAX}"
  echo "tcp_limit_output_bytes: ${TCP_LIMIT_OUTPUT_BYTES}"
  echo "Detected Config Type: ${config_type}"
  if [[ "${config_type}" == "netplan" ]]; then
    set_netplan_mtu "${iface}" "${netplan_file}"
  elif [[ "${config_type}" == "interfaces" ]]; then
    set_interfaces_mtu "${iface}" "${interfaces_file}"
  else
    echo "Applying runtime MTU only..."
    ip link set dev "${iface}" mtu "${MTU}"
  fi
  write_sysctl
  write_qdisc_service "${iface}"
  restart_network
  show_status "${iface}" "${config_type}" "${config_file}"
}

main "$@"
