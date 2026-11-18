# Arquitetura do JurisDocs

## Visão geral

O JurisDocs utiliza o MongoDB como base NoSQL principal e o Redis como cache complementar. A aplicação foi separada em contêineres para manter responsabilidades isoladas e facilitar a reprodução do ambiente de avaliação.

```text
Navegador → Frontend React/Nginx → API Flask → MongoDB
                                         └──→ Redis
```

O Nginx entrega os arquivos estáticos do React e encaminha as solicitações iniciadas por `/api` para a API Flask. Assim, a interface e a API são consumidas pelo mesmo endereço de origem durante a demonstração local.

## Serviços

| Serviço | Imagem/camada | Papel | Persistência |
| --- | --- | --- | --- |
| `frontend` | Nginx com build React | interface e proxy reverso para a API | não necessária |
| `api` | Flask + Gunicorn | REST, validação, CRUD, cache e healthcheck | não necessária |
| `mongodb` | MongoDB 8 | dados e índices da coleção `documentos` | volume `mongodb-data` |
| `redis` | Redis 7 com AOF | cache de leituras e metadados temporários | volume `redis-data` |
| `mongo-express` | Mongo Express | inspeção acadêmica do MongoDB | não necessária |
| `redis-commander` | Redis Commander | inspeção acadêmica das chaves Redis | não necessária |

## Dados no MongoDB

A coleção principal é `documentos`. Cada documento contém número, título, tipo, descrição, status, tags e datas de criação/atualização.

Índices aplicados:

- `uq_documentos_numero`: campo `numero` único;
- `idx_documentos_texto`: texto em `titulo`, `descricao` e `tags`;
- `idx_tipo_status_data`: filtro combinado por `tipo`, `status` e `dataCriacao`.

## Estratégia de cache

O cache usa o padrão **cache-aside**:

1. A API calcula a chave da consulta e procura a resposta no Redis.
2. Em caso de acerto, devolve a resposta com `X-Cache: HIT`.
3. Em caso de ausência, consulta o MongoDB, grava o resultado com TTL de 60 segundos e devolve `X-Cache: MISS`.
4. Operações `POST`, `PUT` e `DELETE` invalidam as chaves relacionadas.
5. Se o Redis falhar, a API consulta o MongoDB e informa `X-Cache: BYPASS`.

Essa estratégia mantém o MongoDB como fonte de verdade e evita indisponibilidade da aplicação por falha no cache.

## Rede e segurança local

Todos os serviços compartilham a rede privada criada pelo Compose. MongoDB e Redis publicam portas somente no loopback (`127.0.0.1`), evitando acesso de outros computadores da rede local. Senhas e chaves ficam no arquivo `.env`, que é ignorado pelo Git; use `.env.example` como referência para uma instalação nova.
