"""Automated tests for the student-ml-api service."""

import pytest

from app import APPLICATION_NAME, APPLICATION_VERSION, MODEL_VERSION, app as flask_app


@pytest.fixture()
def client():
    flask_app.config.update(TESTING=True)
    with flask_app.test_client() as test_client:
        yield test_client


def test_health_reports_healthy_status(client):
    response = client.get("/health")

    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"
    assert data["application"] == APPLICATION_NAME


def test_health_reports_application_and_model_versions(client):
    response = client.get("/health")

    data = response.get_json()
    assert data["application_version"] == APPLICATION_VERSION
    assert data["model_version"] == MODEL_VERSION
    # The application version is served from the VERSION file, not hard-coded in the app.
    assert data["application_version"] == "1.1.0"


def test_predict_returns_prediction_for_valid_input(client):
    response = client.post("/predict", json={"value": 10})

    assert response.status_code == 200
    data = response.get_json()
    assert data["input"] == 10
    assert data["prediction"] == 20


def test_predict_rejects_missing_input(client):
    response = client.post("/predict", json={})

    assert response.status_code == 400
    assert "value" in response.get_json()["error"]


def test_predict_rejects_invalid_input(client):
    response = client.post("/predict", json={"value": "ten"})

    assert response.status_code == 400
    assert "number" in response.get_json()["error"]


def test_predict_rejects_non_json_body(client):
    response = client.post("/predict", data="value=10", content_type="text/plain")

    assert response.status_code == 400
    assert "JSON" in response.get_json()["error"]
