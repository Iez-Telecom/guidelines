# Padrões de Design de `.proto`

Este documento dá padrões concretos para escrever arquivos `.proto` que serão consumidos por **três alvos**:

1. Frontend, via gRPC direto
2. Sistemas legados / REST, via Envoy gRPC-JSON transcoding
3. Agentes de IA, via servidor MCP separado que traduz MCP→gRPC

A documentação do proto **é** a documentação do tool MCP. Trate cada comentário como visível para um agente de IA decidindo se chama ou não.

## Estrutura de arquivos

```
api/proto/v1/
  assinantes.proto         # 1 arquivo por feature
  faturas.proto
  portabilidade.proto
  common.proto             # tipos genuinamente compartilhados (paginação, erros)
```

- Um arquivo por feature de negócio.
- Versão na pasta (`v1/`), não no nome do arquivo.
- `common.proto` só para tipos reusados em **≥3 serviços** (paginação, formato de erro padronizado, range de datas). Quando em dúvida, duplicar — acoplamento por tipos compartilhados é pior que duplicação pequena.

## Cabeçalho de cada arquivo

```protobuf
syntax = "proto3";

package telecom.v1;

option go_package = "github.com/empresa/repo/gen/go/v1;telecomv1";

import "google/api/annotations.proto";   // necessário para REST via Envoy
import "google/protobuf/timestamp.proto"; // para datas
import "google/protobuf/empty.proto";    // raramente — preferir Response próprio
```

Notas:
- `package telecom.v1` mantém todas as features sob o mesmo namespace gRPC para simplificar imports cruzados.
- `go_package` deve seguir o padrão da equipe Go (a equipe de implementação configura).
- `google.api.annotations` só importar nos arquivos que de fato usam REST transcoding.

## Convenção de idioma aplicada ao `.proto`

| Elemento                | Idioma                      | Exemplo                              |
|-------------------------|-----------------------------|---------------------------------------|
| `service`               | `Servico<Feature>`, PT      | `ServicoAssinantes`                   |
| `rpc` (verbo de negócio)| Português                   | `BuscarAssinantePorMSISDN`            |
| `message` (domínio)     | Português                   | `Assinante`, `Linha`, `Plano`         |
| `message` (técnico)     | PT_<Operação> + `Request`/`Response` | `BuscarAssinantePorMSISDNRequest`  |
| Campos do message       | snake_case em português     | `assinante_id`, `data_ativacao`       |
| `enum`                  | Português                   | `SituacaoLinha`                       |
| Valores de enum         | UPPER_SNAKE_CASE, PT        | `SITUACAO_LINHA_ATIVA`                |
| Campos genéricos técnicos | snake_case em inglês     | `created_at`, `updated_at` (raros no proto, mais comuns no SQL) |

Os sufixos `Request` e `Response` ficam em inglês porque são convenção técnica do gRPC.

## Documentação obrigatória

Cada elemento do `.proto` tem comentário, sem exceção. Razão: a doc do proto vira a descrição do tool MCP que o agente de IA enxerga.

**Service e RPCs:**

```protobuf
// ServicoAssinantes gerencia assinantes (pessoas físicas e jurídicas com
// contrato com a operadora) e suas linhas móveis. Use este serviço para
// operações de cadastro, consulta e mudança de situação cadastral.
service ServicoAssinantes {
  // BuscarAssinantePorMSISDN retorna o assinante dono de uma linha móvel,
  // identificada pelo MSISDN (número do telefone com código do país e DDD).
  //
  // Use quando você tem o número de telefone do cliente (ex: ele ligou no
  // call center) e precisa identificar quem é. Retorna o assinante e a lista
  // de todas as linhas dele (não só a que foi pesquisada).
  //
  // Retorna NOT_FOUND se nenhum assinante tem essa linha ativa.
  rpc BuscarAssinantePorMSISDN(BuscarAssinantePorMSISDNRequest)
      returns (BuscarAssinantePorMSISDNResponse) {
    option (google.api.http) = {
      get: "/v1/assinantes:porMsisdn"
    };
  }
}
```

**Padrão de comentário para RPC:**

1. Frase curta dizendo **o que** faz.
2. **Quando** usar (cenário típico). Crítico para o agente de IA.
3. **O que retorna** quando há ambiguidade (lista, agregado, etc.).
4. **Erros** relevantes do domínio (NOT_FOUND, FAILED_PRECONDITION, etc.).

**Messages e campos:**

```protobuf
// Assinante representa uma pessoa física ou jurídica com contrato com a
// operadora. Um mesmo assinante pode ter múltiplas linhas móveis e pontos
// de fibra.
message Assinante {
  // ID interno do assinante. UUID. Imutável após cadastro.
  string id = 1;

  // CPF (pessoa física, 11 dígitos) OU CNPJ (pessoa jurídica, 14 dígitos),
  // apenas dígitos, sem formatação. Único na base.
  // Exemplo: "12345678901" (CPF) ou "12345678000190" (CNPJ).
  string cpf_ou_cnpj = 2;

  // Nome completo (pessoa física) ou razão social (pessoa jurídica).
  string nome = 3;

  // Email para notificações e segunda via de boleto. Pode ser vazio.
  string email = 4;

  // Data em que o assinante foi cadastrado na operadora. Imutável.
  google.protobuf.Timestamp data_cadastro = 5;

  // Situação cadastral atual. Veja SituacaoCadastral para semântica de cada
  // valor.
  SituacaoCadastral situacao_cadastral = 6;
}
```

**Padrão de comentário para campo:**
- Significado de negócio (não "string id" — diz **o que é** esse id).
- Formato esperado quando aplicável (formato de CPF, MSISDN, código de barras).
- Exemplo concreto para campos com formato.
- Se pode ser vazio/null, dizer.
- Se referencia outro tipo/enum, apontar para a documentação do tipo.

## Tipos padrão

### Identificadores

- IDs internos: `string` contendo UUID. Não usar `int64` ou `int32` sequencial.
- IDs externos com formato (CPF, MSISDN, ICCID): `string`, **apenas dígitos**, sem formatação, com formato documentado no comentário.

### Datas e timestamps

- Use `google.protobuf.Timestamp` para tudo que é instante no tempo (data + hora + timezone). UTC sempre.
- Para datas sem horário (data de vencimento de boleto, data de aniversário), use também `Timestamp` com hora 00:00:00 UTC e documente. Alternativa: `google.type.Date` se a equipe tem disponibilidade do tipo.
- Não usar `string` para datas — gera confusão de formato.

### Dinheiro

Protobuf **não tem** tipo decimal nativo. Opções, em ordem de preferência:

**1. `string` com formato documentado (padrão recomendado):**

```protobuf
// Valor mensal do plano em reais, com 2 casas decimais. Exemplo: "89.90".
string valor_mensal = 1;
```

A equipe de implementação converte para `decimal.Decimal` (Go) ou `BigDecimal` equivalente. Trade-off: chama atenção para o cuidado com decimal e evita corrupção por float.

**2. `int64` representando centavos** (quando há cálculos intensivos no servidor):

```protobuf
// Valor mensal do plano em centavos. Exemplo: 8990 = R$ 89,90.
int64 valor_mensal_centavos = 1;
```

Use **um único padrão por serviço**. Mistura é a pior opção.

### Bytes / volumes de dados

- Franquia de dados: `int64` em **bytes**. Documente sempre.

```protobuf
// Franquia mensal de dados em bytes. Exemplo: 10737418240 = 10 GiB.
int64 franquia_dados_bytes = 1;
```

### Booleanos

- Nome do campo no afirmativo: `ativo`, `inadimplente`, `permite_portabilidade`. Não usar `nao_ativo` ou `is_active`.

### Coleções

- `repeated <tipo> nome_plural = N`. Exemplo: `repeated Linha linhas = 5;`.
- Para coleções que podem ser grandes, use paginação (ver seção abaixo).
- Slices vazios são representados como `[]`, não como `null`. Configure `sqlc` com `emit_empty_slices: true` para casar.

## Enums

**Regras invioláveis:**

1. **Primeiro valor sempre é `_NAO_ESPECIFICADO = 0`** (ou `_NAO_ESPECIFICADA` quando o nome do enum é feminino). É a regra do protobuf: o zero é "não definido".
2. Valores em **UPPER_SNAKE_CASE**, prefixados com o nome do enum.
3. Comentário em **cada valor** explicando a semântica de negócio.
4. Enum em **português** (vocabulário do domínio).

```protobuf
// SituacaoLinha representa o estado operacional de uma linha móvel.
// Estados são mutuamente exclusivos.
enum SituacaoLinha {
  // Valor não definido. Não use em requisições.
  SITUACAO_LINHA_NAO_ESPECIFICADA = 0;

  // Linha ativa, usável normalmente para chamadas, dados e SMS.
  SITUACAO_LINHA_ATIVA = 1;

  // Suspensão temporária a pedido do cliente (ex: viagem, perda do chip
  // com expectativa de recuperar). Reversível pelo próprio cliente.
  SITUACAO_LINHA_SUSPENSA = 2;

  // Bloqueio operacional (inadimplência, fraude, roubo confirmado).
  // Reversibilidade depende do motivo.
  SITUACAO_LINHA_BLOQUEADA = 3;

  // Linha cancelada permanentemente. Não reativável (cliente teria que
  // contratar nova linha).
  SITUACAO_LINHA_CANCELADA = 4;

  // Portabilidade em andamento (saindo ou recebendo). Linha pode estar
  // operacional ou não, dependendo da fase.
  SITUACAO_LINHA_PORTABILIDADE_EM_ANDAMENTO = 5;
}
```

**Não usar:** `oneof` para representar estados mutuamente exclusivos quando um enum simples resolve. `oneof` é para variantes de payload, não para máquinas de estado.

## Request / Response

### Padrão geral

Sempre crie `Request` e `Response` próprios, mesmo para RPCs aparentemente simples. Razão: facilita adicionar campos depois sem quebrar.

```protobuf
message BuscarAssinantePorMSISDNRequest {
  // MSISDN da linha, apenas dígitos com código do país e DDD.
  // Exemplo: "5511999998888".
  string msisdn = 1;
}

message BuscarAssinantePorMSISDNResponse {
  // Dados do assinante encontrado.
  Assinante assinante = 1;

  // Todas as linhas móveis associadas a este assinante (não só a que foi
  // pesquisada). Pode estar vazia se o assinante só tem fibra.
  repeated Linha linhas = 2;
}
```

### Evitar `google.protobuf.Empty`

Mesmo para operações "void", retorne algo útil:

```protobuf
// Ruim:
rpc SuspenderLinha(SuspenderLinhaRequest) returns (google.protobuf.Empty);

// Bom: retorna a linha no novo estado, útil pro frontend atualizar UI e
// pro agente confirmar que a operação teve efeito.
message SuspenderLinhaResponse {
  // Linha após a suspensão, com situacao atualizada.
  Linha linha = 1;

  // Momento exato em que a suspensão foi efetivada.
  google.protobuf.Timestamp efetivada_em = 2;
}
rpc SuspenderLinha(SuspenderLinhaRequest) returns (SuspenderLinhaResponse);
```

### Idempotência

Para operações que mutam estado, considere campo `idempotency_key` quando há risco real de duplicação (retry de cliente, retry de agente de IA). O servidor de implementação usa para deduplicar.

```protobuf
message RegistrarRecargaRequest {
  // ID da linha que vai receber a recarga.
  string linha_id = 1;

  // Valor da recarga em reais, com 2 casas. Exemplo: "20.00".
  string valor = 2;

  // Canal de origem. Veja CanalRecarga.
  CanalRecarga canal = 3;

  // Chave de idempotência. Se duas requisições chegam com o mesmo valor
  // dentro de 24h, a segunda retorna o resultado da primeira sem executar
  // de novo. UUID ou similar. Recomendado para retries seguros.
  string idempotency_key = 4;
}
```

## Paginação

Para listas que podem crescer, use cursor-based:

```protobuf
message ListarLinhasDoAssinanteRequest {
  // ID do assinante.
  string assinante_id = 1;

  // Tamanho máximo da página. Default 50, máximo 200.
  int32 page_size = 2;

  // Cursor para próxima página. Vazio para primeira página.
  // Vem de next_page_token de uma resposta anterior.
  string page_token = 3;
}

message ListarLinhasDoAssinanteResponse {
  // Linhas nesta página.
  repeated Linha linhas = 1;

  // Token para próxima página. Vazio se não há mais páginas.
  string next_page_token = 2;
}
```

Cursor opaco (string) é melhor que offset numérico para listas que mudam.

## Erros

Use os códigos de status gRPC apropriados, não retorne erro no corpo:

| Código gRPC          | Quando usar                                                   |
|----------------------|---------------------------------------------------------------|
| `NOT_FOUND`          | Entidade não existe (assinante, linha, fatura).               |
| `ALREADY_EXISTS`     | Tentativa de criar algo que já existe (CPF já cadastrado).    |
| `INVALID_ARGUMENT`   | Validação de formato falhou (CPF inválido, MSISDN malformado).|
| `FAILED_PRECONDITION`| Estado não permite a operação (linha já ativa, fatura paga).  |
| `PERMISSION_DENIED`  | Token de agente sem permissão para esta operação.             |
| `UNAUTHENTICATED`    | Token de agente ausente ou inválido.                          |
| `UNAVAILABLE`        | Dependência externa fora do ar.                               |
| `INTERNAL`           | Bug, falha não esperada.                                      |

Para detalhes adicionais do erro, use `google.rpc.ErrorInfo` (a equipe de implementação anexa via metadata). No `.proto`, documente nos comentários do RPC quais erros são esperados:

```protobuf
// AtivarLinha ativa uma linha previamente cadastrada mas ainda não ativa.
//
// Erros:
// - NOT_FOUND: a linha não existe.
// - FAILED_PRECONDITION: a linha já está em situação diferente de
//   AGUARDANDO_ATIVACAO (ex: já ativa, cancelada).
// - INVALID_ARGUMENT: o ICCID informado não corresponde ao que está
//   registrado para a linha.
rpc AtivarLinha(AtivarLinhaRequest) returns (AtivarLinhaResponse);
```

## Annotations para REST (Envoy gRPC-JSON transcoding)

Quando o RPC precisa ser exposto via REST, adicione `google.api.http`:

```protobuf
import "google/api/annotations.proto";

service ServicoAssinantes {
  // GET /v1/assinantes:porMsisdn?msisdn=5511999998888
  rpc BuscarAssinantePorMSISDN(BuscarAssinantePorMSISDNRequest)
      returns (BuscarAssinantePorMSISDNResponse) {
    option (google.api.http) = {
      get: "/v1/assinantes:porMsisdn"
    };
  }

  // GET /v1/assinantes/{id}
  rpc BuscarAssinantePorID(BuscarAssinantePorIDRequest)
      returns (BuscarAssinantePorIDResponse) {
    option (google.api.http) = {
      get: "/v1/assinantes/{id}"
    };
  }

  // POST /v1/assinantes
  // body = CadastrarAssinanteRequest
  rpc CadastrarAssinante(CadastrarAssinanteRequest)
      returns (CadastrarAssinanteResponse) {
    option (google.api.http) = {
      post: "/v1/assinantes"
      body: "*"
    };
  }

  // POST /v1/assinantes/{assinante_id}/linhas/{linha_id}:suspender
  // body = { "motivo": "..." }
  rpc SuspenderLinha(SuspenderLinhaRequest) returns (SuspenderLinhaResponse) {
    option (google.api.http) = {
      post: "/v1/assinantes/{assinante_id}/linhas/{linha_id}:suspender"
      body: "*"
    };
  }
}
```

**Convenções de URL:**

- Recursos no plural: `/assinantes`, `/linhas`, `/faturas`.
- IDs em path: `/assinantes/{id}`.
- Ações custom usam `:verbo`: `/linhas/{id}:suspender`, `/assinantes:porMsisdn`.
- Verbos HTTP semânticos: `GET` lê, `POST` cria/age, `PATCH` atualiza parcial, `PUT` substitui, `DELETE` remove.
- Português nos nomes de recurso e nas ações custom — alinhado com a regra de idioma.

**Não exponha todos os RPCs via REST.** Só os que têm consumidor REST real. Listar as exposições no README do serviço deixa explícito qual é a superfície REST.

## Documentação para MCP

O servidor MCP gera tools baseado nos RPCs + nas mensagens. Quanto melhor a doc do proto, melhor o agente decide quando chamar e como preencher.

**Checklist por RPC que deve virar tool MCP:**

- [ ] Comentário do RPC diz **o que** faz, **quando** usar, **o que** retorna.
- [ ] Erros relevantes do domínio listados.
- [ ] Cada campo do `Request` tem comentário com formato e exemplo.
- [ ] Campos opcionais explicitamente marcados como "Pode ser vazio".
- [ ] Para enums, documentação de cada valor existe (não só do enum como um todo).
- [ ] Pré-condições de negócio documentadas ("só funciona se linha ATIVA").

**Anti-padrão**: comentário tautológico.

```protobuf
// Ruim:
// ID do assinante.
string assinante_id = 1;

// Bom:
// ID interno do assinante (UUID). Use ListarAssinantes ou
// BuscarAssinantePorCPF se você não tiver esse ID.
string assinante_id = 1;
```

O segundo dá ao agente uma dica de **como obter** o campo se ele não tem.

## Exemplo completo: `assinantes.proto`

```protobuf
syntax = "proto3";

package telecom.v1;

option go_package = "github.com/empresa/telecom/gen/go/v1;telecomv1";

import "google/api/annotations.proto";
import "google/protobuf/timestamp.proto";

// ServicoAssinantes gerencia assinantes (pessoas físicas e jurídicas com
// contrato com a operadora) e oferece consulta agregada do contexto do
// assinante. Não gerencia linhas, faturas ou recargas — esses estão em
// seus próprios serviços.
service ServicoAssinantes {
  // BuscarAssinantePorID retorna o assinante pelo seu ID interno.
  // Use quando você já tem o ID (ex: navegando de uma fatura).
  //
  // Erros:
  // - NOT_FOUND: assinante não existe.
  rpc BuscarAssinantePorID(BuscarAssinantePorIDRequest)
      returns (BuscarAssinantePorIDResponse) {
    option (google.api.http) = {
      get: "/v1/assinantes/{id}"
    };
  }

  // BuscarAssinantePorCPF retorna o assinante pelo CPF ou CNPJ.
  // Use quando o cliente se identifica no atendimento.
  //
  // Erros:
  // - NOT_FOUND: nenhum assinante com esse CPF/CNPJ.
  // - INVALID_ARGUMENT: formato do CPF/CNPJ inválido.
  rpc BuscarAssinantePorCPF(BuscarAssinantePorCPFRequest)
      returns (BuscarAssinantePorCPFResponse) {
    option (google.api.http) = {
      get: "/v1/assinantes:porCpf"
    };
  }

  // CadastrarAssinante cria um novo assinante. Pré-cadastro: o assinante
  // ainda não tem linhas nem pontos — esses são criados depois pelos
  // serviços de Linhas e Pontos.
  //
  // Erros:
  // - ALREADY_EXISTS: já existe assinante com esse CPF/CNPJ.
  // - INVALID_ARGUMENT: CPF/CNPJ inválido ou nome vazio.
  rpc CadastrarAssinante(CadastrarAssinanteRequest)
      returns (CadastrarAssinanteResponse) {
    option (google.api.http) = {
      post: "/v1/assinantes"
      body: "*"
    };
  }
}

// Assinante representa uma pessoa física ou jurídica com contrato com a
// operadora. Um mesmo assinante pode ter múltiplas linhas móveis e pontos
// de fibra (modelados em serviços separados).
message Assinante {
  // ID interno do assinante (UUID). Imutável após cadastro.
  string id = 1;

  // CPF (pessoa física, 11 dígitos) ou CNPJ (pessoa jurídica, 14 dígitos).
  // Apenas dígitos, sem formatação. Único na base.
  // Exemplo: "12345678901" (CPF) ou "12345678000190" (CNPJ).
  string cpf_ou_cnpj = 2;

  // Tipo da pessoa. Determina formato do cpf_ou_cnpj.
  TipoPessoa tipo_pessoa = 3;

  // Nome completo (pessoa física) ou razão social (pessoa jurídica).
  string nome = 4;

  // Email para notificações e segunda via de boleto. Pode ser vazio.
  string email = 5;

  // Telefone de contato (não é a linha do serviço — é o contato pra falar
  // com o assinante, pode ser de outra operadora ou fixo).
  // Formato MSISDN: dígitos com código do país e DDD.
  // Pode ser vazio. Exemplo: "5511988887777".
  string telefone_contato = 6;

  // Data em que o assinante foi cadastrado. Imutável.
  google.protobuf.Timestamp data_cadastro = 7;

  // Situação cadastral atual.
  SituacaoCadastral situacao_cadastral = 8;
}

// TipoPessoa distingue pessoa física de pessoa jurídica.
enum TipoPessoa {
  TIPO_PESSOA_NAO_ESPECIFICADO = 0;

  // Pessoa física, identificada por CPF.
  TIPO_PESSOA_FISICA = 1;

  // Pessoa jurídica (empresa), identificada por CNPJ.
  TIPO_PESSOA_JURIDICA = 2;
}

// SituacaoCadastral representa o estado cadastral do assinante na operadora.
enum SituacaoCadastral {
  SITUACAO_CADASTRAL_NAO_ESPECIFICADA = 0;

  // Cadastro ativo, assinante pode contratar serviços.
  SITUACAO_CADASTRAL_ATIVA = 1;

  // Cadastro inativo, assinante saiu da base (todos os serviços cancelados).
  SITUACAO_CADASTRAL_INATIVA = 2;

  // Bloqueio cadastral (fraude confirmada, restrição legal). Impede
  // contratação de novos serviços.
  SITUACAO_CADASTRAL_BLOQUEADA = 3;

  // Em análise (cadastro novo aguardando validação de documentos).
  SITUACAO_CADASTRAL_EM_ANALISE = 4;
}

message BuscarAssinantePorIDRequest {
  // ID interno do assinante (UUID).
  string id = 1;
}

message BuscarAssinantePorIDResponse {
  // Assinante encontrado.
  Assinante assinante = 1;
}

message BuscarAssinantePorCPFRequest {
  // CPF ou CNPJ, apenas dígitos, sem formatação.
  // Exemplo: "12345678901".
  string cpf_ou_cnpj = 1;
}

message BuscarAssinantePorCPFResponse {
  // Assinante encontrado.
  Assinante assinante = 1;
}

message CadastrarAssinanteRequest {
  // CPF ou CNPJ, apenas dígitos, sem formatação. Único na base.
  string cpf_ou_cnpj = 1;

  // Tipo da pessoa. Deve casar com o formato de cpf_ou_cnpj.
  TipoPessoa tipo_pessoa = 2;

  // Nome ou razão social. Não pode ser vazio.
  string nome = 3;

  // Email para notificações. Opcional.
  string email = 4;

  // Telefone de contato (MSISDN). Opcional.
  string telefone_contato = 5;

  // Chave de idempotência para evitar duplo cadastro em retry. Opcional
  // mas recomendado em fluxos automatizados (agentes de IA).
  string idempotency_key = 6;
}

message CadastrarAssinanteResponse {
  // Assinante recém-cadastrado, já com ID gerado e data_cadastro definida.
  // situacao_cadastral começa em EM_ANALISE.
  Assinante assinante = 1;
}
```

## Quando usar `common.proto`

Tipos que valem viver em `common.proto`:

- **Paginação**: `PageRequest`, `PageResponse` (ou só os campos `page_size`, `page_token`, `next_page_token`).
- **Dinheiro padronizado**: se a equipe quiser um tipo `Dinheiro` com `valor` (string) e `moeda` (string, default "BRL").
- **Endereço**: usado por assinante, ponto de fibra, e potencialmente cobrança.
- **Range de datas**: `RangeDatas { Timestamp inicio; Timestamp fim; }`.
- **Formato de erro estruturado**: se a equipe padronizar erros com `Erro { codigo; mensagem; detalhes; }`.

Importe `common.proto` nos arquivos de feature:

```protobuf
import "v1/common.proto";

message Assinante {
  // ...
  telecom.v1.Endereco endereco_cobranca = 9;
}
```

Não exagere — se algo está em `common.proto` mas é usado em 1 ou 2 serviços, considere duplicar.
