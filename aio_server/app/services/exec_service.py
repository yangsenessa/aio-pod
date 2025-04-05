import os
import time
import asyncio
import json
import logging
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
        
        # Prepare command
        cmd = [filepath]
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
                logger.info("Sending stdin data to process")
                stdin_bytes = stdin_data.encode('utf-8') if isinstance(stdin_data, str) else stdin_data
            else:
                stdin_bytes = None
                
            # Wait for process to complete, maximum wait time is timeout seconds
            try:
                logger.info(f"Waiting for process completion (timeout: {timeout}s)")
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(input=stdin_bytes),
                    timeout=timeout
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
                logger.debug(f"Parsing JSON-RPC response: {result.stdout}")
                response = json.loads(result.stdout)
                logger.info("JSON-RPC execution completed successfully")
                return response
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