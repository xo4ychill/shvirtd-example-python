#!/bin/bash

set -euo pipefail

# ---------------- CONFIG ----------------
BACKUP_DIR="/opt/backup"
ENV_FILE="/opt/shvirtd-example-python/.env"
DATE=$(date +%F_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.sql"

# ---------------- INIT ----------------
echo "=== START BACKUP $(date) ==="

# создаём папку
mkdir -p "$BACKUP_DIR"

# загружаем переменные
if [[ -f "$ENV_FILE" ]]; then
    sed -i 's/\r$//' "$ENV_FILE"
    source "$ENV_FILE"
else
    echo "❌ .env не найден"
    exit 1
fi

# проверка переменных
: "${MYSQL_USER:?not set}"
: "${MYSQL_PASSWORD:?not set}"
: "${MYSQL_DATABASE:?not set}"

# ---------------- FIND DB ----------------
DB_CONTAINER=$(docker ps --filter "name=db" --format '{{.Names}}' | head -n1)

if [[ -z "$DB_CONTAINER" ]]; then
    echo "❌ Контейнер db не найден"
    exit 1
fi

echo "DB контейнер: $DB_CONTAINER"

# сеть контейнера
NETWORK=$(docker inspect "$DB_CONTAINER" \
  --format '{{range $k, $v := .NetworkSettings.Networks}}{{printf "%s\n" $k}}{{end}}' | head -n1)

echo "Сеть: $NETWORK"

# IP контейнера
DB_IP=$(docker inspect "$DB_CONTAINER" \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

echo "IP: $DB_IP"

# ---------------- BACKUP ----------------
echo "Создание бэкапа..."
docker run --rm \
  --network container:$DB_CONTAINER \
  -e MYSQL_HOST=db \
  -e MYSQL_USER=root \
  -e MYSQL_PASSWORD="$MYSQL_ROOT_PASSWORD" \
  -e MYSQL_DATABASE="$MYSQL_DATABASE" \
  schnitzler/mysqldump > "$BACKUP_FILE"

# проверка файла
if [[ -s "$BACKUP_FILE" ]]; then
    echo "✅ Бэкап создан: $BACKUP_FILE"
else
    echo "❌ Бэкап пустой"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# ---------------- ROTATION ----------------
find "$BACKUP_DIR" -name "backup_*.sql" -type f -mtime +7 -delete

echo "=== END BACKUP $(date) ==="
