# Banco de Dados — Guia para Desenvolvedores

Este documento orienta como o desenvolvedor interage com o banco de dados durante o desenvolvimento. Não é um guia de operações DBA nem de performance de produção — é sobre como trabalhar bem com o banco local e estruturar propostas de schema maduras.

## Stack

| Camada | Ferramenta | Por quê |
|---|---|---|
| Driver | `github.com/jackc/pgx/v5` | pgx nativo, sem abstração de `database/sql`, melhor suporte a tipos PostgreSQL |
| Geração de código | `sqlc` | SQL escrito por humanos, Go gerado; queries são legíveis por qualquer DBA |
| Migrations | `golang-migrate/migrate` | CLI simples, forward-only, sem ORM acoplado |
| Container local | Podman + `compose.yml` | Postgres 16 em `tmpfs`, reset em segundos |

Não usamos ORMs. SQL escrito à mão é lido pelo Go via sqlc e pode ser revisado por qualquer DBA sem conhecer Go.

## Banco local de desenvolvimento

### Setup

O banco local roda em container com `tmpfs` — os dados vivem em memória e desaparecem quando o container para. Isso é intencional: reset é barato, não há estado acumulado entre sessões.

```bash
make db-up       # sobe o Postgres
make db-migrate  # aplica todas as migrations
make db-shell    # psql interativo
```

Variáveis com defaults razoáveis — você raramente precisa mudar:

| Variável | Default | Override |
|---|---|---|
| `POSTGRES_USER` | `dev` | `.env.local` |
| `POSTGRES_PASSWORD` | `dev` | `.env.local` |
| `POSTGRES_DB` | `meuservico_dev` | `.env.local` |
| `POSTGRES_PORT` | `5432` | `.env.local` |

Crie `.env.local` na raiz do serviço para overrides locais. Esse arquivo está no `.gitignore` — nunca commitar.

```bash
# .env.local (exemplo, nunca commitar)
POSTGRES_PORT=5433   # se a porta padrão estiver ocupada
POSTGRES_DB=cobranca_dev
```

### Ciclo de trabalho local

O ciclo de desenvolvimento com banco local é:

```
fazer mudança no schema → make db-reset → make db-migrate → testar → repetir
```

O `make db-reset` destrói e recria o banco, depois reaplica todas as migrations em ordem. Com `tmpfs`, isso leva menos de 5 segundos. Não há motivo para ter medo de resetar.

```bash
make db-reset        # destroy + recreate + migrate (use sem medo)
make db-migrate      # só aplica pendentes (quando não quer destruir dados de teste)
make db-status       # mostra a versão atual
```

### Dados de desenvolvimento

Se o serviço precisa de dados de referência para funcionar localmente (planos, operadoras, tipos de produto), crie `sql/seed.sql`:

```bash
make db-seed         # aplica sql/seed.sql
```

`sql/seed.sql` pode ser commitado, mas não deve conter dados sensíveis — apenas dados fictícios suficientes para que o serviço responda. Não é fixture de teste (isso vai em `_test.go`).

---

## Migrations

### Estrutura

Migrations ficam em `sql/migrations/`. Cada migration é um arquivo `.up.sql`:

```
sql/
  migrations/
    20260104120000_criar_tabela_assinantes.up.sql
    20260110090000_adicionar_coluna_data_portabilidade.up.sql
    20260201143000_criar_index_msisdn.up.sql
  queries/
    assinantes.sql
  schema/
    schema.sql      # referência estática para o sqlc (ver abaixo)
```

### Criando uma migration

```bash
make db-new NAME=criar_tabela_assinantes
# Cria: sql/migrations/20260604143022_criar_tabela_assinantes.up.sql
```

O arquivo gerado tem um stub com comentários para preenchimento:

```sql
-- Migration: descreva aqui o que esta migration faz
-- Contexto: link para issue/ticket, ADR, ou decisão de negócio relevante

CREATE TABLE assinantes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    msisdn          VARCHAR(13) NOT NULL,
    cpf             VARCHAR(11) NOT NULL,
    situacao        situacao_assinante NOT NULL DEFAULT 'ativo',
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_assinantes_msisdn UNIQUE (msisdn),
    CONSTRAINT uq_assinantes_cpf    UNIQUE (cpf)
);

CREATE INDEX idx_assinantes_msisdn ON assinantes (msisdn);
```

### Regra de imutabilidade

**Depois de commitar uma migration, ela não pode ser editada.**

O racional é que outros desenvolvedores (e os ambientes de homologação) já aplicaram aquela migration. Editar cria divergência. Se errou:

- **Antes de commitar**: edite o arquivo à vontade e rode `make db-reset`.
- **Depois de commitar**: crie uma nova migration corretiva.

```bash
# Errou o tipo de uma coluna depois de commitar? Crie outra migration:
make db-new NAME=corrigir_tipo_coluna_data_portabilidade
```

### Sem `.down.sql`

Não criamos arquivos `.down.sql` (rollback). Rollback em produção raramente funciona como esperado e cria falsa sensação de segurança. Para desfazer uma mudança, crie uma migration que avança na direção correta.

### sqlc e o schema

O `sqlc` precisa conhecer o schema para gerar código tipado. Há duas abordagens:

**Opção A (recomendada)**: Aponte o sqlc para `sql/migrations/` como schema. O sqlc parseia os arquivos de migration e infere o schema final:

```yaml
# sqlc.yaml
sql:
  - schema: "sql/migrations/"
    queries: "sql/queries/"
```

**Opção B**: Mantenha `sql/schema/schema.sql` como snapshot manual do schema atual, atualizado a cada migration. Mais trabalho, mas útil como referência de leitura rápida para novos desenvolvedores.

Escolha uma abordagem por serviço e documente no `AGENTS.md` do serviço.

---

## Convenção de nomenclatura do schema

Não tínhamos um padrão definido — este é o padrão adotado. Consistência entre serviços reduz fricção em queries cross-schema e revisões de DBA.

### Tabelas

**snake_case, plural, vocabulário de domínio em português.**

```sql
-- correto
CREATE TABLE assinantes (...);
CREATE TABLE faturas (...);
CREATE TABLE planos (...);
CREATE TABLE eventos_cobranca (...);
CREATE TABLE tentativas_pagamento (...);

-- errado
CREATE TABLE subscribers (...);       -- inglês
CREATE TABLE fatura (...);            -- singular
CREATE TABLE eventosCobranca (...);   -- camelCase
```

### Colunas

**snake_case, vocabulário de domínio em português.**

```sql
-- correto
id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
msisdn          VARCHAR(13) NOT NULL
cpf             VARCHAR(11) NOT NULL
nome_completo   TEXT NOT NULL
situacao        situacao_assinante NOT NULL
data_ativacao   TIMESTAMPTZ
data_vencimento DATE NOT NULL
valor_cobrado   NUMERIC(12,2) NOT NULL
ativo           BOOLEAN NOT NULL DEFAULT TRUE
criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW()
atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW()

-- errado
subscriber_id   -- inglês para conceito de domínio
is_active       -- prefixo is_ em vez de adjetivo direto
created_at      -- inglês (use criado_em)
updated_at      -- inglês (use atualizado_em)
```

Colunas de auditoria padrão em todas as tabelas:

```sql
criado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW()
atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

### Chave primária

Use `UUID` com `gen_random_uuid()` para entidades que cruzam contextos (serviços distintos, APIs externas):

```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```

Use `BIGINT GENERATED ALWAYS AS IDENTITY` para tabelas de alta inserção onde UUID seria custo desnecessário (logs, eventos, filas internas):

```sql
id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
```

### Chaves estrangeiras

```sql
-- convenção: <tabela_singular>_id
assinante_id    UUID NOT NULL REFERENCES assinantes(id)
fatura_id       UUID NOT NULL REFERENCES faturas(id)
plano_id        UUID NOT NULL REFERENCES planos(id)
```

### Constraints

Sempre nomear constraints explicitamente:

```sql
CONSTRAINT pk_assinantes              PRIMARY KEY (id)
CONSTRAINT fk_faturas_assinante       FOREIGN KEY (assinante_id) REFERENCES assinantes(id)
CONSTRAINT uq_assinantes_msisdn       UNIQUE (msisdn)
CONSTRAINT uq_assinantes_cpf          UNIQUE (cpf)
CONSTRAINT ck_faturas_valor_positivo  CHECK (valor_cobrado > 0)
```

Padrão dos nomes:
- `pk_<tabela>`
- `fk_<tabela>_<referência>`
- `uq_<tabela>_<colunas>`
- `ck_<tabela>_<regra>`

### Índices

```sql
-- simples
CREATE INDEX idx_faturas_assinante_id ON faturas (assinante_id);

-- composto (ordem importa: coluna mais seletiva primeiro)
CREATE INDEX idx_faturas_assinante_vencimento ON faturas (assinante_id, data_vencimento);

-- índice de cobertura (inclui coluna extra para evitar heap fetch)
CREATE INDEX idx_cov_faturas_msisdn ON faturas (msisdn) INCLUDE (situacao, valor_cobrado);

-- parcial (quando só um subconjunto é consultado)
CREATE INDEX idx_faturas_pendentes ON faturas (data_vencimento)
  WHERE situacao = 'pendente';
```

Padrão dos nomes: `idx_<tabela>_<colunas>`, prefixo `idx_cov_` para índices de cobertura.

### Tipos enumerados

Use `CREATE TYPE` para enums com cardinalidade estável. Valores em português:

```sql
CREATE TYPE situacao_assinante AS ENUM ('ativo', 'suspenso', 'cancelado');
CREATE TYPE tipo_cobranca AS ENUM ('recorrente', 'avulsa', 'reativacao');
```

Adicionar valores a um enum existente não requer reescrita da tabela (`ALTER TYPE ... ADD VALUE`), mas remover ou reordenar sim. Se o enum mudar com frequência, prefira `SMALLINT` com constantes documentadas.

---

## Queries com sqlc

Queries ficam em `sql/queries/`, um arquivo por tabela ou feature de domínio:

```
sql/queries/
  assinantes.sql
  faturas.sql
  planos.sql
```

Cada query tem um nome e uma anotação de resultado:

```sql
-- name: BuscarAssinantePorMSISDN :one
SELECT id, msisdn, cpf, nome_completo, situacao, criado_em
FROM assinantes
WHERE msisdn = $1
  AND situacao != 'cancelado';

-- name: ListarFaturasPendentes :many
SELECT f.id, f.assinante_id, f.valor_cobrado, f.data_vencimento
FROM faturas f
WHERE f.situacao = 'pendente'
  AND f.data_vencimento <= $1
ORDER BY f.data_vencimento;

-- name: InserirFatura :one
INSERT INTO faturas (assinante_id, valor_cobrado, data_vencimento, situacao)
VALUES ($1, $2, $3, 'pendente')
RETURNING *;
```

A anotação `:one` gera `GetX()` retornando a row diretamente (ou erro `pgx.ErrNoRows`). `:many` gera um `[]Row`. `:exec` para updates/deletes sem retorno. `:execresult` quando você quer o `pgconn.CommandTag`.

Rodando `make generate` (ou `make sql-gen`) o sqlc produz os tipos Go correspondentes em `gen/sql/`. Não edite esses arquivos — eles são regenerados.

### Transações

Para operações que precisam de atomicidade, passe a transação como argumento do repositório:

```go
// No store, aceitar tanto pool quanto tx:
type DBTX interface {
    Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
    Query(context.Context, string, ...any) (pgx.Rows, error)
    QueryRow(context.Context, string, ...any) pgx.Row
}

// O código gerado pelo sqlc já usa esta interface se configurado com
// emit_methods_with_db_argument = true no sqlc.yaml.
```

---

## Homologação

Homologação é um ambiente compartilhado com dados realistas. O comportamento é diferente do local:

| Aspecto | Local | Homologação |
|---|---|---|
| Dados | Efêmeros (`tmpfs`) | Persistidos |
| Reset | `make db-reset` à vontade | Coordenar com o time |
| Migrations | Teste livre | Aplica com `make db-migrate` |
| Acesso | Só você | Time inteiro |

Em homologação, **nunca use `make db-reset`**. Para aplicar uma migration nova:

```bash
make db-migrate
```

Se uma migration falhar em homologação, investigue antes de tentar de novo. Falhas de migration em ambiente compartilhado podem deixar o schema em estado inconsistente.

---

## Proposta de schema para o time de DBA

Quando o banco local e homologação estão validados e a feature vai para produção, as migrations precisam ser revisadas antes de serem aplicadas em produção.

O que entregar:
1. Os arquivos `sql/migrations/*.up.sql` no PR, com comentários explicando cada decisão não óbvia.
2. O contexto de volume esperado (se souber): quantas rows, crescimento por mês, padrão de acesso (leitura pesada, escrita pesada).
3. O `make db-dump-schema` do ambiente de homologação depois de aplicar, para referência.

O DBA time analisa, pode sugerir mudanças nos índices ou tipos, e aplica em produção no momento adequado ao ciclo de deploy.

A migration commitada no repositório é o contrato — o que está lá é o que vai para produção. Não há "script separado para DBA" — o mesmo arquivo serve todos os ambientes.
