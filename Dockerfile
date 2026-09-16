FROM igorbarinov/openresty-nginx-module-vts

# =============================================
# 1. Network Optimization
# =============================================
RUN echo "net.core.somaxconn = 1024" >> /etc/sysctl.conf && \
    echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_max_syn_backlog = 1024" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.conf

# =============================================
# 2. Install Xray, Cloudflared, Playit & Hysteria2
# =============================================
RUN apk --no-cache add curl unzip openssl \
    && curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm xray.zip \
    && curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared \
    && curl -L https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -o /usr/local/bin/playit \
    && chmod +x /usr/local/bin/playit \
    && curl -L https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 -o /usr/local/bin/hysteria \
    && chmod +x /usr/local/bin/hysteria

# =============================================
# 3. Create directories & Generate Certificate
# =============================================
RUN mkdir -p /etc/xray /cache /usr/local/openresty/nginx/html /app /root/.config/playit_gg && \
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /app/key.pem -out /app/cert.pem \
    -subj "/CN=yourdomain.com" -days 36500

# =============================================
# 4. Copy configuration files
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
# 5. Expose ports & Environment Variables
# =============================================
EXPOSE 443 53/udp 10001 443/udp

ENV TUNNEL_TOKEN=""
ENV SECRET_KEY=""

# =============================================
# 6. Start services
# =============================================
CMD echo "[playit]" > /root/.config/playit_gg/playit.toml && \
    echo "secret_key = \"${SECRET_KEY}\"" >> /root/.config/playit_gg/playit.toml && \
    /usr/local/bin/xray -config /etc/xray/config.json & \
    /usr/local/bin/cloudflared tunnel --no-autoupdate run --token ${TUNNEL_TOKEN} & \
    /usr/local/bin/playit & \
    /usr/local/bin/hysteria server -c /app/hysteria.yaml & \
    /usr/local/openresty/bin/openresty -g "daemon off;"
