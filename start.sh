# start.sh ကို printf နဲ့ ဖန်တီးပါ (echo -e ထက် ပိုစိတ်ချရသည်)
RUN printf '#!/bin/sh\n\
/usr/local/bin/xray -config /etc/xray/config.json &\n\
sleep 2\n\
exec /usr/local/openresty/bin/openresty -g "daemon off;"\n' > /start.sh \
    && chmod +x /start.sh

CMD ["/start.sh"]
