# Guidelines Práticos — Go

Receitas operacionais para o dia a dia em Go. Complementa o [arquitetura_backend.md](./arquitetura_backend.md) — foco em de setup de máquina, build, release e dos comandos que você roda toda semana.

## Como ler este documento

Não é um tutorial de Go. Pressupõe Go 1.25+ instalado, familiaridade com `go mod`, `go test` e Makefile. O objetivo é registrar as configurações e snippets que aparecem em todos os nossos projetos para não termos que reinventar (e errar) a cada repositório novo.

Os arquivos de referência prontos para copiar estão em [`exemplos/`](./exemplos):

- [`exemplos/Makefile`](./exemplos/Makefile)
- [`exemplos/Containerfile`](./exemplos/Containerfile)
- [`exemplos/buf.yaml`](./exemplos/buf.yaml)
- [`exemplos/buf.gen.yaml`](./exemplos/buf.gen.yaml)

As seções abaixo explicam **o porquê** de cada decisão. Para o **o quê**, abra os arquivos.

## Setup de máquina

### Versão do Go

Use a versão major mais recente. Para gerenciar múltiplas versões na mesma máquina, prefira o instalador oficial (`go install golang.org/dl/go1.25@latest && go1.25 download`) ao `gvm`/`asdf` — menos surpresas com `GOROOT`/`GOPATH`.

```bash
go version    # confirme o que está rodando
go env        # inspecione configuração efetiva
```

### Variáveis de ambiente persistentes

Use `go env -w` para persistir configuração em `~/Library/Application Support/go/env` (macOS) ou `~/.config/go/env` (Linux). Não exporte essas variáveis no `.zshrc`/`.bashrc` — fica em dois lugares e diverge.

```bash
go env -w GOPRIVATE="github.com/Iez-Telecom/*"
go env -w GOFLAGS="-mod=mod"
```

Para desfazer:

```bash
go env -u GOPRIVATE
```

## Módulos privados

Repositórios privados (qualquer coisa em `github.com/Iez-Telecom/*`) precisam de duas coisas: dizer ao Go para **não passar pelo proxy público** e **não verificar checksum público** (porque o proxy/sumdb não conseguem ver o código privado), e dar ao `git` credenciais para clonar.

### Configuração do Go

Uma única variável resolve as duas coisas:

```bash
go env -w GOPRIVATE="github.com/Iez-Telecom/*"
```

`GOPRIVATE` é shorthand para `GONOPROXY` + `GONOSUMCHECK`. Não use `GOSUMDB=off` global — desliga a verificação para *todas* as dependências, inclusive públicas, e nesse momento você perdeu a proteção contra ataque de supply chain em libs do ecossistema.

Se quiser separar (por exemplo, ainda passar pelo proxy mas pular checksum), use as variáveis específicas:

```bash
go env -w GONOSUMCHECK="github.com/Iez-Telecom/*"
go env -w GONOPROXY="github.com/Iez-Telecom/*"
```

### Configuração do git

`go mod download` vai chamar `git` por baixo dos panos. O `git` precisa autenticar — escolha SSH e force HTTPS a virar SSH no `~/.gitconfig`:

```gitconfig
[url "git@github.com:Iez-Telecom/"]
    insteadOf = https://github.com/Iez-Telecom/
```

Por que: o `go.mod` referencia módulos por URL HTTPS (`github.com/Iez-Telecom/...`); a regra acima reescreve para SSH na hora de clonar, usando sua chave configurada. Funciona transparentemente para `go get`, `go mod tidy` e CI (basta a CI ter a chave SSH).

Em CI sem SSH, alternativa via token:

```gitconfig
[url "https://oauth2:${GITHUB_TOKEN}@github.com/Iez-Telecom/"]
    insteadOf = https://github.com/Iez-Telecom/
```

## Submodules para protos compartilhados

Contratos `.proto` compartilhados entre serviços moram em um repositório separado (`simfonia-protos`). Cada serviço consome apenas as pastas que precisa via **git submodule com sparse-checkout** — assim você não clona o repositório inteiro de protos só para gerar dois arquivos.

### Adicionando o submodule pela primeira vez

```bash
git submodule add --name SimfoniaProtos \
    git@github.com:Iez-Telecom/simfonia-protos.git external/proto
( cd external/proto && git sparse-checkout init --cone )
( cd external/proto && git sparse-checkout set iez/simfonia crm_sqlgateway )
git submodule update --init --recursive
```

A primeira linha registra o submodule. A segunda ativa sparse-checkout em modo "cone" (mais rápido, só permite pastas inteiras). A terceira escolhe quais pastas materializar no disco. A quarta hidrata.

### Para quem clona o repositório

Adicione ao README do serviço:

```bash
git clone git@github.com:Iez-Telecom/meu-servico.git
cd meu-servico
git submodule update --init --recursive
```

Ou, em um único comando:

```bash
git clone --recurse-submodules git@github.com:Iez-Telecom/meu-servico.git
```

### Atualizando os protos

```bash
git submodule update --remote external/proto
```

Isso busca o HEAD da branch trackeada do repositório de protos. Comite a mudança do submodule junto com a regeneração do código:

```bash
make generate
git add external/proto gen/
git commit -m "atualizar protos para X"
```

### Removendo completamente

```bash
git submodule deinit -f external/proto
git rm -f external/proto
rm -rf .git/modules/SimfoniaProtos
```

## Makefile padrão

Toda automação relevante mora no Makefile. Sem scripts soltos em `scripts/` que ninguém sabe se ainda funcionam.

**Arquivo de referência:** [`exemplos/Makefile`](./exemplos/Makefile) — ponto de partida para qualquer serviço novo. Copie para a raiz do repositório e ajuste o que for específico.

Resumo dos alvos:

| Alvo | O que faz |
|---|---|
| `make` (sem args) | Lista todos os alvos com descrição (autogerado a partir dos `##`) |
| `make generate` | Roda `buf generate` + `sqlc generate` |
| `make build` / `build-linux` | Compila com ldflags injetando versão/commit/data |
| `make run` | Executa localmente com as mesmas flags |
| `make test` | `go test -race -count=1 ./...` |
| `make lint` | `gofmt -l`, `go vet`, `staticcheck` |
| `make vendor` | `go mod tidy && go mod vendor` (commitar `vendor/` depois) |
| `make podman-build` | Constrói a imagem **distroless** (produção), tag `:$(CONTAINER_TAG)` |
| `make podman-build-alpine` | Constrói a imagem **alpine** (debug), tag `:$(CONTAINER_TAG)-alpine` |
| `make podman-run` / `podman-run-alpine` | Roda localmente a variante distroless ou alpine |
| `make podman-deploy REGISTRY=...` | Push da variante distroless |
| `make podman-deploy-alpine REGISTRY=...` | Push da variante alpine (uso em incidente) |
| `make swagger-gen` / `swagger-up` | Gera OpenAPI dos protos e sobe Swagger UI |
| `make clean` / `dist-clean` | Remove binários, código gerado e submodules |

### Por que esse Makefile

- **`.DEFAULT_GOAL := help`** com auto-geração: `make` sem argumentos lista os alvos. Documentação que não rota porque está embutida nos próprios comandos.
- **`VERSION := $(shell git describe --tags --always --dirty)`**: tag se houver, hash curto se não; `-dirty` se você esqueceu de commitar antes do build. Você descobre no `--version` do binário que rodou código não commitado.
- **`-X` em ldflags** injeta versão/commit/data direto no binário sem precisar de arquivos de versão. Veja a próxima seção.
- **`CGO_ENABLED=0`** garante binário estático — roda em imagem distroless/scratch sem libs do sistema.
- **`-s -w`** em ldflags remove tabela de símbolos e debug info: binário ~30% menor. Não fazer em builds para profiling.
- **`-count=1`** em `go test` desabilita o cache do test runner. Cache de teste é silencioso e engana — quando você quer rodar de verdade, force.

## Embutindo versão no binário

Declare variáveis no `main` que o linker preenche:

```go
// cmd/server/main.go
package main

import (
    "fmt"
    "log/slog"
)

// Preenchidas no link time via -ldflags "-X 'main.clientVersion=...'"
var (
    clientVersion = "dev"
    commitHash    = "unknown"
    buildDate     = "unknown"
)

func main() {
    slog.Info("iniciando serviço",
        "version", clientVersion,
        "commit", commitHash,
        "build_date", buildDate,
    )
    // ...
}
```

E uma flag `--version` para inspecionar binário em produção:

```go
if len(os.Args) > 1 && os.Args[1] == "--version" {
    fmt.Printf("%s (commit %s, built %s)\n", clientVersion, commitHash, buildDate)
    return
}
```

Para inspecionar um binário Go pronto sem rodá-lo:

```bash
go version -m bin/server      # mostra módulos e versões embutidos
```

## .gitignore padrão

```gitignore
# Binários
/bin/
*.exe
*.test
*.out

# Protos iez
/external/proto/

# Código gerado (regerado pelo build do Containerfile e por `make generate`)
/gen/

# NÃO ignorar /vendor/ — dependências de terceiros são versionadas
# para garantir build reproduzível sem rede e auditoria via git blame

# Cobertura
coverage.txt
coverage.html

# IDE
.idea/
.vscode/
buf.lock

# Sistema
.DS_Store

# Configuração local (nunca commitar segredos)
.env
.env.local
.env*
*.local.yaml
```

Decisões do time:

- **`/gen/` não vai no repo.** A geração roda dentro do build do container (com versões pinadas de `buf`/`protoc-gen-go` na própria imagem) e via `make generate` localmente. Comitar `gen/` cria conflito sempre que duas branches mexem no proto.
- **`/vendor/` vai no repo.** Build do container roda `go build -mod=vendor`, sem precisar resolver módulos privados pela rede. Atualize com `make vendor` quando mexer em dependências; o diff do `vendor/` no PR é a auditoria de "o que entrou de código de terceiros".

## Containerfile padrão

Multi-stage com `vendor/`, geração de código no build, e **dois runtimes selecionáveis** via `--target`:

| Variante | Tag | Quando usar |
|---|---|---|
| `runtime-distroless` (default) | `cobranca-svc:v1.2.3` | Produção. Sem shell, sem package manager, ~2 MB + binário. |
| `runtime-alpine` (opt-in) | `cobranca-svc:v1.2.3-alpine` | Debug emergencial. Inclui `sh`, `curl`, `bind-tools` para `kubectl exec` interativo. |

**Arquivo de referência:** [`exemplos/Containerfile`](./exemplos/Containerfile) — copie para a raiz do repositório.

Comandos:

```bash
make podman-build               # distroless, tag :v1.2.3
make podman-build-alpine        # alpine,    tag :v1.2.3-alpine
make podman-deploy REGISTRY=...         # push da distroless
make podman-deploy-alpine REGISTRY=...  # push da alpine (em incidente)
```

### A estratégia das duas variantes

O default é distroless porque é o que vai para produção: superfície de ataque mínima, sem shell para virar pivot em comprometimento, imagem pequena. Mas distroless não tem `ps`, `sh`, `wget`, `nslookup` — quando algo dá errado em produção e logs + traces + metrics não bastam, você fica preso.

A saída é construir uma segunda imagem do **mesmo binário** em cima de Alpine, com sufixo `-alpine` na tag. Em um incidente, você troca o deployment para apontar para `cobranca-svc:v1.2.3-alpine`, faz `kubectl exec` para investigar, e depois volta para a tag sem sufixo. As duas imagens são byte-a-byte idênticas no que importa (o binário Go) — só muda a base. Isso elimina a classe de bug "funciona em alpine, quebra em distroless" porque o binário é o mesmo.

A convenção de tag (`-alpine` sufixo) é o que torna isso seguro: no `kubectl describe pod`, no log do registry, no `podman images`, fica óbvio quando alguém deixou um pod rodando a versão de debug. Sem o sufixo, fácil esquecer um pod com shell exposto em produção.

### Trade-off do ENTRYPOINT no distroless

Distroless não tem shell, então `ENTRYPOINT exec /usr/local/bin/${BIN_NAME}` (shell form com interpolação) não funciona — só exec form, que é uma lista literal sem expansão. Resultado: o binário é copiado para `/app` (caminho fixo) e o `ENTRYPOINT` é `["/app"]`.

Consequência prática: dentro do container distroless, o binário se chama `/app` independente do serviço. A identificação fica na tag da imagem (`cobranca-svc:v1.2.3`) e nos labels do Kubernetes — que é onde operadores olham. Como distroless não tem `ps` para listar processos por dentro mesmo, perder o nome do binário interno é um custo barato.

Na variante alpine o binário continua em `/usr/local/bin/${BIN_NAME}` com nome do serviço, então quando você abrir o shell em incidente, `ps aux` mostra `/usr/local/bin/cobranca-svc` e você sabe imediatamente o que está rodando.

### Por que cada parte

- **`BIN_NAME` derivado do módulo** (default `server`, sobrescrito pelo Makefile com `$(notdir $(MODULE))`): resolve o problema de ter N serviços no cluster todos aparecendo como `servidor` em ferramentas de inspeção. A tag da imagem (`CONTAINER_NAME`) usa o mesmo nome — alinhamento de ponta a ponta. No stage alpine o binário fica em `/usr/local/bin/<BIN_NAME>` (visível em `ps`); no distroless vai para `/app` (trade-off explicado acima).
- **Geradores pinados no builder** (`buf@v1.70.0`, etc.): o build não depende do que o dev tem instalado nem do que o CI escolheu instalar essa semana. Quando atualizar versão, é um commit explícito no Containerfile.
- **`vendor/` copiado antes do código**: `go mod download` reaproveita cache enquanto você edita `.go`. Sem isso, qualquer mudança em código-fonte invalida a layer de dependências.
- **`buf dep update && buf generate` no build**: como `/gen/` não é commitado, o build é a única fonte de verdade do código gerado. Garante que ninguém esquece de regenerar.
- **`-mod=vendor`**: o build não chama a rede para resolver módulos privados. Reprodutível mesmo sem `GOPRIVATE`/`insteadOf` configurados no runner.
- **`-trimpath`**: remove `/src/...` do binário. Builds idênticos byte a byte entre máquinas diferentes, e nada vaza sobre o filesystem do build.
- **`-s -w` no ldflags**: binário ~30% menor (tira tabela de símbolos e DWARF). Não fazer em builds para profiling.
- **Stage `runtime-alpine` declarado **antes** do distroless**: a ordem importa, porque `podman build` sem `--target` constrói o último stage. Distroless por último = produção é o caminho de menor atrito; alpine exige `--target` explícito.
- **`exec` no ENTRYPOINT do alpine**: sem `exec`, o sh fica como PID 1 e intercepta sinais; o Go nunca recebe SIGTERM e o pod só morre por timeout depois de 30 s. Sintoma: shutdown sujo e logs aparecem cortados. No distroless o problema não existe porque o ENTRYPOINT já é exec form (`["/app"]`).
- **`curl` e `bind-tools` no alpine**: incluídos *só* porque essa imagem existe para debug. Em distroless eles não entram — você não vai fazer `kubectl exec` em pod de produção mesmo.

### Validando o build

```bash
make podman-build                            # distroless
make podman-build BIN_NAME=outro             # override explícito
make podman-build-alpine                     # variante de debug

# Confirme que o stage certo foi construído:
podman images | grep $(notdir $(MODULE))
# cobranca-svc   v1.2.3          <id>   2.1 MB
# cobranca-svc   v1.2.3-alpine   <id>   12 MB

# Inspecione o ENTRYPOINT efetivo:
podman inspect cobranca-svc:v1.2.3 --format '{{.Config.Entrypoint}}'
# [/app]
podman inspect cobranca-svc:v1.2.3-alpine --format '{{.Config.Entrypoint}}'
# [/bin/sh -c exec /usr/local/bin/cobranca-svc]

# Confirme nome do processo na variante alpine:
podman run --rm cobranca-svc:v1.2.3-alpine ps aux
# /usr/local/bin/cobranca-svc
```

## buf.yaml e buf.gen.yaml

Não usamos `protoc` direto — apenas `buf`.

**Arquivos de referência:**
- [`exemplos/buf.yaml`](./exemplos/buf.yaml) — módulos (`api/proto/v1` próprio + `external/proto` vindo do submodule), dependência de `googleapis`, lint `STANDARD` com exceções, breaking-check a nível de arquivo.
- [`exemplos/buf.gen.yaml`](./exemplos/buf.gen.yaml) — plugins **locais** (`protoc-gen-go`, `protoc-gen-go-grpc`), saída em `gen/` com `paths=source_relative`, geração consumindo os mesmos dois diretórios declarados no `buf.yaml`.

### Decisões pontuais

- **Plugins locais, não remotos.** O Containerfile já instala `protoc-gen-go` e `protoc-gen-go-grpc` com versões pinadas via `go install`; o `buf` chama os binários locais. Isso significa que o build não depende da BSR remota estar disponível, e a versão dos plugins é a mesma na máquina do dev e no container. Plugins remotos (`remote: buf.build/...`) são convenientes em prototipação, mas adicionam uma dependência de rede em todo build.
- **`deps: buf.build/googleapis/googleapis`** traz `google.api.http`, `google.api.annotations` e os tipos auxiliares que usamos para mapear gRPC ↔ REST (`grpc-gateway`) e gerar OpenAPI. Atualize com `buf dep update` quando precisar; o lockfile (`buf.lock`) é commitado.
- **Exceções de lint:**
  - `PACKAGE_VERSION_SUFFIX`: forçaria todo pacote proto a terminar em `.v1`, `.v2`... Nosso schema de diretórios já tem `/v1/`, e o sufixo no nome do pacote duplica informação sem agregar.
  - `PACKAGE_DIRECTORY_MATCH`: exigiria que o nome do pacote proto reflita o caminho do diretório. Em `external/proto` (submodule de terceiros) não temos controle dessa correspondência, então desligamos no projeto inteiro para evitar lint quebrando por arquivos que não são nossos.
- **`rpc_allow_google_protobuf_empty_*`:** permite RPCs com `google.protobuf.Empty` em request ou response, sem ter que declarar uma mensagem vazia só para satisfazer o lint. Útil em health checks, refresh de cache e operações puramente disparadoras.
- **`require_unimplemented_servers=false`:** o servidor **não** embute `UnimplementedXxxServer`; você precisa implementar todo RPC declarado no proto. Quando alguém adiciona um RPC novo, o build do servidor quebra imediatamente — preferimos esse sinal a deixar o servidor compilando e retornar `Unimplemented` em runtime. Use `true` apenas em wrappers/proxies onde implementar todos os RPCs é genuinamente opcional.

### Comandos do dia

```bash
buf lint                                   # valida todos os módulos
buf format -w                              # formata .proto in-place
buf generate                               # gera código (lê buf.gen.yaml)
buf dep update                             # atualiza dependências (commit no buf.lock)
buf breaking --against ".git#branch=main"  # falha se a branch quebrou contrato
```

Em CI, rode `buf lint` e `buf breaking` antes do build — quebra de contrato pega em segundos.

## `replace` para desenvolvimento local

Quando você está mexendo em duas bibliotecas/módulos ao mesmo tempo (por exemplo, num pacote compartilhado e no serviço que o usa), use `replace` no `go.mod` para apontar para a checkout local:

```go
// go.mod
module github.com/Iez-Telecom/meu-servico

go 1.25

require github.com/Iez-Telecom/lib-compartilhada v0.5.0

replace github.com/Iez-Telecom/lib-compartilhada => ../lib-compartilhada
```

**Nunca comite um `replace` apontando para caminho local.** Tira do diff antes de abrir PR. Para evitar acidente, prefira `go.work` (próxima seção) quando o setup é recorrente.

## `go.work` para workspaces

Quando você trabalha em N módulos relacionados em uma mesma sessão de IDE, crie um `go.work` na pasta pai. Não é commitado (`go.work` e `go.work.sum` ficam no `.gitignore` global).

```bash
mkdir ~/Projetos/iez
cd ~/Projetos/iez
git clone git@github.com:Iez-Telecom/lib-compartilhada.git
git clone git@github.com:Iez-Telecom/meu-servico.git

go work init ./lib-compartilhada ./meu-servico
```

O IDE passa a navegar entre os módulos como se fossem um só, sem `replace` em nenhum `go.mod`.

## Comandos do dia a dia

### Dependências

```bash
go get github.com/algo/lib@v1.2.3   # adiciona/atualiza versão específica
go get -u ./...                     # atualiza tudo para minor/patch mais recente
go mod tidy                         # remove o que não é usado, baixa o que falta
go mod why github.com/x/y           # explica por que essa dependência está no projeto
go list -m -u all                   # lista dependências com atualizações disponíveis
```

### Teste

```bash
go test ./...                                # todos os pacotes
go test -race -count=1 ./...                 # com detector de race
go test -run TestBuscarAssinante ./internal/assinante  # um teste específico
go test -v -run TestX/sub_caso ./...         # subteste específico (table-driven)
go test -coverprofile=coverage.out ./...     # cobertura
go tool cover -html=coverage.out             # visualiza cobertura no browser
```

### Build e binário

```bash
go build ./cmd/server                # compila no diretório atual
go install ./cmd/server              # compila e instala em $GOBIN
go version -m bin/server             # inspeciona módulos embutidos
go tool objdump -s 'main\.main' bin/server  # desmonta uma função (debug)
```

### Profiling rápido

```bash
go test -bench=. -benchmem -cpuprofile=cpu.out ./internal/assinante
go tool pprof -http=:8080 cpu.out
```

Em produção, exponha `net/http/pprof` em uma porta interna (nunca pública):

```go
import _ "net/http/pprof"

go func() {
    slog.Info("pprof escutando em :6060")
    _ = http.ListenAndServe("localhost:6060", nil)
}()
```

Depois: `go tool pprof http://localhost:6060/debug/pprof/heap`.

## Tooling local

Instale uma vez:

```bash
# Linter unificado (substitui gofmt/goimports/go vet/staticcheck individuais)
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# Geração de código
go install github.com/bufbuild/buf/cmd/buf@latest
go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# LSP para editores
go install golang.org/x/tools/gopls@latest
```

Configuração canônica do `golangci-lint` em [`exemplos/.golangci.yml`](./exemplos/.golangci.yml). Copie para a raiz do serviço novo junto com Makefile/Containerfile.

Tudo cai em `$GOBIN` (default `~/go/bin`). Coloque no `PATH`:

```bash
export PATH="$PATH:$(go env GOBIN):$(go env GOPATH)/bin"
```

Para CI, fixe versões em um `tools.go` ou um `Makefile` target dedicado — não confie em `@latest` para builds reprodutíveis.

## Configuração do editor (VS Code)

`.vscode/settings.json` no repositório (commitado):

```json
{
  "go.useLanguageServer": true,
  "go.lintTool": "staticcheck",
  "go.lintOnSave": "package",
  "go.formatTool": "goimports",
  "[go]": {
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.organizeImports": "always"
    }
  },
  "gopls": {
    "ui.semanticTokens": true,
    "formatting.gofumpt": false
  }
}
```

Não usamos `gofumpt` — `gofmt` + `goimports` é o suficiente e evita briga com quem usa outro editor.

## CI mínimo

Em qualquer pipeline novo, garanta estes passos antes do build:

```bash
go mod download
golangci-lint run ./...                            # gofmt + vet + staticcheck + ~15 outros
buf lint
buf breaking --against ".git#branch=main"          # opcional, só se há protos versionados
go test -race -count=1 ./...
```

A ordem importa: lint barato falha rápido, antes de gastar tempo compilando e testando.

## Coisas pequenas que economizam horas

- **`go env GOMODCACHE`** mostra onde estão os módulos baixados (`~/go/pkg/mod` por padrão). Quando um download dá errado e fica travado, apague o diretório do módulo específico em vez de limpar o cache inteiro.
- **`go clean -testcache`** para forçar re-execução de todos os testes (alternativa a `-count=1` ad hoc).
- **`GODEBUG=gctrace=1 ./server`** imprime estatísticas de GC. Útil quando você suspeita de pressão de memória.
- **`GOMAXPROCS`** em container Kubernetes: instale [`automaxprocs`](https://github.com/uber-go/automaxprocs) ou setar manualmente. Sem isso, o Go enxerga todos os cores do node, não os do cgroup, e o scheduler sofre.
- **`errors.Join(errs...)`** (Go 1.20+) para acumular múltiplos erros sem perder nenhum — útil em validação de input.
- **`slices`** e **`maps`** (Go 1.21+) substituem várias dependências externas: `slices.Contains`, `slices.Sort`, `maps.Keys`, etc.
- **`context.WithoutCancel`** (Go 1.21+) propaga valores mas não o cancelamento — para iniciar cleanup que precisa rodar mesmo após o context original ser cancelado.

## Quando algo dá errado

| Sintoma | Verifique |
|---|---|
| `go get` em módulo privado falha com 404 | `GOPRIVATE` está setado? `insteadOf` no `~/.gitconfig`? Chave SSH carregada? |
| `checksum mismatch` em módulo privado | Apague a entrada em `go.sum` e rode `go mod download` novamente — costuma ser inconsistência entre cache e `GOSUMDB`. |
| Build local funciona, container quebra | `CGO_ENABLED=0`? Está usando lib que precisa de `glibc` (não roda em distroless/static)? |
| Race detector acusa em CI mas não local | CI tem menos cores e expõe corridas; sempre rode `-race` antes de comitar. |
| `make generate` produz diff em arquivos que não mexi | Versão do `buf`/`sqlc` diferente entre máquinas. Fixe versão. |
| Binário Go gigante (>50 MB) | Faltou `-s -w` no ldflags ou `-trimpath`. Confira o Makefile. |
| Pod em loop de OOMKilled | `GOMAXPROCS` igual ao limite de CPU do pod? GC pressure alta? `GODEBUG=gctrace=1` para investigar. |

## Recursos

- [Effective Go](https://go.dev/doc/effective_go) — leitura única, depois consulta.
- [Go Modules Reference](https://go.dev/ref/mod) — definitiva para `GOPRIVATE`, `replace`, workspaces.
- [Buf Docs](https://buf.build/docs) — para qualquer dúvida de proto/gRPC.
- [Distroless](https://github.com/GoogleContainerTools/distroless) — imagens base.
- Para padrões arquiteturais (layout, ACL, sqlc), volte ao [arquitetura_backend.md](./arquitetura_backend.md).
