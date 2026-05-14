# Session 2026-05-13 → 2026-05-14 — follow-up to 2026-05-09 to 12

## Scope

Two-day pass that consolidates the previous 4-day session's work
(audit doc shipped 2026-05-12) by :

- Bumping the iris-common submodule SHA on all 4 consumers + shared
  so they pick up ADRs 0066-0070 + the auto-merge force-fetch fix.
- Closing the carry-forward items (compat matrix scheduling on java,
  mutmut scheduling on python).
- Fixing the auto-merge promote-dev-to-main template after observing
  a non-fast-forward fetch rejection on the runner workspace.
- Aligning a CI/CD project setting drift (`ci_pipeline_variables_minimum_override_role`)
  across all 5 repos.
- Adding a one-command github-mirror sync script (recurring need).

## Numbers

- **9 MRs merged** : iris-common × 4, iris-service-shared × 2,
  iris-service-java × 2, iris-service-python × 2, iris-ui × 1
- **1 CVE resolved** (python) : urllib3 2.6.3 → 2.7.0
  (CVE-2026-44431 + CVE-2026-44432, fix shipped in 2.7.0)
- **1 new ADR accepted** : [ADR-0071](../adr/0071-pipeline-variable-override-role.md)
- **2 pipeline schedules created** :
  - iris-service-java `compat-matrix-weekly` (Sunday 04:00 Paris, `RUN_COMPAT=true`)
  - iris-service-python `mutmut-auth-monthly` (1st of month 05:00 Paris, `RUN_MUTMUT=true`)
- **1 new shared script** : `bin/ship/github-mirror-sync.sh`
- **3 GitHub mirrors resynced** : iris-common, iris-service-shared, iris-ui
- **5/5 repos** now have `ci_pipeline_variables_minimum_override_role=owner`

## Decisions (linked ADRs)

1. **[ADR-0071](../adr/0071-pipeline-variable-override-role.md) — Pipeline
   variable override role : `owner` across all 5 repos** : discovered
   that python (+ common + shared) had `no_one_allowed` while java + ui
   had `developer`. The drift broke a 403 on schedule variable add for
   the python `mutmut-auth-monthly` schedule. Aligned to `owner` :
   secure default that lets Owners (only) override pipeline variables.

2. **Auto-merge template force-fetch fix** (no ADR — single-line CI
   patch, ADR overhead not justified) : prepended `+` to the
   `git fetch "$REPO_URL" main:refs/remotes/origin/main` line so the
   local `origin/main` ref is force-updated. Runner workspace persists
   between jobs, so a stale ref (typical after manual force-pushes
   during bootstrap) made the non-`+` fetch reject. Documented inline
   in the template comment and in [iris-common MR !36](https://gitlab.com/iris-7/iris-common/-/merge_requests/36).

3. **Wire auto-merge template on iris-service-shared** : shared was
   the only repo that hadn't yet adopted the auto-merge template.
   The MR !30 (iris-common SHA bump) merged on dev but main wasn't
   promoted until a manual `git push origin dev:main`. Fix : include
   `ci-templates/auto-merge-dev-to-main.yml` + add `promote` stage.

## Patterns reinforced

- **`+` prefix on `git fetch` lines in CI templates** that must work
  on persistent runner workspaces. Match the force-with-lease push
  semantics on the line below.
- **Project settings drift is silent until it bites** : the
  `ci_pipeline_variables_minimum_override_role` setting drifted
  across the 5 repos over several sessions. Add to the
  `bin/dev/stability-check.sh` preflight in a future iteration.
- **GitHub mirror sync is recurring** : drift detected 3 out of 5
  repos in a single normal session. The new script
  `bin/ship/github-mirror-sync.sh` makes the operation one command.
  Cadence : run at every session start, after stable-v\* tag
  pushes, and post any manual force-push.
- **Bump iris-common SHA after every iris-common main update** : 4
  consumers need to re-pin to pick up new ADRs / templates /
  scripts. Use `bin/ship/bump-common-everywhere.sh` (or per-repo
  manual bump).
- **Workflow:rules submodule MR allowlist** (intentional, per
  ADR-0070) : submodule bump MRs do NOT trigger MR pipelines
  (allowlist superset rule). They merge instantly. The dev
  pipeline that follows runs the full gating + auto-promotes
  to main. Net result : no per-bump MR-CI delay, main still
  gated.

## Carry-forward closed

- ✅ **Compat matrix java schedule** : `compat-matrix-weekly` cron
  `0 4 * * 0` with `RUN_COMPAT=true`. Rule change in
  [java MR !297](https://gitlab.com/iris-7/iris-service-java/-/merge_requests/297).
- ✅ **Mutmut python schedule** : `mutmut-auth-monthly` cron
  `0 5 1 * *` with `RUN_MUTMUT=true`. Rule change in
  [python MR !82](https://gitlab.com/iris-7/iris-service-python/-/merge_requests/82).

## Known limitations (still carried forward)

- ❌ **Mac arm64 + Docker for Mac + GitLab Runner services** :
  architectural impasse, integration-tests for python still route
  to SaaS runner per ADR-0068.
- ⚠️ **iris-ui MR workflow:rules submodule allowlist** :
  intentional ADR-0070 design (allowlist superset). Submodule
  bumps merge without MR-CI gating ; dev-pipeline still runs.
  Trade-off : speed-of-bumps vs MR-time safety net.

## Where to look next

- New session inheriting this state should expect : 0 open MRs,
  dev = main on all 5 repos, all 5 github mirrors in sync,
  2 active pipeline schedules.
- Add `bin/ship/github-mirror-sync.sh --check` call to
  `bin/dev/stability-check.sh` preflight so drift surfaces at
  every stability checkpoint.
- Test that `compat-matrix-weekly` actually fires Sunday 04:00
  (cron triggers in GitLab can occasionally drop) by checking
  the pipeline list on Monday morning.
- Consider tightening `SHELLCHECK_SEVERITY` from `error` to
  `warning` in iris-common's shellcheck template — pre-existing
  warning backlog in bump-common-everywhere.sh + setup-signed-commits.sh
  would need clean-up first.

## Related session audit docs

- [Previous session](session-2026-05-09-to-12-summary.md) — 4-day
  consolidation of audit doc + double-CI + auto-merge.
