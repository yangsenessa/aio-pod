import os
import time
import asyncio
import json
import logging
import shutil
import tempfile
from typing import Dict, List, Optional, Tuple, Any
import subprocess

from app.services.file_service import FileService
from app.models.schemas import ExecutionResponse
from app.utils.config import get_settings

# Configure logging
logger = logging.getLogger(__name__)
settings = get_settings()

class ExecutionService:
    """Executable file execution service class"""
    
    @staticmethod
    async def execute_file(
        filepath: str,
        arguments: Optional[List[str]] = None,
        stdin_data: Optional[str] = None,
        timeout: int = 30,
        environment: Optional[Dict[str, str]] = None
    ) -> ExecutionResponse:
        """
        Execute file with optional arguments and standard input
        """
        logger.info(f"Executing file: {filepath}")
        logger.info(f"Arguments: {arguments}")
        logger.info(f"Timeout: {timeout}s")
        
        # Ensure file is executable
        if not os.access(filepath, os.X_OK):
            try:
                logger.info(f"Setting executable permissions for file: {filepath}")
                os.chmod(filepath, 0o755)
            except Exception as e:
                logger.error(f"Failed to set executable permissions: {str(e)}")
                return ExecutionResponse(
                    success=False,
                    message=f"Unable to set executable permissions: {str(e)}"
                )
        
        try:
            start_time = time.time()
            
            # Prepare environment
            env = os.environ.copy()
            if environment:
                env.update(environment)
                logger.info(f"Added custom environment variables: {environment}")
            
            # Use shell piping approach (like the test script)
            if stdin_data:
                logger.info(f"Using shell piping approach with stdin data (length: {len(stdin_data)})")
                logger.info(f"First 100 chars of stdin: {stdin_data[:100]}...")
                
                # For large inputs, use a temporary file instead of echo to avoid argument list too long errors
                if len(stdin_data) > 10000:  # If input is larger than ~10KB
                    logger.info(f"Input data too large for echo command ({len(stdin_data)} bytes), using temporary file")
                    
                    # Create a temporary file
                    with tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='.json') as temp_file:
                        temp_filepath = temp_file.name
                        # Write JSON data to file
                        temp_file.write(stdin_data)
                        temp_file.flush()
                        logger.info(f"Created temporary file: {temp_filepath}")
                    
                    try:
                        # Use cat to pipe file content to the executable
                        shell_cmd = f"cat {temp_filepath} | {filepath}"
                        if arguments:
                            shell_cmd += f" {' '.join(arguments)}"
                        
                        logger.info(f"Executing shell command with pipe from file: {shell_cmd}")
                        
                        # Execute the shell command
                        process = await asyncio.create_subprocess_shell(
                            shell_cmd,
                            stdout=asyncio.subprocess.PIPE,
                            stderr=asyncio.subprocess.PIPE,
                            env=env,
                            shell=True
                        )
                        
                        # Wait for process completion with timeout
                        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
                        
                        # Process the response
                        execution_time = time.time() - start_time
                        logger.info(f"Process completed in {execution_time:.2f}s with exit code: {process.returncode}")
                        
                        # Log output sizes
                        stdout_size = len(stdout) if stdout else 0
                        stderr_size = len(stderr) if stderr else 0
                        logger.info(f"Output sizes - stdout: {stdout_size} bytes, stderr: {stderr_size} bytes")
                        
                        # Log preview of outputs (if available)
                        if stdout:
                            stdout_preview = stdout[:100].decode('utf-8', errors='replace')
                            logger.debug(f"Stdout preview: {stdout_preview}...")
                        if stderr:
                            stderr_preview = stderr[:100].decode('utf-8', errors='replace')
                            logger.debug(f"Stderr preview: {stderr_preview}...")
                        
                        return ExecutionResponse(
                            success=process.returncode == 0,
                            stdout=stdout.decode('utf-8', errors='replace') if stdout else None,
                            stderr=stderr.decode('utf-8', errors='replace') if stderr else None,
                            exit_code=process.returncode,
                            execution_time=execution_time,
                            message="Execution successful" if process.returncode == 0 else f"Execution failed, exit code: {process.returncode}"
                        )
                    
                    finally:
                        # Clean up the temporary file
                        logger.info(f"Temporary file: {temp_filepath}")
                        # try:
                        #     os.unlink(temp_filepath)
                        #     logger.info(f"Removed temporary file: {temp_filepath}")
                        # except Exception as e:
                        #     logger.warning(f"Failed to remove temporary file: {str(e)}")
                
                else:
                    # For smaller inputs, use the echo approach
                    # Properly escape the JSON for shell
                    escaped_stdin = stdin_data.replace("'", "'\\''")
                    
                    # Build the shell command
                    shell_cmd = f"echo '{escaped_stdin}' | {filepath}"
                    if arguments:
                        shell_cmd += f" {' '.join(arguments)}"
                    
                    logger.info(f"Executing shell command with piping (showing truncated stdin)")
                    
                    # Execute the shell command
                    process = await asyncio.create_subprocess_shell(
                        shell_cmd,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                        env=env,
                        shell=True
                    )
                    
                    try:
                        # Wait for process completion with timeout
                        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
                        
                        # Process the response
                        execution_time = time.time() - start_time
                        logger.info(f"Process completed in {execution_time:.2f}s with exit code: {process.returncode}")
                        
                        # Log output sizes
                        stdout_size = len(stdout) if stdout else 0
                        stderr_size = len(stderr) if stderr else 0
                        logger.info(f"Output sizes - stdout: {stdout_size} bytes, stderr: {stderr_size} bytes")
                        
                        # Log preview of outputs (if available)
                        if stdout:
                            stdout_preview = stdout[:100].decode('utf-8', errors='replace')
                            logger.info(f"Stdout preview: {stdout_preview}...")
                        if stderr:
                            stderr_preview = stderr[:100].decode('utf-8', errors='replace')
                            logger.info(f"Stderr preview: {stderr_preview}...")
                        
                        # Return execution result
                        return ExecutionResponse(
                            success=process.returncode == 0,
                            stdout=stdout.decode('utf-8', errors='replace') if stdout else None,
                            stderr=stderr.decode('utf-8', errors='replace') if stderr else None,
                            exit_code=process.returncode,
                            execution_time=execution_time,
                            message="Execution successful" if process.returncode == 0 else f"Execution failed, exit code: {process.returncode}"
                        )
                        
                    except asyncio.TimeoutError:
                        logger.error(f"Process execution timed out after {timeout}s")
                        
                        # Try to kill the process
                        try:
                            process.kill()
                            logger.info("Process terminated due to timeout")
                        except ProcessLookupError:
                            logger.warning("Process already terminated")
                        
                        # Special handling for start method
                        try:
                            request_data = json.loads(stdin_data)
                            if request_data.get("method") == "start":
                                logger.info("Service start timed out, considering it successful for start method")
                                return ExecutionResponse(
                                    success=True,
                                    exit_code=None,
                                    execution_time=timeout,
                                    message="Service start successfully"
                                )
                        except (json.JSONDecodeError, AttributeError) as e:
                            logger.warning(f"Failed to parse stdin data for method check: {str(e)}")
                        
                        return ExecutionResponse(
                            success=False,
                            exit_code=None,
                            execution_time=timeout,
                            message=f"Execution timeout (>{timeout} seconds)"
                        )
            else:
                # No stdin data - just run the command directly
                logger.info("No stdin data provided, executing command directly")
                
                # Prepare command
                cmd = [filepath]
                if arguments:
                    cmd.extend(arguments)
                
                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    env=env
                )
                
                try:
                    stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
                    execution_time = time.time() - start_time
                    
                    return ExecutionResponse(
                        success=process.returncode == 0,
                        stdout=stdout.decode('utf-8', errors='replace') if stdout else None,
                        stderr=stderr.decode('utf-8', errors='replace') if stderr else None,
                        exit_code=process.returncode,
                        execution_time=execution_time,
                        message="Execution successful" if process.returncode == 0 else f"Execution failed, exit code: {process.returncode}"
                    )
                except asyncio.TimeoutError:
                    try:
                        process.kill()
                        logger.info("Process terminated due to timeout")
                    except ProcessLookupError:
                        logger.warning("Process already terminated")
                        
                    return ExecutionResponse(
                        success=False,
                        exit_code=None,
                        execution_time=timeout,
                        message=f"Execution timeout (>{timeout} seconds)"
                    )
            
        except Exception as e:
            logger.error(f"Process execution failed: {str(e)}")
            return ExecutionResponse(
                success=False,
                message=f"Execution failed: {str(e)}"
            )
    
    @staticmethod
    async def execute_json_rpc(
        filepath: str,
        method: str,
        params: Any = None,
        id: Any = None,
        timeout: int = 30
    ) -> Dict[str, Any]:
        """
        Execute executable file using JSON-RPC protocol
        
        Args:
            filepath: Executable file path
            method: RPC method name
            params: RPC parameters
            id: RPC request ID
            timeout: Execution timeout (seconds)
            
        Returns:
            JSON-RPC response
        """
        logger.info(f"Starting JSON-RPC execution - filepath: {filepath}, method: {method}, id: {id}, timeout: {timeout}")
        
        # For large base64 data, increase the timeout if needed
        if params and "base64_data" in params and len(params["base64_data"]) > 1000000:  # > 1MB
            original_timeout = timeout
            timeout = max(timeout, 60)  # Ensure at least 60 seconds for large files
            logger.info(f"Large base64 data detected ({len(params['base64_data'])} bytes), increased timeout from {original_timeout}s to {timeout}s")
        
        # Construct JSON-RPC request
        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params if params is not None else {},
            "id": id if id is not None else 1
        }
        
        # Serialize request to JSON string - match the shell script exactly
        try:
            # Use compact JSON formatting without whitespace and ensure_ascii=False to handle non-ASCII characters
            stdin_data = json.dumps(request, ensure_ascii=False, separators=(',', ':'))
            
            logger.info(f"JSON-RPC request size: {len(stdin_data)} bytes")
            # If we have base64 data, log the size
            if params and "base64_data" in params:
                base64_size = len(params["base64_data"])
                logger.info(f"Base64 data size: {base64_size} bytes")
                
            # Validate that we can parse the JSON back - sanity check
            try:
                json.loads(stdin_data)
                logger.info("JSON validation successful")
            except json.JSONDecodeError as e:
                logger.error(f"JSON validation failed: {str(e)}")
                
        except Exception as e:
            logger.error(f"Failed to serialize JSON-RPC request: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32700,
                    "message": f"Failed to serialize request: {str(e)}"
                },
                "id": id
            }
        
        # Execute executable file with shell piping
        logger.info(f"Executing file using shell piping for JSON-RPC request: {method}")
        result = await ExecutionService.execute_file(
            filepath=filepath,
            stdin_data=stdin_data,
            timeout=timeout
        )
        logger.info(f"Execution result - Success status: {result.success}, Exit code: {result.exit_code}")
        
        # For debugging - log response content
        if result.stdout:
            logger.info(f"Response size: {len(result.stdout)} bytes")
            # Try to log a small preview of the response
            preview_size = min(100, len(result.stdout))
            logger.info(f"Response preview: {result.stdout[:preview_size]}...")
        else:
            logger.warning("No stdout response received")
        
        # If there's stderr, log it
        if result.stderr:
            logger.error(f"Stderr output: {result.stderr}")
        
        # Parse response
        if not result.success:
            logger.error(f"JSON-RPC execution failed: {result.message}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32603,
                    "message": result.message,
                    "data": {
                        "stderr": result.stderr,
                        "exit_code": result.exit_code
                    }
                },
                "id": id
            }
        
        # Try to parse JSON-RPC response
        try:
            if result.stdout:
                logger.info(f"Parsing JSON-RPC response: {result.stdout}")
                response = json.loads(result.stdout)
                logger.info("JSON-RPC execution completed successfully")
                return response
            else:
                # For start method, no output is expected
                if method == "start":
                    logger.info("Start method completed with no output, considering it successful")
                    return {
                        "jsonrpc": "2.0",
                        "result": {
                            "status": "success",
                            "message": "Service started successfully"
                        },
                        "id": id
                    }
                else:
                    logger.error("JSON-RPC execution returned no output")
                    return {
                        "jsonrpc": "2.0",
                        "error": {
                            "code": -32603,
                            "message": "Execution successful but no output",
                            "data": {
                                "stderr": result.stderr,
                                "exit_code": result.exit_code
                            }
                        },
                        "id": id
                    }
                
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON-RPC response: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32603,
                    "message": "Response is not a valid JSON-RPC response",
                    "data": {
                        "stdout": result.stdout,
                        "stderr": result.stderr,
                        "exit_code": result.exit_code,
                        "parse_error": str(e)
                    }
                },
                "id": id
            } 