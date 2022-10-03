#!/bin/bash

set -a
source ../.env
set +a

if [[ -z "$PRIVATE_INTERFACE" ]] || [[ -z "$PUBLIC_INTERFACE" ]]; then
  echo 'Either $PUBLIC_INTERFACE or $PRIVATE_INTERFACE has not been set in the environment'
  exit 1
fi

echo 'Attempting to enable forwarding'

iptables -C FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j ACCEPT 1>/dev/null 2>&1
if [[ ! $? ]]; then
  echo 'Add forward to public'
  iptables -A FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j ACCEPT
else
  echo "To public ($PRIVATE_INTERFACE -> $PUBLIC_INTERFACE) forwarding already setup"
fi


iptables -C FORWARD -i  $PUBLIC_INTERFACE -o $PRIVATE_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 1>/dev/null 2>&1
if [[ ! $? ]]; then
  echo 'Add forward to private'
  iptables -A FORWARD -i  $PUBLIC_INTERFACE -o $PRIVATE_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
else
  echo "To private ($PUBLIC_INTERFACE -> $PRIVATE_INTERFACE) forwarding already setup"
fi

iptables -t nat -C POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE 1>/dev/null 2>&1
if [[ ! $? ]]; then
  echo 'Add masquarade'
  iptables -t nat -A POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE
else
  echo "Masquarading (NAT) forwarding already setup"
fi



## TODO this needs to be replaced with
#    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf && sysctl -p
#    but an idempotent variation

#echo 1 > /proc/sys/net/ipv4/ip_forward

