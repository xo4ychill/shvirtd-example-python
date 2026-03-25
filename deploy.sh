#!/bin/bash
# deploy.sh - Скрипт развертывания проекта на ВМ

set -e

echo "=== Начало развертывания ==="

# Установка docker (если нет)
if ! command -v docker &> /dev/null; then
    echo "Установка Docker..."
    sudo apt update
    sudo apt install -y ca-certificates gnupg curl git
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    systemctl enable docker
    systemctl start docker
    usermod -aG docker $USER
fi

# Проверка переменных
: "${MYSQL_ROOT_PASSWORD:?Need to set MYSQL_ROOT_PASSWORD}"
: "${MYSQL_DATABASE:?Need to set MYSQL_DATABASE}"
: "${MYSQL_USER:?Need to set MYSQL_USER}"
: "${MYSQL_PASSWORD:?Need to set MYSQL_PASSWORD}"

# Переход в директорию
mkdir -p /opt
cd /opt

# Клонирование
if [ ! -d "shvirtd-example-python" ]; then
    echo "Клонирование репозитория..."
    git clone https://github.com/xo4ychill/shvirtd-example-python.git
else
    echo "Обновление репозитория..."
    cd shvirtd-example-python
    git pull origin main
    cd ..
fi

cd shvirtd-example-python

# Создание .env
if [ ! -f ".env" ]; then
    echo "Создание .env..."
    cat > .env << EOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
EOF
    chmod 600 .env
fi

# Перезапуск
echo "Перезапуск контейнеров..."
docker compose down --remove-orphans || true
docker compose up -d --build

# Ожидание запуска сервисов
echo "Ожидание запуска сервисов..."
sleep 30

# Проверка доступности
echo "Проверка доступности сервиса..."
if curl -sf http://127.0.0.1:8090 > /dev/null; then
    echo "✅ Сервис успешно запущен!"
    curl -L http://127.0.0.1:8090
else
    echo "❌ Ошибка запуска сервиса"
    docker compose logs web
    exit 1
fi

echo "=== Развертывание завершено ==="