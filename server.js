#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const QDRANT_URL    = process.env.QDRANT_URL;
const EMBEDDING_URL = process.env.EMBEDDING_URL;
const COLLECTION    = process.env.COLLECTION;
const DEFAULT_LIMIT = parseInt(process.env.SEARCH_LIMIT || "8", 10);

if (!QDRANT_URL || !EMBEDDING_URL || !COLLECTION) {
  console.error("ERRORE: variabili d'ambiente mancanti.");
  console.error("Richieste: QDRANT_URL, EMBEDDING_URL, COLLECTION");
  process.exit(1);
}

async function embed(text) {
  const resp = await fetch(`${EMBEDDING_URL}/v1/embeddings`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ input: text, model: "embed" }),
  });
  if (!resp.ok) throw new Error(`Embedding ${resp.status}: ${await resp.text()}`);
  const data = await resp.json();
  return data.data[0].embedding;
}

async function search(query, limit, repoFilter) {
  const vector = await embed(query);
  const payload = { vector, limit, with_payload: true };
  if (repoFilter) {
    payload.filter = { must: [{ key: "repo", match: { value: repoFilter } }] };
  }
  const resp = await fetch(
    `${QDRANT_URL}/collections/${COLLECTION}/points/search`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }
  );
  if (!resp.ok) throw new Error(`Qdrant ${resp.status}: ${await resp.text()}`);
  const data = await resp.json();
  return data.result || [];
}

const server = new Server(
  { name: "qdrant-search", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "search_code",
      description:
        `Ricerca semantica sul codebase (collection "${COLLECTION}"). ` +
        "Usa linguaggio naturale (italiano o inglese) per trovare codice per concetto, " +
        "funzionalità o dominio. Restituisce chunk di codice con repo, file, score di similarità.",
      inputSchema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description:
              "Query in linguaggio naturale. Es: 'Keycloak authentication', 'gestione ferie dipendente'",
          },
          limit: {
            type: "integer",
            description: `Numero di risultati (default ${DEFAULT_LIMIT}, max 20)`,
            default: DEFAULT_LIMIT,
          },
          repo: {
            type: "string",
            description:
              "Filtra per repository (opzionale). Es: 'cloud-intranet', 'administration-fe'",
          },
        },
        required: ["query"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "search_code") {
    throw new Error(`Tool sconosciuto: ${request.params.name}`);
  }

  const args = request.params.arguments || {};
  const query = args.query;
  const limit = Math.min(parseInt(args.limit, 10) || DEFAULT_LIMIT, 20);
  const repo = args.repo;

  try {
    const results = await search(query, limit, repo);
    if (!results.length) {
      return { content: [{ type: "text", text: "Nessun risultato trovato." }] };
    }

    const lines = [
      `## Risultati ricerca: "${query}"`,
      `Collection: \`${COLLECTION}\` | Risultati: ${results.length}`,
      "",
    ];

    results.forEach((r, i) => {
      const p = r.payload || {};
      lines.push(
        `### ${i + 1}. \`${p.repo || ""}/${p.file || ""}\` (chunk ${p.chunk || 0}) — score ${r.score.toFixed(3)}`
      );
      lines.push("```" + (p.ext || "").replace(/^\./, ""));
      lines.push((p.content || "").trim());
      lines.push("```");
      lines.push("");
    });

    return { content: [{ type: "text", text: lines.join("\n") }] };
  } catch (e) {
    return {
      content: [{ type: "text", text: `Errore ricerca: ${e.message}` }],
      isError: true,
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
