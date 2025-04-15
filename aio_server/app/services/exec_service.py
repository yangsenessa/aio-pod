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
        Execute specified executable file
        
        Args:
            filepath: Executable file path
            arguments: Command line arguments
            stdin_data: Standard input data
            timeout: Execution timeout (seconds)
            environment: Environment variables
            
        Returns:
            Execution result response
        """
        logger.setLevel(getattr(logging, settings.log_level.upper()))
        logger.info(f"Starting file execution - filepath: {filepath}, arguments: {arguments}, timeout: {timeout}")
        
        if not FileService.file_exists(filepath):
            logger.error(f"File does not exist: {filepath}")
            return ExecutionResponse(
                success=False,
                message=f"File does not exist: {filepath}"
            )
        
        # Create temporary directory and copy executable
        temp_dir = tempfile.mkdtemp()
        try:
            # Copy file to temporary directory
            temp_filepath = os.path.join(temp_dir, os.path.basename(filepath))
            shutil.copy2(filepath, temp_filepath)
            
            # Ensure file is executable
            if not os.access(temp_filepath, os.X_OK):
                try:
                    logger.info(f"Setting executable permissions for file: {temp_filepath}")
                    os.chmod(temp_filepath, 0o755)
                except Exception as e:
                    logger.error(f"Failed to set executable permissions: {str(e)}")
                    return ExecutionResponse(
                        success=False,
                        message=f"Unable to set executable permissions: {str(e)}"
                    )
            
            # Prepare command
            cmd = [temp_filepath]
            if arguments:
                cmd.extend(arguments)
            logger.info(f"Prepared command: {' '.join(cmd)}")
            
            # Prepare environment variables
            env = os.environ.copy()
            if environment:
                env.update(environment)
                logger.info(f"Added custom environment variables: {environment}")
            
            try:
                start_time = time.time()
                logger.info("Creating subprocess...")
                
                # Create subprocess
                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdin=asyncio.subprocess.PIPE if stdin_data else None,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    env=env
                )
                
                # Send standard input data (if any)
                if stdin_data:
                    logger.info("Sending stdin data to process: %s", stdin_data)
                    stdin_bytes = stdin_data.encode('utf-8') if isinstance(stdin_data, str) else stdin_data
                else:
                    stdin_bytes = None
                    
                # Wait for process to complete, maximum wait time is timeout seconds
                try:
                    logger.info(f"Waiting for process completion (timeout: {timeout}s)")
                    
                    # Create a task for process communication
                    communicate_task = asyncio.create_task(process.communicate(input=stdin_bytes))
                    
                    # Wait for either completion or timeout
                    try:
                        stdout, stderr = await asyncio.wait_for(communicate_task, timeout=timeout)
                    except asyncio.TimeoutError:
                        # Check if there was any stderr output before timeout
                        if process.stderr:
                            try:
                                stderr_data = await asyncio.wait_for(process.stderr.read(), timeout=0.1)
                                if stderr_data:
                                    logger.error(f"Process reported error before timeout: {stderr_data.decode('utf-8', errors='replace')}")
                                    return ExecutionResponse(
                                        success=False,
                                        stderr=stderr_data.decode('utf-8', errors='replace'),
                                        exit_code=None,
                                        execution_time=timeout,
                                        message="Service start failed with error"
                                    )
                            except asyncio.TimeoutError:
                                pass
                        
                        # Check if this is a start method call
                        try:
                            if stdin_data:
                                request_data = json.loads(stdin_data)
                                if request_data.get("method") == "start":
                                    logger.info("Service start timed out with no errors, considering it successful")
                                    return ExecutionResponse(
                                        success=True,
                                        exit_code=None,
                                        execution_time=timeout,
                                        message="Service start successfully"
                                    )
                        except (json.JSONDecodeError, AttributeError) as e:
                            logger.warning(f"Failed to parse stdin data for method check: {str(e)}")
                        
                        # If timeout, terminate process
                        try:
                            process.kill()
                            logger.info("Process terminated due to timeout")
                        except ProcessLookupError:
                            logger.warning("Process already terminated")
                            pass
                            
                        return ExecutionResponse(
                            success=False,
                            exit_code=None,
                            execution_time=timeout,
                            message=f"Execution timeout (>{timeout} seconds)"
                        )
                    
                    execution_time = time.time() - start_time
                    logger.info(f"Process completed in {execution_time:.2f}s with exit code: {process.returncode}")
                    
                    if stdout:
                        logger.debug(f"Process stdout: {stdout.decode('utf-8', errors='replace')}")
                    if stderr:
                        logger.debug(f"Process stderr: {stderr.decode('utf-8', errors='replace')}")
                    
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
                    
                    # Check if this is a start method call
                    try:
                        if stdin_data:
                            request_data = json.loads(stdin_data)
                            if request_data.get("method") == "start":
                                # For start method, we consider it successful if no errors were reported
                                logger.info("Service start timed out, considering it successful for start method")
                                return ExecutionResponse(
                                    success=True,
                                    exit_code=None,
                                    execution_time=timeout,
                                    message="Service start successfully"
                                )
                    except (json.JSONDecodeError, AttributeError) as e:
                        logger.warning(f"Failed to parse stdin data for method check: {str(e)}")
                    
                    # If timeout, terminate process
                    try:
                        process.kill()
                        logger.info("Process terminated due to timeout")
                    except ProcessLookupError:
                        logger.warning("Process already terminated")
                        pass
                        
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
        finally:
            # Clean up temporary directory
            try:
                shutil.rmtree(temp_dir)
                logger.info(f"Cleaned up temporary directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to clean up temporary directory: {str(e)}")
    
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
        logger.debug(f"RPC parameters: {params}")
        
        # Construct JSON-RPC request
        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params if params is not None else {},
            "id": id if id is not None else 1
        }
        
        # Serialize request to JSON string
        try:
            stdin_data = json.dumps(request)
            logger.debug(f"JSON-RPC request: {stdin_data}")
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
        
        # Execute executable file
        logger.info("Executing file with JSON-RPC request")
        result = await ExecutionService.execute_file(
            filepath=filepath,
            stdin_data=stdin_data,
            timeout=timeout
        )
        logger.info(f"执行结果 - 成功状态: {result.success}, 退出码: {result.exit_code}")
        logger.debug(f"标准输出: {result.stdout}")
        logger.debug(f"标准错误: {result.stderr}")
        logger.debug(f"执行信息: {result.message}")
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