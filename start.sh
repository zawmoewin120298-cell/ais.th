#!/bin/bash

# =============================================
# V2Ray & Caddy VPN Server - Startup Script
# =============================================

# Environment Variables (Railway မှာ သတ်မှတ်ပါ)
# export TUNNEL_TOKEN="..."
# export SECRET_KEY="..."
# export DOMAIN="..."
# export DNSTT_DOMAIN="..."
# export VPS_MODE="..."

# =============================================
# Stop Existing Services
# =============================================
echo "[Init] Stopping existing services..."
pkill -f xray 2>/dev/null || true
pkill -f caddy 2>/dev/null || true
pkill -f cloudflared 2>/dev/null || true
pkill -f hysteria 2>/dev/null || true
pkill -f dnstt-server 2>/dev/null || true
pkill -f openresty 2>/dev/null || true
sleep 2

# =============================================
# Start Xray
# =============================================
echo "[1/6] Starting Xray..."
/usr/local/bin/xray -config /etc/xray/config.json > /var/log/xray.log 2>&1 &
XRAY_PID=$!
sleep 2

if ! kill -0 $XRAY_PID 2>/dev/null; then
    echo "❌ Xray failed to start. Check /var/log/xray.log"
    cat /var/log/xray.log
    exit 1
fi
echo "✅ Xray started (PID: $XRAY_PID)"

# =============================================
# Start Caddy (Reverse Proxy & Port Mapping)
# =============================================
echo "[2/6] Starting Caddy..."
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile > /var/log/caddy.log 2>&1 &
CADDY_PID=$!
sleep 2

if ! kill -0 $CADDY_PID 2>/dev/null; then
    echo "⚠️ Caddy failed to start. Check /var/log/caddy.log"
    cat /var/log/caddy.log
else
    echo "✅ Caddy started (PID: $CADDY_PID)"
fi

# =============================================
# Start Cloudflared (FIXED: protocol http2)
# =============================================
if [ -n "$TUNNEL_TOKEN" ]; then
    echo "[3/6] Starting Cloudflared (http2)..."
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 run \
        --token ${TUNNEL_TOKEN} > /var/log/cloudflared.log 2>&1 &
    sleep 3
    echo "✅ Cloudflared started"
fi

# =============================================
# Start Hysteria2
# =============================================
if [ "$VPS_MODE" = "true" ] && [ -f /app/hysteria.yaml ]; then
    echo "[4/6] Starting Hysteria2..."
    /usr/local/bin/hysteria server -c /app/hysteria.yaml > /var/log/hysteria.log 2>&1 &
    sleep 2
    echo "✅ Hysteria2 started"
fi

# =============================================
# Start dnstt
# =============================================
if [ "$VPS_MODE" = "true" ] && [ -f /etc/dnstt/server.key ] && [ -n "$DNSTT_DOMAIN" ]; then
    echo "[5/6] Starting dnstt..."
    /usr/local/bin/dnstt-server \
        -udp :53 \
        -privkey-file /etc/dnstt/server.key \
        -domain ${DNSTT_DOMAIN} \
        127.0.0.1:8000 > /var/log/dnstt.log 2>&1 &
    sleep 2
    echo "✅ dnstt started"
fi

# =============================================
# Start OpenResty (Foreground mode အတွက် exec သုံးခြင်း)
# =============================================
echo "[6/6] Starting OpenResty..."
echo "=========================================="
echo "  All Services Started Successfully!"
echo "=========================================="

# OpenResty ကို Main process အနေနဲ့ Foreground မှာ တွဲ run ပေးခြင်းဖြင့် Script မရပ်သွားအောင် ထိန်းပေးသည်
exec /usr/local/openresty/bin/openresty -g "daemon off;"
