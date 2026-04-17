# simple-mcp

MCP server per ricerca semantica su Qdrant con embedding server OpenAI-compatible (es. proxy verso AWS Bedrock, OpenAI, Cohere, ecc).

## Architettura

```
Claude Code → simple-mcp (MCP server, Node.js)
                  ↓ HTTP
          Embedding Server (OpenAI-compatible)
                  ↓
          AWS Bedrock / Cohere / OpenAI / ...
                  ↓
          Qdrant (vector DB)
```

## Prerequisiti

- Node.js 18+
- Accesso di rete a Qdrant e all'embedding server

## Installazione

Aggiungi al tuo `~/.claude/claude.json`:

```json
{
  "mcpServers": {
    "qdrant-younica": {
      "command": "npx",
      "args": ["-y", "github:lucapolignone/simple-mcp"],
      "env": {
        "QDRANT_URL": "http://172.31.51.114:30333",
        "EMBEDDING_URL": "http://172.31.51.114:30797",
        "COLLECTION": "younica-code",
        "SEARCH_LIMIT": "8"
      }
    },
    "qdrant-yougo": {
      "command": "npx",
      "args": ["-y", "github:lucapolignone/simple-mcp"],
      "env": {
        "QDRANT_URL": "http://172.31.51.114:30333",
        "EMBEDDING_URL": "http://172.31.51.114:30797",
        "COLLECTION": "yougo-legacy",
        "SEARCH_LIMIT": "8"
      }
    }
  }
}
```

Poi riavvia Claude Code.

## Variabili d'ambiente

| Variabile | Obbligatoria | Descrizione |
|---|---|---|
| `QDRANT_URL` | ✅ | URL Qdrant (es. `http://host:6333`) |
| `EMBEDDING_URL` | ✅ | URL embedding server OpenAI-compatible |
| `COLLECTION` | ✅ | Nome collection Qdrant |
| `SEARCH_LIMIT` | ❌ | Max risultati per query (default: 8) |

## Requisiti dell'embedding server

Deve esporre un endpoint OpenAI-compatible:

```
POST /v1/embeddings
{
  "input": "testo da embeddare",
  "model": "qualsiasi-stringa"
}

Risposta:
{
  "data": [
    { "embedding": [0.1, 0.2, ...], "index": 0 }
  ]
}
```

## Tool esposto

### `search_code`

Ricerca semantica sul codebase.

**Parametri:**
- `query` (string, required): Query in linguaggio naturale
- `limit` (integer, optional): Numero di risultati (default 8, max 20)
- `repo` (string, optional): Filtra per repository specifico

**Esempi:**

```
search_code(query="Keycloak authentication configuration")
search_code(query="REST controller contratti", limit=10)
search_code(query="notification service", repo="cloud-intranet")
```

## Test manuale

```bash
QDRANT_URL=http://172.31.51.114:30333 \
EMBEDDING_URL=http://172.31.51.114:30797 \
COLLECTION=younica-code \
npx -y github:lucapolignone/simple-mcp
```

## Licenza

MIT
