#!/usr/bin/env bash
#
# Local counterpart of .github/workflows/demonstration.yml.
#
# Runs the container lifecycle, registry round-trip, rollback, layer-cache and failure
# analysis exercises against a local Docker daemon and writes a transcript. It builds
# throwaway local tags and pulls already-published images; it never pushes.
#
#   Usage: bash scripts/local-demonstration.sh [output-log-path]
#
set -uo pipefail

IMAGE="student-ml-api"
REGISTRY_IMAGE="ghcr.io/maazbinusama65-cyber/student-ml-api"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${1:-${REPO_ROOT}/docs/evidence/local-demonstration.log}"

cd "${REPO_ROOT}"
mkdir -p "$(dirname "${LOG}")"

# Everything below is written to both the terminal and the transcript.
exec > >(tee "${LOG}") 2>&1

section() {
  echo
  echo "==================================================================="
  echo "$*"
  echo "==================================================================="
}

cleanup() {
  docker rm -f student-ml-api student-ml-api-1-1-0 student-ml-api-1-0-0 \
    bad-bind good-bind wrong-port right-port missing-dep > /dev/null 2>&1 || true
  rm -f requirements.broken.txt Dockerfile.broken requirements.bogus.txt Dockerfile.bogus \
    app-change-build.log req-change-build.log login.log
}
trap cleanup EXIT

echo "Local runtime demonstration"
echo "Host:    $(uname -s) $(uname -r)"
echo "Date:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "Commit:  $(git rev-parse HEAD)"
echo "Docker:  $(docker --version)"

cleanup

VERSION="$(cat VERSION)"

section "Part 10 - Build the image locally"
echo "VERSION file reports: ${VERSION}"
docker build \
  --build-arg APP_VERSION="${VERSION}" \
  --build-arg GIT_COMMIT="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t "${IMAGE}:${VERSION}" .

section "Part 10 - Run the container and verify /health"
docker run -d --name student-ml-api -p 5000:5000 "${IMAGE}:${VERSION}"
for _ in $(seq 1 15); do
  curl -fsS http://localhost:5000/health && break || sleep 2
done
echo
echo "--- POST /predict ---"
curl -fsS -X POST http://localhost:5000/predict -H 'Content-Type: application/json' -d '{"value": 10}'
echo
echo "--- POST /predict with a missing field ---"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST http://localhost:5000/predict -H 'Content-Type: application/json' -d '{}'

section "Part 11 - docker images"
docker images | grep -E 'REPOSITORY|student-ml-api'

section "Part 11 - docker ps"
docker ps

section "Part 11 - docker logs"
docker logs student-ml-api

section "Part 11 - docker inspect"
echo "Container ID:      $(docker inspect -f '{{.Id}}' student-ml-api)"
echo "Image ID:          $(docker inspect -f '{{.Image}}' student-ml-api)"
echo "Exposed port:      $(docker inspect -f '{{json .Config.ExposedPorts}}' student-ml-api)"
echo "Published ports:   $(docker inspect -f '{{json .NetworkSettings.Ports}}' student-ml-api)"
echo "Running command:   $(docker inspect -f '{{json .Config.Cmd}}' student-ml-api)"
echo "Working directory: $(docker inspect -f '{{.Config.WorkingDir}}' student-ml-api)"
echo "User:              $(docker inspect -f '{{.Config.User}}' student-ml-api)"

section "Part 11 - docker exec"
# -it needs an interactive terminal; the command run inside the container is the same
# either way, so it is only requested when this script has a TTY on stdin.
if [ -t 0 ]; then
  docker exec -it student-ml-api sh -c 'echo "whoami: $(whoami)"; echo "pwd: $(pwd)"; ls -la'
else
  echo "(no TTY on stdin; running without -it)"
  docker exec student-ml-api sh -c 'echo "whoami: $(whoami)"; echo "pwd: $(pwd)"; ls -la'
fi

section "Part 23 - OCI metadata labels"
docker image inspect "${IMAGE}:${VERSION}" -f '{{json .Config.Labels}}' | tr ',' '\n'

section "Part 25 - Rebuild after changing only app.py"
printf '\n# cache demonstration: application-only change\n' >> app.py
docker build -t "${IMAGE}:cache-app-change" . 2>&1 | tee app-change-build.log
echo "=== cached steps in this build ==="
grep -c 'CACHED' app-change-build.log || true
grep 'CACHED' app-change-build.log || true
git checkout -- app.py

section "Part 25 - Rebuild after changing requirements.txt"
printf '\n# cache demonstration: dependency change\n' >> requirements.txt
docker build -t "${IMAGE}:cache-req-change" . 2>&1 | tee req-change-build.log
echo "=== cached steps in this build ==="
grep -c 'CACHED' req-change-build.log || true
grep 'CACHED' req-change-build.log || true
echo "=== was the dependency layer re-executed? ==="
grep -E 'pip install|Installing collected' req-change-build.log | head -5 || true
git checkout -- requirements.txt

section "Part 17 - Delete the local image and pull it back from the registry"
docker rm -f student-ml-api
docker rmi -f "${IMAGE}:${VERSION}" "${IMAGE}:cache-app-change" "${IMAGE}:cache-req-change"
echo "=== local images after deletion (filtered to this project) ==="
docker images | grep -E 'REPOSITORY|student-ml-api' || echo "no student-ml-api image remains locally"
echo "=== pulling the published artefact ==="
docker pull "${REGISTRY_IMAGE}:1.1.0"
docker image inspect "${REGISTRY_IMAGE}:1.1.0" -f 'RepoDigests: {{json .RepoDigests}}'
docker run -d --name student-ml-api-1-1-0 -p 5000:5000 "${REGISTRY_IMAGE}:1.1.0"
for _ in $(seq 1 15); do
  curl -fsS http://localhost:5000/health && break || sleep 2
done
echo

section "Part 20 - Roll back to 1.0.0 using the registry only"
echo "=== 1.1.0 is assumed to have a production issue; stop it ==="
docker rm -f student-ml-api-1-1-0
echo "=== no source change and no rebuild: pull the previous artefact ==="
docker pull "${REGISTRY_IMAGE}:1.0.0"
docker image inspect "${REGISTRY_IMAGE}:1.0.0" -f 'RepoDigests: {{json .RepoDigests}}'
docker run -d --name student-ml-api-1-0-0 -p 5000:5000 "${REGISTRY_IMAGE}:1.0.0"
for _ in $(seq 1 15); do
  curl -fsS http://localhost:5000/health && break || sleep 2
done
echo
echo "=== the rolled-back container reports the 1.0.0 health contract ==="
docker rm -f student-ml-api-1-0-0

section "Part 26 - Failure - application bound to 127.0.0.1"
docker run -d --name bad-bind -p 5000:5000 "${REGISTRY_IMAGE}:1.1.0" gunicorn --bind 127.0.0.1:5000 app:app
sleep 5
echo "=== symptom: request from the host ==="
curl -sS --max-time 5 http://localhost:5000/health
echo "curl exit code: $?"
echo "=== evidence: gunicorn is listening on the loopback interface only ==="
docker logs bad-bind 2>&1 | grep -i listening
echo "=== correction: bind to 0.0.0.0 ==="
docker rm -f bad-bind
docker run -d --name good-bind -p 5000:5000 "${REGISTRY_IMAGE}:1.1.0" gunicorn --bind 0.0.0.0:5000 app:app
sleep 5
curl -sS --max-time 5 http://localhost:5000/health
echo
docker rm -f good-bind

section "Part 26 - Failure - wrong container port published"
echo "=== symptom: publishing host 5000 to container port 8000, where nothing listens ==="
docker run -d --name wrong-port -p 5000:8000 "${REGISTRY_IMAGE}:1.1.0"
sleep 5
curl -sS --max-time 5 http://localhost:5000/health
echo "curl exit code: $?"
echo "=== evidence: the published mapping targets a port the application does not use ==="
docker port wrong-port
docker inspect -f '{{json .Config.ExposedPorts}}' wrong-port
echo "=== correction: publish the port the application actually listens on ==="
docker rm -f wrong-port
docker run -d --name right-port -p 5000:5000 "${REGISTRY_IMAGE}:1.1.0"
sleep 5
curl -sS --max-time 5 http://localhost:5000/health
echo
docker rm -f right-port

section "Part 26 - Failure - missing dependency in the image"
echo "flask==3.1.0" > requirements.broken.txt
sed -e 's|COPY requirements.txt ./|COPY requirements.broken.txt ./|' \
    -e 's|-r requirements.txt|-r requirements.broken.txt|' Dockerfile > Dockerfile.broken
docker build -f Dockerfile.broken -t "${IMAGE}:missing-dep" .
docker run -d --name missing-dep "${IMAGE}:missing-dep"
sleep 5
echo "=== symptom: the container is not running ==="
docker ps -a --filter name=missing-dep --format '{{.Names}} {{.Status}}'
echo "=== evidence: the entrypoint binary is absent because gunicorn was never installed ==="
docker logs missing-dep 2>&1 | tail -5
docker rm -f missing-dep
rm -f requirements.broken.txt Dockerfile.broken

section "Part 26 - Failure - Docker build failure from an unresolvable dependency"
cp requirements.txt requirements.bogus.txt
echo "this-package-does-not-exist-mlops==9.9.9" >> requirements.bogus.txt
sed -e 's|COPY requirements.txt ./|COPY requirements.bogus.txt ./|' \
    -e 's|-r requirements.txt|-r requirements.bogus.txt|' Dockerfile > Dockerfile.bogus
docker build -f Dockerfile.bogus -t "${IMAGE}:bogus" . 2>&1 | tail -15
echo "=== docker build exit status: ${PIPESTATUS[0]} (non-zero would fail the pipeline) ==="
rm -f requirements.bogus.txt Dockerfile.bogus

section "Part 26 - Failure - invalid registry credentials"
# docker login is run outside a pipeline so its own exit status can be read: $? after a
# pipeline reports the last command's status and PIPESTATUS[0] the first, neither of which
# would be docker login.
docker login ghcr.io -u maazbinusama65-cyber --password-stdin > login.log 2>&1 <<< "invalid-token-value"
status=$?
tail -3 login.log
echo "=== docker login exit status: ${status} (a release job would stop here) ==="
rm -f login.log

section "Demonstration complete"
echo "Transcript written to: ${LOG}"
