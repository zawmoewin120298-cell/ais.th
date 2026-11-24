#!/bin/bash
set -u

# =============================================
# Railway V2Ray / Caddy / OpenResty / SNI-SSL Startup Script
# =============================================

# Railway Environment Variables:
# export PORT="8080"
# export TUNNEL_TOKEN="..."
# export CF_PROTOCOL="http2"
# export SECRET_KEY="..."
# export DOMAIN="..."
# export DNSTT_DOMAIN="..."
# export VPS_MODE="false"
# export FASTLY_ORIGIN_SECRET="..."
# export NGROK_AUTHTOKEN="..."
# export NGROK_PORT="8080"
# export NGROK_PROTO="http"
# export NGROK_ADDR=""
# export PY_RELAY_ENABLED="false"
# export PY_RELAY_ARGS="--listen-host 127.0.0.1 --remote-host 127.0.0.1 --remote-port 8444 --sni example.com --insecure"

APP_PORT="${PORT:-8080}"
mkdir -p /var/log /var/log/app /etc/nginx/cdn

# =============================================
# 0. Sync Runtime Secrets & Port
# =============================================
if [ -n "${FASTLY_ORIGIN_SECRET:-}" ] && [ -f /etc/nginx/cdn/fastly-origin-check.conf ]; then
    sed -i "s/FASTLY_SECRET_KEY_12345/${FASTLY_ORIGIN_SECRET}/g" /etc/nginx/cdn/fastly-origin-check.conf || true
fi

# OpenResty main config မှာ default 8080 ရှိနေရင် Railway $PORT နဲ့ ညှိမယ်
if [ -f /usr/local/openresty/nginx/conf/nginx.conf ] && [ "${APP_PORT}" != "8080" ]; then
    sed -i -E "s/listen[[:space:]]+8080([;[:space:]])/listen ${APP_PORT}\1/g" /usr/local/openresty/nginx/conf/nginx.conf || true
fi

# =============================================
# 1. Stop Existing Services (Exact name match)
# =============================================
echo "[Init] Stopping any leftover processes..."
pkill -x xray 2>/dev/null || true
pkill -x caddy 2>/dev/null || true
pkill -x cloudflared 2>/dev/null || true
pkill -x ngrok 2>/dev/null || true
pkill -x hysteria 2>/dev/null || true
pkill -x dnstt-server 2>/dev/null || true
pkill -x openresty 2>/dev/null || true
sleep 1

# =============================================
# 2. Start Xray (Check + Auto-Restart Watchdog)
# =============================================
echo "[1/7] Starting Xray..."
if [ -f /etc/xray/config.json ]; then
    /usr/local/bin/xray -config /etc/xray/config.json >> /var/log/xray.log 2>&1 &
    XRAY_PID=$!
    sleep 2

    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "❌ Xray failed to start. Check /var/log/xray.log"
        cat /var/log/xray.log
        exit 1
    fi
    echo "✅ Xray started (PID: $XRAY_PID)"

    (
        while true; do
            wait "$XRAY_PID" 2>/dev/null || true
            echo "⚠️ Xray exited, restarting in 2s..." >> /var/log/xray.log
            sleep 2
            /usr/local/bin/xray -config /etc/xray/config.json >> /var/log/xray.log 2>&1 &
            XRAY_PID=$!
        done
    ) &
else
    echo "ℹ️ /etc/xray/config.json not found, skipping Xray."
fi

# =============================================
# 3. Start Caddy (Check + Auto-Restart Watchdog)
# =============================================
echo "[2/7] Starting Caddy..."
if [ -f /etc/caddy/Caddyfile ]; then
    caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >> /var/log/caddy.log 2>&1 &
    CADDY_PID=$!
    sleep 2

    if ! kill -0 "$CADDY_PID" 2>/dev/null; then
        echo "⚠️ Caddy failed to start. Check /var/log/caddy.log"
        cat /var/log/caddy.log
    else
        echo "✅ Caddy started (PID: $CADDY_PID)"
        (
            while true; do
                wait "$CADDY_PID" 2>/dev/null || true
                echo "⚠️ Caddy exited, restarting in 3s..." >> /var/log/caddy.log
                sleep 3
                caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >> /var/log/caddy.log 2>&1 &
                CADDY_PID=$!
            done
        ) &
    fi
else
    echo "ℹ️ Caddyfile not found, skipping Caddy."
fi

# =============================================
# 4. Start Cloudflared (http2 + Auto-Restart)
# =============================================
if [ -n "${TUNNEL_TOKEN:-}" ]; then
    echo "[3/7] Starting Cloudflared (${CF_PROTOCOL:-http2})..."
    (
        while true; do
            /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol "${CF_PROTOCOL:-http2}" run \
                --token "${TUNNEL_TOKEN}" >> /var/log/cloudflared.log 2>&1 || true
            echo "⚠️ Cloudflared exited, retrying in 3s..." >> /var/log/cloudflared.log
            sleep 3
        done
    ) &
    sleep 2
    echo "✅ Cloudflared started"
fi

# =============================================
# 4b. Start Ngrok (Optional if NGROK_AUTHTOKEN is set)
# =============================================
if [ -n "${NGROK_AUTHTOKEN:-}" ]; then
    echo "[Ngrok] Configuring & starting Ngrok..."
    /usr/local/bin/ngrok config add-authtoken "${NGROK_AUTHTOKEN}" >> /var/log/ngrok.log 2>&1 || true

    NGROK_TARGET="${NGROK_ADDR:-127.0.0.1:${NGROK_PORT:-${APP_PORT}}}"
    NGROK_SCHEME="${NGROK_PROTO:-http}"

    (
        while true; do
            /usr/local/bin/ngrok "${NGROK_SCHEME}" "${NGROK_TARGET}" --log=stdout >> /var/log/ngrok.log 2>&1 || true
            echo "⚠️ Ngrok exited, retrying in 3s..." >> /var/log/ngrok.log
            sleep 3
        done
    ) &
    sleep 2
    echo "✅ Ngrok started (target: ${NGROK_SCHEME}://${NGROK_TARGET})"
fi

# =============================================
# 5. Start Hysteria2 (VPS_MODE=true only)
# =============================================
if [ "${VPS_MODE:-false}" = "true" ] && [ -f /app/hysteria.yaml ]; then
    echo "[4/7] Starting Hysteria2..."
    (
        while true; do
            /usr/local/bin/hysteria server -c /app/hysteria.yaml >> /var/log/hysteria.log 2>&1 || true
            echo "⚠️ Hysteria2 exited, retrying in 3s..." >> /var/log/hysteria.log
            sleep 3
        done
    ) &
    sleep 2
    echo "✅ Hysteria2 started"
fi

# =============================================
# 6. Start dnstt (VPS_MODE=true only)
# =============================================
if [ "${VPS_MODE:-false}" = "true" ] && [ -f /etc/dnstt/server.key ] && [ -n "${DNSTT_DOMAIN:-}" ]; then
    echo "[5/7] Starting dnstt..."
    (
        while true; do
            /usr/local/bin/dnstt-server \
                -udp :53 \
                -privkey-file /etc/dnstt/server.key \
                -domain "${DNSTT_DOMAIN}" \
                127.0.0.1:8000 >> /var/log/dnstt.log 2>&1 || true
            echo "⚠️ dnstt exited, retrying in 3s..." >> /var/log/dnstt.log
            sleep 3
        done
    ) &
    sleep 2
    echo "✅ dnstt started"
fi

# =============================================
# 7. Optional Python SNI / SSL Relay
# =============================================
if [ "${PY_RELAY_ENABLED:-false}" = "true" ] && [ -f /app/py_sni_relay.py ]; then
    echo "[6/7] Starting Python SNI/SSL Relay..."
    (
        while true; do
            python3 /app/py_sni_relay.py ${PY_RELAY_ARGS:-} >> /var/log/app/py-sni-relay.log 2>&1 || true
            echo "⚠️ Python SNI/SSL Relay exited, retrying in 3s..." >> /var/log/app/py-sni-relay.log
            sleep 3
        done
    ) &
    sleep 1
    echo "✅ Python SNI/SSL Relay started"
fi

# =============================================
# 8. Start OpenResty (Foreground Main Process)
# =============================================
echo "[7/7] Validating & starting OpenResty on port ${APP_PORT}..."
/usr/local/openresty/bin/openresty -t
echo "=========================================="
echo "  All Services Started Successfully!"
echo "=========================================="

exec /usr/local/openresty/bin/openresty
