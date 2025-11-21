FROM docker.io/alpine:3.22.2

RUN apk update

RUN apk add dnscrypt-proxy dnscrypt-proxy-openrc

RUN apk add openssl && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 5000 -sha256 -keyout /etc/dnscrypt-proxy/localhost.pem -out /etc/dnscrypt-proxy/localhost.pem -subj "/"

ENTRYPOINT dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml