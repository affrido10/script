#!/bin/bash
# lib/core.sh — hostname, timezone, пользователи, SSH

setup_base_security() {
    local R=$1

    # Hostname: ISP без домена (по гайду), все остальные с FQDN
    if [ "$R" == "isp" ]; then
        hostnamectl set-hostname "isp"
    else
        hostnamectl set-hostname "${R}.au-team.irpo"
    fi
    echo "[OK] Hostname: $(hostname)"

    timedatectl set-timezone "$TZ"
    echo "[OK] Timezone: $TZ"

    # Пользователи по пункту 3 ТЗ
    if [ "$R" == "hq-srv" ] || [ "$R" == "br-srv" ]; then
        U="sshuser"; UID_V=2026
    else
        U="net_admin"; UID_V=1001
    fi

    if id "$U" &>/dev/null; then
        echo "[INFO] Пользователь $U уже есть — обновляю пароль"
    else
        useradd -m -u $UID_V -s /bin/bash "$U" 2>/dev/null || \
        useradd -m -s /bin/bash "$U"
        echo "[OK] Создан: $U (UID=$UID_V)"
    fi
    echo "$U:P@ssw0rd" | chpasswd
    echo "$U ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$U"
    chmod 440 "/etc/sudoers.d/$U"
    echo "[OK] $U: пароль P@ssw0rd, sudo без пароля"

    # SSH — только для серверов (пункт 5 ТЗ)
    if [ "$R" == "hq-srv" ] || [ "$R" == "br-srv" ]; then
        _configure_ssh
    fi
}

_configure_ssh() {
    # Найти sshd_config (Alt Linux: /etc/openssh/ или /etc/ssh/)
    local SSHD=""
    for p in /etc/openssh/sshd_config /etc/ssh/sshd_config; do
        [ -f "$p" ] && SSHD="$p" && break
    done
    if [ -z "$SSHD" ]; then
        echo "[WARN] sshd_config не найден — пропускаю SSH"
        return 0
    fi

    # Идемпотентно правим ключевые параметры
    sed -i 's/^#\?Port .*/Port 2026/' "$SSHD"

    for opt in "AllowUsers sshuser" "MaxAuthTries 2" "Banner /etc/banner" "PasswordAuthentication yes"; do
        key="${opt%% *}"
        # Убрать старую строку (закомментированную или нет), добавить новую
        sed -i "/^#\?${key} /d" "$SSHD"
        echo "$opt" >> "$SSHD"
    done

    echo "Authorized access only" > /etc/banner
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    echo "[OK] SSH: порт 2026, AllowUsers sshuser, MaxAuthTries 2, баннер"
}

enable_persistence() {
    if [ ! -f /etc/rc.local ]; then
        printf '#!/bin/bash\nexit 0\n' > /etc/rc.local
        chmod +x /etc/rc.local
    fi
    systemctl enable rc-local 2>/dev/null || true
    systemctl start rc-local 2>/dev/null || true
}
