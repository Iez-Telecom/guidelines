# Containerização e Deploy

## Containerfile (não "Dockerfile")

O time usa `podman` e o arquivo chama-se `Containerfile`. Otimizado para Kubernetes.

**Arquivo canônico:** `../../exemplos/Containerfile`. Esta página resume os princípios — para copiar, use o arquivo do repositório raiz.

## Estratégia das duas variantes

Um único Containerfile com **dois stages de runtime** selecionáveis via `--target`:

| Variante | Stage | Tag resultante | Quando usar |
|---|---|---|---|
| **distroless** (default) | `runtime-distroless` | `svc:v1.2.3` | Produção. Sem shell, sem package manager, ~2 MB + binário. |
| **alpine** (opt-in) | `runtime-alpine` | `svc:v1.2.3-alpine` | Debug emergencial. Inclui `sh`, `curl`, `bind-tools` para `kubectl exec`. |

Distroless por último no Containerfile = construído por padrão quando se omite `--target`. A variante alpine exige flag explícita. O binário Go é **idêntico byte a byte** entre as duas (mesmo stage `builder`), só muda a imagem base.

O sufixo `-alpine` na tag é a única coisa que torna esse setup seguro: no `kubectl describe pod`, no registry e no `podman images`, fica óbvio quando alguém deixou a versão com shell rodando em produção.

## Princípios não-negociáveis

- **Multi-stage build**: builder separado de runtime.
- **`vendor/` commitado, copiado antes do código**: layer de dependências independente, cache reaproveitado, build sem rede.
- **Geração de código dentro do builder**: `buf dep update && buf generate` rodam no container. `/gen/` não é commitado.
- **Geradores pinados** (`buf@v1.70.0`, `protoc-gen-go@v1.36.11`, `protoc-gen-go-grpc@v1.5.1`): build reproduzível.
- **Binário estático**: `CGO_ENABLED=0 GOOS=linux GOARCH=amd64`. Roda em qualquer base sem libc.
- **`-trimpath`**: builds idênticos byte a byte entre máquinas; nada vaza sobre o filesystem do build.
- **`-ldflags "-s -w"`**: ~30% menor (strip de tabela de símbolos e DWARF). Pular em builds para profiling.
- **Versão injetada via ldflags**: `-X 'main.clientVersion=${VERSION}'` permite `--version` em produção.
- **`BIN_NAME` como build-arg**: cada serviço empacota um binário com o próprio nome (`cobranca-svc`, `assinante-svc`). Resolve "todo container chama-se `servidor`" em `kubectl describe` e ferramentas de inspeção.
- **Non-root**: distroless usa `USER nonroot:nonroot`; alpine cria `app:app`.

## Containerfile esquemático

```dockerfile
# syntax=docker/dockerfile:1.7

# Stage 1: Builder (compartilhado entre as duas variantes)
FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.26-alpine AS builder
ARG TARGETOS=linux TARGETARCH=amd64 VERSION=dev BIN_NAME=server
RUN apk add --no-cache git
RUN go install github.com/bufbuild/buf/cmd/buf@v1.70.0 \
    && go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.11 \
    && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1
WORKDIR /src
COPY go.mod go.sum ./
COPY vendor/ vendor/
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN buf dep update && buf generate
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -mod=vendor -trimpath \
        -ldflags="-s -w -X 'main.clientVersion=${VERSION}'" \
        -o /out/${BIN_NAME} ./cmd/server

# Stage 2: Alpine — VERSÃO DE DEBUG (opt-in)
FROM docker.io/library/alpine:3.20 AS runtime-alpine
ARG BIN_NAME=server
RUN apk add --no-cache ca-certificates curl bind-tools \
    && addgroup -S app && adduser -S -G app app
COPY --from=builder /out/${BIN_NAME} /usr/local/bin/${BIN_NAME}
USER app:app
EXPOSE 50051
ENV BIN_NAME=${BIN_NAME}
ENTRYPOINT exec /usr/local/bin/${BIN_NAME}

# Stage 3: Distroless — DEFAULT (produção)
FROM gcr.io/distroless/static-debian12:nonroot AS runtime-distroless
ARG BIN_NAME=server
COPY --from=builder /out/${BIN_NAME} /app
USER nonroot:nonroot
EXPOSE 50051
ENTRYPOINT ["/app"]
```

## Trade-off do ENTRYPOINT no distroless

Distroless não tem shell, então a forma `ENTRYPOINT exec /usr/local/bin/${BIN_NAME}` (shell form com interpolação) não funciona. Só exec form (`["..."]`), que é lista literal sem expansão de ARG/ENV.

Solução: o binário é copiado para `/app` (caminho fixo), `ENTRYPOINT ["/app"]`. Consequência: dentro do container distroless o binário se chama `/app` independente do serviço. A identidade fica na **tag da imagem** e nos labels do K8s — onde operadores olham mesmo. Como distroless não tem `ps`, perder o nome interno é custo barato.

Na variante alpine o ENTRYPOINT é shell form com `exec`, interpolando `${BIN_NAME}`. O `exec` substitui o sh pelo processo Go para que SIGTERM do K8s chegue até o app — sem isso, sh fica como PID 1 e o pod só morre por timeout depois de 30 s.

## Build via Makefile

```bash
make podman-build               # distroless (produção)
make podman-build-alpine        # alpine (debug, tag -alpine)
make podman-deploy REGISTRY=...         # push da distroless
make podman-deploy-alpine REGISTRY=...  # push da alpine (incidente)
```

Internamente:
```bash
podman build --target runtime-distroless \
    -t $(CONTAINER_NAME):$(CONTAINER_TAG) \
    --build-arg BIN_NAME=$(BIN_NAME) \
    --build-arg VERSION=$(VERSION) \
    ...
```

`CONTAINER_NAME` e `BIN_NAME` são ambos derivados de `$(notdir $(MODULE))` — alinhamento de ponta a ponta entre nome do serviço, imagem e binário.

## Configuração Envoy (quando necessário)

Usar Envoy como proxy quando:
- Precisa de **gRPC load balancing** (HTTP/2 precisa de L7 LB, não L4)
- Precisa de **gRPC-Web translation** (browser → Envoy → gRPC)
- Precisa de TLS termination centralizada

### Configuração básica de Envoy para gRPC

```yaml
# deploy/envoy.yaml
static_resources:
  listeners:
    - name: grpc_listener
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 8443
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: grpc_proxy
                codec_type: AUTO
                route_config:
                  name: local_route
                  virtual_hosts:
                    - name: grpc_service
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: grpc_backend
                            timeout: 30s
                http_filters:
                  - name: envoy.filters.http.grpc_web
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
                  - name: envoy.filters.http.cors
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
    - name: grpc_backend
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      typed_extension_protocol_options:
        envoy.extensions.upstreamhttp.v3.HttpProtocolOptions:
          "@type": type.googleapis.com/envoy.extensions.upstreamhttp.v3.HttpProtocolOptions
          explicit_http_config:
            http2_protocol_options: {}
      load_assignment:
        cluster_name: grpc_backend
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: cobranca-svc
                      port_value: 50051
```

## Kubernetes manifests (referência mínima)

### Deployment

```yaml
# deploy/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cobranca-svc
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cobranca-svc
  template:
    metadata:
      labels:
        app: cobranca-svc
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532  # nonroot do distroless
        fsGroup: 65532
      containers:
        - name: cobranca-svc
          image: registry.example.com/cobranca-svc:v1.2.3
          ports:
            - containerPort: 50051
              name: grpc
            - containerPort: 8080
              name: http
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          livenessProbe:
            grpc:
              port: 50051
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            grpc:
              port: 50051
            initialDelaySeconds: 5
            periodSeconds: 5
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: cobranca-svc-secrets
                  key: database-url
            - name: GRPC_ADDR
              value: ":50051"
            - name: GOMAXPROCS
              valueFrom:
                resourceFieldRef:
                  resource: limits.cpu
```

### Pontos importantes para K8s

- **`runAsNonRoot: true`** combina com a imagem distroless `nonroot` (UID 65532).
- **Health checks gRPC**: usar `grpc:` probe (K8s 1.24+), não exec/HTTP.
- **Secrets**: nunca hardcoded. Usar `secretKeyRef` ou external secrets operator.
- **Resources**: sempre definir `requests` e `limits`.
- **`GOMAXPROCS` via downward API**: sem isso, o Go enxerga todos os cores do node, não os do cgroup, e o scheduler sofre. Alternativa: importar `go.uber.org/automaxprocs` com blank import no `main.go`.
- **Migrations**: rodar como **init container** ou **Job** separado, nunca no startup do app.

## Migrations como Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cobranca-svc-migrate
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: registry.example.com/cobranca-svc:v1.2.3
          command: ["/app", "migrate", "up"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: cobranca-svc-secrets
                  key: database-url
```

Note: o `command` é `/app` (caminho fixo no distroless). Se a imagem fosse a `-alpine`, seria `/usr/local/bin/cobranca-svc`.

## Trocar para alpine em incidente

```bash
# 1. Garantir que a tag -alpine existe no registry
make podman-deploy-alpine REGISTRY=...

# 2. Trocar a imagem do deployment temporariamente
kubectl set image deployment/cobranca-svc \
    cobranca-svc=registry.example.com/cobranca-svc:v1.2.3-alpine

# 3. Investigar
kubectl exec -it deploy/cobranca-svc -- sh
# dentro do pod: ps aux, wget, nslookup, etc.

# 4. Voltar para distroless quando terminar
kubectl set image deployment/cobranca-svc \
    cobranca-svc=registry.example.com/cobranca-svc:v1.2.3
```

A regra de operação: **nenhum deployment em produção fica rodando tag `-alpine` por mais de uma janela de incidente**. Se virou permanente, é sinal de que falta observabilidade (logs/traces/metrics) — corrigir isso, não normalizar shell em produção.
