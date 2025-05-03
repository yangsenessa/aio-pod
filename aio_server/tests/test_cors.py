import pytest
from fastapi.testclient import TestClient
from app.api.server import create_app

client = TestClient(create_app())

def test_cors_preflight():
    """Test CORS preflight request"""
    headers = {
        "Origin": "http://example.com",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "Content-Type",
    }
    response = client.options("/aip/v1/test", headers=headers)
    
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "*"
    assert response.headers["access-control-allow-methods"] == "*"
    assert "content-type" in response.headers["access-control-allow-headers"].lower()

def test_cors_actual_request():
    """Test actual CORS request"""
    headers = {
        "Origin": "http://example.com",
    }
    response = client.get("/aip/v1/health", headers=headers)
    
    assert response.status_code in [200, 404]  # 404 is ok if endpoint doesn't exist
    assert response.headers["access-control-allow-origin"] == "*" 