# 0065. Route every CI job to the macbook-local runner

Date: 2026-04-29
Status: Accepted

## Context

GitLab SaaS shared runners come with a monthly compute-minutes quota
on the free tier. The Iris polyrepo runs 4 production repos (java,
python, ui, shared) plus iris-common — each with a multi-stage
pipeline (lint, unit-test, integration-test, sonar, build-jar,
compat matrix, native-build, …). Even at moderate MR throughput the
shared-runner quota is exhausted within days, after which jobs fail
with `ci_quota_exceeded`.

The 2026-04-29 session hit this concretely : the iris-common conv-
commits job on `chore/iris-common-readme-templates` (a single
2-line README change) failed in 0 seconds with `ci_quota_exceeded`,
forcing a direct-merge fallback that bypassed the gate entirely. Same
issue had been observed on iris-service-java and iris-ui in
2026-04-25 ; both fixed by routing to the macbook-local runner.

The macbook-local runner is a developer-machine-hosted GitLab
Runner registered at the iris-7 group level. It :

- has unlimited compute (no SaaS quota)
- runs Apple Silicon arm64
- is shared across the 5 iris-7 projects via group-level
  registration (`benoit.besson` user is the runner registrant)

The trade-off : when the laptop is off, no CI runs. Acceptable for
a portfolio / demo project where the developer is also the CI
operator. Production-grade orgs would use a dedicated runner host.

## Decision

**Every iris-7 repo's `.gitlab-ci.yml` MUST set
`default: tags: [macbook-local]` at the top level.** This routes
every job — including those imported via `include:` from
iris-common templates — to the macbook-local runner unless the job
explicitly overrides `tags:`.

For amd64-target builds (e.g. GKE deploy, native-image build), use
Docker buildx + QEMU on the local runner :

```yaml
docker buildx build --platform linux/amd64 ...
```

Do NOT route those jobs to `saas-linux-medium-amd64` — that's the
exact SaaS quota path this ADR exists to avoid.

Per-job opt-out is allowed for jobs that genuinely need a SaaS
runner (none today, but the door stays open via explicit `tags:`).

## Consequences

### Positive

- Pipeline jobs run unbounded — no `ci_quota_exceeded` 0-second
  failures.
- Consistent execution environment across all 5 repos.
- macbook-local is faster than the free-tier SaaS shared runner
  for most jobs (M-series CPU, fast SSD, warm Maven / npm caches).

### Negative

- CI runs only when the laptop is online.
- If the laptop is dropped / re-imaged, the runner registration
  must be redone (`gitlab-runner register --url ...`).
- Single point of failure for CI.

### Neutral

- Cross-architecture builds (arm64 → amd64) need explicit `--platform`
  passed to `docker buildx`. This is a separate practice from the
  runner choice — applies regardless of which runner the job uses.

## Implementation

The 4 production repos already had this set as of 2026-04-25 :

- iris-service-java/.gitlab-ci.yml line 130-141
- iris-service-python/.gitlab-ci.yml (analogous block)
- iris-ui/.gitlab-ci.yml (analogous block)

iris-service-shared got its first `.gitlab-ci.yml` via MR !18
(2026-04-29) which already includes `default: tags: [macbook-local]`.
iris-common gets it via this MR.

Validation : `git grep -nE 'tags:.*macbook-local' .gitlab-ci.yml` in
each repo returns the expected line.

## Related

- ~/.claude/CLAUDE.md § "Use local runners, never rely on GitLab
  SaaS quota" — the cross-project rule this ADR formalises.
- ADR-0060 — flat-α submodule pattern. Cross-project CI templates
  via iris-common follow the same submodule-share-by-include-only
  philosophy.
- ADR-0063 — MR batching. Combined with this ADR, the polyrepo's
  CI footprint is bounded by both the per-MR cycle count AND the
  per-job runner choice.
