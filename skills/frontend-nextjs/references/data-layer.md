# Camada de dados — ConnectRPC server-side

A regra estruturante: **a aplicação não bate em banco; ela fala gRPC com os serviços de domínio, sempre server-side.** O browser nunca fala gRPC com o domínio — sempre há um servidor da camada de experiência (o próprio Next.js) no meio.

Esta referência tem o código concreto. O racional está em `../../../arquitetura_frontend.md` e `../../../arquitetura_plataforma.md`.

## 1. O cliente gRPC (em `lib/api/`)

Um arquivo por domínio. O transport é server-side e aponta para o endereço **interno** do serviço de domínio. Os tipos vêm de `gen/`, gerados dos `.proto` via `buf`.

```ts
// lib/api/clientes.ts
import "server-only"; // garante erro de build se importado por Client Component

import { createClient } from "@connectrpc/connect";
import { createGrpcTransport } from "@connectrpc/connect-node";
import { ServicoClientes } from "@/gen/clientes/v1/clientes_pb";

const transport = createGrpcTransport({
  baseUrl: process.env.CLIENTES_GRPC_URL!, // endereço interno; nunca exposto ao browser
});

const cliente = createClient(ServicoClientes, transport);

export async function listarClientes() {
  const { clientes } = await cliente.listarClientes({});
  return clientes; // tipo vem do .proto — sem modelagem paralela
}

export async function buscarCliente(id: string) {
  return cliente.buscarCliente({ id });
}

export async function suspenderLinha(input: { linhaId: string }) {
  return cliente.suspenderLinha(input);
}
```

Pontos críticos:

- **`import "server-only"`** no topo: se alguém importar este módulo de um arquivo `"use client"`, o build quebra. É a sua rede de segurança contra vazar segredo e o transport para o browser.
- **`baseUrl` é interno.** Endereço de serviço dentro da rede, token de serviço, etc. — nada disso chega ao browser.
- **Sem modelagem paralela.** Use o tipo gerado (`Cliente` de `gen/`). Se a tela precisa de outro formato, faça o mapeamento explícito aqui na fronteira, não espalhado pelos componentes.

## 2. Leitura — Server Components

Server Component chama a função de `lib/api/` direto no render do servidor. Sem `useEffect`, sem fetch no client.

```tsx
// app/(dashboard)/clientes/page.tsx
// Server Component (sem "use client")

import { listarClientes } from "@/lib/api/clientes";
import { TabelaClientes } from "@/components/features/clientes/TabelaClientes";

export default async function PaginaClientes() {
  const clientes = await listarClientes(); // gRPC server-side
  return (
    <div>
      <h1>Clientes</h1>
      <TabelaClientes clientes={clientes} />
    </div>
  );
}
```

## 3. Mutação — Server Actions

A action roda no servidor, chama o cliente gRPC e revalida. O Client Component apenas invoca a action — nunca fala com o domínio.

```ts
// app/(dashboard)/clientes/acoes.ts
"use server";

import { suspenderLinha } from "@/lib/api/clientes";
import { revalidatePath } from "next/cache";

export async function acaoSuspenderLinha(linhaId: string) {
  await suspenderLinha({ linhaId }); // regra de negócio é do domínio, não daqui
  revalidatePath("/clientes");
}
```

```tsx
// components/features/clientes/BotaoSuspenderLinha.tsx
"use client";

import { acaoSuspenderLinha } from "@/app/(dashboard)/clientes/acoes";
import { useTransition } from "react";

export function BotaoSuspenderLinha({ linhaId }: { linhaId: string }) {
  const [pending, startTransition] = useTransition();
  return (
    <button
      disabled={pending}
      onClick={() => startTransition(() => acaoSuspenderLinha(linhaId))}
    >
      {pending ? "Suspendendo…" : "Suspender linha"}
    </button>
  );
}
```

A action **não** contém regra de negócio. "Pode suspender esta linha?" é decisão do domínio; a action só chama o RPC e trata o resultado.

## 4. Caso de borda — fetch client-side via route handler

Quando uma interação precisa buscar dado sem recarregar a página (scroll infinito, busca incremental), exponha um **route handler** que, no servidor, chama o mesmo cliente de `lib/api/`. O browser fala com o seu route handler; o route handler fala gRPC. O browser continua sem tocar o domínio.

```ts
// app/api/clientes/route.ts
import { listarClientes } from "@/lib/api/clientes";
import { NextResponse } from "next/server";

export async function GET() {
  const clientes = await listarClientes();
  return NextResponse.json(clientes);
}
```

No client, aí sim pode usar TanStack Query batendo no **seu** route handler (não no domínio). É exceção — o padrão é Server Component + Server Action.

## 5. Cache

O cache automático de `fetch` do Next **não** cobre chamadas gRPC (elas não passam por `fetch`). Para cachear leitura de domínio:

```ts
// lib/api/planos.ts
import "server-only";
import { unstable_cache } from "next/cache";
import { createClient } from "@connectrpc/connect";
// ... transport + client ...

// Catálogo de planos muda pouco: cache longo com tag para invalidar sob demanda.
export const listarPlanos = unstable_cache(
  async () => (await cliente.listarPlanos({})).planos,
  ["planos"],
  { revalidate: 3600, tags: ["planos"] },
);
```

- `unstable_cache` para cache entre requests; `cache()` do React para deduplicar a mesma chamada dentro de um render.
- Invalide com `revalidateTag("planos")` / `revalidatePath(...)` nas Server Actions que mudam o dado.
- Não desabilite cache "para garantir dado fresco" sem entender o custo — você paga latência e carga no domínio.

## 6. Tradução de erro

O erro gRPC chega tipado. Traduza na fronteira (`lib/api/`) para o que a tela entende — não deixe `ConnectError` vazar pelos componentes.

```ts
// lib/api/clientes.ts (trecho)
import { ConnectError, Code } from "@connectrpc/connect";

export async function buscarCliente(id: string) {
  try {
    return await cliente.buscarCliente({ id });
  } catch (err) {
    if (err instanceof ConnectError && err.code === Code.NotFound) {
      return null; // a tela decide como mostrar "não encontrado"
    }
    throw err; // erro inesperado sobe
  }
}
```

## Checklist da camada de dados

- [ ] Cliente gRPC em `lib/api/`, um por domínio, com `import "server-only"`.
- [ ] `baseUrl` lido de env server-side; nenhum segredo no bundle do browser.
- [ ] Leitura em Server Component; mutação em Server Action; fetch client-side só via route handler.
- [ ] Tipos vêm de `gen/`; sem redefinição manual.
- [ ] Cache via `unstable_cache`/`cache()` quando faz sentido; invalidação nas actions.
- [ ] Erro gRPC traduzido na fronteira; sem regra de negócio no front.
