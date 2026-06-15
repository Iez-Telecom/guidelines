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

### [Arquitetura de Plataforma](./arquitetura_plataforma.md)

O documento macro, acima dos de backend e frontend. Descreve a forma geral do sistema — onde ficam as fronteiras e quem é dono do quê. Cobre:

- O padrão de **duas camadas**: domínio (Go + gRPC, por capacidade de negócio) e experiência (BFF/Next.js); por que a consistência vem do domínio compartilhado
- O vocabulário travado: **domínio (bounded context) não é o mesmo que aplicação/área**
- Decomposição por capacidade de negócio, Lei de Conway e DDD — com a ressalva de que **a unidade é o bounded context; deployable separado é decisão posterior**
- As costuras entre domínios: heurísticas de fronteira, onde mora a orquestração cross-domínio, e o risco de **distributed monolith**
- Posição **provisória** sobre autenticação e autorização (negócio no domínio; sessão/RBAC na experiência)
- O caminho incremental (*strangler fig*) a partir do `crm_gateway` atual
- Quando NÃO seguir o padrão e quando um monólito modular basta

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
- Camada de dados via **gRPC server-side** (ConnectRPC) com os domínios — não REST, não banco direto
- Web (Next.js fullstack) versus mobile (BFF Go fino, um por app)
- Performance: bundle size, re-renders, cache do Next.js
- Bibliotecas: o que usamos, o que avaliamos, o que evitamos

### [Convenção de Idioma](./convencao_de_idioma.md)

Guia prático de como aplicamos a regra de idioma no código do dia a dia. Cobre:

- A regra: vocabulário do domínio em português, vocabulário técnico em inglês
- Exemplos em Go, TypeScript, Protobuf e SQL
- Vocabulário do nosso domínio (telecomunicações móveis)
- Casos limítrofes e como decidir quando tiver dúvida
- Erros comuns a evitar

### [Banco de Dados — Guia para Desenvolvedores](./guideline_database.md)

Como o desenvolvedor interage com o banco durante o desenvolvimento. Não é guia DBA — é sobre trabalhar bem localmente e propor schemas maduros. Cobre:

- Stack: `pgx/v5`, `sqlc`, `golang-migrate`, Postgres 16 em container local
- Banco local com `tmpfs`: reset em segundos, sem medo de destruir
- Migrations forward-only: timestamp-based, sem `.down.sql`, imutáveis após commit
- **Convenção de nomenclatura do schema**: tabelas, colunas, constraints, índices, enums — tudo em português de domínio
- Ciclo de trabalho local: `make db-new` → editar → `make db-reset` → validar → commitar
- Queries com sqlc: um arquivo por feature, anotações `:one` / `:many` / `:exec`
- Diferença entre local (tmpfs, só você) e homologação (persistido, time inteiro)
- Como entregar a proposta de migration para o time de DBA

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
