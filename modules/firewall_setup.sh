#!/bin/bash
# modules/firewall_setup.sh

firewall_config() {
    log "INFO" "Настройка брандмауэра..."


    # Проверка наличия UFW
    if command -v ufw >/dev/null 2>&1; then
        # Используем UFW для настройки брандмауэра
        log "INFO" "Обнаружен UFW. Настройка правил брандмауэра..."

        # Проверяем, активирован ли UFW
        if ufw status | grep -q "Status: inactive"; then
            log "INFO" "UFW не активен. Активируем UFW..."
            ufw --force enable
        fi

        # Обрабатываем сброс правил
        case "${CLEAR_FIREWALL:-ask}" in
            true)
                log "INFO" "Сброс правил UFW по запросу."
                ufw --force reset
                ;;
            ask)
                read -rp "Хотите сбросить правила UFW? [Y/n] (по умолчанию: Y): " ufw_reset_choice
                ufw_reset_choice=${ufw_reset_choice:-Y}
                if [[ "$ufw_reset_choice" =~ ^[Yy]$ ]]; then
                    log "INFO" "Пользователь подтвердил сброс UFW."
                    ufw --force reset
                else
                    log "INFO" "Пропускаем сброс UFW по выбору пользователя."
                fi
                ;;
            *)
                log "INFO" "Пропускаем сброс UFW по настройкам скрипта."
                ;;
        esac

        # Устанавливаем политики по умолчанию
        ufw default deny incoming || error_exit "Не удалось установить политику по умолчанию для входящего трафика."
        ufw default allow outgoing || error_exit "Не удалось установить политику по умолчанию для исходящего трафика."

        # Открываем необходимые порты с комментариями
        ufw allow "$SSH_PORT"/tcp comment 'SSH порт' || error_exit "Не удалось открыть SSH порт."
        ufw allow "$UI_REMOTE_PORT"/tcp comment 'Удаленный UI порт' || error_exit "Не удалось открыть удаленный UI порт."
        ufw allow 80/tcp comment 'HTTP порт' || error_exit "Не удалось открыть HTTP порт."
        ufw allow 443/tcp comment 'HTTPS порт' || error_exit "Не удалось открыть HTTPS порт."
        ufw allow 10087/tcp comment 'Порт получения сертификата' || error_exit "Не удалось открыть порт получения сертификата."

        # Блокировка пакетов с аномальными TCP-флагами

        sudo ufw deny proto tcp from any to any tcp flags fin,psh,urg fin,psh,urg
        sudo ufw deny proto tcp from any to any tcp flags syn,fin syn,fin
        sudo ufw deny proto tcp from any to any tcp flags syn,rst syn,rst
        sudo ufw deny proto tcp from any to any tcp flags fin,rst fin,rst
        sudo ufw deny proto tcp from any to any tcp flags ack,fin fin
        sudo ufw deny proto tcp from any to any tcp flags ack,psh psh
        sudo ufw deny proto tcp from any to any tcp flags ack,urg urg

        # Отключаем ICMP (ping)
        ufw_pingdisable

        # Перезагружаем UFW для применения изменений
        ufw enable || error_exit "Не удалось включить правила UFW"
        ufw reload || error_exit "Не удалось перезагрузить UFW."

        # Отображаем статус UFW
        ufw status verbose

    else
        log "WARN" "UFW не найден. Попытка использовать iptables..."

        if command -v iptables >/dev/null 2>&1; then
            log "INFO" "Настройка правил брандмауэра с использованием iptables..."

            # Удаляем существующие правила
            iptables -F
            iptables -X

            # Устанавливаем политики по умолчанию
            iptables -P INPUT DROP
            iptables -P FORWARD DROP
            iptables -P OUTPUT ACCEPT

            # Разрешаем localhost и установленные соединения
            iptables -A INPUT -i lo -j ACCEPT
            iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

            # Открываем необходимые порты
            iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
            iptables -A INPUT -p tcp --dport "$UI_REMOTE_PORT" -j ACCEPT
            iptables -A INPUT -p tcp --dport 80 -j ACCEPT
            iptables -A INPUT -p tcp --dport 443 -j ACCEPT
            iptables -A INPUT -p tcp --dport 10087 -j ACCEPT

            # Отключение исходящих ping-запросов через iptables
            iptables -A OUTPUT -p icmp --icmp-type echo-request -j DROP

            # Отключение входящих ping-ответов через iptables
            iptables -A INPUT -p icmp --icmp-type echo-reply -j DROP

            # Сохраняем правила
            if command -v netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save || error_exit "Не удалось сохранить правила iptables."
            else
                iptables-save > /etc/iptables/rules.v4 || error_exit "Не удалось сохранить правила iptables."
            fi

            log "INFO" "Настройка iptables завершена."
        else
            log "ERROR" "Не найден инструмент для управления брандмауэром. Пожалуйста, установите UFW или iptables."
            error_exit "Настройка брандмауэра не выполнена."
        fi
    fi

    log "INFO" "Настройка брандмауэра завершена."
}

# Функция для отключения ICMP (ping)
ufw_pingdisable() {
    # Создаем резервную копию файла before.rules
    backup_file "$UFW_BEFORERULES_FILE"
    
    # Комментируем строки, связанные с ICMP в before.rules
    log "INFO" "Комментируем строки, разрешающие ICMP-запросы в $UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-forward -p icmp --icmp-type time-exceeded -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-forward -p icmp --icmp-type parameter-problem -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"
    sed -i '/-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT/s/^/#/' "$UFW_BEFORERULES_FILE"

    log "INFO" "Изменения в $UFW_BEFORERULES_FILE успешно внесены."
}