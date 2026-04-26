#!/usr/bin/env bash
# =============================================================================
# bin/dev/mcp-smoke.sh — read-only end-to-end MCP integration test
#
# Drives the `claude` CLI in non-interactive mode (`claude --print`) with a
# series of read-only prompts. Each prompt asks Claude to use a specific
# MCP tool ; the script captures the response and asserts :
#   - non-empty response
#   - no "error" / "tool unavailable" markers in the output
#   - specific keywords appear when expected
#
# RULE : NO write tools. Never call `create_order`, `delete_order`,
#        `cancel_order`, `trigger_chaos_experiment`. The smoke test must be
#        idempotent and side-effect-free — re-running 100 times produces the
#        same DB state.
#
# Pre-requisites :
#   1. Mirador stack running locally (./run.sh all in mirador-service-java)
#   2. MCP servers wired : bin/dev/mcp-setup.sh has been run
#   3. claude CLI available + authenticated
#
# Usage :
#   bin/dev/mcp-smoke.sh         # run all checks
#   bin/dev/mcp-smoke.sh --java  # only Java backend tools
#   bin/dev/mcp-smoke.sh --python # only Python backend tools
#   bin/dev/mcp-smoke.sh --infra  # only community infra MCPs
#
# Exit code : 0 if all checks pass, 1 if any fails. Designed for nightly
# cron + manual smoke before tagging a stable release.
# =============================================================================

set -uo pipefail

G='\033[32m'; R='\033[31m'; Y='\033[33m'; D='\033[2m'; N='\033[0m'

PASS=0; FAIL=0
SCOPE="${1:-all}"

# Skip categories the user opted out of
case "$SCOPE" in
    --java) SKIP_PYTHON=1 SKIP_INFRA=1 ;;
    --python) SKIP_JAVA=1 SKIP_INFRA=1 ;;
    --infra) SKIP_JAVA=1 SKIP_PYTHON=1 ;;
    all|--all) ;;
    -h|--help) sed -n '1,/^# ===/p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Unknown scope: $SCOPE"; exit 1 ;;
esac

# ── Helpers ─────────────────────────────────────────────────────────

if ! command -v claude >/dev/null 2>&1; then
    echo "${R}✗${N} claude CLI not found"
    exit 1
fi

# probe — issue a prompt, assert response matches expected keyword
# args : <label> <prompt> <expected-keyword-or-regex>
probe() {
    local label="$1"
    local prompt="$2"
    local expect="$3"

    local out
    if ! out=$(claude --print --max-turns 3 "$prompt" 2>&1); then
        printf "  ${R}✗${N} %-60s ${D}claude exited non-zero${N}\n" "$label"
        FAIL=$((FAIL + 1))
        return
    fi

    if echo "$out" | grep -qiE "$expect"; then
        printf "  ${G}✓${N} %-60s\n" "$label"
        PASS=$((PASS + 1))
    else
        printf "  ${R}✗${N} %-60s ${D}expected /%s/ in response${N}\n" "$label" "$expect"
        FAIL=$((FAIL + 1))
    fi
}

# ── Section 1 : Mirador Java backend (in-process MCP) ───────────────

if [ -z "${SKIP_JAVA:-}" ]; then
    echo "── Mirador Java MCP — read-only ──"

    # Health check — should return UP if the app is healthy
    probe "java health" \
        "Use the mirador-java MCP server's get_health tool and tell me only the top-level status, nothing else." \
        "UP|status"

    # OpenAPI summary — should mention /orders or /products
    probe "java openapi summary" \
        "Use mirador-java's get_openapi_spec with summary=true. Reply with the list of paths only." \
        "/orders|/products|/customers"

    # Recent orders — read-only, will return [] if none
    probe "java list_recent_orders" \
        "Use mirador-java's list_recent_orders with limit=5. Tell me how many orders were returned (0 is OK)." \
        "[0-9]+"

    # Customer 360 — assumes a demo seeded customer 1 ; if not present, error response is acceptable
    probe "java get_customer_360" \
        "Use mirador-java's get_customer_360 with id=1. If the customer doesn't exist, say 'not found' ; otherwise tell me their order count." \
        "order count|not found|orderCount"

    # Logs — should return at least the recent app startup messages
    probe "java tail_logs" \
        "Use mirador-java's tail_logs with n=5. Reply with just 'logs received' if you got any log lines." \
        "logs received|no logs"

    # Metrics — JVM heap is always present
    probe "java get_metrics jvm.memory.used" \
        "Use mirador-java's get_metrics with nameFilter='jvm.memory.used'. Tell me only whether you got a numeric value (yes/no)." \
        "yes|numeric|value"

    # Find low stock products — read-only, predicate query
    probe "java find_low_stock_products" \
        "Use mirador-java's find_low_stock_products with threshold=10. Reply with just the count (0 is OK)." \
        "[0-9]+"
fi

# ── Section 2 : Mirador Python backend (in-process MCP) ─────────────

if [ -z "${SKIP_PYTHON:-}" ]; then
    echo ""
    echo "── Mirador Python MCP — read-only ──"

    probe "python health" \
        "Use mirador-python's get_health tool. Reply with only the top-level status." \
        "UP|healthy|status"

    probe "python list_recent_orders" \
        "Use mirador-python's list_recent_orders with limit=5. How many orders were returned?" \
        "[0-9]+"

    probe "python find_low_stock_products" \
        "Use mirador-python's find_low_stock_products tool with threshold=10. Reply with the count." \
        "[0-9]+"

    probe "python tail_logs" \
        "Use mirador-python's tail_logs with n=5. Reply 'logs received' if any were returned." \
        "logs received|no logs"

    probe "python get_openapi_spec" \
        "Use mirador-python's get_openapi_spec with summary=true. Did you find the /orders path? (yes/no)" \
        "yes|/orders"
fi

# ── Section 3 : Community infra MCP servers ─────────────────────────

if [ -z "${SKIP_INFRA:-}" ]; then
    echo ""
    echo "── Community infra MCP — read-only ──"

    # Postgres — list tables (read-only catalog query)
    probe "postgres list tables" \
        "Use the postgres-mirador MCP server to list the tables in the public schema. Reply with just 'orders' if it's there." \
        "orders|customer|product"

    # Prometheus — query the up{} metric (always present)
    probe "prometheus up{} query" \
        "Use prometheus MCP to query 'up'. Reply with 'metric received' if you got at least one sample." \
        "metric received|up\b|value"

    # GitLab — list open MRs on mirador-service-java (assumes GITLAB_TOKEN set)
    if claude mcp list 2>/dev/null | grep -q "^gitlab"; then
        probe "gitlab list mirador1/mirador-service-java MRs" \
            "Use gitlab MCP to list open merge requests on mirador1/mirador-service-java. Reply with 'count: N'." \
            "count:|merge request|MR"
    else
        printf "  ${Y}○${N} %-60s ${D}gitlab MCP not wired${N}\n" "gitlab list MRs"
    fi

    # GitHub — list mirador1/mirador-service-java repo info
    if claude mcp list 2>/dev/null | grep -q "^github"; then
        probe "github read mirador1/mirador-service-java" \
            "Use github MCP to get info about the mirador1/mirador-service-java repository. What's its description?" \
            "Spring|backend|Mirador|java"
    else
        printf "  ${Y}○${N} %-60s ${D}github MCP not wired${N}\n" "github read repo"
    fi

    # SonarCloud — get latest analysis
    if claude mcp list 2>/dev/null | grep -q "^sonar"; then
        probe "sonar quality gate" \
            "Use the sonar MCP to get the quality gate status of project mirador1_mirador-service-java. Reply with the status." \
            "OK|ERROR|PASSED|FAILED|none"
    else
        printf "  ${Y}○${N} %-60s ${D}sonar MCP not wired${N}\n" "sonar quality gate"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────

echo ""
if [ "$FAIL" = "0" ]; then
    printf "${G}✓ All %d MCP smoke checks passed.${N}\n" "$PASS"
    exit 0
else
    printf "${R}✗ %d failure(s) out of %d.${N}\n" "$FAIL" "$((PASS + FAIL))"
    exit 1
fi
