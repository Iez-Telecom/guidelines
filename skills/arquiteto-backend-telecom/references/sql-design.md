# Padrões de Design SQL (Schema + sqlc)

Padrões concretos para escrever schema PostgreSQL e queries `sqlc` alinhados com os `.proto` do serviço. O alvo final é Go via `sqlc` + `pgx/v5`, mas esta skill produz apenas o SQL.

## Estrutura de arquivos

```
sql/
  schema/
    schema.sql              # todas as tabelas, índices, constraints
  queries/
    assinantes.sql          # queries do pacote "assinantes"
    linhas.sql              # queries do pacote "linhas"
    faturas.sql             # 1 arquivo por feature
```

A configuração `sqlc.yaml` na raiz aponta para essas pastas (ver `references/arquitetura.md`, seção "Configuração do sqlc").

## Convenção de idioma aplicada ao SQL

| Elemento                                | Idioma             | Exemplo                                  |
|-----------------------------------------|--------------------|------------------------------------------|
| Nome de tabela (plural, snake_case)     | Português          | `assinantes`, `linhas`, `faturas`        |
| Nome de coluna (snake_case)             | Português          | `data_ativacao`, `valor_mensal`          |
| Colunas técnicas padrão                 | Inglês             | `id`, `created_at`, `updated_at`         |
| Nome de índice                          | Inglês padronizado | `idx_<tabela>_<coluna>`                  |
| Nome de FK constraint                   | Inglês padronizado | `fk_<tabela>_<tabela_referenciada>`      |
| Nome de query no `sqlc`                 | Português          | `BuscarAssinantePorCPF`                  |

## Esqueleto de toda tabela

Toda tabela tem três colunas técnicas obrigatórias:

```sql
CREATE TABLE nome_da_tabela (
    id              UUID PRIMARY KEY,
    -- colunas de domínio aqui --
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Notas:
- `id` em inglês — convenção técnica.
- `UUID` (não `BIGSERIAL`) — alinha com o `string id` do `.proto` que carrega UUID. Geração na aplicação ou via `gen_random_uuid()` no Postgres.
- `created_at` e `updated_at` em inglês — convenção técnica.
- `TIMESTAMPTZ` (não `TIMESTAMP`) — o `pgx` lida melhor e força ciência de timezone.

`updated_at` deve ser atualizado por trigger ou explicitamente em cada `UPDATE` da aplicação. Padrão da equipe: explicitamente na query, mais simples de auditar.

## Tipos de coluna

| Tipo no `.proto`                  | Tipo no SQL                           | Notas                                              |
|-----------------------------------|---------------------------------------|----------------------------------------------------|
| `string` (UUID)                   | `UUID`                                | Aplique também em FKs para outras tabelas internas |
| `string` (CPF/CNPJ/MSISDN/ICCID)  | `VARCHAR(N)` apropriado               | Tamanho fixo: CPF=11, CNPJ=14, MSISDN=13, ICCID=20 |
| `string` (texto livre)            | `TEXT`                                | Não usar `VARCHAR(255)` por hábito — sem benefício |
| `string` (email, URL)             | `TEXT`                                | Validação de formato fica na aplicação             |
| `int32` / `int64`                 | `INTEGER` / `BIGINT`                  |                                                    |
| `bool`                            | `BOOLEAN`                             |                                                    |
| `google.protobuf.Timestamp`       | `TIMESTAMPTZ`                         | Sempre with timezone                               |
| `enum` (qualquer)                 | `SMALLINT NOT NULL`                   | Veja seção Enums                                   |
| `string` (decimal de dinheiro)    | `NUMERIC(15,2)`                       | Para casos especiais com mais casas, ver abaixo    |
| `bytes`                           | `BYTEA`                               | Raro no domínio                                    |
| `repeated <tipo>`                 | Tabela filha com FK                   | Não usar `ARRAY` exceto casos muito específicos    |

### Sobre `NUMERIC` para dinheiro

- Padrão: `NUMERIC(15,2)` — até 13 dígitos antes do decimal, 2 casas decimais. Cobre até ~10 trilhões.
- Para frações de centavo (rateio de consumo, cálculos intermediários): `NUMERIC(20,6)`.
- **Não usar `REAL` ou `DOUBLE PRECISION`** para dinheiro — precisão de float corrompe valores.

### Por que `SMALLINT` para enums (e não `CREATE TYPE ... AS ENUM`)

- `sqlc` com enum nativo do Postgres gera tipos string `*` — verboso e propenso a typos.
- `SMALLINT` casa diretamente com o número do enum no `.proto` (1, 2, 3, ...) e o código Go pode fazer cast seguro.
- Migração de enum é traumática no Postgres (`ALTER TYPE`); `SMALLINT` é trivial (basta documentar o novo valor).

Sempre adicione `CHECK` constraint listando os valores válidos para travar em runtime:

```sql
situacao SMALLINT NOT NULL CHECK (situacao BETWEEN 0 AND 5),
```

O comentário do schema deve ter o mapa de valores:

```sql
-- situacao SMALLINT:
-- 0 = SITUACAO_LINHA_NAO_ESPECIFICADA (não use, valor inválido em registros)
-- 1 = SITUACAO_LINHA_ATIVA
-- 2 = SITUACAO_LINHA_SUSPENSA
-- 3 = SITUACAO_LINHA_BLOQUEADA
-- 4 = SITUACAO_LINHA_CANCELADA
-- 5 = SITUACAO_LINHA_PORTABILIDADE_EM_ANDAMENTO
```

## Foreign Keys

**Dentro do mesmo serviço**: usar FK explícita.

**Entre serviços diferentes**: NÃO usar FK. Cada serviço é dono dos próprios dados; a referência é lógica. Exemplo:

- Serviço `assinantes` tem tabela `assinantes`.
- Serviço `linhas` tem tabela `linhas` com coluna `assinante_id UUID NOT NULL` mas **sem** `REFERENCES assinantes(id)` (porque `assinantes` está em outro banco/serviço).

Para FKs dentro do serviço:

```sql
CREATE TABLE linhas (
    id              UUID PRIMARY KEY,
    msisdn          VARCHAR(13) NOT NULL UNIQUE,
    -- ...
    plano_codigo    VARCHAR(20) NOT NULL,

    CONSTRAINT fk_linhas_plano
        FOREIGN KEY (plano_codigo) REFERENCES planos(codigo)
        ON DELETE RESTRICT
);
```

- `ON DELETE RESTRICT` é o default seguro. Use `CASCADE` só quando os dados filhos genuinamente não existem sem o pai.
- Constraints nomeadas (`fk_<tabela>_<ref>`) facilitam logs de erro.

## Índices

Crie índice em:

- **Toda FK**: porque queries de listagem ("dame todas as linhas do assinante") são comuns.
- **Toda coluna usada em busca direta**: CPF, MSISDN, email, código de barras de boleto.
- **Toda coluna usada em filtro frequente combinado**: situacao em conjunto com data, etc.

Padrão de nomenclatura: `idx_<tabela>_<coluna>` (ou `_<coluna1>_<coluna2>` para composto).

```sql
CREATE INDEX idx_linhas_assinante_id ON linhas(assinante_id);
CREATE INDEX idx_linhas_situacao ON linhas(situacao);
CREATE UNIQUE INDEX idx_assinantes_cpf_ou_cnpj ON assinantes(cpf_ou_cnpj);
```

Para unicidade lógica de negócio, prefira `UNIQUE` no `CREATE TABLE` ou `CREATE UNIQUE INDEX` — não confiar só em código de aplicação.

**Não crie índice em tudo.** Cada índice custa escrita e armazenamento. Comece com FKs + colunas de busca explícitas; adicione mais conforme uso real.

## Exemplo completo: `schema.sql` para serviço de Assinantes

```sql
-- =====================================================================
-- Serviço: Assinantes
-- Dono dos dados de assinante (pessoa física ou jurídica com contrato).
-- =====================================================================

-- Tabela de assinantes
--
-- tipo_pessoa SMALLINT:
-- 0 = TIPO_PESSOA_NAO_ESPECIFICADO (inválido em registros)
-- 1 = TIPO_PESSOA_FISICA (CPF)
-- 2 = TIPO_PESSOA_JURIDICA (CNPJ)
--
-- situacao_cadastral SMALLINT:
-- 0 = NAO_ESPECIFICADA (inválido)
-- 1 = ATIVA
-- 2 = INATIVA
-- 3 = BLOQUEADA
-- 4 = EM_ANALISE
CREATE TABLE assinantes (
    id                  UUID PRIMARY KEY,
    cpf_ou_cnpj         VARCHAR(14) NOT NULL,
    tipo_pessoa         SMALLINT NOT NULL CHECK (tipo_pessoa BETWEEN 1 AND 2),
    nome                TEXT NOT NULL,
    email               TEXT,
    telefone_contato    VARCHAR(13),
    data_cadastro       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    situacao_cadastral  SMALLINT NOT NULL CHECK (situacao_cadastral BETWEEN 1 AND 4),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CPF/CNPJ é único na base
CREATE UNIQUE INDEX idx_assinantes_cpf_ou_cnpj
    ON assinantes(cpf_ou_cnpj);

-- Busca por email é comum (esqueci minha senha, segunda via)
CREATE INDEX idx_assinantes_email
    ON assinantes(email) WHERE email IS NOT NULL;

-- Filtros operacionais por situação
CREATE INDEX idx_assinantes_situacao_cadastral
    ON assinantes(situacao_cadastral);


-- Tabela de idempotência para cadastros (evita duplo cadastro em retry)
CREATE TABLE assinantes_idempotency (
    idempotency_key     TEXT PRIMARY KEY,
    assinante_id        UUID NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_idempotency_assinante
        FOREIGN KEY (assinante_id) REFERENCES assinantes(id)
        ON DELETE CASCADE
);

-- Permite limpeza periódica de chaves antigas
CREATE INDEX idx_assinantes_idempotency_created_at
    ON assinantes_idempotency(created_at);
```

## Queries do `sqlc`

### Estrutura de cada query

```sql
-- name: NomeDaQuery :anotacao
SELECT ... ou INSERT ... ou UPDATE ... ou DELETE ...
```

Anotações `sqlc`:
- `:one` — retorna exatamente 1 linha. Erro `pgx.ErrNoRows` se não acha.
- `:many` — retorna 0 ou mais linhas (slice, vazio se nada).
- `:exec` — executa, não retorna linhas.
- `:execrows` — executa e retorna número de linhas afetadas.

### Naming das queries

**Casar com o RPC consumidor**. Se o RPC do `.proto` é `BuscarAssinantePorMSISDN`, a query é `BuscarAssinantePorMSISDN`. Isso é o que mantém a Linguagem Ubíqua viva.

Quando uma query é chamada por **múltiplos** RPCs ou serve operações internas (não exposta como RPC), o nome reflete o que ela faz no domínio: `MarcarLinhaComoSuspensa`, `IncrementarContadorTentativas`.

### Exemplo: `queries/assinantes.sql`

```sql
-- name: BuscarAssinantePorID :one
-- Consulta direta por ID interno. Usada pelo RPC BuscarAssinantePorID.
SELECT *
FROM assinantes
WHERE id = $1;


-- name: BuscarAssinantePorCPF :one
-- Consulta por CPF/CNPJ. Usada pelo RPC BuscarAssinantePorCPF e por fluxos
-- internos de validação de duplicidade.
SELECT *
FROM assinantes
WHERE cpf_ou_cnpj = $1;


-- name: ListarAssinantesPorSituacao :many
-- Listagem paginada para operações administrativas (relatórios de
-- inadimplência, análise de cadastros em revisão).
-- Ordenado por data_cadastro DESC. Cursor: data_cadastro + id como tiebreaker.
SELECT *
FROM assinantes
WHERE situacao_cadastral = $1
  AND (data_cadastro, id) < ($2, $3)
ORDER BY data_cadastro DESC, id DESC
LIMIT $4;


-- name: CadastrarAssinante :one
-- Insere novo assinante. data_cadastro e situacao_cadastral inicial (EM_ANALISE)
-- são responsabilidade da aplicação setar. Retorna o registro inserido.
INSERT INTO assinantes (
    id,
    cpf_ou_cnpj,
    tipo_pessoa,
    nome,
    email,
    telefone_contato,
    data_cadastro,
    situacao_cadastral
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8
)
RETURNING *;


-- name: AtualizarSituacaoCadastral :one
-- Atualiza apenas a situação cadastral. updated_at é setado aqui.
UPDATE assinantes
SET situacao_cadastral = $2,
    updated_at = NOW()
WHERE id = $1
RETURNING *;


-- name: AtualizarDadosContato :one
-- Atualiza email e/ou telefone de contato. Email vazio remove.
UPDATE assinantes
SET email = NULLIF($2, ''),
    telefone_contato = NULLIF($3, ''),
    updated_at = NOW()
WHERE id = $1
RETURNING *;


-- name: RegistrarIdempotencia :exec
-- Registra chave de idempotência associada a um cadastro recém-criado.
-- A aplicação consulta esta tabela antes de tentar cadastrar para detectar
-- retries.
INSERT INTO assinantes_idempotency (idempotency_key, assinante_id)
VALUES ($1, $2)
ON CONFLICT (idempotency_key) DO NOTHING;


-- name: BuscarAssinanteIdempotente :one
-- Consulta uma chave de idempotência. Se existe, retorna o assinante já
-- criado por um cadastro anterior.
SELECT a.*
FROM assinantes a
JOIN assinantes_idempotency i ON i.assinante_id = a.id
WHERE i.idempotency_key = $1;
```

### Paginação cursor-based

O exemplo `ListarAssinantesPorSituacao` usa o padrão `(data_cadastro, id) < ($cursor_data, $cursor_id)` como cursor composto. Vantagens:

- Estável se novos registros são inseridos durante a paginação.
- Funciona com `LIMIT` sem `OFFSET` (que fica lento em listas grandes).
- O cliente passa `data_cadastro + id` do último item da página anterior.

Para o `.proto`, o `page_token` é uma string base64 codificando essa tupla. A serialização/desserialização fica com a implementação Go.

### Coisas que não fazemos no SQL

- **Não usar Stored Procedures** ou Functions para regra de negócio. Regra de negócio fica em Go. SQL só lida com dados.
- **Não usar triggers** para regra de negócio. Trigger para `updated_at` é aceitável mas a equipe prefere fazer explicitamente nas queries (mais simples de auditar).
- **Não usar `JSON`/`JSONB`** para dados que têm estrutura conhecida. Modele com colunas próprias. Use `JSONB` só quando o schema é genuinamente flexível (metadados de evento, payload de webhook).
- **Não usar `SELECT *` em produção** sem motivo — em `sqlc`, `SELECT *` está OK porque o tipo é gerado e congelado no build, mas para queries específicas que retornam subset, liste as colunas.

## Padrão para tabelas de evento / auditoria

Quando faz sentido registrar histórico (mudanças de situação, tentativas de operação), use tabela própria:

```sql
CREATE TABLE historico_situacao_linha (
    id              UUID PRIMARY KEY,
    linha_id        UUID NOT NULL,
    situacao_antes  SMALLINT NOT NULL,
    situacao_depois SMALLINT NOT NULL,
    motivo          SMALLINT,        -- ref a MotivoSuspensao / MotivoBloqueio
    observacao      TEXT,
    operado_por     TEXT,            -- agente humano ID, ou "agente-ia:nome", ou "sistema"
    operado_em      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_historico_linha
        FOREIGN KEY (linha_id) REFERENCES linhas(id)
        ON DELETE CASCADE
);

CREATE INDEX idx_historico_linha_id_operado_em
    ON historico_situacao_linha(linha_id, operado_em DESC);
```

A inserção no histórico é responsabilidade da aplicação (na mesma transação da mudança da linha), não de trigger. Isso mantém o controle explícito e auditável.

## Migrations

Cada mudança de schema é uma migration nova, nunca alteração da migration anterior. Padrão de nome: `NNNN_descricao_curta.sql`.

```
sql/schema/
  0001_assinantes_inicial.sql
  0002_adicionar_telefone_contato.sql
  0003_indice_situacao_cadastral.sql
```

A ferramenta de migration (golang-migrate, goose, ou similar) é escolha da equipe de implementação. A skill produz o SQL; a aplicação organiza.

Quando o `.proto` adiciona um campo novo opcional, a migration correspondente é `ADD COLUMN ... NULL` (sem default obrigatório). Backfill posterior, se necessário, é outra migration.
