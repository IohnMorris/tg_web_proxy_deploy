#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

REPO_URL="https://github.com/telegramdesktop/tproxy-server.git"
INSTALL_DIR="/opt/tproxy-server"
SITE_DIR="/srv/tproxy-site"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
cyan()  { printf '\033[36m%s\033[0m\n' "$*"; }
die()   { red "Ошибка: $*"; exit 1; }
ask() {
  local prompt="$1" var="$2" value=""
  read -r -p "$prompt" value
  printf -v "$var" '%s' "$value"
}

trap 'rc=$?; red "Установка прервана (код $rc)."; exit "$rc"' ERR

[[ $EUID -eq 0 ]] || die "Запустите скрипт от имени root: sudo bash $0"

printf '\n'
cyan '============================================================'
cyan '  Telegram WEB Proxy — Автоматическое развёртывание'
cyan '============================================================'
printf '\n'

ask "Домен для прокси (например, proxy.example.com): " HOST
HOST="${HOST,,}"

ask "Email для сертификата (нажми Enter, чтобы использовать адрес по умолчанию): " EMAIL
if [[ -z "$EMAIL" ]]; then
  EMAIL="admin@${HOST}"
  green "Будет использован email: $EMAIL"
fi

SECRET_HEX="$(openssl rand -hex 16)"
SECRET_B64="$(python3 -c "import base64; print(base64.urlsafe_b64encode(bytes.fromhex('$SECRET_HEX')).decode().rstrip('='))")"

green "Сгенерирован серверный секрет (HEX): $SECRET_HEX"
green "Сгенерирован секрет для ссылки (Base64): $SECRET_B64"

yellow "Подготовка публичной директории сайта ($SITE_DIR)..."
mkdir -p "$SITE_DIR"
cat > "$SITE_DIR/index.html" <<HTML
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <title>${HOST}</title>
</head>
<body><h1>Сайт находится в разработке.</h1></body>
</html>
HTML
chmod -R 755 "$SITE_DIR"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git nftables openssl jq python3

if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --depth=1 origin
  git -C "$INSTALL_DIR" checkout -f FETCH_HEAD
else
  git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

cyan "\nЗапуск официального установщика tproxy-server..."
./deploy/install.sh \
  --hostname "$HOST" \
  --email "$EMAIL" \
  --site-dir "$SITE_DIR" \
  --secret "$SECRET_HEX"

sleep 3

CONFIG_FILE="/etc/tproxy-server/config.json"
if [[ -f "$CONFIG_FILE" ]]; then
  BASE_PATH=$(jq -r '.base_path // empty' "$CONFIG_FILE" 2>/dev/null)
else
  die "Файл конфигурации $CONFIG_FILE не найден."
fi

SERVER_ENCODED="${HOST}%2F${BASE_PATH}"
TG_LINK="https://t.me/webproxy?server=${SERVER_ENCODED}&secret=${SECRET_B64}"

printf '\n'
cyan '============================================================'
green 'Установка успешно завершена!'
cyan '============================================================'
printf '\n'

yellow "Твои данные для подключения:"
printf 'Домен (Server): %s\n' "$HOST"
printf 'Путь (Path):    /%s\n' "$BASE_PATH"
printf 'Секрет (Secret): %s\n' "$SECRET_B64"

printf '\n'
green "Готовая ссылка для Telegram (скопируй и нажми):"
printf '\033[1;32m%s\033[0m\n\n' "$TG_LINK"
