# Banco de dados em Go

## Stack obrigatória

- **Driver**: `github.com/jackc/pgx/v5` (diretamente ou via `pgx/v5/pgxpool`)
- **Code generation**: `sqlc` — gera código Go type-safe a partir de queries SQL
- **ORMs são proibidos**: sem GORM, ent, ou similares. SQL escrito à mão, gerado por `sqlc`.
- **Migrations**: usar `github.com/golang-migrate/migrate/v4` ou `github.com/pressly/goose`

## Setup de conexão com pgxpool

```go
// internal/database/pool.go
package database

import (
    "context"
    "fmt"
    "time"

    "github.com/jackc/pgx/v5/pgxpool"
)

// NewPool cria um pool de conexões configurado para produção.
func NewPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
    config, err := pgxpool.ParseConfig(databaseURL)
    if err != nil {
        return nil, fmt.Errorf("parse config: %w", err)
    }

    // Configurações otimizadas para alto volume de transações
    config.MaxConns = 25
    config.MinConns = 5
    config.MaxConnLifetime = 5 * time.Minute
    config.MaxConnIdleTime = 30 * time.Second
    config.HealthCheckPeriod = 15 * time.Second

    pool, err := pgxpool.NewWithConfig(ctx, config)
    if err != nil {
        return nil, fmt.Errorf("criar pool: %w", err)
    }

    // Verificar conectividade
    pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()
    if err := pool.Ping(pingCtx); err != nil {
        pool.Close()
        return nil, fmt.Errorf("ping: %w", err)
    }

    return pool, nil
}
```

Usar `pgxpool.Pool` (não `pgx.Conn` avulso) — o pool gerencia conexões automaticamente.

## Workflow com sqlc

### 1. Configurar sqlc.yaml

O `sqlc.yaml` mora na raiz do repositório. Queries em `sql/queries/`, schema em `sql/schema/`, código gerado em `gen/sql/`.

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

### 2. Escrever o schema

Tabelas e colunas de domínio em português. Convenções técnicas (`id`, `created_at`, `updated_at`) em inglês.

```sql
-- sql/schema/schema.sql

CREATE TABLE assinantes (
    id              UUID PRIMARY KEY,
    cpf             VARCHAR(11) NOT NULL UNIQUE,
    nome            TEXT NOT NULL,
    msisdn          VARCHAR(13) NOT NULL UNIQUE,
    situacao        SMALLINT NOT NULL,
    data_ativacao   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_assinantes_cpf ON assinantes(cpf);
CREATE INDEX idx_assinantes_situacao ON assinantes(situacao);
```

### 3. Escrever queries SQL

Nomes de queries são operações de domínio — em português.

```sql
-- sql/queries/assinantes.sql

-- name: BuscarAssinantePorMSISDN :one
SELECT * FROM assinantes
WHERE msisdn = $1;

-- name: BuscarAssinantePorCPF :one
SELECT * FROM assinantes
WHERE cpf = $1;

-- name: ListarAssinantesPorSituacao :many
SELECT * FROM assinantes
WHERE situacao = $1
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: SalvarAssinante :one
INSERT INTO assinantes (id, cpf, nome, msisdn, situacao, data_ativacao)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: AtualizarSituacaoAssinante :exec
UPDATE assinantes
SET situacao = $2, updated_at = NOW()
WHERE id = $1;
```

### 3. Gerar código

```bash
make generate   # que internamente roda: sqlc generate
```

`sqlc` gera structs e métodos type-safe. Nunca editar os arquivos gerados.

### 4. Usar no código

O `store.go` do pacote de feature encapsula o acesso ao banco. A interface `Store` é definida no mesmo pacote (consumidor).

```go
// internal/assinante/store.go
package assinante

import (
    "context"
    "errors"
    "fmt"

    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    pg "github.com/acme/meuservico/gen/sql"
)

// Store define as operações de persistência de assinante.
type Store interface {
    BuscarPorMSISDN(ctx context.Context, msisdn string) (Assinante, error)
    BuscarPorCPF(ctx context.Context, cpf string) (Assinante, error)
    Salvar(ctx context.Context, a Assinante) error
}

type pgStore struct {
    queries *pg.Queries
}

// NewStore cria um Store backed pelo banco PostgreSQL.
func NewStore(pool *pgxpool.Pool) Store {
    return &pgStore{queries: pg.New(pool)}
}

// BuscarPorMSISDN retorna o assinante com o MSISDN informado.
func (s *pgStore) BuscarPorMSISDN(ctx context.Context, msisdn string) (Assinante, error) {
    row, err := s.queries.BuscarAssinantePorMSISDN(ctx, msisdn)
    if errors.Is(err, pgx.ErrNoRows) {
        return Assinante{}, ErrAssinanteNaoEncontrado
    }
    if err != nil {
        return Assinante{}, fmt.Errorf("buscar assinante por msisdn: %w", err)
    }
    return fromDBAssinante(row), nil
}
```

## Sempre usar variantes Context

`sqlc` gera métodos que já recebem `context.Context`. Nunca contornar isso.

## Transações

```go
// Transfer executa uma transferência entre contas dentro de uma transação.
func (s *AccountService) Transfer(ctx context.Context, from, to int64, amount int64) error {
    tx, err := s.pool.Begin(ctx)
    if err != nil {
        return fmt.Errorf("iniciar transação: %w", err)
    }
    defer tx.Rollback(ctx) // no-op após Commit; faz rollback em retorno antecipado

    qtx := s.queries.WithTx(tx)

    if err := qtx.DebitAccount(ctx, database.DebitAccountParams{
        ID:     from,
        Amount: amount,
    }); err != nil {
        return fmt.Errorf("debitar conta %d: %w", from, err)
    }

    if err := qtx.CreditAccount(ctx, database.CreditAccountParams{
        ID:     to,
        Amount: amount,
    }); err != nil {
        return fmt.Errorf("creditar conta %d: %w", to, err)
    }

    if err := tx.Commit(ctx); err != nil {
        return fmt.Errorf("commit: %w", err)
    }
    return nil
}
```

O padrão `defer tx.Rollback(ctx)` é idiomático — após `Commit()` retorna erro ignorável.

## SQL injection: sempre parametrizar

`sqlc` cuida disso automaticamente — as queries geradas usam parâmetros posicionais (`$1`, `$2`). Nunca concatenar strings para construir queries fora do `sqlc`.

Se precisar de identificadores dinâmicos (nomes de tabela, coluna) — eles não podem ser parametrizados; fazer whitelist no código.

## Migrations

Usar uma ferramenta de migration real, não SQL ad-hoc na inicialização:

```
migrations/
├── 000001_create_users.up.sql
├── 000001_create_users.down.sql
├── 000002_add_orgs.up.sql
└── 000002_add_orgs.down.sql
```

Rodar migrations como etapa separada no deploy (CI/CD), não no `main()`.

Ferramentas aceitas:
- `github.com/golang-migrate/migrate/v4`
- `github.com/pressly/goose`

## Otimizações para alto volume

- **Prepared statements**: ativar `emit_prepared_queries: true` no `sqlc.yaml`. O `pgx` prepara automaticamente no nível de conexão.
- **Batch queries**: usar `pgx.Batch` quando precisar executar múltiplas queries independentes em uma ida ao servidor.
- **COPY**: para inserções em massa, usar `pgx.CopyFrom` ao invés de INSERT em loop.
- **Connection pool sizing**: regra de ouro `MaxConns = (2 × número de CPUs) + discos efetivos`. Ajustar com métricas.
- **Índices**: revisar `EXPLAIN ANALYZE` para toda query crítica.

```go
// Exemplo de batch insert com pgx.CopyFrom
func (r *Repo) BulkInsert(ctx context.Context, items []Item) (int64, error) {
    columns := []string{"name", "value", "created_at"}
    rows := make([][]any, len(items))
    for i, item := range items {
        rows[i] = []any{item.Name, item.Value, item.CreatedAt}
    }

    count, err := r.pool.CopyFrom(
        ctx,
        pgx.Identifier{"items"},
        columns,
        pgx.CopyFromRows(rows),
    )
    if err != nil {
        return 0, fmt.Errorf("bulk insert: %w", err)
    }
    return count, nil
}
```

## Padrão store (repository)

Definir interface no **consumidor** — no `store.go` do próprio pacote de feature. Implementar no mesmo arquivo. Testes usam fakes que implementam a interface, não mocks do pool.

```go
// internal/contrato/store.go
package contrato

import "context"

// Store define as operações de persistência que o pacote contrato precisa.
// Interface definida aqui (consumidor), implementada no mesmo arquivo.
type Store interface {
    BuscarPorID(ctx context.Context, id string) (Contrato, error)
    ListarPorAssinante(ctx context.Context, assinanteID string) ([]Contrato, error)
    Salvar(ctx context.Context, c Contrato) error
    AtualizarSituacao(ctx context.Context, id string, situacao SituacaoContrato) error
}

// Handler usa Store via interface — testável sem banco real.
type Handler struct {
    store  Store
    logger *slog.Logger
}
```

## Regras que NÃO devem ser quebradas

- **NUNCA** usar GORM, ent, ou qualquer ORM.
- **NUNCA** escrever queries SQL como strings concatenadas no código Go.
- **SEMPRE** usar `sqlc` para gerar o código de acesso ao banco.
- **SEMPRE** usar `pgx/v5` como driver.
- **SEMPRE** passar `context.Context` em todas as operações de banco.
