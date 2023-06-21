#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# References:
# https://github.com/pi-hole/docker-pi-hole/
# https://docs.pi-hole.net/guides/dns/unbound/#setting-up-pi-hole-as-a-recursive-dns-server-solution
# https://nlnetlabs.nl/documentation/unbound/howto-anchor/
# https://wiki.alpinelinux.org/wiki/Setting_up_unbound_DNS_server
# https://wiki.archlinux.org/title/unbound

# Create directory
sudo mkdir -p /etc/selfhosted/pihole

# Create Docker network
sudo docker network create pihole

# Create Docker volumes
sudo docker volume create pihole

# Disable the DNSStubListener to unbind it from port 53
sudo sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf

# # Set new symbolic link for resolv.conf
# sudo rm /etc/resolv.conf
# ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Restart systemd-resolved
sudo systemctl restart systemd-resolved

# Import dnsmasq's configuration file
sudo mkdir -p /etc/selfhosted/pihole/dnsmasq.d
sudo tee /etc/selfhosted/pihole/dnsmasq.d/99-edns.conf << EOF
edns-packet-max=1232
EOF

################################################
##### Dockerfile
################################################

# sudo mkdir -p /etc/selfhosted/pihole/cloudflared
# sudo tee /etc/selfhosted/pihole/cloudflared/Dockerfile << EOF
# FROM alpine:edge

# RUN apk update \
#     apk add wget && \
#     mkdir -p /usr/local/bin && \
#     wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 && \
#     mv -f ./cloudflared-linux-arm64 /usr/local/bin/cloudflared && \
#     chmod +x /usr/local/bin/cloudflared

# ENTRYPOINT cloudflared proxy-dns --port 53 --upstream https://cloudflare-dns.com/dns-query --upstream https://dns.google/dns-query --upstream https://dns.quad9.net/dns-query --upstream https://doh.opendns.com/dns-query --upstream https://doh.cleanbrowsing.org/doh/security-filter
# EOF

sudo mkdir -p /etc/selfhosted/pihole/dnscrypt
sudo tee /etc/selfhosted/pihole/dnscrypt/Dockerfile << EOF
FROM alpine:edge

RUN apk update && \
    apk add dnscrypt-proxy dnscrypt-proxy-openrc && \
    sed -i "s|^listen_addresses.*$|listen_addresses = ['0.0.0.0:53']|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^doh_servers.*$|doh_servers = true|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^dnscrypt_servers.*$|dnscrypt_servers = false|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml && \
    sed -i "s|^require_dnssec.*$|require_dnssec = true|g" /etc/dnscrypt-proxy/dnscrypt-proxy.toml

ENTRYPOINT dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml
EOF

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/pihole/docker-compose.yml << EOF
services:
  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: always
    networks:
      - pihole
      - caddy
    ports:
      - 53:53/tcp
      - 53:53/udp
    env_file:
      - config.env
    depends_on:
      - pihole-dnscrypt
    volumes:
      - pihole:/etc/pihole
      - /etc/selfhosted/pihole/dnsmasq.d:/etc/dnsmasq.d
      - /etc/selfhosted/pihole/custom.list:/etc/pihole/custom.list

  pihole-dnscrypt:
    build:
      context: /etc/selfhosted/pihole/dnscrypt
    container_name: pihole-dnscrypt
    restart: always
    networks:
      - pihole

  # pihole-cloudflared:
  #   build:
  #     context: /etc/selfhosted/pihole/cloudflared
  #   container_name: pihole-cloudflared
  #   restart: always
  #   networks:
  #     - pihole

#  pihole-unbound:
#    image: alpinelinux/unbound:latest
#    container_name: pihole-unbound
#    restart: always
#    networks:
#      - pihole
#    volumes:
#      - /etc/selfhosted/pihole/unbound/unbound.conf:/etc/unbound/unbound.conf
#      - /etc/selfhosted/pihole/unbound/root.hints:/etc/unbound/root.hints

volumes:
  pihole:
    external: true

networks:
  pihole:
    external: true
  caddy:
    external: true
EOF

################################################
##### Environment variables
################################################

sudo tee /etc/selfhosted/pihole/config.env << EOF
ADMIN_TOKEN=$(openssl rand -hex 48)
WEBPASSWORD=$(openssl rand -hex 48)
FTLCONF_LOCAL_IPV4=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
TZ=$(cat /etc/timezone)
VIRTUAL_HOST=pihole.${BASE_DOMAIN}
DNSMASQ_LISTENING=all
PIHOLE_DNS_=pihole-dnscrypt#53
DNSSEC=false
DNSMASQ_USER=root
EOF

sudo tee /etc/selfhosted/pihole/custom.list << EOF
10.0.0.1 contacts.${BASE_DOMAIN}
10.0.0.1 obsidian.${BASE_DOMAIN}
10.0.0.1 photos.${BASE_DOMAIN}
10.0.0.1 pihole.${BASE_DOMAIN}
10.0.0.1 syncthing.${BASE_DOMAIN}
10.0.0.1 vault.${BASE_DOMAIN}
10.0.0.1 webdav.${BASE_DOMAIN}
EOF

################################################
##### Unbound configuration
################################################

# # Download root DNS servers
# sudo mkdir -p /etc/selfhosted/pihole/unbound

# sudo wget -O /etc/selfhosted/pihole/unbound/root.hints https://www.internic.net/domain/named.root

# # Import Unbound's configuration file
# sudo tee /etc/selfhosted/pihole/unbound/unbound.conf << EOF
# server:
#     # If no logfile is specified, syslog is used
#     # logfile: "/var/log/unbound/unbound.log"
#     verbosity: 0

#     # Listen on all interfaces (localhost and docker bridge network)
#     interface: 0.0.0.0
#     port: 53
#     do-ip4: yes
#     do-udp: yes
#     do-tcp: yes

#     # Access control (allow localhost and docker bridge network)
#     access-control: 127.0.0.0/8 allow
#     access-control: 172.16.0.0/12 allow

#     # May be set to yes if you have IPv6 connectivity
#     do-ip6: no

#     # You want to leave this to no unless you have *native* IPv6. With 6to4 and
#     # Terredo tunnels your web browser should favor IPv4 for the same reasons
#     prefer-ip6: no

#     # Query root DNS servers
#     root-hints: "/etc/unbound/root.hints"

#     # Enable DNSSEC
#     auto-trust-anchor-file: "/etc/unbound/root.key"

#     # Trust glue only if it is within the server's authority
#     harden-glue: yes

#     # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
#     harden-dnssec-stripped: yes

#     # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
#     # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
#     use-caps-for-id: no

#     # Reduce EDNS reassembly buffer size.
#     # IP fragmentation is unreliable on the Internet today, and can cause
#     # transmission failures when large DNS messages are sent via UDP. Even
#     # when fragmentation does work, it may not be secure; it is theoretically
#     # possible to spoof parts of a fragmented DNS message, without easy
#     # detection at the receiving end. Recently, there was an excellent study
#     # >>> Defragmenting DNS - Determining the optimal maximum UDP response size for DNS <<<
#     # by Axel Koolhaas, and Tjeerd Slokker (https://indico.dns-oarc.net/event/36/contributions/776/)
#     # in collaboration with NLnet Labs explored DNS using real world data from the
#     # the RIPE Atlas probes and the researchers suggested different values for
#     # IPv4 and IPv6 and in different scenarios. They advise that servers should
#     # be configured to limit DNS messages sent over UDP to a size that will not
#     # trigger fragmentation on typical network links. DNS servers can switch
#     # from UDP to TCP when a DNS response is too big to fit in this limited
#     # buffer size. This value has also been suggested in DNS Flag Day 2020.
#     edns-buffer-size: 1232

#     # Perform prefetching of close to expired message cache entries
#     # This only applies to domains that have been frequently queried
#     prefetch: yes

#     # One thread should be sufficient, can be increased on beefy machines. In reality for most users running on small networks or on a single machine, it should be unnecessary to seek performance enhancement by increasing num-threads above 1.
#     num-threads: 1

#     # Ensure kernel buffer is large enough to not lose messages in traffic spikes
#     so-rcvbuf: 1m

#     # Ensure privacy of local IP ranges
#     # 100.64.0.0/10 is tailscale
#     private-address: 192.168.0.0/16
#     private-address: 169.254.0.0/16
#     private-address: 172.16.0.0/12
#     private-address: 10.0.0.0/8
#     private-address: 100.64.0.0/10
#     private-address: fd00::/8
#     private-address: fe80::/10

#     # This attempts to reduce latency by serving the outdated record before
#     # updating it instead of the other way around. Alternative is to increase
#     # cache-min-ttl to e.g. 3600.
#     cache-min-ttl: 0
#     serve-expired: yes

#     msg-cache-size: 8m
#     rrset-cache-size: 16m

# remote-control:
#     # Enable remote control with unbound-control(8) here.
#     # set up the keys and certificates with unbound-control-setup.
#     control-enable: yes
   
#     # what interfaces are listened to for remote control.
#     # give 0.0.0.0 and ::0 to listen to all interfaces.
#     control-interface: 127.0.0.1
   
#     # port number for remote control operations.
#     control-port: 8953
   
#     # unbound server key file.
#     server-key-file: "/etc/unbound/unbound_server.key"
   
#     # unbound server certificate file.
#     server-cert-file: "/etc/unbound/unbound_server.pem"
   
#     # unbound-control key file.
#     control-key-file: "/etc/unbound/unbound_control.key"
   
#     # unbound-control certificate file.
#     control-cert-file: "/etc/unbound/unbound_control.pem"
# EOF

# # Update Unbound root hints weekly
# sudo tee /etc/systemd/system/unbound-root-hints.service << EOF
# [Unit]
# Description=Automatically update Unbound root hints

# [Service]
# Type=oneshot
# ExecStart=/usr/bin/wget -O /etc/selfhosted/pihole/unbound/root.hints https://www.internic.net/domain/named.root
# EOF

# sudo tee /etc/systemd/system/unbound-root-hints.timer << EOF
# [Unit]
# Description=Automatically update Unbound root hints
# RefuseManualStart=no
# RefuseManualStop=no

# [Timer]
# Unit=unbound-root-hints.service
# OnCalendar=Sat *-*-* 04:00:00

# [Install]
# WantedBy=timers.target
# EOF

# sudo systemctl daemon-reload
# sudo systemctl enable unbound-root-hints.timer

################################################
##### Caddyfile
################################################

sudo tee -a /etc/selfhosted/caddy/Caddyfile << EOF

# Pi-hole
pihole.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy pihole:80 {
                header_up X-Real-IP {remote_host}
        }
}
EOF