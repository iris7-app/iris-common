# Tasks — `mirador-common`

Open work only. Per `~/.claude/CLAUDE.md` rules : universal cross-repo
items only ; per-repo items live in each consumer's own `TASKS.md`.

---

## 🔧 bump-common-everywhere.sh — finishing touches

The script SHIPPED on 2026-04-26 (commit [`737ca08`](https://gitlab.com/mirador1/mirador-common/-/commit/737ca08))
but has NOT been smoke-tested end-to-end (the `git fetch origin` step
hung in the Claude eval sandbox — production environment shouldn't have
this issue, but it's not proven).

☐ **Smoke-test the script** : run from a normal terminal in
`~/dev/mirador/mirador-common` :
```bash
bin/ship/bump-common-everywhere.sh --dry-run
```
Should print "Pre-flight 1 : common sync state ✓" + per-consumer status
without doing anything. Then if dry-run is clean, `--no-mr` to bump
locally without creating MRs and verify each consumer's submodule pin
moved.

☐ **Document in `bin/README.md`** : add a row in the `ship/` table for
`bump-common-everywhere.sh` describing it (cross-repo bulk SHA bump).

☐ **Mention in main `README.md`** : 1-line mention in the "How to update"
section : "to propagate a common change to all 4 consumers in one
command, see `bin/ship/bump-common-everywhere.sh`".

### Asymmetry to resolve at next session start

Per `git submodule status` across consumers (2026-04-26) :

| Consumer | infra/common SHA |
|---|---|
| mirador-service-shared | `d37ec84` |
| mirador-service-java | `4291400` |
| mirador-service-python | `d37ec84` |
| mirador-ui | `d37ec84` |

→ python + ui + shared lag behind java + the latest common commit
(currently [`737ca08`](https://gitlab.com/mirador1/mirador-common/-/commit/737ca08)).
This is **the perfect grandeur-nature test** of `bump-common-everywhere.sh`.
Run it at next session start to align all 4 consumers + smoke-test the
script in one stroke.
