# aio-pod
aio pod vm environment

## MCP File Handling Strategy

### File Structure
- MCP executable files are stored in the `uploads/mcp` directory
- Files can be named with or without the `.bin` suffix (e.g., `mcp_voice` or `mcp_voice.bin`)

### Execution Process
1. **File Location**
   - When a request comes to `/api/v1/mcp/{filename}`:
   - Server checks for both `filename.bin` and `filename`
   - Example: for `/api/v1/mcp/mcp_voice`, checks:
     - `uploads/mcp/mcp_voice.bin`
     - `uploads/mcp/mcp_voice`

2. **Permission Handling**
   - Automatically sets execute permissions (chmod +x)
   - Sets permission to 0755 (rwxr-xr-x)
   - Owner can read/write/execute
   - Others can read/execute

3. **Execution**
   - Executes the file using subprocess
   - Captures both stdout and stderr
   - Supports optional command arguments

### API Endpoints

#### Execute MCP File
```http
POST /api/v1/mcp/{filename}
```
- **Parameters**
  - `filename`: Name of the MCP file (with or without .bin)
  - `args` (optional): Command line arguments

- **Response**
  - Success (200): Returns stdout from execution
  - Error (500): Returns stderr from execution
  - Not Found (404): File doesn't exist
  - Forbidden (403): Permission issues

### Error Handling
- Checks file existence before execution
- Verifies execute permissions
- Returns appropriate HTTP status codes and error messages
- Includes CORS headers for cross-origin requests

### Security
- Files must be in the designated `uploads/mcp` directory
- Execute permissions are managed automatically
- Input validation for filenames and arguments
