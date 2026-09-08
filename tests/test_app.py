"""Automated tests for the student-ml-api service."""

import pytest

from app import APPLICATION_NAME, APPLICATION_VERSION, app as flask_app


@pytest.fixture()
def client():
    flask_app.config.update(TESTING=True)
    with flask_app.test_client() as test_client:
        yield test_client


def test_health_reports_healthy_status(client):
    response = client.get("/health")

    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "wrong"
    assert data["application"] == APPLICATION_NAME
    assert data["version"] == APPLICATION_VERSION


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
