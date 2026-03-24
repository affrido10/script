#!/bin/bash
# roles/hq-cli.sh — HQ-CLI: СТРОГО DHCP (пункт 9 ТЗ)

setup_base_security "hq-cli"

CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${IF_MAIN}$" | head -1 | cut -d: -f1)
[ -z "$CON" ] && CON="$IF_MAIN"

nmcli con mod "$CON" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv6.method disabled
nmcli con up "$CON"
echo "[OK] HQ-CLI: DHCP включён на $IF_MAIN"
echo "     Ожидаемый адрес: 192.168.0.33-192.168.0.45"
echo "     (DHCP-сервер должен работать на HQ-RTR)"
