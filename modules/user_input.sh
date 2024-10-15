#!/bin/bash
# modules/user_input.sh

# Определяем цветовые коды
light_blue="\e[36m"
plain="\e[0m"

user_input_data() {

    log "INFO" "Начало сбора пользовательского ввода..."

    # Получаем основной IP-адрес сервера
    log "INFO" "Обнаружен IP-адрес сервера: $MAIN_IP"

    # Запрос имени пользователя
    if [ -z "$newuser" ]; then
        read -rp "$(echo -e "${light_blue}Введите имя нового пользователя (по умолчанию 'XKeen'): ${plain}")" newuser
        newuser=${newuser:-XKeen}
    fi
    log "INFO" "Имя пользователя установлено: $newuser"

    # Проверка существования пользователя и запрос пароля
    if id "$newuser" &>/dev/null; then
        log "INFO" "Пользователь $newuser уже существует."
        if [ -z "$password" ]; then
            read -srp "$(echo -e "${light_blue}Пользователь существует. Введите новый пароль для его обновления (оставьте пустым, чтобы сохранить текущий пароль): ${plain}")" password
            echo
        fi
    else
        if [ -z "$password" ]; then
            read -srp "$(echo -e "${light_blue}Введите пароль (оставьте пустым для автоматической генерации): ${plain}")" password
            echo
            if [[ -z "$password" ]]; then
                password=$(generate_secure_password)
                log "INFO" "Сгенерированный пароль: $password"
            fi
        fi
    fi

    # Проверка и генерация данных для 3X-UI
    if [ -z "$lgn" ]; then
        read -rp "$(echo -e "${light_blue}Введите имя пользователя для 3X-UI (оставьте пустым для автоматической генерации): ${plain}")" lgn
        if [[ -z "$lgn" ]]; then
            lgn=$(openssl rand -base64 5 | tr -dc 'a-zA-Z0-9')
            log "INFO" "Сгенерированное имя пользователя для 3X-UI: $lgn"
        fi
    fi

    if [ -z "$psw" ]; then
        read -srp "$(echo -e "${light_blue}Введите пароль для 3X-UI (оставьте пустым для автоматической генерации): ${plain}")" psw
        echo
        if [[ -z "$psw" ]]; then
            psw=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')
            log "INFO" "Сгенерированный пароль для 3X-UI: $psw"
        fi
    fi

    # Запрос RSA-ключа
    if [ -z "$RSA" ]; then
        read -rp "$(echo -e "${light_blue}Введите ваш RSA публичный ключ (оставьте пустым, если не требуется): ${plain}")" RSA
        if [[ -z "$RSA" ]]; then
            log "WARN" "RSA ключ не предоставлен. Настоятельно рекомендуется использовать SSH-ключи для большей безопасности."
        fi
    fi

    # Запрос доменного имени или IP-адреса
    if [ -z "$DNS" ]; then
        read -rp "$(echo -e "${light_blue}Введите доменное имя или нажмите Enter для использования IP-адреса ($MAIN_IP): ${plain}")" DNS
        DNS=${DNS:-$MAIN_IP}
    fi
    log "INFO" "Доменное имя или IP-адрес: $DNS"

    # Запрос порта SSH
    if [ -z "$SSH_PORT" ]; then
        read -rp "$(echo -e "${light_blue}Введите порт для SSH (по умолчанию сгенерирован $SSH_PORT): ${plain}")" SSH_PORT_Input
        SSH_PORT=${SSH_PORT_Input:-$SSH_PORT}
    fi
    log "INFO" "Порт SSH установлен: $SSH_PORT"

    # Запрос порта UI_REMOTE_PORT
    if [ -z "$UI_REMOTE_PORT" ]; then
        read -rp "$(echo -e "${light_blue}Введите удаленный порт для UI (по умолчанию сгенерирован $UI_REMOTE_PORT): ${plain}")" UI_REMOTE_PORT_Input
        UI_REMOTE_PORT=${UI_REMOTE_PORT_Input:-$UI_REMOTE_PORT}
    fi
    log "INFO" "Удаленный порт для UI установлен: $UI_REMOTE_PORT"

    # Запрос целевого сайта для dest
    if [ -z "$dest" ]; then
        read -rp "$(echo -e "${light_blue}Введите сайт для использования в качестве маскировки (например, example.com): ${plain}")" dest
        if [ -z "$dest" ]; then
            log "ERROR" "Целевой сайт не был введен. Завершение с ошибкой."
            error_exit "Необходимо указать целевой сайт для маскировки."
        fi
    fi
    log "INFO" "Целевой сайт для проксирования: $dest"

    # Запрос значений SNI
    if [ -z "$user_input_sni" ]; then
        read -rp "$(echo -e "${light_blue}Введите значения SNI (через запятую, если несколько): ${plain}")" user_input_sni
        if [ -z "$user_input_sni" ]; then
            error_exit "Значения SNI не могут быть пустыми. Завершение работы."
        fi
    fi
    log "INFO" "Значения SNI: $user_input_sni"

    # Удаление лишних пробелов и замена запятых с пробелами на запятые без пробелов
    local cleaned_input_sni=$(echo "$user_input_sni" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*,[[:space:]]*/,/g')

    # Формирование JSON-массива из введенных значений
    local values=""
    IFS=',' read -ra ADDR <<< "$cleaned_input_sni"
    for i in "${ADDR[@]}"; do
        value=$(echo "$i" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$value" ]; then
            values+="\"$value\", "
        fi
    done

    # Удаление последней запятой и пробела из массива
    SNI=$(echo "$values" | sed 's/, $//')

    log "INFO" "SNI обработано: $SNI"

    log "INFO" "Сбор пользовательского ввода завершен."
}