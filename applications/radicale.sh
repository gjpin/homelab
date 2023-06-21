#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# References:
# https://radicale.org/v3.html#basic-configuration
# https://caddy.community/t/radicale-reverse-proxy-caddy-2-0/8580/5

# Create directory
sudo mkdir -p /etc/selfhosted/radicale

# Create Docker network
sudo docker network create radicale

# Create Docker volumes
sudo docker volume create radicale

################################################
##### Dockerfile
################################################

sudo tee /etc/selfhosted/radicale/Dockerfile << EOF
FROM alpine:edge

RUN apk add --update --no-cache radicale py3-bcrypt

ENTRYPOINT ["radicale"]
EOF

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/radicale/docker-compose.yml << EOF
services:
  radicale:
    build:
      context: /etc/selfhosted/radicale
    container_name: radicale
    restart: always
    networks:
      - radicale
      - caddy
    volumes:
      - /etc/selfhosted/radicale/users:/etc/radicale/users
      - /etc/selfhosted/radicale/config:/etc/radicale/config
      - radicale:/var/lib/radicale/collections

volumes:
  radicale:
    external: true

networks:
  radicale:
    external: true
  caddy:
    external: true
EOF

################################################
##### Configuration
################################################

# Install dependencies
sudo apt install -y apache2-utils

# Create user
PASSWORD=$(openssl rand -hex 48)
sudo htpasswd -c -b -B /etc/selfhosted/radicale/users admin ${PASSWORD}

# Create configuration
sudo tee /etc/selfhosted/radicale/config << EOF
[auth]
type = htpasswd
htpasswd_filename = /etc/radicale/users
htpasswd_encryption = bcrypt

[server]
hosts = 0.0.0.0:5232, [::]:5232
EOF

################################################
##### Caddyfile
################################################

sudo tee -a /etc/selfhosted/caddy/Caddyfile << EOF

# Radicale - Contacts/Calendar
contacts.${BASE_DOMAIN} {
        import default-header

        encode gzip

        reverse_proxy radicale:5232 {
                header_up X-Real-IP {remote_host}
        }
}
EOF