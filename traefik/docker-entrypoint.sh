#!/bin/sh
set -euo pipefail

TPL="/etc/traefik/dynamic.yml"
TMP="/tmp/dynamic.tmpl.yml"

if [ -f "$TPL" ]; then
    cp "$TPL" "$TMP"
    envsubst <"$TMP" >"$TPL"
fi

exec traefik "$@"
