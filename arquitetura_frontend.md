# Diretrizes de Arquitetura Frontend (TypeScript)

Um padrão pragmático para nossas aplicações frontend.

## Como ler este documento

Este documento existe porque temos visto código sendo escrito com base em padrões reconhecidos (Clean Architecture, Hexagonal, Atomic Design) sem que os desenvolvedores consigam explicar *por que* aqueles padrões foram escolhidos. Aplicar arquitetura sem entender o porquê é cargo cult — você paga o custo da complexidade sem colher o benefício, porque o benefício depende de tomar decisões discriminadas que a arquitetura sozinha não toma por você.

A regra para ler este documento é: cada decisão tem que vir com uma justificativa. Se você ler uma seção e a justificativa não fizer sentido para o seu caso específico, *questione*. Padrão sem fundamento é peso morto. Padrão com fundamento é ferramenta. Você está autorizado, e na verdade encorajado, a contestar qualquer coisa aqui que não pareça defensável para o problema concreto que você está resolvendo.

A segunda regra é: tudo tem custo. Cada camada de abstração, cada componente novo, cada biblioteca, cada padrão arquitetural — tudo cobra alguma coisa. O cobrar pode ser em performance (re-renders, bundle size, tempo de build), em manutenibilidade (mais código para entender), ou em onboarding (tempo até alguém novo conseguir contribuir). Quando você adota algo, pergunte: o que isto custa, e o que ganho em troca? Se você não consegue articular o ganho, provavelmente não está ganhando nada.

Não queremos rediscutir arquitetura toda vez que iniciamos um novo projeto. Este documento é o padrão. Siga-o, a menos que você consiga articular uma razão técnica específica para divergir. Se divergir, registre o motivo no README do serviço para que futuros leitores entendam a escolha.

## Por que este documento existe

Não queremos rediscutir arquitetura toda vez que iniciamos um novo projeto frontend. Este documento é o padrão. Siga-o, a menos que você consiga articular uma razão técnica específica para divergir. Se divergir, registre o motivo no README do projeto.

O objetivo é consistência informada, não obediência cega. Um time que entende por que faz o que faz produz código melhor do que um time que segue regras mecanicamente.

## Postura

Construímos aplicações que servem áreas de negócio específicas (vendas, atendimento). Cada aplicação é um deployable independente, é a camada de experiência descrita no [`arquitetura_plataforma.md`](./arquitetura_plataforma.md), e é mantida pelo time da área de negócio correspondente.

Estas aplicações **não têm banco de dados de domínio próprio** e **não contêm regra de negócio** — quem é dono de dado e regra é a camada de domínio (serviços Go + gRPC). A aplicação cuida de renderização, sessão, orquestração de chamadas e modelagem de dado para tela.

No web, usamos **Next.js fullstack**: o próprio servidor Next.js é a camada de experiência, e a "camada de dados" da aplicação, em vez de bater em banco, **fala gRPC com os serviços de domínio, server-side** (via ConnectRPC / cliente gRPC tipado). O browser conversa com o servidor Next.js; o servidor Next.js conversa com o domínio. Isso é detalhado na seção [Camada de dados](#camada-de-dados-a-experiência-fala-grpc-com-o-domínio).

No mobile, o app não fala gRPC com o domínio direto — ele fala com um **BFF dedicado e fino** (um por app, em Go) que traduz o gRPC publicado pelos domínios para o que aquele app precisa. Ver [Web versus mobile](#web-versus-mobile).

**Não** adotamos arquiteturas pesadas como Clean Architecture ou Hexagonal Architecture nos projetos frontend. Esses padrões resolvem problemas que existem em sistemas de longa duração com lógica de domínio rica e múltiplos clientes — o que se aplica ao backend, não ao frontend de uma aplicação web. Frontend tem natureza diferente: a "lógica de negócio" mora no backend, o frontend coordena interface, estado de UI, e chamadas para APIs. Aplicar arquitetura desenhada para isolar lógica de domínio em uma camada que *não tem* lógica de domínio é cerimônia sem benefício.

No lugar disso, usamos uma arquitetura simples e pragmática: organização por feature, componentes coesos, separação clara entre lógica de UI e chamadas de dados, e disciplina sobre onde cada tipo de código mora.

## App Router e Server Components

Usamos o App Router do Next.js. Se algum projeto ainda está em Pages Router, isso fica registrado como dívida técnica e é migrado quando há oportunidade. Não criamos projetos novos em Pages Router.

A distinção entre Server Components e Client Components é a decisão arquitetural mais importante que você toma em cada arquivo. Por padrão, todo componente é Server Component. Você adiciona `"use client"` apenas quando precisa de interatividade (estado, eventos, hooks como `useState`, `useEffect`).

A regra prática: empurre `"use client"` o mais para baixo possível na árvore. Componentes de página, layout, e seções estáticas devem ser Server Components. Apenas o componente específico que precisa de interatividade vira Client Component. Isso reduz JavaScript enviado ao browser, melhora performance inicial, e mantém lógica de busca de dados no servidor.

Por que isto importa: cada Client Component é JavaScript que precisa ser baixado, parseado, e executado no browser do usuário. Um botão interativo dentro de uma página estática deve ser o único Client Component daquela página, não a página inteira. Times que não internalizam isso acabam com aplicações Next.js que entregam tanto JavaScript quanto uma SPA tradicional, perdendo o benefício principal da arquitetura.

## Estrutura de diretórios padrão

```
app/                          # App Router do Next.js
  (marketing)/                # Route group para páginas públicas
    page.tsx
    layout.tsx
  (dashboard)/                # Route group para área autenticada
    assinantes/
      page.tsx                # Server Component, lista assinantes
      [id]/
        page.tsx              # Detalhes do assinante
        editar/
          page.tsx
    faturas/
      page.tsx
    layout.tsx                # Layout compartilhado da área autenticada
  api/                        # Route handlers, se necessário
    webhooks/
      route.ts
  layout.tsx                  # Root layout
  globals.css

components/                   # Componentes reutilizáveis
  ui/                         # Componentes de UI puros (botão, input, etc)
    Button.tsx
    Input.tsx
  features/                   # Componentes específicos de features
    assinantes/
      ListaAssinantes.tsx
      CardAssinante.tsx
      FormAssinante.tsx

lib/                          # Código compartilhado não-componente
  api/                        # Clientes gRPC tipados (ConnectRPC) para os domínios
    clientes.ts               # usados server-side (RSC / Server Actions)
    faturas.ts
  utils/                      # Helpers genuínos (formatação, validação)
    formatarCPF.ts
    formatarMoeda.ts
  types/                      # Tipos TypeScript compartilhados
    assinante.ts
    fatura.ts

hooks/                        # Custom hooks reutilizáveis
  useAssinante.ts
  useDebounce.ts

gen/                          # Tipos/clientes gerados dos .proto (buf) — não editar
  clientes/v1/

public/                       # Assets estáticos
```

Notas sobre essa estrutura:

`app/` é exclusivamente para roteamento — páginas, layouts, e route handlers. Componentes que não são páginas não moram aqui. Os parênteses em `(marketing)` e `(dashboard)` criam route groups, que organizam o código sem afetar a URL.

`components/ui/` versus `components/features/` é uma divisão importante. `ui/` contém componentes genéricos sem conhecimento de domínio — um botão é um botão, não importa se é botão de cadastrar assinante ou de gerar fatura. `features/` contém componentes que conhecem o domínio — um `CardAssinante` sabe o que é assinante, sabe quais campos exibir, sabe formatar MSISDN. Essa separação importa porque componentes de `ui/` são reutilizáveis entre features, e componentes de `features/` não são (e nem deveriam ser).

`lib/` é onde mora código que não é componente React. Clientes de API, helpers, tipos. Não criamos pasta `utils/` solta porque ela vira gaveta de bagunça (mesmo princípio do backend). `lib/utils/` ainda é um nome ruim, mas pelo menos contido — e dentro dela, cada arquivo tem nome descritivo: `formatarCPF.ts`, não `helpers.ts`.

`hooks/` é separado de `lib/` porque hooks são código React (precisam ser usados dentro de componentes), e a separação visual ajuda a navegar.

## Princípios

**Páginas são Server Components por padrão.** Toda `page.tsx` deve ser Server Component a menos que tenha razão concreta para virar Client. Isso permite buscar dados diretamente no servidor (sem `useEffect` + `fetch`), reduz JavaScript no client, e melhora SEO.

**Buscar dados no nível mais alto possível, passar para baixo via props.** Não faça components filhos buscarem seus próprios dados se a página pai já está buscando. Não use `useEffect + fetch` em Client Components quando o pai poderia ter buscado no servidor. O padrão é: Server Component busca dados, passa via props para Client Components que precisam de interatividade.

**`"use client"` é uma fronteira, não uma decoração.** Quando você marca um componente como Client, ele e tudo que ele importa diretamente vai para o bundle do client. Componentes filhos passados como children continuam podendo ser Server Components (isto é uma sutileza importante do React Server Components que vale dominar). Em geral: minimize a árvore que vira Client.

**Componentes têm uma responsabilidade.** Um componente que busca dados, formata dados, gerencia estado de formulário, e renderiza tabela está fazendo coisas demais. Quebra em componentes menores: um para buscar, um para formatar, um para o formulário, um para a tabela. A regra prática: se você precisa de mais de duas frases para explicar o que um componente faz, ele faz coisas demais.

**Estado mora onde é usado, sobe quando precisa ser compartilhado.** Não comece com gerenciamento de estado global. Comece com `useState` no componente que precisa. Suba o estado para o pai quando dois irmãos precisam dele. Use Context apenas quando muitos componentes em níveis diferentes precisam acessar o mesmo estado. Use bibliotecas externas (Zustand, Jotai) apenas quando Context não dá conta — e isso é mais raro do que parece.

**Lógica de negócio fica no backend.** Frontend valida formato (CPF tem 11 dígitos, email tem `@`), backend valida regras de negócio (CPF existe, email não está em uso, assinante pode ser cadastrado). Toda validação de formato no frontend deve ser duplicada no backend, porque o frontend não é confiável. Frontend que tenta calcular preços, aplicar descontos, ou tomar decisões de negócio é fonte de bug — sempre vai estar dessincronizado com o backend, sempre vai ser contornado por alguém manipulando a requisição.

## Server Components vs Client Components na prática

Esta é a parte mais nova e mais mal-compreendida do Next.js, então vai com mais detalhe.

### Quando usar Server Component (padrão)

Páginas que apenas exibem dados. Layouts. Componentes que buscam dados de APIs ou banco. Componentes que renderizam markdown ou conteúdo estático. Tudo isso roda no servidor, retorna HTML pronto, e não envia JavaScript para o client.

```tsx
// app/(dashboard)/assinantes/page.tsx
// Server Component (sem "use client")

import { listarAssinantes } from "@/lib/api/assinantes";
import { TabelaAssinantes } from "@/components/features/assinantes/TabelaAssinantes";

export default async function PaginaAssinantes() {
  // Busca rodando no servidor, sem useEffect
  const assinantes = await listarAssinantes();
  
  return (
    <div>
      <h1>Assinantes</h1>
      <TabelaAssinantes assinantes={assinantes} />
    </div>
  );
}
```

### Quando usar Client Component

Sempre que você precisa de:

Estado local com `useState`. Efeitos com `useEffect`. Event handlers (`onClick`, `onChange`, `onSubmit`). Hooks do React (`useContext`, `useReducer`, hooks customizados). Browser APIs (`window`, `localStorage`, `navigator`). Bibliotecas que dependem de coisas do browser.

```tsx
// components/features/assinantes/FormBuscaAssinante.tsx
"use client";

import { useState } from "react";

export function FormBuscaAssinante({ onBuscar }: Props) {
  const [msisdn, setMsisdn] = useState("");
  
  return (
    <form onSubmit={(e) => {
      e.preventDefault();
      onBuscar(msisdn);
    }}>
      <input
        value={msisdn}
        onChange={(e) => setMsisdn(e.target.value)}
        placeholder="MSISDN"
      />
      <button type="submit">Buscar</button>
    </form>
  );
}
```

### O padrão "ilha de interatividade"

A composição que mais funciona: página é Server Component, a maior parte dela é HTML estático, e apenas as partes interativas são Client Components específicos.

```tsx
// app/(dashboard)/assinantes/[id]/page.tsx
// Server Component

import { buscarAssinante } from "@/lib/api/assinantes";
import { DadosAssinante } from "@/components/features/assinantes/DadosAssinante";
import { BotaoSuspenderLinha } from "@/components/features/assinantes/BotaoSuspenderLinha";

export default async function PaginaDetalhesAssinante({ params }: Props) {
  const assinante = await buscarAssinante(params.id);
  
  return (
    <div>
      {/* DadosAssinante é Server Component, renderiza HTML puro */}
      <DadosAssinante assinante={assinante} />
      
      {/* BotaoSuspenderLinha é Client Component, "use client" */}
      <BotaoSuspenderLinha linhaId={assinante.linhaPrincipalId} />
    </div>
  );
}
```

A página inteira é Server Component, só o botão é Client Component. JavaScript enviado ao browser: apenas o botão. Performance ótima, código simples.

## Convenção de idioma

Aplicamos a mesma convenção do backend (ver documento `convencao-de-idioma.md`): vocabulário do domínio em português, vocabulário técnico em inglês.

```tsx
// Bom
type Assinante = {
  id: string;
  cpf: string;
  nome: string;
  msisdn: string;
  situacaoCadastral: SituacaoCadastral;
};

function CardAssinante({ assinante }: Props) {
  return (
    <div className="card">
      <h2>{assinante.nome}</h2>
      <p>CPF: {formatarCPF(assinante.cpf)}</p>
      <p>Linha: {formatarMSISDN(assinante.msisdn)}</p>
    </div>
  );
}

// Ruim: domínio em inglês
type Subscriber = {
  id: string;
  taxId: string;
  name: string;
  phoneNumber: string;
};
```

Termos técnicos do React e Next.js ficam em inglês: `props`, `state`, `effect`, `ref`, `component`, `layout`, `route`, `params`, `searchParams`. Não traduza estes.

## Gerenciamento de estado

A maioria dos times frontend chega rápido em "precisamos do Redux" (ou Zustand, ou Jotai, ou MobX), e a maioria delas estaria melhor se não tivesse chegado. Comece simples e suba a complexidade só quando o problema concreto exige.

A escada de estado, do mais simples ao mais complexo:

**Estado local com `useState`.** Para qualquer estado que vive em um componente. Formulários, toggles, hover, expansão de seções. Comece sempre aqui.

**Lifted state.** Quando dois irmãos precisam compartilhar estado, sobe para o pai e passa via props. Não pula direto para Context ou biblioteca externa.

**URL state via `searchParams`.** Para estado que faz sentido sobreviver a refresh ou ser compartilhável via link: filtros de busca, paginação, ordenação. Use `useSearchParams()` do Next.js. Bonus: estado na URL melhora UX significativamente.

**Server state via RSC + cache do Next.js.** Dados vindos do domínio não são "estado da aplicação" — são cache de estado do servidor. Como buscamos via gRPC server-side em Server Components, o caminho padrão é deixar o Next.js cachear (`revalidate`, tags de cache) e revalidar nas Server Actions. Só caia para TanStack Query (antigo React Query) no caso de borda em que um Client Component precisa buscar dado dinamicamente — e, mesmo aí, ele bate num route handler seu, não no domínio. Não coloque dados de servidor no Redux.

**Context API.** Para estado que muitos componentes em níveis diferentes precisam acessar mas não muda com frequência: tema, autenticação, configurações do usuário. Não use Context para estado que muda muito — provoca re-renders em cascata.

**Biblioteca externa (Zustand, Jotai).** Apenas quando os anteriores não dão conta. Casos legítimos: estado complexo de UI compartilhado entre muitos componentes (carrinho de compras, builder de formulário multi-step), undo/redo, sincronização entre abas. Se você está reaching for Zustand para um formulário simples, está usando ferramenta errada.

A pergunta que destranca esta decisão: *quem precisa deste estado?* Se a resposta é "este componente", `useState`. Se é "este componente e seus filhos", lifted state. Se é "vários lugares da aplicação que não tem relação de parentesco", aí sim considere Context ou biblioteca.

## Camada de dados: a experiência fala gRPC com o domínio

Esta é a fronteira entre a aplicação e o resto da plataforma, e a regra estruturante é simples: **a camada de dados da aplicação não bate em banco; ela fala gRPC com os serviços de domínio, sempre server-side.**

Os clientes gRPC ficam em `lib/api/`, gerados a partir dos `.proto` publicados pelos domínios e consumidos via **ConnectRPC** (cliente gRPC tipado). Uma função por operação de domínio, tipagem vinda do contrato, tratamento de erro consistente. Esses clientes são instanciados e usados **no servidor** — em Server Components e Server Actions —, nunca no browser.

```ts
// lib/api/clientes.ts
import { createClient } from "@connectrpc/connect";
import { createGrpcTransport } from "@connectrpc/connect-node";
import { ServicoClientes } from "@/gen/clientes/v1/clientes_pb";

// Transport server-side: fala gRPC direto com o domínio, dentro da rede.
const transport = createGrpcTransport({
  baseUrl: process.env.CLIENTES_GRPC_URL!, // endereço interno do serviço de domínio
});

const cliente = createClient(ServicoClientes, transport);

export async function listarClientes() {
  // Tipos vêm do .proto — sem modelagem paralela no front.
  const { clientes } = await cliente.listarClientes({});
  return clientes;
}

export async function buscarCliente(id: string) {
  // O erro gRPC (ex.: NOT_FOUND) chega tipado; traduza para o que a tela precisa.
  return cliente.buscarCliente({ id });
}
```

Três pontos importam aqui:

**Server-side, sempre.** O `baseUrl` é um endereço interno da rede; o token de serviço, os segredos e o tráfego gRPC nunca chegam ao browser. Por isso o cliente é importado só por Server Components e Server Actions. Marcar um arquivo de `lib/api/` como acessível ao client é um erro — vaza credencial e expõe o domínio.

**Sem modelagem de dado paralela.** Os tipos vêm do `.proto` gerado em `gen/`. A aplicação não redefine `Cliente` à mão; ela usa o tipo do contrato. Se a tela precisa de um formato diferente, a transformação é explícita e fica na fronteira (um mapeamento na função de `lib/api/`), não espalhada pelos componentes.

**Leitura e mutação têm caminhos distintos:**

- **Leitura:** Server Components chamam as funções de `lib/api/` diretamente, no render do servidor. Sem `useEffect`, sem fetch no client.
- **Mutação:** use **Server Actions**. A action roda no servidor, chama o cliente gRPC, e revalida o que precisa. O Client Component invoca a action; ele nunca fala com o domínio direto.
- **Caso de borda:** quando uma interação client-side precisa buscar dado sem recarregar a página (scroll infinito, busca incremental), exponha um **route handler** do Next.js que, no servidor, chama o mesmo cliente de `lib/api/`. O browser fala com o seu route handler; o route handler fala gRPC com o domínio. Mesmo nesse caso, o browser nunca toca o gRPC do domínio.

```tsx
// app/(dashboard)/clientes/acoes.ts
"use server";

import { suspenderLinha } from "@/lib/api/linhas";
import { revalidatePath } from "next/cache";

export async function acaoSuspenderLinha(linhaId: string) {
  // Roda no servidor: chama o domínio via gRPC e revalida a tela.
  await suspenderLinha({ linhaId });
  revalidatePath("/clientes");
}
```

Essa centralização tem os benefícios de sempre — tipagem e tratamento de erro num lugar só, fácil de mockar em teste — e mais um, específico do gRPC: o contrato `.proto` é a fonte de verdade dos tipos, então o front não pode divergir silenciosamente do que o domínio expõe. Quando o `.proto` muda de forma incompatível, o build quebra, que é exatamente o que você quer.

## Web versus mobile

As duas plataformas chegam ao domínio de jeitos diferentes, e a diferença é deliberada.

**Web (Next.js fullstack).** O servidor Next.js já é um backend; ele fala gRPC com o domínio server-side, como descrito acima. Não há um BFF separado para o web — o "BFF" é o próprio servidor Next.js. Construir um serviço BFF adicional só para o web seria uma camada de rede a mais sem benefício, já que o Next.js server-side resolve exatamente esse papel.

**Mobile (app nativo + BFF dedicado).** O app mobile não consegue (nem deve) carregar a lógica de orquestração e os segredos de serviço que o servidor Next.js carrega, e o ciclo de release de app é lento demais para acoplar a evolução dos contratos de domínio. Por isso o mobile fala com um **BFF dedicado e fino, um por app, escrito em Go**, que traduz o gRPC publicado pelos domínios para o que aquele app precisa. Esse BFF cai no padrão "mais simples que o padrão" do [`arquitetura_backend.md`](./arquitetura_backend.md#quando-divergir): tipicamente um único pacote com handlers e os clientes gRPC dos domínios, sem pastas de feature.

O que o BFF mobile é e o que não é:

- **É** uma camada de experiência (como o servidor Next.js), só que para o app. Faz agregação para tela, modela payload para o app, cuida de sessão/token do app.
- **Não é** um domínio. Não é dono de dado nem de regra. Não tem banco de domínio. Se você se pegar colocando regra de negócio no BFF mobile, ela está na camada errada — sobe para o domínio.
- **Não é** compartilhado entre apps. Um BFF por app evita que o BFF vire um mini-`crm_gateway` acoplando apps que evoluem em ritmos diferentes. Se dois apps precisam exatamente da mesma coisa, isso é coincidência até prova em contrário.

A regra que vale para os dois: a orquestração de fluxo cross-domínio mora na camada de experiência (servidor Next.js ou BFF mobile), nunca em um domínio chamando outro em cadeia. É o ponto tratado em [`arquitetura_plataforma.md`](./arquitetura_plataforma.md).

## Componentes: princípios concretos

**Props mínimas.** Um componente deve receber só o que precisa. Não passe um objeto inteiro se o componente usa três campos. Isso facilita teste, reuso, e leitura.

**Composição sobre configuração.** Em vez de um componente com vinte props para controlar variações, prefira componentes pequenos compostos. `<Card><CardHeader/><CardBody/></Card>` é melhor que `<Card title="..." showHeader={true} bodyContent="..." />`.

**Componentes "burros" sempre que possível.** Componentes que apenas recebem props e renderizam são fáceis de testar, fáceis de reutilizar, e fáceis de entender. Componentes que buscam dados, gerenciam estado, e renderizam misturam preocupações. Separe quando possível.

**Tamanho máximo razoável: ~150 linhas.** Não é regra rígida, é alarme. Se um componente passa de 150 linhas, provavelmente está fazendo coisas demais e deveria ser quebrado. Componentes pequenos são mais fáceis de tudo: ler, testar, modificar, reusar.

## Bibliotecas: defaults e cuidados

**Que usamos:**

`next` — o framework. Versão atual é a do projeto, atualizada com discussão.

`react`, `react-dom` — bases. Versões dependem da versão do Next.

`typescript` — sempre. Configurado em modo estrito.

`tailwindcss` — para estilização. Padronização e produtividade fortes.

`@connectrpc/connect` + `@connectrpc/connect-node` — clientes gRPC tipados para falar com os domínios server-side. É a base da camada de dados; os tipos saem dos `.proto` publicados, gerados em `gen/` via `buf`.

**Que consideramos caso a caso:**

`@tanstack/react-query` — quando o cache integrado do Next.js não dá conta de cenários client-side complexos.

`zod` — para validação de schemas e parsing seguro. Ótimo para validar dados que vêm de APIs ou de formulários.

`react-hook-form` — para formulários complexos. Para formulários simples, estado local resolve.

`zustand` — quando precisa de estado global e Context não dá conta.

**Que tratamos com cuidado:**

Bibliotecas pequenas de "utilitário" do npm para coisas que JavaScript moderno já faz. Não use uma biblioteca de 500 linhas para fazer debounce — escreva 5 linhas. O ecossistema npm tem incidentes regulares de supply chain (left-pad, event-stream), e cada dependência adiciona risco. Aplique o princípio do backend: tier 4 é "não" por padrão.

Bibliotecas que adicionam runtime grande para resolver problemas pequenos. Adicionar 50KB no bundle para um componente que aparece em uma página é troca ruim.

Bibliotecas que estão em alta no Twitter mas não tem tração real. Frontend tem ciclos de hype curtos. Espere uma ferramenta provar valor antes de adotar.

## Performance: vocabulário de custo

Esta seção existe porque é onde mais vejo desenvolvedores frontend perdendo a categoria "isso tem custo". Todas as decisões abaixo têm custo concreto que, se você não sente, vai produzir aplicações lentas sem entender por quê.

**Cada componente Client Component é JavaScript no browser.** Bundle size importa. Cada KB extra é tempo de download (especialmente em 3G), tempo de parse, tempo de execução. Em mobile, isso é segundos de diferença em first interactive. Empurre interatividade para baixo na árvore.

**Cada `useEffect` é trabalho que roda em todo render.** Não use `useEffect` para coisas que poderiam ser computadas no render. Não busque dados em `useEffect` se Server Component pode fazer no servidor. Não sincronize estado com `useEffect` quando lifting state resolve.

**Cada re-render é trabalho.** Componente re-renderiza quando props mudam ou estado muda. Componente que recebe objeto recriado a cada render do pai vai re-renderizar sempre. Use `useMemo` para valores caros e `useCallback` para callbacks passados a componentes memoizados — mas só quando o profiling mostra problema. Otimização preventiva é tempo desperdiçado.

**Imagens são o maior custo de performance em sites comuns.** Use `next/image`. Não use `<img>` direto. Imagens otimizadas, lazy loading, e dimensões corretas fazem diferença grande em Core Web Vitals.

**Listas grandes precisam de virtualização.** Renderizar tabela com 10.000 linhas trava o browser. Use `react-window` ou `react-virtual` para listas longas. Mas: a maioria das "listas grandes" são páginas com 50 itens, e virtualização é overkill. Meça antes de otimizar.

**Cache é seu amigo.** O cache automático de `fetch` do Next.js **não** cobre chamadas gRPC — elas não passam por `fetch`. Para cachear leitura de domínio, envolva a chamada do cliente gRPC em `unstable_cache` (ou `cache()` do React para deduplicação por request) e invalide com `revalidateTag` / `revalidatePath` nas Server Actions. Para dados que raramente mudam (lista de planos, lista de operadoras), cache longo é correto. Não desabilite cache "para garantir dados atualizados" sem entender o custo — você está pagando latência e carga no domínio por algo que talvez não precisava.

## Quando divergir deste documento

Este padrão serve para a maioria dos projetos frontend de aplicação interna ou para clientes. Casos onde você deve divergir e justificar:

**Site institucional ou marketing puro.** Pode ser SSG simples, sem necessidade de muita estrutura. Adapte para menos.

**Aplicação altamente interativa estilo SaaS dashboard com muito estado client-side.** Pode justificar mais Client Components, biblioteca de estado, e padrões mais sofisticados. Mas: a maioria dos "dashboards complexos" não precisam disso.

**Aplicação mobile-first com requisitos extremos de performance.** Pode justificar otimizações que normalmente não fazemos.

Em qualquer caso de divergência, registre no README do projeto: o que está sendo feito diferente, e por quê.

## Coisas que evitamos explicitamente

**Aplicar Clean Architecture, Hexagonal, ou DDD em frontend.** Esses padrões resolvem problemas que frontend não tem. Times que aplicam isso em frontend acabam com pastas vazias chamadas `domain/entities/` e `infrastructure/adapters/` que apenas movem código entre arquivos sem benefício.

**Atomic Design como religião.** A divisão atoms/molecules/organisms/templates/pages parece elegante e raramente sobrevive contato com a realidade. Um botão é "atom"? E um botão com loading state? E um botão que abre modal? A taxonomia gera mais debate do que clareza. Use a divisão `ui/` versus `features/` que é mais simples e mais útil.

**Reescrever para o framework da moda.** Vue → React → Svelte → Solid → próximo. Cada migração custa meses e raramente entrega valor real. Atualize com cuidado, migre com motivo concreto.

**Microfrontends.** Resolvem problema de escala organizacional (centenas de times trabalhando no mesmo frontend). Para nossos times, é complexidade pura sem benefício.

**Custom design systems do zero.** Construir Button, Input, Modal do zero parece divertido e custa anos de desenvolvimento e manutenção. Use bibliotecas como shadcn/ui, Radix, ou Headless UI como base, e customize. Construir do zero só faz sentido se você tem time dedicado a isso.

## Recursos para aprofundar

Há uma skill operacional do time, [`skills/frontend-nextjs`](./skills/frontend-nextjs/SKILL.md), que destila este documento em checklist e receitas (com código de ConnectRPC, Server Actions e route handlers em `references/data-layer.md`). Use-a no dia a dia; este documento é a fonte do *porquê*.

A documentação oficial do Next.js está atualmente entre as melhores documentações de framework que existem. A seção "App Router" e "Server Components" são leitura obrigatória.

A documentação do React beta (react.dev) é a referência atual. Esqueça tutoriais antigos com classes — React moderno é hooks e Server Components.

Para entender o porquê do React Server Components, vale a pena ler o post original do time do React ("Introducing Server Components", Dan Abramov). Não é leitura curta mas explica o motivo das mudanças.

Para performance, "Web Vitals" do Google e a ferramenta Lighthouse do Chrome são essenciais. Não dá para melhorar o que você não mede.

## Como este documento evolui

Esta diretriz está errada em pontos que ainda não descobrimos. O ecossistema frontend muda mais rápido que backend, então revisões serão mais frequentes. Quando algo mudar significativamente (como aconteceu com a transição Pages Router → App Router), atualizamos.

Propostas de mudança devem citar coisas concretas: bug que vimos, performance que medimos, dor de manutenção que enfrentamos. Não mudamos por ter visto blog post novo no Twitter.

A arquitetura é uma ferramenta para parar de debater arquitetura. A consistência informada é o valor. Escolha entender, depois escolha se comprometer.