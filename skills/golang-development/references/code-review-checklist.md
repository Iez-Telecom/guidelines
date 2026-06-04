# Checklist de code review Go

Percorrer de cima para baixo em qualquer review não-trivial. Achados agrupados em **Bug** (deve corrigir), **Idioma** (deveria corrigir), **Estilo** (nit).

## Erros (Bug)

- [ ] Todo erro é checado. Buscar `_ =` e `_, err :=` seguido de nenhum uso de `err`.
- [ ] Erros que cruzam boundaries de pacote são wrapped com `%w` e mensagem de contexto.
- [ ] Sem comparação de string em mensagens de erro. Usa `errors.Is` / `errors.As`.
- [ ] Sem "log and return" do mesmo erro (um ou outro, não ambos).
- [ ] Tipos de erro customizados implementam `Error()` em **pointer** receivers e são retornados como ponteiros.
- [ ] Funções retornando `error` retornam `nil` puro no sucesso (não um typed nil pointer).
- [ ] `panic` não é usado para fluxo de controle. `recover` apenas em boundaries de processo (handlers).

## Concorrência (Bug)

- [ ] Toda `go func()` tem dono claro, caminho de cancelamento, e caminho de erro.
- [ ] Sem `go func() { ... }()` solto em handlers HTTP/gRPC sem `errgroup` / WaitGroup.
- [ ] Context é propagado; sem `context.Background()` profundo em call stacks.
- [ ] Variáveis de loop não são capturadas por goroutines/closures (ou Go 1.22+ confirmado).
- [ ] Sem `defer` em loops ilimitados.
- [ ] Sem `time.After` em selects de longa duração (usar `time.NewTimer`).
- [ ] Maps protegidos por mutex quando escritos de múltiplas goroutines.
- [ ] `http.Response.Body` sempre fechado (inclusive em non-2xx).
- [ ] Channels fechados pelo sender, nunca pelo receiver.
- [ ] `sync.Mutex` não copiado (struct passada por ponteiro).
- [ ] Código testado com `-race`.

## Context (Bug)

- [ ] `ctx context.Context` é o **primeiro** parâmetro de toda função que faz I/O ou bloqueia.
- [ ] Sem `context.Context` armazenado em campos de struct.
- [ ] Todo `context.WithCancel`/`WithTimeout`/`WithDeadline` seguido de `defer cancel()`.
- [ ] `context.Value` não usado para passar dependências (apenas dados request-scoped).

## Stack obrigatória (Bug)

- [ ] Banco de dados usa **sqlc** + **pgx/v5**. Sem GORM, ent, ou outro ORM.
- [ ] Queries SQL escritas em arquivos `.sql` para o sqlc, não como strings no código Go.
- [ ] Comunicação entre serviços usa **gRPC** + **protobuf**. REST apenas para APIs externas.
- [ ] Protobuf gerado via **buf** (plugins locais com versão pinada), não `protoc` diretamente.
- [ ] `buf.yaml` usa `lint: STANDARD` com as exceções padrão do time; `buf.gen.yaml` usa plugins `local:`.
- [ ] Logging usa **`log/slog`** com atributos estruturados. Sem `log.Println`, `fmt.Printf`, zap, zerolog.
- [ ] Container build usa **Containerfile** (não Dockerfile), com `podman`.
- [ ] Imagem default é **distroless** (`runtime-distroless`), rodando como **non-root**.
- [ ] Quando há variante de debug, ela é stage `runtime-alpine` com tag sufixo `-alpine`.
- [ ] **`vendor/` commitado**, `/gen/` ignorado pelo git e regerado dentro do builder.
- [ ] `BIN_NAME` derivado do módulo (`$(notdir $(MODULE))`); imagem e binário compartilham o nome do serviço.
- [ ] Build com **Makefile** padrão (alvos `generate`, `build`, `test`, `lint`, `vendor`, `podman-build*`).
- [ ] Plataforma alvo: **Linux x86_64** (`CGO_ENABLED=0 GOOS=linux GOARCH=amd64`).
- [ ] Binário compilado com `-trimpath` e `-ldflags "-s -w -X 'main.clientVersion=...'"`.

## Design de API (Idioma)

- [ ] Construtores retornam tipos concretos, não interfaces.
- [ ] Interfaces definidas no **consumidor**, não no produtor.
- [ ] Interfaces pequenas (1–2 métodos).
- [ ] Sem `interface{}` / `any` onde tipo concreto ou generic serviria.
- [ ] Receiver types consistentes para todos os métodos de um tipo.
- [ ] API pública tem doc comments começando com o nome do identificador.
- [ ] Sem identificador exportado que não precisa ser exportado.
- [ ] Dependências injetadas via construtor, não via estado global ou `init()`.

## Gerenciamento de recursos (Bug)

- [ ] Arquivos, conexões, response bodies todos com `defer Close()`.
- [ ] Goroutines de longa duração têm mecanismo de saída (ctx, channel close).
- [ ] Sem `sql.Rows` / `pgx.Rows` deixados abertos.
- [ ] Transações sempre terminam em `Commit` ou `Rollback` (`defer tx.Rollback(ctx)`).

## Testes (Idioma)

- [ ] Testes são table-driven com slices de structs anônimos.
- [ ] `t.Run` com nomes descritivos em português (a frase deve fazer sentido para alguém não-técnico).
- [ ] Helpers chamam `t.Helper()`.
- [ ] Sem estado global mutado por testes (ou isolado com `t.Setenv`/`t.TempDir`).
- [ ] Erros testados com `errors.Is` / `errors.As`, não comparação de string.
- [ ] Código concorrente testado com `-race` no CI **e** usa `testing/synctest` em vez de `time.Sleep`.
- [ ] Mocking feito com fakes manuais (interfaces), sem gomock/mockery/testify.
- [ ] Função pública com input não-trivial tem **`ExampleXxx`** (doc executável).
- [ ] Função com espaço de input grande (parser, validator) tem **fuzz** correspondente.
- [ ] Função com invariantes claros (round-trip, idempotência, monotonicidade) tem **property test** com `rapid`.
- [ ] Output complexo (proto serializado, template) testado com **golden file**; diff do `.golden` revisado no PR.

## Observabilidade (Bug)

- [ ] Toda chave de log estruturado vem de `internal/observability/keys.go`. Sem strings inline.
- [ ] Nova métrica segue convenção `<namespace>_<subsistema>_<nome>_<unidade>`.
- [ ] Labels de métrica têm cardinalidade finita pequena (sem `user_id`, `msisdn`, `request_id`).
- [ ] Span novo segue `<componente>.<operação>` e usa as mesmas chaves dos logs como atributos.
- [ ] `slog.Error` sempre acompanhado de `KeyError` com o erro original.
- [ ] Nada de `fmt.Printf` / `log.Println` em código de produção.
- [ ] `/healthz` não pinga banco; `/readyz` pinga.

## Dependências (Idioma)

- [ ] Nenhuma dependência externa nova sem justificativa explícita.
- [ ] Preferência pela stdlib em todos os casos.
- [ ] Sem frameworks HTTP pesados (Gin, Echo, Fiber). `net/http` ou `chi`.

## Performance (Idioma, quando relevante)

- [ ] Slices/maps pré-dimensionados quando tamanho é conhecido.
- [ ] `strings.Builder` ao invés de `+=` em loops.
- [ ] Sem conversões `[]byte(s)` / `string(b)` desnecessárias em hot paths.
- [ ] Sem regex compilado dentro de hot loop (`var re = regexp.MustCompile(...)` no nível de pacote).

## Estilo e idioma

- [ ] `gofmt` limpo.
- [ ] Imports agrupados (stdlib, third-party, local) — `goimports` limpo.
- [ ] Sem imports, vars ou parâmetros não usados.
- [ ] Acrônimos em maiúsculas (`userID`, `httpClient`, `MSISDN`, `CPF`).
- [ ] Nomes de pacotes lowercase, sem underscores.
- [ ] Early-return para erros, sem `if err == nil` aninhado.
- [ ] Funções com menos de ~50 linhas, indentação menor que 4 níveis.

### Convenção de idioma (ver `../../convencao_de_idioma.md`)

- [ ] **Vocabulário de domínio em português**: nomes de pacotes de feature, tipos do negócio, funções de regra, campos, RPCs, mensagens proto, tabelas, colunas, queries sqlc (`Assinante`, `calcularJurosMora`, `SuspenderLinhaPorInadimplencia`, `data_ativacao`).
- [ ] **Vocabulário técnico em inglês**: infraestrutura e plataforma (`handler`, `store`, `client`, `server`, `database`, `config`, `logger`, `context`, `error`, `request`, `response`).
- [ ] Consistência entre camadas: se o termo está em português no proto, está em português no Go, no schema do banco e nas queries. Não misturar `cliente` no Go com `subscriber_id` no banco.
- [ ] Doc comments começam com o nome do identificador (ex.: `// BuscarPorMSISDN retorna o assinante...`); idioma do doc segue o do identificador.
- [ ] Mensagens de erro voltadas ao negócio em português; erros técnicos genéricos podem ficar em inglês.
- [ ] Logs: chaves em inglês (convenção do ecossistema de observabilidade), valores podem ser do domínio.

## Verificação com ferramentas

```bash
make generate                     # buf generate + sqlc generate
make lint                         # golangci-lint run (gofmt + vet + staticcheck + ~15 outros)
make test                         # go test -race -count=1 ./...
buf lint                          # se há mudança em .proto
buf breaking --against ".git#branch=main"
```

Para fixes automáticos (formatação, imports):

```bash
make lint-fix                     # golangci-lint run --fix
```

Antes de aprovar PR que mexe em dependências ou Containerfile:

```bash
make vendor                       # confirma que vendor/ está consistente com go.mod
make podman-build                 # confirma que a imagem distroless constrói
make podman-build-alpine          # confirma que a variante alpine também
```
