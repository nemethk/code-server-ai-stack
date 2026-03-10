#!/bin/sh
# Generate a self-signed TLS certificate on first startup if one does not
# exist in the persisted /etc/nginx/certs volume, then start nginx.
set -eu

CERT_DIR="/etc/nginx/certs"
CERT_FILE="${CERT_DIR}/nginx.crt"
KEY_FILE="${CERT_DIR}/nginx.key"
DOMAIN="${DOMAIN:-localhost}"

if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
    echo "[nginx] Generating self-signed TLS certificate for: ${DOMAIN}"
    mkdir -p "${CERT_DIR}"

    openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:4096 \
        -keyout "${KEY_FILE}" \
        -out "${CERT_FILE}" \
        -subj "/C=US/ST=Local/L=Local/O=WebAI/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1"

    chmod 600 "${KEY_FILE}"
    chmod 644 "${CERT_FILE}"
    echo "[nginx] Certificate written to ${CERT_FILE}"
else
    echo "[nginx] Using existing TLS certificate"
fi

# Validate config before starting
nginx -t

echo "[nginx] Starting..."
exec nginx -g "daemon off;"
