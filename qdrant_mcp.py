#!/usr/bin/env python3
"""
qdrant_mcp.py — MCP server minimo per ricerca semantica su Qdrant.

Uso:
  QDRANT_URL=http://host:30333 EMBEDDING_URL=http://host:30797 \
  COLLECTION=younica-code python3 qdrant_mcp.py

Dipendenze: pip install mcp requests
"""
import os, json, sys
import requests
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp import types

QDRANT_URL    = os.environ.get("QDRANT_URL", "http://172.31.51.114:30333")
EMBEDDING_URL = os.environ.get("EMBEDDING_URL", "http://172.31.51.114:30797")
COLLECTION    = os.environ.get("COLLECTION", "younica-code")
DEFAULT_LIMIT = int(os.environ.get("SEARCH_LIMIT", "8"))

server = Server("qdrant-search")

def embed(text: str) -> list[float]:
    resp = requests.post(
        f"{EMBEDDING_URL}/v1/embeddings",
        json={"input": text, "model": "embed"},
        timeout=30
    )
    resp.raise_for_status()
    return resp.json()["data"][0]["embedding"]

def search(query: str, limit: int = DEFAULT_LIMIT, repo_filter: str | None = None) -> list[dict]:
    vector = embed(query)
    payload: dict = {"vector": vector, "limit": limit, "with_payload": True}
    if repo_filter:
        payload["filter"] = {
            "must": [{"key": "repo", "match": {"value": repo_filter}}]
        }
    resp = requests.post(
        f"{QDRANT_URL}/collections/{COLLECTION}/points/search",
        json=payload,
        timeout=30
    )
    resp.raise_for_status()
    return resp.json().get("result", [])

@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="search_code",
            description=(
                f"Ricerca semantica sul codebase ({COLLECTION}). "
                "Usa linguaggio naturale per trovare codice per concetto, funzionalità o dominio. "
                "Restituisce i chunk di codice più rilevanti con repo, file e score di similarità."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Query in linguaggio naturale (italiano o inglese). Es: 'Keycloak authentication configuration', 'gestione ferie dipendente'"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Numero di risultati (default 8, max 20)",
                        "default": DEFAULT_LIMIT
                    },
                    "repo": {
                        "type": "string",
                        "description": "Filtra per repository specifico (opzionale). Es: 'cloud-intranet', 'administration-fe'"
                    }
                },
                "required": ["query"]
            }
        )
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    if name != "search_code":
        raise ValueError(f"Tool sconosciuto: {name}")

    query      = arguments["query"]
    limit      = min(int(arguments.get("limit", DEFAULT_LIMIT)), 20)
    repo       = arguments.get("repo")

    try:
        results = search(query, limit=limit, repo_filter=repo)
    except Exception as e:
        return [types.TextContent(type="text", text=f"Errore ricerca: {e}")]

    if not results:
        return [types.TextContent(type="text", text="Nessun risultato trovato.")]

    lines = [f"## Risultati ricerca: \"{query}\"",
             f"Collection: `{COLLECTION}` | Risultati: {len(results)}\n"]

    for i, r in enumerate(results, 1):
        p = r["payload"]
        lines.append(f"### {i}. `{p.get('repo','')}/{p.get('file','')}` (chunk {p.get('chunk',0)}) — score {r['score']:.3f}")
        lines.append(f"```{p.get('ext','').lstrip('.')}")
        lines.append(p.get("content", "").strip())
        lines.append("```\n")

    return [types.TextContent(type="text", text="\n".join(lines))]

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream,
                         server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
