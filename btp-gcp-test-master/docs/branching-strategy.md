# Branching strategy

How a change travels from a topic branch to production in this repository, and what
each branch name causes to happen. 

## The contract

| Branch | Workflow | Environment | Namespace | Image repository | Gate |
|---|---|---|---|---|---|
| `feature/**`, `bugfix/**`, `hotfix/**`, any PR | `ci.yaml` | none | — | — | build + test only, never deploys |
| `develop` | `deploy-dev.yaml` | dev | `default` | `btp-gcp-test-dev` | none |
| `testing/**` | `deploy-dev.yaml` | dev | `default` | `btp-gcp-test-dev` | none |
| `master` | `deploy-qa.yaml` | qa | `demoapp-qa` | `btp-gcp-test-qa` | none |
| `rel.YYYY.MM.DD[-hotfix.N]` | `deploy-qa.yaml` | qa | `demoapp-qa` | `btp-gcp-test-qa` | none |
| `vYYYY.MM.DD[-hotfix.N]` | `deploy-prod.yaml` | prod | `demoapp-prod` | `btp-gcp-test-prod` | this commit passed QA, then `production` environment, required reviewer |

All three environments live in **one** Kyma cluster — shoot `a35836f`, stage — reached
with a single `GCP_KUBECONFIG_B64` secret. They are separated by namespace, not by
subaccount.

```mermaid
flowchart LR
    subgraph branches["Branches"]
        direction TB
        T["feature/** &middot; bugfix/**<br/>hotfix/** &middot; any PR"]
        TEST["testing/**"]
        D["develop"]
        M["master"]
        RC["rel.YYYY.MM.DD<br/>[-hotfix.N]"]
        V["vYYYY.MM.DD<br/>[-hotfix.N]"]
    end

    subgraph flows["Workflows"]
        direction TB
        CI["ci.yaml"]
        WDEV["deploy-dev.yaml"]
        WQA["deploy-qa.yaml"]
        WPROD["deploy-prod.yaml"]
    end

    NONE(["no deploy<br/>build + test only"])
    GATE["QA check, then PAUSE &mdash; environment: production<br/>required reviewer must approve"]
    subgraph cluster["One Kyma cluster &mdash; shoot a35836f (stage), secret GCP_KUBECONFIG_B64"]
        direction TB
        DEV[["ns default<br/>btp-gcp-test-dev"]]
        QA[["ns demoapp-qa<br/>btp-gcp-test-qa"]]
        PROD[["ns demoapp-prod<br/>btp-gcp-test-prod"]]
    end

    T --> CI --> NONE
    TEST --> WDEV
    D --> WDEV --> DEV
    M --> WQA
    RC --> WQA
    WQA --> QA
    V --> WPROD --> GATE --> PROD

    classDef branch fill:#eef4ff,stroke:#4472c4,color:#1a1a1a
    classDef topic fill:#f4f4f4,stroke:#8a8a8a,color:#1a1a1a
    classDef flow fill:#f4f4f4,stroke:#8a8a8a,color:#1a1a1a
    classDef ns fill:#e8f5e9,stroke:#43a047,color:#1a1a1a
    classDef gate fill:#fff4e5,stroke:#e08600,color:#1a1a1a
    classDef nodep fill:#f7f7f7,stroke:#bdbdbd,color:#555
    class D,M,RC,V branch
    class T,TEST topic
    class CI,WDEV,WQA,WPROD flow
    class DEV,QA,PROD ns
    class GATE gate
    class NONE nodep
    style branches fill:#ffffff,stroke:#cccccc,color:#666666
    style flows fill:#ffffff,stroke:#cccccc,color:#666666
    style cluster fill:#ffffff,stroke:#cccccc,color:#666666
```

## Scenario 1 — everyday feature work

The normal path. A topic branch off `develop`, a PR, then promotion through each
environment. Nothing reaches production without passing through QA twice: once from
`master`, once from the frozen release candidate.

```mermaid
%%{init: {"gitGraph": {"mainBranchName": "develop"}, "themeVariables": {"git0": "#4472c4", "git1": "#8a8a8a", "git2": "#8a6fd6", "git3": "#e08600", "git4": "#43a047", "gitBranchLabel0": "#ffffff", "gitBranchLabel1": "#ffffff", "gitBranchLabel2": "#ffffff", "gitBranchLabel3": "#ffffff", "gitBranchLabel4": "#ffffff", "gitBranchLabel5": "#ffffff", "gitBranchLabel6": "#ffffff"}}}%%
gitGraph
   commit id: "develop"
   branch feature/checkout-flow
   commit id: "feat: checkout"
   commit id: "address review"
   checkout develop
   merge feature/checkout-flow tag: "DEV (ns default)"
   branch master
   commit id: "promote to master" tag: "QA (ns demoapp-qa)"
   branch rel.2026.10.13
   commit id: "freeze candidate" tag: "QA (ns demoapp-qa)"
   branch v2026.10.13
   commit id: "cut release" tag: "PROD - approval required"
```

1. Branch from `develop` as `feature/<name>`. Pushing it runs `ci.yaml`: tests, shell
   syntax, `helm lint` and `helm template` for all three environments, and a Docker
   build that is **not** pushed. Nothing deploys.
2. Open a PR into `develop`. The same `ci.yaml` runs.
3. Merge. `deploy-dev.yaml` fires and deploys to namespace `default`.
4. Merge `develop` into `master`. `deploy-qa.yaml` deploys to `demoapp-qa`.
5. Freeze a candidate: `./scripts/cut-release-candidate.sh 2026.10.13` branches
   `rel.2026.10.13` from `master` and pushes it. QA redeploys from the frozen branch and runs
   e2e. Later pushes to `master` redeploy QA too, but the release gate checks this commit's
   own QA run, so that doesn't affect the release.
6. Promote: `./scripts/cut-release.sh 2026.10.13` branches `v2026.10.13` from
   `origin/rel.2026.10.13`. `deploy-prod.yaml` checks that this commit passed QA, then
   **waits** for a reviewer on the `production` environment. If you cut it before the
   `rel.*` run has finished, the check fails; re-run the prod run once QA is green.
7. Merge the release branch back into `master` and `develop`.

## Scenario 2 — hotfix on a released version

Hotfixes reuse the same branch shapes with a `-hotfix.N` suffix. The fix goes to
`master` first so it is never lost, then follows the same QA-then-prod path. The hotfix
candidate is cut from `master`, so any unreleased work on `master` ships with it.

```mermaid
%%{init: {"gitGraph": {"mainBranchName": "develop"}, "themeVariables": {"git0": "#4472c4", "git1": "#8a6fd6", "git2": "#e08600", "git3": "#43a047", "git4": "#8a8a8a", "git5": "#e08600", "git6": "#43a047", "gitBranchLabel0": "#ffffff", "gitBranchLabel1": "#ffffff", "gitBranchLabel2": "#ffffff", "gitBranchLabel3": "#ffffff", "gitBranchLabel4": "#ffffff", "gitBranchLabel5": "#ffffff", "gitBranchLabel6": "#ffffff"}}}%%
gitGraph
   commit id: "develop"
   branch master
   commit id: "master"
   branch rel.2026.10.13
   commit id: "RC"
   branch v2026.10.13
   commit id: "v2026.10.13 live" tag: "PROD"
   checkout master
   branch hotfix/null-pointer
   commit id: "fix: null pointer"
   checkout master
   merge hotfix/null-pointer tag: "QA"
   branch rel.2026.10.13-hotfix.1
   commit id: "freeze hotfix RC" tag: "QA"
   branch v2026.10.13-hotfix.1
   commit id: "ship hotfix" tag: "PROD - approval required"
```

```bash
# after the fix is merged to master
./scripts/cut-release-candidate.sh 2026.10.13 1   # rel.2026.10.13-hotfix.1 -> QA
./scripts/cut-release.sh           2026.10.13 1   # v2026.10.13-hotfix.1    -> PROD (gated)
```

Both scripts validate their arguments: the date must be `YYYY.MM.DD` and the hotfix
number an integer, and `cut-release.sh` refuses to run if the matching `rel.*` branch
does not exist on the remote.

## Scenario 3 — experimental work on the dev cluster

`testing/**` branches deploy to dev exactly as `develop` does. This is a deliberate
escape hatch for trying something on a real cluster without merging it.

Two consequences worth knowing:

- `testing/**` and `develop` share namespace `default` and the Helm release name
  `hello-world`. **They overwrite each other.** Pushing `testing/foo` replaces whatever
  `develop` last deployed, and the next push to `develop` replaces it back.
- A second push waits for the running deploy to finish, so e2e or rollback is never
  cancelled halfway.

Use a `testing/**` branch when you want the dev cluster to yourself for a moment, and
tell whoever else is using dev.

## Scenario 4 — what a deploy does

Dev and QA share `wf-deploy-e2e.yaml`:

```mermaid
flowchart LR
    B["Build &amp; Test<br/>push :GITHUB_SHA"] --> D["Deploy<br/>helm upgrade --atomic"]
    D --> S["APIRule + smoke"] --> E["e2e<br/>scripts/runTest.sh"] --> OK(["green"])
    S -. "failure" .-> R["Rollback<br/>to the last deployed revision"]
    E -. "failure" .-> R
    R --> RED(["red"])
```

| Step that fails | What happens to the running service |
|---|---|
| Tests, placeholder check, image build | Nothing deployed yet. Previous release untouched. |
| `helm upgrade --atomic` | Helm reverts automatically. |
| APIRule wait, smoke test or e2e | Automatic rollback, then the run goes red. |

The e2e suite is a Postman collection, `e2e/demoapp.postman_collection.json`, run by Newman
against the public URL. It follows the FIPC `e2e-test` pattern, and exits 99 when tests fail.
Results are uploaded as a run artifact. Any failure in the e2e job triggers a rollback,
including one that isn't a test failure, such as Newman failing to install.

On a first-ever deploy there's nothing to roll back to, so the release stays up for debugging.

To see a rollback, push a bug that only shows once deployed to a `testing/**` branch, and
don't merge it. For example, in `server.js`:

```js
'/version': process.env.NODE_ENV === 'production' ? 'broken' : (process.env.APP_VERSION || 'unknown')
```

Unit tests and the smoke test pass, because they don't depend on this. e2e fails, and
`/version` returns to the previous commit. A bug in `/` or `/healthz` won't show this:
unit tests stop it before it deploys.

Prod (`deploy-prod.yaml`) has no e2e and no automatic rollback:

1. **QA gate:** this commit must have a successful `deploy-qa.yaml` run on the matching
   `rel.*` branch. A run that rolled back counts as failed. There's no override.
2. **Approval:** a reviewer approves on the `production` environment.
3. **Deploy:** the image QA tested is copied to the prod repository, not rebuilt, then
   deployed and smoke tested.

If a prod smoke test fails, a person decides whether to roll back:

```bash
helm history hello-world -n demoapp-prod
helm rollback hello-world <revision> -n demoapp-prod --wait
```

## Scenario 5 — a PR that is never merged

`ci.yaml` runs on every PR into `develop`, `master`, or a `rel.*` branch, and on every
push to `feature/**`, `bugfix/**` and `hotfix/**`. It runs tests, `bash -n` over the
scripts, `helm lint` plus `helm template` for all three environments, and a Docker build
with `push: false`.

No registry login, no cluster credentials, no deploy. A PR cannot publish an image or
touch a namespace, by construction.

## Reference

### Triggers, exactly as written

```yaml
# ci.yaml
pull_request: [develop, master, 'rel.*']
push:         ['feature/**', 'bugfix/**', 'hotfix/**']

# deploy-dev.yaml
push: [develop, 'testing/**']

# deploy-qa.yaml
push: [master, 'rel.[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]',
               'rel.[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]-hotfix.[0-9]*']

# deploy-prod.yaml
push: ['v[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]',
       'v[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]-hotfix.[0-9]*']
```

