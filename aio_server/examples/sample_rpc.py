#!/usr/bin/env python3
"""
Sample AIO/MCP JSON-RPC Script

This script demonstrates how to implement a JSON-RPC executable file 
that complies with the AIO/MCP protocol. It can receive JSON-RPC requests 
via standard input, process them, and return JSON-RPC responses.

Usage:
1. Make the script executable: chmod +x sample_rpc.py
2. Upload to service: python client.py upload mcp sample_rpc.py
3. Execute RPC call: python client.py execute mcp sample_rpc.py hello '{"name":"World"}'

Setup with conda:
  conda create -n aio_client python=3.9
  conda activate aio_client
  # No additional packages needed for this script
"""

import sys
import json
import time
from typing import Dict, Any, List, Optional

# Available methods list
METHODS = {
    "hello": "Say hello",
    "add": "Calculate sum of two numbers",
    "echo": "Echo input data",
    "sleep": "Wait for specified seconds",
    "error": "Return an error"
}

def handle_hello(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle hello method"""
    name = params.get("name", "Guest")
    return {"message": f"Hello, {name}!"}

def handle_add(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle add method"""
    a = params.get("a", 0)
    b = params.get("b", 0)
    
    # Ensure parameters are numbers
    try:
        a = float(a)
        b = float(b)
    except (ValueError, TypeError):
        raise ValueError("Parameters must be numbers")
        
    return {"result": a + b}

def handle_echo(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle echo method"""
    return {"echo": params}

def handle_sleep(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle sleep method"""
    seconds = params.get("seconds", 1)
    
    try:
        seconds = float(seconds)
    except (ValueError, TypeError):
        raise ValueError("seconds parameter must be a number")
        
    if seconds < 0 or seconds > 10:
        raise ValueError("seconds parameter must be between 0-10")
        
    time.sleep(seconds)
    return {"slept": seconds}

def handle_error(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle error method"""
    code = params.get("code", -32603)
    message = params.get("message", "Internal error")
    
    raise RuntimeError(message)

def handle_request(request: Dict[str, Any]) -> Dict[str, Any]:
    """Handle JSON-RPC request"""
    # Validate JSON-RPC version
    if request.get("jsonrpc") != "2.0":
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32600,
                "message": "Invalid Request: Only JSON-RPC 2.0 is supported"
            },
            "id": request.get("id")
        }
    
    # Extract request parameters
    method = request.get("method")
    params = request.get("params", {})
    id = request.get("id")
    
    # Validate method name
    if not method:
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32600,
                "message": "Invalid Request: Missing method field"
            },
            "id": id
        }
    
    # Check if method exists
    if method not in METHODS:
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32601,
                "message": f"Method not found: {method}",
                "data": {
                    "available_methods": list(METHODS.keys())
                }
            },
            "id": id
        }
    
    # Handle method call
    try:
        # Call appropriate handler function
        handler = globals().get(f"handle_{method}")
        if not handler:
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32603,
                    "message": f"Internal error: Method handler not found: {method}"
                },
                "id": id
            }
            
        result = handler(params)
        
        # Return success response
        return {
            "jsonrpc": "2.0",
            "result": result,
            "id": id
        }
        
    except Exception as e:
        # Handle exceptions
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32603,
                "message": str(e)
            },
            "id": id
        }

def main():
    """Main function"""
    try:
        # Read JSON-RPC request from standard input
        input_data = sys.stdin.read()
        
        if not input_data:
            # If no input, return available methods list
            response = {
                "jsonrpc": "2.0",
                "result": {
                    "status": "ok",
                    "message": "Sample AIO/MCP JSON-RPC Service",
                    "methods": METHODS
                },
                "id": None
            }
        else:
            # Parse request
            try:
                request = json.loads(input_data)
                response = handle_request(request)
            except json.JSONDecodeError:
                response = {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32700,
                        "message": "Parse error: Invalid JSON"
                    },
                    "id": None
                }
        
        # Write response to standard output
        print(json.dumps(response, ensure_ascii=False))
        
    except Exception as e:
        # Handle uncaught exceptions
        response = {
            "jsonrpc": "2.0",
            "error": {
                "code": -32603,
                "message": f"Internal error: {str(e)}"
            },
            "id": None
        }
        print(json.dumps(response, ensure_ascii=False))

if __name__ == "__main__":
    main() 