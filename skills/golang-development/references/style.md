# Estilo e idiomas Go

O mínimo aceitável para qualquer código Go neste projeto. Aplicar sempre.

## Idioma (língua)

Regra fundamental do time: **domínio em português, técnico em inglês**.

### Vocabulário de domínio — português brasileiro

Tudo que vem do negócio fica em português: nomes de pacotes de feature, tipos de domínio, funções de regra de negócio, campos de structs de domínio, variáveis que representam conceitos do negócio, nomes de tabelas e colunas no banco (exceto convenções técnicas como `id`, `created_at`, `updated_at`), nomes de RPCs e mensagens protobuf, nomes de queries sqlc.

```go
// Pacote de feature — nome é o conceito de domínio
package cliente

// Tipo de domínio em português
type Assinante struct {
    ID            string
    CPF           string
    Nome          string
    DataAtivacao  time.Time
    SituacaoLinha SituacaoLinha
}

// Função de regra de negócio em português
func calcularJurosMora(parcela Parcela, dataReferencia time.Time) decimal.Decimal { ... }

// Erro de domínio em português
var ErrAssinanteNaoEncontrado = errors.New("assinante não encontrado")
```

### Vocabulário técnico — inglês

Infraestrutura e plataforma ficam em inglês: nomes de pacotes de infraestrutura (`database`, `config`, `logger`, `cache`), conceitos de engenharia (`handler`, `store`, `client`, `server`), padrões do Go (`Open`, `Close`, `Marshal`, `Unmarshal`, `context`, `error`, `request`, `response`).

```go
// Pacote de infraestrutura — nome técnico em inglês
package database

// Handler técnico em inglês; métodos de domínio em português
type Handler struct {
    store  Store
    logger *slog.Logger
}

// Implementa interface técnica (ServeHTTP é da stdlib)
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) { ... }
```

### Mistura na mesma assinatura

A regra se aplica dentro de uma mesma assinatura: nome do método segue o domínio, parâmetros técnicos ficam em inglês.

```go
// Método de domínio (português) recebe context e retorna error (técnicos, inglês)
func (s *AssinanteStore) BuscarPorCPF(ctx context.Context, cpf string) (*Assinante, error) { ... }
```

### Consistência entre camadas

Um conceito de domínio aparece em português em **todas** as camadas — proto, Go, banco, queries. Inconsistência (`cliente` no Go mas `subscriber_id` no banco) destrói o benefício da Linguagem Ubíqua.

### Doc comments

Identificadores de domínio exportados recebem doc comment com o nome em português:

```go
// BuscarPorMSISDN retorna o assinante associado ao número informado.
// Retorna ErrAssinanteNaoEncontrado se não existir registro.
func (s *AssinanteStore) BuscarPorMSISDN(ctx context.Context, msisdn string) (*Assinante, error) { ... }
```

Identificadores técnicos seguem o padrão Go com o nome do identificador:

```go
// NewPool cria um pool de conexões configurado para produção.
func NewPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) { ... }
```

Comentários de pacote vivem em `doc.go`:
```go
// Package cliente contém os tipos de domínio e a lógica de negócio de clientes.
package cliente
```

## Naming

- **Pacotes de feature**: lowercase, palavra única, nome do conceito de domínio em português. `cliente`, `contrato`, `cobranca`. Nunca `util`, `common`, `helpers`, `models` — viram gavetas de bagunça.
- **Pacotes de infraestrutura**: lowercase, nome técnico em inglês. `database`, `config`, `logger`, `cache`.
- **Arquivos**: `snake_case.go`. Testes em `*_test.go`.
- **Identificadores de domínio**: `MixedCaps` (exportado) ou `mixedCaps` (não-exportado) em português. `Assinante`, `calcularJurosMora`, `SituacaoLinha`.
- **Identificadores técnicos**: `MixedCaps`/`mixedCaps` em inglês. `Handler`, `openPool`, `parseConfig`.
- Acrônimos ficam em maiúsculas: `CPF`, `CNPJ`, `MSISDN`, `userID`, `httpServer`.
- **Receivers**: abreviação de 1–2 letras do tipo. `func (s *AssinanteStore) ...`, não `func (this *AssinanteStore)`.
- **Interfaces**: manter **1–2 métodos**. Interfaces de domínio ficam em português (`AssinanteStore`); interfaces técnicas em inglês (`Reader`, `Closer`).
- **Getters de domínio**: sem prefixo. `assinante.Nome()`, não `assinante.GetNome()`. Em inglês técnico: `server.Port()`.
- **Erros de domínio**: variáveis `ErrXxx` em português (`ErrAssinanteNaoEncontrado`). Erros técnicos em inglês (`ErrNotFound`).
- **RPCs protobuf**: operações de domínio em português. `BuscarAssinante`, `CadastrarLinha`, `SuspenderPorInadimplencia`. Nunca `GetUser`, `CreateSubscriber` no mesmo serviço.
- **Sufixos técnicos de proto**: `Request`/`Response` em inglês (convenção gRPC).

## Imports

Três grupos separados por linhas em branco, nesta ordem:

```go
import (
    "context"
    "fmt"
    "net/http"

    "github.com/jackc/pgx/v5"
    "go.uber.org/zap"

    "github.com/acme/billing/internal/auth"
)
```

`goimports` aplica isso. Nunca usar dot imports (`import . "x"`). Evitar blank imports (`import _ "x"`) exceto para registro de driver.

## Receivers: pointer vs value

Escolher um e ser **consistente para todos os métodos de um tipo**.

Usar **pointer receivers** quando:
- O método muta o receiver
- A struct contém `sync.Mutex` ou outro campo não-copiável
- A struct é grande (>~64 bytes)
- Algum método precisa de pointer receiver (então todos devem)

Usar **value receivers** quando:
- O tipo é pequeno e imutável (um `Point`, tipo `time.Time`)
- O tipo é map, slice, channel, function ou interface (já são tipos referência)

## Zero values

Projetar tipos para que o valor zero seja usável:

```go
// Bom — valor zero funciona
var b bytes.Buffer
b.WriteString("hello")

// Bom — valor zero de sync.Mutex é unlocked
type Cache struct {
    mu   sync.Mutex
    data map[string]string
}
// (inicializar data no construtor ou lazily)
```

Se um construtor é necessário, nomear `NewXxx` e retornar `*Xxx` ou `Xxx` (concreto, não interface).

## Declaração de variáveis

- `var x int` para o valor zero
- `x := 0` para um valor inicial (preferido quando o tipo é óbvio)
- `x := []int{}` apenas se precisar de um slice não-nil vazio. Preferir `var x []int` — `nil` slices se comportam identicamente para `len`, `range`, `append`.

## Fluxo de controle

- Early return em erro. Sem `else` depois de return.
  ```go
  if err != nil {
      return fmt.Errorf("leitura: %w", err)
  }
  // caminho feliz continua no mesmo nível de indentação
  ```
- Sem naked returns em funções com mais de ~5 linhas.
- `switch` sem expressão substitui cadeias longas de `if-else if`.
- Evitar aninhamento profundo. Guard clauses para tratar erros e edge cases imediatamente.

## Strings e slices

- Construir strings em loops com `strings.Builder`, nunca `+=`.
- Pré-alocar slices quando o tamanho é conhecido: `make([]T, 0, n)` depois `append`.
- Pré-dimensionar maps: `make(map[K]V, n)`.
- `len(nil_slice) == 0` e você pode `range` e `append` em um nil slice. Usar isso.

## Generics

Usar generics para **container types** e **funções sobre coleções** onde a alternativa seria `interface{}` + type assertions:

```go
// Bom uso de generics
func Map[T, U any](s []T, f func(T) U) []U { ... }
```

Não usar quando uma interface com método resolve.

## Features modernas da stdlib (Go 1.21+ que já podemos usar)

Antes de adicionar dependência, conferir se a stdlib já resolve:

- **`slices`** (1.21): `slices.Contains`, `Sort`, `SortFunc`, `BinarySearch`, `Clone`, `Reverse`, `Equal`, `Index`. Substitui boilerplate de loop.
- **`maps`** (1.21): `maps.Keys`, `Values`, `Clone`, `Equal`, `Copy`, `DeleteFunc`.
- **`cmp`** (1.21): `cmp.Or` para fallback de zero values, `cmp.Compare` para comparações tipadas.
- **`errors.Join`** (1.20): acumular erros sem perder nenhum, `errors.Is`/`As` percorrem joined.
- **`log/slog`** (1.21): structured logging stdlib. Sem `zap`/`zerolog`/`logrus`.
- **`context.WithoutCancel`** (1.21): propaga values sem cancelamento — cleanup que precisa rodar após cancel.
- **Pattern matching em `net/http`** (1.22): `mux.HandleFunc("GET /users/{id}", h)`. Sem `chi`/`gorilla`.
- **Variável de loop por iteração** (1.22): cada iteração de `for` tem sua própria cópia da variável. Aliases `id := id` agora são ruído.
- **Range over int** (1.22): `for i := range 10 { ... }` substitui `for i := 0; i < 10; i++`.
- **Range over function** (1.23) + package **`iter`** (1.23): iteradores customizados sem allocar slice intermediário.
- **`testing/synctest`** (1.24): clock virtual e detecção de deadlock em testes de código concorrente — fim de `time.Sleep` em testes.
- **`os.Root`** (1.24): I/O confinado a um diretório, sem traversal.
- **Generic type aliases** (1.24): `type Set[T comparable] = map[T]struct{}`.

Versão base do time: **Go 1.25**. Features acima podem ser usadas sem reserva.

## Logging

Usar **exclusivamente** `log/slog` (stdlib). Sempre structured, com atributos contextuais:

```go
slog.Info("pedido processado",
    "trace_id", traceID,
    "user_id", userID,
    "duration_ms", elapsed.Milliseconds(),
)

slog.Error("falha ao buscar usuário",
    "err", err,
    "user_id", id,
)
```

Não usar `log.Println`, `fmt.Printf` para logging, nem `zap`/`zerolog` a menos que já esteja no projeto.

## Coisas a evitar

- `panic` para fluxo normal de erros (apenas para falhas verdadeiramente irrecuperáveis de programador)
- `init()` fazendo trabalho real (conexões de DB, chamadas de rede). Usar setup explícito.
- Variáveis mutáveis no nível de pacote. Injetar dependências.
- `interface{}` como parâmetros. Usar generics ou tipos concretos.
- Funções longas. Se uma função tem mais de ~50 linhas ou >3 níveis de indentação, extrair.
- Struct embedding para reuso de código (usar composição com campos nomeados). Embedding é para satisfazer interfaces.
- **ORMs** (GORM, ent). Usar `sqlc` + SQL direto.
- **Frameworks HTTP pesados** (Gin, Echo, Fiber). Usar `net/http` (Go 1.22+) ou `chi` para routing.
- Dependências externas sem justificativa explícita.
