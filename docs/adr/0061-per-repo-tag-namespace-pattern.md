# ADR-0061 — Per-repo tag namespace pattern (`stable-X-v*`)

**Status** : Accepted
**Date** : 2026-04-26
**Related repos** : `iris-service-java`, `iris-service-python`, `iris-ui`, `iris-service-shared`, `iris-common`

## Context

The iris-7 family hosts 5 git repos that release independently :

- `iris-service-java` — Spring Boot 4 backend
- `iris-service-python` — FastAPI backend (sibling of java)
- `iris-ui` — Angular 21 frontend
- `iris-service-shared` — backend infra submodule (rolls on `main`)
- `iris-common` — universal conventions submodule (rolls on `main`)

Each repo has its own release cadence : java tags every 1-2 days during
active dev, ui tags every 3-5 days, python tags 2-3 days, shared
rolls on main without tags (consumers pin SHAs). When the family is
mirrored or when an external tool lists tags across all repos
(e.g. release notes aggregator), the same prefix `stable-v` would
make tags ambiguous : was `stable-v1.0.5` a java tag or a UI tag ?
In practice both repos have shipped `stable-v1.0.5` separately.

This ADR captures the pattern the family adopted to keep tag
namespaces unambiguous **without coupling release cadences**.

## Decision

Each consumer repo uses its own **prefix-distinguished tag namespace** :

| Repo | Prefix | Example | Tagged at |
|---|---|---|---|
| `iris-service-java`   | `stable-v`     | `stable-v1.2.3`     | every green stability checkpoint |
| `iris-ui`             | `stable-v`     | `stable-v1.0.5`     | every green stability checkpoint |
| `iris-service-python` | `stable-py-v`  | `stable-py-v0.7.0`  | every green stability checkpoint |
| `iris-service-shared` | (none, rolls on main) | — | consumers pin SHAs |
| `iris-common`         | (none, rolls on main) | — | consumers pin SHAs |

**Rule** : when a NEW consumer repo is added to the family (e.g. a
hypothetical `iris-service-go` or `iris-mobile`), pick a prefix
that **disambiguates against existing prefixes** :

- If it's the canonical service for its language family, use `stable-v`
  (only ONE repo per language family does this — currently java-side).
- Otherwise, pick a 2-3-letter language hint :
  `stable-py-v` (Python),
  `stable-go-v` (Go),
  `stable-rs-v` (Rust),
  `stable-ts-v` (TypeScript ; conflicts with UI which is also TypeScript
  but uses `stable-v` because it's the canonical UI),
  `stable-mob-v` (mobile).

The prefix is consumed by [`infra/common/bin/ship/changelog.sh`](../../bin/ship/changelog.sh)
via `--tag-prefix <pfx>` :

```bash
infra/common/bin/ship/changelog.sh                            # java/ui : default = stable-v
infra/common/bin/ship/changelog.sh --tag-prefix stable-py-v   # python
```

Consumer's `CLAUDE.md` declares its tag prefix in a "Release Process"
section so any new contributor / Claude session sees the exception.

## Consequences

### Positive

- **No tag collision** when mirroring or aggregating across repos.
  GitLab + GitHub mirrors, release-notes aggregators, and any
  external tooling that lists tags from multiple repos see a clean
  separation.
- **Independent release cadences preserved** : python can tag
  `stable-py-v0.7.0` without forcing java to bump beyond
  `stable-v1.2.3`. The prefix isolates the version sequences.
- **Backwards-compatible** : the changelog generator's default is
  `stable-v` (preserves zero-arg invocation behaviour for java + ui
  which were the original consumers).
- **Discoverable** : a new contributor searching for "stable-py-v" in
  a `glab pipeline list` immediately sees it's Python-side. No need
  to inspect commit metadata to know which repo.

### Negative

- **One more flag to remember** for the Python maintainer
  (`--tag-prefix stable-py-v`). Mitigated by either : (a) `CLAUDE.md`
  documents the canonical command per repo, (b) a thin wrapper script
  could hard-code the prefix in each Python invocation if it ever
  becomes painful (currently 1 invocation per release, ~3-6/day,
  acceptable).
- **Prefix sprawl risk** : if 5 more language siblings join, we'd have
  `stable-{rs,go,ts,mob,kt}-v` etc. Mitigated by the rule "ONE repo
  per language family uses the bare `stable-v`" — there's never more
  than one ambiguous candidate.

### Neutral

- The prefix is **not the same as a versioning scheme**. Inside a
  prefix, semantic versioning still applies (major.minor.patch).
- **Shared + common roll on `main`** : they don't tag, consumers pin
  SHAs. So no prefix is needed for them. If we ever start tagging shared
  or common, the prefix would be `stable-shared-v` and `stable-common-v`
  respectively (already implied by the renaming convention).

## Alternatives considered

### Bare `stable-v` everywhere

All 4 consumer repos use `stable-v` exclusively. Rejected for the
collision problem above (already happened in 2026-04 when both java
+ UI had `stable-v1.0.5`).

### SemVer with epoch (e.g. `stable-2026.04.26-v0.7.0`)

Use a date-prefix to disambiguate. Rejected — too verbose, breaks the
one-line `git tag --sort -v:refname` reverse chronological listing,
and the date adds zero info that the commit's `--format='%cd'` can't
recover.

### Per-repo CHANGELOG with no tag at all

Drop tags entirely, rely on CHANGELOG.md as the canonical release log.
Rejected — tags are the GitLab Releases hook (`infra/common/bin/ship/gitlab-release.sh`
takes a tag), they show up in GitHub mirror sync, and they're the
machine-readable rollback target for `git checkout <tag>`.

## References

- [ADR-0055](0055-shell-based-release-automation.md) — the changelog generator that consumes `--tag-prefix`
- [ADR-0060](0060-flat-vs-transitive-submodule-inheritance.md) — the flat 2-submodule pattern
- [`infra/common/bin/ship/changelog.sh`](../../bin/ship/changelog.sh) — the generator
- 2026-04-25 incident : both java + ui had `stable-v1.0.5` ; ambiguous in `glab pipeline list` cross-project queries (motivated this ADR)
