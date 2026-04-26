# Changelog

All notable changes to **mirador-common** — universal cross-repo
conventions for the [mirador1](https://gitlab.com/mirador1) family.

This is a leaf submodule (zero dependencies) consumed by every repo.
Format : a lightly-formatted summary per `common-vX.Y.Z` tag (when we
start tagging — currently rolling on `main` only since consumers pin
SHAs, not tags).

## 2026-04-26 — Initial extraction from `mirador-service-shared`

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

- 4 cross-cutting ADRs migrated from `mirador-service-shared` :
  - 0001 — Shared repo via submodule (the pattern this repo embodies)
  - 0055 — Shell-based release automation (no semantic-release)
  - 0057 — Polyrepo vs monorepo (kept polyrepo)
  - 0059 — Renovate base preset (option B : sync script over rendered preset)

### Why extract

`mirador-service-shared` was originally a single shared submodule for
the backend (Java + Python). When UI started needing the same release
scripts + Conventional-Commits CI template, putting them in
`mirador-service-shared` would force UI to pull 90% irrelevant content
(terraform, K8s, OTel, postgres). Splitting into two submodules :

- `mirador-common` (this repo) = universal, leaf, consumed by 4 repos
- `mirador-service-shared` = backend infra, consumed by java + python (NOT ui)

UI gets only what it needs. Backend repos get both.
