FROM alpine:3

RUN apk -U add dnsmasq inotify-tools libintl gettext bind-tools
RUN rm -rf /var/cache/apk/*
RUN touch /etc/dnsmasq.conf.template

# DNS
EXPOSE 53/udp
# DHCP
EXPOSE 67/udp
# TFTP
EXPOSE 69/udp

CMD ["/bin/sh", "-c", "(/usr/bin/envsubst < /etc/dnsmasq.conf.template | tee /etc/dnsmasq.conf) && /usr/sbin/dnsmasq -k -q"]
