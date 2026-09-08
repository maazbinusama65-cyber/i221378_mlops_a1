"""student-ml-api: a minimal ML inference service.

The "model" is deliberately trivial. The purpose of this project is the MLOps delivery
workflow around the service (branching, pull-request gated CI, containerisation and
versioned artefacts), not model performance.
"""

from pathlib import Path

from flask import Flask, jsonify, request

APPLICATION_NAME = "student-ml-api"
PREDICTION_COEFFICIENT = 2

VERSION_FILE = Path(__file__).resolve().parent / "VERSION"
FALLBACK_VERSION = "0.0.0"

# Binding to all interfaces is required so the process is reachable from outside the
# container network namespace. Binding to 127.0.0.1 would make published ports useless.
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 5000


def read_version() -> str:
    """Return the application version from the VERSION file.

    The version is kept in a single file so that the running application, the Git tag and
    the published image tag can never drift apart.
    """
    try:
        version = VERSION_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return FALLBACK_VERSION
    return version or FALLBACK_VERSION


APPLICATION_VERSION = read_version()

app = Flask(__name__)


@app.get("/health")
def health():
    """Liveness probe reporting the identity and version of the running artefact."""
    return jsonify(
        status="healthy",
        application=APPLICATION_NAME,
        version=APPLICATION_VERSION,
    )


@app.post("/predict")
def predict():
    """Return a prediction for a single numeric input."""
    payload = request.get_json(silent=True)

    if not isinstance(payload, dict):
        return jsonify(error="Request body must be a JSON object."), 400

    if "value" not in payload:
        return jsonify(error="Missing required field: 'value'."), 400

    value = payload["value"]

    # bool is a subclass of int, but a boolean is not a valid numeric input here.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return jsonify(error="Field 'value' must be a number."), 400

    return jsonify(input=value, prediction=value * PREDICTION_COEFFICIENT)


if __name__ == "__main__":
    app.run(host=DEFAULT_HOST, port=DEFAULT_PORT)
