FROM golang:1.22 AS builder

WORKDIR /app
COPY go.mod ./
COPY main.go ./

RUN go mod tidy
RUN go build -o app main.go

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=builder /app/app /app
CMD ["/app"]
