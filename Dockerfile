# =============================================
# Base Image (Debian-based OpenResty)
# =============================================
FROM openresty/openresty:1.25.3.1-0-bookworm-fat

# =============================================
# 1. Install Dependencies
# =============================================
RUN apt-get update && apt-get install -y \
    curl wget unzip openssl ca-certificates \
    iptables iproute2 net-tools procps \
    && rm -rf /var/lib/apt/lists/*

# =============================================
# 2. Install Xray
# =============================================
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o /tmp/xray.zip \
    && unzip /tmp/xray.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm /tmp/xray.zip

# =============================================
# 3. Install Cloudflared
# =============================================
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# =============================================
# 4. Install Playit
# =============================================
RUN curl -L https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 \
    -o /usr/local/bin/playit \
    && chmod +x /usr/local/bin/playit

# =============================================
# 5. Install Hysteria2
# =============================================
RUN curl -L https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 \
    -o /usr/local/bin/hysteria \
    && chmod +x /usr/local/bin/hysteria

# =============================================
# 6. Install dnstt (VPS Only)
# =============================================
RUN curl -L https://dnstt.network/dnstt-server-linux-amd64 \
    -o /usr/local/bin/dnstt-server \
    && chmod +x /usr/local/bin/dnstt-server

# =============================================
# 7. Create Directories
# =============================================
RUN mkdir -p /etc/xray /cache /usr/local/openresty/nginx/html /app /etc/dnstt \
    /root/.config/playit_gg /var/log/supervisor

# =============================================
# 8. Generate Self-Signed Cert (Fallback)
# =============================================
RUN openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /app/key.pem -out /app/cert.pem \
    -subj "/CN=${DOMAIN:-localhost}" -days 36500

# =============================================
# 9. Copy Configuration Files
# =============================================
COPY ./config.json /etc/xray/config.json
COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./nginx_edge.conf /usr/local/openresty/nginx/conf/nginx_edge.conf
COPY ./generic_conf/ /usr/local/openresty/nginx/conf/generic_conf/
COPY ./src/ /usr/local/openresty/nginx/src/
COPY ./my-website/ /usr/local/openresty/nginx/html/
COPY ./hysteria.yaml /app/hysteria.yaml

RUN chmod 755 /cache

# =============================================
# 10. Startup Script
# =============================================
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "=========================================="\n\
echo "  Starting Services..."\n\
echo "=========================================="\n\
\n\
# Network Optimization (Container Level)\n\
sysctl -w net.core.somaxconn=1024 2>/dev/null || true\n\
sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null || true\n\
\n\
# Xray (Always)\n\
echo "[1/5] Starting Xray..."\n\
/usr/local/bin/xray -config /etc/xray/config.json &\n\
sleep 2\n\
\n\
# Cloudflared (If Token exists)\n\
if [ -n "$TUNNEL_TOKEN" ]; then\n\
  echo "[2/5] Starting Cloudflared..."\n\
  /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol quic run --token ${TUNNEL_TOKEN} &\n\
  sleep 2\n\
fi\n\
\n\
# Playit (If Secret exists)\n\
if [ -n "$SECRET_KEY" ]; then\n\
  echo "[3/5] Starting Playit..."\n\
  /usr/local/bin/playit --secret ${SECRET_KEY} &\n\
  sleep 1\n\
fi\n\
\n\
# Hysteria2 (VPS Mode Only)\n\
if [ "$VPS_MODE" = "true" ] && [ -f /app/hysteria.yaml ]; then\n\
  echo "[4/5] Starting Hysteria2 (VPS Mode)..."\n\
  /usr/local/bin/hysteria server -c /app/hysteria.yaml &\n\
  sleep 1\n\
fi\n\
\n\
# dnstt (VPS Mode Only)\n\
if [ "$VPS_MODE" = "true" ] && [ -f /etc/dnstt/server.key ] && [ -n "$DNSTT_DOMAIN" ]; then\n\
  echo "[5/5] Starting dnstt (VPS Mode)..."\n\
  /usr/local/bin/dnstt-server \\\n\
    -udp :53 \\\n\
    -privkey-file /etc/dnstt/server.key \\\n\
    -domain ${DNSTT_DOMAIN} \\\n\
    127.0.0.1:8000 &\n\
  sleep 1\n\
fi\n\
\n\
echo "=========================================="\n\
echo "  All Services Started!"\n\
echo "=========================================="\n\
\n\
exec /usr/local/openresty/bin/openresty -g "daemon off;"\n' > /start.sh \
    && chmod +x /start.sh

# =============================================
# 11. Ports & Environment Variables
# =============================================
EXPOSE 443 80 10001 443/udp 53/udp

ENV TUNNEL_TOKEN=""
ENV SECRET_KEY=""
ENV VPS_MODE="false"
ENV DNSTT_DOMAIN=""
ENV DOMAIN="localhost"

# =============================================
# 12. Health Check
# =============================================
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# =============================================
# 13. Entrypoint
# =============================================
CMD ["/start.sh"]
