#!/bin/bash
# modules/caddy_config.sh

# Функция для настройки Caddy
caddy_config() {
    log "INFO" "Настройка Caddy..."

    # Проверка необходимых переменных
    if [[ -z "$UI_REMOTE_PORT" || -z "$UI_LOCAL_PORT" || -z "$MAIN_IP" || -z "$EMAIL" ]]; then
        error_exit "Одна или несколько необходимых переменных не установлены."
    fi

    # Создание основного содержимого Caddyfile
    {
        cat << EOF
{
    auto_https disable_redirects
    https_port $UI_REMOTE_PORT
    http_port 10087
    log {
        level ERROR
    }
    on_demand_tls {
        ask http://localhost:10087/
        interval 3600s
        burst 4
    }
}

https://$MAIN_IP:$UI_REMOTE_PORT {
EOF
        generate_reverse_proxy_block
        echo "}"

        cat << EOF

:10087 {
    respond "allowed" 200 {
        close
    }
    log {
        output file /var/log/caddy/access.log {
            roll_size 10MB
            roll_keep 5
            roll_keep_for 720h
        }
        level WARN
    }
}

:80 {
   root * /var/www/html/fake
   file_server
   log {
        output file /var/log/caddy/access.log {
            roll_size 10MB
            roll_keep 5
            roll_keep_for 720h
        }
        level WARN
    }
}

EOF

        # Если переменная $DNS не пустая, добавляем дополнительный блок для $DNS
        if [[ -n "$DNS" ]]; then
            cat << EOF

https://$DNS:$UI_REMOTE_PORT {
EOF
            generate_reverse_proxy_block
            echo "}"
        fi
    } > "$caddyfile"

    # Установка прав доступа для директории /var/www/html
    if ! chown -R www-data:www-data /var/www/html; then
        error_exit "Не удалось установить права на /var/www/html"
    fi

    if ! chmod -R 755 /var/www/html; then
        error_exit "Не удалось установить разрешения на /var/www/html"
    fi

    # Форматирование конфигурации Caddy
    if ! caddy fmt --overwrite "$caddyfile"; then
        error_exit "Не удалось отформатировать Caddyfile!"
    fi

    # Удаление старых самоподписанных сертификатов, если они существуют
    if [[ -f "$self_key" || -f "$self_crt" ]]; then
        rm -f "$self_key" "$self_crt"
        log "INFO" "Старые самоподписанные сертификаты удалены."
    fi

    # Генерация самоподписанного сертификата, если переменная $DNS пустая
    if [[ -z "$DNS" ]]; then
        generate_self_signed_cert
        if [[ ! -f "$self_crt" || ! -f "$self_key" ]]; then
            error_exit "Не удалось создать самоподписанный сертификат!"
        fi
    fi

    # Перезапуск Caddy
    if ! systemctl restart caddy; then
        error_exit "Не удалось перезапустить Caddy!"
    fi

    log "INFO" "Caddy успешно настроен."
}

# Функция для генерации блока reverse_proxy
generate_reverse_proxy_block() {
    cat << EOB
    reverse_proxy localhost:$UI_LOCAL_PORT {
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up Range {header.Range}
        header_up If-Range {header.If-Range}
    }

    tls {
        on_demand 
        issuer acme {
            email $EMAIL
        }
    }
EOB
}

# Функция для генерации самоподписанного сертификата
generate_self_signed_cert() {
    log "INFO" "Генерация самоподписанного сертификата..."

    mkdir -p "$cert_dir"
    chown -R caddy:caddy "$cert_dir"

    openssl req -new -newkey rsa:2048 -days 1825 -nodes -x509 \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=Xkeen/CN=$MAIN_IP" \
        -keyout "$self_key" -out "$self_crt"

    chown caddy:caddy "$self_crt" "$self_key"
    chmod 600 "$self_crt" "$self_key"

    log "INFO" "Самоподписанный сертификат создан в $cert_dir."
}
