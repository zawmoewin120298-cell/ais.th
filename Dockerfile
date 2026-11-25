# syntax=docker/dockerfile:1

# =============================================
# 0. Build Stage: aleskxyz/SNI-Spoofing-Go
# =============================================
FROM golang:1.25 AS sni-build
WORKDIR /src

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/aleskxyz/SNI-Spoofing-Go.git .

ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go mod download \
    && go build -ldflags="-s -w" -o /out/sni-spoofing .

# =============================================
# Base Image (Debian-based OpenResty)
# =============================================
FROM openresty/openresty:1.25.3.1-0-bookworm-fat

# =============================================
# 1. Install Dependencies
# =============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip openssl ca-certificates \
    python3 python3-requests \
    iptables iproute2 net-tools procps squid \
    stunnel4 \
    debian-keyring debian-archive-keyring apt-transport-https gpg \
    && rm -rf /var/lib/apt/lists/*

# =============================================
# 1b. Install Caddy (Official Debian Repo)
# =============================================
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends caddy \
    && mkdir -p /etc/caddy \
    && rm -rf /var/lib/apt/lists/*

# =============================================
# 2. Install Xray
# =============================================
RUN curl -fsSL https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o /tmp/xray.zip \
    && unzip -o /tmp/xray.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm -f /tmp/xray.zip

# =============================================
# 3. Install Cloudflared
# =============================================
RUN curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# =============================================
# 4. Install Playit
# =============================================
RUN curl -fsSL https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 \
    -o /usr/local/bin/playit \
    && chmod +x /usr/local/bin/playit

# =============================================
# 4b. Install Ngrok
# =============================================
RUN curl -fsSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -o /tmp/ngrok.tgz \
    && tar -xzf /tmp/ngrok.tgz -C /usr/local/bin \
    && chmod +x /usr/local/bin/ngrok \
    && rm -f /tmp/ngrok.tgz

# =============================================
# 4c. Install LocalXpose (loclx)
# =============================================
RUN curl -fsSL "https://api.localxpose.io/api/v2/downloads/loclx-linux-amd64.zip" -o /tmp/loclx.zip \
    && unzip -o /tmp/loclx.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/loclx \
    && rm -f /tmp/loclx.zip

# =============================================
# 5. Install Hysteria2
# =============================================
RUN curl -fsSL https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 \
    -o /usr/local/bin/hysteria \
    && chmod +x /usr/local/bin/hysteria

# =============================================
# 6. Install dnstt
# =============================================
RUN curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 \
    -o /usr/local/bin/dnstt-server \
    && chmod +x /usr/local/bin/dnstt-server

# =============================================
# 6b. Install GOST (TLS Tunnel)
# =============================================
RUN curl -fsSL https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz \
    -o /tmp/gost.gz \
    && gunzip -c /tmp/gost.gz > /usr/local/bin/gost \
    && chmod +x /usr/local/bin/gost \
    && rm -f /tmp/gost.gz

# Copy SNI-Spoofing-Go binary
COPY --from=sni-build /out/sni-spoofing /usr/local/bin/sni-spoofing
RUN chmod +x /usr/local/bin/sni-spoofing

# =============================================
# 7. Create Directories & Log Dirs
# =============================================
RUN mkdir -p /etc/xray /cache /usr/local/openresty/nginx/html /app /etc/dnstt \
    /etc/nginx/cdn /root/.config/playit_gg /root/.localxpose /var/log/supervisor \
    /var/log/squid /var/spool/squid \
    /etc/stunnel /var/run/stunnel /var/log/stunnel /var/log/app

# =============================================
# 8. Generate Self-Signed Cert (with SAN)
# =============================================
RUN openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /app/key.pem -out /app/cert.pem \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    -days 36500

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
# 9b. Squid Proxy Configuration
# =============================================
RUN printf '# ============================================\n\
# Squid Proxy -> Xray HTTP Inbound\n\
# ============================================\n\
http_port 3128\n\
\n\
cache_peer 127.0.0.1 parent 1080 0 no-query default\n\
never_direct allow all\n\
\n\
cache deny all\n\
cache_mem 0 MB\n\
\n\
access_log /var/log/squid/access.log\n\
cache_log /var/log/squid/cache.log\n\
\n\
acl SSL_ports port 443\n\
acl Safe_ports port 80\n\
acl Safe_ports port 443\n\
acl Safe_ports port 8080\n\
acl CONNECT method CONNECT\n\
\n\
http_access deny !Safe_ports\n\
http_access deny CONNECT !SSL_ports\n\
http_access allow localhost\n\
http_access deny all\n\
\n\
dns_nameservers 8.8.8.8 1.1.1.1\n\
visible_hostname proxy\n\
via off\n\
forwarded_for delete\n' > /etc/squid/squid.conf

RUN chown -R proxy:proxy /var/log/squid /var/spool/squid /etc/squid && \
    chmod 755 /var/log/squid /var/spool/squid

# =============================================
# 9c. stunnel Configuration (TLS 1.2+ Hardened)
# =============================================
RUN printf 'foreground = yes\n\
pid = /var/run/stunnel/stunnel.pid\n\
debug = 4\n\
output = /var/log/stunnel/stunnel.log\n\
options = NO_SSLv2\n\
options = NO_SSLv3\n\
options = NO_TLSv1\n\
options = NO_TLSv1_1\n\
\n\
[ws-tls]\n\
accept = 8444\n\
connect = 127.0.0.1:10001\n\
cert = /app/cert.pem\n\
key = /app/key.pem\n\
verify = 0\n\
\n\
[xhttp-tls]\n\
accept = 8445\n\
connect = 127.0.0.1:10002\n\
cert = /app/cert.pem\n\
key = /app/key.pem\n\
verify = 0\n' > /etc/stunnel/stunnel.conf

# =============================================
# 9d–9f. API Data Fetchers
# =============================================
RUN printf 'import json\n\
import os\n\
import requests\n\
\n\
api_key = os.environ.get("TAILSCALE_API_KEY", "").strip()\n\
tailnet = os.environ.get("TAILSCALE_TAILNET", "-").strip()\n\
out_file = os.environ.get("TAILSCALE_OUTPUT_FILE", "/tmp/tailscale_devices.json").strip()\n\
\n\
if not api_key:\n\
    print("[Tailscale] TAILSCALE_API_KEY not set, skipping.")\n\
    raise SystemExit(0)\n\
\n\
try:\n\
    resp = requests.get(\n\
        f"https://api.tailscale.com/api/v2/tailnet/{tailnet}/devices",\n\
        headers={"Authorization": f"Bearer {api_key}"},\n\
        timeout=15,\n\
    )\n\
    resp.raise_for_status()\n\
    devices = resp.json().get("devices", [])\n\
    with open(out_file, "w", encoding="utf-8") as f:\n\
        json.dump(devices, f, indent=2, ensure_ascii=False)\n\
    print(f"[Tailscale] Fetched {len(devices)} devices -> {out_file}")\n\
except Exception as e:\n\
    print(f"[Tailscale] Fetch failed: {e}")\n' > /app/fetch_tailscale.py \
    && printf 'import json\n\
import os\n\
import requests\n\
\n\
token = os.environ.get("REDIRECT_PIZZA_TOKEN", "").strip()\n\
endpoint = os.environ.get("REDIRECT_PIZZA_ENDPOINT", "redirects").strip().lstrip("/")\n\
out_file = os.environ.get("REDIRECT_PIZZA_OUTPUT_FILE", "/tmp/redirect_pizza.json").strip()\n\
\n\
if not token:\n\
    print("[Redirect.pizza] REDIRECT_PIZZA_TOKEN not set, skipping.")\n\
    raise SystemExit(0)\n\
\n\
url = f"https://redirect.pizza/api/v1/{endpoint}"\n\
headers = {\n\
    "Authorization": f"Bearer {token}",\n\
    "Accept": "application/json",\n\
}\n\
\n\
try:\n\
    resp = requests.get(url, headers=headers, timeout=15)\n\
    resp.raise_for_status()\n\
    data = resp.json()\n\
    with open(out_file, "w", encoding="utf-8") as f:\n\
        json.dump(data, f, indent=2, ensure_ascii=False)\n\
    print(f"[Redirect.pizza] Saved {endpoint} -> {out_file}")\n\
except Exception as e:\n\
    print(f"[Redirect.pizza] Fetch failed: {e}")\n' > /app/fetch_redirect_pizza.py \
    && printf 'import json\n\
import os\n\
import requests\n\
\n\
api_key = os.environ.get("QD_KEY", "").strip()\n\
endpoint = os.environ.get("QD_ENDPOINT", "public/balance").strip().lstrip("/")\n\
out_file = os.environ.get("QD_OUTPUT_FILE", "/tmp/quanticdata.json").strip()\n\
\n\
if not api_key:\n\
    print("[QuanticData] QD_KEY not set, skipping.")\n\
    raise SystemExit(0)\n\
\n\
url = f"https://api.quanticdata.io/v1/{endpoint}"\n\
headers = {\n\
    "Authorization": f"Bearer {api_key}",\n\
    "Accept": "application/json",\n\
}\n\
\n\
try:\n\
    resp = requests.get(url, headers=headers, timeout=15)\n\
    resp.raise_for_status()\n\
    data = resp.json()\n\
    with open(out_file, "w", encoding="utf-8") as f:\n\
        json.dump(data, f, indent=2, ensure_ascii=False)\n\
    print(f"[QuanticData] Fetched {endpoint} -> {out_file}")\n\
except Exception as e:\n\
    print(f"[QuanticData] Fetch failed: {e}")\n' > /app/fetch_quanticdata.py \
    && chmod +x /app/fetch_tailscale.py /app/fetch_redirect_pizza.py /app/fetch_quanticdata.py

# =============================================
# 10. Copy Configuration Files & Scripts
# =============================================
COPY ./config.json /etc/xray/config.json
COPY ./Caddyfile /etc/caddy/Caddyfile
COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./nginx_edge.conf /usr/local/openresty/nginx/conf/nginx_edge.conf
COPY ./generic_conf/ /usr/local/openresty/nginx/conf/generic_conf/
COPY ./src/ /usr/local/openresty/nginx/src/
COPY ./my-website/ /usr/local/openresty/nginx/html/
COPY ./hysteria.yaml /app/hysteria.yaml
COPY ./py_sni_relay.py /app/py_sni_relay.py
COPY ./start.sh /start.sh

RUN printf '#!/usr/bin/env bash\n\
set -u\n\
echo "[Entrypoint] Running QuanticData check..."\n\
python3 /app/fetch_quanticdata.py || true\n\
exec "$@"\n' > /entrypoint.sh \
    && chmod +x /entrypoint.sh /start.sh /app/py_sni_relay.py \
    && chmod 755 /cache

# =============================================
# 11. Ports & Environment
# =============================================
EXPOSE 443 80 8080 2053 2086 8443 8444 8445 10002 10001 10003 3128 1081 8081 443/udp 53/udp

ENV TUNNEL_TOKEN=""
ENV CF_PROTOCOL="http2"
ENV SECRET_KEY=""
ENV NGROK_AUTHTOKEN=""
ENV NGROK_PORT="8080"
ENV NGROK_PROTO="http"
ENV NGROK_ADDR=""
ENV LOCLX_ACCESS_TOKEN=""
ENV LOCLX_PORT="8080"
ENV LOCLX_TYPE="http"
ENV LOCLX_ADDR=""
ENV LOCLX_REGION=""
ENV FASTLY_ORIGIN_SECRET=""
ENV FASTLY_ENABLED="false"
ENV VPS_MODE="false"
ENV DNSTT_DOMAIN=""
ENV DOMAIN="localhost"
ENV SNI_SPOOF_ENABLED="false"
ENV SNI_SPOOF_ARGS=""
ENV PY_RELAY_ENABLED="false"
ENV PY_RELAY_ARGS="--listen-host 127.0.0.1 --listen-port 19001 --remote-host 127.0.0.1 --remote-port 8444 --sni example.com --insecure"
ENV TAILSCALE_API_KEY=""
ENV TAILSCALE_TAILNET="-"
ENV TAILSCALE_OUTPUT_FILE="/tmp/tailscale_devices.json"
ENV REDIRECT_PIZZA_TOKEN=""
ENV REDIRECT_PIZZA_ENDPOINT="redirects"
ENV REDIRECT_PIZZA_OUTPUT_FILE="/tmp/redirect_pizza.json"
ENV QD_ENDPOINT="public/balance"
ENV QD_OUTPUT_FILE="/tmp/quanticdata.json"

# =============================================
# 12. Health Check
# =============================================
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

# =============================================
# 13. Entrypoint
# =============================================
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/start.sh"]
