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