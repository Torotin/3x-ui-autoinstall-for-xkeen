#!/bin/bash
# modules/variables.sh

# Этот модуль содержит глобальные переменные, используемые в различных частях скрипта.

MAIN_IP=$(curl -s ipinfo.io/ip)

# Путь к скрипту баннера SSH
banner_script_path="/etc/profile.d/ssh_banner.sh"
geoupdate_cron_sh="/usr/local/x-ui/geoupdate.sh"
XUI_CONFIG_FILE="/usr/local/x-ui/bin/config.json"
UFW_BEFORERULES_FILE="/etc/ufw/before.rules"

# Лог-файл
LOG_FILE="/var/log/Install_XKeen_Server.log"

# Флаги и параметры
AUTO_REBOOT=true
FORCE_RESTART_SSH=false
ENABLE_BBR=false
UPDATE_PACKAGES=false
CLEAR_FIREWALL="ask"  # Возможные значения: true, false, ask

# Пользовательские данные
RSA=""
DNS=""
dest=""
user_input_sni=""
newuser=""
password=""
lgn=""
psw=""
MAIL=""
EMAIL=""
caddyfile="/etc/caddy/Caddyfile"
cert_dir="/etc/ssl/private"
self_crt="$cert_dir/$MAIN_IP.crt"
self_key="$cert_dir/$MAIN_IP.key"

# Порты
SSH_PORT=""
UI_LOCAL_PORT=""
UI_REMOTE_PORT=""
HTTP_PORT=""

# Пути и URL
WEB_PATH=""

# Переменные для API взаимодействия
URL=""
URL_LOGIN=""
URL_API=""
URL_SERVER=""
COOKIES=""
privateKey=""
publicKey=""
inboundid=""
DOMAIN=""

#fail2ban
fail2ban_max_retry=3
fail2ban_ban_time=43200
fail2ban_find_time=600