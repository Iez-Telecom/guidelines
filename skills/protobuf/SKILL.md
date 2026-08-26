---
name: protobuf
description: Use SEMPRE ao criar, revisar, documentar ou refatorar arquivos `.proto` (gRPC/protobuf). Cobre o padrão de documentação rica (o que / quando usar / o que retorna / erros em cada RPC; formato, exemplo e referência cruzada em cada campo), as regras estruturais de evolução de contrato (Request/Response dedicados por RPC, proibição de Empty e de mensagem de domínio como response, enums prefixados, dinheiro em centavos sem double), organização de arquivos, paginação por cursor, idempotência, códigos de erro gRPC, exposição REST via Envoy transcoding e o processo de revisão de protos existentes (mudanças de comentário vs. breaking changes). A documentação do proto alimenta descrições de tools MCP para agentes de IA — qualquer .proto malcomentado degrada os agentes.
---

# Padrão de Protobuf

Esta skill define **como escrever e documentar arquivos `.proto`**.
Ela tem duas metades inseparáveis:

1. **Documentação rica** — todo elemento comentado, num formato fixo.
2. **Regras estruturais** — decisões de contrato que preservam a capacidade
   de evoluir a API sem breaking changes.

A motivação completa de cada regra está em `references/diretrizes.md`
(o mesmo documento distribuído à equipe). Leia quando precisar justificar
uma regra para o usuário ou decidir um caso ambíguo. Um arquivo `.proto`
completo de exemplo, já no padrão, está em `references/exemplo-completo.proto`.

## Por que a documentação importa tanto

Os comentários do `.proto` não são decoração:

- Viram a **descrição dos tools MCP** que agentes de IA usam para decidir
  *qual* RPC chamar e *como* preencher os campos. Campo sem comentário =
  tool mal descrito = agente errando.
- Viram a documentação REST quando o serviço é exposto via transcoding.
- São o que o desenvolvedor do frontend lê no código gerado.

Trate cada comentário como se um agente de IA fosse decidir uma ação de
negócio baseado nele — porque vai.

## Formato de documentação (obrigatório, sem exceção)

### Service

Nome do service: **nome direto da feature, sem prefixo** (`Recargas`,
`Financeiro`, `Assinantes` — não `ServicoRecargas`).

```protobuf
// <Nome> expõe <quais operações, para qual área/jornada>.
//
// <O que concentra. De onde vêm os dados (sistema de origem).
// Se é somente leitura, diga. Se exige ou não autenticação, diga.
// Posição na jornada: o que vem antes e o que vem depois.>
service Financeiro { ... }
```

### RPC — quatro blocos, nesta ordem

```protobuf
// <Verbo><Objeto> <frase curta: o que faz>.
//
// Use <quando: o cenário típico na jornada do app/atendimento>.
// <Se existe RPC parecido, diga qual usar em cada caso —
//  ex: "Para o histórico completo, use ListarHistoricoFaturas.">
//
// <O que retorna em casos não óbvios: lista vazia vs erro,
//  campos que podem vir nulos, ordenação.>
//
// Erros:
// - <CODIGO_GRPC>: <condição de negócio que o dispara>.
rpc ListarFaturasAbertas(...) returns (...) {}
```

Regras do bloco:

- **"Quando usar" é o bloco mais importante** — é o que o agente de IA
  usa para escolher entre tools. Nunca omita.
- "Retorna lista vazia (não erro) se..." sempre que aplicável. A distinção
  vazio-vs-NOT_FOUND é decisão de contrato e deve estar escrita.
- Liste só erros com **semântica de negócio** (ver tabela na seção Erros).
  Não liste INTERNAL/UNAVAILABLE genéricos.
- Nome do RPC: **verbo de negócio em português** + objeto
  (`GerarPix`, `ConsultarConsumoLinha`, `ReservarNovoNumero`).
  Evite prefixos genéricos Get/Create/Update/Delete. Se a busca tem
  critério, ponha no nome: `BuscarAssinantePorCPF`, não `BuscarAssinante2`.
- Documente **pré-condições de negócio** ("só funciona se a linha está
  ATIVA") — elas viram o bloco de erros FAILED_PRECONDITION.

### Campo — o checklist dos cinco itens

Cada campo responde, no comentário, ao que for aplicável:

1. **Significado de negócio** — o que É, não o tipo. Nunca tautológico
   ("ID do cliente" é proibido; "UUID v4 do cliente no CRM Simfonia.
   Imutável." é o mínimo).
2. **Formato** — "somente dígitos (11 dígitos)", "formato YYYY-MM-DD",
   "centavos", "UUID v4".
3. **Exemplo concreto** — `Exemplo: "47999998888"`, `Exemplo: 4990 = R$ 49,90`.
   Obrigatório para qualquer campo com formato.
4. **Opcionalidade e condicionais** — "Pode ser vazio." /
   "Obrigatório quando e_sim = false e forma_entrega = 'chip em mãos';
   deve ficar vazio nos demais casos."
5. **Referência cruzada** — de onde o valor vem e para onde vai:
   "Obtenha via ListarFabricantes." /
   "Deve ser enviado no campo linha.cod_reserva de CriarContrato."
   É isso que permite a um agente de IA descobrir sozinho a ordem das
   chamadas. Sempre que um campo é produzido por um RPC e consumido por
   outro, documente **nas duas pontas**.

Dados sensíveis (PIN, PUK, credenciais, documentos): marque
explicitamente — "Dado sensível — exibir apenas mediante autenticação
do assinante; nunca registrar em logs."

### Enum

- Comentário no enum dizendo o que representa e se os valores são
  mutuamente exclusivos.
- Comentário em **cada valor**, incluindo: semântica de negócio,
  **reversibilidade** (para máquinas de estado: "Reversível pelo próprio
  assinante" / "Não reversível") e gatilho típico ("Tipicamente aplicado
  por inadimplência inicial").
- No valor zero: "Valor padrão. ... Não use em requisições."

## Regras de evolução de contrato

Estas regras existem por um único motivo: **no gRPC, mudar o tipo de
parâmetro ou retorno de um RPC é breaking change; adicionar campo a uma
mensagem não é.** Toda regra abaixo preserva a capacidade de adicionar.

1. **Um Request e um Response dedicados por RPC. Nunca compartilhados.**
   Mesmo que dois RPCs recebam hoje exatamente os mesmos campos, cada um
   tem sua mensagem. Mensagem compartilhada acopla a evolução dos dois:
   um campo novo para um vaza para o outro.
2. **Nunca `google.protobuf.Empty`** como request ou response. Crie uma
   mensagem vazia dedicada (`ListarTiposClienteRequest {}`) com comentário
   "Mensagem vazia dedicada". E para operações "void", prefira retornar
   algo útil: a entidade no novo estado e o instante de efetivação ajudam
   o frontend a atualizar a UI e o agente a confirmar o efeito.
3. **Nunca uma mensagem de domínio como response direto.** `returns
   (Cliente)` impede adicionar metadados de resposta depois. Sempre
   envelope: `LerClientePorUUIDResponse { Cliente cliente = 1; }`.
4. **Nunca um Response reusado como tipo de domínio** (ex: `repeated
   LerContratoUUIDResponse contratos`). Extraia a mensagem de domínio
   (`Contrato`) e referencie nos dois Responses.
5. **Mensagens de domínio** (`Cliente`, `Fatura`, `Linha`) **são
   reusadas à vontade** dentro do serviço — a regra 1 vale só para
   envelopes Request/Response.
6. **Dados sensíveis não pegam carona.** Credenciais (PIN/PUK, tokens)
   não viajam dentro de respostas de consulta geral. Mensagem resumida
   para o caso geral + RPC dedicado com autenticação reforçada para o
   dado sensível.

## Tipos e convenções

1. **Dinheiro nunca em `double`/`float`.** Padrão da iez!: **`int64` em
   centavos**, documentado ("Exemplo: 4990 = R$ 49,90"). `string` decimal
   ("49.90") é aceitável apenas quando o valor só transita sem cálculo.
   Um único padrão por serviço — misturar é a pior opção.
2. **Vocabulário fechado vira enum**, não string livre. Se o comentário
   diria 'Valores possíveis: "PAGO", "EM_ABERTO"...', isso é um enum.
   String livre só para texto realmente livre (nomes, descrições,
   observações). Não use `oneof` para máquina de estados que um enum
   resolve — `oneof` é para variantes de payload.
3. **Enums**: primeiro valor `= 0` com sufixo `_UNSPECIFIED` (convenção
   já vigente na base iez!) e **todos os valores prefixados com o nome
   do enum** (`SITUACAO_LINHA_ATIVA`, não `ATIVO`) — valores de enum
   proto3 compartilham o namespace do pacote e colidem entre enums.
4. **Datas e instantes**: `google.protobuf.Timestamp` (UTC) para
   instantes, `google.type.Date` para datas sem hora (vencimento,
   aniversário). Nunca string.
5. **Identificadores**: `string` com UUID v4 para IDs internos — nunca
   inteiro sequencial. `string` somente dígitos para identificadores com
   formato (CPF, CNPJ, MSISDN, ICCID), com formato e exemplo no
   comentário.
6. **Booleanos no afirmativo**: `ativo`, `inadimplente`,
   `permite_portabilidade`. Não `nao_ativo`, não `is_active`.
7. **Volumes de dados**: `int64` em bytes, documentado
   ("Exemplo: 10737418240 = 10 GiB"). Para franquias expressas em MB/GB
   no negócio, a unidade escolhida vai no nome e no comentário
   (`bonus_dados_mb`).
8. **Coleções**: `repeated <Tipo> nome_no_plural`. Listas que podem
   crescer usam paginação (ver seção Paginação).
9. **Idioma**: domínio em português (`fatura`, `linha`, `cod_reserva`,
   `situacao`), técnico em inglês (`Request`, `Response`, `uuid`,
   `page_token`, sufixos de tipo). Não traduza termos do domínio para
   inglês nem termos técnicos consagrados para português. A regra vale
   em todas as camadas: o que é `situacao` no proto é `situacao` no
   banco e na query.

## Organização de arquivos e cabeçalho

```
api/proto/v1/
  recargas.proto      # 1 arquivo por feature de negócio
  faturas.proto
  common.proto        # só tipos usados por 3+ features
```

- **Um arquivo por feature de negócio.** Versão na pasta e no package
  (`v1`), não no nome do arquivo.
- **`common.proto` só para tipos genuinamente compartilhados** (usados em
  3+ features: paginação, endereço, range de datas). Abaixo disso,
  duplique — acoplamento por tipos compartilhados é pior que duplicação
  pequena.

Cabeçalho padrão:

```protobuf
syntax = "proto3";

// Pacote do <contexto> v1. <Uma frase sobre o que contém.>
package iez.app_assinante.v1;

import "google/protobuf/timestamp.proto";
import "google/type/date.proto";          // só se houver data sem hora
import "google/api/annotations.proto";    // só nos arquivos expostos via REST

option go_package = "<modulo>/gen/go/v1;v1";
```

Importe apenas o que o arquivo usa — imports não usados podem (e devem)
ser removidos.

## Paginação

Listas que podem crescer usam **cursor opaco**, não offset numérico
(offset quebra quando a lista muda entre páginas):

```protobuf
message ListarLinhasDoAssinanteRequest {
  // UUID v4 do assinante. Obtenha via BuscarAssinantePorCPF.
  string uuid_assinante = 1;

  // Tamanho máximo da página. Default 50, máximo 200.
  int32 page_size = 2;

  // Cursor da próxima página, vindo de next_page_token de uma resposta
  // anterior. Vazio para a primeira página.
  string page_token = 3;
}

message ListarLinhasDoAssinanteResponse {
  // Linhas desta página.
  repeated Linha linhas = 1;

  // Token para a próxima página. Vazio quando não há mais páginas.
  string next_page_token = 2;
}
```

## Idempotência

Para operações que mutam estado com risco real de duplicação (retry de
cliente, retry de agente de IA), inclua `idempotency_key`:

```protobuf
// Chave de idempotência para evitar dupla execução em retry. Se duas
// requisições chegam com a mesma chave dentro da janela de deduplicação,
// a segunda retorna o resultado da primeira sem executar de novo.
// UUID v4. Recomendado em fluxos automatizados. Pode ser vazio.
string idempotency_key = 4;
```

## Erros

Erros viajam como **status gRPC**, não em campo do response. Códigos com
semântica de negócio (os que entram no bloco "Erros:" do RPC):

| Código gRPC           | Quando usar                                                    |
|-----------------------|----------------------------------------------------------------|
| `NOT_FOUND`           | Entidade referenciada não existe (assinante, linha, fatura).   |
| `ALREADY_EXISTS`      | Criar algo que já existe (CPF já cadastrado).                  |
| `INVALID_ARGUMENT`    | Validação de formato falhou (CPF inválido, MSISDN malformado). |
| `FAILED_PRECONDITION` | Estado não permite a operação (linha já ativa, fatura paga).   |
| `RESOURCE_EXHAUSTED`  | Limite de negócio atingido (máximo de linhas por CPF).         |
| `PERMISSION_DENIED`   | Autenticado, mas sem permissão para esta operação.             |
| `UNAUTHENTICATED`     | Credencial ausente ou inválida.                                |

`UNAVAILABLE` e `INTERNAL` existem, mas **não entram** na documentação
do RPC — todo RPC pode retorná-los; listar só adiciona ruído.

## Exposição REST (Envoy gRPC-JSON transcoding)

Quando (e somente quando) o RPC tem consumidor REST real, adicione
`google.api.http`:

```protobuf
// GET /v1/assinantes/{uuid}
rpc BuscarAssinantePorUUID(BuscarAssinantePorUUIDRequest)
    returns (BuscarAssinantePorUUIDResponse) {
  option (google.api.http) = { get: "/v1/assinantes/{uuid}" };
}

// POST /v1/linhas/{uuid_linha}:suspender — ação custom com :verbo
rpc SuspenderLinha(SuspenderLinhaRequest) returns (SuspenderLinhaResponse) {
  option (google.api.http) = {
    post: "/v1/linhas/{uuid_linha}:suspender"
    body: "*"
  };
}
```

Convenções de URL:

- Recursos no plural e em português: `/assinantes`, `/linhas`, `/faturas`.
- IDs em path: `/assinantes/{uuid}`.
- Ações custom com `:verbo`: `/linhas/{uuid}:suspender`,
  `/assinantes:porCpf`.
- Verbos HTTP semânticos: `GET` lê, `POST` cria/age, `PATCH` atualiza
  parcial, `DELETE` remove.
- **Não exponha todos os RPCs via REST** — só os que têm consumidor REST.
  Liste as exposições no README do serviço.

## Workflow

### Criando um proto novo

1. Leia `references/exemplo-completo.proto` antes de escrever.
2. Desenhe primeiro os RPCs como frases de negócio ("o assinante consulta
   o consumo da linha no ciclo corrente") — o nome do RPC sai da frase.
3. Escreva mensagens de domínio, depois os envelopes Request/Response.
4. Documente seguindo os formatos acima — escreva o comentário **junto**
   com o campo, nunca "depois eu documento".
5. Autorrevisão final com o checklist abaixo.

### Revisando/documentando um proto existente

1. **Separe os dois planos**: mudanças de comentário (sempre seguras,
   aplique direto) e mudanças estruturais (breaking, **não aplique** —
   liste como recomendações para uma futura v2).
2. Nunca altere nome, número de tag, tipo ou cardinalidade de campo
   existente ao "documentar". Documentar é só comentário.
3. Entregue: o arquivo com a documentação aplicada + lista separada de
   violações estruturais encontradas, ordenadas por gravidade (segurança
   primeiro, depois evolução de contrato, depois estilo).
4. Imports não usados podem ser removidos (não é breaking).

### Checklist de autorrevisão (rode antes de entregar qualquer .proto)

- [ ] Todo RPC tem os 4 blocos (o que / quando usar / retorno / erros)?
- [ ] Todo campo passa nos 5 itens (significado, formato, exemplo,
      opcionalidade, referência cruzada)?
- [ ] Nenhum comentário tautológico ("ID do cliente")?
- [ ] Nenhum Request/Response compartilhado entre RPCs?
- [ ] Nenhum `google.protobuf.Empty`?
- [ ] Nenhuma mensagem de domínio como response direto?
- [ ] Nenhum `double` carregando dinheiro?
- [ ] Enums com zero `_UNSPECIFIED` e valores prefixados?
- [ ] Campos produzidos por um RPC e consumidos por outro documentados
      nas duas pontas?
- [ ] Dados sensíveis marcados e fora de respostas de consulta geral?
- [ ] Listas que podem crescer paginadas (page_size/page_token)?
- [ ] Mutações com risco de retry têm idempotency_key?
- [ ] Annotations REST só nos RPCs com consumidor REST real?

## Referências

- `references/diretrizes.md` — documento de diretrizes da equipe, com a
  **motivação** de cada regra. Leia para justificar decisões ao usuário
  ou resolver casos que o resumo acima não cobre.
- `references/exemplo-completo.proto` — arquivo `.proto` completo no
  padrão, com serviço, RPCs, mensagens, enum, paginação e todos os tipos
  de comentário. Use como gabarito de forma e tom.
