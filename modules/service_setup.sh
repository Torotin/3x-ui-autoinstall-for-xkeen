#!/bin/bash
# modules/service_setup.sh

# Функция для установки 3X-UI
install_3x_ui() {
    log "INFO" "Установка 3X-UI..."

    # Проверка на наличие установленной версии 3X-UI и её удаление
    if [ -f /usr/local/x-ui/x-ui ]; then
        log "INFO" "Обнаружена существующая установка 3X-UI. Удаление..."
        echo y | /usr/local/x-ui/x-ui.sh uninstall || log "WARN" "Не удалось удалить существующую установку 3X-UI."
    fi

    # Скачивание скрипта установки 3X-UI
    local install_script="/tmp/3x-ui-install.sh"
    log "INFO" "Скачивание скрипта установки 3X-UI..."
    if ! curl -o "$install_script" -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh; then
        error_exit "Не удалось скачать скрипт установки 3X-UI."
    fi

    # Назначение прав на выполнение скрипта и его запуск
    chmod +x "$install_script"
    log "INFO" "Запуск скрипта установки 3X-UI..."
    if ! echo n | bash "$install_script"; then
        error_exit "Не удалось установить 3X-UI!"
    fi

    # Настройка параметров для 3X-UI
    log "INFO" "Настройка 3X-UI с заданными параметрами..."
    /usr/local/x-ui/x-ui setting -username "$lgn" -password "$psw" -port "$UI_LOCAL_PORT" || error_exit "Не удалось настроить 3X-UI!"

    # Получение и проверка WEB_PATH
    log "INFO" "Получение пути веб-интерфейса (WEB_PATH)..."
    WEB_PATH=$(x-ui settings | grep webBasePath | awk '{print $2}')

    if [ -z "$WEB_PATH" ]; then
        error_exit "WEB_PATH пуст. Невозможно продолжить установку."
    fi

    # Удаление символов '/' из пути
    WEB_PATH="${WEB_PATH//\//}"

    # Логирование значения WEB_PATH для отладки
    log "INFO" "WEB_PATH установлен на: $WEB_PATH"

    log "INFO" "3X-UI успешно установлен и настроен."
}


# Функция для обновления Geo файлов и создания скрипта для cron
update_geo() {
    log "INFO" "Обновление файлов GeoIP и Geosite..."

    local bin_folder="/usr/local/x-ui/bin"
    mkdir -p "$bin_folder"
    local temp_dir
    temp_dir=$(mktemp -d)

    # Список файлов для загрузки
    declare -A files=(
        ["geoip.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        ["geoip_zkeenip.dat"]="https://github.com/jameszeroX/zkeen-ip/releases/latest/download/zkeenip.dat"
        ["geoip_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-IP/releases/latest/download/geoip.dat"
        ["geoip_v2fly.dat"]="https://github.com/loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        ["geosite.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        ["geosite_v2fly.dat"]="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
        ["geosite_antifilter.dat"]="https://github.com/MrYadro/domain-list-community-antifilter/releases/latest/download/dlc.dat"
        ["geosite_antizapret.dat"]="https://github.com/warexify/antizapret-xray/releases/latest/download/antizapret.dat"
        ["geosite_zkeen.dat"]="https://github.com/jameszeroX/zkeen-domains/releases/latest/download/zkeen.dat"
    )

    # Загрузка файлов
    for file in "${!files[@]}"; do
        # Использование curl для загрузки
        if curl -L --fail --silent --show-error -o "${temp_dir}/${file}" "${files[$file]}"; then
            # Проверка наличия скачанного файла
            if [[ -f "${temp_dir}/${file}" ]]; then
                mv -f "${temp_dir}/${file}" "${bin_folder}/" && log "INFO" "Файл ${file} успешно загружен и перемещен в ${bin_folder}" || log "WARN" "Не удалось переместить файл ${file} в ${bin_folder}"
            else
                log "WARN" "Загрузка прошла успешно, но файл ${file} не найден в ${temp_dir}"
            fi
        else
            log "WARN" "Не удалось загрузить файл ${file}"
        fi
    done

    # Очистка временной директории
    rm -rf "$temp_dir"

    # Перезапуск сервиса x-ui
    systemctl restart x-ui || error_exit "Не удалось перезапустить сервис x-ui!"
    log "INFO" "Файлы Geo обновлены успешно."

    # Создание скрипта для cron
    local cron_script_path="$geoupdate_cron_sh"
    log "INFO" "Создание скрипта $cron_script_path для использования в cron..."

    cat <<EOF > "$cron_script_path"
#!/bin/bash
# Скрипт для обновления Geo файлов

log() {
    local level="\$1"
    local message="\$2"
    echo "[\$(date +'%Y-%m-%d %H:%M:%S')] [\$level] \$message"
}

bin_folder="$bin_folder"
temp_dir=\$(mktemp -d)

declare -A files=(
    ["geoip.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    ["geosite.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    ["geosite_v2fly.dat"]="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
    ["geosite_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-Domains/releases/latest/download/geosite.dat"
    ["geosite_antizapret.dat"]="https://github.com/warexify/antizapret-xray/releases/latest/download/antizapret.dat"
    ["geosite_zkeen.dat"]="https://github.com/jameszeroX/zkeen-domains/releases/latest/download/zkeen.dat"
    ["geoip_zkeenip.dat"]="https://github.com/jameszeroX/zkeen-ip/releases/latest/download/zkeenip.dat"
    ["geoip_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-IP/releases/latest/download/geoip.dat"
    ["geoip_v2fly.dat"]="https://github.com/loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
)

for file in "\${!files[@]}"; do
    if curl -L --fail --silent --show-error -o "\${temp_dir}/\${file}" "\${files[\$file]}"; then
        if [[ -f "\${temp_dir}/\${file}" ]]; then
            mv -f "\${temp_dir}/\${file}" "\${bin_folder}/" && log "INFO" "Файл \${file} успешно обновлен." || log "WARN" "Не удалось переместить файл \${file}"
        else
            log "WARN" "Файл \${file} не найден."
        fi
    else
        log "WARN" "Не удалось скачать файл \${file}"
    fi
done

rm -rf "\${temp_dir}"
systemctl restart x-ui || log "ERROR" "Не удалось перезапустить сервис x-ui!"
log "INFO" "Обновление файлов Geo завершено."
EOF

    # Устанавливаем права на выполнение
    chmod +x "$cron_script_path"

    log "INFO" "Скрипт $cron_script_path создан и готов к использованию в cron."
}

# Функция для создания cron задания для обновления Geo файлов
schedule_geo_update() {
    log "INFO" "Настройка cron задания для обновления Geo файлов..."

    # Параметры для cron задания
    local cron_frequency="0 2 * * *"  # Запуск каждый день в 2:00
    local script_path="$geoupdate_cron_sh"  # Путь к скрипту для обновления Geo файлов
    local log_file="/var/log/geo_update.log"  # Файл логов

    # Команда для добавления в cron
    local cron_command="$cron_frequency /bin/bash $script_path >> $log_file 2>&1"

    # Проверяем, существует ли уже задание в cron
    if crontab -l | grep -F "$script_path" > /dev/null; then
        log "INFO" "Задание для обновления Geo файлов уже существует в cron."
    else
        # Добавляем новое задание в cron
        (crontab -l 2>/dev/null; echo "$cron_command") | crontab -
        log "INFO" "Задание для обновления Geo файлов добавлено в cron: $cron_command"
    fi
}
