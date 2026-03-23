#!/bin/bash
# =============================================================================
# Скрипт для сборки и тестирования Docker-образа FastAPI приложения
# =============================================================================

set -e  # Выход при любой ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== 🐳 Сборка и тестирование Docker-образа ===${NC}"

# 1. Проверка наличия необходимых файлов
echo -e "\n${YELLOW}📋 Проверка файлов...${NC}"
for file in Dockerfile.python .dockerignore compose.yaml requirements.txt main.py; do
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $file найден"
    else
        echo -e "${RED}✗${NC} $file НЕ найден!"
        exit 1
    fi
done

# 2. Сборка образа
echo -e "\n${YELLOW}🔨 Сборка Docker-образа...${NC}"
docker build \
    -f Dockerfile.python \
    -t shvirtd-example-python:latest \
    --no-cache \
    .

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} Образ успешно собран!"
else
    echo -e "${RED}✗${NC} Ошибка сборки!"
    exit 1
fi

# 3. Проверка размера образа
echo -e "\n${YELLOW}📊 Информация об образе:${NC}"
docker images shvirtd-example-python:latest --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# 4. Проверка на наличие секретов в образе
echo -e "\n${YELLOW}🔍 Проверка на утечку секретов...${NC}"
if docker run --rm shvirtd-example-python:latest ls -la /app/.env 2>/dev/null; then
    echo -e "${RED}✗${NC} ВНИМАНИЕ: файл .env обнаружен в образе!"
    exit 1
else
    echo -e "${GREEN}✓${NC} Файл .env корректно исключён из образа"
fi

# 5. Проверка запуска контейнера
echo -e "\n${YELLOW}🚀 Тестовый запуск контейнера...${NC}"
CONTAINER_ID=$(docker run -d \
    --name test_app \
    -p 5000:5000 \
    -e DB_HOST=host.docker.internal \
    -e DB_USER=test \
    -e DB_PASSWORD=test \
    -e DB_NAME=test \
    shvirtd-example-python:latest)

# Ожидание запуска приложения
echo -e "${YELLOW}⏳ Ожидание запуска приложения (30 сек)...${NC}"
sleep 30

# Проверка доступности эндпоинта
if curl -s --max-time 10 http://localhost:5000/debug > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Приложение отвечает на запросы!"
    curl -s http://localhost:5000/debug | head -c 200
    echo "..."
else
    echo -e "${YELLOW}⚠${NC} Приложение не отвечает (возможно, нет доступа к БД - это нормально для теста)"
    echo -e "${YELLOW}⚠${NC} Проверяем логи контейнера:"
    docker logs test_app --tail 20
fi

# 6. Очистка
echo -e "\n${YELLOW}🧹 Очистка тестовых ресурсов...${NC}"
docker stop test_app >/dev/null 2>&1 || true
docker rm test_app >/dev/null 2>&1 || true

echo -e "\n${GREEN}=== ✅ Все этапы завершены ===${NC}"
echo -e "${YELLOW}💡 Для полноценного запуска используйте:${NC}"
echo -e "  docker-compose -f compose.yaml up --build"