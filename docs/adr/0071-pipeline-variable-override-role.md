# ADR-0071 — Pipeline variable override role : `owner` across all 5 repos

**Status** : Accepted (shipped 2026-05-14)

## Context

GitLab CI/CD has a per-project setting
`ci_pipeline_variables_minimum_override_role` that controls who can
pass variables to pipelines (manual runs, scheduled runs, API-triggered
runs). Values are :

- `no_one_allowed` — nobody can override variables
- `owner` — only project Owners (access_level 50)
- `maintainer` — Maintainers (40) + Owners
- `developer` — Developers (30) + Maintainers + Owners

When the iris-7 polyrepo was set up over multiple sessions, the 5
repos drifted to inconsistent values :

| Repo | Setting (before) |
|---|---|
| iris-common | `no_one_allowed` |
| iris-service-shared | `no_one_allowed` |
| iris-service-java | `developer` |
| iris-service-python | `no_one_allowed` |
| iris-ui | `developer` |

Discovered 2026-05-14 when creating the python `mutmut-auth-monthly`
schedule : the GitLab API returned `403 Forbidden` on POST
`/pipeline_schedules/{id}/variables` despite the calling user being
project Owner. Same call worked on java (which had `developer`).
Diagnosed via :

```bash
glab api "projects/iris-7%2F<repo>" | jq '.ci_pipeline_variables_minimum_override_role'
```

## Decision

Align all 5 repos to `owner`. Specifically :

- **`owner`** — only project Owners (= benoit.besson for this
  portfolio) can pass variables to pipelines. This includes :
  - Manual "Run pipeline" with custom vars
  - Pipeline schedules with `RUN_*=true` variables
  - API-triggered pipelines with variables

Applied 2026-05-14 via :

```bash
for p in iris-common iris-service-shared iris-service-java iris-service-python iris-ui; do
  glab api --method PUT "projects/iris-7%2F$p" \
    -f "ci_pipeline_variables_minimum_override_role=owner"
done
```

## Trade-offs

- ✅ **Consistency** — same security stance across the polyrepo ;
  no per-project surprise when running schedules or manual triggers.
- ✅ **Secure default** — `developer` was too permissive for shared
  infrastructure ; `no_one_allowed` was over-restrictive (blocked
  legit Owner schedule variables). `owner` strikes the balance.
- ✅ **Pipeline schedule variables work** — the immediate trigger :
  unblocks `RUN_COMPAT=true` (java compat-matrix-weekly) and
  `RUN_MUTMUT=true` (python mutmut-auth-monthly) schedules.
- ⚠️ **Future contributors** — if iris-7 ever onboards a
  contributor at Developer or Maintainer level, they will not be
  able to override pipeline variables. Re-evaluate at that point.

## Alternatives considered

1. **Keep `no_one_allowed` everywhere + use group-level variables**
   - ❌ Group variables are static, can't be schedule-specific
     (e.g. `RUN_COMPAT=true` for weekly schedule only).
2. **`developer`** (match java + ui pre-state)
   - ❌ Too permissive for a setting that controls schedule
     credentials. Owner-only is the cleanest default.
3. **`maintainer`**
   - ❌ Same outcome as `owner` for this portfolio (only Owner is
     active). No upside.

## Verification

Post-change snapshot (2026-05-14) :

```
iris-common          : owner
iris-service-shared  : owner
iris-service-java    : owner
iris-service-python  : owner
iris-ui              : owner
```

Verified `mutmut-auth-monthly` schedule variable `RUN_MUTMUT=true`
added successfully after the flip on python (was `403 Forbidden`
before).

## Related ADRs

- [ADR-0066](0066-auto-merge-dev-to-main-template.md) — auto-merge template (uses AUTOMERGE_TOKEN, separate variable scope)
- [ADR-0068](0068-route-services-ci-to-saas.md) — SaaS routing on python
- [ADR-0069](0069-double-ci-gitlab-github-actions.md) — Double-CI
