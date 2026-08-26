# Diretrizes de Protobuf — iez! Telecom

> Documento da equipe. Explica **por que** escrevemos nossos `.proto` do
> jeito que escrevemos. As regras operacionais (o "como") estão resumidas
> na skill `protobuf-padrao-iez`; aqui está o raciocínio por trás de cada
> uma, para que qualquer pessoa do time possa questionar, defender ou
> evoluir o padrão com fundamento.

## 1. O contrato é o produto

Um arquivo `.proto` na iez! não é um detalhe de implementação. Ele é
consumido por (pelo menos) três públicos com necessidades diferentes:

1. **O aplicativo** (e qualquer frontend futuro), via gRPC ou REST
   transcoding — precisa de tipos estáveis e previsíveis.
2. **Desenvolvedores** — leem o proto (e o código gerado) como
   documentação primária da API. Para a maioria, o comentário do campo é
   a única documentação que vão ler.
3. **Agentes de IA**, via servidores MCP — os comentários do proto viram
   literalmente as descrições dos tools. Um agente decide *qual* RPC
   chamar lendo o comentário do RPC, e decide *como preencher* cada campo
   lendo o comentário do campo.

O terceiro público é o que muda o jogo: um comentário ruim deixou de ser
"documentação fraca" e passou a ser **um bug em produção** — o agente vai
chamar o RPC errado ou preencher o campo errado. É por isso que a
documentação aqui não é opcional nem "nice to have".

## 2. Por que todo RPC documenta "quando usar"

"O que faz" descreve o mecanismo; "quando usar" descreve a decisão.
Humanos compensam a falta do segundo com contexto e tentativa-e-erro.
Agentes de IA, não: diante de `ListarHistoricoFaturas` e
`ListarFaturasAbertas`, a única coisa que separa a escolha certa da
errada é o texto que diz *"Use na tela de histórico completo... Para
exibir apenas o que está pendente, use ListarFaturasAbertas."*

Por isso o formato de comentário de RPC tem quatro blocos fixos:

1. **O que faz** — uma frase.
2. **Quando usar** — o cenário na jornada, e o RPC alternativo quando
   existir ambiguidade.
3. **O que retorna** nos casos não óbvios — em especial, se ausência de
   resultado é **lista vazia** ou **NOT_FOUND**. Essa distinção é uma
   decisão de contrato: "cliente sem contratos" é um estado de negócio
   válido (lista vazia); "contrato inexistente" é um erro de referência
   (NOT_FOUND). Se não estiver escrita, cada consumidor vai assumir uma
   coisa diferente.
4. **Erros** com semântica de negócio — o consumidor precisa saber o que
   tratar. Não listamos INTERNAL/UNAVAILABLE porque todo RPC pode
   retorná-los; listar só adiciona ruído.

## 3. Por que todo campo tem formato, exemplo e referência cruzada

**Formato e exemplo.** "CPF do cliente" não diz se vem com pontuação.
"`string` 11 dígitos, somente dígitos, Exemplo: '01234567890'" elimina a
classe inteira de bugs de máscara — historicamente uma das maiores fontes
de retrabalho em integração. A regra prática: se o campo tem formato, o
comentário tem exemplo. Sem exceção, porque o custo é uma linha.

**Referência cruzada.** Nossos fluxos são encadeados: o `uuid_cidade` que
entra em `ReservarNovoNumero` saiu de `VerificarCobertura`; o
`cod_reserva` que sai de `ReservarNovoNumero` entra em `CriarContrato`.
Quando documentamos isso **nas duas pontas** ("Obtenha via X" / "Envie no
campo Y de Z"), o grafo de chamadas da jornada fica legível no próprio
contrato — um dev novo ou um agente de IA descobre a ordem das chamadas
sem perguntar a ninguém. É a forma mais barata de documentação de
arquitetura que temos: ela mora junto do código e não desatualiza
separada dele.

**Comentário tautológico é proibido** ("// ID do cliente" em cima de
`string cliente_id`). Ele ocupa o espaço do comentário verdadeiro e
passa na revisão visual como se o campo estivesse documentado. Pior que
ausência: é ausência disfarçada. A versão útil dá ao consumidor uma
pista de **como obter** o valor: "UUID v4 do assinante. Use
BuscarAssinantePorCPF se você não tiver esse ID."

## 4. A regra de ouro da evolução: envelopes dedicados

Quase todas as nossas regras estruturais derivam de um único fato técnico:

> No gRPC, **mudar o tipo** do parâmetro ou do retorno de um RPC é
> breaking change. **Adicionar um campo** a uma mensagem existente não é.

Logo, todo desenho deve maximizar os lugares onde dá para *adicionar* e
minimizar as situações que exigiriam *trocar o tipo*. Daí:

**Um Request e um Response por RPC, nunca compartilhados.** Se
`ListarOfertasDisponiveis` e `VerificarCobertura` compartilham o mesmo
Request, no dia em que um deles precisar de um campo novo (um filtro, uma
paginação) você tem duas opções ruins: poluir o contrato do vizinho com
um campo que não faz sentido lá, ou criar uma mensagem nova e quebrar o
RPC. Duplicar uma mensagem de um campo custa três linhas hoje; desacoplar
um Request compartilhado custa uma versão de API depois.

**Nunca `google.protobuf.Empty`.** `Empty` é um tipo que, por definição,
nunca poderá ganhar um campo. Um `ListarTiposClienteRequest {}` vazio é
funcionalmente idêntico hoje e infinitamente extensível amanhã. No
sentido da resposta, vale mais que extensibilidade: uma operação "void"
que retorna a entidade no novo estado (e o instante de efetivação) deixa
o frontend atualizar a UI sem nova consulta e dá ao agente de IA a
confirmação de que a operação teve efeito.

**Nunca mensagem de domínio como retorno direto.** `returns (Cliente)`
significa que a resposta *é* o cliente — não há onde colocar um metadado
de resposta (paginação, flags de completude, avisos) sem enfiá-lo dentro
do tipo de domínio, contaminando todos os outros lugares que usam
`Cliente`. O envelope (`Response { Cliente cliente = 1; }`) custa uma
mensagem e separa para sempre "o dado" de "a resposta".

**Nunca Response como tipo de domínio.** O simétrico do anterior:
`repeated LerContratoUUIDResponse contratos` transforma o envelope de um
RPC em vocabulário do domínio. Agora os dois RPCs estão algemados — um
campo de resposta novo no detalhe aparece dentro de cada item da listagem.
Extraia a mensagem de domínio (`Contrato`) e deixe cada Response
envelopá-la do seu jeito.

**E onde reusar é certo:** mensagens de domínio (`Cliente`, `Fatura`,
`Linha`, `Endereco`) existem exatamente para serem reusadas. A regra de
envelope dedicado vale para a *casca* do RPC, não para o *recheio*.
Tipos genuinamente transversais (usados em 3+ features — paginação,
endereço, range de datas) podem morar num `common.proto`; abaixo disso,
duplique. Acoplamento por tipos compartilhados é pior que duplicação
pequena: um campo novo num tipo de `common.proto` aparece em todos os
serviços que o importam, queiram ou não.

## 5. Dinheiro nunca em ponto flutuante

`double` não representa decimais exatos: `0.1 + 0.2 != 0.3` em qualquer
linguagem com float IEEE 754. Em valores monetários isso vira centavo
sumindo em soma de fatura — o tipo de bug que destrói confiança do
cliente e dá trabalho regulatório. Nosso padrão é **`int64` em
centavos** ("4990 = R$ 49,90"): aritmética inteira é exata, e o nome/
comentário do campo carrega a unidade. A alternativa aceitável é `string`
decimal ("49.90") quando o valor só transita sem cálculo. O que não
existe é misturar padrões dentro do mesmo serviço.

## 6. Vocabulário fechado vira enum

Se o comentário de um campo `string` precisa dizer 'Valores possíveis:
"PAGO", "EM_ABERTO", "VENCIDO"', o campo está pedindo para ser um enum.
Com string livre, o compilador aceita `"EM ABERTO"` (com espaço),
`"pago"` (minúsculo) e `"VENCIDA"` (typo) — e o bug só aparece em
runtime, no pior lugar possível. Com enum, o erro nem compila, e o
conjunto de valores fica documentável valor a valor.

Duas regras de enum que parecem burocracia mas têm motivo técnico:

- **Zero é sempre `_UNSPECIFIED`.** No proto3, campo não enviado e campo
  com valor zero são indistinguíveis na rede. Se `ATIVO = 0`, "não
  informei o status" e "status é ATIVO" viram a mesma coisa. O zero
  precisa significar "não definido" para essa ambiguidade ser detectável.
- **Valores prefixados com o nome do enum** (`SITUACAO_LINHA_ATIVA`, não
  `ATIVO`). No proto3, valores de enum vivem no namespace do *pacote*,
  não do enum. Dois enums do mesmo pacote com um valor `ATIVO` não
  compilam — e o dia em que isso acontece é sempre o dia em que alguém
  precisava só "adicionar um enumzinho".

Em máquinas de estado (situação de linha, status de fatura), documente
em cada valor a **reversibilidade** e o **gatilho típico** — é a
informação que o atendente (e o agente de IA do atendimento) precisa
para orientar o cliente. E não use `oneof` para representar estados
mutuamente exclusivos que um enum resolve: `oneof` é para variantes de
payload, não para máquinas de estado.

## 7. Tipos com semântica, não strings com fé

- **Instantes**: `google.protobuf.Timestamp` (UTC). **Datas sem hora**:
  `google.type.Date`. String para data ("2025-06-01"? "01/06/2025"?
  com timezone?) é uma negociação de formato implícita entre cada par
  produtor-consumidor — exatamente o que um contrato existe para evitar.
- **IDs internos**: `string` UUID v4 — nunca inteiro sequencial (vaza
  cardinalidade, convida enumeração, acopla ao banco).
- **Identificadores com formato** (CPF, CNPJ, MSISDN, ICCID): `string`
  somente dígitos, formato e exemplo no comentário. Inteiro não serve:
  CPF tem zero à esquerda.
- **Booleanos no afirmativo** (`ativo`, não `nao_ativo`): negação no
  nome obriga o leitor a uma dupla negação (`nao_ativo = false`) — fonte
  clássica de bug de leitura.
- **Volumes de dados em unidade explícita**: a unidade vai no nome e no
  comentário (`franquia_dados_bytes`, `bonus_dados_mb`), com exemplo.
  "10" sem unidade já causou tanto retrabalho quanto CPF com máscara.

## 8. Paginação por cursor, não por offset

Listas que crescem (faturas, recargas, linhas de uma empresa) ganham
`page_size` + `page_token`/`next_page_token` com **cursor opaco**. Offset
numérico (`page=3`) quebra quando a lista muda entre uma página e outra:
itens pulados ou duplicados, e o consumidor nem percebe. O cursor opaco
deixa o servidor livre para implementar como quiser (keyset, snapshot)
sem mudar o contrato. E como paginação é campo de Request/Response — não
tipo de domínio — adicioná-la depois a um RPC que nasceu sem ela é
mudança segura; é exatamente para isso que os envelopes dedicados existem.

## 9. Idempotência em mutações com retry

Frontends fazem retry em timeout; agentes de IA fazem retry por decisão
própria. Uma mutação financeira (recarga, pagamento, cadastro) executada
duas vezes é um incidente. O campo `idempotency_key` (UUID gerado pelo
cliente) permite ao servidor deduplicar: mesma chave dentro da janela →
retorna o resultado da primeira execução sem executar de novo. O campo é
opcional no contrato, mas recomendado em todo fluxo automatizado — e
documentado no proto para que o agente de IA saiba que deve gerá-lo.

## 10. Dados sensíveis não pegam carona

Se a consulta de detalhe do contrato carrega o `SimCard` completo — com
PIN1, PIN2, PUK1, PUK2 — então **toda** tela que mostra contrato puxa
credenciais do chip pela rede, e elas passam por logs de gateway, caches
de cliente e ferramentas de debug no caminho. A superfície de vazamento é
o produto de (quantos RPCs retornam o dado) × (quantas telas chamam esses
RPCs).

O desenho correto: a mensagem de uso geral carrega um **resumo**
(`uuid`, `iccid`, `status`); o dado sensível tem **RPC dedicado** com
autenticação reforçada e auditoria (`ConsultarCredenciaisSimcard`).
Enquanto a separação não acontece, no mínimo o campo é marcado:
"Dado sensível — exibir apenas mediante autenticação do assinante;
nunca registrar em logs."

## 11. Idioma: domínio em português, técnica em inglês

Nosso negócio fala português: *fatura*, *linha*, *recarga*,
*portabilidade*, *cobrança* não têm tradução exata, e traduzi-los cria
uma camada de conversão mental entre quem atende o cliente e quem escreve
o código (é a "Linguagem Ubíqua" do DDD: o vocabulário do negócio e o do
código devem ser o mesmo). Já `Request`, `Response`, `uuid`, `repeated`,
`page_token`, `idempotency_key` são convenções técnicas do ecossistema —
traduzi-las soa estranho e afasta o código das referências que todo dev
consulta. Pela mesma régua, o zero dos enums usa o sufixo técnico
`_UNSPECIFIED`, e os services usam o nome direto da feature
(`Recargas`, `Financeiro`), sem prefixo redundante `Servico` — o
keyword `service` já diz o que é.

A regra só funciona se for consistente em **todas** as camadas: o que é
`situacao` no proto é `situacao` no banco e na query. `Cliente` no proto
com `customer_id` no banco é o pior dos dois mundos.

Nomes de RPC usam **verbos de negócio** (`Gerar`, `Consultar`,
`Reservar`, `Suspender`), não CRUD genérico (`Get`, `Create`). O verbo de
negócio carrega intenção e pré-condições; `UpdateLinha` aceita qualquer
coisa, `SuspenderLinha` diz exatamente o que faz e convida a validar a
transição.

## 12. REST é fachada, não espelho

Quando um RPC precisa de consumidor REST (sistema legado, webhook,
parceiro), o Envoy faz o gRPC-JSON transcoding a partir da annotation
`google.api.http` — o contrato continua sendo um só, o `.proto`. Duas
disciplinas mantêm isso saudável:

- **Não exponha todos os RPCs via REST.** Cada rota exposta é superfície
  pública a manter, documentar e proteger. Só ganha annotation o RPC com
  consumidor REST real, e a lista de exposições vai no README do serviço.
- **URLs seguem o recurso, não o RPC**: recursos no plural e em português
  (`/assinantes`, `/linhas`), IDs em path (`/assinantes/{uuid}`), ações
  custom com `:verbo` (`/linhas/{uuid}:suspender`). Assim a fachada REST
  fica idiomática para quem só enxerga HTTP, sem distorcer o desenho gRPC.

## 13. Mudança segura vs. breaking change

Saber a diferença é o que permite evoluir sem versão nova:

**Seguro (faça quando precisar):**
- Adicionar campo a mensagem existente (tag nova).
- Adicionar RPC a serviço existente.
- Adicionar valor a enum (número não usado).
- Mudar/adicionar comentários, remover imports não usados.

**Breaking (exige v2 coordenada):**
- Renomear/remover campo, mudar tipo ou número de tag.
- Mudar o tipo de Request/Response de um RPC existente.
- Renomear RPC, mensagem ou serviço.
- Reaproveitar número de tag removido (use `reserved`).

Disso sai nossa prática de revisão: **documentar um proto existente é
operação de comentário** — nomes, tags e tipos não se tocam. Violações
estruturais encontradas durante a documentação são registradas como
recomendações para a próxima major version, priorizadas por: segurança >
evolução de contrato > estilo.

## 14. Checklist de revisão de PR

Para o revisor de qualquer PR que toque um `.proto`:

- [ ] Todo RPC novo tem os 4 blocos de comentário (o que / quando usar /
      retorno / erros)?
- [ ] Todo campo novo tem significado, formato, exemplo, opcionalidade e
      referência cruzada (quando aplicável)?
- [ ] Algum Request/Response compartilhado entre RPCs? `Empty`? Domínio
      como retorno direto?
- [ ] Dinheiro em `double`? String com vocabulário fechado? Data em
      string?
- [ ] Enum novo: zero `_UNSPECIFIED` e valores prefixados?
- [ ] Lista nova que pode crescer está paginada? Mutação nova com risco
      de retry tem `idempotency_key`?
- [ ] Algum campo existente renomeado, removido ou com tag/tipo alterado?
      (Se sim: é uma v2 ou é um acidente?)
- [ ] Dado sensível novo trafegando em resposta de consulta geral?
- [ ] Annotation REST nova tem consumidor REST real e está listada no
      README?

---

*Dúvidas ou propostas de mudança neste documento: abram PR. O padrão é
da equipe — ele só vale enquanto todo mundo entender o porquê.*
