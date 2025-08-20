# 💬 Messaging - Веб-сервис для обмена сообщениями

Полнофункциональный веб-сервис для обмена сообщениями, построенный на Go + Fiber с поддержкой WebSocket, мониторингом и балансировкой нагрузки.

## 🚀 Возможности

- **Реальное время**: WebSocket соединения для мгновенной доставки сообщений
- **REST API**: Полноценный API для управления пользователями и сообщениями
- **База данных**: PostgreSQL с оптимизированными индексами
- **Мониторинг**: Prometheus + Grafana для отслеживания метрик
- **Балансировка**: Nginx в качестве reverse proxy
- **Кэширование**: Redis для повышения производительности
- **Health Checks**: Проверки состояния всех сервисов

## 🏗️ Архитектура

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Client    │───▶│    Nginx    │───▶│  Go App     │
│ (Browser)   │    │ (Port 8080) │    │ (Port 5000) │
└─────────────┘    └─────────────┘    └─────────────┘
                          │                    │
                          ▼                    ▼
                   ┌─────────────┐    ┌─────────────┐
                   │ Static Files│    │ PostgreSQL  │
                   │             │    │ (Port 5432) │
                   └─────────────┘    └─────────────┘
                                             │
        ┌─────────────┐    ┌─────────────┐   │   ┌─────────────┐
        │ Prometheus  │───▶│  Grafana    │   │   │    Redis    │
        │ (Port 9090) │    │ (Port 3000) │   │   │ (Port 6379) │
        └─────────────┘    └─────────────┘   ▼   └─────────────┘
                                    ┌─────────────┐
                                    │   Metrics   │
                                    │ (Port 2112) │
                                    └─────────────┘
```

## 📁 Структура проекта

```
messaging-app/
├── app/                              # Основное приложение Go
│   ├── Dockerfile                    # Docker образ для Go приложения
│   ├── go.mod                        # Зависимости Go модуля
│   ├── main.go                       # Основной код приложения
│   └── public/                       # Статические файлы
│       └── index.html                # Веб-клиент для чата
│
├── prometheus/                       # Конфигурация мониторинга
│   └── prometheus.yml                # Настройки Prometheus
│
├── grafana/                          # Настройки Grafana
│   ├── provisioning/                 # Автоматическая настройка
│   └── dashboards/                   # Дашборды мониторинга
│
├── docker-compose.yml                # Оркестрация всех сервисов
├── nginx.conf                        # Конфигурация Nginx
├── init.sql                          # SQL скрипты для инициализации БД
├── Makefile                          # Команды для управления проектом
└── README.md                         # Документация проекта
```

## 🛠️ Установка и запуск

### Предварительные требования

- Docker 20.10+
- Docker Compose 2.0+
- Make 
- Go 1.22+ 

### Быстрый старт

```bash
# Клонирование репозитория
git clone <repository-url>
cd messaging-app

# Запуск всех сервисов
make up-build

# Или без Makefile
docker-compose up -d --build
```

### Доступные сервисы

После запуска будут доступны:

| Сервис | URL | Описание |
|--------|-----|----------|
| **Основное приложение** | http://localhost:5000 | Веб-интерфейс чата |
| **Nginx (прокси)** | http://localhost:8080 | Прокси с балансировкой |
| **Grafana** | http://localhost:3000 | Мониторинг (admin/admin123) |
| **Prometheus** | http://localhost:9090 | Метрики |
| **PostgreSQL** | localhost:5432 | База данных |
| **Redis** | localhost:6379 | Кэш |

## 🔧 Команды Makefile

```bash
# Основные команды
make help              # Показать все доступные команды
make build             # Собрать все образы
make up                # Запустить все сервисы
make up-build          # Собрать и запустить
make down              # Остановить все сервисы
make logs              # Показать логи всех сервисов

# Разработка
make dev               # Запустить только БД и Redis
make dev-app           # Запустить приложение локально
make dev-setup         # Настроить окружение для разработки

# Тестирование
make test              # Запустить тесты
make api-test          # Тестировать API endpoints
make health            # Проверить здоровье сервисов

# База данных
make db-shell          # Подключиться к PostgreSQL
make db-backup         # Создать бэкап БД
make db-migrate        # Применить миграции

# Мониторинг
make stats             # Показать статистику контейнеров
make status            # Показать статус всех сервисов

# Очистка
make clean             # Остановить и удалить контейнеры
make clean-all         # Полная очистка включая образы
```

## 🌐 API Документация

### Пользователи

#### Получить всех пользователей
```http
GET /api/v1/users
```

Ответ:
```json
[
  {
    "id": 1,
    "username": "admin",
    "email": "admin@example.com"
  }
]
```

#### Создать пользователя
```http
POST /api/v1/users
Content-Type: application/json

{
  "username": "newuser",
  "email": "user@example.com"
}
```

### Сообщения

#### Получить сообщения
```http
GET /api/v1/messages?limit=20&offset=0
```

Ответ:
```json
[
  {
    "id": 1,
    "user_id": 1,
    "username": "admin",
    "content": "Привет, мир!",
    "created_at": "2024-01-01T12:00:00Z"
  }
]
```

#### Отправить сообщение
```http
POST /api/v1/messages
Content-Type: application/json

{
  "user_id": 1,
  "username": "admin",
  "content": "Новое сообщение"
}
```

### WebSocket

Подключение к WebSocket:
```
const ws = new WebSocket('ws://localhost:5000/ws');

// Отправка сообщения
ws.send(JSON.stringify({
  user_id: 1,
  username: "user",
  content: "Hello World!"
}));

// Получение сообщений
ws.onmessage = function(event) {
  const message = JSON.parse(event.data);
  console.log('Новое сообщение:', message);
};
```

### Служебные endpoint'ы

#### Health Check
```http
GET /health
```

#### Статистика
```http
GET /stats
```

## 🗄️ База данных

### Схема БД

Основные таблицы:

- **users** - Пользователи системы
- **messages** - Сообщения в чате
- **rooms** - Комнаты/каналы
- **room_members** - Участники комнат
- **attachments** - Прикрепленные файлы
- **message_reactions** - Реакции на сообщения

### Индексы и оптимизации

- Полнотекстовый поиск по содержимому сообщений
- Индексы по времени создания для быстрой пагинации
- Составные индексы для оптимизации запросов

## 📊 Мониторинг и метрики

### Prometheus метрики

- `http_requests_total` - Общее количество HTTP запросов
- `messages_total` - Общее количество отправленных сообщений
- `websocket_connections_active` - Активные WebSocket подключения

### Grafana дашборды

1. **Application Overview** - Общий обзор приложения
2. **Database Performance** - Производительность БД
3. **WebSocket Connections** - Мониторинг WebSocket соединений
4. **System Resources** - Системные ресурсы

## 🔒 Безопасность

### Реализованные меры

- Rate limiting на уровне Nginx
- Валидация входных данных
- SQL injection защита через prepared statements
- CORS настройки
- Security headers в Nginx


## 🚀 Развертывание в продакшене

### Docker Swarm

```bash
# Инициализация swarm
docker swarm init

# Развертывание stack
docker stack deploy -c docker-compose.yml messaging-app
```

### Kubernetes

```bash
# Создать namespace
kubectl create namespace messaging-app

# Применить манифесты
kubectl apply -f k8s/
```

### Переменные окружения

```bash
# Основные настройки
DB_HOST=postgres
DB_PORT=5432
DB_USER=user
DB_PASSWORD=password
DB_NAME=mydb
PORT=5000

# Redis (опционально)
REDIS_HOST=redis
REDIS_PORT=6379

# Настройки приложения
LOG_LEVEL=info
MAX_CONNECTIONS=1000
```

## 🧪 Тестирование

### Unit тесты

```bash
cd app/
go test -v ./...
```

### Интеграционные тесты

```bash
# Запустить тестовую среду
make up

# Выполнить API тесты
make api-test

# Нагрузочное тестирование
curl -X POST http://localhost:5000/api/v1/messages \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"username":"load_test","content":"Load test message"}'
```

### Мониторинг производительности

```bash
# Статистика контейнеров
make stats

# Проверка здоровья
make health

# Логи производительности
make logs-app | grep "duration"
```

## 📋 Troubleshooting

### Частые проблемы

#### Проблема с подключением к БД
```bash
# Проверить статус PostgreSQL
docker-compose logs postgres

# Перезапустить сервисы
make down && make up
```

#### WebSocket не подключается
```bash
# Проверить логи приложения
make logs-app

# Проверить nginx конфигурацию
docker-compose exec nginx nginx -t
```


### Настройка окружения 

```bash
# Клонировать репозиторий
git clone <repository-url>
cd messaging-app

# Настроить окружение
make dev-setup

# Запустить только БД для разработки
make dev

# Запустить приложение локально
make dev-app
```

