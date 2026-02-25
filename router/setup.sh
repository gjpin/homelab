# Update list of available packages
opkg update

# Install common packages
opkg install \
    gawk \
    grep \
    sed \
    coreutils-sort \
    nano

################################################
##### DNS over HTTPS
################################################

# References:
# https://openwrt.org/docs/guide-user/services/dns/dnscrypt_dnsmasq_dnscrypt-proxy2

# Install DNSCrypt Proxy
opkg install dnscrypt-proxy2

# Enable DNS encryption
service dnsmasq stop
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].cachesize='0'
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server="127.0.0.53"
uclient-fetch https://raw.githubusercontent.com/gjpin/homelab/refs/heads/main/router/configs/dnscrypt-proxy.toml -O /etc/dnscrypt-proxy2/dnscrypt-proxy.toml
uci commit dhcp
service dnsmasq start
service dnscrypt-proxy restart

# Ensure, that the NTP server can work without DNS
uci del system.ntp.server
uci add_list system.ntp.server='194.177.4.1'    # 0.openwrt.pool.ntp.org
uci add_list system.ntp.server='213.222.217.11' # 1.openwrt.pool.ntp.org
uci add_list system.ntp.server='80.50.102.114'  # 2.openwrt.pool.ntp.org
uci add_list system.ntp.server='193.219.28.60'  # 3.openwrt.pool.ntp.org
uci commit system

# Disable ISP's DNS server
uci set network.wan.peerdns='0'
uci set network.wan6.peerdns='0'
uci commit network

# Divert-DNS, port 53
uci add firewall redirect
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].target='DNAT'
uci set firewall.@redirect[-1].name='Divert-DNS, port 53'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].src_dport='53'
uci set firewall.@redirect[-1].dest_port='53'
uci commit firewall

# Block DNS-over-TLS over port 853
uci add firewall rule
uci set firewall.@rule[-1].name='Reject-DoT,port 853'
uci add_list firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].dest_port='853'
uci set firewall.@rule[-1].target='REJECT'
uci commit firewall

# Redirect queries for DNS servers running on non-standard ports. For example: 5353
uci add firewall redirect
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].target='DNAT'
uci set firewall.@redirect[-1].name='Divert-DNS, port 5353'
uci set firewall.@redirect[-1].src='lan'
uci set firewall.@redirect[-1].src_dport='5353'
uci set firewall.@redirect[-1].dest_port='53'
uci commit firewall

# Reload firewall
/etc/init.d/firewall reload

################################################
##### Adblock-lean
################################################

# References:
# https://github.com/lynxthecat/adblock-lean

# Install adblock-lean
uclient-fetch https://raw.githubusercontent.com/lynxthecat/adblock-lean/master/abl-install.sh -O /tmp/abl-install.sh
sh /tmp/abl-install.sh -v release

# Add more lists
sed -i 's/^raw_block_lists.*/raw_block_lists="hagezi:pro.plus hagezi:fake hagezi:tif hagezi:dyndns hagezi:native.amazon hagezi:native.apple hagezi:native.lgwebos hagezi:native.samsung hagezi:native.winoffice hagezi:native.xiaomi oisd:big"/' /etc/adblock-lean/config
sed -i 's/^hosts_block_lists.*/hosts_block_lists="stevenblack:base"/' /etc/adblock-lean/config

# Restart adblock-lean
service adblock-lean restart

# creates:
# /etc/init.d/adblock-lean
# /usr/lib/adblock-lean/abl-lib.sh
# /usr/lib/adblock-lean/abl-process.sh
# /etc/adblock-lean/config
# changes:
# /etc/config/dhcp

# Enable blocklist compression
# uci add_list dhcp.@dnsmasq[0].addnmount='/bin/busybox'
# uci add_list dhcp.@dnsmasq[0].addnmount='/var/run/adblock-lean/abl-blocklist.gz'
# uci commit dhcp
# service dnsmasq restart

################################################
##### Adblock-Fast
################################################

# References:
# https://github.com/lynxthecat/adblock-lean

# Upgrade from dnsmasq to dnsmasq-full
# cd /tmp/
# opkg download dnsmasq-full
# opkg install ipset libnettle8 libnetfilter-conntrack3

# opkg remove dnsmasq
# opkg install dnsmasq-full --cache /tmp/
# rm -f /tmp/dnsmasq-full*.ipk;

# Install packages
# opkg install \
#     adblock-fast \
#     luci-app-adblock-fast

################################################
##### WireGuard
################################################

# References:
# https://openwrt.org/docs/guide-user/services/vpn/wireguard/server

# Install packages
opkg install \
    wireguard-tools \
    luci-proto-wireguard

# Configure firewall
uci rename firewall.@zone[0]="lan"
uci rename firewall.@zone[1]="wan"
uci del_list firewall.lan.network="${VPN_IF}"
uci add_list firewall.lan.network="${VPN_IF}"
uci -q delete firewall.wg
uci set firewall.wg="rule"
uci set firewall.wg.name="Allow-WireGuard"
uci set firewall.wg.src="wan"
uci set firewall.wg.dest_port="${VPN_PORT}"
uci set firewall.wg.proto="udp"
uci set firewall.wg.target="ACCEPT"
uci commit firewall
service firewall restart

# Configure network
uci -q delete network.${VPN_IF}
uci set network.${VPN_IF}="interface"
uci set network.${VPN_IF}.proto="wireguard"
uci set network.${VPN_IF}.private_key="${VPN_KEY}"
uci set network.${VPN_IF}.listen_port="${VPN_PORT}"
uci add_list network.${VPN_IF}.addresses="${VPN_ADDR}"
uci add_list network.${VPN_IF}.addresses="${VPN_ADDR6}"
 
# Add VPN peers
uci -q delete network.wgclient
uci set network.wgclient="wireguard_${VPN_IF}"
uci set network.wgclient.public_key="${VPN_PUB}"
uci set network.wgclient.preshared_key="${VPN_PSK}"
uci add_list network.wgclient.allowed_ips="${VPN_ADDR%.*}.2/32"
uci add_list network.wgclient.allowed_ips="${VPN_ADDR6%:*}:2/128"
uci commit network
service network restart