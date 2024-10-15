#!/bin/bash
# modules/network_optimization.sh

enable_bbr() {
    log "INFO" "Включение BBR и оптимизация сетевых настроек..."

    # Проверяем версию ядра (BBR поддерживается в ядрах 4.9 и выше)
    kernel_version=$(uname -r)
    if [[ $(uname -r | awk -F. '{print $1$2}') -lt 49 ]]; then
        log "ERROR" "BBR не поддерживается на ядрах ниже 4.9. Текущая версия ядра: $kernel_version"
        return 1
    fi

    # Загружаем модуль tcp_bbr, если он не загружен
    if ! lsmod | grep -q "tcp_bbr"; then
        if ! modprobe tcp_bbr; then
            log "ERROR" "Не удалось загрузить модуль tcp_bbr."
            return 1
        fi
    fi

    # Проверяем доступные алгоритмы управления перегрузкой
    if sysctl net.ipv4.tcp_available_congestion_control | grep -qw "bbr"; then
        log "INFO" "BBR поддерживается ядром."
    else
        log "ERROR" "BBR не доступен. Убедитесь, что ваше ядро поддерживает BBR."
        return 1
    fi

    # Создаем резервную копию файла /etc/sysctl.conf
    if ! backup_file "/etc/sysctl.conf"; then
        log "ERROR" "Не удалось создать резервную копию /etc/sysctl.conf"
        return 1
    fi

    # Определение параметров, которые нужно удалить
    local settings_to_remove=(
        "net.core.default_qdisc"
        "net.ipv4.tcp_congestion_control"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.core.wmem_default"
        "net.core.netdev_max_backlog"
        "net.core.somaxconn"
        "net.ipv4.tcp_syncookies"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_keepalive_time"
        "net.ipv4.tcp_keepalive_probes"
        "net.ipv4.tcp_keepalive_intvl"
        "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_max_tw_buckets"
        "net.ipv4.tcp_fastopen"
        "net.ipv4.tcp_mem"
        "net.ipv4.udp_mem"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_mtu_probing"
        "net.ipv4.tcp_slow_start_after_idle"
        "fs.inotify.max_user_instances"
        "net.ipv4.ip_local_port_range"
        "net.ipv4.icmp_echo_ignore_all"
        "net.ipv4.icmp_echo_ignore_broadcasts"
        "net.core.netdev_budget"
        "net.core.netdev_budget_usecs"
        "net.core.busy_poll"
        "net.ipv4.tcp_no_metrics_save"
        "net.ipv4.tcp_sack"
        "net.ipv4.tcp_fack"
        "net.ipv4.tcp_window_scaling"
        "net.ipv4.tcp_moderate_rcvbuf"
        "net.ipv4.tcp_low_latency"
        "net.ipv4.route.flush"
    )

    # Удаляем старые сетевые настройки из /etc/sysctl.conf
    for setting in "${settings_to_remove[@]}"; do
        sed -i "/^\s*${setting}\s*=.*/d" /etc/sysctl.conf
        log "INFO" "Удалена старая настройка: $setting"
    done

    # Определяем новые сетевые параметры
    local new_settings=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
        "net.core.rmem_max=67108864"
        "net.core.wmem_max=67108864"
        "net.core.wmem_default=33554432"
        "net.core.netdev_max_backlog=250000"
        "net.core.somaxconn=4096"
        "net.ipv4.tcp_syncookies=1"
        "net.ipv4.tcp_tw_reuse=1"
        "net.ipv4.tcp_fin_timeout=30"
        "net.ipv4.tcp_keepalive_time=1200"
        "net.ipv4.tcp_keepalive_probes=5"
        "net.ipv4.tcp_keepalive_intvl=30"
        "net.ipv4.tcp_max_syn_backlog=8192"
        "net.ipv4.tcp_max_tw_buckets=5000"
        "net.ipv4.tcp_fastopen=3"
        "net.ipv4.tcp_mem=786432 1048576 1572864"
        "net.ipv4.udp_mem=65536 131072 262144"
        "net.ipv4.tcp_rmem=4096 87380 67108864"
        "net.ipv4.tcp_wmem=4096 65536 67108864"
        "net.ipv4.tcp_mtu_probing=1"
        "net.ipv4.tcp_slow_start_after_idle=0"
        "fs.inotify.max_user_instances=8192"
        "net.ipv4.ip_local_port_range=10240 65535"
        "net.ipv4.icmp_echo_ignore_all=1"
        "net.ipv4.icmp_echo_ignore_broadcasts=1"
        "net.core.netdev_budget=600"
        "net.core.netdev_budget_usecs=8000"
        "net.core.busy_poll=50"
        "net.ipv4.tcp_no_metrics_save=1"
        "net.ipv4.tcp_sack=1"
        "net.ipv4.tcp_fack=1"
        "net.ipv4.tcp_window_scaling=1"
        "net.ipv4.tcp_moderate_rcvbuf=1"
        "net.ipv4.tcp_low_latency=1"
        "net.ipv4.route.flush=1"
    )

    # Обновляем или добавляем новые настройки в /etc/sysctl.conf
    for setting in "${new_settings[@]}"; do
        key="${setting%%=*}"
        value="${setting#*=}"

        # Проверяем, существует ли ключ в файле /etc/sysctl.conf
        if grep -q "^\s*${key}\s*=" /etc/sysctl.conf; then
            # Обновляем значение настройки
            sed -i "s|^\s*${key}\s*=.*|${key}=${value}|" /etc/sysctl.conf
            log "INFO" "Обновлена настройка: ${key}=${value}"
        else
            # Добавляем новую настройку
            echo "${key}=${value}" >> /etc/sysctl.conf
            log "INFO" "Добавлена новая настройка: ${key}=${value}"
        fi
    done

    # Применяем все настройки из файла /etc/sysctl.conf
    if ! sysctl -p /etc/sysctl.conf; then
        log "ERROR" "Не удалось применить сетевые настройки."
        return 1
    fi

    # Проверяем, активирован ли BBR
    current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$current_cc" == "bbr" ]]; then
        log "INFO" "BBR успешно активирован."
    else
        log "ERROR" "Не удалось активировать BBR."
        return 1
    fi

    log "INFO" "Оптимизация сетевых настроек завершена успешно."
}