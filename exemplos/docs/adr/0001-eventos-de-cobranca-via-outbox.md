# 0001. Publicação de eventos de cobrança via padrão Outbox

- **Data:** 2026-05-12
- **Status:** Aceito
- **Decisores:** squad Cobrança
- **Tags:** persistência | eventos | consistência

## Contexto

O serviço `cobranca-svc` precisa publicar eventos em NATS quando faturas mudam de situação (`fatura.emitida`, `fatura.paga`, `fatura.vencida`, `fatura.cancelada`). Esses eventos alimentam o `notificacao-svc`, o `dw-svc` (data warehouse) e o `auditoria-svc`.

A primeira implementação publicava direto no NATS dentro do handler, depois do `tx.Commit()`. Em testes de carga, vimos duas falhas:

1. Quando o NATS estava indisponível mas o banco respondendo, a transação commitava e o evento se perdia silenciosamente — sem rastro. Em três incidentes, o `notificacao-svc` deixou de mandar boleto para clientes porque o evento `fatura.emitida` nunca chegou.
2. Quando o processo morria entre `tx.Commit()` e o `nats.Publish()`, mesmo problema.

Não temos transação distribuída entre Postgres e NATS, e nem queremos (2PC entre tecnologias diferentes não é uma rota razoável aqui).

## Decisão

Adotar o **padrão Outbox**:

1. Toda mudança de situação de fatura escreve a linha do evento numa tabela `eventos_outbox` **dentro da mesma transação** do `UPDATE faturas`.
2. Um worker em background lê `eventos_outbox` em batches, publica no NATS, e marca como `publicado` (também transacionalmente).
3. Worker faz retry com backoff exponencial; eventos com falha permanente após N tentativas vão para `eventos_outbox_dlq`.

Alternativas consideradas:

- **Opção A (escolhida): Outbox.** Garantia at-least-once, atômica com a mudança de estado, observável (a tabela é inspecionável).
- **Opção B: 2PC entre Postgres e NATS.** Rejeitada — NATS JetStream tem suporte experimental, complexo de operar, e a maioria das ferramentas de DBA não suporta XA.
- **Opção C: CDC (Debezium lendo o WAL do Postgres).** Rejeitada para este serviço — operacionalmente pesado (Kafka Connect, schema registry), e a vazão de eventos cabe bem em uma tabela polled.

## Consequências

**Positivas:**
- Zero perda de evento por falha de NATS ou crash do processo.
- Tabela `eventos_outbox` serve como auditoria natural — fácil reproduzir o que foi publicado.
- Worker é simples de testar (lê tabela, publica, marca; nada de transação distribuída).

**Negativas / trade-offs aceitos:**
- Latência mínima entre commit e publicação ~100ms (intervalo do worker). Para `notificacao-svc`, isso é aceitável; para algo com SLA de ms, não seria.
- Custo extra de escrita: cada mudança de fatura agora gera 1 row extra na `eventos_outbox`. Volume estimado <1GB/mês, irrelevante.
- Eventos podem ser publicados **mais de uma vez** se o worker crashar entre `nats.Publish()` e `UPDATE eventos_outbox SET publicado=true`. Consumidores devem ser idempotentes (já são).

**Coisas que precisam acontecer:**
- Migration `000023_criar_eventos_outbox.up.sql` (pronta, PR #421).
- Worker em `internal/cobranca/outbox/`. Health check expõe `outbox_pending_count` para alertar quando a fila atrasa.
- `notificacao-svc` e `dw-svc` já são idempotentes por design; `auditoria-svc` precisa confirmar (issue #189).
- Dashboard Grafana: lag do outbox + taxa de DLQ.

## Referências

- "Pattern: Transactional Outbox" — Chris Richardson, microservices.io
- PR #421 — implementação inicial
- Incidente INC-2026-04-03 — perda de evento `fatura.emitida` que motivou a decisão
