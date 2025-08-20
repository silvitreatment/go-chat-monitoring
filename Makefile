.PHONY: help build up down logs clean test dev-setup

COMPOSE_FILE := docker-compose.yml
PROJECT_NAME := messaging-app
APP_DIR := app

help:
	@echo "Доступные команды:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: 
	docker-compose -f $(COMPOSE_FILE) build

up: 
	docker-compose -f $(COMPOSE_FILE) up -d
	@echo "Сервисы запущены:"
	@echo "🌐 Приложение: http://localhost:5000"
	@echo "🔄 Nginx (прокси): http://localhost:8080"
	@echo "📊 Grafana: http://localhost:3000 (admin/admin123)"
	@echo "🔍 Prometheus: http://localhost:9090"
	@echo "🗄️ PostgreSQL: localhost:5432"

up-build:
	docker-compose -f $(COMPOSE_FILE) up -d --build

down: 
	docker-compose -f $(COMPOSE_FILE) down

down-volumes: 
	docker-compose -f $(COMPOSE_FILE) down -v

logs: 
	docker-compose -f $(COMPOSE_FILE) logs -f

logs-app: 
	docker-compose -f $(COMPOSE_FILE) logs -f app

logs-db: 
	docker-compose -f $(COMPOSE_FILE) logs -f postgres

logs-nginx: 
	docker-compose -f $(COMPOSE_FILE) logs -f nginx

dev: 
	docker-compose -f $(COMPOSE_FILE) up -d postgres redis
	@echo "База данных и Redis запущены для разработки"
	@echo "🗄️ PostgreSQL: localhost:5432"
	@echo "🔴 Redis: localhost:6379"

dev-app: 
	cd $(APP_DIR) && go run main.go

dev-setup: 
	@echo "Настройка окружения для разработки..."
	cd $(APP_DIR) && go mod tidy
	@echo "Зависимости установлены"

test:
	cd $(APP_DIR) && go test -v ./...

test-coverage: 
	cd $(APP_DIR) && go test -v -cover ./...

db-migrate: 
	docker-compose -f $(COMPOSE_FILE) exec postgres psql -U user -d mydb -f /docker-entrypoint-initdb.d/init.sql

db-shell: 
	docker-compose -f $(COMPOSE_FILE) exec postgres psql -U user -d mydb

db-backup:
	docker-compose -f $(COMPOSE_FILE) exec postgres pg_dump -U user mydb > backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "Бэкап создан: backup_$(shell date +%Y%m%d_%H%M%S).sql"

db-restore: 
	docker-compose -f $(COMPOSE_FILE) exec -T postgres psql -U user -d mydb < $(BACKUP)

stats: 
	docker stats $(shell docker-compose -f $(COMPOSE_FILE) ps -q)

health: 
	@echo "Проверка здоровья сервисов..."
	@curl -s http://localhost:5000/health | jq . || echo "❌ Приложение недоступно"
	@curl -s http://localhost:8080/health | jq . || echo "❌ Nginx недоступен"

clean: 
	docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans
	docker system prune -f

clean-all: 
	docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans --rmi all
	docker system prune -a -f

prod-deploy: 
	@echo "🚀 Разворачивание в продакшене..."
	docker-compose -f $(COMPOSE_FILE) pull
	docker-compose -f $(COMPOSE_FILE) up -d --remove-orphans
	@echo "✅ Развертывание завершено"

prod-update: 
	@echo "🔄 Обновление приложения..."
	docker-compose -f $(COMPOSE_FILE) build app
	docker-compose -f $(COMPOSE_FILE) up -d app
	@echo "✅ Приложение обновлено"

api-test: 
	@echo "🧪 Тестирование API..."
	@echo "Создание пользователя:"
	curl -X POST http://localhost:5000/api/v1/users \
		-H "Content-Type: application/json" \
		-d '{"username":"testuser","email":"test@example.com"}' | jq .
	@echo "\nПолучение списка пользователей:"
	curl -s http://localhost:5000/api/v1/users | jq .
	@echo "\nПолучение сообщений:"
	curl -s http://localhost:5000/api/v1/messages | jq .


install-tools: 
	@echo "📦 Установка инструментов..."
	@which jq > /dev/null || (echo "Установка jq..." && sudo apt-get update && sudo apt-get install -y jq)
	@which curl > /dev/null || (echo "Установка curl..." && sudo apt-get update && sudo apt-get install -y curl)
	@echo "✅ Инструменты установлены"

status:
	@echo "📊 Статус сервисов:"
	docker-compose -f $(COMPOSE_FILE) ps

ports: 
	@echo "🔌 Используемые порты:"
	@echo "5000  - Основное приложение"
	@echo "8080  - Nginx (прокси)"
	@echo "3000  - Grafana"
	@echo "9090  - Prometheus"
	@echo "5432  - PostgreSQL"
	@echo "6379  - Redis"
	@echo "2112  - Метрики приложения"

info: 
	@echo "📋 Информация о проекте:"
	@echo "Название: $(PROJECT_NAME)"
	@echo "Версия Docker Compose: $(shell docker-compose version --short)"
	@echo "Статус сервисов:"
	@docker-compose -f $(COMPOSE_FILE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"