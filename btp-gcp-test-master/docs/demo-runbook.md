# Test runbook: branching and e2e

Run these 9 tests in order. Each one lists the exact commands and what must happen for it to pass. Record each result in the table at the end.

These pipelines haven't run on GitHub yet. If a run doesn't match a test's expected result, stop and fix that before moving on.

## Before you start

- The 3 repo secrets are set.
- The `production` environment exists in the repo, with at least one required reviewer. Without one, test 8 won't stop for approval.
- `git`, `gh`, `curl`, `helm`, `rsync`, `perl` and Node are installed, and `gh` is signed in to `github.tools.sap`.
- Your working copy has no uncommitted changes when you run each test.

Set these in your terminal. Replace `<owner>/<repo>` and the kubeconfig path:

```bash
export GH_HOST=github.tools.sap
export REPO=<owner>/<repo>
export KUBECONFIG=~/path/to/kyma.kubeconfig.yaml
export DEV_URL=https://demoapp-dev.a35836f.stage.kyma.ondemand.com
export QA_URL=https://demoapp-qa.a35836f.stage.kyma.ondemand.com
export PROD_URL=https://demoapp.a35836f.stage.kyma.ondemand.com
export RELEASE=$(date +%Y.%m.%d)
```

Check every run under the repo's **Actions** tab.

## Test 1: Push the pipeline to `develop` and `master`

Replace `<this folder>` with the folder containing this code:

```bash
git clone "https://github.tools.sap/$REPO.git" btp-demo-test
cd btp-demo-test
git switch develop || git switch -c develop
rsync -a --exclude .git "<this folder>/" ./
git add -A
git commit -m "Add post-deploy e2e, rollback and QA gate"
git push -u origin develop
```

Then update `master`. If it doesn't exist yet, run `git push origin develop:master` instead:

```bash
gh pr create --repo "$REPO" --base master --head develop --title "Add e2e pipeline" --body "Add e2e pipeline"
gh pr merge develop --repo "$REPO" --merge
```

**Pass when:**
- **Deploy – dev** and **Deploy – qa** are both green.
- `curl -s "$DEV_URL/version"` prints the `develop` commit from `git rev-parse origin/develop`.
- `curl -s "$QA_URL/version"` prints the `master` commit from `git rev-parse origin/master`, after `git fetch`.

## Test 2: A PR runs CI and doesn't deploy

```bash
git switch develop && git pull
git switch -c feature/demo-change
echo "Demo change." >> README.md
git commit -am "Demo change"
git push -u origin feature/demo-change
gh pr create --repo "$REPO" --base develop --head feature/demo-change --title "Demo change" --body "Demo"
```

**Pass when:**
- **CI** is green on the PR.
- No **Deploy – dev** run started.
- `curl -s "$DEV_URL/version"` hasn't changed.

## Test 3: Merging to `develop` deploys to dev and runs e2e

```bash
gh pr merge feature/demo-change --repo "$REPO" --merge --delete-branch
git switch develop && git pull
```

**Pass when:**
- **Deploy – dev** shows Build & Test, Deploy, APIRule + smoke and e2e all green, and Rollback skipped.
- The e2e log ends with `Test Execution ===> SUCCESS`.
- The run has an `e2e-results-dev` artifact.
- `curl -s "$DEV_URL/version"` prints the same commit as `git rev-parse HEAD`.

## Test 4: A bug fails e2e and dev rolls back

This bug passes the unit tests and the smoke test. It only appears in the deployed image, which sets `NODE_ENV=production`. **Don't merge this branch.**

**Terminal 1:** watch the live version. Leave it running.

```bash
while true; do printf '%s  ' "$(date +%T)"; curl -s -m 5 "$DEV_URL/version"; echo; sleep 5; done
```

**Terminal 2:** push the bug.

```bash
git switch develop && git pull
git rev-parse HEAD      # the version rollback must restore
git switch -c testing/rollback-demo
perl -pi -e "s/process\.env\.APP_VERSION \|\| 'unknown'/process.env.NODE_ENV === 'production' ? 'broken' : (process.env.APP_VERSION || 'unknown')/" server.js
npm test
git commit -am "Rollback demo: bug only visible once deployed"
git push -u origin testing/rollback-demo
```

**Pass when:**
- `npm test` passes.
- **Deploy – dev** shows Build & Test, Deploy and APIRule + smoke green, **e2e red**, Rollback green, and the whole run red.
- The e2e log shows `expected 'broken' to deeply equal '<commit>'`.
- The Rollback log ends with `Rolled back hello-world in default to version <develop commit>`.
- Terminal 1 goes from the `develop` commit to `broken`, then back to the `develop` commit.
- `helm history hello-world -n default` shows a newest revision with status `deployed` and description `Rollback to <n>`.

Clean up, and stop Terminal 1 with `Ctrl+C`:

```bash
git switch develop
git branch -D testing/rollback-demo
git push origin --delete testing/rollback-demo
```

## Test 5: Merging to `master` deploys to QA and runs e2e

```bash
gh pr create --repo "$REPO" --base master --head develop --title "Promote to QA" --body "Promote to QA"
gh pr merge develop --repo "$REPO" --merge
```

**Pass when:**
- **Deploy – qa** is green, with Rollback skipped.
- `curl -s "$QA_URL/version"` prints the new `master` commit.

## Test 6: A release candidate deploys to QA and runs e2e

```bash
git switch master && git pull
./scripts/cut-release-candidate.sh "$RELEASE"
```

**Pass when:**
- A `rel.<date>` branch exists.
- **Deploy – qa** is green on that branch.

Wait for this run to finish before test 8.

## Test 7: A commit with no QA run can't reach prod

```bash
git switch develop && git pull
git switch -c v2026.01.01
git push -u origin v2026.01.01
```

**Pass when:**
- **Deploy – prod** is red at *QA passed for this commit*.
- The log shows `No successful QA run for <commit> on rel.2026.01.01`.
- *Deploy* is skipped and no approval is requested.
- `curl -s "$PROD_URL/version"` hasn't changed.

Clean up:

```bash
git switch develop
git branch -D v2026.01.01
git push origin --delete v2026.01.01
```

## Test 8: A commit that passed QA reaches prod after approval

```bash
./scripts/cut-release.sh "$RELEASE"
```

The run stops and waits for review. A required reviewer then approves it in the Actions run.

**Pass when:**
- The log shows `QA passed for <commit> on rel.<date>`.
- The run waits for approval before *Deploy* starts.
- After approval, **Deploy – prod** is green.
- `curl -s "$PROD_URL/version"` prints the same commit as `git rev-parse "origin/rel.$RELEASE"`.

## Test 9: A hotfix goes through `master`, QA and prod

```bash
git switch master && git pull
git switch -c hotfix/demo-fix
echo "Hotfix demo." >> README.md
git commit -am "Hotfix demo"
git push -u origin hotfix/demo-fix
gh pr create --repo "$REPO" --base master --head hotfix/demo-fix --title "Hotfix demo" --body "Hotfix demo"
gh pr merge hotfix/demo-fix --repo "$REPO" --merge --delete-branch
git switch master && git pull
./scripts/cut-release-candidate.sh "$RELEASE" 1
```

Wait for **Deploy – qa** to go green on `rel.<date>-hotfix.1`, then run:

```bash
./scripts/cut-release.sh "$RELEASE" 1
```

A required reviewer then approves it.

**Pass when:**
- **CI** is green on the PR.
- **Deploy – qa** is green on `rel.<date>-hotfix.1`.
- **Deploy – prod** is green on `v<date>-hotfix.1`.
- `curl -s "$PROD_URL/version"` prints the same commit as `git rev-parse "origin/rel.$RELEASE-hotfix.1"`.

## Results

| Test | Proves | Passed? | Run link | Date |
|---|---|---|---|---|
| 1 | Pipeline is live on both branches | | | |
| 2 | A PR runs CI and doesn't deploy | | | |
| 3 | `develop` deploys to dev, then e2e runs | | | |
| 4 | Failed e2e rolls back dev | | | |
| 5 | `master` deploys to QA, then e2e runs | | | |
| 6 | `rel.*` deploys to QA, then e2e runs | | | |
| 7 | A commit with no QA pass is blocked from prod | | | |
| 8 | A commit that passed QA reaches prod after approval | | | |
| 9 | Hotfix path works | | | |

## If a test fails

| What you see | What to do |
|---|---|
| `Could not install Newman` | The runner can't reach npm. Point npm at the internal registry, or install Newman on the runner. |
| Certificate error in e2e | The runner doesn't trust the certificate. Add the CA with Newman's `--ssl-extra-ca-certs`. Don't use `--insecure`. |
| e2e fails on `POST is not successful` | Check `apirule.methods` in `helm/demoapp/values.yaml`. Only `GET` should be listed. |
| *Deploy* is red and Rollback is skipped | Expected: `--atomic` has already reverted it. Check the pod events and the `hello-world-registry` pull secret. |
| `nothing to roll back to` | It's the first deploy of that release. Deploy a good version, then repeat the test. |
| `No successful QA run` in test 8 or 9 | QA failed or hadn't finished. Wait for a green `rel.*` run, then re-run the prod run. |
| Prod deployed without approval | Add a required reviewer to the `production` environment. |
| `A branch named ... already exists` from a cut script | That release was already cut. Set `RELEASE` to a new `YYYY.MM.DD` value. |
