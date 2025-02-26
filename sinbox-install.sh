#!/bin/sh

# Проверка доступности репозитория OpenWRT
check_repo() {
    printf "\033[32;1mChecking OpenWrt repo availability...\033[0m\n"
    opkg update | grep -q "Failed to download" && printf "\033[32;1mopkg failed. Check internet or date. Command for force ntp sync: ntpd -p ptbtime1.ptb.de\033[0m\n" && exit 1
}

# Настройка маршрутизации для Sing-Box
add_routing_tables() {
    printf "\033[32;1mConfigure routing tables\033[0m\n"
    grep -q "98 ru_table" /etc/iproute2/rt_tables || echo '98 ru_table' >> /etc/iproute2/rt_tables
    grep -q "99 vpn_table" /etc/iproute2/rt_tables || echo '99 vpn_table' >> /etc/iproute2/rt_tables

    ip rule add fwmark 0x1 lookup ru_table 2>/dev/null || true
    ip rule add fwmark 0x2 lookup vpn_table 2>/dev/null || true

    ip route add default dev eth1 table ru_table 2>/dev/null || true
    ip route add default dev tun0 table vpn_table 2>/dev/null || true
}

# Добавление правила маркировки трафика
add_mark() {
    printf "\033[32;1mConfigure mark rules\033[0m\n"
    # Маркировка трафика для ru_domains
    if ! uci show network | grep "mark='0x1'"; then
        uci add network rule
        uci set network.@rule[-1].name='mark_ru_domains'
        uci set network.@rule[-1].mark='0x1'
        uci set network.@rule[-1].priority='100'
        uci set network.@rule[-1].lookup='ru_table'
        uci commit
    fi

    # Маркировка трафика для остального трафика
    if ! uci show network | grep "mark='0x2'"; then
        uci add network rule
        uci set network.@rule[-1].name='mark_other_traffic'
        uci set network.@rule[-1].mark='0x2'
        uci set network.@rule[-1].priority='110'
        uci set network.@rule[-1].lookup='vpn_table'
        uci commit
    fi
}

# Добавление правил для внутренних доменов (Россия)
add_internal_domains() {
    if uci show firewall | grep -q "@ipset.*name='ru_domains'"; then
        printf "\033[32;1mSet already exist\033[0m\n"
    else
        printf "\033[32;1mCreate set\033[0m\n"
        uci add firewall ipset
        uci set firewall.@ipset[-1].name='ru_domains'
        uci set firewall.@ipset[-1].match='dst_net'
        uci commit firewall
    fi
    if uci show firewall | grep -q "@rule.*name='mark_ru_domains'"; then
        printf "\033[32;1mRule for set already exist\033[0m\n"
    else
        printf "\033[32;1mCreate rule set\033[0m\n"
        uci add firewall rule
        uci set firewall.@rule[-1]=rule
        uci set firewall.@rule[-1].name='mark_ru_domains'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='*'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].ipset='ru_domains'
        uci set firewall.@rule[-1].set_mark='0x1'
        uci set firewall.@rule[-1].target='MARK'
        uci set firewall.@rule[-1].family='ipv4'
        uci commit firewall
    fi

    # Маркировка остального трафика
    if ! uci show firewall | grep -q "@rule.*name='mark_other_domains'"; then
        printf "\033[32;1mCreate rule for marking other domains\033[0m\n"
        uci add firewall rule
        uci set firewall.@rule[-1]=rule
        uci set firewall.@rule[-1].name='mark_other_domains'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='*'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].set_mark='0x2'
        uci set firewall.@rule[-1].target='MARK'
        uci set firewall.@rule[-1].family='ipv4'
        uci commit firewall
    fi
}

# Настройка Sing-Box
configure_singbox() {
    printf "\033[32;1mConfigure Sing-box\033[0m\n"
    if opkg list-installed | grep -q sing-box; then
        echo "Sing-box already installed"
    else
        AVAILABLE_SPACE=$(df / | awk 'NR>1 { print $4 }')
        if [ "$AVAILABLE_SPACE" -gt 2000 ]; then
            echo "Installed sing-box"
            opkg install sing-box
        else
            printf "\033[31;1mNo free space for a sing-box. Sing-box is not installed.\033[0m\n"
            exit 1
        fi
    fi
    # Включение Sing-Box в конфигурации
    if grep -q "option enabled '0'" /etc/config/sing-box; then
        sed -i "s/	option enabled \'0\'/	option enabled \'1\'/" /etc/config/sing-box
    fi
    # Настройка пользователя
    if grep -q "option user 'sing-box'" /etc/config/sing-box; then
        sed -i "s/	option user \'sing-box\'/	option user \'root\'/" /etc/config/sing-box
    fi
    # Создание конфигурационного файла
    if grep -q "tun0" /etc/sing-box/config.json; then
        printf "\033[32;1mConfig /etc/sing-box/config.json already exists\033[0m\n"
    else
        cat << 'EOF' > /etc/sing-box/config.json
{
  "log": {
    "level": "debug"
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "tun0",
      "domain_strategy": "ipv4_only",
      "address": ["172.16.250.1/30"],
      "auto_route": false,
      "strict_route": false,
      "sniff": true 
   }
  ],
  "outbounds": [
    {
      "type": "vmess",
      "server": "example.com",
      "server_port": 443,
      "uuid": "your-uuid-here",
      "security": "auto"
    }
  ],
  "route": {
    "auto_detect_interface": true
  }
}
EOF
    printf "\033[32;1mCreate template config in /etc/sing-box/config.json. Edit it manually.\033[0m\n"
    fi
}

# Настройка зоны файрвола
add_zone() {
    if uci show firewall | grep -q "@zone.*name='singbox'"; then
        printf "\033[32;1mZone already exist\033[0m\n"
    else
        printf "\033[32;1mCreate zone\033[0m\n"
        uci add firewall zone
        uci set firewall.@zone[-1].name='singbox'
        uci set firewall.@zone[-1].device='tun0'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall
    fi
    if uci show firewall | grep -q "@forwarding.*name='singbox-lan'"; then
        printf "\033[32;1mForwarding already configured\033[0m\n"
    else
        printf "\033[32;1mConfigured forwarding\033[0m\n"
        uci add firewall forwarding
        uci set firewall.@forwarding[-1]=forwarding
        uci set firewall.@forwarding[-1].name='singbox-lan'
        uci set firewall.@forwarding[-1].dest='singbox'
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].family='ipv4'
        uci commit firewall
    fi
}

# Настройка DNS через dnsmasq-full
dnsmasqfull() {
    if opkg list-installed | grep -q dnsmasq-full; then
        printf "\033[32;1mdnsmasq-full already installed\033[0m\n"
    else
        printf "\033[32;1mInstalled dnsmasq-full\033[0m\n"
        cd /tmp/ && opkg download dnsmasq-full
        opkg remove dnsmasq && opkg install ./dnsmasq-full*.ipk
        [ -f /etc/config/dhcp-opkg ] && cp /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
}

# Настройка confdir для dnsmasq
dnsmasqconfdir() {
    if uci get dhcp.@dnsmasq[0].confdir | grep -q /tmp/dnsmasq.d; then
        printf "\033[32;1mconfdir already set\033[0m\n"
    else
        printf "\033[32;1mSetting confdir\033[0m\n"
        uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
        uci commit dhcp
    fi
}

# Настройка Stubby для защиты DNS
add_dns_resolver() {
    echo "Configure Stubby for DNS over TLS"
    if opkg list-installed | grep -q stubby; then
        printf "\033[32;1mStubby already installed\033[0m\n"
    else
        printf "\033[32;1mInstalling Stubby...\033[0m\n"
        opkg install stubby
        if ! opkg list-installed | grep -q stubby; then
            printf "\033[31;1mError: failed to install Stubby\033[0m\n"
            exit 1
        fi
    fi
    printf "\033[32;1mConfiguring Dnsmasq to use Stubby\033[0m\n"
    uci set dhcp.@dnsmasq[0].noresolv="1"
    uci -q delete dhcp.@dnsmasq[0].server
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5453"
    uci add_list dhcp.@dnsmasq[0].server='/use-application-dns.net/'
    uci commit dhcp
    printf "\033[32;1mRestarting Dnsmasq...\033[0m\n"
    /etc/init.d/dnsmasq restart
}

# Создание скрипта для обновления доменов
add_getdomains() {
    # Установка drill
    if opkg list-installed | grep -q drill; then
        echo "drill already installed"
    else
        AVAILABLE_SPACE=$(df / | awk 'NR>1 { print $4 }')
        if [ "$AVAILABLE_SPACE" -gt 200 ]; then
            echo "Installed drill"
            opkg install drill
        else
            printf "\033[31;1mNo free space for a drill. Drill is not installed.\033[0m\n"
            exit 1
        fi
    fi
    # Создаем файл ru-доменами, потом его можно редактировать
    printf "\033[32;1mCreate conf file /etc/domains.conf\033[0m\n"
    echo "yandex.ru mail.ru vk.com mos.ru gosuslugi.ru ozon.ru gov.ru kremlin.ru mosenergosbyt.ru" > /etc/domains.conf
    printf "\033[32;1mCreate script /etc/init.d/getdomains\033[0m\n"
    cat << 'EOF' > /etc/init.d/getdomains
	#!/bin/sh /etc/rc.common
	START=99
	start () {
    # Читаем домены из файла
    DOMAINS=$(cat /etc/domains.conf | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
    TMP_FILE="/tmp/dnsmasq.d/ru_domains.lst"
    > "$TMP_FILE"

    for DOMAIN in $DOMAINS; do
        echo "Processing domain: $DOMAIN"
        # Разрешаем основной домен
        IP_ADDRESSES=$(drill +short "$DOMAIN" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
        if [ -n "$IP_ADDRESSES" ]; then
            for IP in $IP_ADDRESSES; do
                echo "ipset=/#$DOMAIN/$IP" >> "$TMP_FILE"
            done
        else
            echo "Failed to resolve domain: $DOMAIN" >&2
        fi

        # Разрешаем поддомены через wildcard
        SUBDOMAINS=$(drill +short "*.$DOMAIN" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
        if [ -n "$SUBDOMAINS" ]; then
            for SUB_IP in $SUBDOMAINS; do
                echo "ipset=/#*.$DOMAIN/$SUB_IP" >> "$TMP_FILE"
            done
        else
            echo "No subdomains found for: $DOMAIN" >&2
        fi
    done

    # Проверяем синтаксис конфигурации dnsmasq
    if dnsmasq --conf-file="$TMP_FILE" --test 2>&1 | grep -q "syntax check OK"; then
        mv "$TMP_FILE" /tmp/dnsmasq.d/ru_domains.lst
        /etc/init.d/dnsmasq restart
    else
        echo "Error: Invalid dnsmasq configuration. Check the domains list." >&2
        rm -f "$TMP_FILE"
    fi
}
EOF
    chmod +x /etc/init.d/getdomains
    /etc/init.d/getdomains enable

    # Добавляем задачу в cron
    if ! crontab -l | grep -q /etc/init.d/getdomains; then
        crontab -l | { cat; echo "0 */8	/etc/init.d/getdomains start"; } | crontab -
    fi

    printf "\033[32;1mStart script\033[0m\n"
    /etc/init.d/getdomains start
}

# Перехватываем весь DNS-трафик
add_dns_interception() {
    printf "\033[32;1mConfigure DNS interception via firewall\033[0m\n"

    # Проверяем, существует ли уже правило для перехвата DNS
    if uci show firewall | grep -q "@redirect.*name='dns_redirect'"; then
        printf "\033[32;1mDNS interception rule already exists\033[0m\n"
    else
        printf "\033[32;1mCreating DNS interception rule\033[0m\n"

        # Добавляем правило перенаправления DNS
        uci add firewall redirect
        uci set firewall.@redirect[-1].name='dns_redirect'
        uci set firewall.@redirect[-1].src='lan'
        uci set firewall.@redirect[-1].proto='udp'
        uci set firewall.@redirect[-1].src_dport='53'
        uci set firewall.@redirect[-1].dest_port='53'
        uci set firewall.@redirect[-1].target='DNAT'
        uci set firewall.@redirect[-1].family='ipv4'

        # Сохраняем изменения
        uci commit firewall

        printf "\033[32;1mDNS interception rule added successfully\033[0m\n"
    fi
}

printf "\033[31;1mAll actions performed here cannot be rolled back automatically.\033[0m\n"

# Выполнение функций
check_repo
dnsmasqfull
dnsmasqconfdir
configure_singbox
add_mark
add_zone
add_routing_tables
add_dns_resolver
add_getdomains
add_internal_domains
add_dns_interception

# Перезапуск служб
printf "\033[32;1mRestart network\033[0m\n"
/etc/init.d/network restart
printf "\033[32;1mDone\033[0m\n"
