# AGENTS.md — Contexto do serviço

> Este arquivo é onboarding para qualquer contribuinte novo — humano ou ferramenta de IA.
> Preencha **na criação do serviço** e atualize quando algo do que está aqui mudar.
> Para guidelines do time como um todo (idioma, arquitetura, stack), ver o repositório `guidelines/`.

## Visão geral

**Nome:** `<nome-do-serviço>`
**Responsabilidade:** uma frase. O que esse serviço faz que justifica existir.
**Donos:** time/squad responsável. Quem chamar quando algo quebrar.
**Linguagem ubíqua específica:** termos do domínio deste serviço que talvez não apareçam em outros (ex.: "ciclo de cobrança", "janela de portabilidade").

## Como rodar / testar / construir

Comandos básicos (todos via Makefile):

```bash
make                    # lista alvos disponíveis
make generate           # buf generate + sqlc generate
make test               # go test -race -count=1 ./...
make lint               # golangci-lint run
make run                # roda localmente (precisa de DATABASE_URL setada)
make podman-build       # imagem distroless para produção
make podman-build-alpine # imagem alpine para debug emergencial
```

Variáveis de ambiente obrigatórias:

| Var | Descrição | Exemplo |
|---|---|---|
| `DATABASE_URL` | Conexão Postgres | `postgres://user:pass@localhost:5432/db?sslmode=disable` |
| `GRPC_ADDR` | Endereço gRPC | `:50051` |
| `LOG_LEVEL` | Nível de log | `info` |

Opcional/avançado: ver `internal/config/config.go`.

## Contratos relevantes

- **gRPC API:** `api/proto/v1/<feature>.proto` — contrato exposto para outros serviços.
- **Schema do banco:** `sql/schema/schema.sql` — fonte de verdade do que o serviço persiste.
- **Queries:** `sql/queries/*.sql` — formato `sqlc`. Nomes em português refletem operações de domínio.
- **Submodule de protos compartilhados:** `external/proto/` (sparse-checkout das pastas que importamos).
- **Eventos publicados/consumidos:** (se houver) listar tópicos NATS/Kafka e seu schema.

## Integrações externas

Listar serviços externos com os quais este serviço fala (e onde fica o wrapper ACL):

| Sistema | Wrapper | O que usamos | Observações |
|---|---|---|---|
| Receita Federal | `external/receita_federal/` | consulta CPF | rate limit: 10 req/s |
| `assinante-svc` | `external/assinante/` | buscar dados de assinante | tem cache local de 5 min |
| ... | ... | ... | ... |

## Decisões arquiteturais (ADRs)

Decisões não óbvias estão em `docs/adr/`. Antes de propor mudança arquitetural significativa, leia os ADRs relevantes — possivelmente o assunto já foi debatido.

Lista resumida:
- `0001-<título>` — uma linha sobre o que decide
- `0002-<título>` — ...

## Convenções específicas deste serviço

Aqui entram convenções **que diferem ou estendem** os guidelines globais do time. Se está nos guidelines, não repetir aqui. Exemplos do que entra:

- "Toda operação que muda situação de linha publica evento em `linha.situacao.alterada` — handler deve garantir isso dentro da transação."
- "Datas de ciclo de cobrança ficam em `America/Sao_Paulo`, nunca em UTC."
- "Identificadores de fatura seguem padrão `FAT-<ano>-<sequencial>`, gerado por `internal/fatura/numero.go`."

## Gotchas conhecidos

Coisas que mordem quem é novo no serviço:

- "O pool de conexão tem `MaxConns=25` porque o banco gerenciado tem limite de 100 e somos 4 réplicas."
- "Migration `000017_renomear_situacao.up.sql` deve rodar antes do deploy do `v2.0` — coordenar com o time de DB."
- "Health check `/healthz` é o que o K8s usa; `/readyz` checa banco também."

## Estrutura

```
cmd/server/         # main: wiring e bootstrap apenas
api/proto/v1/       # contratos gRPC publicados
external/           # ACL para serviços externos (incluindo submodule de protos)
gen/                # código gerado (não commitado — regerado no build)
internal/           # código privado
  config/           # carregamento de configuração
  database/         # pool de conexão
  logger/           # configuração de log
  observability/    # keys de log, métricas, spans (contratos operacionais)
  <feature>/        # um pacote por feature de domínio
sql/                # fonte de verdade para o sqlc
  queries/          # queries .sql
  schema/           # schema do banco
vendor/             # dependências de terceiros (commitado)
docs/adr/           # Architecture Decision Records
```

## Para humanos novos no time

1. Leia `guidelines/README.md` (raiz dos guidelines globais) — uma vez na carreira.
2. Leia este arquivo do começo ao fim.
3. Folheie os ADRs.
4. Rode `make generate && make test` localmente para confirmar que o ambiente funciona.
5. Pareie com alguém do squad nas primeiras 3 PRs.

## Para ferramentas de IA

- Sempre seguir a ordem **spec-first**: contrato (proto/SQL) → testes table-driven → implementação. Ver `guidelines/skills/golang-development/SKILL.md` seção "Workflow spec-first".
- Antes de propor refactor arquitetural, ler ADRs relevantes em `docs/adr/`.
- Vocabulário do domínio em português, técnico em inglês — consistente em todas as camadas (proto, Go, SQL, logs). Ver `guidelines/convencao_de_idioma.md`.
- Não introduzir dependência nova sem justificativa explícita. Preferir stdlib (`slices`, `maps`, `cmp`, `log/slog`, `errors.Join`).
- `golangci-lint run` deve passar sem warning antes de devolver código.
