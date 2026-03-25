#!/bin/bash
# deploy.sh - Скрипт развёртывания проекта на ВМ

set -e

# Параметры по умолчанию 
REPO_URL="${REPO_URL:-https://github.com/xo4ychill/shvirtd-example-python.git}"
BRANCH="${BRANCH:-main}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-60}"  # секунд
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"    # секунд между проверками
REBUILD="${REBUILD:-false}"             # пересборка образов (true/false)
SERVICE_URL="${SERVICE_URL:-http://127.0.0.1:8090}"
ENV_FILE_PATH="${ENV_FILE_PATH:-.env}"

echo "=== Начало развёртывания ==="
echo "Параметры развёртывания:"
echo "  Репозиторий: $REPO_URL"
echo "  Ветвь: $BRANCH"
echo "  Директория: $DEPLOY_DIR"
echo "  Таймаут проверки: $CHECK_TIMEOUT сек"
echo "  Интервал проверки: $CHECK_INTERVAL сек"
echo "  Пересборка: $REBUILD"

# Проверка ОС (только Ubuntu/Debian)
if [[ "$(lsb_release -is 2>/dev/null)" != "Ubuntu" ]] && [[ "$(lsb_release -is 2>/dev/null)" != "Debian" ]]; then
    echo "❌ Ошибка: поддерживается только Ubuntu/Debian"
    exit 1
fi


# Проверка прав sudo
if ! sudo -n true 2>/dev/null && ! sudo -v; then
    echo "❌ Ошибка: требуются права sudo для выполнения операций"
    exit 1
fi

# Установка Docker (если нет)
if ! command -v docker &> /dev/null; then
    echo "Установка Docker..."
    
    sudo apt update
    sudo apt install -y ca-certificates gnupg curl git
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
    newgrp docker
    echo "✅ Docker установлен. Перезалогиньтесь для применения прав группы docker."
fi

# Проверка переменных
#: "${MYSQL_ROOT_PASSWORD:?Ошибка: необходимо установить MYSQL_ROOT_PASSWORD. Пример: export MYSQL_ROOT_PASSWORD='ваш_пароль'}"
#: "${MYSQL_DATABASE:?Ошибка: необходимо установить MYSQL_DATABASE. Пример: export MYSQL_DATABASE='имя_базы'}"
#: "${MYSQL_USER:?Ошибка: необходимо установить MYSQL_USER. Пример: export MYSQL_USER='пользователь'}"
#: "${MYSQL_PASSWORD:?Ошибка: необходимо установить MYSQL_PASSWORD. Пример: export MYSQL_PASSWORD='пароль_пользователя'}"

# Переход в директорию
mkdir -p "$DEPLOY_DIR" || { echo "❌ Ошибка: не удалось создать директорию $DEPLOY_DIR"; exit 1; }
cd "$DEPLOY_DIR"

# Клонирование/обновление репозитория
REPO_DIR="shvirtd-example-python"
if [ ! -d "$REPO_DIR" ]; then
    echo "Клонирование репозитория..."
    git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR" || { echo "❌ Ошибка клонирования репозитория"; exit 1; }
else
    echo "Обновление репозитория..."
    cd "$REPO_DIR"
    git fetch origin || { echo "❌ Ошибка получения обновлений из репозитория"; cd ..; exit 1; }
    git reset --hard "origin/$BRANCH" || { echo "❌ Ошибка обновления репозитория"; cd ..; exit 1; }
    cd ..
fi

cd "$REPO_DIR"

# Создание/обновление .env
echo "Создание/обновление $ENV_FILE_PATH..."
cat > "$ENV_FILE_PATH" << EOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
EOF
chmod 600 "$ENV_FILE_PATH"

# Очистка неиспользуемых образов (опционально)
echo "Очистка неиспользуемых Docker-образов..."
docker image prune -f 2>/dev/null || true

# Перезапуск контейнеров
echo "Перезапуск контейнеров..."
docker compose down --remove-orphans || true
if [[ "$REBUILD" == "true" ]]; then
    docker compose up -d --build || { echo "❌ Ошибка запуска контейнеров"; exit 1; }
else
    docker compose up -d || { echo "❌ Ошибка запуска контейнеров"; exit 1; }
fi

# Ожидание запуска сервисов
echo "Ожидание запуска сервисов... (до $CHECK_TIMEOUT секунд)"
start_time=$(date +%s)
attempt=1
max_attempts=$((CHECK_TIMEOUT / CHECK_INTERVAL))

while [ $(( $(date +%s) - start_time )) -lt $CHECK_TIMEOUT ]; do
    echo "Попытка $attempt/$max_attempts..."
    if curl -sf "$SERVICE_URL" > /dev/null; then
        echo "✅ Сервис работает"
        curl -L "$SERVICE_URL"
        echo "=== Развёртывание завершено успешно ==="
        exit 0
    fi
    sleep "$CHECK_INTERVAL"
    ((attempt++))
done

echo "❌ Сервис не запустился в течение $CHECK_TIMEOUT секунд"
echo "Логи контейнера web:"
docker compose logs web
echo "=== Развёртывание завершено с ошибкой ==="
exit 1
