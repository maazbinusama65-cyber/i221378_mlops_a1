# student-ml-api

A minimal ML inference service used to demonstrate a production-style MLOps delivery
workflow: feature branches, pull requests, automated CI, Docker packaging, semantic
version tags, and publication of versioned images to a container registry.

```
feature branch -> Pull Request -> CI -> review -> merge to main -> version tag -> release workflow -> container registry
```

## Status

Repository bootstrap. The application, tests, container image and workflows are delivered
through pull requests; direct development on `main` is not permitted.
