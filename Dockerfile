# =============================================
# Base Image (Debian-based OpenResty)
# =============================================
FROM openresty/openresty:1.25.3.1-0-bookworm-fat

# =============================================
# 1. Install Dependencies
# =============================================
RUN apt-get update && apt-get install -y \
    curl wget unzip openssl ca-certificates \
    iptables iproute2 net-tools procps squid \
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
    /etc/nginx/cdn /root/.config/playit_gg /var/log/supervisor \
    /var/log/squid /var/spool/squid

# =============================================
# 8. Generate Self-Signed Cert (Fallback)
# =============================================
RUN openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /app/key.pem -out /app/cert.pem \
    -subj "/CN=${DOMAIN:-localhost}" -days 36500

# =============================================
# 9. Fastly CDN Configuration
# =============================================
RUN printf 'allow 23.235.32.0/20;\n\
allow 43.249.72.0/22;\n\
allow 103.244.50.0/24;\n\
allow 103.245.222.0/23;\n\
allow 103.245.224.0/24;\n\
allow 104.156.80.0/20;\n\
allow 140.248.64.0/18;\n\
allow 140.248.128.0/17;\n\
allow 146.75.0.0/16;\n\
allow 151.101.0.0/16;\n\
allow 157.52.64.0/18;\n\
allow 167.82.0.0/17;\n\
allow 167.82.128.0/20;\n\
allow 167.82.160.0/20;\n\
allow 167.82.224.0/20;\n\
allow 172.111.64.0/18;\n\
allow 185.31.16.0/22;\n\
allow 199.27.72.0/21;\n\
allow 199.232.0.0/16;\n\
deny all;\n' > /etc/nginx/cdn/fastly-ips.conf

RUN printf 'allow 2a04:4e40::/32;\n\
allow 2a04:4e42::/32;\n\
deny all;\n' > /etc/nginx/cdn/fastly-ipv6.conf

RUN printf '# Fastly CDN Headers\n\
proxy_set_header Fastly-Client-IP $http_fastly_client_ip;\n\
proxy_set_header Fastly-FF $http_fastly_ff;\n\
proxy_set_header Fastly-SSL $http_fastly_ssl;\n\
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\
proxy_set_header X-Real-IP $http_fastly_client_ip;\n\
proxy_set_header X-Forwarded-Proto $scheme;\n\
proxy_set_header X-Origin-Secret $http_x_origin_secret;\n' > /etc/nginx/cdn/fastly-headers.conf

RUN printf '# Fastly Origin Secret Check\n\
if ($http_x_origin_secret != "FASTLY_SECRET_KEY_12345") {\n\
    return 403;\n\
}\n' > /etc/nginx/cdn/fastly-origin-check.conf

# =============================================
# 9b. Squid Proxy Configuration (NEW)
# =============================================
RUN printf '# ============================================\n\
# Squid Proxy -> Xray HTTP Inbound\n\
# ============================================\n\
http_port 3128\n\
\n\
# Xray HTTP inbound (1080) as upstream parent\n\
cache_peer 127.0.0.1 parent 1080 0 no-query default\n\
never_direct allow all\n\
\n\
# No caching (VPN traffic)\n\
cache deny all\n\
cache_mem 0 MB\n\
\n\
# Logs\n\
access_log /var/log/squid/access.log\n\
cache_log /var/log/squid/cache.log\n\
\n\
# Ports\n\
acl SSL_ports port 443\n\
acl Safe_ports port 80\n\
acl Safe_ports port 443\n\
acl Safe_ports port 8080\n\
acl CONNECT method CONNECT\n\
\n\
# Access\n\
http_access deny !Safe_ports\n\
http_access deny CONNECT !SSL_ports\n\
http_access allow all\n\
http_access deny all\n\
\n\
# DNS\n\
dns_nameservers 8.8.8.8 1.1.1.1\n\
visible_hostname proxy\n\
via off\n\
forwarded_for delete\n' > /etc/squid/squid.conf

# Squid log/cache dir permissions
RUN chown -R proxy:proxy /var/log/squid /var/spool/squid /etc/squid && \
    chmod 755 /var/log/squid /var/spool/squid

# =============================================
# 10. Copy Configuration Files
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
# 11. Startup Script
# =============================================
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "=========================================="\n\
echo "  Starting Services..."\n\
echo "=========================================="\n\
\n\
sysctl -w net.core.somaxconn=1024 2>/dev/null || true\n\
sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null || true\n\
\n\
# Xray (Always)\n\
echo "[1/7] Starting Xray..."\n\
/usr/local/bin/xray -config /etc/xray/config.json &\n\
sleep 2\n\
\n\
# Squid Proxy (Always)\n\
echo "[2/7] Starting Squid..."\n\
/usr/sbin/squid -N -f /etc/squid/squid.conf &\n\
sleep 1\n\
\n\
# Cloudflared (If Token exists)\n\
if [ -n "$TUNNEL_TOKEN" ]; then\n\
  echo "[3/7] Starting Cloudflared..."\n\
  /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol quic run --token ${TUNNEL_TOKEN} &\n\
  sleep 2\n\
fi\n\
\n\
# Playit (If Secret exists)\n\
if [ -n "$SECRET_KEY" ]; then\n\
  echo "[4/7] Starting Playit..."\n\
  /usr/local/bin/playit --secret ${SECRET_KEY} &\n\
  sleep 1\n\
fi\n\
\n\
# Hysteria2 (VPS Mode Only)\n\
if [ "$VPS_MODE" = "true" ] && [ -f /app/hysteria.yaml ]; then\n\
  echo "[5/7] Starting Hysteria2 (VPS Mode)..."\n\
  /usr/local/bin/hysteria server -c /app/hysteria.yaml &\n\
  sleep 1\n\
fi\n\
\n\
# dnstt (VPS Mode Only)\n\
if [ "$VPS_MODE" = "true" ] && [ -f /etc/dnstt/server.key ] && [ -n "$DNSTT_DOMAIN" ]; then\n\
  echo "[6/7] Starting dnstt (VPS Mode)..."\n\
  /usr/local/bin/dnstt-server \\\n\
    -udp :53 \\\n\
    -privkey-file /etc/dnstt/server.key \\\n\
    -domain ${DNSTT_DOMAIN} \\\n\
    127.0.0.1:8000 &\n\
  sleep 1\n\
fi\n\
\n\
echo "[7/7] Starting OpenResty..."\n\
echo "=========================================="\n\
echo "  All Services Started!"\n\
echo "=========================================="\n\
\n\
exec /usr/local/openresty/bin/openresty -g "daemon off;"\n' > /start.sh \
    && chmod +x /start.sh

# =============================================
# 12. Ports & Environment Variables
# =============================================
EXPOSE 443 80 8080 2053 2086 8443 10002 10001 3128 443/udp 53/udp

# Cloudflare
ENV TUNNEL_TOKEN=""
ENV SECRET_KEY=""

# Fastly
ENV FASTLY_ORIGIN_SECRET="FASTLY_SECRET_KEY_12345"
ENV FASTLY_ENABLED="false"

# VPS Mode
ENV VPS_MODE="false"
ENV DNSTT_DOMAIN=""
ENV DOMAIN="localhost"

# =============================================
# 13. Health Check
# =============================================
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# =============================================
# 14. Entrypoint
# =============================================
CMD ["/start.sh"]
