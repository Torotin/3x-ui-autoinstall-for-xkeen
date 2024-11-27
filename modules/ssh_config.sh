#!/bin/bash
# modules/ssh_config.sh

# Функция для настройки SSH
configure_ssh() {
    log "INFO" "Настройка SSH..."

    local ssh_config="/etc/ssh/sshd_config"
    backup_file "$ssh_config"

    # Проверка необходимых переменных
    if [[ -z "$SSH_PORT" || -z "$newuser" || -z "$banner_script_path" ]]; then
        error_exit "Необходимо установить переменные SSH_PORT, newuser и banner_script_path."
    fi

    # Определение метода аутентификации
    if [ -n "$RSA" ]; then
        password_auth="no"
        pubkey_auth="yes"
    else
        password_auth="yes"
        pubkey_auth="no"
    fi

    # Создание или обновление конфигурационного файла SSH
    cat << EOF > "$ssh_config"
Include /etc/ssh/sshd_config.d/*.conf
Port $SSH_PORT
AllowUsers $newuser
PasswordAuthentication $password_auth
PubkeyAuthentication $pubkey_auth
MaxAuthTries 3
ClientAliveInterval 60
ClientAliveCountMax 3
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    # Проверка корректности конфигурации SSH
    if sshd -t -f "$ssh_config"; then
        log "INFO" "Синтаксис конфигурации SSH корректен."
    else
        error_exit "Обнаружена ошибка в конфигурации SSH. Пожалуйста, проверьте настройки."
    fi

    log "INFO" "Настройка SSH завершена."
}


# Функция для настройки Fail2Ban
configure_fail2ban() {
    log "INFO" "Настройка Fail2Ban..."

    # Проверка установки Fail2Ban
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        error_exit "Fail2Ban не установлен. Пожалуйста, установите Fail2Ban и повторите попытку."
    fi

    # Проверка необходимых переменных
    if [[ -z "$SSH_PORT" ]]; then
        error_exit "Переменная SSH_PORT не задана. Необходимо установить порт SSH."
    fi

    # Резервное копирование конфигурационного файла Fail2Ban
    backup_file "/etc/fail2ban/jail.local"

    # Настраиваемые параметры (можно задавать извне)
    local max_retry="${fail2ban_max_retry:-3}"
    local ban_time="${fail2ban_ban_time:-43200}"
    local find_time="${fail2ban_find_time:-600}"

    log "INFO" "Конфигурация Fail2Ban: порт SSH=$SSH_PORT, maxretry=$max_retry, bantime=$ban_time, findtime=$find_time."

    # Создание нового конфигурационного файла Fail2Ban
    cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = %(sshd_log)s
backend = %(sshd_backend)s
action = iptables[name=SSH, port=ssh, protocol=tcp]
maxretry = $max_retry
bantime = ${ban_time}m
findtime = $find_time
EOF

    # Добавление настроек для IP-лимитов (на основе create_iplimit_jails)
    local iplimit_log_path="/var/log/iplimit.log"  # Убедитесь, что путь корректен
    local iplimit_banned_log_path="/var/log/iplimit-banned.log"  # Путь для журнала заблокированных IP

    # Создание jail для 3x-ipl
    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled = true
backend = auto
filter = 3x-ipl
action = 3x-ipl
logpath = $iplimit_log_path
maxretry = $max_retry
bantime = ${ban_time}m
findtime = $find_time
EOF

    # Создание фильтра для 3x-ipl
    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    # Создание действия для 3x-ipl
    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> $iplimit_banned_log_path

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> $iplimit_banned_log_path

[Init]
EOF

    log "INFO" "Правила IP-лимитов добавлены с bantime = ${bantime} минут."

    local fail2banconf="/etc/fail2ban/fail2ban.conf"
    local allowipv6="allowipv6 = auto"

    # Проверяем наличие строки allowipv6 в конфиге
    if grep -q "^#.*allowipv6" "$fail2banconf"; then
        # Если строка закомментирована, удаляем её и записываем новое значение
        sed -i "/^#.*allowipv6/d" "$fail2banconf"
        echo "$allowipv6" >> "$fail2banconf"
        log "INFO" "Закомментированная строка найдена и заменена на allowipv6 = auto."
    elif grep -q "^[^#]*allowipv6" "$fail2banconf"; then
        # Если строка уже активна, ничего не делаем
        log "INFO" "Параметр allowipv6 уже активен. Изменений не требуется."
    else
        # Если параметра нет вообще, добавляем его
        echo "$allowipv6" >> "$fail2banconf"
        log "INFO" "Параметр allowipv6 отсутствовал. Добавлено allowipv6 = auto."
    fi

    # Перезапуск Fail2Ban
    if systemctl restart fail2ban; then
        log "INFO" "Служба Fail2Ban успешно перезапущена."
    else
        error_exit "Не удалось перезапустить службу Fail2Ban."
    fi

    log "INFO" "Fail2Ban настроен и успешно запущен."
}

