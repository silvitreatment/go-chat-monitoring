package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/websocket/v2"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Message struct {
	ID        int       `json:"id" db:"id"`
	UserID    int       `json:"user_id" db:"user_id"`
	Username  string    `json:"username" db:"username"`
	Content   string    `json:"content" db:"content"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type User struct {
	ID       int    `json:"id" db:"id"`
	Username string `json:"username" db:"username"`
	Email    string `json:"email" db:"email"`
}

type CreateMessageRequest struct {
	UserID   int    `json:"user_id" validate:"required"`
	Username string `json:"username" validate:"required"`
	Content  string `json:"content" validate:"required,min=1,max=1000"`
}

type CreateUserRequest struct {
	Username string `json:"username" validate:"required,min=3,max=50"`
	Email    string `json:"email" validate:"required,email"`
}

var (
	db        *sql.DB
	clients   = make(map[*websocket.Conn]bool)
	broadcast = make(chan Message)

	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	messagesTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "messages_total",
			Help: "Total number of messages sent",
		},
	)

	activeConnections = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "websocket_connections_active",
			Help: "Number of active WebSocket connections",
		},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(messagesTotal)
	prometheus.MustRegister(activeConnections)
}

func connectDB() {
	var err error
	dbHost := getEnv("DB_HOST", "postgres")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "user")
	dbPassword := getEnv("DB_PASSWORD", "password")
	dbName := getEnv("DB_NAME", "mydb")

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPassword, dbName)

	db, err = sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	for i := 0; i < 30; i++ {
		if err = db.Ping(); err == nil {
			break
		}
		log.Printf("Waiting for database connection... (%d/30)", i+1)
		time.Sleep(2 * time.Second)
	}

	if err != nil {
		log.Fatal("Database connection failed:", err)
	}

	log.Println("Connected to database successfully")
	initDatabase()
}

func initDatabase() {
	createTables := `
	CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		username VARCHAR(50) UNIQUE NOT NULL,
		email VARCHAR(100) UNIQUE NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS messages (
		id SERIAL PRIMARY KEY,
		user_id INTEGER REFERENCES users(id),
		username VARCHAR(50) NOT NULL,
		content TEXT NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
	CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);
	`

	if _, err := db.Exec(createTables); err != nil {
		log.Fatal("Failed to create tables:", err)
	}

	log.Println("Database tables initialized")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func metricsMiddleware(c *fiber.Ctx) error {
	start := time.Now()

	err := c.Next()

	duration := time.Since(start)
	status := strconv.Itoa(c.Response().StatusCode())

	httpRequestsTotal.WithLabelValues(c.Method(), c.Path(), status).Inc()

	log.Printf("%s %s - %s (%v)", c.Method(), c.Path(), status, duration)

	return err
}

func handleWebSocket(c *websocket.Conn) {
	clients[c] = true
	activeConnections.Inc()

	defer func() {
		delete(clients, c)
		activeConnections.Dec()
		c.Close()
	}()

	for {
		var msg Message
		if err := c.ReadJSON(&msg); err != nil {
			log.Println("WebSocket read error:", err)
			break
		}

		msg.CreatedAt = time.Now()
		if err := saveMessage(&msg); err != nil {
			log.Println("Error saving message:", err)
			continue
		}

		messagesTotal.Inc()
		broadcast <- msg
	}
}

func handleBroadcast() {
	for {
		msg := <-broadcast

		for client := range clients {
			if err := client.WriteJSON(msg); err != nil {
				log.Println("WebSocket write error:", err)
				client.Close()
				delete(clients, client)
				activeConnections.Dec()
			}
		}
	}
}

func saveMessage(msg *Message) error {
	query := `
		INSERT INTO messages (user_id, username, content, created_at)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`
	return db.QueryRow(query, msg.UserID, msg.Username, msg.Content, msg.CreatedAt).Scan(&msg.ID)
}

func getMessages(c *fiber.Ctx) error {
	limit := c.QueryInt("limit", 50)
	offset := c.QueryInt("offset", 0)

	query := `
		SELECT id, user_id, username, content, created_at
		FROM messages
		ORDER BY created_at DESC
		LIMIT $1 OFFSET $2
	`

	rows, err := db.Query(query, limit, offset)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Database query failed"})
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		var msg Message
		if err := rows.Scan(&msg.ID, &msg.UserID, &msg.Username, &msg.Content, &msg.CreatedAt); err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Failed to scan message"})
		}
		messages = append(messages, msg)
	}

	return c.JSON(messages)
}

func createMessage(c *fiber.Ctx) error {
	var req CreateMessageRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid request body"})
	}

	msg := Message{
		UserID:    req.UserID,
		Username:  req.Username,
		Content:   req.Content,
		CreatedAt: time.Now(),
	}

	if err := saveMessage(&msg); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to save message"})
	}

	messagesTotal.Inc()

	select {
	case broadcast <- msg:
	default:
	}

	return c.Status(201).JSON(msg)
}

func getUsers(c *fiber.Ctx) error {
	query := `SELECT id, username, email FROM users ORDER BY username`

	rows, err := db.Query(query)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Database query failed"})
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var user User
		if err := rows.Scan(&user.ID, &user.Username, &user.Email); err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Failed to scan user"})
		}
		users = append(users, user)
	}

	return c.JSON(users)
}

func createUser(c *fiber.Ctx) error {
	var req CreateUserRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid request body"})
	}

	query := `
		INSERT INTO users (username, email)
		VALUES ($1, $2)
		RETURNING id
	`

	var user User
	user.Username = req.Username
	user.Email = req.Email

	if err := db.QueryRow(query, user.Username, user.Email).Scan(&user.ID); err != nil {
		return c.Status(409).JSON(fiber.Map{"error": "User already exists"})
	}

	return c.Status(201).JSON(user)
}

func healthCheck(c *fiber.Ctx) error {
	if err := db.Ping(); err != nil {
		return c.Status(503).JSON(fiber.Map{
			"status": "unhealthy",
			"error":  "Database connection failed",
		})
	}

	return c.JSON(fiber.Map{
		"status":      "healthy",
		"timestamp":   time.Now(),
		"connections": len(clients),
	})
}

func getStats(c *fiber.Ctx) error {
	var messageCount, userCount int

	db.QueryRow("SELECT COUNT(*) FROM messages").Scan(&messageCount)
	db.QueryRow("SELECT COUNT(*) FROM users").Scan(&userCount)

	return c.JSON(fiber.Map{
		"messages":           messageCount,
		"users":              userCount,
		"active_connections": len(clients),
		"uptime":             time.Since(time.Now()).String(),
	})
}

func main() {
	connectDB()
	defer db.Close()

	go handleBroadcast()

	app := fiber.New(fiber.Config{
		ErrorHandler: func(ctx *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			return ctx.Status(code).JSON(fiber.Map{
				"error": err.Error(),
			})
		},
	})
	app.Use(cors.New())
	app.Use(logger.New())
	app.Use(metricsMiddleware)

	app.Get("/health", healthCheck)
	app.Get("/stats", getStats)

	api := app.Group("/api/v1")

	api.Get("/messages", getMessages)
	api.Post("/messages", createMessage)

	api.Get("/users", getUsers)
	api.Post("/users", createUser)

	app.Use("/ws", func(c *fiber.Ctx) error {
		if websocket.IsWebSocketUpgrade(c) {
			c.Locals("allowed", true)
			return c.Next()
		}
		return fiber.ErrUpgradeRequired
	})
	app.Get("/ws", websocket.New(handleWebSocket))

	app.Static("/", "./public")

	go func() {
		http.Handle("/metrics", promhttp.Handler())
		log.Println("Prometheus metrics server starting on :2112")
		if err := http.ListenAndServe(":2112", nil); err != nil {
			log.Printf("Prometheus server error: %v", err)
		}
	}()

	port := getEnv("PORT", "5000")
	log.Printf("Server starting on port %s", port)
	log.Fatal(app.Listen(":" + port))
}
