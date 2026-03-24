#!/bin/bash
set -e

[[ $EUID -ne 0 ]] && echo "Запускай от root: sudo $0 <роль>" && exit 1

ROLE=$1
[ -z "$ROLE" ] && echo "Usage: sudo ./setup.sh <isp|hq-rtr|br-rtr|hq-srv|hq-cli|br-srv>" && exit 1

CONF="iface_${ROLE}.env"

if [ ! -f "$CONF" ]; then
    echo ""
    echo "=== НАСТРОЙКА ИНТЕРФЕЙСОВ ДЛЯ: $ROLE ==="
    ip -br link show | grep -v lo
    echo ""
    case "$ROLE" in
        isp)
            read -p "WAN интерфейс (к интернету/провайдеру): " W
            read -p "Интерфейс к HQ-RTR: " H
            read -p "Интерфейс к BR-RTR: " B
            echo -e "IF_WAN=$W\nIF_HQ=$H\nIF_BR=$B" > "$CONF"
            ;;
        hq-rtr)
            read -p "WAN интерфейс (к ISP): " W
            read -p "LAN интерфейс (trunk к коммутатору): " L
            echo -e "IF_WAN=$W\nIF_LAN=$L" > "$CONF"
            ;;
        br-rtr)
            read -p "WAN интерфейс (к ISP): " W
            read -p "LAN интерфейс (к BR-SRV): " L
            echo -e "IF_WAN=$W\nIF_LAN=$L" > "$CONF"
            ;;
        *)
            read -p "Основной интерфейс: " M
            echo "IF_MAIN=$M" > "$CONF"
            ;;
    esac
    echo "[OK] Сохранено в $CONF"
fi

source ./inventory.env
source "$CONF"
source lib/core.sh
source lib/net.sh
source lib/dns.sh
source lib/check.sh

# Роутеры работают без NetworkManager
if [[ "$ROLE" == *"rtr"* ]]; then
    echo "[INFO] Роутер — отключаю NetworkManager"
    systemctl stop NetworkManager 2>/dev/null || true
    systemctl disable NetworkManager 2>/dev/null || true
    USE_NM=false
else
    command -v nmcli >/dev/null 2>&1 && USE_NM=true || USE_NM=false
fi

echo ""
echo "============================================================"
echo "  au-team | Модуль 1 | Роль: $ROLE"
echo "============================================================"
echo ""

source "roles/${ROLE}.sh"
run_checks "$ROLE"
