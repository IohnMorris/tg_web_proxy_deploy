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

# Генерируем только HEX-секрет для установщика tproxy-server
SECRET_HEX="$(openssl rand -hex 16)"
green "Сгенерирован серверный секрет (HEX): $SECRET_HEX"

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

# Даем сервисам пару секунд на старт и сохранение конфигов
sleep 3

# Извлекаем сгенерированный base_path и готовый SECRET из конфигурации
BASE_PATH=""
SECRET_B64_FINAL=""
CONFIG_FILE="/etc/tproxy-server/config.json"

if [[ -f "$CONFIG_FILE" ]]; then
  BASE_PATH=$(jq -r '.base_path // empty' "$CONFIG_FILE" 2>/dev/null)
  SECRET_B64_FINAL=$(jq -r '.secret // empty' "$CONFIG_FILE" 2>/dev/null)
else
  die "Файл конфигурации $CONFIG_FILE не найден."
fi

[[ -z "$BASE_PATH" ]] && die "Не удалось получить base_path из конфигурации."
[[ -z "$SECRET_B64_FINAL" ]] && die "Не удалось получить финальный secret из конфигурации."

# Формируем итоговую ссылку
SERVER_ENCODED="${HOST}%2F${BASE_PATH}"
TG_LINK="https://t.me/webproxy?server=${SERVER_ENCODED}&secret=${SECRET_B64_FINAL}"

printf '\n'
cyan '============================================================'
green 'Установка успешно завершена!'
cyan '============================================================'
printf '\n'

yellow "Твои данные для подключения:"
printf 'Домен (Server): %s\n' "$HOST"
printf 'Путь (Path):    /%s\n' "$BASE_PATH"
printf 'Секрет (Secret): %s\n' "$SECRET_B64_FINAL"

printf '\n'
green "Готовая ссылка для Telegram (скопируй и нажми):"
printf '\033[1;32m%s\033[0m\n\n' "$TG_LINK"
