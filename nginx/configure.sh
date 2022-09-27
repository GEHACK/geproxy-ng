#!/bin/bash

# Remove default

# Enable default listen, if needed this gets overridden with ssl config
cat <<EOT >/etc/nginx/listen
listen 80;
listen [::]:80;
EOT

if [[ ! -f "$SSL_CERT_LOC" ]] | [[ ! -f "$SSL_KEY_LOC" ]]; then
  >&2 echo "Either \$SSL_CERT_LOC='$SSL_CERT_LOC', or \$SSL_KEY_LOC='$SSL_KEY_LOC' does not exist. Falling back to HTTP!"
  exit
fi

echo "Certificate found, attempting to configure SSL for $DOMAIN."

days=${SSL_CERT_MINIMUM_DAYS:-7}
secs=$(($days * 24 * 60 * 60))

# Check whether the certificate will expire in a week 7*24*60*60 = 604800
openssl x509 -noout -dates -checkend $secs <"$SSL_CERT_LOC" 1>/dev/null 2>&1

if [[ $? -ne 0 ]]; then
  >&2 echo "Certificate expires within ${days} days (${secs} seconds)! Falling back to HTTP!"
  exit
fi

echo "Certificate is valid for at least ${days} days".

# Check whether the key matches
# Check if EC cert, otherwise check for RSA
grep 'EC PRIVATE' gehack.nl.key 1>/dev/null 2>&1
if [[ $? ]]; then
  openssl x509 -in "$SSL_CERT_LOC" -noout -pubkey >/tmp/crt.pubkey 2>/dev/null
  openssl ec -in "$SSL_KEY_LOC" -pubout >/tmp/key.pubkey 2>/dev/null
else
  openssl x509 -noout -modulus -in "$SSL_CERT_LOC" | openssl md5 >/tmp/crt.pubkey
  openssl rsa -noout -modulus -in "$SSL_KEY_LOC" | openssl md5 >/tmp/key.pubkey
fi

# Check if there is a match
diff /tmp/key.pubkey /tmp/crt.pubkey >/dev/null
if [[ ! $? ]]; then
  >&2 echo 'Key and certificate appear to not belong together! Falling back to HTTP!'
  exit
fi

# Check for subdomains
names=$(openssl x509 -noout -ext subjectAltName <"$SSL_CERT_LOC" | grep -o -e "\([\*A-Za-z0-9_-]\.\)*$DOMAIN")
if [[ "${names}" == *"*.$DOMAIN"* ]]; then
  echo "Certificate contains wildcard, awesome!"
else
  # Check whether all subdomains are contained in the names
  readarray -td, subs <<<"$SUBDOMAINS,"
  unset 'subs[-1]'
  for f in "${subs[@]}"; do
    if [[ ! "${names}" == *"${f}.$DOMAIN"* ]]; then
      >&2 echo "Subdomain '${f}.$DOMAIN' not in certificate '$SSL_CERT_LOC'! Falling back to HTTP!"
      exit
    else
      echo "Subdomain '${f}.$DOMAIN' found in certificate '$SSL_CERT_LOC'."
    fi
  done
fi

# SSL certs appear to be valid
echo "Setting up SSL!"

# Add a http->https redirect
cat <<EOT >/etc/nginx/conf.d/redirect
server {
        listen   80 default_server;
        server_name _default_;
        return 308 https://\$host\$request_uri;  # enforce https
}
EOT

# Override the listen helper, note this is a basic ssl config and needs to be improved.
cat <<EOT >/etc/nginx/listen
listen   443 ssl http2;
listen   [::]:443 ssl http2;

ssl_certificate $SSL_CERT_LOC;
ssl_certificate_key $SSL_KEY_LOC;

ssl_session_timeout 5m;
ssl_prefer_server_ciphers on;

add_header Strict-Transport-Security max-age=31556952;

send_timeout 36000s;

EOT
