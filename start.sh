#!/bin/bash

# =============================================
# V2Ray VPN Server - Startup Script
# =============================================

# =============================================
# Environment Variables (ကိုယ်တိုင် ပြောင်းပါ)
# =============================================
export TUNNEL_TOKEN="သင့်_Cloudflare_Tunnel_Token"
export SECRET_KEY="သင့်_Playit_Secret"
export DOMAIN="mydomain.com"
export DNSTT_DOMAIN="t.mydomain.com"
export VPS_MODE="true"

# =============================================
# Network Optimization
# =============================================
echo "[Init] Optimizing network..."
sysctl -w net.core.somaxconn=65535
sysctl -w net.core.netdev_max_backlog=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.ipv4.tcp_syncookies=1
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=30
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl -w net.core.default_qdisc=fq

# =============================================
# Stop Existing Services
# =============================================
echo "[Init] Stopping existing services..."
pkill -f xray 2>/dev/null || true
pkill -f cloudflared 2>/dev/null || true
pkill -f hysteria 2>/dev/null || true
pkill -f dnstt-server 2>/dev/null || true
pkill -f openresty 2>/dev/null || true
sleep 2

# =============================================
# Start Xray
# =============================================
echo "[1/5] Starting Xray..."
/usr/local/bin/xray -config /etc/xray/config.json > /var/log/xray.log 2>&1 &
XRAY_PID=$!
sleep 2

if ! kill -0 $XRAY_PID 2>/dev/null; then
    echo "❌ Xray failed to start. Check /var/log/xray.log"
    exit 1
fi
echo "✅ Xray started (PID: $XRAY_PID)"

# =============================================
# Start Cloudflared
# =============================================
if [ -n "$TUNNEL_TOKEN" ]; then
    echo "[2/5] Starting Cloudflared..."
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol quic run \
        --token ${TUNNEL_TOKEN} > /var/log/cloudflared.log 2>&1 &
    sleep 3
    echo "✅ Cloudflared started"
fi

# =============================================
# Start Hysteria2
# =============================================
if [ "$VPS_MODE" = "true" ] && [ -f /app/hysteria.yaml ]; then
    echo "[3/5] Starting Hysteria2..."
    /usr/local/bin/hysteria server -c /app/hysteria.yaml > /var/log/hysteria.log 2>&1 &
    sleep 2
    echo "✅ Hysteria2 started"
fi

# =============================================
# Start dnstt
# =============================================
if [ "$VPS_MODE" = "true" ] && [ -f /etc/dnstt/server.key ] && [ -n "$DNSTT_DOMAIN" ]; then
    echo "[4/5] Starting dnstt..."
    /usr/local/bin/dnstt-server \
        -udp :53 \
        -privkey-file /etc/dnstt/server.key \
        -domain ${DNSTT_DOMAIN} \
        127.0.0.1:8000 > /var/log/dnstt.log 2>&1 &
    sleep 2
    echo "✅ dnstt started"
fi

# =============================================
# Start OpenResty
# =============================================
echo "[5/5] Starting OpenResty..."
/usr/local/openresty/bin/openresty -g "daemon off;" > /var/log/openresty.log 2>&1 &
sleep 2
echo "✅ OpenResty started"

# =============================================
# Summary
# =============================================
echo ""
echo "=========================================="
echo "  All Services Started!"
echo "=========================================="
echo ""
echo "Active processes:"
ps aux | grep -E "xray|cloudflared|hysteria|dnstt|nginx" | grep -v grep
echo ""
echo "Logs:"
echo "  Xray:       tail -f /var/log/xray.log"
echo "  Cloudflared: tail -f /var/log/cloudflared.log"
echo "  Hysteria2:  tail -f /var/log/hysteria.log"
echo "  dnstt:      tail -f /var/log/dnstt.log"
echo "  OpenResty:  tail -f /var/log/openresty.log"
echo ""

# =============================================
# Keep Script Running
# =============================================
wait
