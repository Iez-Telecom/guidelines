# Serviços HTTP e gRPC em Go

## Hierarquia de comunicação

1. **gRPC + Protobuf** — padrão para comunicação entre serviços (ver `references/grpc.md` para detalhes de protobuf/buf)
2. **net/http (stdlib)** — apenas para APIs públicas externas ou endpoints simples (health, metrics)

Não usar Gin, Echo, Fiber, chi, ou qualquer framework/router HTTP de terceiros. O `net/http` da stdlib em Go 1.22+ tem pattern matching com método e path variables (`GET /users/{id}`), que cobre o que precisamos. Biblioteca padrão > dependência extra.

## Servidor HTTP mínimo (para endpoints auxiliares)

```go
// internal/server/http.go
package server

import (
    "context"
    "errors"
    "fmt"
    "log/slog"
    "net/http"
    "time"
)

// NewHTTPServer cria um servidor HTTP configurado para produção.
// Usado para health checks, métricas, e APIs REST públicas.
func NewHTTPServer(addr string, mux http.Handler, logger *slog.Logger) *http.Server {
    return &http.Server{
        Addr:              addr,
        Handler:           mux,
        ReadHeaderTimeout: 5 * time.Second,
        ReadTimeout:       30 * time.Second,
        WriteTimeout:      30 * time.Second,
        IdleTimeout:       120 * time.Second,
    }
}

// RunHTTPServer inicia o servidor e gerencia shutdown graceful.
func RunHTTPServer(ctx context.Context, srv *http.Server, logger *slog.Logger) error {
    serverErr := make(chan error, 1)
    go func() {
        logger.Info("servidor HTTP escutando", "addr", srv.Addr)
        if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
            serverErr <- err
        }
        close(serverErr)
    }()

    select {
    case err := <-serverErr:
        return fmt.Errorf("servidor HTTP: %w", err)
    case <-ctx.Done():
        logger.Info("desligando servidor HTTP")
    }

    shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    return srv.Shutdown(shutdownCtx)
}
```

**Sempre**:
- Definir timeouts no `http.Server`. Os padrões são "sem timeout" — um cliente lento faz DoS.
- Usar `signal.NotifyContext` no `main()` e propagar via `ctx`.
- Fazer graceful shutdown com deadline.

## Handlers

Preferir o padrão **handler-com-dependências** ao invés de estado de pacote:

```go
// internal/handler/user.go
package handler

import (
    "encoding/json"
    "errors"
    "log/slog"
    "net/http"
)

// UserHandler lida com requests HTTP relacionados a usuários.
type UserHandler struct {
    store  UserStore
    logger *slog.Logger
}

// NewUserHandler cria um handler com as dependências injetadas.
func NewUserHandler(store UserStore, logger *slog.Logger) *UserHandler {
    return &UserHandler{store: store, logger: logger}
}

// Get busca um usuário por ID.
func (h *UserHandler) Get(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id") // Go 1.22+ pattern matching

    u, err := h.store.GetUser(r.Context(), id)
    if errors.Is(err, ErrNotFound) {
        writeError(w, http.StatusNotFound, "usuário não encontrado")
        return
    }
    if err != nil {
        h.logger.Error("falha ao buscar usuário", "err", err, "id", id)
        writeError(w, http.StatusInternalServerError, "erro interno")
        return
    }

    writeJSON(w, http.StatusOK, u)
}

// Registro de rotas:
// mux.HandleFunc("GET /users/{id}", h.Get)
```

## Helpers de JSON

Não repetir o padrão de encoding:

```go
func writeJSON(w http.ResponseWriter, status int, v any) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    if err := json.NewEncoder(w).Encode(v); err != nil {
        slog.Error("falha ao codificar resposta", "err", err)
    }
}

func writeError(w http.ResponseWriter, status int, msg string) {
    writeJSON(w, status, map[string]string{"error": msg})
}
```

## Decodificação de request com limites

```go
// decodeJSON decodifica o corpo JSON com limites de segurança.
func decodeJSON(r *http.Request, dst any) error {
    r.Body = http.MaxBytesReader(nil, r.Body, 1<<20) // 1 MiB
    dec := json.NewDecoder(r.Body)
    dec.DisallowUnknownFields()
    if err := dec.Decode(dst); err != nil {
        return fmt.Errorf("decodificar body: %w", err)
    }
    if dec.More() {
        return errors.New("body deve conter um único objeto JSON")
    }
    return nil
}
```

## Middleware

Middleware é `func(http.Handler) http.Handler`:

```go
// loggingMiddleware registra cada request com log estruturado.
func loggingMiddleware(logger *slog.Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            ww := &statusRecorder{ResponseWriter: w, status: 200}
            next.ServeHTTP(ww, r)
            logger.Info("request",
                "method", r.Method,
                "path", r.URL.Path,
                "status", ww.status,
                "duration_ms", time.Since(start).Milliseconds(),
            )
        })
    }
}

type statusRecorder struct {
    http.ResponseWriter
    status int
}

func (s *statusRecorder) WriteHeader(code int) {
    s.status = code
    s.ResponseWriter.WriteHeader(code)
}
```

Recovery middleware (ver `errors.md`) deve ser o wrapper mais externo.

## HTTP client — sempre fechar Body e usar timeout

```go
resp, err := httpClient.Do(req)
if err != nil {
    return fmt.Errorf("fazer request: %w", err)
}
defer resp.Body.Close() // SEMPRE, mesmo em non-2xx

if resp.StatusCode >= 400 {
    body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
    return fmt.Errorf("status %d: %s", resp.StatusCode, body)
}
```

**Não usar `http.DefaultClient` em produção** — não tem timeout:

```go
var httpClient = &http.Client{
    Timeout: 10 * time.Second,
    Transport: &http.Transport{
        MaxIdleConns:        100,
        MaxIdleConnsPerHost: 10,
        IdleConnTimeout:     90 * time.Second,
    },
}
```

Sempre usar `http.NewRequestWithContext(ctx, ...)` para que a chamada respeite cancelamento.
