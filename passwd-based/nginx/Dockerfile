FROM nginx:alpine

# openssl is not included in nginx:alpine; needed to generate the self-signed cert
RUN apk add --no-cache openssl

COPY nginx.conf    /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cert directory – will be backed by a named Docker volume
RUN mkdir -p /etc/nginx/certs

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
