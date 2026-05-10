# ADR-0066 — auto-merge dev → main via CI template + group token

**Status** : Accepted (shipped 2026-05-10)
* Decision date : 2026-05-10
* Deciders : @Beennnn
* Tags : `ci`, `polyrepo`, `release-engineering`

## Context

Before 2026-05-10, every `dev → main` promote on the 4 consumer repos
(iris-service-java, iris-service-python, iris-ui, iris-service-shared)
required a manual MR. Workflow :

1. Open MR with target `dev` for the change
2. Wait pipeline green, MR mergé sur dev
3. Open separate MR `dev → main`
4. Wait pipeline green again, merge MR #2

Step 3 + 4 add ~10-15 min latency + the cognitive cost of remembering
to do the second MR. For a high-velocity session, this is the bottleneck.

Variations of this problem are common in dev/main two-step workflows
(GitFlow lite, trunk-with-staging, …). The textbook solution is
**release branches with auto-promote**, but those require infrastructure
(release-please, semantic-release, ChangeSets, …) often overkill
for a polyrepo of 5 repos.

## Decision

Ship a reusable **CI template** at `iris-common/ci-templates/
auto-merge-dev-to-main.yml` that consumers include. The template
defines a single job `promote-dev-to-main` :

```yaml
promote-dev-to-main:
  stage: promote
  image: alpine:3.20
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"
      when: on_success
  script:
    - |
      REPO_URL="https://oauth2:${AUTOMERGE_TOKEN}@gitlab.com/${CI_PROJECT_PATH}.git"
      git fetch "$REPO_URL" main:refs/remotes/origin/main
      if git merge-base --is-ancestor HEAD origin/main; then
        echo "ℹ️  dev already ancestor of main — nothing to promote."
        exit 0
      fi
      git push --force-with-lease=main:origin/main "$REPO_URL" "HEAD:refs/heads/main"
```

The job runs as the last stage of the dev pipeline (after every
gating stage). On `on_success`, it pushes `dev → main` using a Personal
Access Token stored as group CI variable `AUTOMERGE_TOKEN`
(scope `write_repository`).

## Setup prerequisites (one-time per group)

1. **PAT created at user level**, scope=`write_repository`, expiry 1 year.
2. **Variable `AUTOMERGE_TOKEN`** at group level (Settings > CI/CD >
   Variables), masked + protected.
3. **Branch protection on dev** with `Maintainers` push access (so the
   variable's protected flag matches a protected branch — required for
   GitLab to expose `AUTOMERGE_TOKEN` to the dev pipeline).
4. **Branch protection on main** with `allow_force_push = true` —
   required because dev/main can diverge (e.g. after a hotfix merged
   directly to main), in which case `--force-with-lease` writes over.

## Consumer integration

Each consumer's `.gitlab-ci.yml` adds :

```yaml
include:
  - project: 'iris-7/iris-common'
    ref: main
    file: 'ci-templates/auto-merge-dev-to-main.yml'

stages:
  - validate
  - test
  # … all gating stages …
  - promote    # ← new, last stage
```

Plus the consumer's `workflow:rules` MUST accept `dev` pushes (else the
pipeline never runs and the job never fires). Typical pattern :

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: [...]
    - if: ($CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH || $CI_COMMIT_BRANCH == "dev") && $CI_PIPELINE_SOURCE != "schedule"
      changes: [...]
```

## Alternatives considered

1. **Manual dev → main MR every batch** (status quo).
   - ❌ 10-15 min latency × N batches per day.
2. **Release-please** (semantic-release for monorepo).
   - ❌ Overkill for 5 polyrepo with no release engineering pressure.
3. **GitLab Merge Request API auto-merge** (mwps).
   - ❌ Still requires creating a MR, slow.
4. **Single-branch workflow (trunk-based, drop dev)**.
   - ❌ Loses the dev/main split which is conceptually clean (dev = WIP,
     main = production-ready). Cost-benefit not in favor.

## Trade-offs

- ✅ **0 manual step** : every dev push that goes green automatically
   becomes main.
- ✅ **Reusable** : same template across the 5 iris-7 repos.
- ✅ **Idempotent** : if dev is already ancestor of main (rare race),
   skip without error.
- ⚠️ **Force-push on main** : `--force-with-lease` is safe, but requires
   the runner's PAT user to have force-push permission. If main was
   manually edited between dev pipeline start and the promote job's
   push, the lease guard fails → manual recovery needed.
- ⚠️ **PAT rotation** : the AUTOMERGE_TOKEN expires every 1 year. Set
   a calendar reminder (or use GitLab's token expiration notifications).
- ⚠️ **Group access tokens unavailable on Free** : we use a user-level
   PAT instead. If team grows past 1 dev, switch to a Group Access
   Token (requires Premium) or rotate the PAT.

## Status post-shipping (2026-05-10)

- 5 repos shipped : iris-common (eat own dogfood), iris-service-shared,
  iris-service-java, iris-service-python, iris-ui.
- First end-to-end live run : !77 python (integration-tests + redpanda
  switch) merged on dev → auto-pushed to main in ~3s after dev pipeline
  green.
- Saved : ~10 manual promote MRs already eliminated in the first day.

## Related ADRs

- [ADR-0060](0060-flat-vs-transitive-submodule-inheritance.md) — polyrepo flat α submodule pattern (context for the 5 repos)
- [ADR-0065](0065-route-ci-to-macbook-local-runner.md) — runner setup
