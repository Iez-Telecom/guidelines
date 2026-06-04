# Layout de projeto

## Estrutura padrão do time

```
cmd/
  server/
    main.go               # Orquestrador: wiring e inicialização — sem lógica de negócio
api/proto/v1/             # Contratos de serviço expostos via Envoy ou gRPC direto
  assinantes.proto
  contratos.proto
  contratos_types.proto   # Opcional: quando há grande número de tipos
gen/
  go/v1/                  # Código gerado do protobuf (nunca editar)
  sql/                    # Código gerado pelo sqlc (nunca editar)
sql/                      # Fontes para o sqlc
  queries/
    assinantes.sql        # Queries para o pacote internal/assinante
    contratos.sql
  schema/
    schema.sql            # Schema do banco (lido pelo sqlc para tipos corretos)
internal/
  assinante/              # Pacote de feature — todo código de assinante
    assinante.go          # Tipos do domínio e lógica de negócio
    assinante_tipos.go    # Opcional: separar tipos quando há muitos
    handler.go            # Handler gRPC (protocolo → domínio)
    store.go              # Acesso ao banco (usa sqlc)
    cpf.go                # Lógica específica de CPF (conhecimento de domínio)
  contrato/               # Outro pacote de feature, mesmo padrão
  database/
    database.go           # Abertura, gerenciamento e fechamento da conexão
  cep/                    # Pacote de domínio compartilhado (tratamento de CEP)
  config/                 # Carregamento de configuração
  logger/                 # Configuração de log
external/
  operadora_destino/      # Wrapper do cliente gRPC para serviço externo (ACL)
  receita_federal/
sqlc.yaml                 # Configuração do sqlc na raiz do repositório
buf.yaml
buf.gen.yaml
go.mod
go.sum
Makefile
```

## Por que feature, não camada

**Dentro de `internal/`, organizar por feature, não por camada.**

Um pacote de feature (`assinante/`) contém tudo relacionado àquela feature: handler, lógica de domínio, persistência. Quando você adiciona algo, edita um único diretório. Quando você lê, coisas relacionadas estão juntas.

A divisão estilo Java em `/handlers`, `/services`, `/repositories` espalha o código de uma feature por três pastas diferentes. É o anti-padrão que evitamos.

A divisão em camadas acontece **dentro do pacote**, via arquivos separados (`handler.go`, `assinante.go`, `store.go`) — não via subpacotes.

## Pastas na raiz

Pastas no nível raiz separam coisas categoricamente diferentes:
- `cmd/` — pontos de entrada
- `api/` — contratos publicados
- `gen/` — código gerado por máquina
- `sql/` — fontes para o sqlc
- `internal/` — código privado do serviço
- `external/` — wrappers para serviços externos (Anti-Corruption Layer)

## Regras de layout

### `cmd/server/main.go`

O ponto de entrada cuida de inicialização, configuração, criação dos recursos compartilhados e wiring das dependências — e nada mais.

```go
// cmd/server/main.go
package main

import (
    "context"
    "log/slog"
    "os"
    "os/signal"
    "syscall"

    "github.com/acme/meuservico/internal/assinante"
    "github.com/acme/meuservico/internal/config"
    "github.com/acme/meuservico/internal/database"
    "github.com/acme/meuservico/internal/logger"
)

func main() {
    log := logger.New()
    slog.SetDefault(log)

    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    if err := run(ctx, log); err != nil {
        slog.Error("falha na inicialização", "err", err)
        os.Exit(1)
    }
}

func run(ctx context.Context, log *slog.Logger) error {
    cfg, err := config.Load()
    if err != nil {
        return fmt.Errorf("carregar config: %w", err)
    }

    pool, err := database.NewPool(ctx, cfg.DatabaseURL)
    if err != nil {
        return fmt.Errorf("criar pool: %w", err)
    }
    defer pool.Close()

    assinanteStore := assinante.NewStore(pool)
    assinanteHandler := assinante.NewHandler(assinanteStore, log)

    // Iniciar servidor gRPC, aguardar ctx.Done(), graceful shutdown
    return runGRPCServer(ctx, cfg.GRPCAddr, assinanteHandler, log)
}
```

**Lógica de negócio no `main.go` é proibida.** Regra absoluta — sem exceção de tamanho.

### `internal/<feature>/`

Cada pacote de feature contém arquivos com responsabilidades bem definidas:

| Arquivo | Responsabilidade |
|---|---|
| `assinante.go` | Tipos do domínio + lógica de negócio |
| `assinante_tipos.go` | Opcional: separar tipos quando há muitos |
| `handler.go` | Handler gRPC: protocolo → domínio → protocolo |
| `store.go` | Acesso ao banco via sqlc |
| `cpf.go` | Lógica específica de subconceito |

O handler traduz request para domínio e domínio para response — nada mais. Lógica de negócio fica em `assinante.go`. Acesso ao banco fica em `store.go`.

```go
// internal/assinante/handler.go
package assinante

import (
    "context"
    "errors"
    "log/slog"

    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"

    assinantev1 "github.com/acme/meuservico/gen/go/v1"
)

type Handler struct {
    assinantev1.UnimplementedServicoAssinantesServer
    store  Store
    logger *slog.Logger
}

func NewHandler(store Store, logger *slog.Logger) *Handler {
    return &Handler{store: store, logger: logger}
}

func (h *Handler) BuscarAssinantePorMSISDN(ctx context.Context, req *assinantev1.BuscarAssinantePorMSISDNRequest) (*assinantev1.BuscarAssinantePorMSISDNResponse, error) {
    if req.GetMsisdn() == "" {
        return nil, status.Error(codes.InvalidArgument, "msisdn é obrigatório")
    }

    a, err := h.store.BuscarPorMSISDN(ctx, req.GetMsisdn())
    if errors.Is(err, ErrAssinanteNaoEncontrado) {
        return nil, status.Errorf(codes.NotFound, "assinante %s não encontrado", req.GetMsisdn())
    }
    if err != nil {
        h.logger.Error("falha ao buscar assinante", "err", err, "msisdn", req.GetMsisdn())
        return nil, status.Error(codes.Internal, "erro interno")
    }

    return &assinantev1.BuscarAssinantePorMSISDNResponse{
        Assinante: paraProtoAssinante(a),
    }, nil
}
```

### `internal/database/`

Abertura e gerenciamento do pool de conexão. Não contém lógica de feature.

### Pacotes de domínio compartilhado

Quando múltiplas features precisam do mesmo conhecimento de domínio, ele ganha pacote próprio com nome descritivo:

```
internal/
  cep/        # tratamento de CEP — compartilhado por assinante, contrato
  cpf/        # validação de CPF — se compartilhado por múltiplos pacotes
```

Não existe `utils/`, `helpers/`, `common/` em nenhum nível. Nunca.

Quando você quiser criar um `utils/`, pergunte: "que nome eu daria a um pacote contendo apenas isso?" A resposta quase sempre é um nome real. Use esse nome.

### `external/`

Wrappers para serviços externos — implementam a Anti-Corruption Layer (ACL). Ver seção abaixo.

## Anti-Corruption Layer (external/)

Toda integração com sistema externo passa por uma ACL em `external/`. O wrapper:

1. **Traduz vocabulário**: tipos externos nunca cruzam a fronteira. O código de domínio vê tipos do seu domínio, não do sistema externo.
2. **Traduz erros**: HTTP 503, 422, 200-com-erro-no-corpo → códigos gRPC (`codes.Unavailable`, `codes.InvalidArgument`).
3. **Centraliza preocupações transversais**: retry, backoff, circuit breaking, cache, autenticação.
4. **Define a interface no consumidor**: o pacote de feature define a interface com os métodos que precisa; `external/` implementa.

```go
// internal/assinante/assinante.go — interface definida no consumidor
type ReceitaFederalClient interface {
    ConsultarCPF(ctx context.Context, cpf string) (SituacaoCPF, error)
}

// external/receita_federal/client.go — implementação na ACL
package receita_federal

// Client implementa assinante.ReceitaFederalClient traduzindo para o vocabulário
// do nosso domínio.
type Client struct {
    httpClient *http.Client
    baseURL    string
}

func (c *Client) ConsultarCPF(ctx context.Context, cpf string) (assinante.SituacaoCPF, error) {
    // chama API da Receita, traduz resposta para tipos do domínio
}
```

A ACL aplica-se também a outros serviços internos com modelo diferente do seu.

## Interfaces no consumidor

Interfaces são definidas no **pacote que as consome**, não no pacote que as implementa.

```go
// internal/assinante/store.go — interface definida aqui, no consumidor
package assinante

// Store define as operações de persistência que o pacote assinante precisa.
type Store interface {
    BuscarPorMSISDN(ctx context.Context, msisdn string) (Assinante, error)
    BuscarPorCPF(ctx context.Context, cpf string) (Assinante, error)
    Salvar(ctx context.Context, a Assinante) error
}
```

A implementação concreta fica em `store.go` (usando sqlc) e satisfaz a interface implicitamente.

## Configuração do sqlc

O `sqlc.yaml` mora na raiz do repositório, ao lado do `go.mod`:

```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "sql/queries/"
    schema: "sql/schema/"
    gen:
      go:
        package: "pg_sql"
        out: "gen/sql"
        sql_package: "pgx/v5"
        emit_interface: false
        emit_pointers_for_null_types: true
        emit_json_tags: true
        emit_prepared_queries: false
        emit_exact_table_names: false
        emit_empty_slices: true
```

Nomes de queries ficam em português (são operações de domínio):

```sql
-- sql/queries/assinantes.sql

-- name: BuscarAssinantePorMSISDN :one
SELECT * FROM assinantes WHERE msisdn = $1;

-- name: BuscarAssinantePorCPF :one
SELECT * FROM assinantes WHERE cpf = $1;

-- name: SalvarAssinante :one
INSERT INTO assinantes (id, cpf, nome, msisdn, situacao, data_ativacao)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: AtualizarSituacaoAssinante :exec
UPDATE assinantes
SET situacao = $2, updated_at = NOW()
WHERE id = $1;
```

## Makefile obrigatório

```makefile
.PHONY: generate build test lint run container clean

generate:
	buf generate
	sqlc generate

build:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/server ./cmd/server

test:
	go test -race -count=1 ./...

lint:
	gofmt -l .
	go vet ./...
	staticcheck ./...

run:
	go run ./cmd/server

container:
	podman build -f deploy/Containerfile -t meuservico:latest .

clean:
	rm -rf bin/
```

## Quando divergir do padrão

**Mais simples**: serviço sem lógica de negócio (proxy, wrapper fino de gRPC para REST, <~2.000 linhas). Pode ser um único pacote com handler e cliente externo, sem subpastas de feature.

**Mais estruturado**: pacote de feature com lógica de domínio rica (regras de precificação, workflows, máquinas de estado) ou passando de ~1.500 linhas. Dividir em subpacotes: `assinante/service/`, `assinante/store/`, `assinante/transport/`, mantendo tipos compartilhados no `assinante/` raiz.

Qualquer divergência deve ser documentada no README do serviço.

## Anti-padrões

- Organização por camada (`handlers/`, `services/`, `repositories/`) — espalha uma feature por três pastas.
- Pacote `models/` com todas as structs sem lógica — colocar tipos junto do código que os usa.
- Pacote `utils/`, `helpers/`, `common/` em qualquer nível — nomear pelo que o pacote faz.
- Lógica de negócio no handler — o handler só traduz protocolo.
- Tipos do sistema externo cruzando a fronteira da `external/` — violar isso é corrupção do domínio.
- Interfaces definidas no provedor (produtor) — sempre definir no consumidor.
- Seguir `golang-standards/project-layout` como referência — não é padrão oficial; a orientação oficial está em go.dev/doc/modules/layout.
- Arquitetura especulativa para necessidades hipotéticas — resolver problemas do presente.
