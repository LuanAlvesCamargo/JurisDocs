# Referência da API

Base local: `http://127.0.0.1:5050/api`

Todas as respostas são JSON. As leituras que passam pelo cache incluem o cabeçalho `X-Cache` com `MISS`, `HIT` ou `BYPASS`.

## Rotas

| Método | Rota | Finalidade |
| --- | --- | --- |
| `GET` | `/health` | verifica API, MongoDB e Redis |
| `GET` | `/documentos` | lista documentos com pesquisa, filtros e paginação |
| `POST` | `/documentos` | cria documento |
| `GET` | `/documentos/{id}` | consulta um documento por identificador |
| `PUT` | `/documentos/{id}` | atualiza documento |
| `DELETE` | `/documentos/{id}` | exclui documento |
| `GET` | `/estatisticas` | retorna totais utilizados pela interface |

## Listagem e filtros

```bash
curl -i 'http://127.0.0.1:5050/api/documentos?busca=contrato&tipo=Contrato&status=Ativo&pagina=1&limite=10'
```

| Parâmetro | Descrição |
| --- | --- |
| `busca` | termo textual aplicado aos campos indexados |
| `tipo` | classificação do documento |
| `status` | situação do documento |
| `tag` | etiqueta vinculada ao documento |
| `pagina` | página desejada, iniciando em 1 |
| `limite` | quantidade de registros por página |

## Criação

```bash
curl -X POST http://127.0.0.1:5050/api/documentos \
  -H 'Content-Type: application/json' \
  -d '{
    "numero": "DOC-2026-0099",
    "titulo": "Exemplo acadêmico",
    "tipo": "Parecer",
    "descricao": "Registro fictício para demonstração.",
    "status": "Em revisão",
    "tags": ["exemplo", "academico"]
  }'
```

Campos obrigatórios: `numero`, `titulo`, `tipo`, `descricao` e `status`. O campo `numero` deve ser único.

## Códigos de resposta

| Código | Situação |
| --- | --- |
| `200` | leitura, atualização ou exclusão concluída |
| `201` | documento criado |
| `400` | dados inválidos |
| `404` | documento não encontrado |
| `409` | número de documento duplicado |
| `500` | erro interno não previsto |
