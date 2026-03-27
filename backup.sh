#!/bin/bash
# Подключения через schnitzler/mysqldump и fallback на mysql:8
# Если  schnitzler/mysqldump не может подключиться к MySQL (нет поддерки caching_sha2_password), запускаем mysqldump из mysql:8

set -euo pipefail

APP_DIR="/opt/shvirtd-example-python"
BACKUP_DIR="/opt/backup"
LOG_FILE="/opt/backup.log"
DATE=$(date +%F_%H-%M-%S)

mkdir -p "$BACKUP_DIR"

# -------------------------------
# Функция логирования
# -------------------------------
log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

log "🔐 Загрузка переменных"

# -------------------------------
# Загрузка .env
# -------------------------------
if [ -f "$APP_DIR/.env" ]; then
    set -a
    source "$APP_DIR/.env"
    set +a
else
    log "❌ .env не найден"
    exit 1
fi

# -------------------------------
# Поиск сети
# -------------------------------
log "🔍 Поиск сети backend..."

NETWORK=$(docker network ls --format '{{.Name}}' | grep '_backend$' | head -n 1)

if [ -z "$NETWORK" ]; then
    log "❌ Сеть backend не найдена"
    exit 1
fi

log "🌐 Используем сеть: $NETWORK"

# -------------------------------
# Ожидание БД
# -------------------------------
log "⏳ Проверка доступности БД..."

DB_READY=false

for i in {1..10}; do
    if docker run --rm \
        --network "$NETWORK" \
        mysql:8 \
        sh -c "mysql -h db -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'SELECT 1;'" \
        > /dev/null 2>&1; then

        DB_READY=true
        log "✅ БД доступна"
        break
    fi

    log "⏳ Ждём БД ($i/10)..."
    sleep 3
done

if [ "$DB_READY" = false ]; then
    log "❌ БД недоступна"
    exit 1
fi

# -------------------------------
# Проверка schnitzler
# -------------------------------
log "🔍 Проверка schnitzler/mysqldump..."

SCHNITZLER_OK=false

if docker run --rm \
    --network "$NETWORK" \
    -e MYSQL_HOST=db \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    schnitzler/mysqldump \
    sh -c "mysql -h \$MYSQL_HOST -u \$MYSQL_USER -p\$MYSQL_PASSWORD -e 'SELECT 1;'" \
    > /dev/null 2>&1; then

    SCHNITZLER_OK=true
    log "✅ schnitzler подключается к БД"
else
    log "⚠️ schnitzler не работает → используем fallback"
fi

# -------------------------------
# Создание backup
# -------------------------------
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.sql"

if [ "$SCHNITZLER_OK" = true ]; then
    log "📦 Backup через schnitzler..."

    docker run --rm \
        --network "$NETWORK" \
        -e MYSQL_HOST=db \
        -e MYSQL_USER="$MYSQL_USER" \
        -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
        -e MYSQL_DATABASE="$MYSQL_DATABASE" \
        schnitzler/mysqldump \
        > "$BACKUP_FILE" 2>>"$LOG_FILE"

    log "✅ Backup создан (schnitzler)"

else
    log "📦 Backup через mysql:8 ..."

    docker run --rm \
        --network "$NETWORK" \
        mysql:8 \
        sh -c "mysqldump -h db -uroot -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE" \
        > "$BACKUP_FILE" 2>>"$LOG_FILE"

    log "✅ Backup создан (mysql:8)"
fi

# -------------------------------
# Проверка backup
# -------------------------------
if [ ! -s "$BACKUP_FILE" ]; then
    log "❌ Backup пустой или не создан"
    exit 1
fi

# -------------------------------
# Очистка старых backup
# -------------------------------
log "🧹 Очистка старых backup..."

find "$BACKUP_DIR" -type f -name "*.sql" -mtime +1 -delete

log "🎉 Backup успешно завершён"