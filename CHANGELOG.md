# Changelog

All notable changes to **iris-common** — universal cross-repo
conventions for the [iris-7](https://gitlab.com/iris-7) family.

This is a leaf submodule (zero dependencies) consumed by every repo.
Format : a lightly-formatted summary per `common-vX.Y.Z` tag (when we
start tagging — currently rolling on `main` only since consumers pin
SHAs, not tags).

## 2026-05-09 → 2026-05-14 — auto-merge, double-CI, schedules, hygiene

### ✨ Features

- `ci-templates/auto-merge-dev-to-main.yml` — GitLab CI template that
  auto-promotes `dev` → `main` once the dev pipeline goes green.
  Requires `AUTOMERGE_TOKEN` group variable + `promote` stage in
  consumer (see ADR-0066).
- `ci-templates/adr-drift.yml` — fail when `docs/adr/` has new ADRs
  the README hasn't been re-regenerated against.
- `ci-templates/shellcheck.yml` — `koalaman/shellcheck-alpine` on
  `bin/**/*.sh`, gates on `error` by default. Subject limit bumped
  72 → 100 chars (`fix(deps): bump gitpython 3.1.47→3.1.50, mako
  1.3.11→1.3.12, python-multipart 0.0.26→0.0.27` legitimately
  exceeds the GitLab default).
- `bin/ship/github-mirror-sync.sh` — one-command sync of all 5
  github mirrors. `--check` for drift detection, `--repo <name>`
  for one. Uses `--force-with-lease` so divergent github commits
  surface a push failure instead of being silently overwritten.

### 🐛 Fixes

- `ci-templates/auto-merge-dev-to-main.yml` — prefix `+` on the
  `git fetch` line so a stale runner-workspace `origin/main` ref
  doesn't reject the fetch as `non-fast-forward`. Force-update
  matches the `force-with-lease` push semantics one line below.
- `ci-templates/shellcheck.yml` — switch to `--format=gcc` to
  bypass the v0.10.0 encoding bug on multi-byte UTF-8 (em-dashes,
  smart quotes). Discovered 2026-05-09 on a `bin/run/_preamble.sh`
  comment with an em-dash.
- `ci-templates/conventional-commits.yml` — skip merge commits
  (parent count > 1) ; GitLab's auto-generated merge subjects
  aren't conventional and shouldn't fail the gate.

### 📚 Documentation

- 6 new ADRs accepted :
  - [0066](docs/adr/0066-auto-merge-dev-to-main-template.md) — Auto-merge dev → main CI template
  - [0067](docs/adr/0067-kafka-redpanda-switch-for-ci.md) — Kafka → redpanda for CI services
  - [0068](docs/adr/0068-route-services-ci-to-saas.md) — Python integration-tests routes to SaaS Linux runner
  - [0069](docs/adr/0069-double-ci-gitlab-github-actions.md) — Double-CI : GitLab reference + GitHub Actions backup
  - [0070](docs/adr/0070-workflow-rules-dev-branch-pattern.md) — workflow:rules dev/main allowlist superset of MR allowlist
  - [0071](docs/adr/0071-pipeline-variable-override-role.md) — Pipeline variable override role : `owner` across all 5 repos
- 2 session audit docs :
  - [session-2026-05-09-to-12-summary](docs/audit/session-2026-05-09-to-12-summary.md) — 4-day consolidation
  - [session-2026-05-13-to-14-followup](docs/audit/session-2026-05-13-to-14-followup.md) — 2-day follow-up

### Patterns reinforced

- **dev branch on all 5 repos** : iris-common + iris-service-shared
  now also follow dev → main (previously rolled directly on main).
- **gitlink path in `workflow:rules`** : `infra/common` (without
  glob) needed to catch SHA-only changes — `infra/common/**/*`
  (with glob) only catches changes inside the submodule, not bumps.
- **Force-with-lease for auto-merge** : protects against unrelated
  work on main being overwritten.
- **`ci_pipeline_variables_minimum_override_role`** : aligned to
  `owner` across all 5 repos (was a 3-way drift across
  `no_one_allowed` / `developer`).

## 2026-04-26 — Initial extraction from `iris-service-shared`

### ✨ Features

- `bin/ship/pre-sync.sh` — git-safety pre-flight before `git reset --hard`
- `bin/ship/changelog.sh` — Conventional-Commits → CHANGELOG (with `--tag-prefix`)
- `bin/ship/gitlab-release.sh` — create GitLab Release object from a tag
- `bin/ship/renovate-sync.sh` — sync `renovate.json` across consumers
- `bin/ship/check-default-branch.sh` — verify `default_branch=main` on all repos
- `bin/dev/regen-adr-index.sh` — regenerate ADR flat-index, `--check` for drift
- `ci-templates/conventional-commits.yml` — Conventional Commits enforcement template
- `renovate-base.json` — common Renovate config (synced into each repo)

### 📚 Documentation

- 4 cross-cutting ADRs migrated from `iris-service-shared` :
  - 0001 — Shared repo via submodule (the pattern this repo embodies)
  - 0055 — Shell-based release automation (no semantic-release)
  - 0057 — Polyrepo vs monorepo (kept polyrepo)
  - 0059 — Renovate base preset (option B : sync script over rendered preset)

### Why extract

`iris-service-shared` was originally a single shared submodule for
the backend (Java + Python). When UI started needing the same release
scripts + Conventional-Commits CI template, putting them in
`iris-service-shared` would force UI to pull 90% irrelevant content
(terraform, K8s, OTel, postgres). Splitting into two submodules :

- `iris-common` (this repo) = universal, leaf, consumed by 4 repos
- `iris-service-shared` = backend infra, consumed by java + python (NOT ui)

UI gets only what it needs. Backend repos get both.
