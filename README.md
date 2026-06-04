# Diretrizes de Desenvolvimento

Este repositório contém as diretrizes técnicas que guiam como construímos software. Não são regras para seguir cegamente — são decisões fundamentadas para não precisar rediscutir a cada projeto novo.

## Como usar este repositório

Leia os documentos antes de iniciar um projeto novo ou quando tiver dúvidas sobre onde determinado código deve morar, como nomear algo, ou como estruturar uma integração. Se uma diretriz não parecer defensável para o seu caso concreto, questione — mas registre o motivo da divergência no README do serviço.

## Documentos

### [Diretrizes de colaboração com IA](./guidelines_ia.md)

Como o time trabalha com IA generativa em código — descritivo, não prescritivo. Cobre:

- O padrão recomendado: **humano dirige contrato (proto, schema, ADR), IA dirige implementação (handler, store, componente)**
- A técnica das sessões separadas para isolar contexto de contrato e contexto de implementação
- Onde IA é genuinamente boa (tradução constrita, boilerplate, refactor mecânico) e genuinamente ruim (modelagem de domínio, schema com awareness de carga, decisões regulatórias)
- Como entregar contexto (AGENTS.md, ADRs, spec antes de implementação)
- Como validar saída (failure modes específicos por stack, desconfiar de "parece certo")
- Workflow por tipo de tarefa (feature nova, bug fix, refactor, spike, onboarding, debug)
- Anti-padrões e postura cética saudável

### [Arquitetura de Serviços Backend](./arquitetura_backend.md)

Padrão para serviços em Go + PostgreSQL + gRPC. Cobre:

- Estrutura de diretórios (`cmd/`, `internal/`, `external/`, `gen/`, `sql/`)
- Organização por feature dentro de `internal/`
- Configuração do `sqlc` e geração de código
- Gestão de dependências de terceiros com hierarquia de confiança
- Anti-Corruption Layer para integrações com sistemas externos
- Comunicação entre serviços via gRPC síncrono e cache orientado a eventos
- Quando simplificar ou adicionar mais estrutura que o padrão

### [Arquitetura Frontend](./arquitetura_frontend.md)

Padrão para aplicações em TypeScript + Next.js (App Router). Cobre:

- Estrutura de diretórios (`app/`, `components/`, `lib/`, `hooks/`)
- Server Components versus Client Components — quando usar cada um
- Padrão "ilha de interatividade" para performance
- Escada de gerenciamento de estado (do `useState` ao Zustand)
- Centralização de chamadas de API em `lib/api/`
- Performance: bundle size, re-renders, cache do Next.js
- Bibliotecas: o que usamos, o que avaliamos, o que evitamos

### [Convenção de Idioma](./convencao_de_idioma.md)

Guia prático de como aplicamos a regra de idioma no código do dia a dia. Cobre:

- A regra: vocabulário do domínio em português, vocabulário técnico em inglês
- Exemplos em Go, TypeScript, Protobuf e SQL
- Vocabulário do nosso domínio (telecomunicações móveis)
- Casos limítrofes e como decidir quando tiver dúvida
- Erros comuns a evitar

### [Guidelines Práticos — Go](./guidelines_golang.md)

Receitas operacionais para o dia a dia em Go. Complementa o documento de arquitetura backend com o "como fazer" das ferramentas. Cobre:

- Setup de máquina: `GOPRIVATE`, `insteadOf` SSH, configuração de módulos privados
- Submodules com sparse-checkout para protos compartilhados
- Makefile padrão com geração de código, build, lint e deploy
- Embutindo versão/commit/data no binário via `-ldflags`
- Containerfile multi-stage com dois runtimes: **distroless** (produção) e **alpine** (debug emergencial), tag `-alpine` para identificação
- Configuração de `buf.yaml` / `buf.gen.yaml` com plugins locais e `googleapis`
- Comandos do dia a dia, profiling, tooling (`golangci-lint`) e tabela de troubleshooting
- Arquivos prontos para copiar em [`exemplos/`](./exemplos): `Makefile`, `Containerfile`, `buf.yaml`, `buf.gen.yaml`, `.golangci.yml`, `AGENTS.md`, e template/exemplo de ADR em [`exemplos/docs/adr/`](./exemplos/docs/adr/)

## Postura geral

Não adotamos padrões por reconhecimento de nome. Cada decisão registrada aqui tem uma justificativa. Se você ler uma seção e a justificativa não fizer sentido para o seu caso, questione — e se divergir, documente o porquê.

Tudo tem custo: cada camada de abstração, cada biblioteca, cada padrão arquitetural. A pergunta a se fazer sempre é: o que isto custa, e o que ganho em troca?

O objetivo é consistência, não perfeição. Um padrão aplicado uniformemente é mais valioso do que uma escolha ótima debatida indefinidamente.

## Evoluindo estas diretrizes

Propostas de mudança devem citar experiências concretas — bugs enfrentados, problemas de manutenção, gargalos de performance observados. Não mudamos com base em artigos novos ou tendências. Mudamos com base no que aprendemos com código real em produção.
