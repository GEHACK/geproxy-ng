#!/bin/bash

# Enable default listen, if needed this gets overridden with ssl config
cat <<EOT >/etc/nginx/listen
listen 80;
listen [::]:80;
EOT

if [[ ! -f "/etc/nginx/ssl/${DOMAIN}.key" ]] | [[ ! -f "/etc/nginx/ssl/${DOMAIN}.crt" ]]; then
  >&2 echo "Either '${DOMAIN}.key', or '${DOMAIN}.crt' does not exist. Falling back to HTTP!"
  exit
fi

echo "Certificate found, attempting to configure SSL for ${DOMAIN}."

days=${SSL_CERT_MINIMUM_DAYS:-7}
secs=$(($days * 24 * 60 * 60))

# Check whether the certificate will expire in a week 7*24*60*60 = 604800
openssl x509 -noout -dates -checkend $secs <"/etc/nginx/ssl/$DOMAIN.crt" 1>/dev/null 2>&1

if [[ $? -ne 0 ]]; then
  >&2 echo "Certificate expires within ${days} days (${secs} seconds)! Falling back to HTTP!"
  exit
fi

echo "Certificate is valid for at least ${days} days".

# Check whether the key matches
# Check if EC cert, otherwise check for RSA
grep 'EC PRIVATE' "/etc/nginx/ssl/${DOMAIN}.key" 1>/dev/null 2>&1
if [[ $? ]]; then
  openssl x509 -in "/etc/nginx/ssl/${DOMAIN}.crt" -noout -pubkey >/tmp/crt.pubkey 2>/dev/null
  openssl ec -in "/etc/nginx/ssl/${DOMAIN}.key" -pubout >/tmp/key.pubkey 2>/dev/null
else
  openssl x509 -noout -modulus -in "/etc/nginx/ssl/${DOMAIN}.crt" | openssl md5 >/tmp/crt.pubkey
  openssl rsa -noout -modulus -in "/etc/nginx/ssl/${DOMAIN}.key" | openssl md5 >/tmp/key.pubkey
fi

# Check if there is a match
diff /tmp/key.pubkey /tmp/crt.pubkey >/dev/null
if [[ ! $? ]]; then
  >&2 echo 'Key and certificate appear to not belong together! Falling back to HTTP!'
  exit
fi

# Check for subdomains
names=$(openssl x509 -noout -ext subjectAltName <"/etc/nginx/ssl/${DOMAIN}.crt" | grep -o -e "\([\*A-Za-z0-9_-]\.\)*${DOMAIN}")
if [[ "${names}" == *"*.${DOMAIN}"* ]]; then
  echo "Certificate contains wildcard, awesome!"
else
  # Check whether all subdomains are contained in the names
  readarray -td, subs <<<"$SUBDOMAINS,"
  unset 'subs[-1]'
  for f in "${subs[@]}"; do
    if [[ ! "${names}" == *"${f}.${DOMAIN}"* ]]; then
      >&2 echo "Subdomain '${f}.${DOMAIN}' not in certificate '/etc/nginx/ssl/${DOMAIN}.crt'! Falling back to HTTP!"
      exit
    else
      echo "Subdomain '${f}.${DOMAIN}' found in certificate '/etc/nginx/ssl/${DOMAIN}.crt'."
    fi
  done
fi

# SSL certs appear to be valid
echo "Setting up SSL!"

# Add a http->https redirect
cat <<"EOT" >/etc/nginx/conf.d/redirect
server {
        listen   80 default_server;
        server_name _default_;
        return 308 https://$host$request_uri;  # enforce https
}
EOT

# Override the listen helper, note this is a basic ssl config and needs to be improved.
cat <<EOT >/etc/nginx/listen
listen   443 ssl;
listen   [::]:443 ssl;
http2    on;

ssl_certificate /etc/nginx/ssl/${DOMAIN}.crt;
ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;

ssl_session_timeout 5m;
ssl_prefer_server_ciphers on;

add_header Strict-Transport-Security max-age=31556952;

send_timeout 36000s;

EOT
