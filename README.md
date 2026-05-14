![iris-common](docs/assets/banner.svg)

[![BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)
![Leaf submodule](https://img.shields.io/badge/Leaf-zero_deps-green)

Universal **cross-repo conventions** for the [iris-7](https://gitlab.com/iris-7)
project family — release engineering scripts, ADR tooling, Conventional
Commits CI template, auto-merge dev→main template, Renovate base preset.

Part of **Iris**, an observability-first showcase across 7 facets.
See [iris-service-java](https://gitlab.com/iris-7/iris-service-java)
for the master narrative + visual.

## Why this repo

Some scripts and configs are **truly universal** : they don't care whether
the consuming project is Java + Spring Boot, Python + FastAPI, or
Angular zoneless. Examples : a `git reset --hard` safety check
(`bin/ship/pre-sync.sh`), an ADR-index regenerator
(`bin/dev/regen-adr-index.sh`), a Conventional-Commits CI template,
the Renovate base config.

Putting these in `iris-service-shared` (the backend infra repo)
forces UI to pull in 90% irrelevant content (terraform, K8s, OTel
collector, postgres) just to use 2 small scripts. Putting them in
each consumer repo creates 3-4 copies that drift.

**Solution** : a leaf submodule consumed by every repo (java, python,
ui, AND shared-service itself).

## What lives here

| Path | Purpose | Used by |
|---|---|---|
| `bin/ship/pre-sync.sh` | Git-safety pre-flight before `git reset --hard` | every repo |
| `bin/ship/changelog.sh` | Generate CHANGELOG entry from Conventional Commits (`--tag-prefix` flag for per-repo tag namespaces) | every repo |
| `bin/ship/gitlab-release.sh` | Create GitLab Release object from a tag | every repo |
| `bin/ship/renovate-sync.sh` | Sync `renovate.json` across consumers from `renovate-base.json` | maintainer (run from any repo) |
| `bin/ship/check-default-branch.sh` | Verify all 4 iris-7 projects have `default_branch=main` | maintainer / pre-tag |
| `bin/ship/bump-common-everywhere.sh` | Bump `infra/common` SHA across all 4 consumers in one pass (commit + push + MR + auto-merge) | maintainer (run from `iris-common`) |
| `bin/ship/github-mirror-sync.sh` | Push every repo's GitLab `main` HEAD to its GitHub mirror (`--check` for drift detection, `--repo <name>` for one) | maintainer / session-start hygiene |
| `bin/dev/regen-adr-index.sh` | Regenerate `docs/adr/README.md` flat-index table from ADR files (`--check` for CI drift) | every repo (per-repo ADRs) |
| `ci-templates/conventional-commits.yml` | GitLab CI template enforcing Conventional Commits on every MR | every repo (`include:` from `.gitlab-ci.yml`) |
| `ci-templates/shellcheck.yml` | GitLab CI template running `koalaman/shellcheck-alpine` on `bin/**/*.sh` ; gates on `error` by default (override with `SHELLCHECK_SEVERITY=warning` once a repo's warning backlog is clean) | every repo with shell scripts |
| `ci-templates/adr-drift.yml` | GitLab CI template invoking `infra/common/bin/dev/regen-adr-index.sh --check` to fail when `docs/adr/` has new ADRs the index hasn't been re-regenerated against | every repo with `docs/adr/` |
| `ci-templates/auto-merge-dev-to-main.yml` | GitLab CI template that auto-promotes `dev` → `main` once the dev pipeline goes green ; requires `AUTOMERGE_TOKEN` group variable + `promote` stage in consumer | every repo (`include:` from `.gitlab-ci.yml`) |
| `renovate-base.json` | Common Renovate config, synced into each repo's `renovate.json` via `bin/ship/renovate-sync.sh` | every repo |

See [`docs/adr/`](docs/adr/) for the full ADR set covering submodule pattern (ADR-0001), polyrepo decision (ADR-0057), per-repo tag namespaces (ADR-0061), auto-merge template (ADR-0066), kafka→redpanda CI switch (ADR-0067), double-CI GitLab+GitHub (ADR-0069), workflow:rules dev/main allowlist (ADR-0070), pipeline variable override role (ADR-0071), and 12 others.

## What does NOT live here

Backend-specific infrastructure (clusters, terraform, K8s manifests,
OTel collector, postgres+kafka+redis compose stack, observability
dashboards) lives in **`iris-service-shared`**. It is consumed
by the backend repos (java + python) but NOT by ui — UI doesn't run
backends, doesn't deploy K8s clusters, doesn't manage cloud cost.

The split (this repo = universal ; iris-service-shared = backend)
formalises the boundary so each consumer pulls only what it needs.

## How consumers use this

```bash
# In iris-service-java, iris-service-python, iris-ui, iris-service-shared :
git submodule add https://gitlab.com/iris-7/iris-common.git infra/common
git commit -m "chore(submodule): add iris-common"

# Then call scripts via :
infra/common/bin/ship/pre-sync.sh
infra/common/bin/ship/changelog.sh --tag-prefix stable-v   # Java/UI default
infra/common/bin/ship/changelog.sh --tag-prefix stable-py-v # Python
infra/common/bin/dev/regen-adr-index.sh --check
```

## How to update

```bash
# In iris-common :
$ cd ~/dev/iris/iris-common
$ git switch main
# … edit, commit, push …
$ git push origin main

# In any consumer repo (manual single-bump) :
$ cd <consumer>/infra/common
$ git pull origin main
$ cd ../..
$ git add infra/common
$ git commit -m "chore(common): bump SHA — <reason>"
$ git push
```

**Bulk bump across all 4 consumers in one command** (faster, safer —
runs pre-flight checks first, then commits + pushes + creates MR with
auto-merge per consumer) :

```bash
$ cd ~/dev/iris/iris-common
$ bin/ship/bump-common-everywhere.sh           # creates MRs + auto-merge
$ bin/ship/bump-common-everywhere.sh --dry-run # preview without changes
```

The consumer repo's CI re-runs against the new common SHA. Tag the
consumer's own `stable-<prefix>-vX.Y.Z` when a milestone lands.

## Adding to a new consumer repo

```bash
git submodule add https://gitlab.com/iris-7/iris-common.git infra/common
git submodule update --init infra/common
```

Then add to `.gitlab-ci.yml` (typical iris-7 consumer set) :

```yaml
include:
  - project: 'iris-7/iris-common'
    ref: main
    file: 'ci-templates/conventional-commits.yml'
  - project: 'iris-7/iris-common'
    ref: main
    file: 'ci-templates/shellcheck.yml'         # if the repo has bin/**/*.sh
  - project: 'iris-7/iris-common'
    ref: main
    file: 'ci-templates/adr-drift.yml'          # if the repo has docs/adr/
  - project: 'iris-7/iris-common'
    ref: main
    file: 'ci-templates/auto-merge-dev-to-main.yml'

stages:
  - validate
  - test
  - promote   # required by the auto-merge template
```

Also requires a group-level CI variable `AUTOMERGE_TOKEN` (Personal Access
Token, scope `write_repository`) for the auto-merge template — see
[ADR-0066](docs/adr/0066-auto-merge-dev-to-main-template.md).

(Or vendor the template files directly if you prefer pin-by-SHA over
`ref: main`.)

## See also

- [CHANGELOG](CHANGELOG.md) — release notes
- [ADR index](docs/adr/README.md) — all architecture decisions, in one table
- [ADR-0001 — Shared repo via submodule](docs/adr/0001-shared-repo-via-submodule.md) — the foundation
- [ADR-0057 — Polyrepo vs monorepo](docs/adr/0057-polyrepo-vs-monorepo.md) — why 5 repos and not 1
- [ADR-0060 — Flat α vs transitive β submodule inheritance](docs/adr/0060-flat-vs-transitive-submodule-inheritance.md) — why each consumer pins independently
- [ADR-0066 — Auto-merge dev → main CI template](docs/adr/0066-auto-merge-dev-to-main-template.md)
- [ADR-0069 — Double-CI : GitLab as reference + GitHub Actions as backup](docs/adr/0069-double-ci-gitlab-github-actions.md)
- [`iris-service-shared`](https://gitlab.com/iris-7/iris-service-shared) — backend infra (clusters, terraform, K8s, observability)
- Sibling repos : [java](https://gitlab.com/iris-7/iris-service-java) · [python](https://gitlab.com/iris-7/iris-service-python) · [ui](https://gitlab.com/iris-7/iris-ui)

## License

[BSD-3-Clause](LICENSE)
