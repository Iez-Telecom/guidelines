---
name: golang-development
description: Use this skill whenever the user is writing, reviewing, debugging, refactoring, or designing Go (Golang) code. Triggers include any mention of `.go` files, `go.mod`, `go.sum`, `go test`, `go build`, `go run`, goroutines, channels, contexts, interfaces, generics, the standard library (`net/http`, `encoding/json`, `database/sql`, `io`, `context`, `errors`), `sqlc`, `pgx`, `protobuf`, `buf`, gRPC, NATS JetStream, Containerfile, Envoy, cobra, viper, or requests to "make this idiomatic Go", build a Go service, CLI, microservice, or worker. Also use when the user shares Go code that compiles but is non-idiomatic, has races, ignores errors, leaks goroutines, or misuses contexts. Pushy use: even if the user just says "I have a small Go question", consult this skill — Go has many subtle idioms (error wrapping, context propagation, slice aliasing, nil interface vs nil pointer, defer in loops) that are easy to get wrong without a checklist.
---

# Go (Golang) Development

Skill para escrever **código Go idiomático e pronto para produção**, seguindo a stack e as convenções específicas do time.

## Regras inegociáveis

### Stack obrigatória

| Componente | Tecnologia | Observação |
|---|---|---|
| Banco de dados | **PostgreSQL** via `sqlc` + `github.com/jackc/pgx/v5` | NUNCA usar ORMs (GORM, ent). `sqlc` gera código type-safe a partir de SQL. |
| Comunicação entre serviços | **gRPC** + **Protocol Buffers** | Usar `buf` para gerar código. REST apenas para APIs públicas externas. |
| Build e code-gen | **Makefile** com `buf generate`, `sqlc generate`, `podman build` | Sem scripts ad-hoc. Arquivo canônico em `../../exemplos/Makefile`. |
| Containerização | **Containerfile** (não "Dockerfile") otimizado para **Kubernetes** | Multi-stage. Dois runtimes via `--target`: **distroless** (default, produção) e **alpine** (debug, tag sufixo `-alpine`). Arquivo canônico em `../../exemplos/Containerfile`. |
| Dependências | **`vendor/` commitado**, `/gen/` regerado no build | `go build -mod=vendor` no container; geração de protos roda dentro do builder. |
| Módulos privados | `GOPRIVATE=github.com/Iez-Telecom/*` + `insteadOf` SSH no `~/.gitconfig` | Sem isso, `go mod download` falha em CI. Detalhes em `../../guidelines_golang.md`. |
| Plataforma alvo | **Linux x86_64** | `CGO_ENABLED=0 GOOS=linux GOARCH=amd64`. |
| Logging | `log/slog` (stdlib) | Structured logging com atributos contextuais (trace ID, user ID). |
| Versão no binário | `-ldflags "-X 'main.clientVersion=..."` injetado pelo Makefile | Visível via flag `--version` ou `go version -m`. |
| Proxy / LB | **Envoy** quando gRPC load balancing ou gRPC-Web for necessário | |

### Idioma e documentação

- **Vocabulário do domínio** (tipos de negócio, funções de regra, nomes de pacotes de feature, campos de domain types, nomes de tabelas/colunas de domínio, RPCs e mensagens protobuf, nomes de queries sqlc): **português brasileiro**.
- **Vocabulário técnico** (infraestrutura, plataforma e idiomas de Go): **inglês** (`handler`, `store`, `client`, `server`, `database`, `config`, `logger`, `context`, `error`, `pool`, `transaction`).
- A separação não é "tudo inglês" — é cada conceito no seu idioma natural. Ver `references/style.md` para exemplos e `references/project-layout.md` para a convenção aplicada ao layout.
- Doc comments de identificadores exportados seguem formato Go (`// NomeExportado faz X`). Identificadores de domínio ficam em português, infraestrutura em inglês.

### Dependências externas

- **Evitar** adicionar novas dependências Go externas a menos que absolutamente necessário.
- Quando uma dependência nova for introduzida, a justificativa **deve** ser declarada explicitamente no plano gerado.
- Preferir sempre a stdlib.

## Filosofia central

Go recompensa código **simples, explícito, legível**. Antes de escrever ou aceitar qualquer código Go, internalizar:

1. **Erros são valores.** Retornar, wrappear com `fmt.Errorf("falha ao processar item %s: %w", itemID, err)`, nunca ignorar com `_`. Sentinelas via `errors.Is`, tipados via `errors.As`.
2. **`context.Context` é o primeiro parâmetro** de qualquer função que faz I/O, bloqueia, ou precisa de cancelamento. Respeitar `ctx.Done()` e timeouts. Nunca armazenar em structs. Nunca passar `nil` — usar `context.TODO()`.
3. **Aceitar interfaces, retornar structs concretas.** Definir interfaces no **consumidor**, não no produtor. Mantê-las pequenas (1–2 métodos).
4. **Goroutines precisam de um dono.** Cada `go func()` deve ter resposta clara: quem espera? como cancela? para onde vão os erros? Usar `errgroup.Group` ou `sync.WaitGroup`.
5. **Channels para orquestrar fluxo de dados e transferir ownership. Mutex para proteger estado em memória.** Não usar channel para tudo.
6. **Zero values devem ser úteis.** Projetar structs cujo valor zero funciona.
7. **Sem estado mutável no nível de pacote.** Sem `init()` fazendo trabalho real. Injetar dependências via construtores (`NewService(repo Repository)`).
8. **`golangci-lint` não é opcional.** Wrapa `gofmt`, `goimports`, `go vet`, `staticcheck` e ~15 outros checks. Config canônica em `../../exemplos/.golangci.yml`.
9. **Sem `panic` em lógica de negócio ou handlers HTTP/gRPC.** `panic` só para falhas críticas de inicialização (`regexp.MustCompile`).

## Workflow spec-first

Sempre que a tarefa envolve uma capacidade nova (RPC, endpoint, query, evento, integração externa), seguir esta ordem:

```
1. .proto              (contrato gRPC: tipos de domínio e operações)
   ↓
2. sql/queries + schema (contrato com o banco: o que persistir, como buscar)
   ↓
3. testes table-driven  (spec executável do comportamento esperado)
   ↓
4. handler + store      (implementação que satisfaz proto + queries + testes)
   ↓
5. integração end-to-end (confirmar que as peças se encaixam)
```

A ordem importa por três razões:

- **O contrato resiste mais que a implementação.** Implementação é regerada; contrato é evolução cuidadosa (`buf breaking`). Escrever o contrato primeiro força clareza sobre o que o sistema *é*, antes de decidir como ele *faz*.
- **Testes table-driven antes do código são spec, não verificação.** Quando você escreve `name: "linha já ativa retorna erro"` antes de implementar o handler, está formalizando uma regra de negócio. Depois você implementa para satisfazer a tabela.
- **A IA é boa em preencher implementação quando o contrato e os testes existem.** É ruim em adivinhar contrato a partir de "implemente algo que cadastra cliente".

### Quando pular ou inverter a ordem

- **Bug fix em código existente**: começar pelos testes que reproduzem o bug, depois corrigir. Sem mexer no contrato a menos que o bug seja no contrato.
- **Refactor sem mudança de comportamento**: testes existentes são a spec; rodar antes/depois.
- **Spike exploratório**: pode pular tudo isso. Mas spike vira código de produção só depois de retornar à ordem canônica.

### O que escrever em cada etapa (resumo)

| Etapa | Artefato | Pergunta que responde |
|---|---|---|
| 1 | `api/proto/v1/<feature>.proto` | "Que operações o serviço expõe e que tipos de domínio elas movem?" |
| 2 | `sql/schema/*.sql` + `sql/queries/*.sql` | "O que precisa estar persistido e como será lido?" |
| 3 | `internal/<feature>/<feature>_test.go` | "Que comportamento o negócio espera, incluindo casos de erro?" |
| 4 | `internal/<feature>/{handler.go,<feature>.go,store.go}` | "Como satisfazer 1+2+3?" |
| 5 | testes de integração + `make podman-build` | "As peças se compõem? O container roda?" |

### Artefatos de contexto durável

Para decisões que não cabem no contrato nem nos testes, usar ADRs em `docs/adr/` (template em `../../exemplos/docs/adr/`). Para contexto do serviço como um todo (visão geral, gotchas, convenções específicas), usar `AGENTS.md` na raiz (template em `../../exemplos/AGENTS.md`). Esses dois artefatos fazem o serviço ser navegável para qualquer contribuinte novo — humano ou IA.

## Workflow para qualquer tarefa Go

### 1. Identificar o tipo de tarefa e carregar a referência certa

| Tarefa | Ler |
|---|---|
| Novo serviço gRPC / HTTP | `references/http-services.md` |
| Concorrência, goroutines, channels, races | `references/concurrency.md` |
| Error handling, wrapping, erros customizados | `references/errors.md` |
| Layout de projeto, módulos, dependências | `references/project-layout.md` |
| Testes, benchmarks, fuzzing, table-driven | `references/testing.md` |
| Performance / profiling / alocações | `references/performance.md` |
| CLI (cobra, flag) | `references/cli.md` |
| Banco de dados (sqlc, pgx, transações) | `references/databases.md` |
| gRPC, protobuf, buf | `references/grpc.md` |
| Containerização e deploy | `references/containers.md` |
| Observabilidade (logs, metrics, traces como contrato) | `references/observability.md` |
| Review de código existente | `references/code-review-checklist.md` |
| **Operacional**: setup de máquina, módulos privados, submodules, Makefile, Containerfile, ldflags, deploy | `../../guidelines_golang.md` + arquivos em `../../exemplos/` |
| **Arquitetura**: estrutura `cmd/internal/external`, ACL, padrões de comunicação | `../../arquitetura_backend.md` |
| **Idioma**: o que vai em PT, o que vai em EN, exemplos | `../../convencao_de_idioma.md` |

Ler **apenas** a(s) referência(s) relevantes. Não ler todas.

Para questões operacionais (como configurar `GOPRIVATE`, como adicionar submodule de protos, qual é o Makefile padrão, qual é o Containerfile padrão com distroless e alpine), o ponto de verdade é `../../guidelines_golang.md` e os arquivos prontos em `../../exemplos/` (`Makefile`, `Containerfile`, `buf.yaml`, `buf.gen.yaml`). As referências locais cobrem o **como escrever código Go**; o documento raiz cobre o **como construir, empacotar e operar** os serviços.

### 2. Checklist pré-voo (sempre)

Antes de escrever ou retornar código, verificar mentalmente:

- [ ] Todo erro é checado e wrapped com contexto (`fmt.Errorf("operação: %w", err)`)
- [ ] Toda função que faz I/O recebe `ctx context.Context` como primeiro parâmetro
- [ ] Toda goroutine tem dono definido, lifetime, e caminho de erro
- [ ] Sem `defer` dentro de `for` loop ilimitado (vazamento de recurso — extrair função)
- [ ] Sem `interface{}` / `any` a menos que realmente necessário — preferir generics.
- [ ] Identificadores públicos têm doc comments começando com o nome do identificador
- [ ] Sem naked returns em funções longas
- [ ] `strings.Builder` ao invés de `+=` em loops
- [ ] Slices e maps pré-alocados quando o tamanho é conhecido (`make([]T, 0, n)`)
- [ ] Receiver types consistentes (todos pointer ou todos value para um dado tipo)
- [ ] Logging com `log/slog` e atributos contextuais (trace ID, user ID, etc.)
- [ ] Sem `panic` em handlers ou lógica de negócio
- [ ] Vocabulário de domínio em português em todas as camadas (tipos, funções de regra, campos, RPCs, queries, tabelas)
- [ ] Vocabulário técnico de infraestrutura em inglês (`handler`, `store`, `database`, `config`, `logger`, etc.)
- [ ] Pacotes de feature nomeados pelo conceito de domínio (sem `utils`, `helpers`, `common`)
- [ ] Nenhuma dependência nova sem justificativa explícita

### 3. Escrever o código

Seguir as convenções em `references/style.md` — carregar no primeiro task Go de qualquer conversa. É curto.

### 4. Fornecer artefatos executáveis quando relevante

Se a tarefa envolve mais de ~50 linhas ou múltiplos arquivos, scaffoldar um exemplo mínimo executável com `go.mod` e mostrar como rodar (`go run .` ou `go test ./...`). O script `scripts/init_module.sh` cria um starter limpo.

### 5. Mostrar comandos de verificação

Terminar toda resposta que produz código com os comandos que o usuário deve rodar (alvos do Makefile padrão em `../../exemplos/Makefile`):

```bash
make generate            # buf generate + sqlc generate (quando aplicável)
make lint                # golangci-lint run (gofmt + vet + staticcheck + ~15 outros)
make test                # go test -race -count=1 ./...
make build               # binário local com ldflags de versão
make podman-build        # imagem distroless (produção)
make podman-build-alpine # imagem alpine (debug, tag -alpine — só quando necessário)
```

## Review de código existente

1. Carregar `references/code-review-checklist.md` e percorrer explicitamente.
2. Agrupar achados por severidade: **Bug** (race, leak, erro ignorado, context errado) → **Idioma** (não-idiomático mas correto) → **Estilo** (naming, formatação).
3. Mostrar código corrigido, não apenas descrições.
4. Sempre sugerir rodar com `-race` se concorrência está envolvida.

## Armadilhas comuns para procurar ativamente

- **Nil interface ≠ nil pointer.** Retornar `(*MyError)(nil)` como `error` faz `err != nil` ser true. Sempre retornar `nil` puro.
- **Captura de variável de loop** em goroutines (pre-1.22) e em closures armazenadas entre iterações.
- **Slice aliasing**: `append` pode ou não alocar; passar slices para funções que fazem `append` é armadilha. Usar `slices.Clone`.
- **Maps não são seguros para escrita concorrente.** `sync.RWMutex` + map puro na maioria dos casos.
- **`time.After` em `select` dentro de loop vaza** até o timer disparar. Usar `time.NewTimer` com `Stop()`.
- **`http.Response.Body` deve ser fechado**, inclusive em respostas de erro, ou vaza conexões.
- **Context values são para dados request-scoped, não parâmetros opcionais.** Não enfiar dependências no `ctx`.

## Formato de output esperado

- Código em blocos ```go com o filename como comentário na linha 1: `// caminho/para/arquivo.go`
- Outputs multi-arquivo usam um bloco por arquivo
- Sempre incluir a declaração `package`
- Imports agrupados: stdlib, linha em branco, third-party, linha em branco, módulo local
- Nunca elidir código com `// ...` a menos que o usuário tenha pedido um snippet — mostrar funções completas
- Comentários inline e docs em português brasileiro para identificadores de domínio; padrão Go (e inglês idiomático) para infraestrutura

## Índice de referências

```
guidelines/                                    (raiz do repositório)
├── arquitetura_backend.md                     arquitetura de serviços (estrutura, ACL, comunicação)
├── guidelines_golang.md                       operacional: setup, módulos privados, Makefile, Containerfile
├── convencao_de_idioma.md                     domínio em PT, técnico em EN — exemplos completos
├── exemplos/
│   ├── Makefile                               canônico — copiar para serviços novos
│   ├── Containerfile                          canônico — distroless (default) + alpine (debug)
│   ├── buf.yaml                               canônico — STANDARD + exceções
│   ├── buf.gen.yaml                           canônico — plugins locais
│   ├── .golangci.yml                          canônico — linters habilitados + settings
│   ├── AGENTS.md                              template — contexto do serviço (onboarding humano/IA)
│   └── docs/adr/
│       ├── 0000-template.md                   template de ADR (Nygard format)
│       └── 0001-*.md                          ADR de exemplo
└── skills/golang-development/
    ├── SKILL.md                               (este arquivo)
    ├── references/
    │   ├── style.md                           idiomas, naming, formatação
    │   ├── errors.md                          wrapping, sentinel, typed errors, panics
    │   ├── concurrency.md                     goroutines, channels, sync, errgroup, races, synctest
    │   ├── http-services.md                   net/http, handlers, middleware, graceful shutdown
    │   ├── testing.md                         table-driven, synctest, property-based, fuzz, golden, examples
    │   ├── project-layout.md                  modules, internal/, cmd/, Makefile, buf, sqlc
    │   ├── performance.md                     profiling, escape analysis, alocações
    │   ├── cli.md                             cobra, flag, viper patterns
    │   ├── databases.md                       sqlc, pgx/v5, transações, migrations
    │   ├── grpc.md                            protobuf, buf, gRPC server/client, interceptors
    │   ├── containers.md                      Containerfile, distroless+alpine, K8s, Envoy
    │   ├── observability.md                   slog keys, OpenTelemetry, Prometheus como contrato
    │   └── code-review-checklist.md           revisão sistemática
    ├── scripts/
    │   └── init_module.sh                     scaffolda novo módulo Go
    └── assets/
        └── gitignore                          .gitignore padrão Go
```
