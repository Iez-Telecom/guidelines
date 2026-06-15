# Checklist de review — Next.js / React / TypeScript

Use ao revisar PRs de frontend. Agrupe achados por severidade: **Bug** (vaza segredo, quebra build, stale closure, regra no lugar errado) → **Arquitetura** (camada errada, Client onde devia ser Server) → **Idioma/Estilo** (naming, formatação). Mostre o código corrigido, não só a descrição.

## Camada e fronteira (o que mais importa aqui)

- [ ] **Sem regra de negócio no front.** Cálculo de preço, elegibilidade, desconto, máquina de estado → domínio. No front só validação de *formato*.
- [ ] **Cliente gRPC / segredo não vaza para o client.** Nada de `lib/api/` (ou `process.env` de serviço) importado em arquivo `"use client"`. Idealmente os módulos de `lib/api/` têm `import "server-only"`.
- [ ] **Browser não fala gRPC direto.** Toda ida ao domínio passa por Server Component, Server Action ou route handler.
- [ ] **Tipos de domínio vêm de `gen/`** (gerados do `.proto`), não redefinidos à mão.
- [ ] **Nenhum acesso a banco** no frontend (não existe; se aparecer, é erro de camada).

## Server vs Client Components

- [ ] Componente é Server Component por padrão; `"use client"` só com interatividade real (estado, evento, hook de browser).
- [ ] `"use client"` está o mais baixo possível na árvore (não na página inteira).
- [ ] Página (`page.tsx`) é Server Component, salvo razão concreta registrada.
- [ ] Server Component não usa `useState`/`useEffect`/hooks de client (não compila, mas a IA às vezes propõe).
- [ ] Children Server Components passados a um Client Component não foram desnecessariamente "client-ificados".

## Dados e estado

- [ ] Leitura via Server Component (gRPC server-side), não `useEffect + fetch`.
- [ ] Mutação via Server Action com `revalidatePath`/`revalidateTag`; a action não carrega regra de negócio.
- [ ] Cache de leitura via `unstable_cache`/`cache()` quando aplicável (cache de `fetch` do Next não cobre gRPC).
- [ ] `useEffect` é efeito real — não derivação de valor (que vai no render) nem sincronização de prop.
- [ ] Dependency array de `useEffect` completa (sem stale closure).
- [ ] Estado no nível certo: `useState` → lifted → `searchParams` → Context → lib externa. Sem Zustand/Redux para o que `useState` resolve.
- [ ] Dado de servidor não foi parar em Redux/store global (é cache de estado do servidor).

## TypeScript

- [ ] Sem `any` (use `unknown` quando desconhece). Modo estrito respeitado.
- [ ] Tipos de retorno de funções de `lib/api/` explícitos onde ajuda a leitura.
- [ ] Erros tratados de forma tipada (`ConnectError`/`Code`), não `catch (e: any)` engolido.

## Componentes

- [ ] Responsabilidade única; alarme em ~150 linhas.
- [ ] Props mínimas (não passar objeto inteiro se usa 3 campos).
- [ ] Composição sobre configuração (não um componente com 20 props booleanas).
- [ ] `components/ui/` (genérico, sem domínio) vs `components/features/` (com domínio) respeitado.
- [ ] Form com `onSubmit` chama `e.preventDefault()`; estado de loading/erro tratado.

## Performance

- [ ] `next/image` em vez de `<img>`.
- [ ] `useMemo`/`useCallback` só onde o profiling mostrou problema (não preventivo).
- [ ] Listas realmente grandes virtualizadas (mas 50 itens não precisam — meça antes).
- [ ] Bundle do client minimizado (interatividade empurrada para baixo).

## Idioma e naming

- [ ] Domínio em português (`Assinante`, `valorParcela`, `CardAssinante`); técnico de React/Next em inglês (`props`, `params`, `layout`).
- [ ] Sem `helpers.ts`/`utils.ts` genérico — arquivos com nome descritivo (`formatarCPF.ts`).
- [ ] Componentes de feature nomeados pelo conceito de domínio.

## Dependências

- [ ] Nenhuma dependência nova sem justificativa (tier 4 é "não" por padrão).
- [ ] Não usar lib pesada para o que JS moderno resolve em poucas linhas.

## Verificação

- [ ] `pnpm lint` (eslint + typecheck) limpo.
- [ ] `pnpm build` passa (pega erros de fronteira Server/Client e de tipo).
- [ ] Testes verdes quando existem.
