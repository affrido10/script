#!/bin/bash
# lib/dns.sh — DNS bind на HQ-SRV (пункт 10)

setup_dns() {
    apt-get install -y bind bind-utils 2>/dev/null || \
    apt-get install -y bind9 bind9utils 2>/dev/null || true

    mkdir -p /etc/bind/zone

    local NAMED_CONF=""
    for p in /etc/named.conf /etc/bind/named.conf; do
        [ -f "$p" ] && NAMED_CONF="$p" && break
    done
    [ -z "$NAMED_CONF" ] && NAMED_CONF="/etc/named.conf" && touch "$NAMED_CONF"

    # options: форвардеры (идемпотентно)
    if ! grep -q "forwarders" "$NAMED_CONF"; then
        sed -i "/options {/a \        forwarders { $DNS_FWD; };\n        forward only;\n        allow-query { any; };\n        recursion yes;\n        dnssec-validation no;" "$NAMED_CONF"
    fi

    # Зона прямого просмотра (Таблица 3 ТЗ)
    cat > /etc/bind/zone/au-team.irpo << 'EOF'
$TTL 1D
@ IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
    2026010101 12H 1H 1W 1H )
  IN NS hq-srv.au-team.irpo.

hq-srv  IN A 192.168.0.1
hq-rtr  IN A 192.168.0.30
hq-cli  IN A 192.168.0.34
br-rtr  IN A 192.168.1.14
br-srv  IN A 192.168.1.1
docker  IN A 172.16.1.14
web     IN A 172.16.2.14
EOF

    # Обратная зона HQ (PTR для hq-srv, hq-rtr, hq-cli)
    cat > /etc/bind/zone/db.0.168.192 << 'EOF'
$TTL 1D
@ IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
    2026010101 12H 1H 1W 1H )
  IN NS hq-srv.au-team.irpo.

1   IN PTR hq-srv.au-team.irpo.
30  IN PTR hq-rtr.au-team.irpo.
34  IN PTR hq-cli.au-team.irpo.
EOF

    # Обратная зона BR
    cat > /etc/bind/zone/db.1.168.192 << 'EOF'
$TTL 1D
@ IN SOA hq-srv.au-team.irpo. admin.au-team.irpo. (
    2026010101 12H 1H 1W 1H )
  IN NS hq-srv.au-team.irpo.

1   IN PTR br-srv.au-team.irpo.
14  IN PTR br-rtr.au-team.irpo.
EOF

    cat > /etc/bind/named.conf.local << 'EOF'
zone "au-team.irpo" {
    type master;
    file "/etc/bind/zone/au-team.irpo";
};
zone "0.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/zone/db.0.168.192";
};
zone "1.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/zone/db.1.168.192";
};
EOF

    grep -qF "named.conf.local" "$NAMED_CONF" || \
        echo 'include "/etc/bind/named.conf.local";' >> "$NAMED_CONF"

    chown -R named:named /etc/bind/zone 2>/dev/null || \
    chown -R bind:bind /etc/bind/zone 2>/dev/null || true

    named-checkconf && echo "[OK] named.conf синтаксис OK" || echo "[WARN] named-checkconf нашёл ошибки"

    systemctl enable named 2>/dev/null || systemctl enable bind9 2>/dev/null || true
    systemctl restart named 2>/dev/null || systemctl restart bind9 2>/dev/null || true
    echo "[OK] DNS: bind запущен, зоны au-team.irpo + PTR"
}
