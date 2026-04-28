#!/usr/bin/env bash
# =============================================================================
# bin/dev/mcp-setup-infra.sh — wire up community (infra) MCP servers
#
# Per shared ADR-0062 (iris-service-java/docs/adr/0062-…) :
#   - APPLICATION MCP servers (iris-java, iris-python) expose what the
#     apps PRODUCE in-process — wired by the SIBLING `mcp-setup-app.sh`
#     because they require the backends to be running.
#   - COMMUNITY MCP servers (postgres, prometheus, grafana, gitlab, github,
#     k8s, auth0, redis, docker, filesystem) cover everything ELSE — wired
#     here. They don't need the backends, so this script can run any time.
#
# Why split ? `mcp-setup-app.sh` only makes sense after `./mvnw spring-boot:run`
# (Java) or `uv run iris-service` (Python) ; running it before would wire
# unhealthy entries that show as ✗ Failed in `claude mcp list`. The infra
# script has no such dependency — postgres-demo / kafka / redis / LGTM
# containers handle their own readiness.
#
# Required env vars (set in your shell or ~/.profile / ~/.zshenv) :
#   GH_TOKEN              — GitHub PAT with repo scope (read-only fine for most)
#   GITLAB_TOKEN          — GitLab PAT with api scope (project access at minimum)
#   SONAR_TOKEN           — SonarCloud user token (Project > Security > Tokens)
#   GRAFANA_TOKEN         — Grafana admin / viewer token (read-only fine)
#   AUTH0_DOMAIN          — e.g. mirador.eu.auth0.com
#   AUTH0_CLIENT_ID       — Auth0 M2M app client ID (read-only API access)
#   AUTH0_CLIENT_SECRET   — same M2M app client secret
#
# Optional env vars (override defaults) :
#   POSTGRES_URL          — default postgresql://demo:demo@localhost:5432/mirador
#   PROMETHEUS_URL        — default http://localhost:9091  (LGTM container Mimir)
#   GRAFANA_URL           — default http://localhost:3000  (LGTM container Grafana)
#   REDIS_URL             — default redis://localhost:6379
#   K8S_CONTEXT           — default current kubectl context (~/.kube/config)
#
# Usage :
#   bin/dev/mcp-setup-infra.sh           # wire up everything env vars cover
#   bin/dev/mcp-setup-infra.sh --check   # dry-run : list what would be added
#   bin/dev/mcp-setup-infra.sh --remove  # un-wire everything (clean slate)
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

# -----------------------------------------------------------------------------
# mcp_add — name [--env|-e KEY=VAL]... [--transport TYPE] [--] CMD ARG1 ARG2…
#
# Auto-detects URL vs stdio :
#   - First positional after flags matches ^https?:// → HTTP/SSE transport
#     (default `http`, can be overridden with `--transport sse`).
#   - Otherwise → stdio. The remaining $@ is the command + args, passed
#     after `--` to claude mcp add so it word-splits correctly.
#
# Why the rewrite : the previous mcp_add packed the whole command into a
# single quoted string, which `claude mcp add` then stored verbatim as the
# `command` field — claude tried to exec a binary literally named
# "npx -y @modelcontextprotocol/server-…" and obviously failed. The fix is
# to ALWAYS pass cmd+args as separate argv entries via `-- $@`.
# -----------------------------------------------------------------------------
mcp_add() {
    local name="$1"
    shift

    if [ "$REMOVE" = "1" ]; then
        if claude mcp remove "$name" 2>/dev/null; then
            ok "removed : $name"
        else
            skip "$name" "not installed"
        fi
        return
    fi

    # Parse leading -e/--env and --transport flags ; everything after is
    # the URL or the stdio command + args.
    local opts=()
    local transport="http"
    while [ $# -gt 0 ]; do
        case "$1" in
            -e|--env)
                opts+=("-e" "$2")
                shift 2
                ;;
            -t|--transport)
                transport="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                opts+=("$1")
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$DRY_RUN" = "1" ]; then
        ok "would add : $name → $*"
        return
    fi

    # Re-add idempotently : remove first, ignore failure.
    claude mcp remove "$name" >/dev/null 2>&1 || true

    if [ $# -eq 1 ] && [[ "$1" =~ ^https?:// ]]; then
        # URL → HTTP/SSE transport. -e env vars do not apply here ; ignore
        # them silently rather than fail (the caller may set both for hybrid
        # transport scripts that don't care).
        if claude mcp add --transport "$transport" "$name" "$1" 2>&1 | tail -1; then
            ok "added : $name (transport=$transport)"
        else
            fail "failed : $name"
        fi
    else
        # stdio : opts (e.g. -e KEY=VAL) BEFORE the name per `claude mcp add
        # --help`, then `--` separator, then command + args.
        if claude mcp add "${opts[@]}" "$name" -- "$@" 2>&1 | tail -1; then
            ok "added : $name"
        else
            fail "failed : $name"
        fi
    fi
}

# ── Section 1 : Always-on (no env vars required) ──────────────────────

echo "── Always-on MCP servers ──"

# Filesystem — official Anthropic, lets Claude read/write files outside cwd if asked.
mcp_add filesystem npx -y @modelcontextprotocol/server-filesystem ~/dev/mirador

# ── Section 2 : Database (Postgres) ──────────────────────────────────

echo ""
echo "── Database MCP servers ──"

# @modelcontextprotocol/server-postgres takes the connection string as a
# POSITIONAL argument, NOT as an env var. The previous --env URL=... was
# silently ignored.
POSTGRES_URL="${POSTGRES_URL:-postgresql://demo:demo@localhost:5432/mirador}"
mcp_add postgres-mirador npx -y @modelcontextprotocol/server-postgres "$POSTGRES_URL"

# ── Section 3 : Observability (Prometheus / Mimir, Grafana, Loki) ────

echo ""
echo "── Observability MCP servers ──"

# `prometheus-mcp` (idanfishman, npm) requires a `stdio` subcommand to start
# the MCP server ; without it the binary just prints help and exits.
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9091}"
mcp_add prometheus -e PROMETHEUS_URL="$PROMETHEUS_URL" -- npx -y prometheus-mcp stdio

if [ -n "${GRAFANA_TOKEN:-}" ]; then
    GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
    # The npm package is `mcp-grafana-npx` (animalnots) — NOT `mcp-grafana`
    # which doesn't exist on the registry. Verified 2026-04-27 by trying
    # both : `mcp-grafana` returns E404, `mcp-grafana-npx` connects fine
    # given a valid GRAFANA_API_KEY (use a Grafana service-account token,
    # NOT a legacy /api/auth/keys token — that endpoint is removed in
    # Grafana >= 9.x).
    mcp_add grafana \
        -e GRAFANA_URL="$GRAFANA_URL" \
        -e GRAFANA_API_KEY="$GRAFANA_TOKEN" \
        -- npx -y mcp-grafana-npx
else
    skip "grafana" "GRAFANA_TOKEN not set — create a service-account token at $GRAFANA_URL/api/serviceaccounts (Grafana >= 9.x)"
fi

# Loki — fewer maintained MCP packages exist ; skip until a stable one ships.
skip "loki" "no stable community MCP yet — use grafana for log queries via the LGTM stack"

# ── Section 4 : Source control (GitLab + GitHub) ─────────────────────

echo ""
echo "── Source control MCP servers ──"

if [ -n "${GITLAB_TOKEN:-}" ]; then
    mcp_add gitlab \
        -e GITLAB_PERSONAL_ACCESS_TOKEN="$GITLAB_TOKEN" \
        -e GITLAB_API_URL="https://gitlab.com/api/v4" \
        -- npx -y @modelcontextprotocol/server-gitlab
else
    skip "gitlab" "GITLAB_TOKEN not set"
fi

if [ -n "${GH_TOKEN:-}" ]; then
    mcp_add github -e GITHUB_TOKEN="$GH_TOKEN" -- github-mcp-server
else
    skip "github" "GH_TOKEN not set"
fi

# ── Section 5 : Quality gate (SonarCloud) ────────────────────────────

echo ""
echo "── Quality MCP servers ──"

if [ -n "${SONAR_TOKEN:-}" ]; then
    SONAR_URL="${SONAR_URL:-https://sonarcloud.io}"
    mcp_add sonar \
        -e SONAR_URL="$SONAR_URL" \
        -e SONAR_TOKEN="$SONAR_TOKEN" \
        -- npx -y mcp-server-sonarqube
else
    skip "sonar" "SONAR_TOKEN not set"
fi

# ── Section 6 : Kubernetes (GKE prod, kind local) ────────────────────

echo ""
echo "── Kubernetes MCP servers ──"

# Generic kubectl wrapper — works against any cluster pointed at by ~/.kube/config.
# For Iris : prod GKE = mirador-prod (europe-west1) ; local = kind-mirador-local.
if command -v kubectl >/dev/null 2>&1; then
    if [ -n "${K8S_CONTEXT:-}" ]; then
        mcp_add kubernetes -e CONTEXT="$K8S_CONTEXT" -- npx -y mcp-server-kubernetes
    else
        mcp_add kubernetes npx -y mcp-server-kubernetes
    fi
else
    skip "kubernetes" "kubectl not installed"
fi

# ── Section 7 : Auth (Auth0) ─────────────────────────────────────────

echo ""
echo "── Auth MCP servers ──"

if [ -n "${AUTH0_DOMAIN:-}" ] && [ -n "${AUTH0_CLIENT_ID:-}" ] && [ -n "${AUTH0_CLIENT_SECRET:-}" ]; then
    mcp_add auth0 \
        -e AUTH0_DOMAIN="$AUTH0_DOMAIN" \
        -e AUTH0_CLIENT_ID="$AUTH0_CLIENT_ID" \
        -e AUTH0_CLIENT_SECRET="$AUTH0_CLIENT_SECRET" \
        -- npx -y mcp-server-auth0 \
    || skip "auth0" "no community package yet — DIY wrapper needed (see ADR-0062)"
else
    skip "auth0" "AUTH0_DOMAIN/CLIENT_ID/CLIENT_SECRET not all set"
fi

# ── Section 8 : Cache + Docker (Redis, Docker) ───────────────────────

echo ""
echo "── Infra MCP servers ──"

# Kafka — `kafka-mcp` (npm) is a CLI for inspecting topics, NOT a stdio MCP
# server. No usable community package fits ; skip with rationale. Use
# `docker exec mirador-kafka kafka-topics.sh` for ad-hoc inspection.
skip "kafka" "kafka-mcp on npm is a CLI, not a stdio MCP server — no community package fits"

# Redis — community `redis-mcp` (npm) ; passes URL via env var.
mcp_add redis -e REDIS_URL="${REDIS_URL:-redis://localhost:6379}" -- npx -y redis-mcp

# Docker — community `mcp-server-docker` (no env required).
mcp_add docker npx -y mcp-server-docker

# ── Section 9 : (optional) Slack, Linear, Jira — uncomment if used ──

# if [ -n "${SLACK_TOKEN:-}" ]; then
#     mcp_add slack -e SLACK_BOT_TOKEN="$SLACK_TOKEN" -- npx -y @modelcontextprotocol/server-slack
# fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
if [ "$DRY_RUN" = "1" ]; then
    echo "${Y}DRY-RUN${N} : nothing added. Re-run without --check to apply."
elif [ "$REMOVE" = "1" ]; then
    echo "${Y}REMOVE${N} done. Re-run without --remove to re-wire."
else
    echo "${G}✓ Infra MCP setup complete${N}. List with : claude mcp list"
    echo "${D}  Application MCPs (iris-java, iris-python) : run bin/dev/mcp-setup-app.sh AFTER starting the backends.${N}"
fi
