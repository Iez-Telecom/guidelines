# ============================================================
# Variáveis derivadas
# ============================================================

MODULE           := $(shell head -n 1 go.mod | cut -d ' ' -f 2)
VERSION          := $(shell git describe --tags --always --dirty)
COMMIT           := $(shell git rev-parse --short HEAD)
BUILD_DATE       := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
VERSION_VAR_PATH := main.clientVersion

# ============================================================
# Build / container
# ============================================================

BIN_DIR        := bin
# BIN_NAME deriva do módulo: meu-servico/go.mod -> binário "meu-servico".
# Evita ter N serviços rodando como "server" em ps/top/kubectl describe.
BIN_NAME       := $(notdir $(MODULE))
PLATFORM       := linux/amd64
TARGETOS       := linux
TARGETARCH     := amd64
CONTAINER_NAME := $(BIN_NAME)
CONTAINER_TAG  := $(VERSION)

LDFLAGS := -s -w \
    -X '$(VERSION_VAR_PATH)=$(VERSION)' \
    -X 'main.commitHash=$(COMMIT)' \
    -X 'main.buildDate=$(BUILD_DATE)'

# ============================================================
# Help (default target)
# ============================================================

.DEFAULT_GOAL := help

help: ## Lista todos os alvos disponíveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	    | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ============================================================
# Geração de código
# ============================================================

generate: proto-gen sql-gen ## Gera todo o código (protobuf + sqlc)

proto-gen: ## Gera código Go a partir dos .proto
	buf generate

sql-gen: ## Gera código Go a partir das queries SQL
	sqlc generate

# ============================================================
# Build local
# ============================================================

build: ## Compila o binário para a plataforma local
	mkdir -p $(BIN_DIR)
	go build -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/$(BIN_NAME) ./cmd/server

build-linux: ## Compila o binário para Linux x86_64 (mesmo target do container)
	mkdir -p $(BIN_DIR)
	CGO_ENABLED=0 GOOS=$(TARGETOS) GOARCH=$(TARGETARCH) \
	    go build -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/$(BIN_NAME) ./cmd/server

run: ## Executa o serviço localmente
	go run -ldflags "$(LDFLAGS)" ./cmd/server

# ============================================================
# Qualidade
# ============================================================

test: ## Roda todos os testes com -race
	go test -race -count=1 ./...

lint: ## Roda golangci-lint (inclui gofmt, go vet, staticcheck e ~15 outros)
	golangci-lint run ./...

lint-fix: ## Aplica fixes automáticos onde possível (formatação, imports)
	golangci-lint run --fix ./...

tidy: ## Limpa dependências não usadas
	go mod tidy

vendor: tidy ## Atualiza vendor/ com as dependências fixadas (commitar o resultado)
	go mod vendor

# ============================================================
# Container (Podman)
#
# Duas variantes:
#   - distroless (produção, default)   -> tag: $(CONTAINER_TAG)
#   - alpine     (debug emergencial)   -> tag: $(CONTAINER_TAG)-alpine
#
# A tag -alpine deixa claro no registry e no kubectl describe pod que
# aquela imagem inclui shell — nunca deve rodar como deployment padrão.
# ============================================================

PODMAN_BUILD_ARGS := --platform $(PLATFORM) \
    -f Containerfile \
    --build-arg TARGETOS=$(TARGETOS) \
    --build-arg TARGETARCH=$(TARGETARCH) \
    --build-arg VERSION=$(VERSION) \
    --build-arg BIN_NAME=$(BIN_NAME)

podman-build: ## Constrói a imagem distroless (produção)
	podman build $(PODMAN_BUILD_ARGS) \
	    --target runtime-distroless \
	    -t $(CONTAINER_NAME):$(CONTAINER_TAG) \
	    .

podman-build-alpine: ## Constrói a imagem alpine para debug (tag -alpine)
	podman build $(PODMAN_BUILD_ARGS) \
	    --target runtime-alpine \
	    -t $(CONTAINER_NAME):$(CONTAINER_TAG)-alpine \
	    .

podman-run: podman-build ## Roda o container distroless localmente
	podman run --rm -p 8080:8080 $(CONTAINER_NAME):$(CONTAINER_TAG)

podman-run-alpine: podman-build-alpine ## Roda o container alpine (com shell, para debug)
	podman run --rm -it -p 8080:8080 $(CONTAINER_NAME):$(CONTAINER_TAG)-alpine

podman-deploy: ## Envia imagem distroless para o registry (use: make podman-deploy REGISTRY=...)
	@if [ -z "$(REGISTRY)" ]; then \
	    echo ">> Erro: defina REGISTRY (ex: REGISTRY=registry.internal.com)"; exit 1; \
	fi
	@echo ">> Enviando $(REGISTRY)/$(CONTAINER_NAME):$(CONTAINER_TAG)..."
	podman tag $(CONTAINER_NAME):$(CONTAINER_TAG) $(REGISTRY)/$(CONTAINER_NAME):$(CONTAINER_TAG)
	podman push $(REGISTRY)/$(CONTAINER_NAME):$(CONTAINER_TAG)

podman-deploy-alpine: ## Envia imagem alpine para o registry (para incidentes)
	@if [ -z "$(REGISTRY)" ]; then \
	    echo ">> Erro: defina REGISTRY (ex: REGISTRY=registry.internal.com)"; exit 1; \
	fi
	@echo ">> Enviando $(REGISTRY)/$(CONTAINER_NAME):$(CONTAINER_TAG)-alpine..."
	podman tag $(CONTAINER_NAME):$(CONTAINER_TAG)-alpine $(REGISTRY)/$(CONTAINER_NAME):$(CONTAINER_TAG)-alpine
	podman push $(REGISTRY)/$(CONTAINER_NAME):$(CONTAINER_TAG)-alpine

# ============================================================
# Swagger / OpenAPI
# ============================================================

swagger-gen: ## Gera documentação OpenAPI a partir dos protos
	mkdir -p gen/openapiv2
	buf generate grpc/cliente

swagger-up: swagger-gen ## Sobe Swagger UI com a documentação gerada
	podman run --rm -p 8080:8080 \
	    -e SWAGGER_JSON=/swagger.json \
	    -v $(PWD)/gen/openapiv2/cliente.swagger.json:/swagger.json:ro \
	    docker.io/swaggerapi/swagger-ui

# ============================================================
# Limpeza
# ============================================================

clean: ## Remove arquivos gerados (binários e código gerado)
	rm -rf $(BIN_DIR) gen/openapiv2 gen/go/v1 gen/sql

dist-clean: clean ## Limpeza total, inclusive submodules
	git submodule deinit -f external/proto && git rm -f external/proto || true
	rm -rf .git/modules/SimfoniaProtos

.PHONY: help generate proto-gen sql-gen build build-linux run test lint lint-fix tidy vendor \
        podman-build podman-build-alpine podman-run podman-run-alpine \
        podman-deploy podman-deploy-alpine \
        swagger-gen swagger-up clean dist-clean
