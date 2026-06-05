#!/usr/bin/env bash
# init_module.sh — cria um novo serviço Go com a estrutura padrão do time iez!.
#
# Uso: ./init_module.sh <module-path> [target-dir]
# Exemplo: ./init_module.sh github.com/Iez-Telecom/cobranca-svc ./cobranca-svc
#
# Faz:
#   1. cria a estrutura de diretórios canônica (cmd/server, api/proto/v1, internal,
#      external, sql/{queries,schema}, vendor/)
#   2. inicializa go.mod
#   3. gera cmd/server/main.go com o esqueleto padrão (run() + ldflags vars)
#   4. copia Makefile, Containerfile, buf.yaml, buf.gen.yaml de ../../exemplos/
#      (ou regera se a pasta não estiver acessível)
#   5. cria .gitignore com a política do time (vendor commitado, gen ignorado)
#   6. roda go mod tidy && go mod vendor

set -euo pipefail

MODULE="${1:?uso: $0 <module-path> [target-dir]}"
DIR="${2:-$(basename "$MODULE")}"
APP_NAME="$(basename "$MODULE")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEMPLOS_DIR="${GUIDELINES_EXEMPLOS:-$SCRIPT_DIR/../../../exemplos}"

echo ">> Criando serviço $MODULE em $DIR..."

# ============================================================
# Estrutura de diretórios (layout do time)
# ============================================================

mkdir -p "$DIR"/{cmd/server,api/proto/v1,gen,internal/{config,database,logger,observability},external,sql/{queries,schema,migrations},scripts,docs/adr}
cd "$DIR"

# ============================================================
# go.mod
# ============================================================

go mod init "$MODULE"

# ============================================================
# cmd/server/main.go (esqueleto padrão)
# ============================================================

cat > cmd/server/main.go <<'GOEOF'
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
)

// Preenchidas no link time via -ldflags "-X 'main.clientVersion=...'" (ver Makefile).
var (
	clientVersion = "dev"
	commitHash    = "unknown"
	buildDate     = "unknown"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--version" {
		fmt.Printf("%s (commit %s, built %s)\n", clientVersion, commitHash, buildDate)
		return
	}

	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := run(ctx, logger); err != nil {
		slog.Error("falha na inicialização", "err", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, logger *slog.Logger) error {
	logger.Info("iniciando serviço",
		"version", clientVersion,
		"commit", commitHash,
		"build_date", buildDate,
	)

	// TODO:
	// 1. Carregar configuração: cfg, err := config.Load()
	// 2. Criar pool de banco: pool, err := database.NewPool(ctx, cfg.DatabaseURL)
	// 3. Instanciar stores e handlers (DI explícito via construtores)
	// 4. Iniciar servidor gRPC e aguardar ctx.Done()
	// 5. Graceful shutdown

	<-ctx.Done()
	logger.Info("desligando...")
	return nil
}
GOEOF

# ============================================================
# internal/config/config.go (boilerplate de configuração)
# ============================================================

cat > internal/config/config.go <<'GOEOF'
package config

import (
	"errors"
	"os"
)

// Config contém a configuração da aplicação carregada do ambiente.
type Config struct {
	GRPCAddr    string
	HTTPAddr    string
	DatabaseURL string
	LogLevel    string
}

// Load carrega a configuração de variáveis de ambiente.
func Load() (Config, error) {
	cfg := Config{
		GRPCAddr:    getEnv("GRPC_ADDR", ":50051"),
		HTTPAddr:    getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
		LogLevel:    getEnv("LOG_LEVEL", "info"),
	}
	if cfg.DatabaseURL == "" {
		return cfg, errors.New("DATABASE_URL é obrigatório")
	}
	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
GOEOF

# ============================================================
# sqlc.yaml (na raiz, ao lado do go.mod)
# ============================================================

cat > sqlc.yaml <<'SQLCEOF'
version: "2"
sql:
  - engine: "postgresql"
    queries: "sql/queries/"
    # sqlc lê os .up.sql de migrations como schema cumulativo.
    # Alternativa: manter sql/schema/schema.sql como snapshot manual.
    schema: "sql/migrations/"
    gen:
      go:
        package: "pg_sql"
        out: "gen/sql"
        sql_package: "pgx/v5"
        emit_interface: false
        emit_pointers_for_null_types: true
        emit_json_tags: true
        emit_prepared_queries: false
        emit_exact_table_names: false
        emit_empty_slices: true
SQLCEOF

# ============================================================
# Makefile, Containerfile, buf.yaml, buf.gen.yaml
# Copiados de exemplos/ se acessível; senão, alerta para puxar manualmente.
# ============================================================

copy_or_warn() {
	local src="$EXEMPLOS_DIR/$1"
	local dst="$1"
	if [[ -f "$src" ]]; then
		cp "$src" "$dst"
		echo "   - $dst (copiado de $EXEMPLOS_DIR)"
	else
		echo "   - $dst NÃO COPIADO (não encontrei $src)"
		echo "     Copie manualmente do repositório guidelines/exemplos/$1"
	fi
}

echo ">> Copiando arquivos canônicos..."
copy_or_warn Makefile
copy_or_warn Containerfile
copy_or_warn compose.yml
copy_or_warn buf.yaml
copy_or_warn buf.gen.yaml
copy_or_warn .golangci.yml
copy_or_warn AGENTS.md

# Script de banco de dados
if [[ -f "$EXEMPLOS_DIR/scripts/db.sh" ]]; then
    cp "$EXEMPLOS_DIR/scripts/db.sh" scripts/db.sh
    chmod +x scripts/db.sh
    echo "   - scripts/db.sh (copiado e tornando executável)"
else
    echo "   - scripts/db.sh NÃO COPIADO (não encontrei $EXEMPLOS_DIR/scripts/db.sh)"
fi

# ADR template + numera o próximo como 0001 para o serviço já começar com um
if [[ -f "$EXEMPLOS_DIR/docs/adr/0000-template.md" ]]; then
	cp "$EXEMPLOS_DIR/docs/adr/0000-template.md" docs/adr/0000-template.md
	echo "   - docs/adr/0000-template.md (copiado)"
else
	echo "   - docs/adr/0000-template.md NÃO COPIADO (não encontrei em $EXEMPLOS_DIR/docs/adr/)"
fi

# ============================================================
# .gitignore (alinhado com a política: vendor commitado, gen ignorado)
# ============================================================

cat > .gitignore <<'GIEOF'
# Binários
/bin/
*.exe
*.test
*.out

# Código gerado (regerado pelo build do Containerfile e por `make generate`)
/gen/

# NÃO ignorar /vendor/ — dependências de terceiros são versionadas
# para garantir build reproduzível sem rede e auditoria via git blame

# Cobertura
coverage.txt
coverage.html

# Workspaces locais
go.work
go.work.sum

# IDE
.idea/
.vscode/

# Sistema
.DS_Store

# Configuração local (nunca commitar segredos)
.env
.env.local
*.local.yaml
GIEOF

# ============================================================
# Schema e query placeholder (para sqlc não reclamar)
# ============================================================

cat > sql/schema/schema.sql <<'SQLEOF'
-- Schema inicial. Adicione tabelas aqui ou referencie via migration tool.
-- Exemplo:
--
-- CREATE TABLE assinantes (
--     id              UUID PRIMARY KEY,
--     cpf             VARCHAR(11) NOT NULL UNIQUE,
--     nome            TEXT NOT NULL,
--     msisdn          VARCHAR(13) NOT NULL UNIQUE,
--     situacao        SMALLINT NOT NULL,
--     data_ativacao   TIMESTAMPTZ,
--     created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
--     updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- );
SQLEOF

cat > sql/queries/healthcheck.sql <<'SQLEOF'
-- name: HealthCheck :one
-- Verifica se o banco está respondendo.
SELECT 1;
SQLEOF

# ============================================================
# README.md
# ============================================================

cat > README.md <<RDEOF
# $APP_NAME

Serviço $APP_NAME — descrição do que ele faz.

## Pré-requisitos

- Go 1.25+
- buf, sqlc, podman, staticcheck (\`make tooling\`)
- PostgreSQL para rodar localmente

## Setup

\`\`\`bash
go env -w GOPRIVATE="github.com/Iez-Telecom/*"
git submodule update --init --recursive   # se houver submodule de protos
make generate                              # buf generate + sqlc generate
\`\`\`

## Desenvolvimento

\`\`\`bash
make                # lista todos os alvos
make test           # go test -race -count=1 ./...
make lint           # gofmt + go vet + staticcheck
make run            # roda localmente
\`\`\`

## Container

\`\`\`bash
make podman-build           # distroless (produção)
make podman-build-alpine    # alpine com shell (debug, tag -alpine)
\`\`\`

A imagem distroless é o default. A variante alpine só é usada em incidente
para \`kubectl exec\` — ver guidelines do time para o procedimento.

## Estrutura

\`\`\`
cmd/server/         # main: apenas wiring e inicialização
api/proto/v1/       # contratos gRPC
gen/                # código gerado (não commitado)
sql/                # queries e schema do sqlc
internal/           # código privado do serviço
  config/           # carregamento de configuração
  database/         # pool de conexão
  logger/           # configuração de log
  <feature>/        # um pacote por feature de domínio
external/           # ACL para serviços externos
vendor/             # dependências de terceiros (commitado)
\`\`\`

## Deploy

\`\`\`bash
make podman-deploy REGISTRY=registry.internal.com
\`\`\`
RDEOF

# ============================================================
# Dependências básicas (pgx, slog já está na stdlib)
# ============================================================

echo ">> Resolvendo dependências..."
go get github.com/jackc/pgx/v5@latest
go get github.com/jackc/pgx/v5/pgxpool@latest
go mod tidy
go mod vendor

echo ""
echo ">> Serviço $MODULE criado em $(pwd)"
echo ""
echo "  Próximos passos:"
echo "    cd $(pwd)"
echo "    # 1. Preencher AGENTS.md com contexto do serviço (visão, gotchas, integrações)"
echo "    # 2. Para qualquer decisão arquitetural não-óbvia, criar ADR em docs/adr/"
echo "       cp docs/adr/0000-template.md docs/adr/0001-titulo.md"
echo "    # 3. Criar repositório git e adicionar submodule de protos se aplicável:"
echo "       git init && git add . && git commit -m 'Versão inicial'"
echo "       git submodule add git@github.com:Iez-Telecom/simfonia-protos.git external/proto"
echo "    # 4. Workflow spec-first: .proto → sql/queries → testes → handler/store"
echo "       make generate && make lint && make test"
echo "       make podman-build"
