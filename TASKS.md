# Tasks — `mirador-common`

Open work only. Per `~/.claude/CLAUDE.md` rules : universal cross-repo
items only ; per-repo items live in each consumer's own `TASKS.md`.

---

## 🔧 Cross-repo bump automation

☐ **`bin/ship/bump-common-everywhere.sh`** — script qui bump le SHA de
`infra/common/` dans les 4 consumers en parallèle (java + python + ui +
shared) après un push sur `mirador-common/main`.

**Pourquoi** : la pattern α flat (cf. [ADR-0060](docs/adr/0060-flat-vs-transitive-submodule-inheritance.md))
implique que chaque consumer pin son propre SHA de common. Quand on
patch common (fix critique, nouvelle option d'un script universel), il
faut bumper chaque consumer manuellement — 4 séquences de
`cd <repo> && cd infra/common && git pull && cd .. && git add infra/common
&& git commit + push + MR + auto-merge`. Pénible si répétitif.

**Solution** : script qui automatise pour les 4 repos en une commande.
Pattern similaire à `bin/ship/renovate-sync.sh` (qui sync `renovate.json`
across repos).

### Acceptance criteria

- [ ] **Localisation** : `mirador-common/bin/ship/bump-common-everywhere.sh`
- [ ] **Détection auto des consumers** : lire `consumers.txt` ou un argument
      explicite. Default : `mirador-service-java`, `mirador-service-python`,
      `mirador-ui`, `mirador-service-shared`.
- [ ] **Pre-flight checks** :
  - Common's main est-il à jour avec origin ? (refuser si non)
  - Tous les consumers existent localement à un path connu ? (skip si absent)
  - Tous les consumers ont une branche `dev` propre (pas de uncommitted) ?
- [ ] **Pour chaque consumer** : `cd <repo> && git switch dev &&
      git pull --rebase && cd infra/common && git pull origin main &&
      cd .. && git add infra/common && git commit -m "chore(submodule): bump common SHA" && git push`.
- [ ] **MR auto-creation** (optionnel via flag `--mr`) : `glab mr create
      --auto-merge` pour chaque consumer après le push.
- [ ] **Dry-run** (`--dry-run`) : montre les bumps qui seraient faits sans rien commiter.
- [ ] **Rollback safety** : si un consumer fail, les autres déjà bumpés
      ne sont pas rollbackés (le script log clairement où ça a planté).
- [ ] **Output** : un tableau récap final genre `✓ java bumped, ✓ python
      bumped, ✗ ui FAILED (uncommitted changes), ✓ shared bumped`.
- [ ] Tests : un dry-run sur les 4 repos doit passer sans erreur.
- [ ] Documenter dans `bin/README.md` (la table `ship/`).
- [ ] Mention dans le README principal du repo.

### Quand l'utiliser (pas systématiquement)

- ✅ Patch critique d'un script universel → propagation rapide à tous
- ✅ Nouvelle option d'un script qu'on veut tous voir
- ❌ Petit fix local qui n'affecte pas les consumers actifs (laisser α
  jouer son rôle d'isolation)
- ❌ Refactor qui change l'API d'un script (les consumers doivent
  d'abord adapter leur usage avant de bumper — une cascade automatique
  les casserait)

### Pourquoi pas un script `git submodule sync` natif

`git submodule sync` met à jour les URLs des submodules (rare), pas leur
SHA pin. `git submodule update --remote` bump UN repo à la fois et
nécessite un `git add + commit` après — il y a 4 répétitions à
automatiser, plus la création de MR. D'où le besoin d'un wrapper bash.

### Lien avec les ADRs

- [ADR-0060](docs/adr/0060-flat-vs-transitive-submodule-inheritance.md) — α
  flat = chaque consumer pin son SHA, ce script aide à les aligner
  rapidement quand voulu
- [ADR-0001](docs/adr/0001-shared-repo-via-submodule.md) — pattern submodule
  général
