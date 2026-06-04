# Tratamento de erros em Go

Erros são valores. Tratá-los como qualquer outro retorno: checar, transformar, propagar com contexto.

## A forma básica

```go
f, err := os.Open(path)
if err != nil {
    return fmt.Errorf("abrir %s: %w", path, err)
}
defer f.Close()
```

Três regras:
1. **Checar imediatamente.** Nunca `_, err := ...` e olhar depois.
2. **Wrappear com `%w`** para preservar a cadeia. Usar `%v` somente quando quiser flatten intencionalmente.
3. **Adicionar contexto** na mensagem de wrap — o que estava fazendo, com que inputs.

## Erros sentinela (comparar com `errors.Is`)

Para condições de erro conhecidas e comparáveis:

```go
package userrepo

import "errors"

// ErrNotFound indica que o usuário não foi encontrado no banco.
var ErrNotFound = errors.New("usuário não encontrado")

// Get busca um usuário pelo ID.
func (r *Repo) Get(ctx context.Context, id string) (*User, error) {
    // ...
    if rows == 0 {
        return nil, ErrNotFound
    }
}

// No chamador:
u, err := r.Get(ctx, id)
if errors.Is(err, userrepo.ErrNotFound) {
    // tratar caso de não encontrado
}
```

Definir sentinelas no pacote que os produz. Nomear `ErrXxx`.

## Erros tipados (extrair com `errors.As`)

Quando o erro precisa carregar dados:

```go
// ValidationError representa um erro de validação em um campo específico.
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validação: %s: %s", e.Field, e.Message)
}

// No chamador:
var verr *ValidationError
if errors.As(err, &verr) {
    slog.Warn("campo inválido", "field", verr.Field)
}
```

Sempre implementar `Error()` no **pointer** receiver e retornar o **tipo ponteiro** — senão `errors.As` não unwrapa corretamente através de `%w`.

## A armadilha do nil interface

```go
// ERRADO — o `err != nil` do chamador será true mesmo sem erro!
func do() error {
    var e *ValidationError // ponteiro nil
    // ... se não houver problema de validação, e permanece nil
    return e // wrapped em interface header não-nil
}

// CERTO — retornar nil puro
func do() error {
    var e *ValidationError
    // ...
    if e != nil {
        return e
    }
    return nil
}
```

Um valor de interface é nil somente quando **tanto** tipo quanto valor são nil.

## Wrappear vs não wrappear

- **Wrappear** ao cruzar boundary de camada quando o erro interno é significativo para chamadores.
- **Não wrappear** quando o erro é puramente interno e o chamador não deve depender dele (usar `%v` ou erro novo).
- **Substituir** quando quiser esconder detalhes de implementação: `return ErrNotFound` ao invés de vazar `sql.ErrNoRows`.

```go
// Get busca um usuário no banco de dados.
func (r *Repo) Get(ctx context.Context, id string) (*User, error) {
    err := r.queries.GetUser(ctx, id) // sqlc gerado
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, ErrNotFound // erro de domínio, não de SQL
    }
    if err != nil {
        return nil, fmt.Errorf("buscar usuário %s: %w", id, err)
    }
    return u, nil
}
```

## Múltiplos erros (`errors.Join`, Go 1.20+)

```go
var errs []error
for _, item := range items {
    if err := validate(item); err != nil {
        errs = append(errs, fmt.Errorf("item %s: %w", item.ID, err))
    }
}
if len(errs) > 0 {
    return errors.Join(errs...)
}
```

`errors.Is` e `errors.As` percorrem erros joinados.

## Panic e recover

- **Não usar panic para fluxo de controle.** Erros são para falhas esperadas.
- Panic apenas para falhas verdadeiramente irrecuperáveis de programador (assertions de estado impossível).
- **Absolutamente sem `panic` em lógica de negócio ou handlers HTTP/gRPC.** `panic` permitido apenas para inicialização (`regexp.MustCompile`).
- `recover` apenas em boundaries de processo (handlers HTTP, entry points de goroutines) para logar + retornar 500/Internal ao invés de crashar o processo inteiro.

```go
// recoverMiddleware converte panics em erros gRPC Internal.
func recoverMiddleware(logger *slog.Logger) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp any, err error) {
        defer func() {
            if rec := recover(); rec != nil {
                logger.Error("panic no handler",
                    "method", info.FullMethod,
                    "panic", rec,
                    "stack", string(debug.Stack()),
                )
                err = status.Error(codes.Internal, "erro interno")
            }
        }()
        return handler(ctx, req)
    }
}
```

## Anti-padrões

```go
// RUIM — silenciosamente descartado
result, _ := doThing()

// RUIM — erro sem contexto
return err

// RUIM — comparação de string ao invés de errors.Is
if err.Error() == "not found" { ... }

// RUIM — log E return (chamador vai logar de novo)
if err != nil {
    slog.Error("falha", "err", err)
    return err
}
// Escolher um: ou tratar (log + não retornar) ou retornar (não logar).
```
