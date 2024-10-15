#!/bin/bash
# modules/create_ssh_banner.sh

create_ssh_banner_script() {
    log "INFO" "Создание динамического скрипта приветствия при входе по SSH..."

    # Проверяем, что переменная 'banner_script_path' задана
    if [[ -z "$banner_script_path" ]]; then
        error_exit "Переменная 'banner_script_path' не установлена."
    fi

    # Создаем скрипт баннера
    cat << 'EOF' > "$banner_script_path"
#!/bin/bash

# Загрузка процессора
cpu_load=$(awk '{print $1}' /proc/loadavg)

# Использование памяти
read -r mem_total mem_used <<< $(free -m | awk '/Mem:/ {print $2" "$3}')
mem_usage=$(awk "BEGIN {printf \"%.2f%%\", ($mem_used/$mem_total)*100}")

# Использование SWAP
read -r swap_total swap_used <<< $(free -m | awk '/Swap:/ {print $2" "$3}')
if [[ $swap_total -gt 0 ]]; then
    swap_usage=$(awk "BEGIN {printf \"%.2f%%\", ($swap_used/$swap_total)*100}")
else
    swap_usage="Нет SWAP"
fi

# Использование диска (требует sudo для доступа к некоторым разделам)
disk_usage=$(df -h / | awk 'NR==2{print $5}')

# Время работы системы
uptime=$(uptime -p)

# Версия ядра
kernel_version=$(uname -r)

# Информация о ОС
if [ -f /etc/os-release ]; then
    os_info=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
else
    os_info=$(uname -o)
fi

# Локальные IP-адреса
ipv4=$(hostname -I | awk '{print $1}')
ipv6=$(ip -6 addr show scope global | awk '/inet6/{print $2}' | head -n1)

# Внешний IP (проверка на наличие curl, использование sudo для работы с сетью)
if command -v curl >/dev/null 2>&1; then
    ext_ip=$(curl -s --connect-timeout 2 ifconfig.me || echo "Недоступен")
else
    ext_ip="curl не установлен"
fi

# Доступные обновления (требует sudo)
if command -v apt-get >/dev/null 2>&1; then
    updates_available=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
else
    updates_available="N/A"
fi

# Уязвимые пакеты (требует sudo)
vulnerable_packages=$(apt-get upgrade -s | grep -i security || echo "Уязвимых пакетов нет.")

# Последние неудачные попытки входа (требует sudo)
suspicious_logins=$(sudo grep 'Failed password' /var/log/auth.log | grep -v -E "sudo.*COMMAND=/usr/bin/grep 'Failed password' /var/log/auth.log" 2>/dev/null | tail -n 5)
if [[ -z "$suspicious_logins" ]]; then
    suspicious_logins="Неудачных попыток входа не зафиксировано."
fi

# Логи Fail2Ban (требует sudo)
fail2ban_log="/var/log/fail2ban.log"
if [ -f "$fail2ban_log" ]; then
    last_bans=$(sudo grep "Ban" "$fail2ban_log" | tail -n 5)
    total_bans=$(sudo grep "Ban" "$fail2ban_log" | wc -l)
else
    last_bans="Лог Fail2Ban не найден."
    total_bans="Неизвестно"
fi

# Статус UFW (требует sudo)
if command -v ufw >/dev/null 2>&1; then
    ufw_status=$(sudo ufw status verbose 2>/dev/null || echo "UFW не установлен")
else
    ufw_status="UFW не установлен"
fi

# Текущая сетевая активность (требует sudo)
network_connections=$(sudo ss -tunap | grep -vE "ESTABLISHED|LISTEN|TIME-WAIT|UNCONN" | awk '{printf "%-5s %-12s %-30s %-30s\n", $1, $2, $5, $6}' | sed -e 's/\[//g' -e 's/\]//g' -e 's/::ffff://g')

# Последние успешные логины (требует sudo)
last_successful_logins=$(sudo last -a | grep -vE 'reboot|shutdown' | head -n 5 | awk '{print $4, $5, $6, $1, $(NF)}')


# Отображение баннера
cat << BANNER
===========================================
      Информация о состоянии системы
===========================================
        Время работы: $uptime
        Загрузка CPU: $cpu_load
 Использование диска: $disk_usage
Использование памяти: $mem_usage
  Использование SWAP: $swap_usage
-------------------------------------------
                  ОС: $os_info
         Версия ядра: $kernel_version
Доступные обновления: $updates_available
     Уязвимые пакеты: $vulnerable_packages
-------------------------------------------
      Локальный IPv6: $ipv6
      Локальный IPv4: $ipv4
          Внешний IP: $ext_ip
-------------------------------------------
Последние успешные логины:
$last_successful_logins
-------------------------------------------
Последние предупреждения безопасности:

- Последние неудачные попытки входа:
$suspicious_logins

- Действия Fail2Ban:
Всего банов: $total_bans
--Последние баны
$last_bans

- Статус UFW:
$ufw_status

- Текущая сетевая активность
$network_connections

--------------------------------------------------------------------------------------
                            Детали конфигурации сервера
======================================================================================
         Порт SSH: SSH_PORT_PLACEHOLDER
Локальный порт UI: UI_LOCAL_PORT_PLACEHOLDER
Удалённый порт UI: UI_REMOTE_PORT_PLACEHOLDER
--------------------------------------------------------------------------------------
  Панель URL: https://MAIN_IP_PLACEHOLDER:UI_REMOTE_PORT_PLACEHOLDER/WEB_PATH_PLACEHOLDER
 Логин 3X-UI: LGN_PLACEHOLDER
Пароль 3X-UI: PSW_PLACEHOLDER
======================================================================================
BANNER
EOF

    # Используем $DNS, если она задана, иначе используем $MAIN_IP
    main_ip_or_dns=${DNS:-$MAIN_IP}

    # Замена placeholders одной командой sed
    sed -i -e "s|SSH_PORT_PLACEHOLDER|$SSH_PORT|g" \
           -e "s|UI_LOCAL_PORT_PLACEHOLDER|$UI_LOCAL_PORT|g" \
           -e "s|UI_REMOTE_PORT_PLACEHOLDER|$UI_REMOTE_PORT|g" \
           -e "s|MAIN_IP_PLACEHOLDER|$main_ip_or_dns|g" \
           -e "s|WEB_PATH_PLACEHOLDER|$WEB_PATH|g" \
           -e "s|LGN_PLACEHOLDER|$lgn|g" \
           -e "s|PSW_PLACEHOLDER|$psw|g" "$banner_script_path"

    # Делаем скрипт исполняемым
    chmod +x "$banner_script_path"
    # Отключаем стандартный баннер
    chmod -x /etc/update-motd.d/*

    log "INFO" "Динамический скрипт приветствия по SSH успешно создан."
}
