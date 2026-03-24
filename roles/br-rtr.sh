#!/bin/bash
# roles/br-rtr.sh — BR-RTR: WAN, LAN, GRE, OSPF, NAT

apt-get update -y
apt-get install -y frr nftables

enable_forward
enable_persistence
setup_base_security "br-rtr"

set_ip_safe "$BR_WAN_IP" "$IF_WAN" "$BR_GW"
set_ip_safe "$BR_LAN_IP" "$IF_LAN"

# GRE-туннель (пункт 6 ТЗ)
setup_gre_persistent "172.16.1.1" "172.16.2.1" "$TUN_BR"

# OSPF (пункт 7 ТЗ)
sed -i 's/^#\?ospfd=.*/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr
sleep 2

vtysh \
  -c "configure terminal" \
  -c "router ospf" \
  -c "passive-interface default" \
  -c "no passive-interface gre1" \
  -c "network 10.5.5.0/30 area 0" \
  -c "network 192.168.1.0/28 area 0" \
  -c "exit" \
  -c "interface gre1" \
  -c "ip ospf authentication message-digest" \
  -c "ip ospf message-digest-key 1 md5 ${OSPF_PASS}" \
  -c "exit" \
  -c "end" \
  -c "write memory" \
  || echo "[WARN] vtysh OSPF — проверь вручную"

# NAT + DNAT (пункты 8, модуль 2)
setup_nat_with_dnat "$IF_WAN" "192.168.1.1"
