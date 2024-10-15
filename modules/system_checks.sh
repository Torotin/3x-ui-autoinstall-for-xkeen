#!/bin/bash
# modules/system_checks.sh

# Функция для проверки системных ресурсов
check_system_resources() {
    log "INFO" "Проверка системных ресурсов..."

    # Проверка прав root
    if [ "$EUID" -ne 0 ]; then
        error_exit "Этот скрипт должен быть запущен от имени root."
    fi

    # Проверка доступного места на диске
    required_space_mb=1024  # Требуется 1 ГБ свободного места
    available_space_mb=$(df / | tail -1 | awk '{print $4}')
    available_space_mb=$((available_space_mb / 1024))

    if (( available_space_mb < required_space_mb )); then
        error_exit "Недостаточно места на диске. Требуется: ${required_space_mb}MB, Доступно: ${available_space_mb}MB"
    fi

    # Проверка наличия команды systemctl
    if ! command_exists systemctl; then
        error_exit "Для работы скрипта требуется systemd."
    fi

    log "INFO" "Проверка системных ресурсов пройдена."
}

# Функция для проверки интернет-соединения
check_internet_connection() {
    log "INFO" "Проверка интернет-соединения..."
    if ! ping -c 1 ipinfo.io &>/dev/null; then
        error_exit "Не обнаружено интернет-соединение. Пожалуйста, проверьте сетевые настройки."
    fi
    log "INFO" "Интернет-соединение активно."
}

# Определение ассоциативного массива с необходимыми командами и соответствующими пакетами
# Ключи массива - команды, которые должны быть доступны в системе
# Значения массива - названия пакетов, которые содержат соответствующие команды
declare -A required_commands=(
    ["mc"]="mc"                        # Midnight Commander
    ["perl"]="perl"                    # Интерпретатор Perl
    ["curl"]="curl"                    # Инструмент для передачи данных с URL
    ["caddy"]="caddy"                  # Веб-сервер Caddy
    ["fail2ban-client"]="fail2ban"     # Инструмент Fail2Ban для блокировки IP-адресов
    ["openssl"]="openssl"              # Набор инструментов для работы с SSL/TLS
    ["lsof"]="lsof"                    # Просмотр открытых файлов
    ["ufw"]="ufw"                      # Простая настройка брандмауэра
    ["shuf"]="coreutils"               # Перемешивание строк файла или ввода
    ["top"]="procps"                   # Мониторинг активности процессов
    ["free"]="procps"                  # Отображение информации о свободной и занятой памяти
    ["df"]="coreutils"                 # Отчет о свободном месте на дисках
    ["journalctl"]="systemd"           # Просмотр журнала systemd
    ["jq"]="jq"                        # Инструмент для обработки JSON из командной строки
    ["gzip"]="gzip"                    # Утилита для сжатия файлов
    ["cron"]="cron"                    # Планировщик задач, позволяет запускать команды по расписанию
)


# Инициализация массива отсутствующих пакетов
missing_packages=()

# Функция для проверки наличия команды
check_command() {
    local command="$1"
    local package="$2"

    # Если команда отсутствует, добавляем пакет для установки
    if ! command_exists "$command"; then
        log "WARN" "Команда '$command' не найдена, добавляем пакет '$package' в список для установки."
        missing_packages+=("$package")
    else
        log "INFO" "Команда '$command' уже установлена."
    fi
}

# Функция для проверки всех необходимых команд
check_required_commands() {
    # Проверяем каждую команду из массива required_commands
    for cmd in "${!required_commands[@]}"; do
        check_command "$cmd" "${required_commands[$cmd]}"
    done
}

# Функция для установки недостающих пакетов на Ubuntu
install_packages() {
    if [ ${#missing_packages[@]} -gt 0 ]; then
        # Удаляем дубликаты в массиве недостающих пакетов
        missing_packages=($(printf "%s\n" "${missing_packages[@]}" | sort -u))

        log "INFO" "Установка недостающих пакетов: ${missing_packages[*]}"

        # Обновляем списки пакетов и устанавливаем недостающие
        apt-get update || error_exit "Не удалось обновить списки пакетов!"
        apt-get install -y "${missing_packages[@]}" || error_exit "Не удалось установить некоторые пакеты!"

        log "INFO" "Все необходимые пакеты установлены."
    else
        log "INFO" "Все необходимые пакеты уже установлены."
    fi
}


# Функция для обновления и апгрейда пакетов
update_and_upgrade_packages() {
    log "INFO" "Обновление и апгрейд системных пакетов..."
    apt-get update && apt-get upgrade -y
    log "INFO" "Системные пакеты обновлены и обновления установлены."
}
