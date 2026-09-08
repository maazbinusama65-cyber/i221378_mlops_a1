# student-ml-api

A minimal ML inference service used to demonstrate a production-style MLOps delivery
workflow: feature branches, pull-request gated CI, Docker packaging, semantic version tags
and publication of versioned images to a container registry.

```
feature branch -> Pull Request -> CI -> review -> merge to main -> version tag -> release workflow -> container registry
```

The "model" is deliberately trivial. The subject of this repository is the delivery
pipeline around the service, not model performance.

## API

| Method | Path       | Description                              |
| ------ | ---------- | ---------------------------------------- |
| GET    | `/health`  | Liveness probe reporting the application and model versions |
| POST   | `/predict` | Returns a prediction for a numeric input |

```console
$ curl http://localhost:5000/health
{"application":"student-ml-api","application_version":"1.1.0","model_version":"model-1","status":"healthy"}

$ curl -X POST http://localhost:5000/predict -H 'Content-Type: application/json' -d '{"value": 10}'
{"input":10,"prediction":20}
```

`/predict` returns HTTP 400 when the `value` field is missing, is not numeric, or when the
request body is not a JSON object.

## Local development

```bash
python -m venv .venv
.venv/bin/pip install -r requirements-dev.txt   # Windows: .venv/Scripts/pip
.venv/bin/pytest                                 # runs the automated test suite
python app.py                                    # development server on :5000
```

`requirements.txt` holds runtime dependencies only, so the container image never ships the
test tooling. `requirements-dev.txt` adds the test dependencies on top of it.

## Container

```bash
docker build -t student-ml-api:$(cat VERSION) .
docker run -d --name student-ml-api -p 5000:5000 student-ml-api:$(cat VERSION)
curl http://localhost:5000/health
```

Published images are available from the GitHub Container Registry:

```bash
docker pull ghcr.io/maazbinusama65-cyber/student-ml-api:1.1.0
```

Every published image carries OCI labels recording the version, the originating commit and
the build date, so any running container can be traced back to its source.

## Versioning

The application version and the model version are tracked separately. `VERSION` is the
single source of truth for the application version; the model version is reported by
`/health` and can be overridden per deployment with the `MODEL_VERSION` environment
variable, so a model can change without an application release and vice versa.

`VERSION` is the single source of truth for the application version. It is read by the
application at runtime, and the release workflow refuses to publish unless the file matches
the Git tag being released. A tag `v1.0.0` produces the image tags `1.0.0`, `latest` and the
short commit SHA.

## Workflows

| Workflow | Trigger | Responsibility |
| --- | --- | --- |
| `.github/workflows/ci.yml` | pull requests to `main`, pushes to development branches | Test, validate, build-check. Never publishes. |
| `.github/workflows/release.yml` | push of a `v*.*.*` tag | Test, build, version, publish to GHCR. |

## Branching policy

`main` is protected: pull requests are required, both CI checks must pass, the branch must
be up to date, administrators are included, and force pushes and deletion are blocked. All
work happens on feature branches and reaches `main` only through a reviewed pull request.

## Delivery report

[`docs/REPORT.md`](docs/REPORT.md) documents the pipeline as built, with the branch
protection settings and the reasoning behind them, the merge strategy, the full
traceability chain from pull request to image digest, the layer-cache measurements, the
rollback demonstration and the failure analysis. Every value in it comes from this
repository's own runs and registry.
