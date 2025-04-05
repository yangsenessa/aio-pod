import pytest
import os
import json
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

# Test data
TEST_MCP = "memory_mcp"

# Helper functions
def create_test_mcp():
    """Create a test mcp file"""
    mcp_path = os.path.join("uploads", "mcp", TEST_MCP)
    os.makedirs(os.path.dirname(mcp_path), exist_ok=True)
    # 确保文件存在
    if not os.path.exists(mcp_path):
        with open(mcp_path, "w") as f:
            f.write("#!/bin/bash\necho 'test output'")
    return mcp_path

def cleanup_test_files():
    """Clean up test files"""
    mcp_path = os.path.join("uploads", "mcp", TEST_MCP)
    if os.path.exists(mcp_path):
        os.remove(mcp_path)

# Setup and teardown
@pytest.fixture(autouse=True)
def setup_teardown():
    # Setup
    os.makedirs("uploads/mcp", exist_ok=True)
    create_test_mcp()
    
    yield
    
    # Teardown
    cleanup_test_files()

# Test MCP execution endpoint
def test_execute_mcp():
    mcp_path = create_test_mcp()
    
    # Make file executable
    os.chmod(mcp_path, 0o755)
    
    # Test basic execution
    response = client.post(
        "/api/v1/execute/mcp",
        params={
            "filename": TEST_MCP,
            "args": None
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert "output" in data

# Test MCP execution with arguments
def test_execute_mcp_with_args():
    mcp_path = create_test_mcp()
    
    # Make file executable
    os.chmod(mcp_path, 0o755)
    
    # Test execution with arguments
    response = client.post(
        "/api/v1/execute/mcp",
        params={
            "filename": TEST_MCP,
            "args": "--port 8080 --memory-path ./memory.json"
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert "output" in data

# Test MCP execution with invalid file
def test_execute_mcp_invalid_file():
    response = client.post(
        "/api/v1/execute/mcp",
        params={
            "filename": "nonexistent.mcp",
            "args": None
        }
    )
    
    assert response.status_code == 404
    data = response.json()
    assert "detail" in data
    assert "File does not exist" in data["detail"]

# Test MCP execution with non-executable file
def test_execute_mcp_non_executable():
    mcp_path = create_test_mcp()
    
    # Remove execute permission
    os.chmod(mcp_path, 0o644)
    
    response = client.post(
        "/api/v1/execute/mcp",
        params={
            "filename": TEST_MCP,
            "args": None
        }
    )
    
    assert response.status_code == 403
    data = response.json()
    assert "detail" in data
    assert "File does not have execute permission" in data["detail"]

# Test MCP execution with execution error
def test_execute_mcp_execution_error():
    mcp_path = create_test_mcp()
    
    # Make file executable but with error
    os.chmod(mcp_path, 0o755)
    with open(mcp_path, "w") as f:
        f.write("#!/bin/bash\nexit 1")
    
    response = client.post(
        "/api/v1/execute/mcp",
        params={
            "filename": TEST_MCP,
            "args": None
        }
    )
    
    assert response.status_code == 500
    data = response.json()
    assert "detail" in data 