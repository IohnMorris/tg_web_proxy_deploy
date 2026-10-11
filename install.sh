#!/usr/bin/env bash
# Автоматический установщик Telegram WEB Proxy (official tproxy-server)
# Tested target: Ubuntu 22.04+/Debian 12+, x86_64, systemd.
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
[[ "$(uname -s)" == Linux ]] || die "Скрипт предназначен только для Linux."
[[ "$(uname -m)" == x86_64 ]] || die "Требуется архитектура сервера x86_64."
command -v systemctl >/dev/null || die "Для работы требуется система с systemd."

printf '\n'
cyan '============================================================'
cyan '  Telegram WEB Proxy — Автоматическое развёртывание'
cyan '============================================================'
printf '\n'

ask "Домен для прокси (например, proxy.example.com): " HOST
HOST="${HOST,,}"
[[ "$HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && "$HOST" == *.* ]] || die "Некорректный домен."

ask "Email для сертификата (нажми Enter, чтобы использовать адрес по умолчанию): " EMAIL
if [[ -z "$EMAIL" ]]; then
  EMAIL="admin@${HOST}"
  green "Будет использован email: $EMAIL"
elif [[ ! "$EMAIL" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  die "Некорректный email."
fi

# 1. Генерируем 16-байтный секрет в формате HEX (32 символа) для сервера
SECRET_HEX="$(openssl rand -hex 16)"
# 2. Конвертируем этот HEX-секрет в Base64URL для Telegram-ссылки
SECRET_B64="$(python3 -c "import base64; print(base64.urlsafe_b64encode(bytes.fromhex('$SECRET_HEX')).decode().rstrip('='))")"

green "Сгенерирован серверный секрет (HEX): $SECRET_HEX"
green "Сгенерирован секрет для ссылки (Base64): $SECRET_B64"

# 3. Создаем директорию для сайта, чтобы tproxy-server не падал при запуске
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

# 4. Устанавливаем зависимости
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git nftables openssl jq python3

# 5. Скачиваем официальный репозиторий
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --depth=1 origin
  git -C "$INSTALL_DIR" checkout -f FETCH_HEAD
else
  git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# 6. Запускаем официальный установщик (передаем ему правильный HEX-секрет)
cyan "\nЗапуск официального установщика tproxy-server..."
./deploy/install.sh \
  --hostname "$HOST" \
  --email "$EMAIL" \
  --site-dir "$SITE_DIR" \
  --secret "$SECRET_HEX"

# Даем сервисам пару секунд на старт
sleep 3
systemctl --no-pager status caddy mtproxy tproxy-server >/dev/null 2>&1 || true

# 7. Извлекаем сгенерированный base_path из конфигурации
BASE_PATH=""
CONFIG_FILE="/etc/tproxy-server/config.json"

if [[ -f "$CONFIG_FILE" ]]; then
  BASE_PATH=$(jq -r '.base_path // empty' "$CONFIG_FILE" 2>/dev/null)
else
  die "Файл конфигурации $CONFIG_FILE не найден. Установка завершилась с ошибкой."
fi

[[ -z "$BASE_PATH" ]] && die "Не удалось получить base_path из конфигурации."

# 8. Формируем итоговую ссылку
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

# 9. Важное предупреждение о маскировке сайта
red "⚠️ ВАЖНО ДЛЯ ОБХОДА БЛОКИРОВОК (DPI):"
yellow "Сейчас по адресу https://${HOST} установлена простая заглушка."
yellow "ОБЯЗАТЕЛЬНО замените содержимое папки ${SITE_DIR} на свой полноценный сайт."
yellow "Вы можете:"
yellow "  1. Сгенерировать красивый лендинг или блог с помощью ИИ."
yellow "  2. Скачать любой бесплатный HTML-шаблон из интернета."
yellow "  3. Загрузить свой уже готовый сайт."
yellow "Это нужно, чтобы ваш сервер выглядел как обычный веб-ресурс и не вызывал подозрений."
printf '\n'
