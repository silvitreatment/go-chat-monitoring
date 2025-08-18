package main

import (
	"math/rand"
	"net/http"

	"github.com/gofiber/fiber/v2"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	app := fiber.New()

	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Hello from Go + Fiber!")
	})

	app.Get("/random", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"number": rand.Intn(100)})
	})

	go func() {
		http.Handle("/metrics", promhttp.Handler())
		http.ListenAndServe(":2112", nil)
	}()

	app.Listen(":5000")
}
