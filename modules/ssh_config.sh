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
    local max_retry="${max_retry:-3}"
    local ban_time="${ban_time:-43200}"
    local find_time="${find_time:-600}"

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
bantime = $ban_time
findtime = $find_time
EOF
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
