#!/bin/bash
# modules/utils.sh

# Определение цветовых кодов
green="\e[32m"
yellow="\e[33m"
red="\e[31m"
plain="\e[0m"  # Возврат к обычному цвету

# Логирование
log() {
    local type="$1"
    local message="$2"
    local function_name="${FUNCNAME[1]}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local color=""
    case "$type" in
        "INFO") color="${green}";;
        "WARN") color="${yellow}";;
        "ERROR") color="${red}";;
    esac

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$type] [$function_name] ${message}" >> "$LOG_FILE"
    fi
    echo -e "${color}[$type] [$function_name] ${message}${plain}"

    if [[ "$type" == "ERROR" && -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [DEBUG] [${function_name}] $(caller)" >> "$LOG_FILE"
    fi
}


error_exit() {
    log "ERROR" "$1"
    exit 1
}

command_exists() {
    command -v "$1" &>/dev/null
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +"%Y%m%d%H%M%S")"
        log "INFO" "Backup of $file created."
    fi
}

is_port_in_use() {
    local port=$1
    if lsof -i -P -n | grep -w ":$port" > /dev/null; then
        return 0
    else
        return 1
    fi
}

generate_random_port() {
    local port
    while true; do
        port=$(shuf -i 1024-65535 -n1)
        if [[ "$port" -ne 40000 ]] && ! is_port_in_use "$port"; then
            echo "$port"
            return
        fi
    done
}

generate_secure_password() {
    log "INFO" "Generating a secure password with special characters..."

    local charset='a-zA-Z0-9!@#$%^&*()_+{}[]:;<>?'
    local password
    password=$(openssl rand -base64 24 | tr -dc "$charset")

    while [[ ! "$password" =~ [\!\@\#\$\%\^\&\*\(\)_\+\{\}\[\]\:\;\<\>\?] ]]; do
        log "INFO" "Regenerating password to include special characters..."
        password=$(openssl rand -base64 24 | tr -dc "$charset")
    done

    log "INFO" "Secure password with special characters generated."
    echo "$password"
}


# Функция для генерации случайных портов
generate_random_ports() {
    SSH_PORT=$(generate_random_port)
    UI_LOCAL_PORT=$(generate_random_port)
    UI_REMOTE_PORT=$(generate_random_port)
}

# Функция для проверки, чтобы порты были разными
ensure_unique_ports() {
    while [ "$UI_LOCAL_PORT" -eq "$UI_REMOTE_PORT" ] || [ "$SSH_PORT" -eq "$UI_LOCAL_PORT" ] || [ "$SSH_PORT" -eq "$UI_REMOTE_PORT" ]; do
        generate_random_ports
    done
}

# Генерация случайных значений для EMAIL
generate_random_mail(){
    MAIL=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9')
    DOMAIN=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9')
    EMAIL=${MAIL}@${DOMAIN}.com
}

generate_random_data() {
    generate_random_ports
    ensure_unique_ports    
    generate_random_mail
}

# Функция для проверки, является ли строка IP-адресом
is_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0  # Это IP-адрес
    else
        return 1  # Это не IP-адрес
    fi
}

# Функция для редактирования config.json
# Пример использования функции для изменения определенных полей
# XUI_CONFIG_FILE 'log.loglevel' '"info"'
# XUI_CONFIG_FILE 'inbounds[0].port' 8282

XUI_CONFIG_FILE() {
    local key="$1"
    local new_value="$2"

    # Проверка наличия файла
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Файл конфигурации не найден: $XUI_CONFIG_FILE"
        exit 1
    fi

    # Редактирование с использованием jq
    if jq . "$XUI_CONFIG_FILE" > /dev/null 2>&1; then
        jq ".$key = $new_value" "$XUI_CONFIG_FILE" > "$XUI_CONFIG_FILE.tmp" && mv "$XUI_CONFIG_FILE.tmp" "$XUI_CONFIG_FILE"
        echo "Значение $key успешно изменено на $new_value."
    else
        echo "Ошибка в структуре файла JSON."
        exit 1
    fi
}