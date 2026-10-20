#!/bin/bash

# =============================================
# V2Ray VPN Server - Startup Script
# =============================================

# Environment Variables (Railway မှာ သတ်မှတ်ပါ၊ ဒီမှာ မထည့်ပါနဲ့)
# export TUNNEL_TOKEN="..."
# export SECRET_KEY="..."
# export DOMAIN="..."
# export DNSTT_DOMAIN="..."
# export VPS_MODE="..."

# =============================================
# Network Optimization (Railway မှာ ခွင့်မပြုပါဘူး၊ ဒါကြောင့် ဖျက်ထားပါတယ်)
# =============================================
# sysctl -w net.core.somaxconn=65535
# ...

# =============================================
# Stop Existing Services (မလိုအပ်ပါဘူး၊ ဒါပေမယ့် ထားခဲ့လို့ရပါတယ်)
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
    # Railway မှာ Log ကြည့်နိုင်ဖို့ stdout ကို ပြန်ပို့ပါ
    cat /var/log/xray.log
    exit 1
fi
echo "✅ Xray started (PID: $XRAY_PID)"

# =============================================
# Start Cloudflared (FIXED: protocol http2)
# =============================================
if [ -n "$TUNNEL_TOKEN" ]; then
    echo "[2/5] Starting Cloudflared (http2)..."
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 run \
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
/usr/local/openresty/bin/openresty -g "daemon off;" &
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

# =============================================
# Keep Script Running
# =============================================
wait
