#!/usr/bin/env bash
# =============================================================================
# bin/dev/mcp-setup.sh — wire up community MCP servers for Mirador development
#
# Per shared ADR-0062 (mirador-service-java/docs/adr/0062-…) :
#  - The application MCP servers (Java + Python) expose what the apps PRODUCE
#    in-process (domain, logs, metrics, actuator, OpenAPI).
#  - Everything else (Postgres raw access, Mimir queries, Grafana panels,
#    Loki tail, GitLab MRs, GitHub PRs, Kubernetes pods, SonarQube/Cloud
#    quality gate, Auth0 tenant config, Kafka topics, Redis keys, …) goes
#    through COMMUNITY MCP servers added at the Claude Desktop / Code level.
#
# This script wires up the external MCP servers a Mirador dev needs.
# Each `claude mcp add` call is idempotent — re-running is safe.
#
# Required env vars (set in your shell or ~/.profile / ~/.zshenv) :
#   GH_TOKEN              — GitHub PAT with repo scope (read-only fine for most)
#   GITLAB_TOKEN          — GitLab PAT with api scope (project access at minimum)
#   SONAR_TOKEN           — SonarCloud user token (Project > Security > Tokens)
#   GRAFANA_TOKEN         — Grafana admin / viewer token (read-only fine)
#   AUTH0_DOMAIN          — e.g. mirador.eu.auth0.com
#   AUTH0_CLIENT_ID       — Auth0 M2M app client ID (read-only API access)
#   AUTH0_CLIENT_SECRET   — same M2M app client secret
#   HASS_URL              — e.g. http://homeassistant.local:8123 (local network)
#   HASS_TOKEN            — Long-lived token from HA Profile → Long-Lived Tokens
#
# Optional env vars (override defaults) :
#   POSTGRES_URL          — default postgresql://demo:demo@localhost:5432/mirador
#   PROMETHEUS_URL        — default http://localhost:9091  (LGTM container Mimir)
#   GRAFANA_URL           — default http://localhost:3000  (LGTM container Grafana)
#   K8S_CONTEXT           — default current kubectl context (~/.kube/config)
#
# Usage :
#   bin/dev/mcp-setup.sh           # wire up everything env vars cover
#   bin/dev/mcp-setup.sh --check   # dry-run : list what would be added
#   bin/dev/mcp-setup.sh --remove  # un-wire everything (clean slate)
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

mcp_add() {
    local name="$1"
    local cmd="$2"
    shift 2

    if [ "$REMOVE" = "1" ]; then
        if claude mcp remove "$name" 2>/dev/null; then
            ok "removed : $name"
        else
            skip "$name" "not installed"
        fi
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        ok "would add : $name → $cmd"
        return
    fi

    # Re-add idempotently : remove first if already present, ignore failure
    claude mcp remove "$name" >/dev/null 2>&1 || true
    if claude mcp add "$name" "$cmd" "$@" 2>&1 | tail -1; then
        ok "added : $name"
    else
        fail "failed : $name"
    fi
}

# ── Section 1 : Always-on (no env vars required) ──────────────────────

echo "── Always-on MCP servers ──"

# Filesystem — official Anthropic, lets Claude read/write files outside cwd if asked
mcp_add filesystem "npx -y @modelcontextprotocol/server-filesystem ~/dev/mirador"

# ── Section 2 : Mirador app MCP servers (custom, in-process) ──────────

echo ""
echo "── Mirador application MCP servers ──"
echo "${D}  These expose the app's own domain + logs + metrics + actuator${N}"

# Java backend — assumed running locally (or pointed via env to staging/prod)
JAVA_MCP_URL="${MIRADOR_JAVA_MCP_URL:-http://localhost:8080/mcp}"
mcp_add mirador-java "$JAVA_MCP_URL"

# Python backend — same shape, port 8000 by default
PY_MCP_URL="${MIRADOR_PYTHON_MCP_URL:-http://localhost:8000/mcp}"
mcp_add mirador-python "$PY_MCP_URL"

# ── Section 3 : Database (Postgres) ──────────────────────────────────

echo ""
echo "── Database MCP servers ──"

POSTGRES_URL="${POSTGRES_URL:-postgresql://demo:demo@localhost:5432/mirador}"
mcp_add postgres-mirador "npx -y @modelcontextprotocol/server-postgres" --env URL="$POSTGRES_URL"

# ── Section 4 : Observability (Prometheus / Mimir, Grafana, Loki) ────

echo ""
echo "── Observability MCP servers ──"

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9091}"
mcp_add prometheus "npx -y mcp-server-prometheus" --env URL="$PROMETHEUS_URL"

if [ -n "${GRAFANA_TOKEN:-}" ]; then
    GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
    mcp_add grafana "npx -y mcp-grafana" --env URL="$GRAFANA_URL" --env TOKEN="$GRAFANA_TOKEN"
else
    skip "grafana" "GRAFANA_TOKEN not set"
fi

# Loki — fewer maintained MCP packages exist ; skip until a stable one ships
skip "loki" "no stable community MCP yet — use grafana for log queries via the LGTM stack"

# ── Section 5 : Source control (GitLab + GitHub) ─────────────────────

echo ""
echo "── Source control MCP servers ──"

if [ -n "${GITLAB_TOKEN:-}" ]; then
    mcp_add gitlab "npx -y @modelcontextprotocol/server-gitlab" \
        --env GITLAB_PERSONAL_ACCESS_TOKEN="$GITLAB_TOKEN" \
        --env GITLAB_API_URL="https://gitlab.com/api/v4"
else
    skip "gitlab" "GITLAB_TOKEN not set"
fi

if [ -n "${GH_TOKEN:-}" ]; then
    mcp_add github "github-mcp-server" --env GITHUB_TOKEN="$GH_TOKEN"
else
    skip "github" "GH_TOKEN not set"
fi

# ── Section 6 : Quality gate (SonarCloud) ────────────────────────────

echo ""
echo "── Quality MCP servers ──"

if [ -n "${SONAR_TOKEN:-}" ]; then
    SONAR_URL="${SONAR_URL:-https://sonarcloud.io}"
    mcp_add sonar "npx -y mcp-server-sonarqube" \
        --env SONAR_URL="$SONAR_URL" \
        --env SONAR_TOKEN="$SONAR_TOKEN"
else
    skip "sonar" "SONAR_TOKEN not set"
fi

# ── Section 7 : Kubernetes (GKE prod, kind local) ────────────────────

echo ""
echo "── Kubernetes MCP servers ──"

# Generic kubectl wrapper — works against any cluster pointed at by ~/.kube/config
# For Mirador : prod GKE = mirador-prod (europe-west1) ; local = kind-mirador-local
if command -v kubectl >/dev/null 2>&1; then
    mcp_add kubernetes "npx -y mcp-server-kubernetes" \
        ${K8S_CONTEXT:+--env CONTEXT="$K8S_CONTEXT"}
else
    skip "kubernetes" "kubectl not installed"
fi

# ── Section 8 : Auth (Auth0) ─────────────────────────────────────────

echo ""
echo "── Auth MCP servers ──"

if [ -n "${AUTH0_DOMAIN:-}" ] && [ -n "${AUTH0_CLIENT_ID:-}" ] && [ -n "${AUTH0_CLIENT_SECRET:-}" ]; then
    # Note : if no community MCP exists for Auth0, set up via curl-based custom
    # MCP server in mirador-common/bin/mcp-servers/auth0.sh (TODO).
    mcp_add auth0 "npx -y mcp-server-auth0" \
        --env AUTH0_DOMAIN="$AUTH0_DOMAIN" \
        --env AUTH0_CLIENT_ID="$AUTH0_CLIENT_ID" \
        --env AUTH0_CLIENT_SECRET="$AUTH0_CLIENT_SECRET" \
    || skip "auth0" "no community package yet — DIY wrapper needed (see ADR-0062)"
else
    skip "auth0" "AUTH0_DOMAIN/CLIENT_ID/CLIENT_SECRET not all set"
fi

# ── Section 9 : Messaging + cache (Kafka, Redis, Docker) ─────────────

echo ""
echo "── Infra MCP servers ──"

# Kafka — community, choose one of :
#   - kafka-mcp-server (Python)
#   - mcp-kafka (Node)
mcp_add kafka "npx -y mcp-kafka" --env BROKERS="${KAFKA_BROKERS:-localhost:9092}" \
    || skip "kafka" "no community package fits — use docker exec for now"

# Redis — community
mcp_add redis "npx -y mcp-server-redis" --env URL="${REDIS_URL:-redis://localhost:6379}" \
    || skip "redis" "no community package fits — use docker exec / redis-cli for now"

# Docker — official, useful for local dev (ps, logs)
mcp_add docker "npx -y mcp-server-docker" || skip "docker" "no community package found"

# ── Section 10 : Home Automation (Home Assistant on local network) ───

echo ""
echo "── Home automation MCP servers ──"

# Home Assistant — community MCP server (hass-mcp on npm), talks to a HA
# instance via its REST API on the local network. Long-lived token from
# HA UI → Profile → Long-Lived Access Tokens → Create Token.
#
# Env vars (note : env var names match what hass-mcp expects, NOT HA's
# own HOMEASSISTANT_* convention) :
#   HASS_URL    — e.g. http://homeassistant.local:8123  or  http://192.168.1.42:8123
#   HASS_TOKEN  — long-lived access token from HA Profile page
#
# DO NOT expose your HA token in CI ; this is a local-dev MCP only.
# 3 tools exposed by hass-mcp : ha_get_state, ha_list_states, ha_call_service.
if [ -n "${HASS_URL:-}" ] && [ -n "${HASS_TOKEN:-}" ]; then
    mcp_add home-assistant "npx -y hass-mcp" \
        --env HASS_URL="$HASS_URL" \
        --env HASS_TOKEN="$HASS_TOKEN"
else
    skip "home-assistant" "HASS_URL and HASS_TOKEN must both be set"
fi

# ── Section 11 : Robotics (Ecovacs vacuum/mop robots) ───────────────

echo ""
echo "── Robotics MCP servers ──"

# Ecovacs — official MCP server published by Ecovacs (github.com/ecovacs-ai/
# ecovacs-mcp). Two transport modes ; we use SSE remote because it's hosted
# by Ecovacs and zero-install :
#   stdio local : `python -m ecovacs_robot_mcp` + ECO_API_KEY env
#   sse remote  : https://open.ecovacs.<region>/sse?ak=<AK>     ← chosen
#
# 4 tools : list_devices, start_cleaning (s/p/r/h), return_to_base
# (go-start/stopGo), query_status (cleanSt + chargeSt + stationSt).
#
# AK (API Key) is obtained one-time at https://open.ecovacs.com/preparationForUse
# (or open.ecovacs.cn if you're in mainland China). Do NOT expose your AK
# in CI ; this is a local-dev MCP only.
#
# Env vars :
#   ECO_API_KEY — Access Key from open.ecovacs.com developer portal
#   ECO_API_URL — optional, defaults to https://open.ecovacs.com
#                  (use https://open.ecovacs.cn for mainland China)
if [ -n "${ECO_API_KEY:-}" ]; then
    ECO_API_URL="${ECO_API_URL:-https://open.ecovacs.com}"
    mcp_add ecovacs "${ECO_API_URL}/sse?ak=${ECO_API_KEY}" --transport sse
else
    skip "ecovacs" "ECO_API_KEY not set — get one at https://open.ecovacs.com/preparationForUse"
fi

# ── Section 12 : (optional) Slack, Linear, Jira — uncomment if used ──

# if [ -n "${SLACK_TOKEN:-}" ]; then
#     mcp_add slack "npx -y @modelcontextprotocol/server-slack" --env SLACK_BOT_TOKEN="$SLACK_TOKEN"
# fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
if [ "$DRY_RUN" = "1" ]; then
    echo "${Y}DRY-RUN${N} : nothing added. Re-run without --check to apply."
elif [ "$REMOVE" = "1" ]; then
    echo "${Y}REMOVE${N} done. Re-run without --remove to re-wire."
else
    echo "${G}✓ MCP setup complete${N}. List with : claude mcp list"
fi
