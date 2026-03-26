#!/bin/bash

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

    echo "⚠️ Выполни 'newgrp docker' или перелогинься и запусти скрипт снова"
    exit 1
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
# Проверка .env
# -------------------------------
if [ ! -f ".env" ]; then
    echo "❌ Файл .env не найден!"
    exit 1
fi

echo "🔐 Загрузка переменных..."
set -a
source .env
set +a

# -------------------------------
# Права на backup.sh
# -------------------------------
echo "🔧 Установка прав на backup.sh..."

if [ -f "backup.sh" ]; then
    chmod +x backup.sh
    echo "✅ backup.sh готов к выполнению"
else
    echo "⚠️ backup.sh не найден"
fi

# -------------------------------
# Настройка systemd timer
# -------------------------------
echo "⏰ Настройка systemd timer..."

SERVICE_FILE="/etc/systemd/system/backup.service"
TIMER_FILE="/etc/systemd/system/backup.timer"

# Service
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=MySQL Backup Script
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/shvirtd-example-python/backup.sh

Restart=on-failure
RestartSec=10s
StartLimitIntervalSec=60
StartLimitBurst=3
EOF

# Timer
sudo tee "$TIMER_FILE" > /dev/null <<EOF
[Unit]
Description=Run MySQL Backup every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s
Persistent=true
Unit=backup.service

[Install]
WantedBy=timers.target
EOF

# Применение systemd
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer

echo "✅ systemd timer настроен"

echo "📋 Активные таймеры:"
systemctl list-timers --all | grep backup || true

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

for i in {1..30}; do
    if docker exec "$DB_CONTAINER" mysqladmin ping --silent > /dev/null 2>&1; then
        echo "✅ MySQL запущен"
        break
    fi
    echo "⏳ Ждём MySQL ($i/30)..."
    sleep 2
done

if ! docker exec "$DB_CONTAINER" mysqladmin ping --silent > /dev/null 2>&1; then
    echo "❌ MySQL не запустился"
    docker compose logs db
    exit 1
fi

# -------------------------------
# Проверка web
# -------------------------------
echo "⏳ Проверка web-сервиса..."

WEB_OK=false

for i in {1..20}; do
    if curl -sf --max-time 3 http://127.0.0.1:8090 > /dev/null; then
        WEB_OK=true
        echo "✅ Сервис доступен!"
        echo "📡 Ответ:"
        curl -L http://127.0.0.1:8090
        echo ""
        break
    fi
    echo "⏳ Ждём web ($i/20)..."
    sleep 3
done

# -------------------------------
# Финальная проверка
# -------------------------------
if [ "$WEB_OK" = false ]; then
    echo "❌ Сервис не запустился"
    echo "📜 Логи web:"
    docker compose logs web

    echo "=== ❌ Развертывание завершено с ошибкой ==="
    exit 1
fi

echo "=== 🎉 Развертывание завершено успешно ==="
exit 0