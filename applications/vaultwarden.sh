#!/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Create directory
sudo mkdir -p /etc/selfhosted/vaultwarden

# Create Docker network
sudo docker network create --internal vaultwarden

# Create Docker volumes
sudo docker volume create vaultwarden

# Add Caddy to vaultwarden's network
sudo sed -i '/    networks:/a \      - vaultwarden' /etc/selfhosted/caddy/docker-compose.yml
sudo sed -i '/^networks:/a \  vaultwarden:' /etc/selfhosted/caddy/docker-compose.yml
sudo sed -i '/  vaultwarden:/a \    external: true' /etc/selfhosted/caddy/docker-compose.yml

################################################
##### Docker Compose
################################################

sudo tee /etc/selfhosted/vaultwarden/docker-compose.yml << EOF
services:
  vaultwarden:
    image: vaultwarden/server:alpine
    container_name: vaultwarden
    restart: always
    networks:
      - vaultwarden
    env_file:
      - config.env
    volumes:
      - vaultwarden:/data/

volumes:
  vaultwarden:
    external: true

networks:
  vaultwarden:
    external: true
EOF

################################################
##### Environment variables
################################################

sudo tee /etc/selfhosted/vaultwarden/config.env << EOF
ADMIN_TOKEN=$(openssl rand -hex 48)
WEBSOCKET_ENABLED=true
SIGNUPS_ALLOWED=true
INVITATIONS_ALLOWED=false
SHOW_PASSWORD_HINT=false
EOF

################################################
##### Caddyfile
################################################

sudo tee -a /etc/selfhosted/caddy/Caddyfile << EOF

# Vaultwarden
vault.${BASE_DOMAIN} {
        import default-header

        encode gzip

        # Vaultwarden HTTP server
        reverse_proxy vaultwarden:80 {
                header_up X-Real-IP {remote_host}
        }

        # Websockets server
        reverse_proxy /notifications/hub vaultwarden:3012 {
                header_up X-Real-IP {remote_host}
        }

        # Negotiation endpoint
        reverse_proxy /notifications/hub/negotiate vaultwarden:8080 {
                header_up X-Real-IP {remote_host}
        }
}
EOF