#!/bin/bash
# modules/api_functions.sh

# Функция для авторизации и получения cookies
api_login() {
    log "INFO" "Попытка авторизации в API..."

    local COOKIE_FILE="cookies.txt"

    # Выполняем POST-запрос и сохраняем ответ
    response=$(curl -s -X POST "$URL_LOGIN" \
        -H "Content-Type: application/json" \
        -d "$(jq -nc --arg username "$lgn" --arg password "$psw" '{username: $username, password: $password}')" \
        -c "$COOKIE_FILE")

    # Проверяем наличие файла cookies
    if [ ! -f "$COOKIE_FILE" ]; then
        log "ERROR" "Файл cookies не создан. Возможная ошибка авторизации."
        error_exit "Не удалось авторизоваться в API."
    fi

    # Читаем cookies из файла
    COOKIES=$(awk 'NR>4 {print $6 "=" $7}' "$COOKIE_FILE" | tr '\n' '; ')
    rm -f "$COOKIE_FILE"

    if [[ -z "$COOKIES" ]]; then
        log "ERROR" "Не удалось получить cookies при авторизации в API."
        error_exit "Не удалось авторизоваться в API."
    else
        log "INFO" "Успешно авторизовались в API."
    fi
}

# Функция для генерации сертификатов
api_certgen() {
    log "INFO" "Генерация новых сертификатов X25519 через API..."

    local cert_response=$(curl -s -X POST "$URL_SERVER/getNewX25519Cert" \
        -H "Content-Type: application/json" \
        -H "Cookie: $COOKIES")

    privateKey=$(echo "$cert_response" | jq -r '.obj.privateKey')
    publicKey=$(echo "$cert_response" | jq -r '.obj.publicKey')

    if [[ -z "$privateKey" || -z "$publicKey" ]]; then
        log "ERROR" "Не удалось получить сертификаты из API."
        error_exit "Не удалось сгенерировать сертификаты."
    else
        log "INFO" "Сертификаты успешно сгенерированы."
    fi
}

# Функция для генерации случайного shortId
generate_random_short_id() {
    local length=$1
    openssl rand -hex "$((length / 2))"  # Генерируем hex-строку нужной длины
}

# Функция для генерации массива случайных shortIds
generate_short_ids() {
    local count=$1
    local max_length=$2
    local short_ids=()

    for ((i=0; i<count; i++)); do
        # Генерация случайной длины от 2 до $max_length
        local length=$((RANDOM % (max_length - 1) + 2))
        
        # Генерация shortId с этой длиной
        short_ids+=("$(generate_random_short_id "$length")")
    done

    # Возвращаем массив в формате JSON
    jq -n --argjson shortIds "$(printf '%s\n' "${short_ids[@]}" | jq -R . | jq -s .)" '$shortIds'
}


# Функция для добавления нового входящего подключения (inbound)
api_add_inbound() {
    log "INFO" "Добавление нового входящего подключения через API..."

    # Проверка обязательных переменных
    if [[ -z "$privateKey" || -z "$publicKey" || -z "$dest" || -z "$user_input_sni" || -z "$URL_API" || -z "$COOKIES" ]]; then
        log "ERROR" "Отсутствуют необходимые переменные (privateKey, publicKey, dest, user_input_sni, URL_API, COOKIES)"
        return 1
    fi

    # Удаляем все пробелы из строки $user_input_sni перед разбиением
    local cleaned_user_input_sni=$(echo "$user_input_sni" | tr -d ' ')

    # Теперь разделяем строку на массив по запятым
    IFS=',' read -r -a sni_array <<< "$cleaned_user_input_sni"

    # Генерация случайных shortIds
    local short_ids
    short_ids=$(generate_short_ids 8 16)  # Генерируем 8 случайных shortIds длиной 16 символов

    # log "INFO" "Generated short IDs: $short_ids"

    # Преобразуем массив SNI в JSON
    local sni_json
    sni_json=$(printf '%s\n' "${sni_array[@]}" | jq -R . | jq -s .)

   # Преобразуем streamSettings в строку с сериализованным JSON
    stream_settings=$(jq -n '{
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
            "dest": $dest,
            "serverNames": $serverNames,
            "privateKey": $privateKey,
            "shortIds": $shortIds,
            "settings": {
                "publicKey": $publicKey,
                "fingerprint": "chrome",
                "serverName": "",
                "spiderX": "/"
            }
        },
        "tcpSettings": {
            "header": {
                "type": "none"
            }
        }
    }' --arg dest "$dest:443" --argjson serverNames "$sni_json" --arg privateKey "$privateKey" --arg publicKey "$publicKey" --argjson shortIds "$short_ids")

    # Преобразуем sniffing в строку с сериализованным JSON
    sniffing_settings=$(jq -n '{
        "enabled": true,
        "destOverride": ["http", "tls", "quic", "fakedns"],
        "metadataOnly": false,
        "routeOnly": false
    }')

    # Формируем JSON-данные с сериализацией sniffing и streamSettings
    json_data=$(jq -n \
        --arg privateKey "$privateKey" \
        --arg publicKey "$publicKey" \
        --arg dest "$dest:443" \
        --argjson serverNames "$sni_json" \
        --argjson shortIds "$short_ids" \
        --arg settings '{"clients":[],"decryption":"none","fallbacks":[]}' \
        --arg streamSettings "$stream_settings" \
        --arg sniffing "$sniffing_settings" \
        '{
            "enable": true,
            "remark": "Inbound Auto Generated",
            "listen": "",
            "port": 443,
            "protocol": "vless",
            "expiryTime": 0,
            "settings": $settings,  # Передаем settings как строку JSON
            "streamSettings": $streamSettings,  # Передаем streamSettings как строку JSON
            "sniffing": $sniffing  # Передаем sniffing как строку JSON
        }')

    # Логирование для проверки
    # log "INFO" "Сформированный JSON: $json_data"

    # Выполнение запроса с правильным JSON-объектом
    add_response=$(curl -s -X POST "$URL_API/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Cookie: $COOKIES" \
        -d "$json_data")




    # Извлечение ID созданного inbound
    inboundid=$(echo "$add_response" | jq -r '.obj.id')

    if [[ -z "$inboundid" || "$inboundid" == "null" ]]; then
        log "ERROR" "Ошибка при добавлении inbound: $(echo "$add_response" | jq -r '.msg')"
        return 1
    else
        log "INFO" "Новый inbound добавлен: ID=$inboundid"
    fi
}



# Функция для добавления нового пользователя
api_add_newuser() {
    log "INFO" "Добавление нового пользователя через API..."

    # Генерация случайного email (9 символов) через openssl
    mail=$(openssl rand -hex 5 | tr -dc 'a-z0-9' | head -c 9)
    if [[ -z "$mail" ]]; then
        log "ERROR" "Не удалось сгенерировать случайный email."
        return 1
    fi

    # Генерация UUID
    guid=$(uuidgen)
    if [[ -z "$guid" ]]; then
        log "ERROR" "Не удалось сгенерировать UUID."
        return 1
    fi

    log "INFO" "Сгенерированы email: $mail, UUID: $guid"

    # Проверка, что inboundid определен и является числом
    if [[ -z "$inboundid" || ! "$inboundid" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Неверный inbound ID: $inboundid"
        return 1
    fi

    # Генерация данных для нового пользователя
    local settings_data
    settings_data=$(jq -nc --arg guid "$guid" --arg mail "$mail" '{
        clients: [{
            id: $guid,
            flow: "xtls-rprx-vision",
            email: $mail,
            enable: true
        }]
    }')

    # Преобразование settings в строку
    local settings_string
    settings_string=$(echo "$settings_data" | jq -c .)

    # Преобразование объекта JSON в строку для отправки
    local add_userdata
    add_userdata=$(jq -nc --argjson id "$inboundid" --arg settings "$settings_string" '{
        id: $id,
        settings: $settings
    }')

    log "INFO" "Запрос к API для добавления пользователя: $add_userdata"

    # Выполнение POST-запроса для добавления нового пользователя
    local add_newuser
    add_newuser=$(curl -s -X POST "$URL_API/inbounds/addClient" \
        -H "Content-Type: application/json" \
        -H "Cookie: $COOKIES" \
        -d "$add_userdata")

    # Проверка на успешность запроса
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Сетевая ошибка при выполнении запроса."
        return 1
    fi

    # Проверка на успешность добавления пользователя через API
    if [[ $(echo "$add_newuser" | jq -r '.success') == "true" ]]; then
        log "INFO" "Пользователь успешно добавлен: email=$mail, id=$guid"
    else
        log "ERROR" "Ошибка при добавлении пользователя: $(echo "$add_newuser" | jq -r '.msg')"
        return 1
    fi
}



# Функция для получения списка существующих inbound-подключений
api_get_inbound_by_port() {
    log "INFO" "Получение списка входящих подключений через API..."

    # Выполнение GET-запроса для получения списка всех inbound-соединений
    local response=$(curl -s -X GET "$URL_API/inbounds/list" \
        -H "Content-Type: application/json" \
        -H "Cookie: $COOKIES")

    # Проверка успешности запроса
    if [[ $(echo "$response" | jq -r '.success') != "true" ]]; then
        log "ERROR" "Ошибка при получении inbound-подключений: $(echo "$response" | jq -r '.msg')"
        return 1
    fi

    # Ищем объект с портом 443 и сохраняем его ID
    inboundid=$(echo "$response" | jq -r '.obj[] | select(.port == 443) | .id')

    # Проверяем, найдено ли подключение на порту 443
    if [[ -n "$inboundid" ]]; then
        log "INFO" "Inbound-подключение с портом 443 найдено: ID=$inboundid"
    else
        log "INFO" "Inbound-подключение на порту 443 не найдено"
    fi
}

# Функция для удаления inbound-подключения по его ID
api_delete_inbound_by_id() {
    log "INFO" "Попытка удалить inbound-подключение с ID=$inboundid через API..."

    # Проверка, что inboundid передан
    if [[ -z "$inboundid" || ! "$inboundid" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Неверный inbound ID для удаления: $inboundid"
        return 1
    fi

    # Выполнение POST-запроса для удаления inbound-подключения по ID
    local delete_response=$(curl -s -X POST "$URL_API/inbounds/del/$inboundid" \
        -H "Content-Type: application/json" \
        -H "Cookie: $COOKIES")

    # Проверка успешности запроса
    if [[ $(echo "$delete_response" | jq -r '.success') == "true" ]]; then
        log "INFO" "Inbound-подключение с ID=$inboundid успешно удалено."
    else
        log "ERROR" "Ошибка при удалении inbound-подключения: $(echo "$delete_response" | jq -r '.msg')"
        return 1
    fi
}

# Функция для генерации нового inbound-подключения и пользователя
generate_new_inbound() {
    log "INFO" "Ожидание 15 секунд перед началом генерации нового inbound..."
    sleep 15
    
    URL="http://localhost:$UI_LOCAL_PORT/$WEB_PATH"
    URL_LOGIN="$URL/login"
    URL_API="$URL/panel/api"
    URL_SERVER="$URL/server"
    
    log "INFO" "Начинаем процесс генерации нового inbound-подключения..."

    api_login
    sleep 5
    api_get_inbound_by_port

    if [[ -n "$inboundid" && "$inboundid" =~ ^[0-9]+$ ]]; then
        log "INFO" "Inbound-подключение найдено с ID: $inboundid"

        # Запрос подтверждения от пользователя с таймером ожидания 10 секунд
        read -t 10 -p "Вы хотите удалить подключение с ID=$inboundid? (нажмите Enter для подтверждения или введите 'n' для отмены) [Y/n]: " confirm

        # Если пользователь не ввел ответ (нажал Enter) или ввел 'y', 'Y', удаляем подключение
        if [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Удаление inbound-подключения..."
            sleep 5
            api_delete_inbound_by_id
        else
            log "INFO" "Удаление inbound-подключения отменено пользователем."
            exit 0
        fi
    else
        log "INFO" "Inbound-подключение для удаления не найдено."
    fi

    api_certgen
    sleep 3
    api_add_inbound
    sleep 3
    api_add_newuser

    log "INFO" "Новое inbound-подключение успешно сгенерировано."
}