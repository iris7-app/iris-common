#!/usr/bin/env bash
# =============================================================================
# bin/ship/bump-common-everywhere.sh — bump infra/common SHA across all
# mirador1 consumer repos in one pass.
#
# Why : pattern α flat (cf. ADR-0060) implies each consumer pin its own
# common SHA independently. When we patch common (fix critique, nouvelle
# option d'un script universel), it's painful to manually run :
#   cd <repo> && cd infra/common && git pull && cd .. && git add infra/common
#   && git commit && git push && glab mr create && glab mr merge --auto-merge
# in 4 different repos. This script automates that 4-repo loop.
#
# Usage :
#   bin/ship/bump-common-everywhere.sh [OPTIONS]
#
# Options :
#   --dry-run         Print what would happen without bumping or pushing.
#   --no-mr           Bump locally + push dev, but skip MR creation
#                     (you create + merge manually). Default = create MR.
#   --auto-merge      Arm auto-merge on the created MR (default = yes when --no-mr is absent).
#   --no-auto-merge   Skip the auto-merge step (just create MR, leave it open).
#   --consumers REPO1,REPO2,...  Override the consumer list. Default = all 4.
#   --workspace DIR   Override the workspace root. Default = ~/dev/mirador.
#   --help            Show this help.
#
# Exit codes :
#   0  All consumers bumped successfully.
#   1  Pre-flight failed (common not in sync, dirty workspace, etc.).
#   2  One or more consumers failed during bump (others may have succeeded ;
#      a recap table is printed).
#
# Pre-flight checks (ALL must pass before any bump) :
#   1. mirador-common's main is at-or-ahead-of origin/main (no unpushed commits)
#   2. Each consumer exists at <workspace>/<consumer-name>
#   3. Each consumer has a clean working tree (no uncommitted)
#   4. Each consumer's `dev` branch is at-or-behind origin/main (no unpushed
#      dev commits that would be lost in a force-merge)
#
# When you DON'T want to use this :
#   - Small fix that only matters to one consumer (let α isolation play its role)
#   - Refactor that changes a script's API (consumers must adapt their usage
#     before bumping — a cascade would break them)
# =============================================================================

set -uo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
G='\033[32m'; R='\033[31m'; Y='\033[33m'; B='\033[34m'; BOLD='\033[1m'; DIM='\033[2m'; N='\033[0m'

ok()    { printf "  ${G}✓${N} %s\n" "$1"; }
fail()  { printf "  ${R}✗${N} %s\n" "$1"; }
warn()  { printf "  ${Y}!${N} %s\n" "$1"; }
info()  { printf "  ${B}ℹ${N} %s\n" "$1"; }

# ── Defaults ─────────────────────────────────────────────────────────────────
DRY_RUN=0
CREATE_MR=1
AUTO_MERGE=1
WORKSPACE="${HOME}/dev/mirador"
CONSUMERS_DEFAULT="mirador-service-shared,mirador-service-java,mirador-service-python,mirador-ui"
CONSUMERS="${CONSUMERS_DEFAULT}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)          DRY_RUN=1 ; shift ;;
        --no-mr)            CREATE_MR=0 ; AUTO_MERGE=0 ; shift ;;
        --auto-merge)       AUTO_MERGE=1 ; shift ;;
        --no-auto-merge)    AUTO_MERGE=0 ; shift ;;
        --consumers)        CONSUMERS="$2" ; shift 2 ;;
        --consumers=*)      CONSUMERS="${1#--consumers=}" ; shift ;;
        --workspace)        WORKSPACE="$2" ; shift 2 ;;
        --workspace=*)      WORKSPACE="${1#--workspace=}" ; shift ;;
        --help|-h)
            sed -n '2,55p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown arg: $1 (use --help)" >&2
            exit 2
            ;;
    esac
done

# ── Locate common ────────────────────────────────────────────────────────────
COMMON_DIR="${WORKSPACE}/mirador-common"
if [ ! -d "${COMMON_DIR}/.git" ]; then
    echo "ERROR: mirador-common not found at ${COMMON_DIR}" >&2
    echo "Pass --workspace <dir> if your repos live elsewhere." >&2
    exit 1
fi

printf "${BOLD}bump-common-everywhere — %s${N}\n" "$(date +'%H:%M:%S')"
printf "${DIM}workspace: %s${N}\n" "${WORKSPACE}"
printf "${DIM}consumers: %s${N}\n" "${CONSUMERS}"
printf "${DIM}dry-run:   %s    create-mr: %s    auto-merge: %s${N}\n" \
    "$([ "$DRY_RUN" = "1" ] && echo "ON" || echo "OFF")" \
    "$([ "$CREATE_MR" = "1" ] && echo "ON" || echo "OFF")" \
    "$([ "$AUTO_MERGE" = "1" ] && echo "ON" || echo "OFF")"
echo

# ── Pre-flight 1 : common is in-sync with its remote ─────────────────────────
echo "── Pre-flight 1 : common sync state ──"
cd "${COMMON_DIR}"
git fetch origin main --quiet 2>/dev/null || true
COMMON_LOCAL=$(git rev-parse HEAD)
COMMON_REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
COMMON_SHORT=$(git rev-parse --short HEAD)

if [ "${COMMON_LOCAL}" != "${COMMON_REMOTE}" ]; then
    AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
    BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
    if [ "${AHEAD}" -gt 0 ]; then
        fail "common HEAD (${COMMON_SHORT}) has ${AHEAD} unpushed commits — push first then re-run"
        exit 1
    fi
    if [ "${BEHIND}" -gt 0 ]; then
        warn "common HEAD is behind origin/main by ${BEHIND} commits — pulling"
        if [ "${DRY_RUN}" = "0" ]; then
            git pull --rebase origin main --quiet
            COMMON_LOCAL=$(git rev-parse HEAD)
            COMMON_SHORT=$(git rev-parse --short HEAD)
        fi
    fi
fi
ok "common is at ${COMMON_SHORT} (in sync with origin/main)"
echo

# ── Pre-flight 2-4 : per-consumer checks ─────────────────────────────────────
echo "── Pre-flight 2-4 : per-consumer state ──"
PREFLIGHT_FAILED=0
declare -a CONSUMERS_OK=()
declare -a CONSUMERS_SKIP=()

# Note : associative arrays don't work well in older bash (3.x is default on macOS).
# Use parallel arrays + linear search instead.

IFS=',' read -ra CONSUMER_LIST <<< "${CONSUMERS}"
for consumer in "${CONSUMER_LIST[@]}"; do
    cdir="${WORKSPACE}/${consumer}"
    if [ ! -d "${cdir}/.git" ]; then
        warn "${consumer} : not at ${cdir} — SKIP"
        CONSUMERS_SKIP+=("${consumer}")
        continue
    fi
    cd "${cdir}"

    # Has the consumer got infra/common at all ?
    if [ ! -d "infra/common/.git" ] && [ ! -f "infra/common/.git" ]; then
        warn "${consumer} : no infra/common/ submodule — SKIP"
        CONSUMERS_SKIP+=("${consumer}")
        continue
    fi

    # Working tree clean ?
    if [ -n "$(git status --porcelain | grep -v '^??')" ]; then
        fail "${consumer} : uncommitted changes — fix first"
        PREFLIGHT_FAILED=1
        continue
    fi

    # Submodule clean ?
    if [ -n "$(cd infra/common && git status --porcelain)" ]; then
        fail "${consumer} : infra/common has uncommitted changes — fix first"
        PREFLIGHT_FAILED=1
        continue
    fi

    # Already at the new SHA ?
    CURRENT_SHA=$(cd infra/common && git rev-parse HEAD)
    if [ "${CURRENT_SHA}" = "${COMMON_LOCAL}" ]; then
        info "${consumer} : already at common ${COMMON_SHORT} — nothing to do"
        CONSUMERS_SKIP+=("${consumer}")
        continue
    fi

    OLD_SHORT=$(cd infra/common && git rev-parse --short HEAD)
    ok "${consumer} : will bump common ${OLD_SHORT} → ${COMMON_SHORT}"
    CONSUMERS_OK+=("${consumer}")
done

if [ "${PREFLIGHT_FAILED}" = "1" ]; then
    echo
    fail "Pre-flight failed for one or more consumers. Fix and re-run."
    exit 1
fi

if [ "${#CONSUMERS_OK[@]}" = "0" ]; then
    echo
    ok "Nothing to do — all consumers already at common ${COMMON_SHORT}"
    exit 0
fi

if [ "${DRY_RUN}" = "1" ]; then
    echo
    info "DRY RUN — no changes will be made. Re-run without --dry-run to apply."
    exit 0
fi

# ── Bump phase ───────────────────────────────────────────────────────────────
echo
echo "── Bumping ${#CONSUMERS_OK[@]} consumer(s) ──"
declare -a BUMPED=()
declare -a FAILED=()
declare -a MR_URLS=()

for consumer in "${CONSUMERS_OK[@]}"; do
    echo
    printf "${BOLD}▸ ${consumer}${N}\n"
    cdir="${WORKSPACE}/${consumer}"
    cd "${cdir}"

    # Step 1 : sync local main + dev with origin
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    git fetch origin --quiet 2>/dev/null || { fail "fetch failed"; FAILED+=("${consumer}"); continue; }

    # If consumer has a dev branch, use it ; else commit directly on main
    HAS_DEV=$(git ls-remote --heads origin dev | wc -l | tr -d ' ')
    if [ "${HAS_DEV}" = "1" ]; then
        TARGET_BRANCH="dev"
    else
        TARGET_BRANCH="${DEFAULT_BRANCH}"
    fi
    info "target branch : ${TARGET_BRANCH}"

    git switch "${TARGET_BRANCH}" --quiet 2>/dev/null || git switch -c "${TARGET_BRANCH}" "origin/${TARGET_BRANCH}" --quiet || {
        fail "could not switch to ${TARGET_BRANCH}"
        FAILED+=("${consumer}"); continue
    }
    git pull --rebase origin "${TARGET_BRANCH}" --quiet 2>/dev/null || true

    # Step 2 : bump submodule
    cd infra/common
    git fetch origin main --quiet
    git checkout "${COMMON_LOCAL}" --quiet
    cd "${cdir}"
    git add infra/common

    # Step 3 : commit
    if ! git commit -m "chore(submodule): bump common SHA → ${COMMON_SHORT}" --quiet; then
        fail "commit failed (no diff?)"
        FAILED+=("${consumer}"); continue
    fi
    ok "committed bump"

    # Step 4 : push
    if ! git push origin "${TARGET_BRANCH}" --quiet 2>&1 | grep -v "^remote:"; then
        # push may print remote:... lines, those are normal. Only fail on non-zero exit.
        if [ "${PIPESTATUS[0]}" != "0" ]; then
            fail "push failed"
            FAILED+=("${consumer}"); continue
        fi
    fi
    ok "pushed to origin/${TARGET_BRANCH}"

    BUMPED+=("${consumer}")

    # Step 5 : MR (optional)
    if [ "${CREATE_MR}" = "1" ] && [ "${TARGET_BRANCH}" = "dev" ]; then
        if ! command -v glab >/dev/null 2>&1; then
            warn "glab not installed — skipping MR creation"
            continue
        fi
        MR_URL=$(glab mr create \
            --title "chore(submodule): bump common SHA → ${COMMON_SHORT}" \
            --description "Auto-bump from \`bump-common-everywhere.sh\`. Common SHA → [\`${COMMON_SHORT}\`](https://gitlab.com/mirador1/mirador-common/-/commit/${COMMON_LOCAL})." \
            --target-branch "${DEFAULT_BRANCH}" \
            --remove-source-branch=false 2>&1 | grep -oE 'https://gitlab.com/[^ ]+' | head -1)
        if [ -n "${MR_URL}" ]; then
            ok "MR created : ${MR_URL}"
            MR_URLS+=("${consumer}::${MR_URL}")

            if [ "${AUTO_MERGE}" = "1" ]; then
                MR_ID=$(echo "${MR_URL}" | grep -oE '/[0-9]+$' | tr -d '/')
                # Use API directly to set merge_when_pipeline_succeeds (more reliable than glab mr merge --auto-merge)
                if [ -n "${GITLAB_TOKEN:-}" ]; then
                    TOKEN="${GITLAB_TOKEN}"
                else
                    TOKEN=$(grep "^[[:space:]]*token:" "${HOME}/Library/Application Support/glab-cli/config.yml" 2>/dev/null | awk '{print $2}')
                fi
                if [ -n "${TOKEN}" ] && [ -n "${MR_ID}" ]; then
                    PROJECT_PATH="mirador1%2F${consumer}"
                    HTTP_CODE=$(curl -s -X PUT -H "PRIVATE-TOKEN: ${TOKEN}" \
                        "https://gitlab.com/api/v4/projects/${PROJECT_PATH}/merge_requests/${MR_ID}/merge?merge_when_pipeline_succeeds=true&should_remove_source_branch=false" \
                        -o /dev/null -w "%{http_code}")
                    if [ "${HTTP_CODE}" = "200" ]; then
                        ok "auto-merge armed (HTTP ${HTTP_CODE})"
                    else
                        warn "auto-merge arming returned HTTP ${HTTP_CODE} — check MR manually"
                    fi
                else
                    warn "missing token or MR id — auto-merge skipped"
                fi
            fi
        else
            warn "MR creation failed (already exists?)"
        fi
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo
printf "${BOLD}── Summary ──${N}\n"
printf "Bumped to common ${COMMON_SHORT} : ${G}%d${N}\n" "${#BUMPED[@]}"
for c in "${BUMPED[@]}"; do printf "  ${G}✓${N} %s\n" "$c"; done
if [ "${#CONSUMERS_SKIP[@]}" -gt 0 ]; then
    printf "Skipped : ${Y}%d${N}\n" "${#CONSUMERS_SKIP[@]}"
    for c in "${CONSUMERS_SKIP[@]}"; do printf "  ${Y}○${N} %s (already at SHA, missing repo, or no submodule)\n" "$c"; done
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
    printf "Failed : ${R}%d${N}\n" "${#FAILED[@]}"
    for c in "${FAILED[@]}"; do printf "  ${R}✗${N} %s\n" "$c"; done
fi
if [ "${#MR_URLS[@]}" -gt 0 ]; then
    echo
    printf "${BOLD}MRs created :${N}\n"
    for entry in "${MR_URLS[@]}"; do
        printf "  %s\n" "${entry/::/ → }"
    done
fi
echo

if [ "${#FAILED[@]}" -gt 0 ]; then
    exit 2
fi
exit 0
