#!/bin/bash
# deploy.sh - скрипт развёртывания

set -e

echo "=== 🚀 Начало развертывания ==="

# -------------------------------
# Проверка Docker
# -------------------------------
if ! command -v docker &> /dev/null; then
    echo "📦 Установка Docker..."

    sudo apt update
    sudo apt install -y ca-certificates gnupg curl git lsb-release

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker
    sudo systemctl start docker

    sudo usermod -aG docker $USER

    echo "⚠️ ВАЖНО: Выполни 'newgrp docker' или перелогинься!"
fi

# -------------------------------
# Подготовка директории
# -------------------------------
mkdir -p /opt
cd /opt

# -------------------------------
# Клонирование / обновление
# -------------------------------
if [ ! -d "shvirtd-example-python" ]; then
    echo "📥 Клонирование репозитория..."
    git clone https://github.com/xo4ychill/shvirtd-example-python.git
else
    echo "🔄 Обновление репозитория..."
    cd shvirtd-example-python
    git fetch origin
    git reset --hard origin/main
    cd ..
fi

cd shvirtd-example-python

# -------------------------------
# Запуск контейнеров
# -------------------------------
echo "🐳 Перезапуск контейнеров..."
docker compose down --remove-orphans || true
docker compose up -d --build

# -------------------------------
# Проверка MySQL
# -------------------------------
echo "⏳ Ожидание MySQL..."

DB_CONTAINER=$(docker compose ps -q db)

if [ -z "$DB_CONTAINER" ]; then
    echo "❌ Контейнер db не найден"
    exit 1
fi

for i in {1..20}; do
    if docker exec "$DB_CONTAINER" \
        mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent; then
        echo "✅ MySQL готов"
        break
    fi
    echo "⏳ Ждём MySQL ($i/20)..."
    sleep 2
done

if ! docker exec "$DB_CONTAINER" \
    mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent; then
    echo "❌ MySQL не запустился"
    docker compose logs db
    exit 1
fi

# -------------------------------
# Проверка web
# -------------------------------
echo "⏳ Проверка web-сервиса..."

for i in {1..15}; do
    if curl -sf --max-time 3 http://127.0.0.1:8090 > /dev/null; then
        echo "✅ Сервис доступен!"
        echo "📡 Ответ:"
        curl -L http://127.0.0.1:8090
        echo ""
        echo "=== 🎉 Развертывание завершено успешно ==="
        exit 0
    fi
    echo "⏳ Ждём web ($i/15)..."
    sleep 3
done

# -------------------------------
# Ошибка
# -------------------------------
echo "❌ Сервис не запустился"
echo "📜 Логи web:"
docker compose logs web

echo "=== ❌ Развертывание завершено с ошибкой ==="
exit 1