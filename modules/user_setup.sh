#!/bin/bash
# modules/user_setup.sh

# Функция для создания или обновления пользователя
create_user() {
    log "INFO" "Проверка существования пользователя $newuser..."

    # Проверяем, существует ли пользователь
    if id "$newuser" &>/dev/null; then
        log "INFO" "Пользователь $newuser уже существует. Обновление пароля..."
        echo "$newuser:$password" | chpasswd
    else
        log "INFO" "Создание нового пользователя $newuser..."
        useradd -m -s /bin/bash "$newuser"
        echo "$newuser:$password" | chpasswd
        usermod -aG sudo "$newuser"
        log "INFO" "Пользователь $newuser создан и добавлен в группу sudo."
    fi

    # Настройка SSH для пользователя
    local ssh_dir="/home/$newuser/.ssh"
    mkdir -p "$ssh_dir"
    touch "$ssh_dir/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "$ssh_dir/authorized_keys"
    chown -R "$newuser:$newuser" "$ssh_dir"

    # Добавление RSA ключа, если он задан
    if [ -n "$RSA" ]; then
        log "INFO" "Добавление RSA ключа для пользователя $newuser..."
        echo "$RSA" >> "$ssh_dir/authorized_keys"
    fi

    user_sudoers

    log "INFO" "Настройка пользователя $newuser завершена."
}

user_sudoers() {
    log "INFO" "Настройка sudo для пользователя $newuser..."

    # Определение записи и файла для sudoers
    local sudoers_entry="$newuser ALL=(ALL) NOPASSWD:ALL"
    local sudoers_file="/etc/sudoers.d/$newuser"

    # Проверка, существует ли файл sudoers для пользователя
    if [ -f "$sudoers_file" ]; then
        log "INFO" "Запись для $newuser уже существует в sudoers."
    else
        # Создание файла sudoers для пользователя
        echo "$sudoers_entry" > "$sudoers_file"

        # Установка корректных прав доступа
        chmod 0440 "$sudoers_file"
        chown root:root "$sudoers_file"

        # Проверка синтаксиса файла sudoers
        if visudo -cf "$sudoers_file"; then
            log "INFO" "Пользователь $newuser успешно добавлен в sudoers без пароля."
        else
            rm -f "$sudoers_file"
            error_exit "Ошибка: файл sudoers некорректен. Изменения не применены."
        fi
    fi
}
