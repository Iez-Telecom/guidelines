# Performance em Go

Regra zero: **medir antes de otimizar**. A força do Go é que código idiomático geralmente é rápido o suficiente. Usar estas técnicas apenas após benchmark ou profile apontar um problema real.

## Profiling

### Perfis de CPU e memória

```go
import _ "net/http/pprof"

// Habilitar endpoint de profiling (apenas em dev/staging)
go func() { slog.Info("pprof", "err", http.ListenAndServe("localhost:6060", nil)) }()
```

Depois:

```bash
go tool pprof -http=:8080 http://localhost:6060/debug/pprof/profile?seconds=30
go tool pprof -http=:8080 http://localhost:6060/debug/pprof/heap
go tool pprof -http=:8080 http://localhost:6060/debug/pprof/goroutine
```

### Benchmarks

```bash
go test -bench=. -benchmem -count=10 ./...
benchstat old.txt new.txt    # comparar runs (golang.org/x/perf/cmd/benchstat)
```

`-count=10` importa — benchmarks de run única são ruidosos.

### Execution tracer

```bash
go test -trace trace.out -bench=BenchmarkX
go tool trace trace.out
```

Útil para scheduling de goroutines, pausas de GC, análise de bloqueio.

## Redução de alocações

A maioria do trabalho de performance em Go é reduzir alocações no heap. Usar `-benchmem` e `-gcflags="-m"`:

```bash
go build -gcflags="-m=2" ./... 2>&1 | grep "escapes to heap"
```

Ganhos comuns:

### Pré-dimensionar slices e maps

```go
// 0 alocações para o slice em si
out := make([]Item, 0, len(in))
for _, x := range in {
    out = append(out, transform(x))
}
```

### Reutilizar buffers

```go
var buf bytes.Buffer
for _, line := range lines {
    buf.Reset()
    // escrever no buf, usar
}
```

### Evitar conversões string↔[]byte em hot paths

```go
// Aloca
if string(b) == "hello" { ... }

// Não aloca (Go otimiza essa comparação)
if bytes.Equal(b, []byte("hello")) { ... }
```

### `sync.Pool` para objetos de alta rotatividade

Somente quando alocações são dominantes e objetos são uniformes:

```go
var bufPool = sync.Pool{
    New: func() any { return new(bytes.Buffer) },
}

func handle() {
    buf := bufPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufPool.Put(buf)
    }()
    // usar buf
}
```

`sync.Pool` é armadilha: objetos pooled podem ser coletados pelo GC entre usos, e pooling de objetos pequenos frequentemente prejudica mais do que ajuda. Medir.

## Micro-pessimizações comuns para evitar

- `strings.Builder` ao invés de `+=` em qualquer loop que constrói strings.
- Compilar regex uma vez no nível de pacote, não dentro de funções:
  ```go
  var emailRe = regexp.MustCompile(`...`)
  ```
- Evitar `fmt.Sprintf` para concatenação simples — `+` ou `strings.Builder` é mais rápido.
- `for i := range slice` (sem `_, v`) quando não precisa do valor.
- Evitar `defer` em funções extremamente quentes e minúsculas — tem overhead mensurável (Go 1.14+ reduziu, mas ainda é não-zero).

## Não otimizar o que não é lento

Speedup de 10x em uma função que consome 0.1% do runtime é invisível. Profiling primeiro. O gargalo quase sempre é I/O, não CPU.
