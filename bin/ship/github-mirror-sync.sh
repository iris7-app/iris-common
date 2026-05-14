#!/usr/bin/env bash
# github-mirror-sync.sh — push each iris-7 repo's GitLab main HEAD
# to its GitHub mirror.
#
# Why this exists : the iris-7 polyrepo uses GitLab as the reference
# CI + source of truth, and GitHub as a read-only mirror (per ADR-0069
# double-CI). The mirror drifts whenever :
#   - A force-push lands on GitLab main during bootstrap (auto-merge
#     template fix 2026-05-14 was one such case).
#   - The auto-mirror SSH push hook in iris-common's release scripts
#     fails silently (e.g. token expired, branch protection tightened
#     on github main).
#   - A manual `git push origin dev:main` is done (skips the hook).
#
# Discovered 2026-05-14 : 3 of 5 repos had drift after a normal session
# (iris-common, iris-service-shared, iris-ui — all gaps of 1-5 commits).
# Fix : a single command that fetches origin/main + force-pushes to
# github main on every repo, with --force-with-lease so divergent
# remotes are caught rather than overwritten silently.
#
# Run :
#   bin/ship/github-mirror-sync.sh                 # all 5 repos
#   bin/ship/github-mirror-sync.sh --check         # dry-run, exit 1 if drift
#   bin/ship/github-mirror-sync.sh --repo java     # one repo only
#
# Exit codes :
#   0 — all mirrors in sync (or successfully synced)
#   1 — drift detected in --check mode (no push attempted)
#   2 — missing tool / unconfigured remote / push failure
#
# Cadence suggestion : add to bin/dev/stability-check.sh preflight, so
# every stability checkpoint catches new drift before tagging.

set -euo pipefail

# ── Repos ────────────────────────────────────────────────────────────────────
# Path lookup : ${IRIS_ROOT:-$HOME/dev/iris}/<repo>
REPOS=(
    "iris-common"
    "iris-service-shared"
    "iris-service-java"
    "iris-service-python"
    "iris-ui"
)
IRIS_ROOT="${IRIS_ROOT:-$HOME/dev/iris}"

# ── Args ─────────────────────────────────────────────────────────────────────
mode="push"
filter=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) mode="check" ;;
        --repo)  shift; filter="$1" ;;
        -h|--help)
            head -33 "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown arg : $1" ; exit 2 ;;
    esac
    shift
done

# ── Tool check ───────────────────────────────────────────────────────────────
if ! command -v git >/dev/null 2>&1; then
    echo "❌ git not found"
    exit 2
fi

# ── Sync loop ────────────────────────────────────────────────────────────────
drift_count=0
synced_count=0
skipped_count=0

for repo in "${REPOS[@]}"; do
    if [ -n "$filter" ] && [ "$repo" != "$filter" ] && [ "$repo" != "iris-$filter" ] \
       && [ "$repo" != "iris-service-$filter" ]; then
        continue
    fi
    path="$IRIS_ROOT/$repo"
    if [ ! -d "$path/.git" ]; then
        printf "  ⏭  %-25s no clone at %s\n" "$repo" "$path"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    # Verify github remote exists.
    if ! git -C "$path" remote get-url github >/dev/null 2>&1; then
        printf "  ⏭  %-25s no 'github' remote configured\n" "$repo"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    # Fetch both sides (quiet — only output on drift).
    git -C "$path" fetch origin --quiet 2>/dev/null || true
    git -C "$path" fetch github --quiet 2>/dev/null || true

    gitlab_sha=$(git -C "$path" rev-parse origin/main 2>/dev/null | cut -c1-12)
    github_sha=$(git -C "$path" rev-parse github/main 2>/dev/null | cut -c1-12)

    if [ -z "$gitlab_sha" ] || [ -z "$github_sha" ]; then
        printf "  ⚠️  %-25s failed to fetch one of the remotes\n" "$repo"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    if [ "$gitlab_sha" = "$github_sha" ]; then
        printf "  ✓ %-25s in sync (%s)\n" "$repo" "$gitlab_sha"
        synced_count=$((synced_count + 1))
        continue
    fi

    drift_count=$((drift_count + 1))
    if [ "$mode" = "check" ]; then
        printf "  ⚠️  %-25s DRIFT gitlab=%s github=%s\n" "$repo" "$gitlab_sha" "$github_sha"
        continue
    fi

    # Push mode : force-with-lease so divergent github commits don't get
    # silently overwritten — if github has commits gitlab doesn't, the push
    # fails and a human investigates.
    printf "  ▶ %-25s syncing %s → %s\n" "$repo" "$github_sha" "$gitlab_sha"
    if ! git -C "$path" push github "origin/main:refs/heads/main" --force-with-lease 2>/dev/null; then
        printf "  ❌ %-25s push failed — investigate manually\n" "$repo"
        exit 2
    fi
    printf "  ✓ %-25s synced\n" "$repo"
done

echo ""
if [ "$mode" = "check" ]; then
    echo "Summary : $synced_count in sync, $drift_count drifted, $skipped_count skipped"
    [ $drift_count -gt 0 ] && exit 1 || exit 0
else
    echo "Summary : $((synced_count + drift_count)) synced (incl. $drift_count fresh), $skipped_count skipped"
fi
