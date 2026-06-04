# Concorrência em Go

A parte mais difícil de acertar em Go. Padrão: **não** usar goroutines até ter uma razão clara; padrão: **mutexes** antes de channels.

## Regras de ownership de goroutines

Toda `go func()` deve responder três perguntas:

1. **Quem espera ela terminar?** (`sync.WaitGroup`, `errgroup.Group`, ou sinal via channel)
2. **Como ela é cancelada?** (um `context.Context` que ela observa)
3. **Para onde vão os erros?** (um channel de erro, um `errgroup`, ou logado na boundary)

Se não conseguir responder as três, não criar a goroutine.

## Padrão: errgroup com context

O padrão de concorrência mais útil. Usar `golang.org/x/sync/errgroup`:

```go
// fetchAll busca todos os itens em paralelo com limite de concorrência.
func fetchAll(ctx context.Context, ids []string) ([]Item, error) {
    g, ctx := errgroup.WithContext(ctx)
    items := make([]Item, len(ids))

    for i, id := range ids {
        g.Go(func() error {
            item, err := fetch(ctx, id)
            if err != nil {
                return fmt.Errorf("buscar %s: %w", id, err)
            }
            items[i] = item
            return nil
        })
    }

    if err := g.Wait(); err != nil {
        return nil, err
    }
    return items, nil
}
```

Se qualquer goroutine retornar erro, o context é cancelado e `Wait` retorna aquele erro. Cada goroutine escreve no seu próprio slot do slice — sem mutex necessário.

## Padrão: concorrência limitada

Não criar N goroutines para N itens se N é ilimitado. Usar `errgroup.SetLimit` (Go 1.20+):

```go
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(8) // máximo 8 em voo
for _, id := range ids {
    g.Go(func() error { return process(ctx, id) })
}
return g.Wait()
```

## Padrão: worker pool

Quando precisa de workers de longa duração consumindo uma fila:

```go
// runPool inicia n workers que processam jobs do channel.
func runPool(ctx context.Context, n int, jobs <-chan Job) error {
    g, ctx := errgroup.WithContext(ctx)
    for i := 0; i < n; i++ {
        g.Go(func() error {
            for {
                select {
                case <-ctx.Done():
                    return ctx.Err()
                case job, ok := <-jobs:
                    if !ok {
                        return nil // channel fechado, sem mais trabalho
                    }
                    if err := handle(ctx, job); err != nil {
                        return err
                    }
                }
            }
        })
    }
    return g.Wait()
}
```

O produtor fecha `jobs` para sinalizar "sem mais trabalho". Workers saem de forma limpa em `ctx.Done()` ou fechamento do channel.

## Channels: quando e como

Usar channels para:
- **Sinalização** entre goroutines (done, ready, cancel)
- **Streaming** de valores de um produtor para um consumidor
- **Distribuição de trabalho** (um channel, vários leitores)

Não usar channels para:
- Proteger um pedaço de estado em memória. Usar `sync.Mutex`.
- Substituir chamadas de função por "mensagens".

Regras:
- **O sender fecha o channel, nunca o receiver.** Fechar um channel que não é seu causa panic.
- **Não fechar channel com múltiplos senders** sem coordenação. Usar `sync.Once` ou reestruturar.
- Receive de channel fechado retorna o zero value imediatamente. Usar `v, ok := <-ch` para detectar close.
- Channels com buffer não são "mais rápidos". Usar buffer tamanho 1 para handoff, maior apenas com justificativa.

## Mutexes

`sync.Mutex` para acesso exclusivo, `sync.RWMutex` quando leituras superam escritas enormemente (e você mediu).

```go
// Cache implementa um cache thread-safe em memória.
type Cache struct {
    mu   sync.RWMutex
    data map[string]string
}

// Get busca um valor no cache de forma thread-safe.
func (c *Cache) Get(k string) (string, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    v, ok := c.data[k]
    return v, ok
}

// Set armazena um valor no cache de forma thread-safe.
func (c *Cache) Set(k, v string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    if c.data == nil {
        c.data = make(map[string]string)
    }
    c.data[k] = v
}
```

- Lockar o mais estreitamente possível — não segurar lock durante I/O.
- Nunca copiar uma struct contendo mutex. Passar `*Cache`, não `Cache`.
- `defer Unlock()` imediatamente após `Lock()` para não esquecer em retornos antecipados.

## Propagação de context

```go
// handle processa um request HTTP com timeout de 5 segundos.
func (s *Server) handle(w http.ResponseWriter, r *http.Request) {
    ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
    defer cancel()

    user, err := s.users.Get(ctx, id) // propagado até o banco
    // ...
}
```

- **Sempre passar `ctx` como primeiro parâmetro** de qualquer função que faz I/O.
- **Sempre chamar `cancel`** de `WithCancel`/`WithTimeout`/`WithDeadline`, mesmo no caminho feliz. Usar `defer cancel()`.
- **Nunca armazenar `ctx` em struct.** Exceção: workers de background de longa duração podem ter seu próprio context derivado.
- **Nunca passar `nil` ctx.** Usar `context.TODO()` se genuinamente não tem um.
- `context.Value` é para dados request-scoped (request ID, identidade do usuário), não para passar dependências.

## Race detector

```bash
go test -race ./...
go run -race ./cmd/server
go build -race
```

Rodar `-race` no CI e durante desenvolvimento. Ele encontra bugs reais. Sim, é mais lento — por isso não vai em builds de produção.

## Testando código concorrente: `testing/synctest` (Go 1.24+)

Antes de Go 1.24, testar código concorrente envolvia `time.Sleep` que vazava determinismo (flaky em CI). O `testing/synctest` introduz um clock virtual e detecção de deadlock: o teste avança o tempo instantaneamente quando todas as goroutines estão bloqueadas.

```go
func TestRetryComBackoff(t *testing.T) {
    synctest.Run(func() {
        start := time.Now()
        err := RetryComBackoff(context.Background(), 3, func() error {
            return errors.New("falha temporária")
        })
        elapsed := time.Since(start)

        // Mesmo com retries que somam 7s no relógio virtual, o teste
        // roda instantaneamente porque synctest avança o clock.
        if elapsed < 7*time.Second {
            t.Errorf("backoff insuficiente: %v", elapsed)
        }
        if err == nil {
            t.Fatal("esperava erro após retries")
        }
    })
}
```

Game changer para testar timeouts, retries, schedulers, rate limiters. Ver `references/testing.md` para detalhes.

## Bugs comuns

### Vazamento de `time.After` em loop

```go
// VAZA — cada iteração cria um timer que vive até disparar
for {
    select {
    case <-ctx.Done():
        return
    case <-time.After(time.Second):
        // ...
    }
}

// CORREÇÃO — reutilizar o timer
t := time.NewTimer(time.Second)
defer t.Stop()
for {
    t.Reset(time.Second)
    select {
    case <-ctx.Done():
        return
    case <-t.C:
        // ...
    }
}
```

### `defer` em loop

```go
// VAZA file handles até a função retornar
for _, path := range paths {
    f, _ := os.Open(path)
    defer f.Close()
    // ...
}

// CORREÇÃO — extrair função
for _, path := range paths {
    if err := processFile(path); err != nil {
        return err
    }
}

// processFile processa um único arquivo com cleanup garantido.
func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close()
    // ...
}
```

### Vazamento de goroutine por send bloqueante

```go
// VAZA goroutine se ninguém lê ch
go func() {
    ch <- compute() // bloqueia para sempre se o receiver sumiu
}()

// CORREÇÃO — select em ctx.Done()
go func() {
    select {
    case ch <- compute():
    case <-ctx.Done():
    }
}()
```

## Quando NÃO usar goroutines

- "Quero mais rápido" — medir primeiro. Overhead de goroutine é real.
- "Fire and forget" — fire-and-forget sem ownership é um vazamento esperando acontecer.
- Dentro de hot loop criando uma por item — usar worker pool com concorrência limitada.
