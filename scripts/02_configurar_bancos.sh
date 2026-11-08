#!/usr/bin/env bash

# JurisDocs — Marco 1: configuracao idempotente de MongoDB e Redis.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f .env ]] || fail "Arquivo .env nao encontrado. Execute primeiro o script 01."

set -a
source .env
set +a

for command in podman; do
  command -v "$command" >/dev/null 2>&1 || fail "Comando ausente: $command"
done

podman inspect jurisdocs-mongodb >/dev/null 2>&1 || fail "Container jurisdocs-mongodb nao encontrado."
podman inspect jurisdocs-redis >/dev/null 2>&1 || fail "Container jurisdocs-redis nao encontrado."

info "Configurando usuario, colecao, indices e dados ficticios no MongoDB"
podman exec -i \
  -e JURISDOCS_APP_DATABASE="$MONGO_DATABASE" \
  -e JURISDOCS_APP_USERNAME="$MONGO_APP_USERNAME" \
  -e JURISDOCS_APP_PASSWORD="$MONGO_APP_PASSWORD" \
  jurisdocs-mongodb \
  mongosh --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin <<'MONGOSH'
const database = process.env.JURISDOCS_APP_DATABASE;
const appUsername = process.env.JURISDOCS_APP_USERNAME;
const appPassword = process.env.JURISDOCS_APP_PASSWORD;
const appDb = db.getSiblingDB(database);

if (!appDb.getUser(appUsername)) {
  appDb.createUser({
    user: appUsername,
    pwd: appPassword,
    roles: [{ role: "readWrite", db: database }]
  });
  print(`Usuario ${appUsername} criado.`);
} else {
  print(`Usuario ${appUsername} ja existe.`);
}

if (!appDb.getCollectionInfos({ name: "documentos" }).length) {
  appDb.createCollection("documentos");
  print("Colecao documentos criada.");
}

appDb.documentos.createIndex({ numero: 1 }, { unique: true, name: "uq_documentos_numero" });
appDb.documentos.createIndex(
  { titulo: "text", descricao: "text", tags: "text" },
  { name: "idx_documentos_texto", default_language: "portuguese" }
);
appDb.documentos.createIndex(
  { tipo: 1, status: 1, dataCriacao: -1 },
  { name: "idx_tipo_status_data" }
);

const documents = [
  {
    numero: "DOC-2026-0001",
    titulo: "Contrato ficticio de prestacao de servicos",
    tipo: "Contrato",
    descricao: "Documento ficticio criado para demonstracao academica.",
    status: "Ativo",
    tags: ["contrato", "servicos", "demonstracao"]
  },
  {
    numero: "DOC-2026-0002",
    titulo: "Peticao inicial ficticia",
    tipo: "Peticao",
    descricao: "Exemplo academico de documento em revisao.",
    status: "Em revisao",
    tags: ["peticao", "processo", "demonstracao"]
  },
  {
    numero: "DOC-2026-0003",
    titulo: "Parecer juridico ficticio",
    tipo: "Parecer",
    descricao: "Parecer ficticio para testes da aplicacao.",
    status: "Ativo",
    tags: ["parecer", "analise", "demonstracao"]
  },
  {
    numero: "DOC-2026-0004",
    titulo: "Termo de confidencialidade ficticio",
    tipo: "Termo",
    descricao: "Registro ficticio arquivado para demonstrar filtros.",
    status: "Arquivado",
    tags: ["termo", "confidencialidade", "arquivo"]
  },
  {
    numero: "DOC-2026-0005",
    titulo: "Notificacao extrajudicial ficticia",
    tipo: "Notificacao",
    descricao: "Registro ficticio em processo de revisao.",
    status: "Em revisao",
    tags: ["notificacao", "revisao", "demonstracao"]
  }
];

for (const document of documents) {
  const now = new Date();
  appDb.documentos.updateOne(
    { numero: document.numero },
    { $setOnInsert: { ...document, dataCriacao: now, dataAtualizacao: now } },
    { upsert: true }
  );
}

print(`Total de documentos: ${appDb.documentos.countDocuments()}`);
printjson(appDb.documentos.getIndexes());
MONGOSH
success "MongoDB configurado."

info "Verificando autenticacao, persistencia AOF e TTL no Redis"
podman exec jurisdocs-redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping'
podman exec jurisdocs-redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli SET jurisdocs:verificacao "redis-operacional" EX 60'
podman exec jurisdocs-redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli GET jurisdocs:verificacao'
podman exec jurisdocs-redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli TTL jurisdocs:verificacao'
success "Redis validado."

info "Resumo da configuracao"
podman exec -i jurisdocs-mongodb \
  mongosh --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "const appDb = db.getSiblingDB('$MONGO_DATABASE'); printjson(appDb.documentos.find({}, {_id: 0, numero: 1, titulo: 1, tipo: 1, status: 1}).toArray())"

cat <<'EOF'

Marco 1 concluido: MongoDB e Redis estao prontos para a API.
O script pode ser executado novamente sem duplicar usuario, indices ou documentos.
EOF
