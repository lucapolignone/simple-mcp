#!/usr/bin/env bash
# install.sh — Installer MCP Qdrant per Claude Code
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/lucapolignone/simple-mcp/main/install.sh | bash -s -- \
#     --name qdrant-younica \
#     --collection younica-code \
#     --qdrant-url http://HOST:PORT \
#     --embedding-url http://HOST:PORT

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Default values — modifica OWNER/REPO con il tuo repo GitHub
# ═══════════════════════════════════════════════════════════════════════════════
REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/OWNER/REPO/main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/qdrant-mcp}"
CLAUDE_CONFIG="${CLAUDE_CONFIG:-$HOME/.claude.json}"

SERVER_NAME=""
COLLECTION=""
QDRANT_URL=""
EMBEDDING_URL=""
SEARCH_LIMIT="8"

# ═══════════════════════════════════════════════════════════════════════════════
# Parse args
# ═══════════════════════════════════════════════════════════════════════════════
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)           SERVER_NAME="$2"; shift 2 ;;
        --collection)     COLLECTION="$2"; shift 2 ;;
        --qdrant-url)     QDRANT_URL="$2"; shift 2 ;;
        --embedding-url)  EMBEDDING_URL="$2"; shift 2 ;;
        --limit)          SEARCH_LIMIT="$2"; shift 2 ;;
        --config)         CLAUDE_CONFIG="$2"; shift 2 ;;
        --install-dir)    INSTALL_DIR="$2"; shift 2 ;;
        --repo-url)       REPO_URL="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
Uso: $0 [opzioni]

Opzioni obbligatorie:
  --name NAME              Nome MCP server in .claude.json
  --collection NAME        Collection Qdrant
  --qdrant-url URL         URL Qdrant (es. http://host:30333)
  --embedding-url URL      URL embedding server (es. http://host:30797)

Opzioni facoltative:
  --limit N                Max risultati per query (default: 8)
  --config PATH            File config Claude (default: ~/.claude.json)
  --install-dir PATH       Directory installazione (default: ~/.local/share/qdrant-mcp)
  --repo-url URL           Base URL repo (default: hardcoded)
EOF
            exit 0
            ;;
        *)
            echo "❌ Opzione sconosciuta: $1"
            echo "   Usa --help per la lista delle opzioni"
            exit 1
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# Validazione parametri obbligatori
# ═══════════════════════════════════════════════════════════════════════════════
MISSING=()
[[ -z "$SERVER_NAME"   ]] && MISSING+=("--name")
[[ -z "$COLLECTION"    ]] && MISSING+=("--collection")
[[ -z "$QDRANT_URL"    ]] && MISSING+=("--qdrant-url")
[[ -z "$EMBEDDING_URL" ]] && MISSING+=("--embedding-url")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "❌ Parametri obbligatori mancanti: ${MISSING[*]}"
    echo "   Usa --help per la lista delle opzioni"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Checks
# ═══════════════════════════════════════════════════════════════════════════════
echo "🔍 Controllo prerequisiti..."

command -v python3 >/dev/null 2>&1 || { echo "❌ python3 non trovato"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl non trovato"; exit 1; }

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "   ✅ Python $PYTHON_VERSION"

# ═══════════════════════════════════════════════════════════════════════════════
# Install script
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "📦 Installazione in $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

echo "   Download qdrant_mcp.py..."
curl -fsSL "$REPO_URL/qdrant_mcp.py" -o "$INSTALL_DIR/qdrant_mcp.py"
chmod +x "$INSTALL_DIR/qdrant_mcp.py"

# ═══════════════════════════════════════════════════════════════════════════════
# Virtualenv con deps
# ═══════════════════════════════════════════════════════════════════════════════
VENV_DIR="$INSTALL_DIR/.venv"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "   Creo virtualenv in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

echo "   Installo dipendenze (mcp, requests)..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet mcp requests

PYTHON_BIN="$VENV_DIR/bin/python3"

# ═══════════════════════════════════════════════════════════════════════════════
# Test connettività
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "🔌 Test connettività..."

if curl -sf --max-time 5 "$QDRANT_URL/collections/$COLLECTION" >/dev/null 2>&1; then
    POINTS=$(curl -sf "$QDRANT_URL/collections/$COLLECTION" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['points_count'])")
    echo "   ✅ Qdrant raggiungibile — collection '$COLLECTION' ha $POINTS punti"
else
    echo "   ⚠️  Qdrant NON raggiungibile a $QDRANT_URL (installazione procede comunque)"
fi

if curl -sf --max-time 5 "$EMBEDDING_URL/health" >/dev/null 2>&1; then
    echo "   ✅ Embedding server raggiungibile a $EMBEDDING_URL"
else
    echo "   ⚠️  Embedding server NON raggiungibile a $EMBEDDING_URL (installazione procede comunque)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Update .claude.json
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "⚙️  Aggiorno $CLAUDE_CONFIG..."

python3 - <<PYEOF
import json, os, sys
from pathlib import Path

path = Path(os.path.expanduser("$CLAUDE_CONFIG"))
path.parent.mkdir(parents=True, exist_ok=True)

data = {}
if path.exists():
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print(f"   ⚠️  $CLAUDE_CONFIG esistente non è JSON valido, sovrascrivo")
        data = {}

data.setdefault("mcpServers", {})

if "$SERVER_NAME" in data["mcpServers"]:
    print(f"   ℹ️  Aggiorno server esistente '$SERVER_NAME'")
else:
    print(f"   ➕ Aggiungo nuovo server '$SERVER_NAME'")

data["mcpServers"]["$SERVER_NAME"] = {
    "command": "$PYTHON_BIN",
    "args": ["$INSTALL_DIR/qdrant_mcp.py"],
    "env": {
        "QDRANT_URL": "$QDRANT_URL",
        "EMBEDDING_URL": "$EMBEDDING_URL",
        "COLLECTION": "$COLLECTION",
        "SEARCH_LIMIT": "$SEARCH_LIMIT"
    }
}

with open(path, "w") as f:
    json.dump(data, f, indent=2)

print(f"   ✅ $CLAUDE_CONFIG aggiornato")
PYEOF

# ═══════════════════════════════════════════════════════════════════════════════
# Done
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "🎉 Installazione completata!"
echo ""
echo "   MCP server:     $SERVER_NAME"
echo "   Collection:     $COLLECTION"
echo "   Qdrant:         $QDRANT_URL"
echo "   Embedding:      $EMBEDDING_URL"
echo "   Script:         $INSTALL_DIR/qdrant_mcp.py"
echo "   Python:         $PYTHON_BIN"
echo "   Config:         $CLAUDE_CONFIG"
echo ""
echo "📝 Prossimi passi:"
echo "   1. Riavvia Claude Code per caricare il nuovo MCP server"
echo "   2. In Claude Code chiedi: 'cerca autenticazione Keycloak'"
echo ""
echo "🗑️  Per disinstallare:"
echo "   rm -rf $INSTALL_DIR"
echo "   # Poi rimuovi '$SERVER_NAME' da $CLAUDE_CONFIG"
