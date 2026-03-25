#!/bin/bash
# Скрипт резервного копирования MySQL с использованием образа schnitzler/mysqldump
# Запуск: ./backup_db.sh
# Логи: /var/log/mysql-backup.log
# Бэкапы: /opt/backup/*.sql.gz
# Ротация: удаление бэкапов старше 7 дней

set -euo pipefail

# ------------------------ КОНФИГУРАЦИЯ ------------------------
BACKUP_DIR="./backup"
LOG_FILE="/var/log/mysql-backup.log"
DB_NAME="${DB_NAME:-virtd}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
SECRETS_FILE="/opt/.mysql_secrets"

# ------------------------ ФУНКЦИИ ------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" | tee -a "$LOG_FILE"
}

load_secrets() {
    if [[ -f "$SECRETS_FILE" && -r "$SECRETS_FILE" ]]; then
        if [[ "$(stat -c '%a' "$SECRETS_FILE" 2>/dev/null)" == "600" ]]; then
            # shellcheck disable=SC1090
            source "$SECRETS_FILE"
            log "INFO" "Секреты загружены из $SECRETS_FILE"
            return 0
        else
            log "ERROR" "Небезопасные права на $SECRETS_FILE (должно быть 600)"
            return 1
        fi
    elif [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
        log "WARN" "Использование пароля из переменной окружения (не рекомендуется для продакшена)"
        return 0
    else
        log "ERROR" "Не удалось получить пароль MySQL. Создайте файл $SECRETS_FILE с переменной MYSQL_ROOT_PASSWORD=..."
        return 1
    fi
}

get_network() {
    # Попытка использовать сеть контейнера db
    if docker ps --format '{{.Names}}' | grep -q "^db$"; then
        echo "container:db"
        return 0
    fi
    # Поиск сети backend, созданной Docker Compose
    local net
    net=$(docker network ls --format '{{.Name}}' | grep -E '^.*_backend$' | head -n1)
    if [[ -n "$net" ]]; then
        echo "$net"
        return 0
    fi
    log "ERROR" "Не найдена сеть 'backend' или контейнер 'db'"
    return 1
}

perform_backup() {
    mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
    local network mysql_host timestamp backup_file
    network=$(get_network) || return 1
    log "INFO" "Используется сеть: $network"

    # Определяем хост MySQL
    if [[ "$network" == "container:db" ]]; then
        mysql_host="127.0.0.1"
    else
        mysql_host="db"
    fi

    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="${BACKUP_DIR}/${DB_NAME}_${timestamp}.sql.gz"

    log "INFO" "Создание бэкапа $DB_NAME в $backup_file"

    if docker run --rm \
        --entrypoint "" \
        --network "$network" \
        -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" \
        schnitzler/mysqldump \
        mysqldump -h "$mysql_host" -u root \
        --databases "$DB_NAME" \
        --single-transaction --quick --lock-tables=false --skip-add-drop-table \
        2>>"$LOG_FILE" | gzip > "$backup_file"
    then
        if [[ -s "$backup_file" ]] && gzip -t "$backup_file" &>/dev/null; then
            local size
            size=$(du -h "$backup_file" | cut -f1)
            log "INFO" "Бэкап успешно создан: $backup_file ($size)"
            return 0
        else
            log "ERROR" "Файл бэкапа повреждён или пуст, удаляем"
            rm -f "$backup_file"
            return 1
        fi
    else
        log "ERROR" "Ошибка выполнения mysqldump"
        rm -f "$backup_file"
        return 1
    fi
}

rotate_backups() {
    log "INFO" "Ротация бэкапов старше $RETENTION_DAYS дней"
    local deleted
    deleted=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -mtime +"$RETENTION_DAYS" -delete -print | wc -l)
    [[ $deleted -gt 0 ]] && log "INFO" "Удалено старых бэкапов: $deleted"
    log "INFO" "Текущие бэкапы:"
    ls -lh "$BACKUP_DIR"/"${DB_NAME}_"*.sql.gz 2>/dev/null | tail -5 | tee -a "$LOG_FILE" || true
}

# ------------------------ ОСНОВНАЯ ЛОГИКА ------------------------
main() {
    log "INFO" "========== ЗАПУСК СКРИПТА БЭКАПА =========="
    load_secrets || exit 1
    perform_backup || exit 1
    rotate_backups
    log "INFO" "========== БЭКАП ЗАВЕРШЕН =========="
}

main "$@"
