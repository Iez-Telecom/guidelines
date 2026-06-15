# Diretrizes de Arquitetura de Serviços

Um padrão pragmático para nossos serviços em Go + Postgres + gRPC.

## Como ler este documento

Este documento existe porque temos visto código sendo escrito com base em padrões reconhecidos (Clean Architecture, Hexagonal, Atomic Design) sem que os desenvolvedores consigam explicar por que aqueles padrões foram escolhidos. Aplicar arquitetura sem entender o porquê é ingenuidade pura — você paga o custo da complexidade sem colher o benefício, porque o benefício depende de tomar decisões discriminadas que a arquitetura sozinha não toma por você.

A regra para ler este documento é: cada decisão tem que vir com uma justificativa. Se você ler uma seção e a justificativa não fizer sentido para o seu caso específico, questione. Padrão sem fundamento é peso morto. Padrão com fundamento é ferramenta. Você está autorizado, e na verdade encorajado, a contestar qualquer coisa aqui que não pareça defensável para o problema concreto que você está resolvendo.

A segunda regra é: tudo tem custo. Cada camada de abstração, cada componente novo, cada biblioteca, cada padrão arquitetural — tudo cobra alguma coisa. O cobrar pode ser em performance , em manutenibilidade (mais código para entender), ou em onboarding (tempo até alguém novo conseguir contribuir). Quando você adota algo, pergunte: o que isto custa, e o que ganho em troca? Se você não consegue articular o ganho, provavelmente não está ganhando nada.

## Por que este documento existe

Não queremos rediscutir arquitetura toda vez que iniciamos um novo projeto. Este documento é o padrão. Siga-o, a menos que você consiga articular uma razão técnica específica para divergir. Se divergir, registre o motivo no README do serviço para que futuros leitores entendam a escolha.

O objetivo é consistência, não perfeição. Um padrão sem graça aplicado uniformemente é melhor do que uma escolha ótima debatida por duas semanas a cada projeto.

## Postura

Construímos serviços autocontidos que são donos dos próprios dados e se comunicam via gRPC. Cada serviço é pequeno o suficiente para ser entendido de ponta a ponta e grande o suficiente para justificar ser uma unidade de implantação independente.

Nós **não** adotamos Clean Architecture ou Arquitetura Hexagonal como padrão. Esses padrões surgem de contextos orientados a objetos (Java, C#) e trazem cerimônia que não se encaixa nos idiomas do Go. As fronteiras que eles tentam impor — separar lógica de negócio da infraestrutura — já estão presentes nas fronteiras dos nossos serviços (contratos gRPC, bancos de dados próprios). Recriá-las dentro de cada serviço duplica o trabalho sem agregar valor para a maior parte do nosso código.

No lugar disso, usamos **arquitetura em camadas organizada por feature**, aplicada com bom senso. Esse é o padrão sem graça que software funcional usa há décadas. Ele não tem marca, youtuber, nem livro, e não há nada de errado com isso.

## Estrutura de diretórios padrão

```
cmd/
  server/
    main.go               # Orquestrador: faz wiring e inicializa a aplicação
api/proto/v1/             # Contratos de serviço expostos via Envoy ou gRPC direto
  clientes.proto
  contratos.proto
  contratos_types.proto   # Quando um serviço tem grande número de tipos
gen/
  go/v1/                  # Código gerado do protobuf
  sql/                    # Código gerado pelo sqlc
sql/                      # Arquivos-fonte para o sqlc
  queries/
    clientes.sql          # Queries para o pacote `internal/cliente`
  schema/
    schema.sql            # Schemas do banco
internal/
  cliente/                # Pacote de feature — todo código de cliente
    cliente.go            # Tipos do domínio e lógica de negócio
    cliente_tipos.go      # Opcional: separar tipos quando há muitos
    handler.go            # Handler gRPC/HTTP (protocolo → domínio)
    store.go              # Acesso ao banco (usa sqlc)
    cpf.go                # Lógica específica de CPF (conhecimento de domínio)
  contratos/              # Outro pacote de feature, mesmo padrão
  database/
    database.go           # Abertura, gerenciamento e fechamento da conexão
  cep/                    # Pacote de domínio compartilhado (tratamento de CEP)
  config/                 # Carregamento de configuração
  logger/                 # Configuração de log
external/
  application_1/          # Wrapper do cliente gRPC para serviço externo
  application_2/
sqlc.yaml                 # Configuração do sqlc na raiz do repositório
```

## Princípios por trás da estrutura

**Pastas no nível raiz separam coisas categoricamente diferentes.** `cmd/` são pontos de entrada, `api/` são contratos publicados, `gen/` é código gerado por máquina, `sql/` são fontes para o sqlc, `internal/` é nosso código privado, `external/` são wrappers para serviços externos ao projeto. Essas distinções justificam seu lugar na árvore de diretórios.

**O `main.go` é orquestrador, não implementador.** O ponto de entrada cuida de inicialização, parsing de linha de comando, leitura de configuração, criação dos recursos compartilhados e wiring das dependências — e nada mais. Lógica de domínio, lógica de infraestrutura e qualquer coisa que mereça ser testada vivem em pacotes próprios dentro de `internal/`. É por isso que existem `internal/database/`, `internal/config/` e `internal/logger/` mesmo que sejam pequenos: a regra "main.go não tem lógica" é mais sustentável que "main.go pode ter lógica se for pequena". Regras com exceções de tamanho viram debate a cada caso; regras absolutas são aplicadas sem discussão.

**Dentro de `internal/`, organize por feature, não por camada.** Um pacote de feature contém tudo relacionado àquela feature: handlers, lógica de negócio, persistência. Quando você adiciona uma feature, adiciona arquivos em um único lugar. Quando você lê o código, coisas relacionadas estão juntas. Isso é o oposto da divisão estilo Java em `/handlers`, `/services`, `/repositories`, que espalha o código de uma única feature por três pastas.

**Arquivos dentro de um pacote cuidam da divisão em camadas.** Dentro de `cliente/`, arquivos separados para handler, lógica de negócio e armazenamento dão os benefícios de testabilidade e legibilidade da divisão em camadas, sem o custo de navegação entre subpacotes. A disciplina importa: o arquivo de handler lida com questões de protocolo, o de lógica de negócio com regras de domínio, o de armazenamento com persistência.

**Separar tipos em arquivos próprios é opcional.** Quando uma feature tem muitos tipos a ponto de o arquivo principal ficar difícil de navegar, vale criar um `cliente_tipos.go` (ou equivalente). Para features pequenas, manter tipos e lógica no mesmo arquivo é mais fácil de ler. Use o split quando o tamanho justifica, não por padrão.

**Nomes de pacotes descrevem o que o pacote faz.** Como `net/http` ou `encoding/json`. `cliente` significa "tudo relacionado a cliente". `cep` significa "tratamento de CEP". Nunca usamos nomes genéricos como `utils`, `helpers`, `common` ou `shared` — eles viram gavetas de bagunça e escondem conhecimento de domínio.

**Defina interfaces no pacote consumidor, não no provedor.** Quando `cliente` precisa chamar `application_1`, defina a interface em `cliente/` listando apenas os métodos que cliente usa. A implementação fica em `external/application_1/`. Isso mantém a lógica de negócio testável sem rede e segue o idioma do Go: "aceite interfaces, retorne structs".

**Configuração do sqlc.** O `sqlc.yaml` mora na raiz do repositório, ao lado do `go.mod`. Aponta para `sql/queries/` como entrada e `gen/sql/` como saída. Schemas do banco em `sql/schema/` são lidos pelo sqlc para gerar tipos corretos. Quem cria um serviço novo deve copiar essa configuração junto com a estrutura de pastas.
```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "sql/queries/"
    schema: "sql/schema/"
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

````


## Quando divergir

**Vá mais simples que o padrão** quando:
- O serviço não tem lógica de negócio (pura tradução, puro proxy, wrapper fino de gRPC para REST)
- O serviço é pequeno o suficiente para que a divisão em camadas adicione atrito sem benefício (limite aproximado: menos de ~2.000 linhas)

Um serviço wrapper simples pode ser um único pacote com um arquivo de handler e o cliente externo. Não precisa de pastas de feature dentro de `internal/`.

**Vá mais estruturado que o padrão** quando:
- O serviço tem lógica de domínio rica que vale testar isoladamente (regras de precificação, workflows complexos, máquinas de estado, fluxos de aprovação)
- Um pacote de feature passa de ~1.500 linhas e está ficando difícil de navegar
- A mesma lógica de negócio precisa de múltiplos mecanismos de entrega (gRPC + HTTP + consumidor de fila)

Nesses casos, divida a feature em subpacotes: `cliente/service/`, `cliente/store/`, `cliente/transport/`, com `cliente/` em si guardando os tipos de domínio compartilhados. Isso é mais próximo de Hexagonal em espírito. Aplique seletivamente, não em toda a plataforma.

## Sobre código utilitário

Não existe pasta `utils/` em nenhum nível. Nunca.

Boa parte do que as pessoas chamam de "utilitário" é na verdade conhecimento de domínio que ainda não foi reconhecido como tal. `cleanCPF()` não é um utilitário — é código do domínio de identidade do cliente, e mora no pacote que é dono do conceito de CPF. `cleanCEP()` também não é utilitário — é tratamento de CEP, e se múltiplas features precisam dele, ganha o próprio pacote chamado `cep/`.

A regra: quando você quiser colocar algo em `utils/`, pergunte "que nome eu daria a um pacote contendo apenas isso e seus parentes próximos?" A resposta é quase sempre um nome real. Use esse nome.

Helpers usados por apenas um pacote moram como funções não exportadas naquele pacote, em um arquivo nomeado pelo que fazem. Helpers usados por múltiplos pacotes são promovidos a um pacote com nome descritivo. Pequena duplicação entre pacotes (uma função de três linhas aparecendo duas vezes) é preferível a criar uma gaveta de bagunça compartilhada.

## Sobre convenção de idioma

Vocabulário de domínio em português. Vocabulário técnico em inglês.

Esta é uma decisão deliberada e vai contra a corrente de 99% dos times de Go que conhecemos. Vale registrar o raciocínio porque é o tipo de decisão que será questionada repetidamente, e ter a justificativa escrita evita rediscussão a cada nova contratação.

### A convenção

Tudo que vem do domínio do negócio fica em português: nomes de pacotes de feature (`cliente`, `contratos`, `cobranca`), tipos (`Cliente`, `Contrato`, `Parcela`), funções de regra de negócio (`calcularJurosMora`, `validarCPF`, `gerarBoleto`), campos de tipos do domínio (`dataNascimento`, `valorParcela`, `situacaoCadastral`), nomes de tabelas e colunas no banco, mensagens de erro voltadas para o negócio, nomes em arquivos `.proto` que representam conceitos do domínio.

Tudo que é vocabulário técnico da plataforma fica em inglês: nomes de pacotes de infraestrutura (`database`, `config`, `logger`, `cache`), conceitos de engenharia (`handler`, `store`, `client`, `server`), padrões consagrados (`Open`, `Close`, `Marshal`, `Unmarshal`), termos do Go e da stack (`context`, `error`, `request`, `response`).

### Por que ir contra a corrente

A convenção "código sempre em inglês" existe por uma razão real: a maior parte do material técnico (documentação, livros, bibliotecas, Stack Overflow) está em inglês, e padronizar reduz fricção quando você importa esse mundo para o seu código. Mas isso resolve um problema diferente do que normalmente enfrentamos.

Nosso problema é: o domínio do negócio é em português. Os documentos legais e regulatórios estão em português. Os usuários falam português. Especialistas do negócio com quem conversamos pensam em "boleto", "inadimplência", "carência", "rescisão". Impor uma camada de tradução só na nomenclatura do código adiciona fricção sem benefício real.

Quando um desenvolvedor lê `cliente.contract.installmentValue`, ele está mentalmente traduzindo para `cliente.contrato.valorParcela` antes de entender o que aquilo significa no contexto do negócio. Essa tradução constante é um custo cognitivo invisível mas real, especialmente para desenvolvedores cujo inglês não é fluente. E mesmo para quem é fluente em inglês, a tradução perde nuance: "boleto" não tem equivalente real em inglês, e qualquer tentativa (`bankSlip`, `paymentSlip`) perde informação que todo brasileiro entende imediatamente quando lê "boleto".

### O argumento via DDD

O argumento mais forte vem de Domain-Driven Design. Eric Evans, no livro original de 2003, é explícito sobre o que ele chama de *Ubiquitous Language* (Linguagem Ubíqua): o vocabulário usado no código deve ser exatamente o mesmo vocabulário que os especialistas do domínio usam quando falam sobre o problema. O ponto inteiro do conceito é evitar a tradução entre "como o negócio fala" e "como o código nomeia". Cada tradução é uma chance de perder nuance, criar mal-entendidos, e desalinhar código e negócio.

Se o negócio brasileiro fala "contrato", "parcela", "boleto", "inadimplência", "cobrança", traduzir para `contract`, `installment`, `bankSlip`, `default`, `collection` rompe a Linguagem Ubíqua exatamente do jeito que Evans alerta para não fazer. O DDD foi escrito em inglês porque o autor é americano, mas o princípio é independente de idioma. Times brasileiros aplicando DDD com vocabulário em inglês estão aplicando a forma sem o conteúdo.

A consequência prática: quando um analista de negócio descreve uma regra ("cliente em situação de inadimplência não pode gerar novo boleto"), o desenvolvedor consegue procurar o código pelo termo exato que o analista usou. Quando o código está em inglês, o desenvolvedor precisa primeiro traduzir mentalmente a regra do analista, depois procurar pela versão traduzida. Essa fricção é pequena por busca, mas multiplicada por anos de manutenção, é substancial.

### Por que termos técnicos ficam em inglês

A linha que separa os dois vocabulários é: o vocabulário do *domínio* é a linguagem do negócio, o vocabulário *técnico* é a linguagem da plataforma. Cada um deve estar no idioma natural daquela camada.

`database`, `handler`, `store`, `cache`, `config`, `logger` são vocabulário do Go e da engenharia de software. Não há equivalente em português que adicione clareza — "manipulador" para `handler` é estranho mesmo para falantes nativos de português. Esses termos são lidos como vocabulário técnico, do mesmo jeito que `for`, `if`, `func` são lidos como vocabulário técnico. Traduzir cria ruído sem benefício.

Em outras palavras: usamos português para conceitos que existem no negócio, inglês para conceitos que existem na engenharia. Não é mistura inconsistente — é cada conceito no seu vocabulário natural.

### Disciplina de consistência

Uma decisão como essa só funciona se for aplicada de forma consistente em todas as camadas. O risco é cair em casos como `cliente` no código do domínio mas `cliente_id` na tabela do banco, ou `Cliente` no proto mas `CustomerService` no nome do RPC. Esse tipo de inconsistência destrói o benefício da Linguagem Ubíqua porque força a tradução de volta na fronteira entre camadas.

A regra de aplicação prática: se um termo é vocabulário do domínio, ele aparece em português em *todas* as camadas — proto, código Go, schema do banco, queries, logs de aplicação, mensagens de erro voltadas ao negócio. Sem exceção. A revisão de código deve pegar essas inconsistências quando aparecem.

### Considerações práticas

Algumas fricções reais que vale antecipar:

**Ferramentas de IA e geração de código** (Gemini, Claude, ChatGPT) tendem a sugerir código em inglês por padrão, treinadas em codebases majoritariamente em inglês. Times usando código em português frequentemente recebem sugestões que precisam ser corrigidas. Não é motivo para mudar a decisão, mas é uma fricção real. Ao usar IA, inclua na instrução que nomes de domínio devem ficar em português.

**Bibliotecas e frameworks** sempre serão em inglês. Quando você implementa uma interface vinda de uma biblioteca, o método terá nome em inglês — `ServeHTTP`, `Read`, `Write`. Tudo bem. Esses são pontos de contato com a plataforma, não com o domínio.

**Acrônimos brasileiros** (CPF, CNPJ, CEP, RG) são usados como estão, sem tentativa de tradução. São termos já consagrados no domínio e não precisam de adaptação.

**Conjugação e pluralização em português** podem gerar verbosidade maior que em inglês. `calcularValorTotalDaFaturaComJurosEMulta` é mais longo que `calculateInvoiceTotal`. Aceitável: clareza vence concisão. Se um nome ficou longo demais, vale repensar se a função está fazendo coisas demais (princípio que se aplica em qualquer idioma).

### Resumo

Domínio em português porque o negócio é em português. Técnico em inglês porque a plataforma é em inglês. Consistência em todas as camadas. A decisão é fundamentada em DDD genuíno, não desvio de boas práticas, e o time deve estar pronto para defender a escolha quando questionada.

## Sobre dependências de terceiros

O padrão é "não" para dependências, e exigimos justificativa técnica para o "sim". O custo de uma dependência ruim é pago por anos; o custo de escrever 200 linhas você mesmo é pago uma vez.

Avalie dependências em uma hierarquia de confiança:

**Tier 1 — efetivamente biblioteca padrão** (`golang.org/x/*`, bibliotecas oficiais de gRPC e protobuf): use livremente.

**Tier 2 — respaldo institucional com adoção ampla** (`pgx`, `sqlc`, bibliotecas do OpenTelemetry, `zap` da Uber): use quando atender a necessidade.

**Tier 3 — mantida pela comunidade com adoção ampla** (`gorilla/mux`, `spf13/cobra`): avalie, mas tenda ao "sim". Leia o código se for pequeno. Confirme que o projeto está ativamente mantido.

**Tier 4 — bibliotecas pequenas, de nicho, de um único mantenedor** ou `github.com/dev_maluco/super_boleto`: o padrão é "não". Três alternativas em ordem de preferência:
1. **Escreva você mesmo** para problemas pequenos e bem definidos sem casos de borda reais (validação de CEP, tratamento de formato simples)
2. **Faça vendor do código relevante** preservando a licença, quando você realmente precisa do código mas não confia na manutenção a longo prazo
3. **Faça um fork** quando você precisa do código e precisa evoluí-lo sob seu controle

Importar uma biblioteca tier-4 como dependência regular exige justificativa técnica específica. A biblioteca padrão do Go é abrangente o suficiente para que possamos ir longe sem dependências tier-4 na maioria dos serviços.

Casos em que escrever você mesmo é SEMPRE errado, independentemente do tamanho da biblioteca: criptografia, código sensível à segurança, implementações de protocolo (TLS, HTTP/2), primitivas de sistemas distribuídos, qualquer coisa em que a correção seja difícil de verificar, mas nesse caso deve-se buscar algo **Tier 1** ou **Tier 2**.

## Sobre serviços que falam com outros serviços

Chamadas gRPC síncronas entre serviços não são gratuitas. São chamadas de rede que podem falhar, dar timeout ou ficar lentas. A ideia de que "parece uma chamada de função local" é uma armadilha — chamadas locais não têm esses modos de falha.

Cuidado com a profundidade do grafo de chamadas. `Vendas` chamando `Atendimento` chamando `Logistica` chamando `Cidades` chamando `ReceitaFederal` em uma única requisição de usuário é um desastre de latência esperando para acontecer. Use rastreamento distribuído (OpenTelemetry) para tornar o grafo implícito visível.

Para dados de referência que mudam pouco e são lidos com frequência (como cidades atendidas), considere caches locais orientados a eventos além da interface gRPC síncrona. O serviço dono publica eventos de mudança; os consumidores mantêm caches locais somente leitura. Isso troca consistência imediata por resiliência e latência, e a troca geralmente vale a pena para dados de referência.

Para dados que precisam estar atualizados (saldo atual, estoque em tempo real, verificação de identidade), mantenha gRPC síncrono.

Trate arquivos `.proto` como contratos publicados. Mudanças aditivas são seguras. Remover ou renomear campos exige migração coordenada entre consumidores. Use `buf` com detecção de quebras em CI.

## Anti-Corruption Layer (ACL)

Toda integração com sistemas externos — APIs do governo, serviços de terceiros, sistemas legados, e até outros serviços internos com modelos diferentes do nosso — deve passar por uma Anti-Corruption Layer. É o nome formal do que já fazemos com nossos wrappers em `external/`, e dar nome ao padrão ajuda a tomar as decisões de design certas.

### O que é

Anti-Corruption Layer é um padrão do Domain-Driven Design (Eric Evans, 2003). A "corrupção" que a camada protege não é de segurança — é *conceitual*: o jeito como o vocabulário, as suposições e as esquisitices de um sistema externo vazam para o seu domínio quando você integra com ele.

Exemplo canônico: você integra com um ERP legado que chama clientes de "contas", usa códigos de status como `STAT_03_PEND_RVW` e representa preços em décimos de centavos para evitar floats. Se o seu código chama o ERP direto, todo esse vocabulário infecta o seu codebase. Seu tipo `Customer` ganha um campo `accountStatusCode`. Sua lógica de negócio faz `if status == "STAT_03_PEND_RVW"`. O modelo do ERP corrompeu o seu modelo — não maliciosamente, só por gravidade.

A ACL é uma camada de tradução que fica entre o seu domínio e o sistema externo. Seu domínio fala com a ACL no vocabulário do seu domínio; a ACL traduz para e do vocabulário do sistema externo. Seu código nunca vê `STAT_03_PEND_RVW`; vê `CustomerStatus.PendingReview` ou o que fizer sentido no seu modelo. Quando o ERP eventualmente for substituído, você muda a implementação da ACL; seu código de domínio não muda porque nunca soube da existência do ERP.

### Por que isso importa mais do que parece

O padrão soa quase trivial quando enunciado de forma abstrata — "traduzir entre dois sistemas" — mas a disciplina de fazer isso de forma consistente é mais difícil do que parece, e as consequências de pular se acumulam devagar de formas que os times subestimam.

Sem uma ACL, os conceitos do sistema externo se espalham pelo seu código por capilaridade. Alguém escreve `if response.statusCode == "STAT_03_PEND_RVW"` uma vez, num handler. Alguns meses depois, essa verificação aparece em mais três lugares porque foi mais fácil copiar do que abstrair. Um ano depois, o time do ERP renomeia o status para `STAT_PENDING_REVIEW` e você tem que achar todos os lugares no seu codebase que referenciam o código antigo, em lógica de negócio que conceitualmente não tinha nada a ver com o ERP. A mudança se propaga por código que nunca deveria ter sabido da existência do ERP.

Esse é o custo real que a ACL evita: não o custo da integração inicial, mas o custo contínuo de acoplamento que se acumula ao longo do tempo.

### Princípios de design

Uma vez que você reconhece um serviço como ACL, certos princípios seguem que não seriam óbvios se você pensasse nele só como "wrapper de API".

**O contrato do protocolo deve refletir a linguagem do seu domínio e projeto, não a do sistema externo.** Seu `.proto` deve expor tipos e operações nomeados no vocabulário do seu negócio. Se a API do governo retorna um campo `cpf_situacao_cadastral`, seu proto deve expor `estadoCPF` (ou como o negócio chamar esse conceito) com valores que façam sentido no seu projeto. A tradução de `cpf_situacao_cadastral` para `estadoCPF.Ativo` acontece dentro da ACL. Esse é o trabalho real de "anti-corrupção" — recusar deixar o vocabulário externo cruzar a fronteira.

Isso parece óbvio mas é frequentemente pulado sob pressão de prazo. Programadores expõem a estrutura da API externa direto porque é mais rápido: mesmos campos, mesmos nomes, mesmos tipos. O resultado é que a ACL vira um proxy fino que não protege nada; a corrupção passa direto. A disciplina é traduzir mesmo quando a tradução parece trivial hoje, porque a proteção se acumula com o tempo.

**Semântica de erro deve ser traduzida, não repassada.** A API externa retorna HTTP 503 porque o servidor caiu. Retorna HTTP 422 porque a entrada estava malformada. Retorna 200 com código de erro no corpo porque o design dela é mal feito. Sua ACL deve traduzir tudo isso em códigos de status gRPC que façam sentido (`UNAVAILABLE`, `INVALID_ARGUMENT`, etc.) e que seus clientes grpc possam tratar sem saber se o que está embaixo é REST, SOAP ou sinal de fumaça. Clientes grpc nunca devem precisar saber "se a API do governo está fora, a resposta tem essa cara".

**Preocupações transversais ficam na ACL, não nos clientes grpc.** Retentativas, backoff exponencial, circuit breaking, cache de respostas, rate limiting, gerenciamento de tokens de autenticação, assinatura de requisições — tudo isso é responsabilidade da ACL. Se cada cliente grpc precisa implementar retry quando chama a API do governo, a abstração falhou.

**A ACL pode "mentir" quando útil.** Se o sistema externo exige uma gambiarra em que você precisa fazer duas chamadas para obter os dados que o seu domínio conceitualmente precisa, a ACL pode expor uma única chamada que faz as duas internamente. Se o sistema externo tem consistência eventual e você precisa de read-after-write, a ACL pode implementar isso com cache ou polling. O trabalho da ACL é dar ao seu projeto a abstração que ele precisa, não reproduzir fielmente o sistema externo.

### Aplica também a serviços internos

A "fronteira externa" não precisa ser fora da empresa. Pode ser outro projeto ou time interno cujo modelo difere do seu.

Se o contexto de Vendas usa "cliente" para significar "pessoa que fez pelo menos um pedido" mas o contexto de Atendimento usa "cliente" para significar "pessoa com conta ativa", são *conceitos diferentes que compartilham nome*. Quando Vendas chama a API do Atendimento para pegar dados de cliente, integração ingênua trata como a mesma coisa e cria bugs. Uma ACL entre Vendas e Atendimento traduz: o código de domínio de Vendas fala em "Vendas.Cliente", e a ACL traduz de e para "Atendimento.Cliente" na fronteira. Os dois conceitos podem evoluir independentemente porque a tradução absorve as diferenças.

Para a nossa plataforma, isso significa: em `external/application_1/`, o wrapper não é só gerar um cliente gRPC e expor direto para os pacotes de feature. Ele traduz as respostas para tipos que fazem sentido no domínio do *seu* serviço. Os pacotes de feature importam tipos definidos no seu domínio ou no wrapper, nunca tipos do proto do serviço externo.

### Quando ACL é exagero

Agora ACL é um padrão com custos reais, e aplicar em todo lugar é burrice.

**Não precisamos usar padrões como uma religião**

Se dois serviços genuinamente compartilham um modelo — foram desenhados juntos, pelo mesmo time, para o mesmo domínio — forçar tradução na fronteira é cerimônia sem benefício. Você está traduzindo entre estruturas idênticas, o que é puro overhead. O padrão é para quando os modelos *diferem*, não para quando coincidem de estarem em lados diferentes de uma fronteira de rede.

Se um serviço vai chamar outro exatamente uma vez, de um jeito que claramente vai continuar simples, construir uma ACL completa é over-engineering. Uma chamada direta com wrapping mínimo pode ser suficiente.

O julgamento é: o quanto o modelo do sistema externo é genuinamente diferente do nosso, e o quanto essas diferenças vão custar com o tempo se não traduzirmos? Se a resposta é "não muito", pule a ACL. Se a resposta é "notavelmente diferente e provavelmente vai evoluir", construa.

### Implementação prática em Go

Uma ACL para uma API externa tipicamente tem três peças. O cliente bruto (frequentemente gerado de specs OpenAPI, ou escrito à mão para APIs REST sem specs). A camada de tradução que converte entre os tipos externos e seus tipos de domínio — é aqui que o trabalho real da ACL acontece. E o servidor gRPC que expõe sua interface traduzida para o resto da plataforma.

A camada de tradução é a parte que mais vale investir, porque é onde o valor do padrão vive. Geralmente parece um conjunto de funções de mapeamento: `traduzRespostaGovernoCliente(resp *govapi.Response) (*domain.Customer, error)`. Cada cliente grpc trata a conversão de um tipo externo para um tipo de domínio, incluindo conversão de unidades, tradução de enums, e mapeamento de erros. Esses mapeamentos devem ser testáveis sem rede — são funções puras que recebem tipos externos e retornam tipos de domínio — e você deve testar, porque é onde os bugs se escondem.

A camada de clientes grpc também tende a ser onde você descobre lacunas. Quando você escreve `traduzRespostaGovernoCliente` e percebe que a resposta do governo tem um código de status para o qual você não tem equivalente no domínio, você tem uma decisão de design para tomar: estender seu domínio para representar aquele caso, ou decidir que não importa e mapear para um default razoável. De qualquer forma, a decisão é *visível* no código em vez de enterrada em uma comparação em algum lugar lá embaixo.

## Coisas que evitamos explicitamente

- O repositório `golang-standards/project-layout` como referência. Não é um padrão oficial, a comunidade Go critica, e o nome dele engana. A orientação oficial está em [go.dev/doc/modules/layout](https://go.dev/doc/modules/layout).
- Cargo-cult de blogs de engenharia das FAANG. Spotify, Netflix e Google têm problemas que não temos. Padrões que resolvem "100 times não conseguem se coordenar" pioram nossa situação, não melhoram. Avalie cada ideia pelo problema que ela resolve e se esse problema é realmente nosso.
- Arquitetura especulativa para necessidades futuras hipotéticas. "Talvez troquemos banco de dados de Postgres por X" quase nunca acontece, e quando acontece, a abstração construída anos antes geralmente está errada para o novo banco. Arquitetura deve resolver problemas do presente.
- Reescrever serviços antigos por moda arquitetural. Serviços existentes não migram para novos padrões a menos que haja um problema concreto em produção empurrando essa decisão.

## Recursos para novos membros do time

- Kat Zien, "How Do You Structure Your Go Apps?" (GopherCon 2018, YouTube). Vocabulário compartilhado para os padrões que discutimos. ~45 minutos.
- Mat Ryer, "How I write HTTP services" (série de blog). Um exemplo concreto do estilo Go pragmático.
- Dan McKinley, "Choose Boring Technology" (mcfunley.com). A filosofia por trás de optar por soluções comprovadas e simples como padrão.
- John Ousterhout, *A Philosophy of Software Design*. Sobre complexidade como inimiga, sem prescrever uma arquitetura específica.

## Como este documento evolui

Esta diretriz está errada em pontos que ainda não descobrimos. Revisamos de vez em quando com base no que aprendemos com serviços reais, não com base em artigos novos. Propostas de mudança devem citar coisas concretas que vivenciamos, não melhorias teóricas.

A arquitetura é uma ferramenta para parar de debater arquitetura. A consistência é o valor. Escolha se comprometer.