# Observabilidade como contrato

## Princípio

**Logs, métricas e traces são contratos operacionais.** Quem mexe neles quebra dashboard, alerta e runbook tanto quanto quem muda um campo de proto. Tratar com a mesma disciplina que tratamos `.proto`: nome de chave/métrica/span é tão estável quanto nome de campo de mensagem.

A consequência prática: chaves de log e nomes de métrica vivem centralizados, não inline. Mudar uma chave é uma decisão deliberada, com migração de dashboard, não algo que acontece no calor de um PR.

## Logs estruturados (`log/slog`)

### Centralizar chaves em `internal/observability/keys.go`

```go
// internal/observability/keys.go
package observability

// Chaves estáveis de log estruturado. Estes nomes aparecem em dashboards do
// Grafana e regras de alerta no Alertmanager. Renomear quebra observabilidade.
const (
    KeyTraceID     = "trace_id"
    KeyRequestID   = "request_id"
    KeyAssinanteID = "assinante_id"
    KeyMSISDN      = "msisdn"
    KeyFaturaID    = "fatura_id"
    KeyError       = "err"
    KeyDuration    = "duration_ms"
    KeyOperacao    = "operacao"      // ex: "suspender_linha", "gerar_fatura"
    KeyComponent   = "component"     // ex: "outbox-worker", "grpc-handler"
)
```

Uso:

```go
import "github.com/Iez-Telecom/cobranca-svc/internal/observability"

logger.Info("linha suspensa por inadimplência",
    observability.KeyAssinanteID, a.ID,
    observability.KeyMSISDN,       linha.MSISDN,
    observability.KeyOperacao,     "suspender_linha",
    observability.KeyDuration,     time.Since(start).Milliseconds(),
)
```

`golangci-lint` com regra `goconst` ajuda a detectar chaves "soltas" pelo código.

### Padrão de níveis

- **`slog.Debug`**: detalhe de fluxo útil em dev/staging, ruidoso em produção. Desligado por default.
- **`slog.Info`**: eventos de negócio relevantes (linha ativada, fatura gerada, evento publicado). Sempre on.
- **`slog.Warn`**: situação degradada mas recuperável (retry, rate limit, fallback ativado).
- **`slog.Error`**: erro que precisa de atenção. Toda chamada de `Error` deve ter `KeyError` com o erro original.

Nunca `slog.Info("erro: ...")` — perde a query "todos os erros das últimas 24h".

### Atributos contextuais via context

```go
// internal/observability/context.go
package observability

type ctxKey struct{ name string }

var traceIDKey = ctxKey{"trace_id"}

func WithTraceID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, traceIDKey, id)
}

func TraceID(ctx context.Context) string {
    v, _ := ctx.Value(traceIDKey).(string)
    return v
}

// LoggerFromContext extrai um logger já enriquecido com atributos do contexto.
func LoggerFromContext(ctx context.Context, base *slog.Logger) *slog.Logger {
    return base.With(KeyTraceID, TraceID(ctx))
}
```

Interceptor gRPC injeta `trace_id` no contexto; handlers usam `LoggerFromContext` para já loggar com ele.

## Tracing (OpenTelemetry)

OpenTelemetry é **o** padrão de spec para tracing distribuído. O wire format dele (W3C Trace Context) é a interface entre serviços.

### Setup mínimo

```go
// internal/observability/tracing.go
package observability

import (
    "context"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func NewTracerProvider(ctx context.Context, serviceName, version string) (*sdktrace.TracerProvider, error) {
    exporter, err := otlptracegrpc.New(ctx)
    if err != nil {
        return nil, fmt.Errorf("criar exporter OTLP: %w", err)
    }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceName(serviceName),
            semconv.ServiceVersion(version),
        )),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}
```

### Naming convention para spans

Spans seguem `<componente>.<operação>`. Operação em português (vocabulário de domínio); componente em inglês.

```go
tracer := otel.Tracer("cobranca-svc")

ctx, span := tracer.Start(ctx, "handler.SuspenderLinhaPorInadimplencia")
defer span.End()

// Em camadas internas:
ctx, span := tracer.Start(ctx, "store.AtualizarSituacaoLinha")
ctx, span := tracer.Start(ctx, "outbox.PublicarEvento")
```

Atributos no span seguem **as mesmas chaves** dos logs:

```go
span.SetAttributes(
    attribute.String(KeyAssinanteID, a.ID),
    attribute.String(KeyOperacao, "suspender_linha"),
)
```

Alinhamento entre logs e traces: você consegue pular de log para trace usando `trace_id`.

### Interceptors

Para gRPC, usar `otelgrpc.NewServerHandler()` e `otelgrpc.NewClientHandler()` da `go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc`. Eles cuidam de extrair/injetar W3C Trace Context automaticamente.

## Métricas (Prometheus)

Convenção de naming (padrão Prometheus + Iez):

```
<namespace>_<subsistema>_<nome>_<unidade>
```

- `namespace`: nome do serviço sem `-svc` (`cobranca`, `assinante`)
- `subsistema`: domínio interno (`fatura`, `outbox`, `grpc`)
- `nome`: o que mede (`total`, `bytes`, `duration`)
- `unidade`: `seconds`, `bytes`, `total` (para counters)

Exemplos:

```
cobranca_fatura_emitidas_total           # counter
cobranca_outbox_pending_count            # gauge
cobranca_grpc_request_duration_seconds   # histogram
```

### Centralizar registro

```go
// internal/observability/metrics.go
package observability

import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
)

var (
    FaturasEmitidasTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "cobranca_fatura_emitidas_total",
            Help: "Total de faturas emitidas, particionado por situação.",
        },
        []string{"situacao_assinante"},
    )

    OutboxPendingCount = promauto.NewGauge(
        prometheus.GaugeOpts{
            Name: "cobranca_outbox_pending_count",
            Help: "Eventos no outbox aguardando publicação no NATS.",
        },
    )

    GRPCRequestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "cobranca_grpc_request_duration_seconds",
            Help:    "Latência de handlers gRPC em segundos.",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "code"},
    )
)
```

### Cardinalidade de labels — cuidado

Cada combinação de labels = uma série temporal. Labels com cardinalidade ilimitada (user_id, request_id, msisdn) **explodem** o Prometheus.

Regra prática: o produto cartesiano de todos os valores possíveis de labels deve caber em < 10.000 séries por métrica. Se passar disso, o label é dado para log/trace, não para métrica.

| OK como label | Nunca como label |
|---|---|
| `situacao` (5 valores) | `assinante_id` (milhões) |
| `metodo_pagamento` (4 valores) | `msisdn` (milhões) |
| `code` gRPC (16 valores) | `trace_id` (infinito) |
| `tenant_id` (dezenas) | `email` (infinito) |

### Endpoint `/metrics`

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

http.Handle("/metrics", promhttp.Handler())
go http.ListenAndServe(":9090", nil)  // porta interna, nunca pública
```

## O conjunto importa mais que as peças

O valor de observabilidade vem do **trio funcionando junto**:

- **Log** te diz *o que aconteceu*.
- **Métrica** te diz *com que frequência e quão rápido*.
- **Trace** te diz *o caminho exato que a request percorreu entre serviços*.

Se os três usam **as mesmas chaves** (`trace_id`, `assinante_id`, `operacao`), você navega entre eles com um clique. Se cada um inventa nomes próprios, viram três silos.

## Health checks

Distinguir:

- **`/healthz` (liveness):** o processo está vivo? Não testa dependências. K8s reinicia se falhar.
- **`/readyz` (readiness):** o processo está pronto para receber tráfego? Testa banco, cache, etc. K8s tira do balancer se falhar.

```go
mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
})

mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
    if err := pool.Ping(r.Context()); err != nil {
        http.Error(w, "banco indisponível", http.StatusServiceUnavailable)
        return
    }
    w.WriteHeader(http.StatusOK)
})
```

## Checklist de PR que mexe em observabilidade

- [ ] Nova chave de log? Está em `internal/observability/keys.go`?
- [ ] Nova métrica? Nome segue `<namespace>_<subsistema>_<nome>_<unidade>`?
- [ ] Label de métrica tem cardinalidade finita pequena (<100)?
- [ ] Span novo segue `<componente>.<operação>`?
- [ ] Atributos do span usam as mesmas chaves dos logs?
- [ ] Dashboard/alerta correspondente atualizado (ou ticket aberto)?
- [ ] Se removeu/renomeou: confirmou que ninguém depende (grep no repo de dashboards)?

## Anti-padrões

- **Chaves de log inline** (`logger.Info("...", "trace-id", ...)` em um arquivo e `"traceID"` em outro). Resultado: queries quebradas.
- **Métrica com label de alta cardinalidade** (`user_id`, `request_id`). Resultado: Prometheus OOM em produção.
- **`fmt.Printf` ou `log.Println`** em código de produção. Não estrutura, não tem nível, não tem contexto.
- **Logar erro e continuar como se nada**. Erro existe para ser tratado ou propagado.
- **Span sem atributos relevantes**. Trace de "função foo executou em 12ms" sem saber sobre o que ela operou é inútil.
- **Health check que pinga banco em `/healthz`**. Quando o banco oscila, K8s reinicia o pod em loop e piora o problema.
