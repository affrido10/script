#!/bin/bash
# roles/isp.sh — ISP: DHCP WAN, статика к роутерам, NAT, forwarding

setup_base_security "isp"

# WAN — DHCP (пункт 2 ТЗ)
CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${IF_WAN}$" | head -1 | cut -d: -f1)
if [ -z "$CON" ]; then
    nmcli con add type ethernet ifname "$IF_WAN" con-name "$IF_WAN" \
        ipv4.method auto ipv6.method disabled
    CON="$IF_WAN"
fi
nmcli con mod "$CON" ipv4.method auto ipv4.gateway "" ipv6.method disabled
nmcli con up "$CON"
echo "[OK] $IF_WAN: DHCP"

# Статика на линках к роутерам
set_ip_safe "$ISP_HQ_IP" "$IF_HQ"
set_ip_safe "$ISP_BR_IP" "$IF_BR"

# Forwarding + NAT
enable_forward
setup_nat "$IF_WAN"
