#!/bin/bash
# lib/check.sh — итоговые проверки

run_checks() {
    local ROLE=$1
    echo ""
    echo "=== FINAL CHECK: $ROLE ==="

    echo -e "\n[hostname]"
    hostname -f 2>/dev/null || hostname

    echo -e "\n[ip -br a]"
    ip -br a

    echo -e "\n[маршруты]"
    ip r

    echo -e "\n[ip_forward]"
    sysctl net.ipv4.ip_forward 2>/dev/null || echo "?"

    if [[ "$ROLE" == *"rtr"* ]]; then
        echo -e "\n[GRE туннель]"
        ip tunnel show 2>/dev/null || true
        echo -e "\n[nftables]"
        nft list ruleset 2>/dev/null | head -20 || true
        echo -e "\n[OSPF соседи]"
        vtysh -c "show ip ospf neighbor" 2>/dev/null || echo "vtysh — проверь вручную"
    fi

    if [[ "$ROLE" == "hq-rtr" ]]; then
        echo -e "\n[DHCP статус]"
        systemctl is-active dhcpd 2>/dev/null || true
    fi

    if [[ "$ROLE" == "hq-srv" ]]; then
        echo -e "\n[DNS проверка]"
        named-checkconf 2>/dev/null && echo "named.conf: OK" || echo "named.conf: FAIL"
        dig @127.0.0.1 hq-rtr.au-team.irpo +short 2>/dev/null || true
    fi

    echo ""
    echo "=== ГОТОВО: $ROLE ==="
    return 0
}
