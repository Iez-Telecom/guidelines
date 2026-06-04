# Diretrizes de colaboração com IA

Como o time trabalha com IA generativa em código — o que funciona, o que morde, e como dividir responsabilidade entre humano e ferramenta.

## Como ler este documento

Este documento é descritivo, não prescritivo. Registra o que aprendemos funcionando em código de produção, não o que está na moda. Cada pessoa no time está num ponto diferente do espectro de adoção — desde quem não usa, até quem usa intensamente em todo PR. Tudo bem.

A pergunta certa para cada seção não é "preciso fazer isso?". É "isso faz sentido para o problema que estou resolvendo agora?". Se a resposta for não, ignore — e se descobrir um padrão melhor, traga de volta para evoluirmos o documento.

A regra que vale para todos: **quem digita ou cola o código é responsável por ele.** Não importa se foi humano que escreveu ou IA que sugeriu — quando entra no repositório, é seu.

## Por que este documento existe

Sem registro, cada pessoa do time reinventa (ou evita) IA por conta própria, e o resultado é inconsistente: PR com código que ninguém entendeu, PR sem usar IA onde teria ajudado muito, conversas longas em revisão sobre "como você fez isso". Padrões compartilhados eliminam essas conversas e deixam o tempo livre para o que importa.

A outra razão: a forma errada de usar IA é silenciosamente cara. Vaza nas semanas seguintes — em código que ninguém defende, em bugs que ninguém explica, em decisões que ninguém lembra ter tomado. Por isso vale escrever antes que o time grande adote.

## Postura

IA é ferramenta. Como qualquer ferramenta, vale dominar onde ela ajuda, onde ela atrapalha, e como integrar sem virar dependência. Não tratar como oráculo (quase sempre erra em algo) nem como brinquedo (resolve problemas reais quando bem dirigida).

A autoridade da IA vem de **fundamentação que você consegue verificar**, não de fluência. Resposta confiante e bem escrita não é evidência de correção — é só estilo. Sempre que possível, peça à IA para mostrar a fonte, citar o padrão, ou explicar por que aquela escolha. Se ela não consegue, você não tem evidência — tem palpite com gramática boa.

A meta não é maximizar uso de IA. É **maximizar qualidade do código entregue, com o mínimo de retrabalho**. Em algumas tarefas isso significa usar IA muito; em outras, nada. As próximas seções ajudam a decidir.

## O padrão recomendado: humano dirige contrato, IA dirige implementação

O padrão que tem dado o melhor resultado é separar **contrato** de **implementação**, deixando humano dirigindo o primeiro e IA dirigindo o segundo.

**O que é contrato:**
- Arquivos `.proto` (RPCs e mensagens gRPC publicadas)
- Schemas SQL (tabelas, colunas, índices, constraints)
- Queries `sqlc` (operações de domínio sobre o banco)
- Tipos compartilhados entre serviços ou entre frontend e backend
- OpenAPI / JSON Schema de APIs públicas
- ADRs (decisões arquiteturais)

**O que é implementação:**
- Handlers (gRPC, HTTP) — tradução de protocolo para domínio
- Stores — adaptadores sqlc → tipos de domínio
- Componentes React, hooks, formulários
- Workers, jobs, schedulers
- Funções utilitárias internas a um pacote
- Testes table-driven a partir de tabela já desenhada

### Por que essa divisão

**Meia-vida.** Contrato dura anos; implementação dura meses. Schema de banco com decisão errada custa migração, downtime e arqueologia de dados. Função em Go ou componente em React mal escrito custa uma tarde de refactor. Vale alocar **atenção humana onde o custo de erro é alto** e atenção de IA onde o custo de erro é baixo.

**Impacto cross-team.** Quem muda um proto mexe em N consumidores. Quem muda um schema mexe em todo histórico de dados. Quem muda um handler mexe num arquivo. A IA otimiza para o RPC que está escrevendo agora; o humano lembra dos outros consumidores e da janela de manutenção do banco.

**Internalização do sistema.** Quem desenha contrato entende o sistema. Quem só revisa saída de IA drift de entendimento. Em 12 meses, esse drift é a diferença entre alguém que sabe o que tem que mudar quando algo quebra e alguém que precisa abrir Slack para perguntar.

**IA como compilador.** Compilador recebe entrada tipada e saída tipada, e gera código que liga os dois respeitando ambos. Esse é exatamente o regime em que IA é melhor: tradução com restrições explícitas. Quando você dá contrato bem definido, a IA tem muito menos margem de manobra — e portanto muito menos chance de inventar algo errado.

### Como aplica na prática

| Tarefa | Quem dirige |
|---|---|
| Desenhar novo serviço, definir RPCs | Humano (proto) |
| Modelar tabela nova ou índice composto | Humano (schema SQL) |
| Implementar handler que satisfaz o proto | IA (Go) |
| Implementar store que satisfaz as queries | IA (Go) |
| Escrever componente que consome tipo TS já existente | IA (TypeScript) |
| Decidir migração de schema (online vs locking) | Humano |
| Preencher casos de teste table-driven em tabela esboçada | IA |
| Decidir o nome dos casos da tabela (a regra de negócio) | Humano |
| ADR (decisão arquitetural) | Humano escreve, IA pode revisar |

### Quando o contrato é trivial

Há tarefas em que o "contrato" é evidente: adicionar uma coluna óbvia (`telefone_secundario TEXT`), expor um RPC que é só leitura de uma tabela existente, adicionar um campo a um formulário que já tem cinco outros iguais. Nesses casos, o overhead de você desenhar o contrato cuidadosamente antes vira gargalo sem ganho — a IA pode propor o pacote completo (schema + proto + código) e você só revisa.

A linha: **se a decisão é local e regenerável, IA pode propor de ponta a ponta. Se a decisão tem impacto cross-team ou cross-tempo, humano desenha.**

## A técnica das sessões separadas

Para tarefas onde a divisão contrato/implementação faz sentido, vale a pena usar **sessões distintas de IA** para cada lado — literal, abre uma nova conversa.

### Por que funciona

- **Evita pollution de contexto.** Na sessão de contrato, a IA não está pensando em implementação. Foca em modelagem. Na sessão de implementação, ela trata o contrato como dado fixo, não como sugestão.
- **Força o contrato a ser artefato.** O handoff entre sessões é literal: você fecha uma janela e abre outra. O contrato precisa estar bom o suficiente para sobreviver a esse handoff. Isso é a versão prática de "contrato é spec".
- **Reduz alucinação cruzada.** A IA na sessão de implementação não pode "ajustar o proto enquanto isso" porque não tem permissão para isso na cabeça dela. Tem que respeitar o que está dado.

### Quando vale o overhead

- Features novas com contrato não-trivial (RPC novo, tabela nova, integração externa).
- Refactors que mudam contrato (renomear proto, mover dados entre tabelas).
- Qualquer coisa que vá ser revisada por outro time.

### Quando pular

- Bug fix em código existente sem mudança de contrato.
- Tweaks de implementação que não tocam interface.
- Tarefas de menos de uma hora.
- Spikes exploratórios (round único da IA, joga fora, refaz com método se a ideia vingar).

## Onde IA é genuinamente boa

Casos onde, na nossa experiência, IA acelera muito sem perder qualidade:

- **Tradução constrita.** Implementar handler que satisfaz um proto bem definido. Implementar store que satisfaz queries sqlc já escritas. Implementar componente React que consome um tipo TS já existente.
- **Boilerplate seguindo padrão.** Depois que você implementou o primeiro handler CRUD de um padrão, IA escreve o segundo, terceiro, quarto seguindo o mesmo. Você revisa em segundos.
- **Refactor mecânico.** Renomear identificador em N arquivos. Mover função entre pacotes. Trocar `interface{}` por generic. Atualizar chamadas após mudança de assinatura.
- **Preencher casos de teste table-driven.** Você esboça os 3 primeiros casos com nomes em português; IA propõe os edge cases (input vazio, valor máximo, caracteres especiais, casos de erro). Você revisa quais fazem sentido.
- **Tradução de documentação técnica.** Resumir spec de fornecedor (Receita Federal, GSMA TS.43, RFC). Converter exemplo em uma linguagem para outra. Explicar o que faz um código alheio.
- **Exploração de API desconhecida.** "O que existe na stdlib para X?" — economiza vinte minutos de googling. Verifica depois na doc oficial antes de usar.
- **Revisão de mudanças mecânicas.** Após `goimports`, `gofmt`, refactor automatizado, IA é boa em ver se algo estranho aconteceu.
- **Mensagens de commit, descrições de PR, changelog.** A partir do diff, gerar resumo.

## Onde IA é genuinamente ruim

Casos onde o ganho de velocidade é menor que o custo de revisar atentamente e corrigir o que ela errou:

- **Modelagem de domínio com restrições não-locais.** "Como cliente se relaciona com linha?" depende de decisões anteriores em vendas, atendimento, regulatório. IA não tem esse contexto. Vai propor um modelo que parece limpo e ignora 6 meses de aprendizado do time.
- **Schema com awareness de carga.** IA escreve `ALTER TABLE ADD COLUMN NOT NULL DEFAULT ...` sem saber que sua tabela tem 50M linhas e isso vai lockar por minutos em produção. Não sabe que esse campo é lido 100x mais que escrito e poderia ser desnormalizado. Não sabe quais índices já estão pressionando os writes.
- **Decisões com impacto regulatório.** O que pode ir em log? O que precisa ser cifrado em rest? Quem pode ver esse campo? IA não conhece LGPD, ANATEL, contratos com operadoras de roaming. Decisões aqui são humanas.
- **Compatibilidade retroativa.** IA aceita renomear um campo de proto sem piscar. Não lembra que o `app-mobile` em produção ainda usa a v1. `buf breaking` só pega quebra sintática — escolha ruim que não quebra hoje mas trava evolução amanhã passa.
- **Algoritmos novos.** Se a abordagem não está no treinamento dela (provavelmente não está se é novo), IA vai propor algo plausível que provavelmente está errado sutilmente. Para isso, escreva você mesmo e use IA só para revisar.
- **Concorrência fina.** Deadlocks sutis, ordering de memória, races que só aparecem em produção. IA escreve código concorrente que "passa no teste"; o teste é incompleto. Em código de concorrência, leia cada linha duas vezes.
- **UX que depende de contexto não verbalizado.** "Esse modal deveria ter X comportamento" — IA propõe genericamente. Se você não disse que esse fluxo é usado por operador de call center com 3 segundos por chamada, IA não vai inferir.
- **Estimativa de complexidade.** Pergunte "quanto tempo isso leva?" — resposta é palpite, não estimativa.

## Como entregar contexto para IA

Qualidade da saída é proporcional à qualidade do contexto. Algumas práticas que rendem muito:

- **AGENTS.md no projeto.** Template em [`exemplos/AGENTS.md`](./exemplos/AGENTS.md). É onboarding doc — para humano novo no projeto e para IA. Preencher na criação do serviço, atualizar quando algo importante muda. Cobre visão geral, integrações, convenções específicas do serviço, gotchas conhecidos.
- **ADRs em `docs/adr/`.** Template em [`exemplos/docs/adr/0000-template.md`](./exemplos/docs/adr/0000-template.md). Antes de propor refactor arquitetural, leia os ADRs relevantes — provavelmente o assunto já foi debatido. Para IA, mencione: "leia os ADRs antes de propor".
- **Spec antes de implementação.** Quando pedir código, dê primeiro o contrato (proto, query SQL, tipo TS). A IA implementa em cima. Sem contrato, ela inventa.
- **Slice mínimo necessário, não dump.** Não cole o arquivo de 800 linhas se ela só precisa de 30. Cada token de contexto irrelevante diminui a precisão.
- **Repita constraints importantes.** "Vocabulário de domínio em português, técnico em inglês. Sem dependência nova. log/slog para log." Mesmo que estejam no AGENTS.md, repetir no pedido reforça.
- **Mostre exemplo do estilo.** Se já existem 3 handlers similares no projeto, cole um e diga "siga esse padrão". A IA mimetiza bem.

## Como validar saída de IA

Não-negociável antes de commit:

1. **Ler o código.** Linha por linha. Se você não consegue defender cada linha em revisão, não está pronto.
2. **`make lint && make test`.** Linter limpa e testes verdes. Sem exceção.
3. **Rodar o código.** Manualmente ou via teste. Código que compila não é código que funciona.
4. **Code review humano.** Por outra pessoa do time. IA revisando saída de IA é eco, não revisão.

### Failure modes específicos da nossa stack

Coisas que a IA erra com frequência e que vale ativamente caçar antes de commit:

**Go:**
- `var e *MyError; return e` quando deveria ser `return nil` — nil pointer wrapped em interface não-nil.
- `go func() { ... }()` sem ownership claro (quem espera? quem cancela? para onde vai o erro?).
- Context não propagado ou substituído por `context.Background()` no meio do call stack.
- `defer` dentro de loop ilimitado, vazando recurso.
- Map acessado concorrentemente sem mutex.
- `http.Response.Body` não fechado em caminho de erro.
- `time.Sleep` em teste de código concorrente (usar `testing/synctest`).
- Sentinela comparada por string em vez de `errors.Is`.

**TypeScript / React:**
- `any` escondido em algum lugar (use `unknown` se de fato desconhece).
- Dependency array de `useEffect` incompleta — vai dar stale closure.
- Server component fazendo `useState` (não compila, mas IA às vezes propõe).
- `useEffect` para sincronizar com prop — quase sempre é derivação, não efeito.
- Fetch sem tratamento de erro nem loading state.
- Form submission sem `e.preventDefault()`.

**SQL / sqlc:**
- Query sem `LIMIT` em endpoint que pode retornar muito.
- `JOIN` sem usar índice (rode `EXPLAIN ANALYZE` antes de aceitar).
- Migration que não pode rodar online em tabela grande.

### Desconfiar de "parece certo"

A IA escreve código que parece estar certo. Esse é o problema. Quanto mais bem escrito, mais perigoso quando errado, porque você baixa a guarda. Heurísticas:

- Se o código é trivial e parece certo, provavelmente está certo.
- Se o código é complexo e parece certo, **especialmente** desconfie. Releia. Procure pelo bug.
- Se você não entende uma linha, não comite essa linha. Peça para a IA explicar; se a explicação não convence, refaça à mão.

## Workflow por tipo de tarefa

### Feature nova

1. Humano: desenhar contrato (proto + schema SQL ou tipos TS).
2. Humano: esboçar tabela de testes em português (a spec de comportamento).
3. **(Nova sessão)** IA: implementar handler/store/componente que satisfaz contrato + tabela.
4. Humano: revisar, rodar, ajustar.
5. Humano: integração end-to-end.

### Bug fix

1. Humano: escrever teste que reproduz o bug.
2. IA: propor fix (ou humano, dependendo da complexidade).
3. Humano: revisar que o fix não introduz outro bug.
4. Commit do teste + fix juntos.

### Refactor

1. Garantir testes existentes cobrem o comportamento (sem testes, escreva primeiro).
2. IA: aplicar refactor.
3. Rodar testes — devem passar sem alteração.
4. Revisar diff.

### Spike / exploração

1. Round único da IA, sem cerimônia.
2. Verificar manualmente.
3. **Joga fora.**
4. Se a ideia vingar, refaça com método (workflow de feature nova).

### Onboarding em código novo

Use IA para **explicar**, não para mexer. "O que faz esse arquivo? Por que essa decisão?". A IA é boa em resumir. Use até entender; depois desligue.

### Investigação / debug

IA é útil para hipóteses (`"esse traceback sugere quê?"`) e para explorar áreas desconhecidas do código. Não confie em diagnóstico final dela — verifique você mesmo no código real.

## Anti-padrões

Padrões que parecem produtivos no momento e mordem depois:

- **Deixar IA desenhar banco do zero.** Coberto na seção 5. Schema é decisão de longo prazo; merece humano.
- **Aceitar proto da IA sem rodar `buf breaking` contra main.** Mesmo que o lint passe, pode estar quebrando consumidor.
- **Ignorar warning de linter porque "a IA escreveu, deve estar certo".** Linter está alertando exatamente porque a IA cometeu um erro comum.
- **Misturar contextos em uma sessão.** Proto + Go + revisão de PR de outra pessoa + dúvida de TypeScript numa janela só. A IA perde fio, você perde foco. Abra sessões separadas.
- **Pedir refactor sem testes que provem comportamento atual.** Sem rede de segurança, refactor com IA vira loteria.
- **Commitar código que você não leu.** Mesmo que tudo passe. Se você não pode defender, não pode comitar.
- **Usar IA para evitar entender o sistema.** Por dois meses parece eficiente; no terceiro mês, você não consegue depurar nada sem perguntar. Esse buraco é fundo.
- **Sessões longas demais.** Após uns ~30 turnos, o contexto degrada. Saída fica errática, IA esquece constraints que você falou no início. Saia, salve o que serve, comece nova sessão com o estado atual.
- **Pedir múltiplas mudanças não relacionadas no mesmo turno.** A IA tenta fazer tudo, e tipicamente erra em alguma. Uma mudança por turno, revisada.
- **Tratar saída de IA como argumento de autoridade em discussão técnica.** "A IA disse que..." não é evidência. O código é evidência; o benchmark é evidência; a doc oficial é evidência.

## Postura cética saudável

Algumas perguntas que vale ter no holster:

- **"Por que essa escolha?"** A pergunta mais útil. Se a IA não consegue justificar, você não tem evidência — tem palpite.
- **"Qual a alternativa? Por que essa é melhor?"** Força a IA a considerar trade-off em vez de propor a primeira ideia plausível.
- **"Onde isso pode dar errado?"** Pede análise de failure mode. Saída costuma ser útil mesmo quando a implementação está correta.
- **"Mostra a fonte / link da doc oficial."** Para qualquer afirmação sobre API, biblioteca, padrão. Se a IA inventa link (acontece), você descobre.

### Quando IA está confiante e errada

Os piores casos são quando a IA está confiante numa resposta errada. Sinais:

- Cita API ou função que não existe (alucinação).
- Justifica com referência a "best practice" sem fonte.
- Responde rápido demais para a complexidade da pergunta.
- Dá uma resposta inconsistente quando você pergunta de outra forma.

Quando suspeitar, peça **referência verificável** (doc oficial, RFC, código real do projeto). Se ela não consegue dar, trate como hipótese, não como resposta.

### Reconhecer ignorância mútua

Há perguntas para as quais nem você nem a IA têm resposta. Reconhecer isso explicitamente economiza tempo. "Não sabemos qual abordagem é melhor sem testar; vamos prototipar as duas em meia hora." É melhor que três rodadas de IA dando palpite plausível.

### Quando parar de iterar

Sinais de que você deveria sair e fazer manualmente:

- Já é a quarta correção do mesmo bug introduzido pela IA.
- A IA está pedindo desculpa em todo turno.
- Você está reescrevendo mentalmente a saída antes de ler.
- A solução manual seria mais rápida que a próxima iteração.

Não é fracasso desligar. É calibração.

### Sinais de que você virou dependente

Vale autoaudit periódica:

- Você não consegue mais começar tarefa sem abrir IA.
- Você não consegue mais explicar partes do código que você comitou semana passada.
- Sua produtividade some quando a IA está fora do ar.
- Você defere decisões técnicas para "ver o que a IA acha".

Nenhum desses por si é alarme. Os quatro juntos são. Resolva fazendo as próximas tarefas sem IA por uma semana — re-calibra a relação.

## Recursos

- [Workflow spec-first no SKILL.md de Go](./skills/golang-development/SKILL.md) — sequência canônica `.proto → SQL → testes → implementação`.
- [AGENTS.md template](./exemplos/AGENTS.md) — contexto de serviço para humano e IA.
- [ADR template](./exemplos/docs/adr/0000-template.md) — formato Nygard.
- [ADR de exemplo](./exemplos/docs/adr/0001-eventos-de-cobranca-via-outbox.md) — decisão real com alternativas e trade-offs.
- [Convenção de idioma](./convencao_de_idioma.md) — domínio em PT, técnico em EN, consistente em todas as camadas. Especialmente importante quando IA está envolvida.

## Como este documento evolui

Como todos os outros guidelines: muda com base em coisas concretas que vivenciamos, não em artigos novos ou ferramentas que apareceram. Se você experimentou um padrão que funcionou bem por meses (ou um que mordeu várias vezes), traga para discutirmos a inclusão. Se algo aqui parar de fazer sentido para um problema que você tem, questione — e se divergir, registre o motivo no README do serviço.

Esse documento é deliberadamente agnóstico de modelo e ferramenta. Claude, Cursor, Copilot, o que vier amanhã — os princípios sobrevivem. Quando a recomendação depende da ferramenta específica, ela envelhece em meses; quando depende do princípio (separar contrato de implementação, validar saída, manter entendimento), sobrevive.
