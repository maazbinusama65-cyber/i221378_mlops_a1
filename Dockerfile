# Pinned to an explicit patch version so a rebuild can never silently change the runtime.
FROM python:3.12.7-slim-bookworm

# Build metadata, supplied by the release workflow (see .github/workflows/release.yml).
ARG APP_VERSION=0.0.0
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG SOURCE_REPOSITORY=https://github.com/maazbinusama65-cyber/i221378_mlops_a1

# OCI labels make the artefact self-describing: the image itself records which commit and
# which repository produced it.
LABEL org.opencontainers.image.title="student-ml-api" \
      org.opencontainers.image.description="Minimal ML inference service" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.source="${SOURCE_REPOSITORY}" \
      org.opencontainers.image.created="${BUILD_DATE}"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies are copied and installed before the application source so that editing
# app.py reuses the cached dependency layer instead of reinstalling every package.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY VERSION app.py ./

# Run as an unprivileged account rather than root.
RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health').read()"

# gunicorn rather than the Flask development server; bound to 0.0.0.0 so the published
# container port is reachable from the host.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
