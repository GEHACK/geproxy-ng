FROM alpine:3

RUN apk -U add dnsmasq inotify-tools libintl gettext
RUN rm -rf /var/cache/apk/*

EXPOSE 53/udp
EXPOSE 69

VOLUME ["/dnsmasq.conf"]

CMD "envsubst < /dnsmasq.conf > /etc/dnsmasq.conf && dnsmasq -k -q"
