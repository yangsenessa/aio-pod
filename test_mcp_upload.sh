#!/bin/bash

# Create a test directory if it doesn't exist
mkdir -p test_files

# Create a sample MCP file for testing
echo "This is a test MCP file content" > test_files/test.mcp

# URL of the upload endpoint
URL="http://localhost:8001/upload/mcp"

echo "Testing MCP file upload..."
echo "Uploading test.mcp to $URL"

# Send POST request using curl with verbose output and proper headers
curl -X POST \
     -v \
     -H "Content-Type: multipart/form-data" \
     -H "Accept: application/json" \
     -F "file=@test_files/test.mcp" \
     "$URL"

# Check the exit status
if [ $? -eq 0 ]; then
    echo -e "\nUpload test completed successfully"
else
    echo -e "\nUpload test failed"
fi 