#!/bin/bash
# deploy.sh - Скрипт развертывания проекта на ВМ

set -e  # Выход при ошибке

echo "=== Начало развертывания ==="

# Переход в целевую директорию
cd /opt || mkdir -p /opt && cd /opt

# Клонирование форк-репозитория (используем переменные для токена)
if [ ! -d "shvirtd-example-python" ]; then
    echo "Клонирование репозитория..."
    # Вариант 1: публичный доступ
    git clone https://github.com/xo4ychill/shvirtd-example-python.git
    # Вариант 2: с токеном (токен передаётся через переменную окружения)
    # git clone https://${GH_TOKEN}@github.com/<your-username>/shvirtd-example-python.git
else
    echo "Обновление репозитория..."
    cd shvirtd-example-python
    git pull origin main
fi

cd /opt/shvirtd-example-python

# Создание .env файла если отсутствует (секреты из переменных окружения)
if [ ! -f ".env" ]; then
    echo "Создание .env файла..."
    cat > .env << EOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
EOF
    chmod 600 .env
fi

# Остановка старых контейнеров
echo "Остановка старых контейнеров..."
docker compose down --remove-orphans 2>/dev/null || true

# Сборка и запуск
echo "Запуск проекта..."
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