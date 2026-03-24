#!/bin/bash
# lib/net.sh — IP, forwarding, GRE, NAT
# ИСПРАВЛЕНИЕ: именно здесь была проблема с интернетом на других машинах.
# Роутеры теперь явно добавляют маршрут по умолчанию И включают forward ДО NAT.

enable_forward() {
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-routing.conf
    # Alt Linux также читает /etc/net/sysctl.conf
    if [ -f /etc/net/sysctl.conf ]; then
        grep -q "ip_forward" /etc/net/sysctl.conf || \
            echo "net.ipv4.ip_forward=1" >> /etc/net/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1
    echo "[OK] IP forwarding включён"
}

set_ip_safe() {
    local ADDR=$1
    local IFACE=$2
    local GW=${3:-}

    if ! ip link show "$IFACE" &>/dev/null; then
        echo "[WARN] Интерфейс '$IFACE' не найден — пропускаю"
        echo "       Доступные: $(ip -br link | awk '{print $1}' | grep -v lo | tr '\n' ' ')"
        return 0
    fi

    if [ "$USE_NM" = true ]; then
        local CON
        CON=$(nmcli -t -f NAME,DEVICE con show | grep ":${IFACE}$" | head -1 | cut -d: -f1)
        if [ -z "$CON" ]; then
            nmcli con add type ethernet ifname "$IFACE" con-name "$IFACE" \
                ipv4.method manual ipv4.addresses "$ADDR" ipv6.method disabled
            CON="$IFACE"
        fi
        nmcli con mod "$CON" ipv4.method manual ipv4.addresses "$ADDR" ipv6.method disabled
        if [ -n "$GW" ]; then
            nmcli con mod "$CON" ipv4.gateway "$GW"
        else
            nmcli con mod "$CON" ipv4.gateway ""
        fi
        nmcli con up "$CON"
    else
        # Без NM — ip команды + rc.local
        ip addr flush dev "$IFACE" 2>/dev/null || true
        ip addr add "$ADDR" dev "$IFACE" 2>/dev/null || true
        ip link set "$IFACE" up

        # Маршрут по умолчанию — КРИТИЧНО для интернета
        if [ -n "$GW" ]; then
            ip route replace default via "$GW" 2>/dev/null || true
        fi

        # Персистентность через rc.local
        enable_persistence
        local ESC_ADDR="${ADDR//\//\\/}"
        grep -qF "addr add $ADDR dev $IFACE" /etc/rc.local || \
            sed -i "/exit 0/i ip link set $IFACE up\nip addr add $ADDR dev $IFACE 2>/dev/null || true" /etc/rc.local
        if [ -n "$GW" ]; then
            grep -qF "default via $GW" /etc/rc.local || \
                sed -i "/exit 0/i ip route replace default via $GW 2>/dev/null || true" /etc/rc.local
        fi
    fi

    echo "[OK] $IFACE → $ADDR${GW:+  GW: $GW}"
}

setup_gre_persistent() {
    local REMOTE=$1
    local LOCAL=$2
    local TUN_IP=$3

    ip tunnel del gre1 2>/dev/null || true
    ip tunnel add gre1 mode gre remote "$REMOTE" local "$LOCAL"
    ip addr add "$TUN_IP" dev gre1 2>/dev/null || true
    ip link set gre1 up

    enable_persistence
    grep -qF "tunnel add gre1" /etc/rc.local || sed -i "/exit 0/i \
ip tunnel del gre1 2>/dev/null; ip tunnel add gre1 mode gre remote $REMOTE local $LOCAL; ip addr add $TUN_IP dev gre1 2>/dev/null; ip link set gre1 up" \
        /etc/rc.local

    echo "[OK] GRE gre1: $LOCAL → $REMOTE  IP: $TUN_IP"
}

setup_nat() {
    local WAN_IF=$1

    command -v nft &>/dev/null || apt-get install -y nftables

    mkdir -p /etc/nftables
    cat > /etc/nftables/nftables.nft << EOF
#!/usr/sbin/nft -f
flush ruleset

table ip filter {
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "$WAN_IF" masquerade
    }
}
EOF

    systemctl enable nftables
    systemctl restart nftables 2>/dev/null || nft -f /etc/nftables/nftables.nft
    echo "[OK] NAT masquerade на $WAN_IF"
}

# NAT + проброс портов для модуля 2 (пункты 8)
setup_nat_with_dnat() {
    local WAN_IF=$1
    local SRV_IP=$2

    command -v nft &>/dev/null || apt-get install -y nftables

    mkdir -p /etc/nftables
    cat > /etc/nftables/nftables.nft << EOF
#!/usr/sbin/nft -f
flush ruleset

table ip filter {
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "$WAN_IF" tcp dport 8080 dnat to ${SRV_IP}:8080
        iifname "$WAN_IF" tcp dport 2026 dnat to ${SRV_IP}:2026
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "$WAN_IF" masquerade
    }
}
EOF

    systemctl enable nftables
    systemctl restart nftables 2>/dev/null || nft -f /etc/nftables/nftables.nft
    echo "[OK] NAT + DNAT (8080, 2026 → $SRV_IP) на $WAN_IF"
}
