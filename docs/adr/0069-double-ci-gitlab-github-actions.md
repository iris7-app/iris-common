# ADR-0069 — Double-CI : GitLab as reference + GitHub Actions as backup

**Status** : Accepted (shipped 2026-05-10)

## Context

Until 2026-05-10, GitLab CI was the only CI gate for iris-7 repos. After
the SaaS routing decision for python integration-tests
([ADR-0068](0068-route-services-ci-to-saas.md)), we noticed two
adjacent risks :

1. **SaaS dependency** : if GitLab SaaS Linux runners are down,
   integration-tests block. iris-7 is a portfolio project (low priority)
   but blocking the gate stalls merges.
2. **Mac arm64 local runner brittleness** : 5 attempts to make services
   work on macbook-local failed. If the runner has another silent
   failure mode in the future, we have no second opinion.

GitHub Actions on `ubuntu-latest` provides :
- 2000 free min/mo for public repos
- Native amd64 Linux runner (no arm64 quirk)
- First-class `services:` support
- Independent failure domain from GitLab

Cost is just a workflow YAML mirror + the bytes pushed to github.

## Decision

For `iris-service-python` (the only repo currently with integration-tests
CI), mirror the integration-tests job as a GitHub Actions workflow at
`.github/workflows/integration-tests.yml`. The job runs in a container
(`ghcr.io/astral-sh/uv:python3.14-bookworm-slim`) so postgres + kafka
services are reachable via alias (same setup as GitLab CI).

**GitLab remains the reference** — it runs every job (validate, unit,
integration, sonar, security scans, deploy targets, etc.). GitHub Actions
runs **only integration-tests** as a backup gate.

## Trade-offs

- ✅ **Independent failure domain** : if GitLab is down, GH Actions
  still catches integration regressions.
- ✅ **Native Linux amd64** : no arm64 quirk on services.
- ✅ **Free tier** : 2000 min/mo for public repos covers ~700 runs
  (vs 400 min/mo on GitLab SaaS).
- ⚠️ **2 CI systems to maintain** : workflow drift between GitLab CI
  and GH Actions is a real risk. Compensating control : keep GH Actions
  workflow minimal (only integration-tests) so drift surface is small.
- ⚠️ **CI cost noise** : reviewer sees 2 statuses on each PR/MR. Solution :
  the GitLab status is the gate ; GH Actions is informational.
- ⚠️ **iris-ui github protection** : iris-ui github main is force-push-
  protected (cannot mirror force-pushes from GitLab). Workflows on
  github main only update when mirror push succeeds. For iris-ui, the
  workflow is shipped but won't always run latest dev code. Acceptable
  for backup tier.

## Alternatives considered

1. **GH Actions only** (drop GitLab CI).
   - ❌ Loses GitLab's full CI (sonar, security scans, terraform, etc.).
2. **Cloudflare Workers / Vercel** (other CI providers).
   - ❌ More services to maintain, not Linux native, paid tiers.
3. **Self-hosted GH Actions runner**.
   - ❌ Same arm64 quirks as GitLab macbook-local. Defeats the purpose.

## Coverage status

- iris-service-python : GitHub Actions live (run #25639568671 success)
- iris-service-java : not yet (potential future expansion)
- iris-ui : not yet (potential future expansion)
- iris-common, iris-service-shared : no integration-tests, N/A

## Related ADRs

- [ADR-0068](0068-route-services-ci-to-saas.md) — SaaS routing for python
- [ADR-0067](0067-kafka-redpanda-switch-for-ci.md) — kafka redpanda fix
- [ADR-0066](0066-auto-merge-dev-to-main-template.md) — auto-merge template
