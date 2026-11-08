#!/usr/bin/env bash

# JurisDocs — etapa 1: infraestrutura local (MongoDB + Redis).
# Este script nao cria colecoes, usuarios da aplicacao, indices ou dados de exemplo.
# Essas configuracoes serao feitas em uma etapa posterior.

set -Eeuo pipefail

PROJECT_NAME="jurisdocs"
MONGODB_CONTAINER="jurisdocs-mongodb"
REDIS_CONTAINER="jurisdocs-redis"
MONGODB_PORT="27018"
REDIS_PORT="6380"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Comando obrigatorio nao encontrado: $1"
}

assert_port_free() {
  local port="$1"
  if ss -ltn "( sport = :${port} )" 2>/dev/null | grep -q "LISTEN"; then
    fail "A porta ${port} ja esta em uso. Resolva o conflito antes de executar o script."
  fi
}

wait_for_healthy() {
  local container="$1"
  local attempts=30
  local status

  for ((i = 1; i <= attempts; i++)); do
    status="$(podman inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "$container" 2>/dev/null || true)"

    if [[ "$status" == "healthy" ]]; then
      success "${container} esta saudavel."
      return 0
    fi

    if [[ "$status" == "unhealthy" ]]; then
      podman logs --tail 40 "$container" >&2 || true
      fail "${container} ficou unhealthy."
    fi

    printf 'Aguardando %s (%s/30): %s\n' "$container" "$i" "${status:-indisponivel}"
    sleep 2
  done

  podman logs --tail 40 "$container" >&2 || true
  fail "Tempo esgotado aguardando ${container}."
}

cd "$PROJECT_DIR"

info "Verificando requisitos locais"
require_command podman
require_command ss
podman compose version >/dev/null 2>&1 || fail "Podman Compose nao esta disponivel."

info "Verificando portas"
assert_port_free "$MONGODB_PORT"
assert_port_free "$REDIS_PORT"

info "Criando diretorios do projeto"
mkdir -p mongo/init redis evidencias scripts api frontend tests

if [[ ! -f .gitignore ]]; then
  cat > .gitignore <<'EOF'
.env
__pycache__/
.pytest_cache/
node_modules/
dist/
EOF
  success ".gitignore criado."
elif ! grep -qxF '.env' .gitignore; then
  printf '\n.env\n' >> .gitignore
  success ".env adicionado ao .gitignore existente."
fi

if [[ ! -f .env ]]; then
  cat > .env <<'EOF'
# Ambiente local academico. Nao versionar este arquivo.
MONGO_ROOT_USERNAME=jurisdocs_root
MONGO_ROOT_PASSWORD=6a7d5e8f9c2b1a4d7e3f8c6a9b2d5e1f4a7c8d9e2b6f3a5c

MONGO_DATABASE=jurisdocs
MONGO_APP_USERNAME=jurisdocs_api
MONGO_APP_PASSWORD=1f8a6d3c9e5b2a7f4d8c6e1a9b3f5d7c2e8a4b6d9f1c3e5a

REDIS_PASSWORD=9c4e7a1d6f3b8e2c5a9d4f7e1b6c3a8d5e2f9a4c7b1d6e3f
FLASK_SECRET_KEY=4e8a1c7d5f2b9e6a3c8d1f7e4b2a9c6d5e3f8a1b7c4d9e2f
EOF
  chmod 600 .env
  success ".env criado com permissoes locais restritas."
else
  success ".env ja existe; nenhum segredo foi sobrescrito."
fi

if [[ ! -f compose.yaml ]]; then
  cat > compose.yaml <<'EOF'
name: jurisdocs

services:
  mongodb:
    image: docker.io/library/mongo:8.0.30
    container_name: jurisdocs-mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_DATABASE}
    ports:
      - "127.0.0.1:27018:27017"
    volumes:
      - mongodb-data:/data/db
    networks:
      - jurisdocs-net
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "mongosh --quiet --username \"$$MONGO_INITDB_ROOT_USERNAME\" --password \"$$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval \"if (db.adminCommand({ping: 1}).ok !== 1) quit(1)\""
        ]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  redis:
    image: docker.io/library/redis:7.4.12-alpine
    container_name: jurisdocs-redis
    restart: unless-stopped
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    command:
      [
        "redis-server",
        "--appendonly",
        "yes",
        "--requirepass",
        "${REDIS_PASSWORD}"
      ]
    ports:
      - "127.0.0.1:6380:6379"
    volumes:
      - redis-data:/data
    networks:
      - jurisdocs-net
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "REDISCLI_AUTH=\"$$REDIS_PASSWORD\" redis-cli ping | grep -q PONG"
        ]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s

volumes:
  mongodb-data:
  redis-data:

networks:
  jurisdocs-net:
    driver: bridge
EOF
  success "compose.yaml criado."
else
  success "compose.yaml ja existe; ele nao foi sobrescrito."
fi

info "Validando o arquivo Compose"
podman compose -p "$PROJECT_NAME" config >/dev/null
success "Arquivo Compose valido."

info "Baixando imagens oficiais"
podman compose -p "$PROJECT_NAME" pull

info "Subindo MongoDB e Redis"
podman compose -p "$PROJECT_NAME" up -d mongodb redis

info "Aguardando healthchecks"
wait_for_healthy "$MONGODB_CONTAINER"
wait_for_healthy "$REDIS_CONTAINER"

info "Estado final"
podman compose -p "$PROJECT_NAME" ps

cat <<'EOF'

Infraestrutura pronta.

Proximas verificacoes para registrar em evidencia:
  podman compose -p jurisdocs ps
  podman logs --tail 30 jurisdocs-mongodb
  podman logs --tail 30 jurisdocs-redis

O proximo passo sera configurar cada banco (usuario da aplicacao, colecao,
indices, dados ficticios e testes de conexao). Nenhum dado academico foi criado
por este script.
EOF
