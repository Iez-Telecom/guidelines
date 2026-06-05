#!/usr/bin/env bash
# scripts/db.sh — gerenciamento do banco de dados de desenvolvimento.
#
# Chamado pelos alvos make db-* do Makefile. Não executar diretamente em produção.
#
# Dependências:
#   - podman-compose (ou docker-compose — troque abaixo se necessário)
#   - migrate CLI: https://github.com/golang-migrate/migrate
#   - psql / pg_dump (cliente postgresql)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

# Carrega overrides locais se o arquivo existir. Nunca commitar .env.local.
if [[ -f .env.local ]]; then
  # shellcheck source=/dev/null
  set -a; source .env.local; set +a
fi

POSTGRES_USER="${POSTGRES_USER:-dev}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-dev}"
POSTGRES_DB="${POSTGRES_DB:-meuservico_dev}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"
MIGRATIONS_DIR="sql/migrations"
COMPOSE_FILE="compose.yml"

# ---------------------------------------------------------------------------
# Funções
# ---------------------------------------------------------------------------

db_up() {
  echo ">> Subindo Postgres..."
  podman-compose -f "$COMPOSE_FILE" up -d --wait
  echo ">> Postgres pronto em localhost:${POSTGRES_PORT}/${POSTGRES_DB}"
}

db_down() {
  echo ">> Parando Postgres..."
  podman-compose -f "$COMPOSE_FILE" down
}

db_reset() {
  echo ">> Resetando banco (destroy + recreate + migrate)..."
  # --volumes remove o volume nomeado se houver; no tmpfs não faz diferença,
  # mas garante limpeza caso alguém troque para volume persistente localmente.
  podman-compose -f "$COMPOSE_FILE" down --volumes 2>/dev/null || true
  podman-compose -f "$COMPOSE_FILE" up -d --wait
  db_migrate
  echo ">> Reset concluído."
}

db_migrate() {
  echo ">> Aplicando migrations em ${DB_URL}..."
  migrate -path "${MIGRATIONS_DIR}" -database "${DB_URL}" up
  echo ">> Migrations aplicadas."
}

db_new() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "Erro: informe o nome da migration."
    echo "Uso: make db-new NAME=criar_tabela_assinantes"
    exit 1
  fi
  local timestamp
  timestamp="$(date -u +%Y%m%d%H%M%S)"
  local filename="${MIGRATIONS_DIR}/${timestamp}_${name}.up.sql"
  mkdir -p "${MIGRATIONS_DIR}"
  cat > "$filename" <<'SQL'
-- Migration: descreva aqui o que esta migration faz
-- Contexto: link para issue/ticket, ADR, ou decisão de negócio relevante

SQL
  echo ">> Criado: ${filename}"
}

db_status() {
  echo ">> Versão atual das migrations:"
  migrate -path "${MIGRATIONS_DIR}" -database "${DB_URL}" version 2>&1 || echo "(banco sem migrations aplicadas)"
}

db_shell() {
  echo ">> Abrindo psql em ${POSTGRES_DB}..."
  PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h localhost -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}"
}

db_seed() {
  local seed_file="sql/seed.sql"
  if [[ ! -f "$seed_file" ]]; then
    echo "Arquivo ${seed_file} não encontrado."
    echo "Crie ${seed_file} com dados de desenvolvimento (não commitar dados sensíveis)."
    exit 1
  fi
  echo ">> Aplicando seed a partir de ${seed_file}..."
  PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h localhost -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -f "$seed_file"
  echo ">> Seed aplicado."
}

db_dump_schema() {
  local output="${1:-sql/schema_dump.sql}"
  echo ">> Exportando schema para ${output}..."
  PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h localhost -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --schema-only \
    --no-owner \
    --no-acl \
    -f "$output"
  echo ">> Schema exportado: ${output}"
}

db_help() {
  cat <<'EOF'
Uso: ./scripts/db.sh <subcomando> [args]

Subcomandos:
  up             Sobe o Postgres local via podman-compose
  down           Para o Postgres
  reset          Destrói e recria o banco, reaplica todas as migrations
  migrate        Aplica migrations pendentes (sem destruir o banco)
  new <nome>     Cria arquivo de migration com timestamp (ex: new criar_tabela_assinantes)
  status         Mostra a versão atual das migrations
  shell          Abre psql no banco local
  seed           Aplica sql/seed.sql (dados de desenvolvimento)
  dump-schema    Exporta schema atual (sem dados) para sql/schema_dump.sql
  help           Exibe esta ajuda

Variáveis de ambiente (override via .env.local na raiz do serviço):
  POSTGRES_USER      (default: dev)
  POSTGRES_PASSWORD  (default: dev)
  POSTGRES_DB        (default: meuservico_dev)
  POSTGRES_PORT      (default: 5432)
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

SUBCOMMAND="${1:-help}"
shift 2>/dev/null || true

case "$SUBCOMMAND" in
  up)           db_up ;;
  down)         db_down ;;
  reset)        db_reset ;;
  migrate)      db_migrate ;;
  new)          db_new "${1:-}" ;;
  status)       db_status ;;
  shell)        db_shell ;;
  seed)         db_seed ;;
  dump-schema)  db_dump_schema ;;
  help|*)       db_help ;;
esac
