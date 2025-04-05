import pytest
import os
import json
import uuid
from fastapi.testclient import TestClient
from main import app
from app.models.schemas import FileType

client = TestClient(app)

# Test data
TEST_FILES = {
    "agent": "test_agent.agent",
    "mcp": "test_mcp.mcp",
    "img": "test_image.jpg",
    "video": "test_video.mp4"
}

TEST_MCP = "memory_mcp"

# Helper functions
def create_test_file(file_type: str, content: str = "test content"):
    """Create a test file for upload"""
    filename = TEST_FILES[file_type]
    file_path = os.path.join("uploads", file_type, filename)
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "w") as f:
        f.write(content)
    return filename, file_path

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
    for file_type in TEST_FILES.values():
        file_path = os.path.join("uploads", file_type)
        if os.path.exists(file_path):
            os.remove(file_path)
    mcp_path = os.path.join("uploads", "mcp", TEST_MCP)
    if os.path.exists(mcp_path):
        os.remove(mcp_path)

# Setup and teardown
@pytest.fixture(autouse=True)
def setup_teardown():
    # Setup
    os.makedirs("uploads/agent", exist_ok=True)
    os.makedirs("uploads/mcp", exist_ok=True)
    os.makedirs("uploads/img", exist_ok=True)
    os.makedirs("uploads/video", exist_ok=True)
    create_test_mcp()
    
    yield
    
    # Teardown
    cleanup_test_files()

# Test file upload endpoints
@pytest.mark.parametrize("file_type", ["agent", "mcp", "img", "video"])
def test_upload_file(file_type):
    filename, file_path = create_test_file(file_type)
    
    with open(file_path, "rb") as f:
        response = client.post(f"/upload/{file_type}", files={"file": (filename, f)})
    
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "File upload successful"
    assert data["filename"] == filename
    assert os.path.exists(data["path"])

# Test file download endpoint
@pytest.mark.parametrize("file_type", ["agent", "mcp", "img", "video"])
def test_download_file(file_type):
    filename, file_path = create_test_file(file_type)
    
    response = client.get(f"/?type={file_type}&filename={filename}")
    
    assert response.status_code == 200
    assert response.headers["content-disposition"] == f'attachment; filename="{filename}"'

# Test file list endpoint
def test_list_files():
    # Upload test files
    for file_type in ["agent", "mcp"]:
        filename, file_path = create_test_file(file_type)
        with open(file_path, "rb") as f:
            client.post(f"/upload/{file_type}", files={"file": (filename, f)})
    
    response = client.get("/api/v1/files")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert len(data["files"]) >= 2  # At least our test files

# Test file info endpoint
def test_get_file_info():
    # Upload a test file
    filename, file_path = create_test_file("agent")
    with open(file_path, "rb") as f:
        client.post("/upload/agent", files={"file": (filename, f)})
    
    response = client.get(f"/api/v1/files/agent/{filename}")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["file"]["filename"] == filename

# Test file delete endpoint
def test_delete_file():
    # Upload a test file
    filename, file_path = create_test_file("agent")
    with open(file_path, "rb") as f:
        client.post("/upload/agent", files={"file": (filename, f)})
    
    response = client.delete(f"/api/v1/files/agent/{filename}")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert not os.path.exists(file_path)

# Test file execution endpoint
def test_execute_file():
    # Upload a test file
    filename, file_path = create_test_file("agent", "#!/bin/bash\necho 'test output'")
    with open(file_path, "rb") as f:
        client.post("/upload/agent", files={"file": (filename, f)})
    
    # Make file executable
    os.chmod(file_path, 0o755)
    
    response = client.post(
        "/api/v1/execute",
        json={
            "filepath": file_path,
            "arguments": [],
            "timeout": 5
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "test output" in data["stdout"]

# Test JSON-RPC execution endpoint
def test_execute_rpc():
    # Upload a test file
    filename, file_path = create_test_file("agent", '#!/bin/bash\necho "{\\"jsonrpc\\":\\"2.0\\",\\"result\\":\\"test\\",\\"id\\":1}"')
    with open(file_path, "rb") as f:
        client.post("/upload/agent", files={"file": (filename, f)})
    
    # Make file executable
    os.chmod(file_path, 0o755)
    
    response = client.post(
        f"/api/v1/rpc/agent/{filename}",
        json={
            "jsonrpc": "2.0",
            "method": "test",
            "params": {},
            "id": 1
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert data["result"] == "test"
    assert data["id"] == 1

# Test error cases
def test_upload_invalid_file_type():
    response = client.post("/upload/invalid", files={"file": ("test.txt", b"test")})
    assert response.status_code == 404

def test_download_nonexistent_file():
    response = client.get("/?type=agent&filename=nonexistent.agent")
    assert response.status_code == 404

def test_execute_nonexistent_file():
    response = client.post(
        "/api/v1/execute",
        json={
            "filepath": "nonexistent.agent",
            "arguments": [],
            "timeout": 5
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is False
    assert "File does not exist" in data["message"]

def test_delete_nonexistent_file():
    response = client.delete("/api/v1/files/agent/nonexistent.agent")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is False
    assert "File does not exist" in data["message"]

# Test MCP execution endpoint
def test_execute_mcp():
    mcp_path = create_test_mcp()
    
    # Make file executable
    os.chmod(mcp_path, 0o755)
    
    # Test basic execution
    response = client.post(
        "/api/v1/execute",
        json={
            "filepath": mcp_path,
            "arguments": [],
            "timeout": 5
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True

# Test MCP JSON-RPC execution endpoint
def test_execute_mcp_rpc():
    mcp_path = create_test_mcp()
    
    # Make file executable
    os.chmod(mcp_path, 0o755)
    
    # Test JSON-RPC execution
    response = client.post(
        f"/api/v1/rpc/mcp/{TEST_MCP}",
        json={
            "jsonrpc": "2.0",
            "method": "start",
            "params": {
                "port": 8080,
                "memory_path": "./memory.json"
            },
            "id": 1
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert "id" in data

# Test MCP execution with invalid parameters
def test_execute_mcp_invalid_params():
    mcp_path = create_test_mcp()
    
    # Test with invalid port
    response = client.post(
        f"/api/v1/rpc/mcp/{TEST_MCP}",
        json={
            "jsonrpc": "2.0",
            "method": "start",
            "params": {
                "port": "invalid",
                "memory_path": "./memory.json"
            },
            "id": 1
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["jsonrpc"] == "2.0"
    assert "error" in data

# Test MCP execution with timeout
def test_execute_mcp_timeout():
    mcp_path = create_test_mcp()
    
    # Test with very short timeout
    response = client.post(
        "/api/v1/execute",
        json={
            "filepath": mcp_path,
            "arguments": [],
            "timeout": 0.1
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is False
    assert "timeout" in data["message"].lower() 