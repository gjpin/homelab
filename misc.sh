################################################
##### Port forward attempts
################################################

# Forward ports for Pi-Hole (5353 -> 53)
# sudo firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p udp -o lo --dport 53 -j REDIRECT --to-ports 5353
# sudo firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 53 -j REDIRECT --to-ports 5353

# Forward ports for Caddy (4443 -> 443)
# sudo firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 443 -j REDIRECT --to-ports 4443
# sudo firewall-cmd --permanent --direct --remove-rule ipv4 nat PREROUTING 0 -p tcp --dport 443 -j REDIRECT --to-ports 4443
# sudo iptables -t nat -I PREROUTING -p udp -m udp --dport 443 -j REDIRECT --to-ports 4443
# sudo iptables -t nat -I PREROUTING -p tcp -m tcp --dport 443 -j REDIRECT --to-ports 4443
# sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 4443

# sudo firewall-cmd --permanent --direct --add-rule \
#     ipv4 nat OUTPUT 0 -o lo -p tcp --dport 443 -j REDIRECT --to-port 4443
# sudo firewall-cmd --reload

# sudo sysctl -w net.ipv4.conf.enp34s0.route_localnet=1

# Forward traffic of privileged ports
# sudo firewall-cmd --permanent --zone=FedoraServer --add-forward-port=port=443:proto=tcp:toport=4443
# sudo firewall-cmd --permanent --zone=FedoraServer --add-forward-port=port=53:proto=tcp:toport=5353
# sudo firewall-cmd --permanent --zone=FedoraServer --add-forward-port=port=53:proto=udp:toport=5353


export BASE_DOMAIN=
export DATA_PATH=/data/containers
export BACKUP_PATH=/backup/containers

# Update containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml pull
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml pull

# Shutdown containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml down

# Start containers
docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/radicale/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/syncthing/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/vaultwarden/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/immich/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/gitea/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/librechat/docker/docker-compose.yml up --force-recreate -d


export BASE_DOMAIN=
export DATA_PATH=$HOME/containers


docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml build --pull --no-cache
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml build --pull --no-cache

docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml down
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml down

docker compose -f ${DATA_PATH}/caddy/docker/docker-compose.yml up --force-recreate -d
docker compose -f ${DATA_PATH}/pihole/docker/docker-compose.yml up --force-recreate -d
