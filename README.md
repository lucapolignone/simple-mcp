# qdrant-mcp

MCP server per ricerca semantica su Qdrant, pensato per usare un embedding server custom OpenAI-compatible (es. proxy verso AWS Bedrock).

## Architettura

```
Claude Code → qdrant_mcp.py (MCP server)
                  ↓ HTTP
          Embedding Server (OpenAI-compatible)
                  ↓
          AWS Bedrock / Cohere / OpenAI / ...
                  ↓
          Qdrant (vector DB)
```

## Installazione rapida

```bash
curl -sSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | bash -s -- \
  --name qdrant-younica \
  --collection younica-code \
  --qdrant-url http://172.31.51.114:30333 \
  --embedding-url http://172.31.51.114:30797
```

Lo script:
1. Scarica `qdrant_mcp.py` in `~/.local/share/qdrant-mcp/`
2. Crea un virtualenv con le dipendenze (`mcp`, `requests`)
3. Aggiorna `~/.claude.json` con la configurazione MCP
4. Testa la connettività a Qdrant e all'embedding server

## Installazioni multiple

Puoi installare più server per collection diverse:

```bash
# Younica
curl -sSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | bash -s -- \
  --name qdrant-younica --collection younica-code

# YouGO
curl -sSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | bash -s -- \
  --name qdrant-yougo --collection yougo-legacy
```

## Opzioni installer

| Flag | Default | Descrizione |
|---|---|---|
| `--name` | `qdrant-search` | Nome MCP server in `.claude.json` |
| `--collection` | `younica-code` | Nome collection Qdrant |
| `--qdrant-url` | `http://172.31.51.114:30333` | URL Qdrant |
| `--embedding-url` | `http://172.31.51.114:30797` | URL embedding server |
| `--limit` | `8` | Max risultati per query |
| `--config` | `~/.claude.json` | File config Claude Code |
| `--install-dir` | `~/.local/share/qdrant-mcp` | Directory installazione |

## Prerequisiti

- Python 3.10+
- `curl`
- Accesso di rete a Qdrant e all'embedding server

## Requisiti dell'embedding server

Lo script si aspetta un endpoint OpenAI-compatible:

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

## Uso

Dopo l'installazione, riavvia Claude Code. Il server espone un tool `search_code`:

```
search_code(query="Keycloak authentication configuration")
search_code(query="REST controller contratti", limit=10)
search_code(query="notification service", repo="cloud-intranet")
```

## Disinstallazione

```bash
rm -rf ~/.local/share/qdrant-mcp
# Poi rimuovi manualmente il server da ~/.claude.json
```

## Test manuale

```bash
QDRANT_URL=http://172.31.51.114:30333 \
EMBEDDING_URL=http://172.31.51.114:30797 \
COLLECTION=younica-code \
~/.local/share/qdrant-mcp/.venv/bin/python3 ~/.local/share/qdrant-mcp/qdrant_mcp.py
```

Poi invia un messaggio MCP via stdin (formato JSON-RPC).

## Licenza

MIT
