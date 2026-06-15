# Diretrizes de Arquitetura de Plataforma

A forma macro do sistema: como as aplicações e os serviços se dividem, quem é dono do quê, e onde mora cada tipo de código.

## Como ler este documento

Este é o documento mais "alto" da pasta. Os outros descrevem como construir bem *dentro* de uma fronteira: [`arquitetura_backend.md`](./arquitetura_backend.md) trata da estrutura de um serviço Go, [`arquitetura_frontend.md`](./arquitetura_frontend.md) da estrutura de uma aplicação Next.js. Este aqui trata das fronteiras em si: quantos serviços existem, por que eles existem, e como se relacionam. Quando você precisar decidir *se* algo deve ser um serviço novo (e não *como* estruturá-lo), é aqui que se olha.

A regra de leitura é a mesma dos outros: cada decisão vem com justificativa, e você está encorajado a contestar qualquer coisa que não pareça defensável para o problema concreto. Padrão sem fundamento é peso morto; padrão com fundamento é ferramenta. E tudo tem custo — cada serviço novo, cada chamada de rede, cada contrato publicado cobra alguma coisa em latência, manutenção ou onboarding. Quando adotar algo, pergunte o que custa e o que ganha em troca.

**Este documento é um norte, não uma ordem de migração.** Ele descreve para onde queremos ir, não um cronograma de reescrita. Nada aqui significa "pare o que está fazendo e quebre o sistema atual em vinte serviços". O valor de escrever isto agora é ter um alvo combinado, para que cada decisão incremental empurre na mesma direção em vez de cada um inventar a sua.

## O ponto de partida real: `crm_gateway`

Hoje a maior parte das regras de negócio mora em um único serviço, o `crm_gateway`. O nome conta a história: ele é, ao mesmo tempo, o *gateway* (a porta de entrada que as aplicações chamam, que orquestra e modela dado para tela) **e** o dono das regras de domínio. Duas responsabilidades muito diferentes colapsadas em um lugar só.

Isso não é um erro de quem construiu — é o caminho natural de quase todo sistema que começa pequeno. Um lugar só é mais simples enquanto o sistema cabe na cabeça de poucas pessoas. O problema aparece com o tempo: quando orquestração e regra vivem juntas, mudar uma tela arrisca uma regra de negócio, e mudar uma regra arrisca todas as telas. O acoplamento cresce devagar e a conta chega de uma vez.

Este documento existe porque estamos explorando para onde ir *antes* de o `crm_gateway` virar um problema caro. A direção proposta — separar em duas camadas, com o domínio decomposto por capacidade de negócio — é o resultado dessa exploração. O caminho até lá é tratado na seção [O caminho a partir do `crm_gateway`](#o-caminho-a-partir-do-crm_gateway), e é deliberadamente incremental.

## O padrão: duas camadas com responsabilidades distintas

A arquitetura-alvo tem duas camadas, e a distinção entre elas é a decisão estruturante de tudo o que segue.

**Camada de domínio.** Serviços em Go + gRPC, organizados por *área de negócio* (cliente, linha, fatura, plano, chamado), não por aplicação. São os donos das regras de negócio e dos dados. Cada um é dono do próprio dado e da própria regra, e não compartilha banco com ninguém — quem precisa de um dado lê pela interface gRPC do dono, nunca por SQL direto na tabela alheia.

**Camada de experiência.** As aplicações que as pessoas usam (vendas, atendimento, app do assinante), descritas em detalhe no [`arquitetura_frontend.md`](./arquitetura_frontend.md). Cuidam de renderização, sessão, orquestração de chamadas e modelagem de dado para tela. **Não** contêm regra de negócio nem são donas de dado. No web são aplicações **Next.js fullstack** (o servidor Next.js é a própria camada de experiência); no mobile são apps nativos servidos por um **BFF dedicado e fino**. Como cada uma alcança o domínio está em [Como a experiência fala com o domínio](#como-a-experiência-fala-com-o-domínio).

A consequência mais importante desse arranjo: **a consistência entre aplicações vem da camada de domínio compartilhada, não da camada de experiência.** Os serviços de domínio são únicos; a camada de experiência é replicada por aplicação. Se a regra "cliente inadimplente não gera novo boleto" mora no domínio, ela vale igual em vendas, em atendimento e no app, automaticamente. Se ela morasse na experiência, cada aplicação teria a sua cópia, e elas divergiriam — é uma questão de quando, não de se.

Por isso a regra de ouro: **regra de negócio mora no domínio; a experiência repassa e apresenta.** Quando você se pegar escrevendo um cálculo de preço, uma validação de elegibilidade ou uma máquina de estado na camada de experiência, pare — esse código está na camada errada.

Alguém já descreveu uma forma muito parecida com esta: a Uber chama de **DOMA (Domain-Oriented Microservice Architecture)**, e a literatura genérica fala em *layered/tiered service architecture*. Vale ler como vocabulário compartilhado e como prova de que o desenho não é exótico. O único cuidado ao importar ideias de empresas desse porte é o de sempre: pese se o problema que aquilo resolve é o seu. Boa parte da complexidade de uma Uber existe para coordenar centenas de times; se você adotar a solução sem ter o problema, paga o custo sem o benefício. Isso vale para qualquer fonte, não é um veto a nenhuma.

## Vocabulário: domínio não é o mesmo que aplicação

Esta seção é curta de propósito e é a única coisa que travamos antes de qualquer outra discussão, porque sem ela toda conversa sobre fronteira vira confusão.

**Domínio (bounded context):** um substantivo do negócio que é dono de um conjunto coeso de dados e das regras sobre eles. *Cliente, linha, fatura, plano, chamado.* É uma unidade de modelo, com vocabulário próprio.

**Aplicação / área:** um recorte organizacional ou de produto que serve uma experiência a um grupo de usuários. *Vendas, atendimento, app do assinante.* É uma unidade de uso, não de modelo.

A armadilha é que os dois às vezes compartilham nome de conversa ("o time de atendimento", "o sistema de atendimento") e isso faz parecer que "Atendimento" é um domínio. Quase nunca é. Vendas e atendimento são *áreas* que consomem vários domínios (cliente, linha, fatura) para montar uma experiência. Quando um suposto "serviço de domínio Atendimento" começa a orquestrar chamadas para cliente, linha e fatura, ele provavelmente é uma aplicação disfarçada de domínio — uma camada de experiência que vazou para o backend. Esse é o primeiro sintoma do *distributed monolith* descrito mais adiante.

Regra prática: se a coisa **é dona de um dado e de regras sobre ele**, é domínio. Se a coisa **monta uma experiência juntando dados de vários donos**, é aplicação. Mantenha os dois vocabulários separados em conversa, em diagrama e em nome de repositório.

## Decomposição por capacidade de negócio

O princípio que organiza a camada de domínio é **decompor por capacidade de negócio** (também dito *decompose by subdomain*, no vocabulário de microsserviços): quebrar os serviços pelo *o quê do negócio*, não pela camada técnica nem pela aplicação que consome.

### Por que organizar assim

Porque é organizar em torno do que **muda devagar**. Aplicações vão e vêm: vendas é reescrita, surge um app novo, o fluxo de atendimento muda de fornecedor. Os conceitos do negócio — "cliente", "fatura", "linha", "plano" — são muito mais estáveis. Alinhar o serviço ao domínio é alinhá-lo ao eixo mais estável que existe, e portanto minimizar o quanto a fronteira do serviço precisa se mexer.

"Mais estável" não quer dizer "imutável" — vale ser honesto sobre isso. Fronteiras de domínio mudam: uma mudança regulatória da ANATEL redefine o que é uma "linha", um produto novo cria um conceito que não existia, uma reorganização funde duas áreas. O eixo do domínio se mexe menos que o da aplicação, não nunca. Por isso a decomposição é uma hipótese a revisar, não uma verdade gravada em pedra.

O pano de fundo organizacional é a **Lei de Conway**: a estrutura do software espelha a estrutura de comunicação de quem o constrói. Times donos de *capacidades de negócio* (e não de aplicações) tendem a produzir serviços de domínio limpos; times donos de aplicações tendem a produzir o `crm_gateway` de novo. O benefício prático declarado é concreto: fica mais fácil construir aplicações novas sem reimplementar regra, porque a regra já está no domínio certo, atrás de um contrato.

O argumento de fundo é o **Domain-Driven Design** (Eric Evans): cada serviço de domínio é um *bounded context*, com seu modelo, suas regras e seus dados. É o mesmo princípio que sustenta a [convenção de idioma](./convencao_de_idioma.md) e a [Anti-Corruption Layer](./arquitetura_backend.md#anti-corruption-layer-acl) do backend.

### A unidade é o bounded context; o deployable é uma decisão separada

Esta é a distinção mais importante da seção, e é onde o `novo.md` original fundia duas decisões que precisam ficar separadas.

Decidir as **fronteiras de domínio** (onde termina cliente, onde começa faturamento) é uma decisão. Decidir se **cada domínio vira um processo/deployable separado** é outra, posterior, e movida por necessidade concreta — escala independente, fronteira de time, cadência de deploy independente, isolamento de falha. Enquanto essas necessidades não existem, um bounded context pode perfeitamente ser um **módulo dentro de um monólito modular**: pacote próprio, dono do próprio schema, sem ninguém lendo suas tabelas por fora. Isso é um destino legítimo, não uma etapa de vergonha rumo a "microsserviços de verdade".

Em outras palavras: separe primeiro o *modelo* (contextos com fronteiras nítidas, mesmo dentro de um processo só), e extraia para serviços separados só quando houver uma razão que você consiga nomear. Tirar um módulo bem isolado para fora é barato; juntar de volta dois serviços que nunca deveriam ter se separado é caro. Comece pelo reversível.

Isso é coerente com o "Choose Boring Technology" que já adotamos no backend: a complexidade de sistemas distribuídos (latência, falha parcial, transação distribuída, versionamento de contrato, observabilidade entre processos) é real e se paga todo dia. Você quer pagar essa conta de propósito, por um benefício nomeado — não como efeito colateral de seguir um diagrama.

## As costuras: onde o risco realmente está

Criar os serviços é a parte fácil. O trabalho fino — e onde os projetos morrem — está nas **costuras entre domínios**.

### Onde cortar a fronteira

Não existe resposta certa única, e achar o corte é mais arte que ciência. O que existe é um conjunto de heurísticas para puxar a decisão:

- **Coesão de dados.** Dados que mudam juntos, e por causa um do outro, provavelmente pertencem ao mesmo domínio. Dados que só se referenciam por id provavelmente são domínios diferentes.
- **Quem é dono da regra.** Se uma regra de negócio precisa enxergar dois conjuntos de dados ao mesmo tempo para decidir, ou os dois são o mesmo domínio, ou a regra está na costura errada.
- **Frequência de mudança conjunta.** Se toda mudança em A obriga uma mudança em B, A e B talvez devam ser um só. Se evoluem em ritmos independentes, são bons candidatos a fronteiras separadas.
- **Linguagem do especialista.** Quando o analista de negócio descreve o processo, onde ele troca de assunto? As junções naturais da fala costumam ser boas fronteiras.

Espere errar e re-cortar. A primeira divisão estará parcialmente errada — isso é normal e não é fracasso. O objetivo é errar barato (contextos como módulos, fáceis de remanejar) antes de errar caro (serviços separados, difíceis de fundir).

**Perguntas que ainda estão em aberto para o time** — levantá-las é parte do propósito deste documento, não respondê-las prematuramente: onde mora o conceito de "contrato" (é domínio próprio, ou parte de cliente)? "Chamado" é um domínio ou um aspecto de atendimento? Onde termina "linha" e começa "plano"? Essas decisões merecem análise dedicada e, quando tomadas, um [ADR](./exemplos/docs/adr/0000-template.md).

### Fluxos que cruzam domínios e o distributed monolith

A segunda dificuldade são os fluxos que tocam vários domínios — uma venda mexe em cliente, linha, plano e fatura. A pergunta é: *onde mora a orquestração desse fluxo?*

A resposta que adotamos: **a orquestração de fluxo cross-domínio mora na camada de experiência (na BFF), ou em um serviço de caso-de-uso fino e explícito — nunca em um domínio chamando outro domínio em cadeia.** O domínio expõe operações sobre o seu próprio modelo; ele não sabe coordenar uma venda de ponta a ponta, porque venda não é um domínio, é um caso de uso.

O anti-padrão a evitar tem nome: **distributed monolith** — serviços que parecem separados mas chamam uns aos outros o tempo todo, em cadeia, dentro de uma única requisição de usuário. `cliente` chamando `faturamento` chamando `plano` chamando `cliente` de novo é o pior dos dois mundos: a complexidade da rede sem a independência que justificaria pagá-la. Se os seus "serviços" não conseguem ser deployados, testados ou entendidos independentemente, você não tem microsserviços — tem um monólito espalhado por rede, que é mais difícil que o monólito original.

Sinais de alerta de que uma costura está errada: uma requisição de usuário dispara uma cadeia profunda de chamadas síncronas entre domínios; mudar um domínio quase sempre obriga a mudar outro junto; um "domínio" não tem dado próprio, só orquestra os outros. O backend doc trata as ferramentas concretas para lidar com isso — gRPC síncrono versus [cache orientado a eventos](./arquitetura_backend.md#sobre-serviços-que-falam-com-outros-serviços) para dado de referência, e cuidado com a profundidade do grafo de chamadas via OpenTelemetry.

## Autenticação e autorização: posição provisória

Esta é uma área que ainda precisa amadurecer, e a posição abaixo é deliberadamente provisória — um default de baixo custo de reversão, para podermos avançar agora e revisar quando soubermos mais. Quando a decisão amadurecer, registre em um [ADR](./exemplos/docs/adr/0000-template.md).

O ponto de partida é separar dois conceitos que costumam ser confundidos sob a palavra "auth":

**Autorização de negócio** — "este cliente pode gerar boleto?", "este plano permite portabilidade?", "esta linha pode ser suspensa?". É regra de negócio e, sob risco regulatório (ANATEL, LGPD, contratos com operadoras), é sensível. **Mora no domínio.** É durável e não pode depender de a aplicação lembrar de checar.

**Autenticação, sessão e RBAC de tela** — quem está logado, qual é o token, qual papel pode ver qual botão ou acessar qual rota. **Mora na camada de experiência / BFF**, como já indica o [`arquitetura_frontend.md`](./arquitetura_frontend.md).

A divisão prática: a experiência decide *se você entra e o que você vê*; o domínio decide *se a operação que você pediu é permitida pelas regras do negócio*. As duas checagens coexistem — a de tela é conveniência de UX, a de domínio é a que não pode ser burlada por alguém manipulando a requisição.

Marque isto como provisório no código e nos serviços que o implementarem, para que a migração futura seja consciente e não desfaça suposições silenciosas.

## Pré-requisitos do modelo

Duas coisas deixam de ser "boas práticas opcionais" e viram fundação, porque o modelo inteiro depende delas.

**O contrato `.proto` é a fronteira, e contrato é compromisso.** Se a consistência da plataforma vem dos serviços de domínio compartilhados, então o `.proto` de cada domínio é a interface da qual todas as aplicações dependem. Mudança aditiva é segura; remover ou renomear campo exige migração coordenada entre consumidores. `buf` com detecção de quebra em CI não é luxo — é o que impede que uma mudança local derrube um consumidor em produção (o `app-mobile` ainda na v1, por exemplo). Trate `.proto` como API publicada desde o primeiro dia.

**A experiência fala com o domínio por gRPC, sempre server-side.** A camada de experiência consome os domínios via gRPC, e nunca toca o banco de um domínio direto nem reimplementa regra que o domínio já expõe. O *como* depende da plataforma e está detalhado na próxima seção. Os detalhes de wrapping e tradução na fronteira seguem a [Anti-Corruption Layer](./arquitetura_backend.md#anti-corruption-layer-acl) do backend.

## Como a experiência fala com o domínio

A regra inegociável: **o cliente final (browser ou app) nunca fala gRPC com o domínio diretamente.** Sempre há um servidor da camada de experiência no meio, que detém os segredos de serviço, faz a orquestração cross-domínio e modela o dado para a tela. O que muda entre web e mobile é quem é esse servidor.

**Web — Next.js fullstack.** O próprio servidor Next.js é a camada de experiência. A "camada de dados" da aplicação, em vez de bater em banco, fala gRPC com os domínios **server-side**, via ConnectRPC / cliente gRPC tipado. O browser conversa com o servidor Next.js (Server Components para leitura, Server Actions para mutação); o servidor Next.js conversa com o domínio. Não existe um serviço BFF separado para o web — seria uma camada de rede a mais sem benefício, porque o servidor Next.js já cumpre esse papel.

**Mobile — app nativo + BFF dedicado.** O app não fala gRPC com o domínio direto: ele fala com um **BFF fino, um por app, escrito em Go**, que traduz o gRPC publicado pelos domínios para o que aquele app precisa. Existe um serviço dedicado aqui (e não no web) por duas razões: o app não pode carregar segredos de serviço nem a orquestração que um servidor carrega, e o ciclo de release de app é lento demais para acoplar a evolução dos contratos de domínio — o BFF absorve essa diferença de ritmo. Esse BFF é uma **camada de experiência**, não um domínio: não é dono de dado nem de regra, e cai no padrão "mais simples que o padrão" do [`arquitetura_backend.md`](./arquitetura_backend.md#quando-divergir).

O que esses dois caminhos têm em comum: a orquestração de fluxo cross-domínio mora aqui (servidor Next.js ou BFF mobile), nunca em um domínio chamando outro em cadeia — é a defesa contra o *distributed monolith* descrita acima.

**Terceiros e integradores externos** são um terceiro consumidor, fora do eixo das nossas aplicações. Para eles, expomos **REST traduzido via Envoy (gRPC-JSON transcoding)** sobre o mesmo `.proto` publicado pelo domínio — um caminho deliberado e suportado, não uma gambiarra. A vantagem é não manter uma API separada à mão: o contrato gRPC continua sendo a fonte de verdade, e o Envoy gera a fachada REST a partir dele. A distinção que importa é só esta: o transcoding REST é para quem está **fora** (parceiros, clientes que só falam REST); as nossas aplicações de experiência (web e mobile) falam gRPC server-side, como acima.

## O caminho a partir do `crm_gateway`

O alvo é o desenho de duas camadas. O caminho até ele é incremental e puxado por dor concreta — não por este documento.

A estratégia é *strangler fig*: em vez de reescrever o `crm_gateway` de uma vez (alto risco, sem entrega de valor por meses), extrair um bounded context de cada vez. Escolhe-se o contexto cuja separação resolve uma dor real e atual — o pedaço que mais machuca, ou o mais fácil de isolar com segurança — extrai-se para um módulo ou serviço próprio dono do seu dado, redireciona-se o `crm_gateway` para chamá-lo, e repete-se. O monólito vai encolhendo por dentro até sobrar só orquestração, que por sua vez migra para a camada de experiência.

Três disciplinas tornam isso seguro:

- **Puxe por dor, não por diagrama.** Não extraia um contexto porque o desenho prevê; extraia porque ele está causando um problema concreto que a extração resolve. Se nenhum contexto está doendo, não extraia nada ainda.
- **Comece pelo reversível.** Primeiro separe o *modelo* (módulo com fronteira nítida e dado próprio, ainda dentro do processo). Promova a serviço separado só quando houver necessidade nomeada. Módulo mal-cortado se remaneja barato; serviço mal-cortado, não.
- **Cada extração com rede de segurança.** Testes que provam o comportamento atual antes de mover; contrato `.proto` versionado; nenhum consumidor quebrado. Refactor sem teste que prove o comportamento é loteria — vale tanto aqui quanto no [guideline de IA](./guidelines_ia.md).

Não há prazo neste documento de propósito. O `crm_gateway` pode conviver com os domínios extraídos por bastante tempo; um estado intermediário estável é aceitável e geralmente preferível a uma migração apressada.

## Quando NÃO seguir este padrão

O padrão de duas camadas com domínios separados serve à plataforma como um todo no horizonte que enxergamos. Ele não é obrigatório para tudo, e há casos onde aplicá-lo é over-engineering:

- **Quando um monólito modular basta.** Se não há necessidade nomeada de deploy independente, escala independente ou fronteira de time, manter os contextos como módulos de um processo só é a escolha mais barata e correta. Separar em serviços de rede sem essa necessidade é pagar a conta de sistemas distribuídos por nada.
- **Ferramentas internas pequenas, scripts, integrações pontuais.** Não precisam respeitar a arquitetura da plataforma. Um serviço que é puro wrapper ou tradução pode ser um único pacote, como já diz o [backend doc](./arquitetura_backend.md#quando-divergir).
- **Quando dois contextos genuinamente compartilham um modelo.** Se foram desenhados juntos, pelo mesmo time, para o mesmo conceito, forçar uma fronteira de rede e tradução entre eles é cerimônia sem benefício. O padrão é para quando os modelos *diferem*.

Em qualquer divergência, registre o motivo no README do serviço, para que quem chegar depois entenda a escolha.

## Referências

- **Eric Evans, *Domain-Driven Design* (2003)** — bounded contexts e linguagem ubíqua. A base conceitual de toda a camada de domínio.
- **Chris Richardson, microservices.io** — os patterns *decompose by business capability* e *by subdomain*, e o catálogo de anti-padrões (incluindo distributed monolith).
- **Uber Engineering, DOMA (Domain-Oriented Microservice Architecture)** — artigo público que descreve uma forma muito próxima desta, com outras palavras. Vocabulário compartilhado; pese a aplicabilidade ao nosso porte.
- **Martin Fowler, "StranglerFigApplication"** — a estratégia incremental de migração a partir de um monólito.
- **Melvin Conway, "How Do Committees Invent?" (1968)** — a Lei de Conway, sobre por que a fronteira do software espelha a fronteira do time.
- Documentos irmãos: [arquitetura de backend](./arquitetura_backend.md), [arquitetura frontend](./arquitetura_frontend.md), [convenção de idioma](./convencao_de_idioma.md), [colaboração com IA](./guidelines_ia.md).

## Como este documento evolui

Este é o documento mais especulativo da pasta, porque descreve um estado futuro que ainda não vivemos por inteiro — boa parte da plataforma ainda é o `crm_gateway`. Logo, ele está mais errado do que os outros em pontos que só vamos descobrir extraindo os primeiros domínios.

Por isso ele deve mudar com frequência, e mudar com base em coisas concretas: a primeira extração que fizemos e o que aprendemos com ela, a fronteira que cortamos errado e tivemos que re-cortar, a chamada cross-domínio que virou gargalo. Não mudamos com base em artigos novos nem em como uma empresa famosa faz. Mudamos com base no nosso próprio código em produção.

A arquitetura é uma ferramenta para parar de debater arquitetura. Enquanto a forma não estiver assentada, este documento é o lugar de registrar o que aprendemos — para não redebater do zero a cada extração.
