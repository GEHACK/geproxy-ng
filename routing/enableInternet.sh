#!/bin/bash


set -a
source ../.env
set +a

if [[ ! $(iptables -t nat -C POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE 1>/dev/null 2>&1) ]]; then
  #iptables -t nat -A POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE
  echo 'Add masquarade'
fi

if [[ ! $(iptables FORWARD -i $PUBLIC_INTERFACE -o $PUBLIC_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 1>/dev/null 2>&1) ]]; then
  #iptables -A FORWARD -i $PUBLIC_INTERFACE -o $PUBLIC_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
  echo 'Add forward to public'
fi

if [[ ! $(iptables -C FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j ACCEPT 1>/dev/null 2>&1) ]]; then
  #iptables -A FORWARD -i $PRIVATE_INTERFACE -o $PUBLIC_INTERFACE -j ACCEPT
  echo 'Add forward to private'
fi


#echo 1 > /proc/sys/net/ipv4/ip_forward

