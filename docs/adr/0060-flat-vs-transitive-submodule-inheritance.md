# ADR-0060 — Flat 2-submodule inheritance over transitive nested

**Status** : Accepted
**Date** : 2026-04-26
**Related repos** : `iris-service-java`, `iris-service-python`, `iris-ui`, `iris-service-shared`, `iris-common`

## Context

When [`iris-common`](https://gitlab.com/iris-7/iris-common) was extracted from
[`iris-service-shared`](https://gitlab.com/iris-7/iris-service-shared) on
2026-04-26 (per the rationale captured in the [shared-repo ADR-0001](0001-shared-repo-via-submodule.md)),
the family ended up needing **two shared layers** :

- `iris-common` — universal cross-repo conventions (release scripts,
  ADR tooling, Conventional Commits CI template, Renovate base) ;
  applies to all 4 repos including UI.
- `iris-service-shared` — backend infrastructure (clusters,
  terraform, K8s manifests, OTel collector, postgres + kafka + redis
  compose stack, observability dashboards) ; applies only to
  `iris-service-java` + `iris-service-python`.

The question : **how do backend repos (java + python) attach common ?**
Two architectures were on the table :

| | α (flat) | β (transitive nested) |
|---|---|---|
| Backend submodules count | 2 (`infra/shared/` + `infra/common/`) | 1 (`infra/shared/`, with common nested inside) |
| Backend SHA pinning | independent : java pins common@SHA-X AND shared@SHA-Y separately | dependent : java pins shared@SHA-Y, gets common@whatever-shared-pinned |
| Per-repo divergence on common SHA | possible (java=v3, python=v2) | impossible (forced alignment via shared) |
| Clone command | `git submodule update --init` (1-level) | `git submodule update --init --recursive` (2-level) |
| Path inside backend | `infra/common/bin/...` (clean, symmetric across all 4 repos) | `infra/shared/common/bin/...` (different from UI's `infra/common/bin/...`) |
| Bump propagation latency for a common patch | 1 step per consumer, parallel | 2 steps : push common, bump common in shared, push shared, bump shared in each consumer (cascade) |
| Visibility of double inheritance | explicit (java's `.gitmodules` lists both) | implicit (java's `.gitmodules` only mentions shared ; common is hidden inside) |

## Decision

**α** — each consumer that needs common attaches it as **its own
direct submodule** at `infra/common/`. Same path everywhere :

- `iris-service-java/infra/common/`         → iris-common (own pin)
- `iris-service-java/infra/shared/`         → iris-service-shared (own pin)
- `iris-service-python/infra/common/`       → iris-common (own pin)
- `iris-service-python/infra/shared/`       → iris-service-shared (own pin)
- `iris-ui/infra/common/`                   → iris-common (own pin)
- `iris-service-shared/infra/common/`       → iris-common (self-reference)

`iris-service-shared` itself ALSO has common as a submodule (so that
its own ADR-drift checks + release scripts work) — but its SHA pin is
independent of any consumer's pin.

## Consequences

### Positive

- **Independent versioning** : when we patch a script in common, each
  consumer can bump on its own schedule without forcing the others.
  Useful for staged rollout (validate the change in python first, then
  java, then ui) or partial rollback (java keeps the old SHA while
  others move to the new one).
- **Symmetric path** across all 4 consumers : `infra/common/bin/ship/...`
  works identically in java, python, ui, and shared. No mental overhead
  ("oh wait, in java it's `infra/shared/common/`"). Easier muscle memory
  + simpler grep across repos.
- **Explicit dependency declaration** : `.gitmodules` in each consumer
  lists both `infra/shared/` and `infra/common/` directly. A new
  contributor cloning java sees the two deps immediately ; with β,
  they'd see only `infra/shared/` and discover common only after running
  `--recursive`.
- **Standard clone semantics** : `git submodule update --init` (no
  `--recursive` flag needed). One less footgun in onboarding /
  CI scripts.
- **Coherent in case of double inheritance** : the chosen architecture
  reflects how a polyglot team naturally thinks — "I depend on common +
  I depend on shared (which itself happens to also depend on common,
  but that's its problem, not mine)". The dependency graph is a DAG with
  shared and common as separate nodes, both of which java points to ;
  no hidden transitive layer.

### Negative

- **`.gitmodules` has 2 entries instead of 1** for backend repos.
  Negligible cost (4 lines of YAML).
- **Common patches require N independent bumps** (one per consumer)
  instead of 1 bump-cascade. In practice a maintainer runs the same
  `cd infra/common && git pull && cd .. && git add infra/common &&
  git commit -m "..."` in each repo — scriptable in 30 lines via
  `bin/ship/renovate-sync.sh`-style automation if it ever becomes
  painful.
- **Risk of drift** : java could pin common@SHA-X while python pins
  common@SHA-Y. Mitigation : the `bin/ship/check-default-branch.sh`-style
  audit can be extended to also check submodule SHA consistency, or
  Renovate can be configured to bump both repos in lockstep.

### Neutral

- **Cross-repo references still work** : ADR-0055 in iris-common
  is now linkable from any consumer via
  `https://gitlab.com/iris-7/iris-common/-/blob/main/docs/adr/0055-shell-based-release-automation.md` —
  same as before its move.
- **Both options ARE versioned** : submodule = pinned SHA in both α and
  β. The difference is who controls the pin (the consumer in α, or the
  intermediate layer in β).

## Alternatives considered

### β — common nested inside shared

Backend repos have only `infra/shared/` ; common arrives transitively
via `infra/shared/common/`. Rejected for the asymmetric path
(`infra/shared/common/` in backend vs `infra/common/` in UI), the
forced alignment of common-SHA between java and python (no per-repo
divergence possible), and the cascade of bumps required to propagate
a single common patch to backend repos.

### γ — git subtree instead of submodule

Common content is `git subtree`-imported into shared-service +
each consumer, so it lives directly in their filesystem (no submodule
indirection). Rejected for : (a) `git subtree` is non-trivial to learn
+ remember (less documented than submodule), (b) git history pollution
(common's commits show up inside each consumer's history), (c) doesn't
solve the "UI shouldn't get backend infra" problem any better than α.

### δ — no shared layer, copy-paste

Each consumer holds its own copy of every script. Rejected as the
opposite of factorisation — exactly the drift this whole effort
exists to prevent.

## References

- [ADR-0001](0001-shared-repo-via-submodule.md) — the underlying submodule pattern
- [ADR-0057](0057-polyrepo-vs-monorepo.md) — why polyrepo (not monorepo) in the first place
- [`iris-common/README.md`](../../README.md) — leaf submodule overview
- [`iris-service-shared/README.md`](https://gitlab.com/iris-7/iris-service-shared/-/blob/main/README.md) — backend submodule overview
- 2026-04-26 split commit on shared-service : `b1df97f` (deletes the universal scripts + adds infra/common/ submodule self-reference)
- 2026-04-26 bootstrap of iris-common : `8028236` (initial extraction)
