---
name: frontend-nextjs
description: Use this skill whenever the user is writing, reviewing, debugging, or designing frontend code for our web applications — Next.js (App Router), React, TypeScript. Triggers include any mention of `.tsx`/`.ts` files in an app, `page.tsx`, `layout.tsx`, Server Components, Client Components, `"use client"`, Server Actions, route handlers, hooks (`useState`, `useEffect`), Tailwind, ConnectRPC / gRPC clients in the frontend, `lib/api/`, data fetching for screens, forms, or "build a screen/page/component". Also use for the mobile experience layer when it means the thin per-app BFF that translates published gRPC for the app. Pushy use: even for "small" frontend questions, consult this skill — the data layer is gRPC server-side (never REST, never DB), the PT/EN idioma rule applies, and Server vs Client component boundaries are easy to get wrong. Do NOT use for Go backend/domain services (use golang-development) or for proto/SQL contract design (use arquiteto-backend-telecom).
---

# Frontend — Next.js (App Router) + TypeScript

Skill para construir a **camada de experiência web** do time: aplicações Next.js fullstack que consomem os domínios via gRPC server-side. O guideline humano completo é `../../arquitetura_frontend.md`; esta skill operacionaliza o dia a dia e aponta para ele.

## Onde o frontend se encaixa (leia primeiro)

A arquitetura é de duas camadas (`../../arquitetura_plataforma.md`): **domínio** (serviços Go + gRPC, donos de dado e regra) e **experiência** (as aplicações). Esta skill é sobre a camada de experiência. Três fatos moldam tudo o que segue:

1. **A aplicação não tem banco de dados de domínio.** Não há SQL aqui. Se você sentiu falta de um banco, o que você quer é uma operação no domínio dono daquele dado, exposta por gRPC.
2. **A aplicação não contém regra de negócio.** Validação de *formato* (CPF tem 11 dígitos) é frontend; regra de *negócio* (esse CPF pode contratar) é domínio. Cálculo de preço, elegibilidade, máquina de estado → domínio, sempre.
3. **A camada de dados fala gRPC com o domínio, server-side.** No web, o próprio servidor Next.js é a camada de experiência; ele fala gRPC (ConnectRPC) com os domínios. O browser nunca fala gRPC direto.

## Regras inegociáveis

### Stack obrigatória

| Componente | Tecnologia | Observação |
|---|---|---|
| Framework | **Next.js (App Router)** | Sem projetos novos em Pages Router. |
| Linguagem | **TypeScript** em modo estrito | Sem `any` escondido; use `unknown` quando desconhece. |
| Estilização | **Tailwind CSS** | Base de design via shadcn/ui / Radix / Headless UI — não construir design system do zero. |
| Camada de dados | **ConnectRPC** (`@connectrpc/connect` + `@connectrpc/connect-node`), server-side | Tipos gerados dos `.proto` via `buf`, em `gen/`. Sem REST, sem `fetch` a gateway, sem banco. |
| Mutação | **Server Actions** | Client Component invoca a action; a action fala gRPC no servidor. |
| Fetch client-side (borda) | **route handler** do Next.js que repassa para o gRPC | Só quando inevitável (scroll infinito, busca incremental). O browser fala com o route handler, não com o domínio. |

### Idioma e documentação

Mesma convenção do backend (`../../convencao_de_idioma.md`): **vocabulário do domínio em português, vocabulário técnico em inglês.**

- Domínio (PT): tipos e campos de negócio (`Assinante`, `Fatura`, `situacaoCadastral`, `valorParcela`), componentes de feature (`CardAssinante`), funções de regra de formato (`formatarCPF`).
- Técnico (EN): termos de React/Next (`props`, `state`, `layout`, `route`, `params`, `searchParams`, `component`), nomes de infraestrutura.
- Os tipos de domínio vêm do `.proto` gerado — **não** redefina `Assinante` à mão no front. Se o contrato está em PT, o tipo no front nasce em PT.

### Dependências externas

- Padrão é **não** adicionar dependência. JavaScript moderno faz muita coisa (não importe lib de 500 linhas para um debounce).
- Mesma hierarquia de confiança do backend; tier 4 é "não" por padrão. Justifique no PR quando for "sim".

## Filosofia central

1. **Server Component é o padrão.** `"use client"` só quando há interatividade (estado, eventos, hooks de browser). Empurre `"use client"` o mais para baixo possível na árvore.
2. **Buscar dado no nível mais alto, passar para baixo via props.** Server Component busca (via gRPC server-side); Client Component recebe e interage. Sem `useEffect + fetch` quando o pai pode buscar no servidor.
3. **`"use client"` é fronteira, não decoração.** O que vira Client vai para o bundle do browser. Minimize a árvore Client. (Children passados a um Client Component podem continuar Server Components — domine essa sutileza.)
4. **Componente tem uma responsabilidade.** Se precisa de mais de duas frases para explicar o que ele faz, está fazendo demais. Alarme de tamanho: ~150 linhas.
5. **Estado mora onde é usado, sobe quando compartilhado.** Comece em `useState`. Suba para o pai (lifted state). Depois `searchParams` (URL), depois Context, e só então biblioteca externa (Zustand). Pergunta que destranca: *quem precisa deste estado?*
6. **Segredo nunca chega ao browser.** Cliente gRPC, tokens de serviço e URLs internas são server-side. Marcar um arquivo de `lib/api/` como acessível ao client é vazamento.

## Camada de dados (o coração desta skill)

Detalhes, código e armadilhas em `references/data-layer.md`. Resumo operacional:

- Clientes gRPC tipados ficam em `lib/api/`, **um por domínio**, instanciados com transport server-side, e importados **só** por Server Components e Server Actions.
- **Leitura:** Server Component chama a função de `lib/api/` no render. Sem `useEffect`.
- **Mutação:** Server Action chama o cliente gRPC e revalida (`revalidatePath` / `revalidateTag`). O Client Component invoca a action.
- **Cache:** o cache automático de `fetch` do Next **não** cobre gRPC. Envolva leituras em `unstable_cache` (ou `cache()` do React para dedup por request) e invalide nas actions.
- **Erro gRPC** chega tipado (ex.: `Code.NotFound`); traduza para o que a tela precisa, na fronteira de `lib/api/`, não espalhado pelos componentes.

## Web versus mobile

- **Web (Next.js fullstack):** o servidor Next.js é a camada de experiência e o "BFF". Não construa um serviço BFF separado para o web — seria rede a mais sem benefício.
- **Mobile (app nativo + BFF dedicado):** o app fala com um **BFF fino, um por app, em Go**, que traduz o gRPC publicado para o app. Esse BFF é camada de experiência (não domínio, sem banco, sem regra) e é construído com a skill `golang-development` (arquétipo "BFF mobile"). Esta skill cobre o app/UX; a construção do BFF Go é lá.

A regra comum: orquestração de fluxo cross-domínio mora na experiência (servidor Next.js ou BFF mobile), nunca em um domínio chamando outro em cadeia.

## Estrutura de diretórios

```
app/                  # App Router: páginas, layouts, route handlers (só roteamento)
  (dashboard)/
    clientes/
      page.tsx        # Server Component (lê via gRPC server-side)
      acoes.ts        # "use server" — Server Actions de mutação
components/
  ui/                 # genéricos, sem domínio (Button, Input) — via shadcn/Radix
  features/           # com domínio (CardAssinante, FormAssinante)
lib/
  api/                # clientes gRPC tipados (ConnectRPC), usados server-side
  utils/              # helpers com nome descritivo (formatarCPF.ts) — nunca "helpers.ts"
  types/              # tipos TS compartilhados (os de domínio vêm de gen/)
hooks/                # custom hooks (código React)
gen/                  # tipos/clientes gerados dos .proto (buf) — não editar
```

## Workflow para qualquer tarefa de frontend

### 1. Identificar o tipo de tarefa e carregar a referência certa

| Tarefa | Ler |
|---|---|
| Buscar/mutar dado, ConnectRPC, Server Actions, route handlers, cache | `references/data-layer.md` |
| Review de código existente | `references/code-review-checklist.md` |
| **Padrão completo** (Server vs Client, ilha de interatividade, estado, performance, libs) | `../../arquitetura_frontend.md` |
| **Onde o frontend se encaixa** (duas camadas, web vs mobile) | `../../arquitetura_plataforma.md` |
| **Idioma**: o que vai em PT, o que vai em EN | `../../convencao_de_idioma.md` |

Ler **apenas** o que é relevante. Para a maioria das tarefas de tela, `references/data-layer.md` + `../../arquitetura_frontend.md` bastam.

### 2. Checklist pré-voo (sempre)

- [ ] A página é Server Component? (só vira Client se tem interatividade real)
- [ ] `"use client"` está o mais baixo possível na árvore?
- [ ] Dado buscado no servidor (gRPC via `lib/api/`), não em `useEffect + fetch`?
- [ ] Nenhuma regra de negócio no front (só formato); cálculo/elegibilidade está no domínio?
- [ ] Cliente gRPC e segredos ficam server-side (não importados por Client Component)?
- [ ] Tipos de domínio vêm de `gen/` (não redefinidos à mão)?
- [ ] Mutação via Server Action com revalidação? Sem regra de negócio na action?
- [ ] Vocabulário de domínio em PT, técnico (React/Next) em EN?
- [ ] `useEffect` só para efeito real (não para derivar valor nem sincronizar prop)?
- [ ] Dependency array de `useEffect` completa (sem stale closure)?
- [ ] Componente < ~150 linhas e com responsabilidade única?
- [ ] Nenhuma dependência nova sem justificativa?
- [ ] **Nunca** `localStorage`/`sessionStorage` se o alvo for artifact; em app real, com parcimônia.

### 3. Escrever o código

Siga os padrões de `../../arquitetura_frontend.md` (ilha de interatividade, composição sobre configuração, props mínimas). Para qualquer coisa que toque dado, `references/data-layer.md` tem o código.

### 4. Mostrar comandos de verificação

Terminar respostas que produzem código com:

```bash
pnpm gen        # buf generate (tipos/clientes gRPC em gen/) quando o .proto mudou
pnpm lint       # eslint + typecheck
pnpm build      # next build (pega erros de Server/Client boundary e de tipo)
pnpm test       # quando houver testes
```

## Armadilhas comuns para procurar ativamente

- **Client Component tentando falar gRPC direto.** Não existe — gRPC é server-side. Vá por Server Action ou route handler.
- **Importar `lib/api/` em arquivo `"use client"`.** Vaza segredo e quebra o build. Cliente gRPC é server-only.
- **Redefinir tipos de domínio à mão** em vez de usar os de `gen/`. Diverge silenciosamente do contrato.
- **`useEffect` para sincronizar estado com prop** — quase sempre é derivação no render, não efeito.
- **`useEffect + fetch`** quando um Server Component poderia ter buscado no servidor.
- **Regra de negócio no front** (cálculo de preço, elegibilidade) — sempre vai dessincronizar do domínio.
- **Esperar que o cache de `fetch` do Next cacheie gRPC** — não cacheia. Use `unstable_cache`.
- **`"use client"` no topo da página** "para facilitar" — joga a página inteira no bundle.
- **`<img>` em vez de `next/image`**, listas grandes sem virtualização (mas meça antes — 50 itens não precisam).

## Formato de output esperado

- Código em blocos ```tsx / ```ts com o filename como comentário na linha 1: `// app/(dashboard)/clientes/page.tsx`.
- Sempre deixar claro se o arquivo é Server ou Client Component (presença/ausência de `"use client"`).
- Imports agrupados: libs externas, depois `@/` locais.
- Comentários e identificadores de domínio em português; termos de React/Next em inglês.
- Não elidir código com `// ...` salvo se o usuário pediu snippet.

## Índice de referências

```
guidelines/                                    (raiz do repositório)
├── arquitetura_plataforma.md                  macro: duas camadas, web vs mobile, BFF
├── arquitetura_frontend.md                    padrão completo de frontend (humano)
├── convencao_de_idioma.md                     domínio em PT, técnico em EN
└── skills/frontend-nextjs/
    ├── SKILL.md                               (este arquivo)
    └── references/
        ├── data-layer.md                      ConnectRPC server-side, Server Actions, route handlers, cache, erros
        └── code-review-checklist.md           revisão sistemática de PR React/TS
```
