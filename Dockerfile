# Pinned to an explicit patch version so a rebuild can never silently change the runtime.
FROM python:3.12.7-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# The unprivileged runtime account is created early: it is a stable layer that later
# application changes do not invalidate.
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

# Dependencies are copied and installed before the application source so that editing
# app.py reuses the cached dependency layer instead of reinstalling every package.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appuser VERSION app.py ./

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health').read()"

# Build metadata is declared last, on purpose. These values (commit SHA, build date) change
# on every single build, so any layer placed after them would be rebuilt every time. Keeping
# them below the dependency and source layers means metadata changes cost one cheap layer.
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

# gunicorn rather than the Flask development server; bound to 0.0.0.0 so the published
# container port is reachable from the host.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
