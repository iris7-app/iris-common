# ADR-0068 — Route Python integration-tests to GitLab SaaS runner

**Status** : Accepted (shipped 2026-05-10)
* Decision date : 2026-05-10
* Deciders : @Beennnn
* Tags : `ci`, `runner`, `services`

## Context

Global CLAUDE.md rule : "Use local runners, never rely on GitLab SaaS
quota." This applies to all iris-7 repos by default.

`iris-service-python` integration-tests requires GitLab `services:`
(postgres + redpanda). After 5 failed attempts to make this work on the
local `macbook-local` runner (Mac arm64 + Docker for Mac) :

1. Default config (socket binding) → services don't start.
2. `network_per_build = true` → DNS resolves, services still unreachable.
3. `privileged = true` → broke Java testcontainers as side effect.
4. `wait_for_services_timeout = 120` → kafka bootstrap still too slow.
5. **Pure dind runner** (dedicated `macbook-local-dind` runner instance,
   tag `dind-services`, no socket binding) → services start in container
   but health check across network never connects.

Root cause : Mac arm64 + Docker for Mac + GitLab Runner services mode
has an architectural networking quirk that we cannot fix from
configuration alone.

Switching kafka → redpanda fixed the *time* dimension (boot 3-5s vs
30-45s), but the *network* dimension persists on macbook-local — services
are visible (container running) but unreachable via the runner's health
check container.

## Decision

Tag `iris-service-python:integration-tests` with `tags:
[saas-linux-medium-amd64]` to route this single job to the GitLab SaaS
Linux runner. The rest of the python pipeline (unit-tests, lint, pip-
audit, etc.) continues to route to `macbook-local`.

Trade : ~3 min × N MRs per month against SaaS quota (free tier ~400
min/month). Estimated 1-2% consumption.

## Alternatives considered (extensive)

1. **Approach A — separate dind runner**. Documented in [docs/audit/runner-dind-migration-2026-05-09.md](https://gitlab.com/iris-7/iris-service-python/-/blob/main/docs/audit/runner-dind-migration-2026-05-09.md).
   - ❌ Failed : services still unreachable from health check container
     despite full dind mode.
2. **Approach C — GitHub Actions only** for integration-tests, drop
   GitLab side.
   - ❌ Loses GitLab as single source of CI truth ; doubles maintenance.
3. **Approach D — testcontainers fallback in CI** (no GitLab `services:`).
   - ❌ Earlier attempt 2026-04-27 failed : macbook-local runner Docker
     bridge didn't route from job container to testcontainers spawned via
     host socket.
4. **Approach E — wait for upstream fix** of Mac arm64 + Docker + runner
   networking.
   - ❌ Indefinite timeline, blocks integration-tests indefinitely.

## Trade-offs

- ✅ **Works immediately** : SaaS Linux native amd64 has first-class
  services support, kafka redpanda + postgres both start <10s.
- ✅ **Isolated impact** : only 1 job re-routes, ~3 min × N MRs per month.
- ✅ **Free tier coverage** : 400 min/mo headroom for ~130 MRs.
- ⚠️ **Violates CLAUDE.md local-runner rule** explicitly. Compensating
  fence : ADR documents the decision + audit doc + extensive prior
  attempts.
- ⚠️ **Network dependency** : if SaaS is down, integration-tests block.
  iris-7 is small enough that this is acceptable.
- ⚠️ **arm64 → amd64 image** : redpanda has both. Postgres alpine has
  both. No issue.

## Compensating controls

1. **Audit doc** : [docs/audit/runner-dind-migration-2026-05-09.md](https://gitlab.com/iris-7/iris-service-python/-/blob/main/docs/audit/runner-dind-migration-2026-05-09.md)
   captures the 5 attempts in detail.
2. **GitHub Actions mirror** workflow added at
   `.github/workflows/integration-tests.yml` — uses
   `runs-on: ubuntu-latest` + `container:` for service alias resolution.
   Belt-and-braces double-CI.
3. **Re-test trigger** : if Docker for Mac arm64 networking fix lands
   upstream, retry Approach A. ADR will be amended or superseded.

## Status post-shipping

- Shipped 2026-05-10 in `iris-service-python` (!77).
- First live run : main pipeline #2514037064 success on SaaS runner.
- GH Actions parallel run : success (run #25639568671).
- Other jobs : all continue to route to macbook-local unchanged.
- Saas quota consumed : ~6 min for 2 successful integration-tests runs
  (init + retest).

## Future review

Revisit if :
- Mac arm64 Docker networking fixes the services mode.
- SaaS quota usage approaches 200 min/mo (would suggest the job is
  triggered too often — workflow:rules should narrow).
- Need additional CI services (e.g. redis) — should they go to SaaS
  too, or revisit Approach A ?

## Related ADRs / docs

- [ADR-0066](0066-auto-merge-dev-to-main-template.md) — auto-merge dev → main template
- [ADR-0067](0067-kafka-redpanda-switch-for-ci.md) — kafka → redpanda switch
- [docs/audit/runner-dind-migration-2026-05-09.md](https://gitlab.com/iris-7/iris-service-python/-/blob/main/docs/audit/runner-dind-migration-2026-05-09.md) — detailed runner debug
- [docs/audit/kafka-ci-redpanda-switch-2026-05-10.md](https://gitlab.com/iris-7/iris-service-python/-/blob/main/docs/audit/kafka-ci-redpanda-switch-2026-05-10.md) — kafka boot time fix
- Global CLAUDE.md "Use local runners" — superseded for this single job, with documented compensating controls.
