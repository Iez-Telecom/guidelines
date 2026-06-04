# Testes em Go

## Filosofia

Testes são **especificação executável**, não verificação no final. Bem escritos, são a melhor documentação do comportamento do sistema: um analista de negócio deve conseguir ler a descrição dos `t.Run` e entender as regras.

Ordem natural num feature novo:

1. Escrever a tabela de testes (spec do comportamento)
2. Implementar até a tabela passar
3. Adicionar property-based ou fuzz se a função tem espaço de input grande
4. Rodar `-race`

## Regras do time

- **Stdlib `testing`** como base. Sem testify, gomock, mockery, ginkgo.
- **`go-cmp`** é a única dependência de teste permitida (diffs legíveis).
- **`pgregory.net/rapid`** permitida para property-based testing (justificada caso a caso).
- Table-driven com **slices de structs anônimos** como padrão.
- **Fakes manuais** para isolar lógica de negócio de I/O.
- **`golangci-lint run` + `go test -race -count=1`** antes de qualquer commit.

## Table-driven tests (padrão obrigatório)

Nomes em português descrevendo a regra de negócio. Cada `name` deve ser uma frase que faz sentido para alguém não-técnico:

```go
func TestSuspenderLinhaPorInadimplencia(t *testing.T) {
    tests := []struct {
        name        string
        situacao    SituacaoLinha
        diasAtraso  int
        wantSituacao SituacaoLinha
        wantErr     error
    }{
        {
            name:         "linha ativa com 30 dias de atraso é suspensa",
            situacao:     SituacaoLinhaAtiva,
            diasAtraso:   30,
            wantSituacao: SituacaoLinhaSuspensa,
        },
        {
            name:        "linha já suspensa retorna erro",
            situacao:    SituacaoLinhaSuspensa,
            diasAtraso:  60,
            wantErr:     ErrLinhaJaSuspensa,
        },
        {
            name:        "linha cancelada não pode ser suspensa",
            situacao:    SituacaoLinhaCancelada,
            diasAtraso:  90,
            wantErr:     ErrLinhaCancelada,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            linha := Linha{Situacao: tt.situacao}
            got, err := suspenderPorInadimplencia(linha, tt.diasAtraso)

            if !errors.Is(err, tt.wantErr) {
                t.Fatalf("err = %v, want %v", err, tt.wantErr)
            }
            if err == nil && got.Situacao != tt.wantSituacao {
                t.Errorf("situacao = %v, want %v", got.Situacao, tt.wantSituacao)
            }
        })
    }
}
```

Regras:
- `t.Run(tt.name, ...)` para cada caso — aparece no output.
- Struct anônimo com campos `name`, inputs, `want*`, `wantErr`.
- Um test function por comportamento, muitos casos por test function.
- `t.Parallel()` quando os casos são independentes.
- Comparar erros com `errors.Is`, nunca por string.

## `testing/synctest` para código concorrente (Go 1.24+)

Antes, testar timeout/retry/scheduler envolvia `time.Sleep` que vazava determinismo. O `synctest` introduz **clock virtual** e detecção de deadlock: o tempo só avança quando todas as goroutines estão bloqueadas.

```go
import "testing/synctest"

func TestRetryComBackoffExponencial(t *testing.T) {
    synctest.Run(func() {
        chamadas := 0
        start := time.Now()

        err := RetryComBackoff(context.Background(), 3, func() error {
            chamadas++
            return errors.New("temporariamente indisponível")
        })

        elapsed := time.Since(start)

        // 3 tentativas com backoff 1s + 2s + 4s = 7s no clock virtual.
        // O teste roda instantaneamente — synctest pula o sleep.
        if chamadas != 3 {
            t.Errorf("chamadas = %d, want 3", chamadas)
        }
        if elapsed < 7*time.Second {
            t.Errorf("backoff insuficiente: %v", elapsed)
        }
        if err == nil {
            t.Fatal("esperava erro após esgotar tentativas")
        }
    })
}
```

Quando usar:
- Testar timeout/deadline.
- Testar retry/backoff.
- Testar rate limiter, ticker, scheduler.
- Qualquer coisa que envolva `time.After`, `time.NewTimer`, `time.Sleep`.

Quando **não** usar:
- Código sem timing — testes table-driven simples já bastam.
- Integração real com I/O (banco, rede) — synctest pausa o relógio virtual mas não controla I/O externo.

## Property-based testing com `rapid`

Quando o input tem espaço grande e você consegue formular **invariantes** (propriedades que devem valer para qualquer input), property-based é mais valioso que tabela. A IA é particularmente boa em gerar implementações que satisfazem propriedades quando elas estão escritas.

```go
import "pgregory.net/rapid"

// Propriedade: parse seguido de format é a identidade.
func TestMSISDN_RoundTrip(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        ddd := rapid.IntRange(11, 99).Draw(t, "ddd")
        numero := rapid.IntRange(900000000, 999999999).Draw(t, "numero")
        original := fmt.Sprintf("55%d%d", ddd, numero)

        parsed, err := ParseMSISDN(original)
        if err != nil {
            t.Fatalf("ParseMSISDN(%q) erro inesperado: %v", original, err)
        }

        if parsed.Format() != original {
            t.Errorf("roundtrip falhou: %q → %q", original, parsed.Format())
        }
    })
}

// Propriedade: aplicar franquia nunca produz consumo negativo.
func TestAplicarFranquia_NaoNegativo(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        consumo := rapid.Int64Range(0, 1<<40).Draw(t, "consumo")
        franquia := rapid.Int64Range(0, 1<<40).Draw(t, "franquia")

        excedente := AplicarFranquia(consumo, franquia)
        if excedente < 0 {
            t.Errorf("excedente negativo: consumo=%d franquia=%d → %d",
                consumo, franquia, excedente)
        }
    })
}
```

Casos típicos onde vale property-based:
- Parsers / formatters (round-trip)
- Serialização / deserialização (proto, JSON)
- Funções matemáticas / financeiras (invariantes de monotonicidade, comutatividade)
- Validadores (idempotência)

Não substitui tabela: use property para invariantes gerais, tabela para casos canônicos e edge cases nomeados.

## Fuzz testing (Go 1.18+)

Para parsers, validadores, deserializadores — qualquer coisa que recebe bytes do mundo. O Go gera input aleatório e usa coverage-guided search para achar entradas que crasham.

```go
func FuzzParseMSISDN(f *testing.F) {
    // Seeds — exemplos que devem funcionar (positivos) e edge cases conhecidos
    f.Add("5511999998888")
    f.Add("5521987654321")
    f.Add("")
    f.Add("invalid")

    f.Fuzz(func(t *testing.T, s string) {
        // O contrato é: nunca pode dar panic, mesmo com input maluco.
        // Erros são OK; panic não.
        _, _ = ParseMSISDN(s)
    })
}
```

Rodar:

```bash
go test -fuzz=FuzzParseMSISDN -fuzztime=30s ./internal/assinante
```

Quando o fuzzer encontra um crash, ele salva o input em `testdata/fuzz/FuzzParseMSISDN/<hash>` — vira teste de regressão permanente. Commitar.

## `ExampleXxx` como documentação executável

Funções com prefixo `Example` aparecem no godoc **e** rodam como teste (output comparado contra comentário `// Output:`). Dupla utilidade: doc + spec.

```go
// ExampleNormalizarCPF mostra como usar NormalizarCPF.
func ExampleNormalizarCPF() {
    cpf, _ := NormalizarCPF("123.456.789-00")
    fmt.Println(cpf)
    // Output: 12345678900
}

// Exemplo nomeado: aparece como subseção no godoc.
func ExampleNormalizarCPF_comEspacos() {
    cpf, _ := NormalizarCPF(" 123 456 789 00 ")
    fmt.Println(cpf)
    // Output: 12345678900
}
```

Quando usar:
- Função pública não trivial — exemplo ensina uso correto.
- Comportamento que vale demonstrar em godoc.

Quando **não** usar:
- Funções privadas (não vão pro godoc).
- Funções com output não determinístico (timestamp, UUID) — `// Output:` precisa ser estável.

## Golden files

Para testar output complexo: protobuf serializado, JSON estruturado, código gerado, mensagem renderizada.

```go
var update = flag.Bool("update", false, "atualizar golden files")

func TestRenderizarFatura(t *testing.T) {
    fatura := Fatura{
        ID:           "abc-123",
        AssinanteID:  "joao-da-silva",
        ValorTotal:   decimal.NewFromInt(12990),
        DataVencimento: time.Date(2026, 7, 15, 0, 0, 0, 0, time.UTC),
    }

    got, err := RenderizarFatura(fatura)
    if err != nil {
        t.Fatalf("render: %v", err)
    }

    golden := filepath.Join("testdata", "fatura.golden.txt")
    if *update {
        if err := os.WriteFile(golden, got, 0o644); err != nil {
            t.Fatal(err)
        }
        return
    }

    want, err := os.ReadFile(golden)
    if err != nil {
        t.Fatal(err)
    }
    if diff := cmp.Diff(string(want), string(got)); diff != "" {
        t.Errorf("output difere (-want +got):\n%s", diff)
    }
}
```

Atualizar quando o output mudou intencionalmente:

```bash
go test -update ./internal/fatura
```

Sempre **revisar o diff do `.golden`** no PR — é a spec do output.

## Fakes manuais (não usar mocks gerados)

Definir a interface no consumidor:

```go
// internal/assinante/assinante.go
type Store interface {
    BuscarPorMSISDN(ctx context.Context, msisdn string) (Assinante, error)
    Salvar(ctx context.Context, a Assinante) error
}
```

Implementar o fake no mesmo pacote, em `*_test.go`:

```go
// internal/assinante/fake_store_test.go
package assinante

type fakeStore struct {
    assinantes map[string]Assinante
    errBuscar  error
    errSalvar  error
}

func newFakeStore() *fakeStore {
    return &fakeStore{assinantes: make(map[string]Assinante)}
}

func (f *fakeStore) BuscarPorMSISDN(_ context.Context, msisdn string) (Assinante, error) {
    if f.errBuscar != nil {
        return Assinante{}, f.errBuscar
    }
    a, ok := f.assinantes[msisdn]
    if !ok {
        return Assinante{}, ErrAssinanteNaoEncontrado
    }
    return a, nil
}

func (f *fakeStore) Salvar(_ context.Context, a Assinante) error {
    if f.errSalvar != nil {
        return f.errSalvar
    }
    f.assinantes[a.MSISDN] = a
    return nil
}
```

Por que fakes manuais e não mocks gerados:
- **Simples**: você lê o código, sabe o que faz.
- **Sem geração extra**: nada para regenerar quando a interface muda.
- **Reutilizável**: o mesmo `newFakeStore()` serve para 20 testes.
- **Erro injetável**: campos `err*` permitem testar caminhos de falha sem ginástica.

## Test helpers

Marcar com `t.Helper()` para que falhas apontem para o chamador:

```go
func mustParseJSON[T any](t *testing.T, data []byte) T {
    t.Helper()
    var v T
    if err := json.Unmarshal(data, &v); err != nil {
        t.Fatalf("decodificar JSON: %v", err)
    }
    return v
}
```

`t.Cleanup` em vez de `defer` em helpers — executa em LIFO no fim do teste.

## `t.TempDir`, `t.Setenv`, `t.Context` (Go 1.24+)

```go
func TestEscreveArquivo(t *testing.T) {
    dir := t.TempDir()           // limpeza automática
    t.Setenv("CONFIG_DIR", dir)  // restaurado após o teste
    ctx := t.Context()           // cancelado quando o teste termina (1.24+)

    // ...
}
```

## Comparação com `cmp.Diff`

```go
if diff := cmp.Diff(want, got); diff != "" {
    t.Errorf("mismatch (-want +got):\n%s", diff)
}
```

Para tipos com campos não comparáveis (timestamps, mutex):

```go
cmp.Diff(want, got, cmpopts.IgnoreFields(Fatura{}, "CreatedAt"))
cmp.Diff(want, got, cmpopts.EquateApproxTime(time.Second))
```

## Benchmarks

```go
func BenchmarkCalcularJurosMora(b *testing.B) {
    parcela := Parcela{Valor: decimal.NewFromInt(15000), DataVencimento: time.Now().Add(-30 * 24 * time.Hour)}
    b.ResetTimer()
    for b.Loop() {  // Go 1.24+
        _ = calcularJurosMora(parcela, time.Now())
    }
}
```

Sintaxe `for b.Loop()` (1.24+) substitui `for i := 0; i < b.N; i++`. O timer é gerenciado pelo `Loop()` — sem precisar `b.ResetTimer()` manual.

```bash
go test -bench=. -benchmem -count=10 ./internal/cobranca
benchstat old.txt new.txt    # comparar runs (golang.org/x/perf/cmd/benchstat)
```

`-count=10` importa: benchmarks de run única são ruidosos.

## Race detector — obrigatório

```bash
go test -race -count=1 ./...
```

Sempre rodar `-race` no CI. `-count=1` desabilita cache de resultados.

## Cobertura

```bash
go test -cover ./...
go test -coverprofile=cover.out ./...
go tool cover -html=cover.out
```

Cobertura é detector de fumaça, não objetivo. Testes significativos com 70% valem mais que 100% testando trivialidades.

## Anti-padrões

- **`time.Sleep` em teste de código concorrente** — usar `testing/synctest`.
- **Mock framework (gomock, mockery, testify/mock)** — fakes manuais.
- **Comparar erros por `err.Error() == "..."`** — `errors.Is`/`errors.As`.
- **Assertion frameworks (`testify/assert`)** — `if got != want { t.Errorf(...) }` é mais claro.
- **Testes que dependem de ordem de execução** — `-shuffle=on` deve passar.
- **Estado global compartilhado entre testes** — usar `t.Setenv`, `t.TempDir`, fixtures locais.
- **`t.Skip` permanente** — ou conserta, ou deleta. Skip é dívida.
