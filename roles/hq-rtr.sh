#!/bin/bash
# roles/hq-rtr.sh — HQ-RTR: WAN, OVS+VLAN, DHCP, GRE, OSPF, NAT

apt-get update -y
apt-get install -y openvswitch frr dhcp-server nftables

enable_forward
enable_persistence
setup_base_security "hq-rtr"

# WAN
set_ip_safe "$HQ_WAN_IP" "$IF_WAN" "$HQ_GW"

# OVS — один физический порт, три VLAN (пункт 4 ТЗ)
systemctl enable --now openvswitch
ovs-vsctl --may-exist add-br br0
ovs-vsctl --may-exist add-port br0 "$IF_LAN"
ip link set "$IF_LAN" up
ip link set br0 up

for V in 100 200 999; do
    ovs-vsctl --may-exist add-port br0 "vlan${V}" \
        "tag=${V}" -- set interface "vlan${V}" type=internal
    ip link set "vlan${V}" up 2>/dev/null || true
done

set_ip_safe "$V100_IP" vlan100
set_ip_safe "$V200_IP" vlan200
set_ip_safe "$V999_IP" vlan999

# Скрипт восстановления OVS-адресов после перезагрузки
cat > /root/ovs-restore.sh << EOF
#!/bin/bash
ip link set br0 up
for V in 100 200 999; do ip link set vlan\$V up; done
ip addr add $V100_IP dev vlan100 2>/dev/null || true
ip addr add $V200_IP dev vlan200 2>/dev/null || true
ip addr add $V999_IP dev vlan999 2>/dev/null || true
EOF
chmod +x /root/ovs-restore.sh
grep -qF "ovs-restore" /etc/rc.local || \
    sed -i "/exit 0/i bash /root/ovs-restore.sh" /etc/rc.local

# DHCP для HQ-CLI на vlan200 (пункт 9 ТЗ)
cat > /etc/dhcp/dhcpd.conf << 'DHCPEOF'
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet 192.168.0.32 netmask 255.255.255.240 {
    range 192.168.0.33 192.168.0.45;
    option routers 192.168.0.46;
    option domain-name-servers 192.168.0.1;
    option domain-name "au-team.irpo";
}
DHCPEOF

echo 'DHCPDARGS="vlan200"' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd
echo "[OK] DHCP: vlan200, диапазон .33-.45, DNS=192.168.0.1"

# GRE-туннель (пункт 6 ТЗ)
setup_gre_persistent "172.16.2.1" "172.16.1.1" "$TUN_HQ"

# OSPF через FRR (пункт 7 ТЗ)
# ВАЖНО: объявляем только конкретные подсети, не весь /24
# passive-interface default + только gre1 активен
sed -i 's/^#\?ospfd=.*/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr
sleep 2

vtysh \
  -c "configure terminal" \
  -c "router ospf" \
  -c "passive-interface default" \
  -c "no passive-interface gre1" \
  -c "network 10.5.5.0/30 area 0" \
  -c "network 192.168.0.0/27 area 0" \
  -c "network 192.168.0.32/28 area 0" \
  -c "network 192.168.0.48/29 area 0" \
  -c "exit" \
  -c "interface gre1" \
  -c "ip ospf authentication message-digest" \
  -c "ip ospf message-digest-key 1 md5 ${OSPF_PASS}" \
  -c "exit" \
  -c "end" \
  -c "write memory" \
  || echo "[WARN] vtysh OSPF — проверь вручную: vtysh -c 'show ip ospf neighbor'"

# NAT + DNAT (пункты 8, модуль 2)
setup_nat_with_dnat "$IF_WAN" "192.168.0.1"
