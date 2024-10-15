#!/bin/bash
# main.sh

# Определение пути к каталогу скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Подключение модулей
source "$SCRIPT_DIR/modules/variables.sh"
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/system_checks.sh"
source "$SCRIPT_DIR/modules/user_input.sh"
source "$SCRIPT_DIR/modules/user_setup.sh"
source "$SCRIPT_DIR/modules/service_setup.sh"
source "$SCRIPT_DIR/modules/network_optimization.sh"
source "$SCRIPT_DIR/modules/firewall_setup.sh"
source "$SCRIPT_DIR/modules/api_functions.sh"
source "$SCRIPT_DIR/modules/html_create.sh"
source "$SCRIPT_DIR/modules/ssh_banner.sh"
source "$SCRIPT_DIR/modules/ssh_config.sh"
source "$SCRIPT_DIR/modules/caddy_config.sh"


# Основная функция
main() {
    local key_used=false

    # Парсинг опций командной строки
    # Цикл while использует getopts для обработки опций, переданных в скрипт
    while getopts ":u:p:l:s:r:d:t:n:fhbcRU" opt; do
        key_used=true  # Флаг, указывающий, что были использованы опции командной строки
        case $opt in
            u) newuser="$OPTARG"  # Опция для указания имени нового системного пользователя
            ;;
            p) password="$OPTARG"  # Опция для указания пароля нового пользователя
            ;;
            l) lgn="$OPTARG"  # Опция для указания имени пользователя 3X-UI
            ;;
            s) psw="$OPTARG"  # Опция для указания пароля пользователя 3X-UI
            ;;
            r) RSA="$OPTARG"  # Опция для указания публичного ключа RSA
            ;;
            d) DNS="$OPTARG"  # Опция для указания доменного имени
            ;;
            t) dest="$OPTARG"  # Опция для указания целевого URL или сайта для маскировки
            ;;
            n) user_input_sni="$OPTARG"  # Опция для указания значений SNI через запятую
            ;;
            f) FORCE_RESTART_SSH=true  # Флаг для принудительного перезапуска службы SSH после изменений
            ;;
            b) ENABLE_BBR=true  # Флаг для включения BBR и оптимизации сети
            ;;
            R) AUTO_REBOOT=true  # Флаг для автоматической перезагрузки системы после завершения скрипта
            ;;
            U) UPDATE_PACKAGES=true  # Флаг для обновления и установки необходимых пакетов
            ;;
            c) CLEAR_FIREWALL=true  # Флаг для сброса правил брандмауэра
            ;;
            h)
                # Показ сообщения с доступными опциями и выход из скрипта
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  -u ИМЯ_ПОЛЬЗОВАТЕЛЯ   Новое системное имя пользователя"
                echo "  -p ПАРОЛЬ            Пароль для нового пользователя"
                echo "  -l ИМЯ_UI            Имя пользователя для 3X-UI"
                echo "  -s ПАРОЛЬ_UI         Пароль для 3X-UI"
                echo "  -r RSA_КЛЮЧ          Публичный ключ RSA"
                echo "  -d ДОМЕН             Доменное имя"
                echo "  -t ЦЕЛЬ              URL или сайт для использования"
                echo "  -n SNI               Значения SNI через запятую"
                echo "  -f                   Принудительный перезапуск службы SSH после изменений"
                echo "  -b                   Включение BBR и оптимизация сети"
                echo "  -R                   Автоматически перезагрузить систему после выполнения скрипта"
                echo "  -U                   Обновить и установить необходимые пакеты"
                echo "  -c                   Сбросить правила брандмауэра"
                echo "  -h                   Показать это сообщение помощи"
                exit 0  # Завершаем выполнение скрипта после показа справки
            ;;
            \?) error_exit "Неверная опция -$OPTARG"  # Обработка ошибок для невалидных опций
            ;;
        esac
    done

    # Проверка, были ли использованы ключи
    if [ "$key_used" = false ]; then
        log "INFO" "No command-line options were used"
        FORCE_RESTART_SSH=false
        ENABLE_BBR=true
        AUTO_REBOOT=true
        UPDATE_PACKAGES=true
        CLEAR_FIREWALL=ask
    fi

    log "DEBUG" "Парсинг параметров завершен:"
    log "DEBUG" "-u Имя пользователя: $newuser"
    log "DEBUG" "-p Пароль: $password"
    log "DEBUG" "-l Имя UI: $lgn"
    log "DEBUG" "-s Пароль UI: $psw"
    log "DEBUG" "-r Ключ RSA: $RSA"
    log "DEBUG" "-d Домен: $DNS"
    log "DEBUG" "-t Целевой URL: $dest"
    log "DEBUG" "-n Значения SNI: $user_input_sni"
    log "DEBUG" "-f Принудительный перезапуск SSH: $FORCE_RESTART_SSH"
    log "DEBUG" "-b Включение BBR: $ENABLE_BBR"
    log "DEBUG" "-R Автоматическая перезагрузка: $AUTO_REBOOT"
    log "DEBUG" "-U Обновление пакетов: $UPDATE_PACKAGES"
    log "DEBUG" "-c Очистка брандмауэра: $CLEAR_FIREWALL"

    log "INFO" "Запуск скрипта..."

    check_internet_connection

    check_system_resources

    generate_random_data
    log "INFO" "Порты успешно сгенерированы: SSH_PORT=$SSH_PORT, UI_LOCAL_PORT=$UI_LOCAL_PORT, UI_REMOTE_PORT=$UI_REMOTE_PORT"

    log "INFO" "Сбор данных пользователя..."
    user_input_data

    # Установка обновлений и необходимых пакетов, если указано
    if [ "${UPDATE_PACKAGES:-false}" = true ]; then
        log "INFO" "Обновление и модернизация пакетов..."
        update_and_upgrade_packages
    fi

    log "INFO" "Установка необходимых пакетов..."
    check_required_commands
    install_packages

    log "INFO" "Создание или обновление пользователя..."
    create_user

    log "INFO" "Настройка SSH..."
    configure_ssh

    log "INFO" "Настройка Fail2Ban..."
    configure_fail2ban

    log "INFO" "Установка 3X-UI..."
    install_3x_ui

    log "INFO" "Настройка брандмауэра..."
    firewall_config

    log "INFO" "Создание HTML-страницы..."
    html_create

    log "INFO" "Настройка Caddy..."
    caddy_config

    # Включение BBR, если указано
    if [ "${ENABLE_BBR:-false}" = true ]; then
        log "INFO" "Включение BBR..."
        enable_bbr
    fi

    log "INFO" "Обновление GEO-файлов..."
    update_geo

    log "INFO" "Создание динамического баннера SSH..."
    create_ssh_banner_script

    generate_new_inbound

    log "WARN" "Конфигурация завершена!"
    log "WARN" "SSH_PORT: $SSH_PORT"
    if [[ -n "$DNS" ]]; then
        log "WARN" "Панель доступна по адресу https://$DNS:$UI_REMOTE_PORT/$WEB_PATH"
    else
        log "WARN" "Панель доступна по адресу https://$MAIN_IP:$UI_REMOTE_PORT/$WEB_PATH"
    fi
    log "WARN" "Имя пользователя 3X-UI: $lgn"
    log "WARN" "Пароль 3X-UI: $psw"

    # Принудительный перезапуск службы SSH, если указано
    if [ "${FORCE_RESTART_SSH:-false}" = true ]; then
        systemctl restart ssh || log "ERROR" "Не удалось перезапустить демон SSH!"
    fi

    # Выполнение перезагрузки или уведомление
    if [ "$AUTO_REBOOT" = true ]; then
        log "INFO" "Хотите перезагрузить систему? (y/n, будет автоматически перезагружено через 10 секунд)"

        read -t 20 -p "Введите y для перезагрузки или n для отмены: " answer

        # Проверка ответа
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            log "INFO" "Пользователь согласился на перезагрузку."
            log "INFO" "Система перезагружается..."
            sleep 5
            sudo reboot now || error_exit "Не удалось перезагрузить систему."
        else
            log "INFO" "Пользователь не ответил или отказался"
        fi

    else
        log "INFO" "Пожалуйста, перезагрузите систему вручную, если это необходимо."
    fi
}

# Вызов основной функции
main "$@"
