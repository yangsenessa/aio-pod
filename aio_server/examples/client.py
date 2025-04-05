#!/usr/bin/env python3
"""
AIO-MCP Execution Service Example Client

Usage:
  python client.py upload agent /path/to/agent_file agent_name
  python client.py upload mcp /path/to/mcp_file mcp_name
  python client.py list [agent|mcp]
  python client.py execute agent|mcp filename [method] [params_json]
  python client.py delete agent|mcp filename

Setup with conda:
  conda create -n aio_client python=3.9
  conda activate aio_client
  pip install requests
"""

import os
import sys
import json
import requests
import argparse
from typing import Dict, Any, Optional, List

# Service base URL
BASE_URL = os.environ.get("AIO_SERVICE_URL", "http://localhost:8000")
API_PATH = "api/v1"

def upload_file(file_path: str, file_type: str, custom_filename: Optional[str] = None) -> Dict[str, Any]:
    """Upload file to service"""
    if not os.path.exists(file_path):
        print(f"Error: File does not exist: {file_path}")
        sys.exit(1)
        
    url = f"{BASE_URL}/{API_PATH}/upload"
    
    # If no custom filename provided, use original filename
    if not custom_filename:
        custom_filename = os.path.basename(file_path)
    
    files = {
        "file": (custom_filename, open(file_path, "rb"), "application/octet-stream")
    }
    
    data = {
        "file_type": file_type,
        "custom_filename": custom_filename
    }
    
    try:
        response = requests.post(url, files=files, data=data)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error: Failed to upload file: {str(e)}")
        sys.exit(1)

def list_files(file_type: Optional[str] = None) -> List[Dict[str, Any]]:
    """List files on the service"""
    url = f"{BASE_URL}/{API_PATH}/files"
    
    params = {}
    if file_type:
        params["file_type"] = file_type
    
    try:
        response = requests.get(url, params=params)
        response.raise_for_status()
        return response.json()["files"]
    except requests.RequestException as e:
        print(f"Error: Failed to get file list: {str(e)}")
        sys.exit(1)

def delete_file(file_type: str, filename: str) -> Dict[str, Any]:
    """Delete file from the service"""
    url = f"{BASE_URL}/{API_PATH}/files/{file_type}/{filename}"
    
    try:
        response = requests.delete(url)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error: Failed to delete file: {str(e)}")
        sys.exit(1)

def execute_file(file_type: str, filename: str, method: Optional[str] = None, params_json: Optional[str] = None) -> Dict[str, Any]:
    """Execute file on the service"""
    # Build file path
    filepath = f"{file_type}/{filename}"
    
    # If method provided, use RPC mode
    if method:
        url = f"{BASE_URL}/{API_PATH}/rpc/{file_type}/{filename}"
        
        params = {}
        if params_json:
            try:
                params = json.loads(params_json)
            except json.JSONDecodeError:
                print(f"Error: Invalid JSON parameters: {params_json}")
                sys.exit(1)
        
        data = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        }
        
        try:
            response = requests.post(url, json=data)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error: Failed to execute RPC request: {str(e)}")
            sys.exit(1)
    
    # Otherwise use standard execution mode
    else:
        url = f"{BASE_URL}/{API_PATH}/execute"
        
        data = {
            "filepath": filepath,
            "arguments": [],
            "timeout": 30
        }
        
        try:
            response = requests.post(url, json=data)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error: Failed to execute file: {str(e)}")
            sys.exit(1)

def print_files(files: List[Dict[str, Any]]) -> None:
    """Print file list"""
    if not files:
        print("No files found.")
        return
        
    print(f"Found {len(files)} files:")
    print("-" * 80)
    print(f"{'ID':<8} {'Filename':<30} {'Type':<8} {'Size':<10} {'Created'}")
    print("-" * 80)
    
    for file in files:
        print(f"{file['id'][:6]:<8} {file['filename']:<30} {file['file_type']:<8} {format_size(file['size']):<10} {file['created_at']}")

def format_size(size: int) -> str:
    """Format byte size to readable string"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024.0:
            return f"{size:.2f}{unit}"
        size /= 1024.0
    return f"{size:.2f}TB"

def main():
    parser = argparse.ArgumentParser(description="AIO-MCP Execution Service Client")
    subparsers = parser.add_subparsers(dest="command", help="supported commands")
    
    # Upload file command
    upload_parser = subparsers.add_parser("upload", help="Upload file")
    upload_parser.add_argument("type", choices=["agent", "mcp"], help="File type")
    upload_parser.add_argument("file", help="File path")
    upload_parser.add_argument("filename", nargs="?", help="Custom filename (optional)")
    
    # List files command
    list_parser = subparsers.add_parser("list", help="List files")
    list_parser.add_argument("type", nargs="?", choices=["agent", "mcp"], help="File type (optional)")
    
    # Execute file command
    execute_parser = subparsers.add_parser("execute", help="Execute file")
    execute_parser.add_argument("type", choices=["agent", "mcp"], help="File type")
    execute_parser.add_argument("filename", help="Filename")
    execute_parser.add_argument("method", nargs="?", help="RPC method name (optional)")
    execute_parser.add_argument("params", nargs="?", help="RPC parameters (JSON string, optional)")
    
    # Delete file command
    delete_parser = subparsers.add_parser("delete", help="Delete file")
    delete_parser.add_argument("type", choices=["agent", "mcp"], help="File type")
    delete_parser.add_argument("filename", help="Filename")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    if args.command == "upload":
        result = upload_file(args.file, args.type, args.filename)
        if result["success"]:
            print(f"Upload successful: {result['filename']}")
            print(f"File path: {result['filepath']}")
            print(f"Download URL: {result['download_url']}")
        else:
            print(f"Upload failed: {result['message']}")
    
    elif args.command == "list":
        files = list_files(args.type)
        print_files(files)
    
    elif args.command == "execute":
        result = execute_file(args.type, args.filename, args.method, args.params)
        print(json.dumps(result, indent=2, ensure_ascii=False))
    
    elif args.command == "delete":
        result = delete_file(args.type, args.filename)
        if result["success"]:
            print(f"Delete successful: {args.type}/{args.filename}")
        else:
            print(f"Delete failed: {result['message']}")

if __name__ == "__main__":
    main() 