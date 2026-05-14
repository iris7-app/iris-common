# Cross-cutting ADRs — `iris-common`

This directory captures the **why** of every architectural choice that
applies UNIVERSALLY across the [iris-7](https://gitlab.com/iris-7)
family — i.e. decisions that bind java + python + ui + shared-service
all four together (release engineering, repo conventions, dependency
management).

For **backend-only** decisions (observability stack, K8s posture,
multi-cloud terraform, secret management), see
[`iris-service-shared/docs/adr/`](https://gitlab.com/iris-7/iris-service-shared/-/tree/main/docs/adr).

For **repo-local** decisions (Spring Boot stack, FastAPI auth, Angular
zoneless mode), see each consumer repo's own `docs/adr/`.

## Status snapshot

- ✨ **Accepted** : current architectural shape ; obey unless an ADR
  supersedes.
- 📝 **Proposed** : draft, awaiting review or implementation.
- 🛑 **Superseded** : kept for historical context ; the link points to
  the replacement.

## Numbering

ADR numbers preserved from the source repo (`iris-service-shared`)
to maintain external references. New ADRs born here will use the next
sequential number from this repo's tip (e.g. 0060+).

## Flat index

The table below is **auto-regenerated** by
[`bin/dev/regen-adr-index.sh`](../../bin/dev/regen-adr-index.sh).
Do not edit between the markers — run the script after adding /
modifying an ADR.

<!-- ADR-INDEX:START -->
| ID | Status | Title |
|---|---|---|
| 0001 | Accepted | [Shared infra extraction via git submodule](0001-shared-repo-via-submodule.md) |
| 0055 | Accepted | [Shell-based release automation (no semantic-release)](0055-shell-based-release-automation.md) |
| 0057 | Accepted | [Conserver le polyrepo (svc + UI séparés), pas de migration vers monorepo](0057-polyrepo-vs-monorepo.md) |
| 0059 | Accepted | [Renovate base preset + sync script (option B)](0059-renovate-base-preset.md) |
| 0060 | Accepted | [Flat 2-submodule inheritance over transitive nested](0060-flat-vs-transitive-submodule-inheritance.md) |
| 0061 | Accepted | [Per-repo tag namespace pattern (`stable-X-v*`)](0061-per-repo-tag-namespace-pattern.md) |
| 0062 | Accepted | [0062. Thematic mastery axes — tag annotations + README top blocks](0062-thematic-mastery-tags-readme.md) |
| 0063 | Accepted | [0063. MR batching vs fan-out — when to merge, when to split](0063-mr-batching-vs-fan-out-pattern.md) |
| 0065 | Accepted | [0065. Route every CI job to the macbook-local runner](0065-route-ci-to-macbook-local-runner.md) |
| 0066 | Accepted | [auto-merge dev → main via CI template + group token](0066-auto-merge-dev-to-main-template.md) |
| 0067 | Accepted | [Kafka CI image switch (bitnamilegacy → redpanda)](0067-kafka-redpanda-switch-for-ci.md) |
| 0068 | Accepted | [Route Python integration-tests to GitLab SaaS runner](0068-route-services-ci-to-saas.md) |
| 0069 | Accepted | [Double-CI : GitLab as reference + GitHub Actions as backup](0069-double-ci-gitlab-github-actions.md) |
| 0070 | Accepted | [workflow:rules dev/main allowlist pattern](0070-workflow-rules-dev-branch-pattern.md) |
| 0071 | Accepted | [Pipeline variable override role : `owner` across all 5 repos](0071-pipeline-variable-override-role.md) |
<!-- ADR-INDEX:END -->

## Adding a new cross-cutting ADR

1. **Verify it's truly universal** — if the decision only affects backend
   (java + python), it belongs in `iris-service-shared/docs/adr/`,
   not here. Litmus test : "would the UI repo need this decision too?"
   → yes = universal.
2. Pick the next 4-digit ID (look at existing files).
3. File name : `NNNN-<kebab-case-title>.md` (e.g. `0060-some-decision.md`).
4. First line of the file : `# ADR-NNNN — <Title>` or `# ADR-NNNN : <Title>`.
5. Include a `**Status** : <Proposed|Accepted|Superseded>` line near the
   top so the index regenerator picks it up.
6. Run `bin/dev/regen-adr-index.sh --in-place` to refresh this README.
7. Commit the ADR + the regenerated README in the same commit on `main`.
8. Bump the submodule SHA in each consumer repo that's affected
   (in practice : all of them, since this is the universal layer).

## See also

- [`../../bin/dev/regen-adr-index.sh`](../../bin/dev/regen-adr-index.sh) — regenerator
- [`../../bin/ship/pre-sync.sh`](../../bin/ship/pre-sync.sh) — git safety pre-flight
- [`../../README.md`](../../README.md) — repo overview + how consumers attach
- Sibling ADR dirs :
  [shared-service](https://gitlab.com/iris-7/iris-service-shared/-/tree/main/docs/adr) ·
  [java](https://gitlab.com/iris-7/iris-service-java/-/tree/main/docs/adr) ·
  [python](https://gitlab.com/iris-7/iris-service-python/-/tree/main/docs/adr) ·
  [ui](https://gitlab.com/iris-7/iris-ui/-/tree/main/docs/adr)
