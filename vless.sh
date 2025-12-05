#!/bin/bash
set -e

# -------- 配置区 --------
ARGO_TOKEN="eyJhIjoiNWZiZDJjZjBmMGNiYzI5ZjdjMzc3YjI2OWIzZWJmMDAiLCJ0IjoiYzYwNGRkN2ItODZhNC00YmY1LWFiODktNzk4ZTMzMTYyNjdiIiwicyI6IllqSTVNekU0TVRZdE5qaGtOeTAwTnpBNUxXSXdaR010TkRaa09HRmxNbVF6TXpBMyJ9"      # 请替换为你的Token，带引号
ARGO_DOMAIN="sg.didi.nyc.mn"                           # 请替换为你的绑定域名，带引号
UUID="8c3f2083-62e8-56ad-fe13-872a266a8ed8"              # 你提供的UUID
XRAY_PORT=8080                                            # Xray监听端口，保持默认或自定义
WS_PATH="/vless"                                          # WebSocket路径，客户端须保持一致
XCONFIG_PATH="$HOME/xray_config.json"
CLOUDFLARED_PATH="$HOME/cloudflared"
CF_TUNNEL_SERVICE="/etc/systemd/system/argo.service"

# -------- 安装依赖 --------
apt update
apt install -y curl wget jq socat

# -------- 安装Xray --------
echo "安装Xray..."
bash -c "$(curl -L https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)" @latest

# -------- 生成Xray配置 --------
cat > "$XCONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WS_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# -------- 配置Xray服务 --------
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/xray run -c $XCONFIG_PATH
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "Xray已启动，监听本地端口 $XRAY_PORT"

# -------- 安装cloudflared --------
if ! command -v cloudflared &>/dev/null; then
    wget -O "$CLOUDFLARED_PATH" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    chmod +x "$CLOUDFLARED_PATH"
else
    CLOUDFLARED_PATH=$(command -v cloudflared)
fi

# -------- 配置Argo固定隧道服务 --------
cat > "$CF_TUNNEL_SERVICE" <<EOF
[Unit]
Description=Cloudflare Argo Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$CLOUDFLARED_PATH tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "$ARGO_TOKEN"
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable argo
systemctl restart argo

sleep 8

ARGO_STATUS=$(systemctl is-active argo)
if [ "$ARGO_STATUS" != "active" ]; then
  echo "Cloudflared Argo服务启动失败，请检查token和网络"
  journalctl -u argo -n 50 --no-pager
  exit 1
fi

echo ""
echo "================= VLESS+WS+TLS+Argo固定隧道部署完成 ================="
echo "域名（host）：$ARGO_DOMAIN"
echo "端口：443"
echo "UUID：$UUID"
echo "传输协议：ws"
echo "路径：$WS_PATH"
echo "TLS：开启"
echo ""
echo "客户端连接示例URL："
echo "vless://$UUID@$ARGO_DOMAIN:443?type=ws&security=tls&host=$ARGO_DOMAIN&path=$WS_PATH#VLESS-WS-TLS-Argo"
echo ""