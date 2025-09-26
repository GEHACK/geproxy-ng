#!/usr/bin/env bash
set -euo pipefail

# ----- load .env (same dir by default) -----
ENV_FILE="${ENV_FILE:-$(dirname "$0")/.env}"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || {
  echo "ERROR: .env not found at $ENV_FILE"; exit 1;
}

# Required vars from your .env
: "${PRIVATE_INTERFACE:?missing in .env}"   # e.g. br-tree
: "${ADMIN_INTERFACE:?missing in .env}"     # e.g. br-admin
: "${FOG_IP:?missing in .env}"              # e.g. 10.2.0.2

# WAN isn’t in your .env—set here or export WAN_INTERFACE in env
WAN="${WAN_INTERFACE:-wlp6s0}"

BR_TREE="$PRIVATE_INTERFACE"
BR_ADMIN="$ADMIN_INTERFACE"

# ----- helpers -----
have_rule() { iptables -t "$1" -C "$2" "${@:3}" 2>/dev/null; }
add_rule()  { have_rule "$1" "$2" "${@:3}" || iptables -t "$1" -A "$2" "${@:3}"; }
ins_rule()  { have_rule "$1" "$2" "${@:3}" || iptables -t "$1" -I "$2" 1 "${@:3}"; }
del_rule()  { have_rule "$1" "$2" "${@:3}" && iptables -t "$1" -D "$2" "${@:3}"; }

enable_forwarding() {
  sysctl -q -w net.ipv4.ip_forward=1 >/dev/null
}

apply_rules() {
  enable_forwarding

  add_rule nat POSTROUTING -o "$WAN" -j MASQUERADE

  add_rule filter FORWARD -i "$BR_TREE" -o "$WAN" -j ACCEPT
  add_rule filter FORWARD -i "$WAN" -o "$BR_TREE" -m state --state ESTABLISHED,RELATED -j ACCEPT

  add_rule filter FORWARD -i "$BR_ADMIN" -o "$WAN" -j ACCEPT
  add_rule filter FORWARD -i "$WAN" -o "$BR_ADMIN" -m state --state ESTABLISHED,RELATED -j ACCEPT

  add_rule filter FORWARD -i "$BR_ADMIN" -o "$BR_TREE" -j ACCEPT

  ins_rule filter FORWARD -i "$BR_TREE" -o "$BR_ADMIN" -d "$FOG_IP" -j ACCEPT
  add_rule filter INPUT -i "$BR_TREE" -d "$ADMIN_IP" -j DROP
  add_rule filter FORWARD -i "$BR_TREE" -o "$BR_ADMIN" -j DROP
}

enable_tree_internet() {
  del_rule filter FORWARD -i "$BR_TREE" -o "$WAN" -j DROP
  del_rule filter FORWARD -i "$WAN" -o "$BR_TREE" -m state --state ESTABLISHED,RELATED -j DROP
  add_rule filter FORWARD -i "$BR_TREE" -o "$WAN" -j ACCEPT
  add_rule filter FORWARD -i "$WAN" -o "$BR_TREE" -m state --state ESTABLISHED,RELATED -j ACCEPT
}

disable_tree_internet() {
  add_rule filter FORWARD -i "$BR_TREE" -o "$WAN" -j DROP
  add_rule filter FORWARD -i "$WAN" -o "$BR_TREE" -m state --state ESTABLISHED,RELATED -j DROP
  del_rule filter FORWARD -i "$BR_TREE" -o "$WAN" -j ACCEPT
  del_rule filter FORWARD -i "$WAN" -o "$BR_TREE" -m state --state ESTABLISHED,RELATED -j ACCEPT
}

status() {
  echo "== FORWARD =="
  iptables -L FORWARD -n -v --line-numbers | egrep -e "$BR_TREE|$BR_ADMIN|$WAN" || true
  echo
  echo "== NAT POSTROUTING =="
  iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "$WAN" || true
}

save_rules() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    sudo netfilter-persistent save
    echo "Saved to /etc/iptables/rules.v4"
  else
    echo "Tip: sudo netfilter-persistent save"
  fi
}

case "${1:-apply}" in
  apply)  apply_rules ;;
  status) status ;;
  save)   save_rules ;;
  enable-tree-internet)  enable_tree_internet ;;
  disable-tree-internet) disable_tree_internet ;;
  *)
    echo "Usage: $0 [apply|status|save|enable-tree-internet|disable-tree-internet]"
    echo "Use ENV_FILE=/path/.env to point at a different env file."
    exit 1
    ;;
esac

