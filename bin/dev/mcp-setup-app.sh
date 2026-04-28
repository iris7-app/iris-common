#!/usr/bin/env bash
# =============================================================================
# bin/dev/mcp-setup-app.sh — wire up Iris APPLICATION MCP servers
#
# Per shared ADR-0062 : the application MCP servers (iris-java,
# iris-python) expose what the apps PRODUCE in-process (Customer/Order/
# Product domain, Logback ring buffer logs, Micrometer metrics, Actuator
# endpoints, OpenAPI summary). Each backend hosts its own MCP transport :
#
#   Java   — Spring AI 1.1.4 starter at http://localhost:8080/mcp
#   Python — FastMCP 1.27 streamable-http at http://localhost:8000/mcp
#
# RUN THIS SCRIPT AFTER starting the backends. Before they are listening,
# `claude mcp add --transport http …` succeeds (the entry is stored), but
# subsequent `claude mcp list` shows ✗ Failed to connect.
#
# Start the backends :
#   cd ~/dev/iris/iris-service-java && ./mvnw spring-boot:run
#   cd ~/dev/iris/iris-service-python && uv run iris-service
#
# Optional env vars (override defaults) :
#   MIRADOR_JAVA_MCP_URL    — default http://localhost:8080/mcp
#   MIRADOR_PYTHON_MCP_URL  — default http://localhost:8080/mcp (shared port
#                              contract — only one backend runs at 8080 at
#                              a time ; switching is a matter of stopping
#                              one and starting the other ; see body for the
#                              "run both simultaneously" override pattern)
#
# Usage :
#   bin/dev/mcp-setup-app.sh           # wire up both backends
#   bin/dev/mcp-setup-app.sh --check   # dry-run
#   bin/dev/mcp-setup-app.sh --remove  # un-wire
# =============================================================================

set -uo pipefail

DRY_RUN=0
REMOVE=0
case "${1:-}" in
  --check) DRY_RUN=1 ;;
  --remove) REMOVE=1 ;;
  -h|--help)
    sed -n '1,/^# ===/p' "$0" | sed 's/^# //'
    exit 0
    ;;
esac

G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[2m'; N='\033[0m'

ok()    { printf "  ${G}✓${N} %s\n" "$1"; }
skip()  { printf "  ${Y}○${N} %s ${D}(${2:-skipped})${N}\n" "$1"; }
fail()  { printf "  ${R}✗${N} %s\n" "$1"; }

if ! command -v claude >/dev/null 2>&1; then
    fail "claude CLI not found — install via https://claude.com/claude-code"
    exit 1
fi

# Both backends use HTTP transport (streamable-http per the MCP 2025-03-26
# spec). The mcp_add helper here is intentionally narrower than the infra
# variant since URL+transport is the only shape we need — keeps the script
# trivial to audit.
mcp_add_http() {
    local name="$1"
    local url="$2"
    local transport="${3:-http}"

    if [ "$REMOVE" = "1" ]; then
        if claude mcp remove "$name" 2>/dev/null; then
            ok "removed : $name"
        else
            skip "$name" "not installed"
        fi
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        ok "would add : $name → $url (transport=$transport)"
        return
    fi

    claude mcp remove "$name" >/dev/null 2>&1 || true
    if claude mcp add --transport "$transport" "$name" "$url" 2>&1 | tail -1; then
        ok "added : $name → $url (transport=$transport)"
    else
        fail "failed : $name"
    fi
}

# Quick reachability probe : warn if the backend isn't listening but still
# wire the entry — claude will reconnect automatically once the backend
# comes up, no need to re-run this script.
probe_reachable() {
    local label="$1"
    local url="$2"
    local host_port
    host_port=$(printf '%s' "$url" | sed -E 's|^https?://||; s|/.*$||')
    if (echo > "/dev/tcp/${host_port%:*}/${host_port##*:}") 2>/dev/null; then
        printf "  ${D}↳ %s reachable at %s${N}\n" "$label" "$host_port"
    else
        printf "  ${Y}↳ %s NOT listening at %s — start the backend, claude will reconnect${N}\n" "$label" "$host_port"
    fi
}

# ── Iris application MCP servers ──────────────────────────────────

echo "── Iris application MCP servers ──"
echo "${D}  These expose the apps' own domain + logs + metrics + actuator${N}"

# BOTH backends share the SAME default contract — port 8080, /mcp endpoint.
# Per the polyrepo design, Java and Python expose an IDENTICAL OpenAPI + MCP
# tool catalogue and are interchangeable plug-replacements for the UI. This
# means only ONE backend runs at a time on 8080 ; switching is a matter of
# stopping one and starting the other.
#
# To run BOTH simultaneously (rare — usually for parity testing) :
#   1. Start Python on a different port :
#        MIRADOR_SERVER_PORT=8000 uv run iris-service
#   2. Override the URL when wiring :
#        MIRADOR_PYTHON_MCP_URL=http://localhost:8000/mcp bin/dev/mcp-setup-app.sh
#
# Otherwise both MCP entries point at 8080 ; the inactive one shows ✗ Failed
# in `claude mcp list` (expected). Claude routes "use iris-java's tool X"
# vs "iris-python's X" by NAME, so even with shared URL each entry is
# distinct from claude's perspective.
JAVA_MCP_URL="${MIRADOR_JAVA_MCP_URL:-http://localhost:8080/mcp}"
mcp_add_http iris-java "$JAVA_MCP_URL"
[ "$DRY_RUN" = "0" ] && [ "$REMOVE" = "0" ] && probe_reachable "iris-java" "$JAVA_MCP_URL"

PY_MCP_URL="${MIRADOR_PYTHON_MCP_URL:-http://localhost:8080/mcp}"
mcp_add_http iris-python "$PY_MCP_URL"
[ "$DRY_RUN" = "0" ] && [ "$REMOVE" = "0" ] && probe_reachable "iris-python" "$PY_MCP_URL"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
if [ "$DRY_RUN" = "1" ]; then
    echo "${Y}DRY-RUN${N} : nothing added. Re-run without --check to apply."
elif [ "$REMOVE" = "1" ]; then
    echo "${Y}REMOVE${N} done. Re-run without --remove to re-wire."
else
    echo "${G}✓ Application MCP setup complete${N}. List with : claude mcp list"
    echo "${D}  Infra MCPs (postgres, prometheus, gitlab, k8s, etc.) : run bin/dev/mcp-setup-infra.sh.${N}"
fi
