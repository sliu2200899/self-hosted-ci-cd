"""Tests that gate the image build.

If these fail, the build-push job never runs and no image reaches GHCR.
"""

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_healthz_returns_ok():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_root_reports_app_and_version():
    response = client.get("/")
    assert response.status_code == 200

    body = response.json()
    assert body["app"] == "sample-app"
    assert body["version"]


def test_unknown_route_is_404():
    assert client.get("/does-not-exist").status_code == 404
