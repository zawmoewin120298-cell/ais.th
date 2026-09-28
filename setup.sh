#!/bin/bash

# =============================================
# V2Ray VPN Server - Installation Script
# For Ubuntu/Debian VPS
# =============================================

set -e

echo "=========================================="
echo "  V2Ray VPN Server - Installation"
echo "=========================================="

# Root Check
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (sudo bash install.sh)"
    exit 1
fi

# =============================================
# 1. System Update
# =============================================
echo "[1/8] Updating system..."
apt-get update -y
apt-get upgrade -y

# =============================================
# 2. Install Dependencies
# =============================================
echo "[2/8] Installing dependencies..."
apt-get install -y \
    curl wget unzip openssl ca-certificates \
    iptables iproute2 net-tools procps \
    dnsutils jq

# =============================================
# 3. Install OpenResty
# =============================================
echo "[3/8] Installing OpenResty..."
wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
echo "deb http://openresty.org/package/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list
apt-get update -y
apt-get install -y openresty

# =============================================
# 4. Install Xray
# =============================================
echo "[4/8] Installing Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# =============================================
# 5. Install Cloudflared
# =============================================
echo "[5/8] Installing Cloudflared..."
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# =============================================
# 6. Install Hysteria2
# =============================================
echo "[6/8] Installing Hysteria2..."
curl -L https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 \
    -o /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria

# =============================================
# 7. Install dnstt
# =============================================
echo "[7/8] Installing dnstt..."
curl -L https://dnstt.network/dnstt-server-linux-amd64 \
    -o /usr/local/bin/dnstt-server
chmod +x /usr/local/bin/dnstt-server

# =============================================
# 8. Create Directories
# =============================================
echo "[8/8] Creating directories..."
mkdir -p /etc/xray /etc/dnstt /app /cache
mkdir -p /usr/local/openresty/nginx/html

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Copy your config files to /etc/xray/config.json"
echo "  2. Run: bash start.sh"
echo ""
