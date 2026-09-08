# student-ml-api — MLOps delivery report

Repository: <https://github.com/maazbinusama65-cyber/i221378_mlops_a1>
Registry package: <https://github.com/users/maazbinusama65-cyber/packages/container/package/student-ml-api>

Every value in this document was taken from this repository, its workflow runs and its
registry. Nothing is illustrative.

---

## 1. Pipeline as built

```
feature branch
    -> commits
    -> push
    -> Pull Request
    -> CI (unit tests, Docker build validation)   [publishes nothing]
    -> review
    -> merge into main (merge commit)
    -> semantic version tag  v1.1.0
    -> Release workflow (test, build, login, tag, push)
    -> ghcr.io/maazbinusama65-cyber/student-ml-api : 1.1.0 / latest / <commit sha>
```

`main` never receives a direct commit. The protection rule was verified by attempting one:

```
$ git commit --allow-empty -m "chore: direct-to-main push attempt (protection test)"
$ git push origin main
remote: - Changes must be made through a pull request.
remote: - 2 of 2 required status checks are expected.
 ! [remote rejected] main -> main (protected branch hook declined)
```

---

## 2. Application and tests (Parts 1–2)

`app.py` is a Flask service. `VERSION` is the single source of truth for the application
version: the application reads it at runtime, and the release workflow refuses to publish if
the file disagrees with the Git tag being released.

| Endpoint | Behaviour |
| --- | --- |
| `GET /health` | Returns `status`, `application`, `application_version`, `model_version` |
| `POST /predict` | Returns `input` and `prediction` (`value * 2`) |

`POST /predict` returns HTTP 400 for a missing `value`, a non-numeric `value`, and a request
body that is not a JSON object. Booleans are rejected explicitly, because `bool` is a
subclass of `int` in Python and would otherwise be accepted as a number.

Six automated tests in `tests/test_app.py`:

1. `test_health_reports_healthy_status`
2. `test_health_reports_application_and_model_versions`
3. `test_predict_returns_prediction_for_valid_input`
4. `test_predict_rejects_missing_input`
5. `test_predict_rejects_invalid_input`
6. `test_predict_rejects_non_json_body`

`pytest.ini` sets `pythonpath = .` so that a bare `pytest` — which is how CI invokes it —
can import the service from the repository root. Without it, `pytest` collected the suite
but failed at import: `ModuleNotFoundError: No module named 'app'`. `python -m pytest` hid
the problem locally because that form prepends the working directory to `sys.path`.

---

## 3. Pull requests (Parts 3–4, 8, 18)

| PR | Branch | Merge commit | Purpose |
| --- | --- | --- | --- |
| [#1](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/1) | `feature/prediction-api` | `90d93d7` | Service, tests, Dockerfile, CI and release workflows (1.0.0) |
| [#2](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/2) | `feature/model-metadata` | `294e960` | Model metadata on `/health` (1.1.0) |
| [#3](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/3) | `feature/runtime-demonstration` | `58ce844` | On-demand runtime demonstration workflow |
| [#4](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/4) | `fix/dockerfile-layer-ordering` | `a076738` | Docker layer-ordering defect found by the cache exercise |
| [#5](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/5) | `fix/demonstration-exit-status` | `e1a9042` | Evidence reporting fix (incomplete) |
| [#6](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/6) | `fix/login-status-reporting` | `138e091` | Correct fix for the same reporting defect |

Every pull request carries Summary, Changes, Testing Performed, Docker Impact and a
completed Checklist. Each was opened before its work reached `main`, and each was reviewed
on the pull request before merging.

### Merge strategy: merge commit

All six were merged with a **merge commit**, and the repository is configured to allow only
that strategy (`allow_squash_merge: false`, `allow_rebase_merge: false`).

The reason is evidence. Squashing would collapse each branch into one commit and discard the
individual `feat:` / `test:` / `build:` / `ci:` / `fix:` steps — precisely the record that
shows how the work was actually done. A merge commit keeps every commit reachable from
`main` and adds an explicit integration point per pull request, which is also the anchor the
traceability chain in section 8 uses. The cost of merge commits is a non-linear history,
which is acceptable at this size; on a busy repository with many concurrent branches the
trade-off would be worth revisiting.

---

## 4. Branch protection (Part 7)

Applied to `main` and verified live:

| Setting | Value | Why |
| --- | --- | --- |
| Require a pull request before merging | on | Nothing enters `main` unreviewed |
| Required approving reviews | 0 | GitHub does not let an author approve their own pull request; a non-zero count would make a single-maintainer repository permanently unmergeable. Reviews are still recorded on every pull request |
| Dismiss stale approvals on new commits | on | An approval describes a specific diff, not a branch |
| Require status checks to pass | on — `Unit tests`, `Docker build validation` | A red pipeline cannot be merged |
| Require branches to be up to date | on | Prevents a semantic conflict passing CI against a stale base |
| Require conversation resolution | on | Review comments cannot be merged past silently |
| Include administrators | **on** | Without it, the rule is advisory for exactly the account most likely to bypass it |
| Force pushes | blocked | Preserves the audit trail |
| Branch deletion | blocked | `main` cannot be removed |

Two independent confirmations that the rule is real, not cosmetic:

- the direct push in section 1 was rejected;
- the merge of #4 was refused by the API while a required check was still running:
  `Required status check "Unit tests" is in progress. (HTTP 405)`.

---

## 5. CI and release workflows (Parts 5, 14, 15, 22)

| | `ci.yml` | `release.yml` |
| --- | --- | --- |
| Trigger | pull requests to `main`, pushes to `feature/**`, `fix/**`, `docs/**` | push of a `v*.*.*` tag only |
| Permissions | `contents: read` | `contents: write`, `packages: write` |
| Jobs | `Unit tests` -> `Docker build validation` | `Unit tests` -> `Build and publish image` |
| Registry | never authenticates | authenticates with the run-scoped `GITHUB_TOKEN` |
| Publishes | nothing | `1.1.0`, `latest`, `<short sha>` |

CI builds the image and runs a smoke test that curls `/health` inside the freshly built
container, then throws the image away. The Docker build validation job runs `needs: test`,
so a failing test suite means the build job never runs and the pull request cannot be merged.

### Why publishing from every pull request is undesirable

A pull request is a proposal, not a decision. Publishing from one would mean:

- **Unreviewed artefacts become deployable.** Anyone able to open a pull request could put
  an image into the registry that a deployment tool might pick up.
- **Credentials spread to untrusted contexts.** A pull request workflow that logs in to a
  registry needs a write credential, which becomes reachable from code the maintainers have
  not yet read. Keeping publish rights in the tag-triggered workflow keeps the write
  credential out of every pull request run.
- **Version identity stops meaning anything.** A registry that accumulates an image per
  pull request revision cannot answer "what is 1.1.0?" — the tag would have been reused and
  overwritten many times.
- **Cost and noise.** Most pull request revisions are never released; storing each one is
  waste.

Validation is cheap and should happen on every proposal; publication is a commitment and
should happen once, from an approved commit, with a version attached.

### Version derivation (Part 15 constraint)

The version is derived from the tag and never hard-coded:

```bash
TAG="${GITHUB_REF_NAME}"   # v1.1.0
VERSION="${TAG#v}"         # 1.1.0
```

The workflow then refuses to continue unless the `VERSION` file matches:

```bash
FILE_VERSION="$(cat VERSION)"
if [ "${FILE_VERSION}" != "${VERSION}" ]; then exit 1; fi
```

That guard is what stops an image labelled `1.1.0` from serving a `/health` response that
reports something else.

---

## 6. Deliberate CI failure (Part 6)

Performed on `feature/prediction-api`, on the open pull request, before merging.

**Broken assertion pushed** — commit `8dbef07`, run
[34256277483](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34256277483):

```
tests/test_app.py::test_health_reports_healthy_status FAILED             [ 20%]
>       assert data["status"] == "wrong"
E       AssertionError: assert 'healthy' == 'wrong'
FAILED tests/test_app.py::test_health_reports_healthy_status
========================= 1 failed, 4 passed in 0.19s ==========================
```

Job results for that run: `Unit tests` **failure**, `Docker build validation` **skipped**,
run conclusion **failure**. The pull request was not mergeable.

**Fix pushed** — commit `1f9bc91` (`fix: correct health endpoint test`), run
[34256405058](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34256405058):
`Unit tests` success, `Docker build validation` success, run conclusion **success**.

---

## 7. Container image (Parts 9–11, 23)

`Dockerfile` highlights: pinned `python:3.12.7-slim-bookworm` (never `latest`), `WORKDIR
/app`, dependency layer installed before application source, `pip install --no-cache-dir`,
unprivileged `appuser` (uid 10001), `EXPOSE 5000`, a `HEALTHCHECK`, OCI provenance labels
and a gunicorn `CMD` bound to `0.0.0.0`. `.dockerignore` excludes `.git`, `.github`,
`__pycache__`, `*.pyc`, `.venv`, `.env`, tests, docs and the dev requirements file.

Runtime facts, from run
[34259514842](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34259514842):

| Item | Value |
| --- | --- |
| Container ID | `b976f313464f0e01a17cb1bf364926efb8b2c025967e51d67e1f0f124870bb52` |
| Image ID | `sha256:fb0c1be12d10a8e89c549f3af419cd7c5f1f25b933f35900a5c91b431cbe70b1` |
| Exposed port | `{"5000/tcp":{}}` |
| Published ports | `5000/tcp -> 0.0.0.0:5000` |
| Running command | `["gunicorn","--bind","0.0.0.0:5000","--workers","2","--access-logfile","-","app:app"]` |
| Working directory | `/app` |
| Runtime user | `appuser` |

`docker exec` inside the running container confirms both: `whoami: appuser`, `pwd: /app`.

Health and prediction responses from that container:

```json
{"application":"student-ml-api","application_version":"1.1.0","model_version":"model-1","status":"healthy"}
{"input":10,"prediction":20}
```

A `POST /predict` with `{}` returns `HTTP 400`.

### OCI metadata (Part 23)

`docker image inspect` on the built image:

```json
{"org.opencontainers.image.created":"2026-09-08T17:50:46Z",
 "org.opencontainers.image.description":"Minimal ML inference service",
 "org.opencontainers.image.revision":"138e091dbe161692a2bf34cdd1c4054a21b39e14",
 "org.opencontainers.image.source":"https://github.com/maazbinusama65-cyber/i221378_mlops_a1",
 "org.opencontainers.image.title":"student-ml-api",
 "org.opencontainers.image.version":"1.1.0"}
```

Given a running container and nothing else, `revision` identifies the exact commit that
produced it and `source` identifies where to find that commit. Here `138e091` is the commit
of `main` that the demonstration run built from, which is the merge commit of
[#6](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/6).

The images published to the registry carry the same labels, set from the released commit.
Read back from the GHCR manifest and config blob:

| Published tag | `image.version` | `image.revision` | Merge commit of |
| --- | --- | --- | --- |
| `1.0.0` | `1.0.0` | `90d93d7e1b31dd08ae8488ca733da0715b147454` | [#1](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/1) |
| `1.1.0` | `1.1.0` | `294e960b80619b33b14d9eb8088f530cd6d2ceb5` | [#2](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/2) |

Each published artefact therefore names, from inside itself, the commit that produced it —
closing the chain in section 8 from the artefact end as well as from the source end.

---

## 8. Registry, versions and traceability (Parts 12, 13, 16, 19, 21, 24)

Registry: `ghcr.io/maazbinusama65-cyber/student-ml-api` (public).

| Tag | Digest |
| --- | --- |
| `1.0.0` | `sha256:af4ebd6d2bd246bd2f113ae7b015a711062e3b1b6313555fd920e6d36d0cb1e5` |
| `90d93d7` | `sha256:af4ebd6d2bd246bd2f113ae7b015a711062e3b1b6313555fd920e6d36d0cb1e5` |
| `1.1.0` | `sha256:6e7ce2289ebb6c1f15f4347d740a04601c8bb2cf166ac30f2b6a6969bf2ef621` |
| `294e960` | `sha256:6e7ce2289ebb6c1f15f4347d740a04601c8bb2cf166ac30f2b6a6969bf2ef621` |
| `latest` | `sha256:6e7ce2289ebb6c1f15f4347d740a04601c8bb2cf166ac30f2b6a6969bf2ef621` |

`latest` and `1.1.0` resolve to the same digest, so `latest -> 1.1.0` is confirmed by
content and not merely by name, while `1.0.0` remains available under its own digest.

### Traceability chain for 1.1.0 (Part 21)

```
Pull Request     #2
Merge Commit     294e960b80619b33b14d9eb8088f530cd6d2ceb5
Git Tag          v1.1.0
Release Run      34257397843
Docker Image     ghcr.io/maazbinusama65-cyber/student-ml-api:1.1.0
Also tagged      latest, 294e960
Image Digest     sha256:6e7ce2289ebb6c1f15f4347d740a04601c8bb2cf166ac30f2b6a6969bf2ef621
```

The same chain for 1.0.0: PR #1 -> `90d93d7e1b31dd08ae8488ca733da0715b147454` -> `v1.0.0` ->
run 34256833820 -> `:1.0.0` -> `sha256:af4ebd6d…d0cb1e5`.

### Benefit of the commit-SHA tag (Part 24)

`1.1.0` says which release an image belongs to; `294e960` says which source tree produced
it, without depending on anyone's release discipline. That matters when:

- an incident starts with a running container and the question is "what code is this?" —
  the SHA tag answers it directly and can be checked out;
- a release tag is moved, re-cut or reused; the commit tag cannot be, because a commit is
  immutable;
- two images built from the same version need to be told apart, for instance a re-run of a
  release after a workflow fix.

Version tags are for humans deciding what to deploy. Commit tags are for engineers
determining what is deployed.

---

## 9. Artefact reproducibility and rollback (Parts 17, 20)

From run
[34259514842](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34259514842),
in order: the locally built image was deleted (`docker rmi`), the listing confirmed no
`student-ml-api` image remained, the published image was pulled back and run, and it
answered `/health` correctly. The pull resolved to
`ghcr.io/maazbinusama65-cyber/student-ml-api@sha256:6e7ce22…f2ef621` — the identical digest
that the release workflow pushed, so the artefact that ran was bit-for-bit the artefact that
was built, not a rebuild of the same source.

**Rollback**, with no source change and no rebuild:

```
docker rm -f student-ml-api-1-1-0
docker pull ghcr.io/maazbinusama65-cyber/student-ml-api:1.0.0
docker run -d --name student-ml-api-1-0-0 -p 5000:5000 ghcr.io/maazbinusama65-cyber/student-ml-api:1.0.0
curl http://localhost:5000/health
{"application":"student-ml-api","status":"healthy","version":"1.0.0"}
```

The rolled-back container answers with the **1.0.0 health contract** — the old `version`
field, not `application_version`/`model_version`. That is proof the running artefact is
genuinely the older build rather than a relabelled current one.

### Why this beats `git clone` + `pip install` + `python app.py`

- **It restores an artefact, not a recipe.** The image is the exact bytes that were tested.
  Re-running `pip install` resolves dependencies again, at a different moment, against a
  registry whose contents move; a transitive dependency can publish a new release between
  the original build and the rollback and change behaviour, even from an unchanged commit.
- **It is one step, and it is the step already practised.** Pull and run — the same commands
  used for a normal deploy. A source-based rollback is a multi-step procedure exercised only
  during incidents, which is when it is least safe to discover it is broken.
- **It is fast and bounded.** Cached layers make the pull near-instant, and the outcome is
  known in advance. A rebuild's duration and result are not.
- **It does not need a build toolchain in production.** No compiler, no source tree, no
  package index reachable from the production host.
- **It is reversible.** `1.1.0` is still in the registry, so rolling forward again after a
  fix is another pull.

---

## 10. Docker layer cache (Part 25)

Both rebuilds below are from run
[34259514842](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34259514842).

**Changing only `app.py` — 4 of 6 layers reused, dependencies untouched:**

```
#6 [2/6] RUN useradd --create-home --uid 10001 appuser          CACHED
#7 [3/6] WORKDIR /app                                            CACHED
#8 [4/6] COPY requirements.txt ./                                CACHED
#9 [5/6] RUN pip install --no-cache-dir -r requirements.txt      CACHED
#10 [6/6] COPY --chown=appuser:appuser VERSION app.py ./          rebuilt
```

**Changing `requirements.txt` — 2 of 6 layers reused, dependencies reinstalled:**

```
#6 [2/6] RUN useradd --create-home --uid 10001 appuser          CACHED
#7 [3/6] WORKDIR /app                                            CACHED
#8 [4/6] COPY requirements.txt ./                                rebuilt
#9 [5/6] RUN pip install --no-cache-dir -r requirements.txt      rebuilt
      Installing collected packages: packaging, MarkupSafe, itsdangerous, click,
      blinker, Werkzeug, Jinja2, gunicorn, Flask
#10 [6/6] COPY --chown=appuser:appuser VERSION app.py ./          rebuilt
```

### Why the split ordering is preferable

```dockerfile
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
```

is better than

```dockerfile
COPY . .
RUN pip install -r requirements.txt
```

because a layer is invalidated when its inputs change, and every layer after an invalidated
one is rebuilt too. In the second form the input to the `COPY` is the whole source tree, so
any change to any file — a one-character edit to `app.py`, a README typo — invalidates it
and forces a full dependency reinstall. In the first form the input to the dependency layer
is `requirements.txt` alone, so it is reused until the dependencies genuinely change. Since
application code changes constantly and dependencies rarely, this converts most builds from
a full reinstall into a file copy. In CI/CD that difference is paid on every pull request
revision and every release.

### A defect this exercise actually found

The first demonstration run
([34258135845](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34258135845))
showed an application-only rebuild reusing just **2** layers and reinstalling all nine
packages, despite the correct `COPY`/`RUN` ordering. The cause was the `ARG`/`LABEL` block
sitting *above* the dependency layer. Two of those arguments — `GIT_COMMIT` and
`BUILD_DATE` — change on every build, so the metadata layer was invalidated every time and
took the dependency layer down with it. Correct instruction ordering had been defeated by a
metadata block placed above it.

PR [#4](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/4) moved `ARG`/`LABEL`
below the dependency and source layers and moved `useradd` above them. The measurements at
the top of this section are from after that fix: 4 cached layers instead of 2, and no
reinstall. The general rule: order instructions by how often their inputs change, most
stable first — and remember that build arguments are inputs.

---

## 11. Failure analysis (Part 26)

Five failures were reproduced and diagnosed. The first is from the pull request CI history;
the rest are from the `Runtime demonstration` workflow, which reproduces each fault and its
correction in sequence.

### 11.1 Failed pytest

- **Symptom** — pull request CI red; `Unit tests` failed and `Docker build validation` never
  ran.
- **Root cause** — `test_health_reports_healthy_status` asserted `data["status"] == "wrong"`
  while the endpoint correctly returns `healthy`.
- **Evidence** — run 34256277483: `AssertionError: assert 'healthy' == 'wrong'`;
  `1 failed, 4 passed`; the build job reported `skipped` because it declares `needs: test`.
- **Correction** — restored the assertion (`fix: correct health endpoint test`, `1f9bc91`);
  run 34256405058 green.

### 11.2 Application bound to 127.0.0.1

- **Symptom** — the container runs and the port is published, but requests from the host
  fail: `curl: (56) Recv failure: Connection reset by peer`, exit code 56.
- **Root cause** — gunicorn was started with `--bind 127.0.0.1:5000`. Inside a container,
  loopback is the container's own loopback; the published port forwards to the container's
  external interface, where nothing is listening. Port publishing cannot fix a process that
  refuses connections from outside its own namespace.
- **Evidence** — `docker logs`: `[INFO] Listening at: http://127.0.0.1:5000 (1)`, next to
  the healthy container's `[INFO] Listening at: http://0.0.0.0:5000 (1)`.
- **Correction** — bind to `0.0.0.0`, as the image's `CMD` does; the same request then
  returns the health payload. This is why the `DEFAULT_HOST = "0.0.0.0"` constant in
  `app.py` carries a comment explaining that it is deliberate.

### 11.3 Wrong container port published

- **Symptom** — identical to 11.2 from the client's side: `curl: (56)`, exit code 56.
  Different cause, same surface.
- **Root cause** — `docker run -p 5000:8000` maps host 5000 to container **8000**, while the
  application listens on 5000.
- **Evidence** — `docker port` reports `8000/tcp -> 0.0.0.0:5000`, and
  `docker inspect .Config.ExposedPorts` reports `{"5000/tcp":{},"8000/tcp":{}}`: the port
  the image declares and the port being published are not the same one.
- **Correction** — `-p 5000:5000`; health returns immediately. The lesson is diagnostic:
  when a published port does not respond, `docker port` distinguishes a mapping fault from a
  binding fault, which no amount of application-log reading will.

### 11.4 Missing dependency in the image

- **Symptom** — `docker run` returns, but the container is not running.
- **Root cause** — the image was built from a requirements file listing only `flask`. The
  `CMD` invokes `gunicorn`, which was never installed.
- **Evidence** — `exec: "gunicorn": executable file not found in $PATH`, and
  `docker ps -a` showing the container exited.
- **Correction** — declare every runtime dependency in `requirements.txt`; `gunicorn` is
  pinned there. Because dependencies are pinned and the base image is pinned to a patch
  version, this failure cannot appear later through drift.

### 11.5 Failed Docker build (unresolvable dependency)

- **Symptom** — the build aborts at the dependency layer; the CI job would fail with it.
- **Root cause** — `requirements.txt` referenced a package that does not exist on PyPI.
- **Evidence** —
  `ERROR: Could not find a version that satisfies the requirement this-package-does-not-exist-mlops==9.9.9 (from versions: none)`,
  followed by `docker build exit status: 1`.
- **Correction** — correct the dependency name/version. The point of the exercise is that
  the CI Docker build validation job catches this on the pull request, before merge and long
  before a release.

### 11.6 Invalid registry credentials

- **Symptom** — `docker login` is rejected, and a release job would stop before pushing.
- **Root cause** — an invalid token was presented to `ghcr.io`.
- **Evidence** — `Error response from daemon: Get "https://ghcr.io/v2/": denied: denied`,
  with `docker login exit status: 1`.
- **Correction** — authenticate with the run-scoped `GITHUB_TOKEN`, as `release.yml` does.
  No credential is stored in YAML or in the repository.
- **Note on the evidence itself** — the first two attempts at this step reported
  `exit status: 0` for a login that had visibly failed, because `$?` after a pipeline reports
  the status of the last command (`tail`) and `PIPESTATUS[0]` reports the first (`echo`),
  neither being `docker login`. Fixed in
  [#6](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/pull/6) by running the
  command outside a pipeline. A monitoring step that reports success for a failed command is
  worse than no monitoring, so it is recorded here rather than quietly corrected.

---

## 12. Evidence index

| Requirement | Where |
| --- | --- |
| Failed CI execution | run [34256277483](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34256277483) |
| Successful CI execution | run [34256405058](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34256405058) |
| Successful release execution (1.0.0) | run [34256833820](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34256833820) |
| Successful release execution (1.1.0) | run [34257397843](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34257397843) |
| Container lifecycle, rollback, cache, failures | run [34259514842](https://github.com/maazbinusama65-cyber/i221378_mlops_a1/actions/runs/34259514842) |
| Release tags | `v1.0.0`, `v1.1.0` |
| Registry contents | `1.0.0`, `1.1.0`, `latest`, `90d93d7`, `294e960` |
| Pull requests | #1–#6, all reviewed before merge |

### A note on where the runtime evidence was produced

The container lifecycle, registry round-trip, rollback, cache and failure exercises were run
on a GitHub-hosted runner through the dispatchable `Runtime demonstration` workflow rather
than typed into a local terminal, because the development machine has Windows'
"Virtual Machine Platform" feature disabled and therefore cannot start the Docker engine.

Every command is the one the exercise asks for, and the evidence is arguably stronger for it:
the workflow is re-runnable by anyone with access, the log is timestamped and cannot be
edited after the fact, and the machine that pulls the published image is genuinely a
different machine from the one that built it — which is exactly the property the artefact
reproducibility exercise is meant to demonstrate. The single deviation is `docker exec`,
which runs without `-it` because a runner has no interactive TTY; the command executed inside
the container is otherwise identical.

---

## 13. Viva preparation

**1. Why avoid pushing directly to `main`?** It skips review and CI, so `main` stops being a
branch that is known to work. It also erases the record of why a change was made — a pull
request holds the reasoning, the discussion and the evidence, and a direct push holds a
commit message.

**2. What is a pull request for, beyond merging?** It is the unit of review, the trigger for
automated verification, and a durable record: what changed, why, what was tested, who
approved. It is also the natural place to enforce policy, because it is a checkpoint that
exists before the change lands rather than after.

**3. Why must CI run before merge?** To keep `main` green. Verifying after merge means the
defect is already in the branch everyone else builds on, and the cost of a bad change grows
with the number of people who have pulled it.

**4. Image versus container?** An image is an immutable, layered filesystem plus metadata —
the artefact. A container is a running instance of one, with its own writable layer, process
namespace and lifecycle. One image, many containers.

**5. Why version Docker images?** So a deployment refers to a specific, reproducible
artefact. Without versions there is no way to say what is running, to roll back to a known
state, or to correlate an incident with a change.

**6. Why is `latest` insufficient?** It is a mutable pointer, not an identity. Two machines
pulling `latest` a day apart can run different code; `latest` today is not `latest`
tomorrow; and nothing about it records which build it refers to. It is useful as a
convenience alias, never as a deployment reference.

**7. Why promote the same artefact rather than rebuild?** A rebuild from the same source is
not guaranteed to produce the same image — dependency resolution, base-image patches and
build-time state all move. Promoting the tested bytes through staging to production means
what was verified is what runs. Rebuilding per environment tests one thing and ships another.

**8. What is a container registry for?** It stores and distributes versioned image artefacts
with authentication, retention and content-addressable digests, and it decouples where an
image is built from where it runs.

**9. CI versus release workflow?** CI validates a proposal on every pull request and
publishes nothing; the release workflow runs on a version tag and is the only thing that
authenticates to the registry and pushes. Separating them keeps write credentials out of
pull request runs and keeps the registry free of unreleased artefacts.

**10. Why store registry credentials as secrets?** A credential in YAML is in the repository,
in its history, in every fork and clone, and in every log that echoes it. Secrets are
injected at run time, masked in logs, and revocable. This repository goes further and uses
no stored registry secret at all: `GITHUB_TOKEN` is minted per run and expires with it.

**11. How do you find the commit that produced an image?** `docker inspect` and read
`org.opencontainers.image.revision`, which this image sets from the building commit. The
commit-SHA image tag gives the same answer from the registry side.

**12. Why does layer ordering affect CI/CD performance?** Because caching is positional: an
invalidated layer invalidates everything after it. Instructions whose inputs change rarely
belong above instructions whose inputs change often. Section 10 measures the difference — and
shows how a metadata block in the wrong place silently undoes correct ordering.

**13. How do you roll back 1.1.0 to 1.0.0?** Pull `1.0.0` from the registry and run it; no
source checkout, no rebuild. Both digests remain available, so the roll-forward is equally
cheap. Section 9 does it.

**14. Relationship between a Git tag and a Docker image tag?** The Git tag names a commit in
the source; the Docker image tag names an artefact built from it. The release workflow is
what ties them together, deriving `1.1.0` from `v1.1.0` and refusing to publish if the
repository's `VERSION` file disagrees.

**15. What extra problems arise when application and model versions move independently?** A
single version number can no longer describe the system. The same application build can
serve different models and produce different predictions, so reproducing a result requires
knowing both — which is why `/health` reports `application_version` and `model_version`
separately and `MODEL_VERSION` is settable per deployment. It follows that the model needs
its own versioned, immutable storage and its own promotion path; that a rollback has two
dimensions, since reverting the application may not revert the model; that "which model
produced this prediction?" must be answerable per request, not per release; and that
correctness becomes statistical — an application is either healthy or not, whereas a model
can serve every request successfully while quietly degrading against drifting data, which no
health endpoint will report.
