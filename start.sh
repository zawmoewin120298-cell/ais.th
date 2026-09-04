# start.sh ဖန်တီးပုံကို ဒီလိုပြောင်းပါ
RUN echo -e '#!/bin/sh\n/usr/local/bin/xray -config /etc/xray/config.json &\n/usr/local/openresty/bin/openresty -g "daemon off;"' > /start.sh \
    && chmod +x /start.sh

CMD ["/start.sh"]
