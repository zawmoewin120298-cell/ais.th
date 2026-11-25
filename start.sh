
#!/usr/bin/env bash
set -u

# =============================================
# Railway VPN Multi-Tunnel Server
# Ngrok + Cloudflare + LocalXpose
# Xray + Caddy + OpenResty
# Hysteria2 + DNSTT + Python Relay
# =============================================

APP_PORT="${PORT:-8080}"

mkdir -p /var/log/app /var/log /etc/nginx/cdn

echo "=========================================="
echo " Starting Railway Multi-Service Server"
echo " Port: ${APP_PORT}"
echo "=========================================="

# =============================================
# 0. Environment & Secret Configuration
# =============================================

# Support both old and new LocalXpose variable names
LX_TOKEN="${LX_ACCESS_TOKEN:-${LOCLX_ACCESS_TOKEN:-}}"

# Remove accidental whitespace around token
LX_TOKEN="$(printf '%s' "$LX_TOKEN" | tr -d '[:space:]')"

# =============================================
# 1. Sync Runtime Secrets
# =============================================

if [ -n "${FASTLY_ORIGIN_SECRET:-}" ] && \
   [ -f /etc/nginx/cdn/fastly-origin-check.conf ]; then

    sed -i "s/FASTLY_SECRET_KEY_12345/${FASTLY_ORIGIN_SECRET}/g" \
        /etc/nginx/cdn/fastly-origin-check.conf || true
fi

# Update OpenResty port
if [ -f /usr/local/openresty/nginx/conf/nginx.conf ]; then
    if [ "$APP_PORT" != "8080" ]; then
        sed -i -E \
        "s/listen[[:space:]]+8080([;[:space:]])/listen ${APP_PORT}\1/g" \
        /usr/local/openresty/nginx/conf/nginx.conf || true
    fi
fi

# =============================================
# 2. Stop Existing Processes
# =============================================

echo "[Init] Cleaning old processes..."

for service in xray caddy cloudflared ngrok loclx hysteria dnstt-server openresty
do
    pkill -x "$service" 2>/dev/null || true
done

sleep 1

# =============================================
# 3. Xray
# =============================================

echo "[Xray] Checking configuration..."

if [ -f /etc/xray/config.json ]; then

    /usr/local/bin/xray -config /etc/xray/config.json \
        >> /var/log/xray.log 2>&1 &

    XRAY_PID=$!

    sleep 2

    if kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "[Xray] Started successfully"

        (
            while true; do
                wait "$XRAY_PID" 2>/dev/null || true

                echo "[Xray] Restarting..." >> /var/log/xray.log
                sleep 3

                /usr/local/bin/xray -config /etc/xray/config.json \
                    >> /var/log/xray.log 2>&1 &

                XRAY_PID=$!
            done
        ) &

    else
        echo "[Xray] Failed to start"
        cat /var/log/xray.log
    fi
else
    echo "[Xray] Config not found, skipping"
fi

# =============================================
# 4. Caddy
# =============================================

echo "[Caddy] Starting..."

if [ -f /etc/caddy/Caddyfile ]; then

    (
        while true; do
            caddy run \
                --config /etc/caddy/Caddyfile \
                --adapter caddyfile \
                >> /var/log/caddy.log 2>&1 || true

            echo "[Caddy] Restarting in 3 seconds..." \
                >> /var/log/caddy.log

            sleep 3
        done
    ) &

    sleep 2
    echo "[Caddy] Process launched"
else
    echo "[Caddy] Caddyfile not found, skipping"
fi

# =============================================
# 5. Cloudflare Tunnel
# =============================================

if [ -n "${TUNNEL_TOKEN:-}" ]; then

    echo "[Cloudflared] Starting..."

    (
        while true; do

            /usr/local/bin/cloudflared tunnel \
                --no-autoupdate \
                --protocol "${CF_PROTOCOL:-http2}" \
                run \
                --token "$TUNNEL_TOKEN" \
                >> /var/log/cloudflared.log 2>&1 || true

            echo "[Cloudflared] Restarting in 5 seconds..." \
                >> /var/log/cloudflared.log

            sleep 5
        done
    ) &

    echo "[Cloudflared] Process launched"
else
    echo "[Cloudflared] TUNNEL_TOKEN missing, skipping"
fi

# =============================================
# 6. Ngrok Tunnel
# =============================================

if [ -n "${NGROK_AUTHTOKEN:-}" ]; then

    echo "[Ngrok] Configuring..."

    /usr/local/bin/ngrok config add-authtoken \
        "$NGROK_AUTHTOKEN" \
        >> /var/log/ngrok.log 2>&1 || true

    NGROK_TARGET="${NGROK_ADDR:-127.0.0.1:${NGROK_PORT:-${APP_PORT}}}"
    NGROK_SCHEME="${NGROK_PROTO:-http}"

    (
        while true; do

            echo "[Ngrok] Starting ${NGROK_SCHEME} tunnel..." \
                >> /var/log/ngrok.log

            /usr/local/bin/ngrok "$NGROK_SCHEME" "$NGROK_TARGET" \
                --log=stdout \
                >> /var/log/ngrok.log 2>&1 || true

            echo "[Ngrok] Restarting in 5 seconds..." \
                >> /var/log/ngrok.log

            sleep 5
        done
    ) &

    echo "[Ngrok] Process launched"
else
    echo "[Ngrok] NGROK_AUTHTOKEN missing, skipping"
fi

# =============================================
# 7. LocalXpose Tunnel
# =============================================

if [ -n "$LX_TOKEN" ]; then

    echo "[LocalXpose] Configuring..."

    LX_TARGET="${LOCLX_ADDR:-127.0.0.1:${LOCLX_PORT:-${APP_PORT}}}"
    LX_TYPE="${LOCLX_TYPE:-http}"

    (
        export LX_ACCESS_TOKEN="$LX_TOKEN"

        while true; do

            echo "[LocalXpose] Starting ${LX_TYPE} tunnel..." \
                >> /var/log/loclx.log

            /usr/local/bin/loclx tunnel "$LX_TYPE" \
                --to "$LX_TARGET" \
                >> /var/log/loclx.log 2>&1

            EXIT_CODE=$?

            echo "[LocalXpose] Exited with code ${EXIT_CODE}" \
                >> /var/log/loclx.log

            echo "[LocalXpose] Retrying in 5 seconds..." \
                >> /var/log/loclx.log

            sleep 5
        done
    ) &

    echo "[LocalXpose] Process launched"
else
    echo "[LocalXpose] LX_ACCESS_TOKEN missing, skipping"
fi

# =============================================
# 8. Hysteria2
# =============================================

if [ "${VPS_MODE:-false}" = "true" ] && \
   [ -f /app/hysteria.yaml ]; then

    echo "[Hysteria] Starting..."

    (
        while true; do

            /usr/local/bin/hysteria server \
                -c /app/hysteria.yaml \
                >> /var/log/hysteria.log 2>&1 || true

            echo "[Hysteria] Restarting..." \
                >> /var/log/hysteria.log

            sleep 5
        done
    ) &

    echo "[Hysteria] Process launched"
fi

# =============================================
# 9. DNSTT
# =============================================

if [ "${VPS_MODE:-false}" = "true" ] && \
   [ -f /etc/dnstt/server.key ] && \
   [ -n "${DNSTT_DOMAIN:-}" ]; then

    echo "[DNSTT] Starting..."

    (
        while true; do

            /usr/local/bin/dnstt-server \
                -udp :53 \
                -privkey-file /etc/dnstt/server.key \
                -domain "$DNSTT_DOMAIN" \
                127.0.0.1:8000 \
                >> /var/log/dnstt.log 2>&1 || true

            echo "[DNSTT] Restarting..." \
                >> /var/log/dnstt.log

            sleep 5
        done
    ) &

    echo "[DNSTT] Process launched"
fi

# =============================================
# 10. Python SNI / SSL Relay
# =============================================

if [ "${PY_RELAY_ENABLED:-false}" = "true" ] && \
   [ -f /app/py_sni_relay.py ]; then

    echo "[Python Relay] Starting..."

    (
        while true; do

            python3 /app/py_sni_relay.py \
                ${PY_RELAY_ARGS:-} \
                >> /var/log/app/py-sni-relay.log 2>&1 || true

            echo "[Python Relay] Restarting..." \
                >> /var/log/app/py-sni-relay.log

            sleep 5
        done
    ) &

    echo "[Python Relay] Process launched"
fi

# =============================================
# 11. OpenResty Configuration Check
# =============================================

echo "[OpenResty] Testing configuration..."

if ! /usr/local/openresty/bin/openresty -t; then

    echo "[OpenResty] Configuration ERROR"

    exit 1
fi

echo "=========================================="
echo " Service startup completed"
echo " Ngrok:        ${NGROK_AUTHTOKEN:+ENABLED}"
echo " Cloudflared:  ${TUNNEL_TOKEN:+ENABLED}"
echo " LocalXpose:   ${LX_TOKEN:+ENABLED}"
echo " OpenResty:    PORT ${APP_PORT}"
echo "=========================================="

# =============================================
# 12. OpenResty Main Foreground Process
# =============================================

echo "[OpenResty] Starting in foreground..."

exec /usr/local/openresty/bin/openresty \
    -g "daemon off;"
    
