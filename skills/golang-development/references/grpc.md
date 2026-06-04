# gRPC e Protocol Buffers

## Stack obrigatória

- **Definição de API**: Protocol Buffers v3
- **Code generation**: `buf` (não `protoc` diretamente)
- **Framework**: `google.golang.org/grpc`

gRPC é o **padrão** para comunicação entre serviços. REST (net/http) é usado apenas para APIs públicas externas.

## Estrutura de arquivos proto

```
api/proto/v1/
├── assinantes.proto
├── contratos.proto
└── contratos_types.proto   # Opcional: quando há grande número de tipos
```

Sempre versionar os protos (`v1`, `v2`). O package protobuf segue o padrão.

### Nomenclatura em protos

- **Serviços e RPCs**: vocabulário de domínio em português. `ServicoAssinantes`, `BuscarAssinantePorMSISDN`, `CadastrarLinha`.
- **Mensagens de domínio**: português. `Assinante`, `Linha`, `Plano`, `SituacaoLinha`.
- **Sufixos técnicos**: `Request`/`Response` em inglês (convenção gRPC).
- **Campos de domínio**: `snake_case` em português. `data_ativacao`, `situacao_linha`, `valor_parcela`.
- **Campos técnicos**: em inglês. `created_at`, `updated_at`.
- **Evitar** prefixos `Get`, `Create`, `Update`, `Delete`. Usar `Buscar`, `Cadastrar`, `Atualizar`, `Cancelar`.

```protobuf
// api/proto/v1/assinantes.proto
syntax = "proto3";

package assinantes.v1;

import "google/protobuf/timestamp.proto";

option go_package = "github.com/acme/meuservico/gen/go/v1;assinantesv1";

// ServicoAssinantes gerencia operações de assinantes.
service ServicoAssinantes {
  // BuscarAssinantePorMSISDN retorna o assinante pelo número de linha.
  rpc BuscarAssinantePorMSISDN(BuscarAssinantePorMSISDNRequest)
      returns (BuscarAssinantePorMSISDNResponse);

  // CadastrarAssinante registra um novo assinante.
  rpc CadastrarAssinante(CadastrarAssinanteRequest)
      returns (CadastrarAssinanteResponse);

  // SuspenderLinhaPorInadimplencia suspende a linha do assinante inadimplente.
  rpc SuspenderLinhaPorInadimplencia(SuspenderLinhaPorInadimplenciaRequest)
      returns (SuspenderLinhaPorInadimplenciaResponse);
}

message Assinante {
  string id = 1;
  string cpf = 2;
  string nome = 3;
  string msisdn = 4;
  SituacaoLinha situacao_linha = 5;
  google.protobuf.Timestamp data_ativacao = 6;
  google.protobuf.Timestamp created_at = 7;
}

enum SituacaoLinha {
  SITUACAO_LINHA_NAO_ESPECIFICADA = 0;
  SITUACAO_LINHA_ATIVA = 1;
  SITUACAO_LINHA_SUSPENSA = 2;
  SITUACAO_LINHA_CANCELADA = 3;
  SITUACAO_LINHA_BLOQUEADA = 4;
}

message BuscarAssinantePorMSISDNRequest {
  string msisdn = 1;
}

message BuscarAssinantePorMSISDNResponse {
  Assinante assinante = 1;
}

message CadastrarAssinanteRequest {
  string cpf = 1;
  string nome = 2;
  string msisdn = 3;
}

message CadastrarAssinanteResponse {
  Assinante assinante = 1;
}

message SuspenderLinhaPorInadimplenciaRequest {
  string assinante_id = 1;
}

message SuspenderLinhaPorInadimplenciaResponse {}
```

## Configuração do buf

**Arquivos canônicos:** `../../exemplos/buf.yaml` e `../../exemplos/buf.gen.yaml`.

### buf.yaml

```yaml
version: v2

deps:
  - buf.build/googleapis/googleapis

modules:
  - path: api/proto/v1
  - path: external/proto

lint:
  use:
    - STANDARD
  except:
    - PACKAGE_VERSION_SUFFIX
    - PACKAGE_DIRECTORY_MATCH
  rpc_allow_google_protobuf_empty_requests: true
  rpc_allow_google_protobuf_empty_responses: true

breaking:
  use:
    - FILE
```

Pontos:
- **Dois módulos**: `api/proto/v1` (próprio) e `external/proto` (submodule de protos compartilhados).
- **`STANDARD`** em vez de `DEFAULT`: regras mais rigorosas.
- **Exceções de lint**:
  - `PACKAGE_VERSION_SUFFIX`: nosso schema de diretórios já tem `/v1/`; sufixo no nome do pacote duplica.
  - `PACKAGE_DIRECTORY_MATCH`: `external/proto` é submodule de terceiros, sem controle dessa correspondência.
- **`rpc_allow_google_protobuf_empty_*`**: permite RPCs com `google.protobuf.Empty` em req/resp sem precisar declarar mensagem vazia (útil em health checks).

### buf.gen.yaml

```yaml
version: v2

plugins:
  - local: protoc-gen-go
    out: gen
    opt: paths=source_relative
  - local: protoc-gen-go-grpc
    out: gen
    opt:
      - paths=source_relative
      - require_unimplemented_servers=true

inputs:
  - directory: api/proto/v1
  - directory: external/proto
```

Pontos:
- **Plugins locais** (`local:`), não remotos. Os binários `protoc-gen-go` e `protoc-gen-go-grpc` são instalados no Containerfile via `go install` com versões pinadas. Vantagens: build não depende da BSR remota; mesma versão em dev e no container.
- **Output em `gen/`** (sem subpasta `/go`).
- **`require_unimplemented_servers`** — escolha consciente:
  - `true` (default do plugin atualmente): server interface inclui método `mustEmbedUnimplementedXxxServer()`; servidor precisa embutir `UnimplementedXxxServer` que fornece defaults `Unimplemented` para todo RPC novo. Modo "forward compatible" — adicionar RPC novo no proto não quebra build, mas retorna `Unimplemented` em runtime.
  - `false`: server interface é literal; adicionar RPC novo quebra o build do servidor. Modo "strict" — preferível quando você quer falha em compile-time. Use em wrappers/proxies onde implementar todos os RPCs realmente é opcional.

### Gerar código

```bash
make generate   # internamente: buf generate
```

Código gerado vai para `gen/`. Nunca editar arquivos gerados. `/gen/` não é commitado — o build do Containerfile regera dentro do próprio builder, então o código vivo no repositório é só `vendor/` + `.proto` + `.go` próprios.

### Manutenção de dependências de proto

```bash
buf dep update      # atualiza buf.lock (commitar)
buf lint            # valida convenções
buf format -w       # formata in-place
buf breaking --against ".git#branch=main"  # falha se quebrou contrato
```

Em CI, sempre rodar `buf lint` e `buf breaking` antes do build do Go.

## Servidor gRPC

O handler fica em `internal/<feature>/handler.go`. Ele é responsável apenas por traduzir protocolo → domínio → protocolo. Lógica de negócio fica nos tipos de domínio.

```go
// internal/assinante/handler.go
package assinante

import (
    "context"
    "errors"
    "log/slog"

    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"

    assinantesv1 "github.com/acme/meuservico/gen/go/v1"
)

// Handler implementa o ServicoAssinantes via gRPC.
type Handler struct {
    assinantesv1.UnimplementedServicoAssinantesServer
    store  Store
    logger *slog.Logger
}

// NewHandler cria o handler com dependências injetadas.
func NewHandler(store Store, logger *slog.Logger) *Handler {
    return &Handler{store: store, logger: logger}
}

// BuscarAssinantePorMSISDN retorna o assinante pelo número de linha.
func (h *Handler) BuscarAssinantePorMSISDN(ctx context.Context, req *assinantesv1.BuscarAssinantePorMSISDNRequest) (*assinantesv1.BuscarAssinantePorMSISDNResponse, error) {
    if req.GetMsisdn() == "" {
        return nil, status.Error(codes.InvalidArgument, "msisdn é obrigatório")
    }

    a, err := h.store.BuscarPorMSISDN(ctx, req.GetMsisdn())
    if errors.Is(err, ErrAssinanteNaoEncontrado) {
        return nil, status.Errorf(codes.NotFound, "assinante %s não encontrado", req.GetMsisdn())
    }
    if err != nil {
        h.logger.Error("falha ao buscar assinante", "err", err, "msisdn", req.GetMsisdn())
        return nil, status.Error(codes.Internal, "erro interno")
    }

    return &assinantesv1.BuscarAssinantePorMSISDNResponse{
        Assinante: paraProtoAssinante(a),
    }, nil
}
```

## Inicialização do servidor gRPC

```go
// internal/server/grpc.go
package server

import (
    "context"
    "fmt"
    "log/slog"
    "net"

    "google.golang.org/grpc"
    "google.golang.org/grpc/reflection"
)

// RunGRPCServer inicia o servidor gRPC e gerencia shutdown graceful.
func RunGRPCServer(ctx context.Context, addr string, register func(*grpc.Server), logger *slog.Logger) error {
    lis, err := net.Listen("tcp", addr)
    if err != nil {
        return fmt.Errorf("listen %s: %w", addr, err)
    }

    srv := grpc.NewServer(
        grpc.ChainUnaryInterceptor(
            loggingInterceptor(logger),
            recoveryInterceptor(logger),
        ),
    )
    register(srv)
    reflection.Register(srv) // habilitar grpcurl/grpcui em dev

    serverErr := make(chan error, 1)
    go func() {
        logger.Info("servidor gRPC escutando", "addr", addr)
        serverErr <- srv.Serve(lis)
    }()

    select {
    case err := <-serverErr:
        return err
    case <-ctx.Done():
        logger.Info("desligando servidor gRPC")
        srv.GracefulStop()
        return nil
    }
}
```

## Interceptors (middleware gRPC)

### Logging

```go
func loggingInterceptor(logger *slog.Logger) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
        start := time.Now()
        resp, err := handler(ctx, req)

        st, _ := status.FromError(err)
        logger.Info("grpc request",
            "method", info.FullMethod,
            "code", st.Code().String(),
            "duration_ms", time.Since(start).Milliseconds(),
        )

        return resp, err
    }
}
```

### Recovery (converter panic em erro gRPC)

```go
func recoveryInterceptor(logger *slog.Logger) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp any, err error) {
        defer func() {
            if r := recover(); r != nil {
                logger.Error("panic no handler gRPC",
                    "method", info.FullMethod,
                    "panic", r,
                    "stack", string(debug.Stack()),
                )
                err = status.Error(codes.Internal, "erro interno")
            }
        }()
        return handler(ctx, req)
    }
}
```

## Códigos de status gRPC

Mapear erros de domínio para códigos gRPC corretos:

| Situação | Código gRPC |
|---|---|
| Input inválido, campo faltando | `codes.InvalidArgument` |
| Recurso não encontrado | `codes.NotFound` |
| Recurso já existe (conflito) | `codes.AlreadyExists` |
| Sem permissão | `codes.PermissionDenied` |
| Não autenticado | `codes.Unauthenticated` |
| Erro interno inesperado | `codes.Internal` |
| Serviço indisponível | `codes.Unavailable` |
| Timeout / deadline excedido | `codes.DeadlineExceeded` |

**Nunca expor detalhes internos (stack traces, nomes de tabela) nas mensagens de erro gRPC.**

## Cliente gRPC

```go
func newUserClient(ctx context.Context, addr string) (myappv1.UserServiceClient, func(), error) {
    conn, err := grpc.NewClient(addr,
        grpc.WithTransportCredentials(insecure.NewCredentials()), // TLS em prod!
    )
    if err != nil {
        return nil, nil, fmt.Errorf("conectar a %s: %w", addr, err)
    }

    cleanup := func() { conn.Close() }
    return myappv1.NewUserServiceClient(conn), cleanup, nil
}
```

Em produção, usar TLS e configurar retry policies.
