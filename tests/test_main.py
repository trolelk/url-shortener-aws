import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch
from main import app, generate_code

client = TestClient(app)


def test_generate_code_ma_7_znakow():
    code = generate_code("https://google.com")
    assert len(code) == 7


def test_generate_code_jest_deterministyczny():
    code1 = generate_code("https://google.com")
    code2 = generate_code("https://google.com")
    assert code1 == code2


def test_generate_code_rozne_urle_rozne_kody():
    code1 = generate_code("https://google.com")
    code2 = generate_code("https://github.com")
    assert code1 != code2


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@patch("main.table")
def test_shorten_nieprawidlowy_url(mock_table):
    response = client.post("/shorten", json={"url": "to_nie_jest_url"})
    assert response.status_code == 422


@patch("main.table")
def test_redirect_nieistniejacy_kod(mock_table):
    mock_table.get_item.return_value = {"Item": None}
    response = client.get("/r/nieistniejacy", follow_redirects=False)
    assert response.status_code == 404

@patch("main.table")
def test_redirect_zwraca_302(mock_table):
    mock_table.get_item.return_value = {"Item": {"code": "abc1234", "url": "https://google.com"}}
    mock_table.update_item.return_value = {}
    response = client.get("/r/abc1234", follow_redirects=False)
    assert response.status_code == 302
    assert response.headers["location"] == "https://google.com"