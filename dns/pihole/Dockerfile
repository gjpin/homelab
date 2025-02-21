FROM docker.io/alpine:3.21.3

RUN apk update

RUN apk add dnscrypt-proxy dnscrypt-proxy-openrc && \
    sed -i "s|^listen_addresses.*$|listen_addresses = ['0.0.0.0:53']|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^doh_servers.*$|doh_servers = true|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^dnscrypt_servers.*$|dnscrypt_servers = false|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^require_dnssec.*$|require_dnssec = true|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^# lb_strategy.*$|lb_strategy = 'p10'|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^# listen_addresses.*$|listen_addresses = ['0.0.0.0:3000']|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^# path.*$|path = '/dns-query'|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^# cert_file.*$|cert_file = '/etc/dnscrypt-proxy/localhost.pem'|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^# cert_key_file .*$|cert_key_file = '/etc/dnscrypt-proxy/localhost.pem'|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml

RUN apk add openssl && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 5000 -sha256 -keyout /etc/dnscrypt-proxy/localhost.pem -out /etc/dnscrypt-proxy/localhost.pem -subj "/"

ENTRYPOINT dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml