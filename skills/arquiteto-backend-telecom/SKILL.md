---
name: arquiteto-backend-telecom
description: Use SEMPRE ao desenhar contratos gRPC (`.proto`) ou schema/queries SQL (sqlc) para serviços backend de operadora de telecom brasileira de porte médio (banda larga fibra + móvel 4G/5G), nas áreas de Vendas e Atendimento. Dispare em pedidos como "criar serviço", "novo .proto", "schema do banco", "expor RPC via REST com Envoy", "tool MCP que chama backend", "como modelar assinante/linha/plano/fatura/recarga/portabilidade", "endpoint para o frontend", "queries sqlc", "como nomear esse campo no proto", "RPC agregador ou múltiplas chamadas", mesmo sem o usuário mencionar "arquitetura". A skill cobre convenção de idioma (domínio em português, técnico em inglês via DDD/Linguagem Ubíqua), padrões de `.proto` para os 3 consumidores (gRPC direto do frontend, REST via Envoy gRPC-JSON transcoding, agentes de IA via servidor MCP separado), decisão de granularidade RPCs vs tools MCP, e padrões de schema PostgreSQL alinhados com sqlc e pgx/v5.
---

# Arquiteto de Backend — Operadora de Telecomunicações

Esta skill apoia o desenho de contratos gRPC (`.proto`) e schema/queries SQL para serviços backend de uma operadora de telecomunicações brasileira de porte médio. Produtos: **banda larga via fibra óptica** e **telefonia móvel 4G/5G**. Áreas atendidas: **Vendas** (aquisição, ofertas, contratação) e **Atendimento ao Cliente** (suporte, mudanças contratuais, cobrança).

## Escopo: o que produz e o que NÃO produz

**Produz:**
- Arquivos `.proto` (serviços, RPCs, mensagens, enums) com documentação rica em **todos** os campos
- Schema PostgreSQL (`sql/schema/*.sql`) compatível com `sqlc` + `pgx/v5`
- Queries SQL nomeadas (`sql/queries/*.sql`) para o `sqlc` gerar tipos e funções
- Decisões arquiteturais escritas em prosa curta (registradas no README do serviço)

**Não produz:**
- Código Go de handlers, stores, services — responsabilidade da equipe de implementação
- Configuração do Envoy — responsabilidade da equipe de plataforma
- Código do servidor MCP — responsabilidade da equipe que mantém o MCP gateway

O motivo do recorte: o arquiteto desenha **contrato** e **modelo de dados**. Implementação fica com quem implementa. Mas o `.proto` e o SQL são pensados sabendo que os alvos finais são **Go** (via `sqlc` e `protoc-gen-go`), **Envoy gRPC-JSON transcoding** (para REST) e **servidor MCP** (para agentes de IA).

## Os três consumidores do `.proto`

Cada `.proto` produzido pela skill é consumido por:

1. **Frontend**, via gRPC direto (TypeScript com connect-web ou similar).
2. **Sistemas legados / REST**, via Envoy fazendo gRPC-JSON transcoding (annotations `google.api.http` no `.proto`).
3. **Agentes de IA**, via **servidor MCP separado** que recebe chamadas MCP e traduz para gRPC. Autenticação atualmente via **token de agente passado como metadata gRPC** (futuramente mTLS).

Implicação importante: **a documentação do `.proto` (comentários sobre RPCs, mensagens e campos) é o que o servidor MCP usa para gerar as descrições dos tools que o agente de IA enxerga.** Portanto:

- Toda mensagem e todo campo tem comentário descritivo, em português, voltado ao significado de negócio.
- Comentários de RPCs dizem **quando usar** aquele RPC, não só o que ele faz — o agente decide chamar baseado nessa descrição.
- Quando o campo tem formato específico (MSISDN, CPF, ICCID, código de barras de boleto), o comentário inclui exemplo.
- Quando existe pré-condição de negócio (ex: "só funciona se linha estiver ativa"), o comentário diz.

## Stack e contexto

- **Linguagem do backend**: Go (não escrevemos código nesta skill, mas o `.proto` e o SQL têm que gerar Go limpo via `protoc` e `sqlc`).
- **Banco**: PostgreSQL, acessado via `pgx/v5`, com `sqlc` gerando tipos e funções de query (`emit_pointers_for_null_types: true`, `emit_json_tags: true`).
- **Comunicação entre serviços**: gRPC síncrono é o padrão. Eventos só onde justificado (dados de referência que mudam pouco, ex: catálogo de planos, cidades atendidas).
- **Exposição REST**: Envoy gRPC-JSON transcoding, configurado pela equipe de plataforma a partir das annotations no `.proto`.
- **MCP**: servidor separado que faz tradução MCP→gRPC.
- **Escala**: porte médio. **Não otimizar para problemas que não temos** (sharding, cache em múltiplas camadas, circuit breakers complexos). Priorizar simplicidade e clareza.

## Regra de idioma (central, sem exceção)

**Domínio em português. Técnico em inglês.**

- **Domínio (português):** `Assinante`, `Linha`, `Plano`, `Fatura`, `Recarga`, `Portabilidade`, `assinante_id`, `data_ativacao`, `situacao_cadastral`, `valor_mensal`, `franquia_dados`. Acrônimos do domínio (MSISDN, ICCID, IMEI, CPF, CNPJ, CEP, DDD) mantêm a forma original.
- **Técnico (inglês):** `Request`, `Response`, `service`, `rpc`, `message`, `enum`, `id`, `created_at`, `updated_at`, `pgxpool`, `context`, `error`.

A regra se aplica **em todas as camadas, sem exceção**: nome do serviço, nome do RPC, nome da mensagem, nome do campo do proto, nome da tabela, nome da coluna, valores do enum, nome da query do `sqlc`. Quebrar essa consistência em uma camada destrói o benefício da Linguagem Ubíqua.

**Casos limítrofes recorrentes:**

- `assinante` (PT) ≠ "subscriber/customer" — **NÃO traduzir**. Cliente do call center fala "assinante".
- `linha` (PT) — número de telefone móvel. **NÃO traduzir** para "line" ou "phoneNumber".
- `fatura`, `boleto`, `recarga` — não têm equivalente exato em inglês; deixar como está.
- `cobranca` (PT) ≠ "billing" — é o processo específico de tentar receber valor em aberto, com regras do nosso negócio.
- `bloqueio` ≠ `suspensao` — são operações distintas sobre a linha, ambas em português, sem traduzir.
- `Request` e `Response` são sufixos técnicos do gRPC, ficam em inglês.

A justificativa completa (em DDD / Linguagem Ubíqua) está em `references/convencao-idioma.md`. Os exemplos detalhados em Go, TypeScript, protobuf e SQL também estão lá.

## Princípios arquiteturais (destilados para uso operacional)

O documento humano completo está em `references/arquitetura.md`. Os pontos que afetam diretamente o que esta skill produz:

**1. Cada serviço é dono dos próprios dados.** O schema SQL de um serviço não é compartilhado com outro serviço. Outros serviços leem por gRPC, não por SQL direto. Isso significa que se duas tabelas pertencem a serviços diferentes, **não** crie FK entre elas — a referência é lógica, validada na aplicação.

**2. Organização por feature.** Um `.proto` típico cobre uma feature (assinantes, faturas, portabilidade) e tem seus tipos próprios. Não crie um `proto/tipos_globais.proto` — duplicar tipos pequenos é melhor que acoplar serviços por tipos compartilhados.
- Exceção limitada: paginação, formato de erro padronizado, ou tipos comuns reusados em ≥3 serviços podem viver em `api/proto/v1/common.proto`.

**3. ACL na fronteira com sistemas externos e com serviços internos de modelo diferente.** Quando o serviço chama uma API do governo (portabilidade, Receita Federal), um ERP legado, ou um serviço interno cujo modelo é diferente do seu, o `.proto` que você desenha expressa o domínio **do seu lado**, não o do sistema externo. A tradução para o vocabulário do externo é problema do implementador no wrapper `external/`. Esta skill desenha o lado de cá da fronteira.

**4. Sem hiperescala.** Não desenhar para problemas que não temos. Sem sharding, sem prefixos de partição manuais em IDs, sem campos `shard_key`. Cache local com TTL é suficiente para dados de referência. Se o agente humano insistir em precisar de algo desse tipo, questione antes de produzir.

**5. Versionamento de proto.** Arquivos vivem em `api/proto/v1/`. Mudanças aditivas (novos campos com tag livre, novos RPCs, novos enum values com número não usado) são seguras. Remover ou renomear campo exige `v2/` e migração coordenada.

## Workflow padrão: novo serviço

Quando o usuário pede "criar serviço X" ou "novo .proto para Y", o roteiro é:

### 1. Entender o domínio

- Quais entidades o serviço é dono? (geralmente 1-3 entidades relacionadas)
- A entidade já existe em outro serviço? Se sim, possivelmente é caso de ACL ou consumo via gRPC, não de novo serviço.
- Quais operações o frontend precisa? E os agentes de IA? E o REST legado (se houver)?
- Banda larga fibra e móvel 4G/5G têm diferenças relevantes — ver `references/dominio-telecom.md`.

Se a entidade for clássica de telecom (assinante, linha, plano, fatura, recarga, portabilidade), `references/dominio-telecom.md` já tem definição, atributos típicos e operações esperadas.

### 2. Desenhar o(s) `.proto`

Padrões concretos (tipos, enums, paginação, erros, annotations `google.api.http`, documentação para MCP, exemplos completos) em `references/proto-design.md`. Pontos críticos:

- Tipos de domínio em mensagens próprias (`Assinante`, `Linha`, `Plano`) — todas com documentação rica em cada campo.
- Enums **sempre** com `_NAO_ESPECIFICADA = 0` ou `_NAO_ESPECIFICADO = 0` como primeiro valor (padrão protobuf — o zero deve significar "não definido").
- Serviço com nome `Servico<Feature>` (ex: `ServicoAssinantes`, `ServicoFaturas`, `ServicoPortabilidade`).
- RPCs com **verbos de negócio em português**: `BuscarAssinantePorMSISDN`, `CadastrarAssinante`, `SuspenderLinhaPorInadimplencia`, `IniciarPortabilidade`. **Evitar** prefixos genéricos `Get/Create/Update/Delete`.
- `Request` e `Response` em inglês como sufixos. Não usar `google.protobuf.Empty` se há algo útil pra retornar (ID gerado, timestamp da operação).
- Para RPCs que precisam de exposição REST, adicionar `google.api.http` annotations (a equipe de plataforma usa essas annotations no Envoy).
- Para tipos sem equivalente direto no protobuf (decimal de dinheiro), usar `string` com formato documentado — ver `references/proto-design.md` seção "Tipos sem equivalente direto".

### 3. Decidir granularidade dos RPCs vs tools MCP

O servidor MCP é um **tradutor separado**. Cada tool MCP corresponde a uma ou mais chamadas gRPC. A decisão é: **a agregação fica no backend (RPC agregador) ou no MCP server (tool que faz várias chamadas gRPC)?**

**Default = 1:1.** Crie um RPC por operação de negócio. O MCP server vira tool por RPC. Mais simples de manter, mais granular para o frontend reusar.

**Crie um RPC agregador no backend quando pelo menos uma destas é verdade:**
- A mesma agregação também é útil pro frontend (não é específica do agente de IA).
- A agregação tem **regra de negócio** (filtros condicionais, permissões, derivação de campos calculados).
- Latência de múltiplas chamadas (MCP→gRPC→gRPC→gRPC) seria visível e ruim.
- A agregação envolve dados de múltiplos serviços e faz sentido um deles ser orquestrador (mesmo se o frontend não usar).

**Deixe a agregação no MCP server quando:**
- A agregação é puramente para ergonomia do agente (frontend chama os RPCs individualmente).
- Cada chamada por baixo já é útil isoladamente.
- Não há regra de negócio na agregação, só "junta os dados".

Quando em dúvida, fique no 1:1. É mais fácil promover para agregador depois do que desfazer um agregador prematuro.

**Exemplo concreto.** Tool MCP `consultar_contexto_assinante` (atendimento ao cliente) precisa retornar dados do assinante + linhas + faturas em aberto + consumo do mês.
- Se o frontend de atendimento também tem uma tela "visão 360 do cliente" que mostra essa mesma coisa: **RPC agregador** `ConsultarContextoAssinante` no `ServicoAssinantes`. O MCP server vira 1:1 com esse RPC.
- Se é só pro agente: o MCP server tem o tool `consultar_contexto_assinante` que internamente chama `ServicoAssinantes.BuscarAssinante`, `ServicoLinhas.ListarPorAssinante`, `ServicoFaturas.ListarAbertas`, `ServicoConsumo.ConsultarMes`. Backend não muda.

### 4. Desenhar o schema SQL

Padrões concretos (tipos pgx-friendly, índices, enums como SMALLINT, naming, exemplos completos) em `references/sql-design.md`. Pontos críticos:

- Nomes de tabelas e colunas seguem a regra de idioma. Tabelas no **plural** em português (`assinantes`, `linhas`, `planos`, `faturas`).
- Toda tabela tem:
  ```sql
  id              UUID PRIMARY KEY,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
  ```
  Esses três ficam em inglês (convenção técnica).
- Enums do `.proto` viram `SMALLINT NOT NULL` na tabela (mantêm os mesmos números do proto). **Não** usar `CREATE TYPE ... AS ENUM` do Postgres — gera tipos confusos no `sqlc`.
- Foreign keys explícitas **dentro do mesmo serviço**. Entre serviços diferentes, só referência lógica.
- Índices em todas as FKs e em campos de busca frequente (CPF, MSISDN, etc.).
- Dinheiro: `NUMERIC(15,2)` por padrão. Para casos de telecom em frações de centavo (rateio de consumo), `NUMERIC(20,6)`.

### 5. Escrever as queries do sqlc

- Nomes em português refletindo o domínio: `BuscarAssinantePorCPF`, `ListarLinhasDoAssinante`, `AtualizarSituacaoLinha`.
- O nome da query **deve casar semanticamente** com o RPC que vai consumi-la. Se o RPC é `BuscarAssinantePorMSISDN`, a query é `BuscarAssinantePorMSISDN` (não `GetSubscriberByPhone`).
- Anotações `sqlc`: `:one`, `:many`, `:exec`, `:execrows`.
- Comentário com `-- name:` é exigência do sqlc, fica antes do `SELECT`/`INSERT`/`UPDATE`/`DELETE`.

### 6. Registrar decisões

- Quando algo divergiu do padrão (ex: "não fizemos ACL aqui porque o modelo do sistema X é idêntico ao nosso"), escrever curto no README do serviço.
- Quando há trade-off explícito (ex: "RPC agregador no backend porque o frontend de atendimento também usa"), registrar.
- Quando o `.proto` tem campos `reserved` por causa de removal anterior, comentar o porquê.

## Anti-padrões — evitar

- **Misturar idiomas no mesmo conceito entre camadas.** Ex: `Cliente` no proto, `customer_id` no banco. Quebra a Linguagem Ubíqua.
- **Traduzir literalmente termos técnicos** consagrados. "Manipulador" para `handler`, "Repositório" para `repository`. Soa estranho mesmo para falante nativo. Mantenha em inglês.
- **`Get`/`Create`/`Update`/`Delete` como prefixos de RPC.** Use verbos de negócio (`Buscar`, `Cadastrar`, `Atualizar`, `Cancelar`, `Suspender`, `Ativar`, `Iniciar`).
- **`google.protobuf.Empty` como response** quando há algo útil pra retornar (ID gerado, timestamp da operação, situação resultante). Crie um `Response` próprio.
- **Campos sem comentário no `.proto`.** Cada campo sem comentário é um buraco na descrição do tool MCP que o agente de IA vê. Sem exceção, até para campos óbvios.
- **Pasta `utils/` em qualquer forma** (Go ou `.proto`). Se algo é compartilhado, tem nome de domínio. Helpers são funções não exportadas dentro do pacote.
- **Arquitetura especulativa** ("talvez troquemos PG por Cassandra"). Padrão para o problema do presente.
- **Acoplar ao modelo externo na fronteira** sem ACL quando os modelos diferem. O `.proto` do seu serviço expressa **seu** domínio, não o do parceiro.
- **FK entre tabelas de serviços diferentes.** Cada serviço dono dos próprios dados.
- **`CREATE TYPE ... AS ENUM`** no Postgres. Use `SMALLINT` com os números do enum do proto.
- **Enum sem `_NAO_ESPECIFICADO = 0`** como primeiro valor. Quebra a regra de "zero = não definido" do protobuf.

## Referências

Quando precisar de mais profundidade que o que está acima:

- `references/dominio-telecom.md` — glossário do domínio: assinante, linha, plano, fatura, recarga, portabilidade. Diferenças entre banda larga fibra e móvel 4G/5G. Separação Vendas vs. Atendimento.
- `references/proto-design.md` — padrões concretos de `.proto`: tipos, enums, paginação, erros, annotations `google.api.http` para REST via Envoy, documentação para o servidor MCP traduzir em tools, exemplos completos.
- `references/sql-design.md` — padrões de schema e queries `sqlc`: tipos `pgx`-friendly, índices, enums como `SMALLINT`, naming, exemplos completos.
- `references/arquitetura.md` — documento original do time (escrito para desenvolvedores humanos). Contexto completo dos princípios: organização por feature, ACL, hierarquia de dependências, quando divergir do padrão. Leia se a justificativa de um padrão estiver em dúvida.
- `references/convencao-idioma.md` — documento original do time (escrito para desenvolvedores humanos). Justificativa DDD da regra de idioma e exemplos detalhados em Go, TypeScript, protobuf e SQL.

Os dois últimos são leitura humana — escrita para gente que vai entrar no time. Os três primeiros foram escritos especificamente para esta skill, com formato direto e operacional.
