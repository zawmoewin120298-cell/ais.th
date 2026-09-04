FROM igorbarinov/openresty-nginx-module-vts

# =============================================
# 1. Network Optimization
# =============================================
RUN echo "net.core.somaxconn = 1024" >> /etc/sysctl.conf && \
    echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_max_syn_backlog = 1024" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_keepalive_time = 300" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_keepalive_intvl = 60" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_keepalive_probes = 5" >> /etc/sysctl.conf

# =============================================
# 2. Install Xray
# =============================================
RUN apk --no-cache add curl unzip \
    && curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm xray.zip \
    && apk del curl unzip

# =============================================
# 3. Create directories
# =============================================
RUN mkdir -p /etc/xray /cache /usr/local/openresty/nginx/html

# =============================================
# 4. Copy configuration files
# =============================================
COPY ./config.json /etc/xray/config.json
COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./nginx_edge.conf /usr/local/openresty/nginx/conf/nginx_edge.conf
COPY ./generic_conf/ /usr/local/openresty/nginx/conf/generic_conf/
COPY ./src/ /usr/local/openresty/nginx/src/

# =============================================
# 5. Copy Website HTML (အမည်အသစ်)
# =============================================
COPY ./my-website/ /usr/local/openresty/nginx/html/

RUN chmod 755 /cache

# =============================================
# 6. Expose ports
# =============================================
EXPOSE 443 53/udp 10001

# =============================================
# 7. Start services
# =============================================
CMD /usr/local/bin/xray -config /etc/xray/config.json & /usr/local/openresty/bin/openresty -g "daemon off;"
