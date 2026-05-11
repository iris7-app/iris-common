# ADR-0070 — workflow:rules dev/main allowlist pattern

**Status** : Accepted (shipped 2026-05-11)

## Context

GitLab CI `workflow:rules` decide whether a pipeline is created. The
iris-7 consumer repos (java, python, ui) use an allowlist pattern :
only changes to specific paths trigger a pipeline. Doc-only commits
(`**/*.md` outside the allowlist) silently skip CI, which is fine.

After the [ADR-0066](0066-auto-merge-dev-to-main-template.md) auto-merge
template shipped 2026-05-10, we discovered an interaction bug :

1. A bump-SHA chore MR (e.g. `chore(submodule): bump iris-common SHA → X`)
   triggers a pipeline on the MR (matches `merge_request_event` rule).
2. Pipeline passes, MR merged on dev.
3. The dev push **does not** match the dev/main allowlist (because the
   allowlist there didn't include `infra/common` gitlink + `.gitmodules`).
4. No dev pipeline → no `promote-dev-to-main` job → main stays stale.

Workaround used 2026-05-11 : manual `git push --force-with-lease origin
dev:main` on 4 repos. Fragile + violates the auto-merge promise.

## Decision

The **dev/main allowlist must be a superset of the MR allowlist** so
any change that triggers a MR pipeline also triggers a dev/main pipeline
after merge. Specifically :

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: [ALLOWLIST_FULL]                # M paths
    - if: ($CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH || $CI_COMMIT_BRANCH == "dev") && $CI_PIPELINE_SOURCE != "schedule"
      changes: [ALLOWLIST_FULL]                # Same M paths — superset OK, subset NOT
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - when: never
```

For iris-7 consumers, the allowlist always includes :
- Source code (`src/**/*`)
- Build files (`pom.xml`, `package.json`, `pyproject.toml`)
- CI config (`.gitlab-ci.yml`, `.gitlab-ci/**/*`, `.gitlab/**/*`,
  `.github/**/*`)
- Submodule paths : **both gitlink (`infra/common` without glob) AND
  glob (`infra/common/**/*` with glob)** — needed because gitlink SHA
  bumps don't match the glob pattern.
- `.gitmodules` — needed when URL or path of submodule changes.
- Docs paths if doc-only changes should still satisfy "main requires
  passing pipeline" branch protection.

## Trade-offs

- ✅ **Auto-merge fires reliably** : every chore that triggers an MR
  pipeline will also trigger the dev pipeline after merge.
- ✅ **Same allowlist, no drift** : just copy-paste between MR rule and
  dev/main rule.
- ⚠️ **Larger dev pipeline footprint** : a chore that only touches
  `.gitmodules` now triggers a full dev pipeline (most stages skipped
  by `changes:` filters anyway). Acceptable cost.
- ⚠️ **Manual checklist** : when adding a new path to the MR allowlist,
  developer must remember to add it to dev/main rule too. Compensating
  control : reviewers check the diff matches both rules. Future improvement :
  YAML anchor / template for the allowlist so it's defined once.

## Compensating controls

1. **Inline comment** on each path-only addition mentions the symmetry
   requirement.
2. **ADR-0070** documents the pattern (this doc).
3. **Future** : factor the allowlist into a YAML anchor (`&allowlist`)
   referenced by both rules — eliminates the drift risk.

## Status

- iris-service-java : MR rule + dev/main rule symmetric ✅ (fix shipped 2026-05-11)
- iris-ui : MR rule + dev/main rule symmetric ✅ (fix shipped 2026-05-11)
- iris-service-python : already symmetric (rule uses regex `^(main|dev)$`)
- iris-common, iris-service-shared : no workflow rules (no allowlist required)

## Related ADRs

- [ADR-0066](0066-auto-merge-dev-to-main-template.md) — auto-merge template (root cause of this requirement)
