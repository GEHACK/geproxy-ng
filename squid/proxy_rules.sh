#!/usr/bin/env bash
set -euo pipefail

# --- adjustable ---
LAN_IFS=(br-tree)          # interfaces receiving client traffic
WAN_IF=""                  # optionally disable rp_filter here too, e.g. WAN_IF=wlan0
SQUID_HTTP_PORT=3128
SQUID_HTTPS_TPROXY_PORT=3129
MARK_HEX=0x1
TABLE_ID=100
TABLE_NAME="squid"
# -------------------

cmd=${1:-}
[[ "$cmd" == "up" || "$cmd" == "down" ]] || { echo "Usage: $0 {up|down}"; exit 1; }

mark_dec=$((MARK_HEX))  # decimal for ip rule show
exists() { iptables "$@" -C >/dev/null 2>&1; }

if [[ "$cmd" == "up" ]]; then
  echo "[*] Load kernel modules"
  for m in xt_TPROXY nf_tproxy_ipv4 nf_tproxy_core xt_socket nf_conntrack; do
    modprobe "$m" 2>/dev/null || true
  done

  echo "[*] Sysctls: ip_forward, ip_nonlocal_bind, rp_filter off"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sysctl -w net.ipv4.ip_nonlocal_bind=1 >/dev/null
  for k in all default lo; do
    sysctl -w net.ipv4.conf.${k}.rp_filter=0 >/dev/null || true
  done
  for IF in "${LAN_IFS[@]}"; do
    sysctl -w net.ipv4.conf.${IF}.rp_filter=0 >/dev/null || true
  done
  if [[ -n "${WAN_IF}" ]]; then
    sysctl -w net.ipv4.conf.${WAN_IF}.rp_filter=0 >/dev/null || true
  fi

  echo "[*] Ensure routing table ${TABLE_ID} ${TABLE_NAME}"
  grep -qE "^\s*${TABLE_ID}\s+${TABLE_NAME}\b" /etc/iproute2/rt_tables 2>/dev/null || \
    echo "${TABLE_ID} ${TABLE_NAME}" >> /etc/iproute2/rt_tables

  echo "[*] Policy routing (fwmark ${mark_dec} -> table ${TABLE_ID})"
  ip -4 rule del fwmark "${mark_dec}" lookup "${TABLE_ID}" 2>/dev/null || true
  ip -4 rule add fwmark "${mark_dec}" lookup "${TABLE_ID}"
  ip -4 route replace local 0.0.0.0/0 dev lo table "${TABLE_ID}"

  echo "[*] mangle/DIVERT chain"
  iptables -t mangle -N DIVERT 2>/dev/null || true
  # ensure exactly one MARK+ACCEPT in DIVERT
  iptables -t mangle -F DIVERT
  iptables -t mangle -A DIVERT -j MARK --set-mark "${mark_dec}"
  iptables -t mangle -A DIVERT -j ACCEPT

  for IF in "${LAN_IFS[@]}"; do
    echo "[*] ${IF}: HTTPS TPROXY -> ${SQUID_HTTPS_TPROXY_PORT}"
    exists -t mangle -A PREROUTING -i "${IF}" -p tcp --dport 443 -m socket -j DIVERT || \
      iptables -t mangle -A PREROUTING -i "${IF}" -p tcp --dport 443 -m socket -j DIVERT
    exists -t mangle -A PREROUTING -i "${IF}" -p tcp --dport 443 -j TPROXY --on-port "${SQUID_HTTPS_TPROXY_PORT}" --tproxy-mark "${MARK_HEX}/${MARK_HEX}" || \
      iptables -t mangle -A PREROUTING -i "${IF}" -p tcp --dport 443 -j TPROXY --on-port "${SQUID_HTTPS_TPROXY_PORT}" --tproxy-mark "${MARK_HEX}/${MARK_HEX}"

    echo "[*] ${IF}: HTTP REDIRECT -> ${SQUID_HTTP_PORT}"
    exists -t nat -A PREROUTING -i "${IF}" -p tcp --dport 80 -j REDIRECT --to-ports "${SQUID_HTTP_PORT}" || \
      iptables -t nat -A PREROUTING -i "${IF}" -p tcp --dport 80 -j REDIRECT --to-ports "${SQUID_HTTP_PORT}"
  done

  echo "[*] (optional) block QUIC/UDP 443 on LAN IFs"
  for IF in "${LAN_IFS[@]}"; do
    exists -t mangle -A PREROUTING -i "${IF}" -p udp --dport 443 -j DROP || \
      iptables -t mangle -A PREROUTING -i "${IF}" -p udp --dport 443 -j DROP
  done

  echo "[*] Done."
  exit 0
fi

# ---------- down ----------
echo "[*] Removing policy routing"
ip -4 rule del fwmark "${mark_dec}" lookup "${TABLE_ID}" 2>/dev/null || true
ip -4 route flush table "${TABLE_ID}" 2>/dev/null || true

echo "[*] Flushing iptables rules"
for IF in "${LAN_IFS[@]}"; do
  iptables -t nat    -D PREROUTING -i "${IF}" -p tcp --dport 80  -j REDIRECT --to-ports "${SQUID_HTTP_PORT}" 2>/dev/null || true
  iptables -t mangle -D PREROUTING -i "${IF}" -p tcp --dport 443 -m socket -j DIVERT 2>/dev/null || true
  iptables -t mangle -D PREROUTING -i "${IF}" -p tcp --dport 443 -j TPROXY --on-port "${SQUID_HTTPS_TPROXY_PORT}" --tproxy-mark "${MARK_HEX}/${MARK_HEX}" 2>/dev/null || true
  iptables -t mangle -D PREROUTING -i "${IF}" -p udp --dport 443 -j DROP 2>/dev/null || true
done
iptables -t mangle -F DIVERT 2>/dev/null || true
iptables -t mangle -X DIVERT 2>/dev/null || true
echo "[*] Done."

