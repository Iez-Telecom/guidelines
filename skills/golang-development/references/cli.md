# Ferramentas CLI em Go

## Quando stdlib `flag` basta

Para um binário único com poucos flags, `flag` é suficiente e tem zero dependências:

```go
package main

import (
    "flag"
    "fmt"
    "os"
)

func main() {
    var (
        addr    = flag.String("addr", ":8080", "endereço de escuta")
        verbose = flag.Bool("v", false, "logging verboso")
    )
    flag.Parse()

    if err := run(*addr, *verbose, flag.Args()); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
}
```

## Quando usar cobra

Quando existem **subcomandos** (`mytool add`, `mytool list`, `mytool delete`), usar `github.com/spf13/cobra`:

**Justificativa da dependência**: cobra é a biblioteca padrão de facto para CLIs com subcomandos em Go. Não existe alternativa na stdlib.

```go
// cmd/root.go

// rootCmd é o comando raiz da aplicação CLI.
var rootCmd = &cobra.Command{
    Use:   "mytool",
    Short: "gerencia widgets",
}

// cmd/add.go

// addCmd adiciona um novo widget.
var addCmd = &cobra.Command{
    Use:   "add [nome]",
    Short: "adicionar um widget",
    Args:  cobra.ExactArgs(1),
    RunE: func(cmd *cobra.Command, args []string) error {
        return doAdd(cmd.Context(), args[0])
    },
}

func init() { rootCmd.AddCommand(addCmd) }
```

Sempre usar `RunE` (retorna error) ao invés de `Run`. Sempre usar `cmd.Context()` para propagar signal handling.

Wiring de sinal de cancelamento no `main`:

```go
func main() {
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer stop()
    if err := rootCmd.ExecuteContext(ctx); err != nil {
        os.Exit(1)
    }
}
```

## Configuração com variáveis de ambiente

Para serviços, preferir **variáveis de ambiente** (ver `references/project-layout.md`). Para CLIs que precisam de flags + env + config file, `viper` cola tudo:

```go
viper.SetEnvPrefix("MYTOOL")
viper.AutomaticEnv()
viper.SetConfigName("config")
viper.AddConfigPath(".")
_ = viper.ReadInConfig() // ok se não existir
viper.BindPFlag("addr", rootCmd.PersistentFlags().Lookup("addr"))
```

**Justificativa para viper**: necessário somente quando a CLI precisa de layered config (flags → env → arquivo). Para casos simples, `os.Getenv` + `flag` basta.

Para necessidades mais simples, `github.com/caarlos0/env/v10` parseia env vars em struct com uma chamada.

## Output

- **Erros e diagnósticos** → `os.Stderr`.
- **Output primário** (o que será piped para outros comandos) → `os.Stdout`.
- Respeitar env var `NO_COLOR` se emitir output colorido.

## Testando comandos CLI

Construir os comandos para que os streams de I/O sejam injetáveis:

```go
// App encapsula a CLI com streams injetáveis para teste.
type App struct {
    Out, Err io.Writer
    In       io.Reader
}

// Run executa o comando com os argumentos fornecidos.
func (a *App) Run(args []string) error { ... }
```

Nos testes, passar `&bytes.Buffer{}` para os streams e assertar no conteúdo.
