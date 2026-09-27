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

# PyInstaller one-file executables unpack native dependencies on every start.
# Starting many copies of the same MCP concurrently can make even a trivial
# `help` request take minutes. Serialize launches per executable while still
# allowing different MCPs to run in parallel.
_EXECUTABLE_LOCKS: Dict[str, asyncio.Lock] = {}
_HELP_CACHE: Dict[Tuple[str, int, int], Dict[str, Any]] = {}
_STDIO_RUNNERS: Dict[str, "_PersistentStdioRunner"] = {}


def _get_executable_lock(filepath: str) -> asyncio.Lock:
    normalized_path = os.path.realpath(filepath)
    lock = _EXECUTABLE_LOCKS.get(normalized_path)
    if lock is None:
        lock = asyncio.Lock()
        _EXECUTABLE_LOCKS[normalized_path] = lock
    return lock


class _PersistentStdioRunner:
    """Keep a line-oriented JSON-RPC executable warm between requests."""

    def __init__(self, filepath: str):
        self.filepath = os.path.realpath(filepath)
        self.process: Optional[asyncio.subprocess.Process] = None
        self.fingerprint: Optional[Tuple[int, int]] = None
        self.lock = asyncio.Lock()
        self.stderr_task: Optional[asyncio.Task] = None
        self.stderr_tail = ""

    def _current_fingerprint(self) -> Tuple[int, int]:
        stat = os.stat(self.filepath)
        return stat.st_mtime_ns, stat.st_size

    async def _drain_stderr(self, stream: asyncio.StreamReader) -> None:
        while True:
            chunk = await stream.read(4096)
            if not chunk:
                return
            message = chunk.decode("utf-8", errors="replace")
            self.stderr_tail = (self.stderr_tail + message)[-8192:]
            logger.debug("MCP stderr: %s", message.rstrip())

    async def _stop(self) -> None:
        process = self.process
        self.process = None
        if process and process.returncode is None:
            process.kill()
            try:
                await asyncio.wait_for(process.wait(), timeout=5)
            except asyncio.TimeoutError:
                logger.error("Persistent MCP process did not exit after kill")
        if self.stderr_task:
            self.stderr_task.cancel()
            self.stderr_task = None

    async def _ensure_started(self) -> None:
        fingerprint = self._current_fingerprint()
        if (
            self.process is not None
            and self.process.returncode is None
            and self.fingerprint == fingerprint
        ):
            return

        await self._stop()
        self.stderr_tail = ""
        self.process = await asyncio.create_subprocess_exec(
            self.filepath,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.fingerprint = fingerprint
        self.stderr_task = asyncio.create_task(self._drain_stderr(self.process.stderr))
        logger.info("Started persistent MCP stdio process pid=%s", self.process.pid)

    async def _read_json_response(self) -> str:
        if self.process is None or self.process.stdout is None:
            raise RuntimeError("MCP process stdout is unavailable")
        response = ""
        while True:
            line = await self.process.stdout.readline()
            if not line:
                raise RuntimeError(
                    "MCP process exited before returning JSON-RPC data"
                    + (f": {self.stderr_tail}" if self.stderr_tail else "")
                )
            response += line.decode("utf-8", errors="replace")
            try:
                json.loads(response)
                return response
            except json.JSONDecodeError:
                # PixelMug currently emits pretty-printed, multi-line JSON.
                # Continue until one complete JSON document has arrived.
                continue

    async def _request_locked(self, stdin_data: str) -> str:
        async with self.lock:
            await self._ensure_started()
            assert self.process is not None and self.process.stdin is not None
            try:
                self.process.stdin.write((stdin_data + "\n").encode("utf-8"))
                await self.process.stdin.drain()
            except (BrokenPipeError, ConnectionResetError):
                # A one-shot executable may exit after each response. Restart
                # it once and retry transparently.
                await self._stop()
                await self._ensure_started()
                assert self.process is not None and self.process.stdin is not None
                self.process.stdin.write((stdin_data + "\n").encode("utf-8"))
                await self.process.stdin.drain()
            return await self._read_json_response()

    async def request(self, stdin_data: str, timeout: int) -> str:
        try:
            # Queueing behind an in-flight device operation is part of the
            # request timeout, preventing an unbounded backlog.
            return await asyncio.wait_for(self._request_locked(stdin_data), timeout=timeout)
        except asyncio.TimeoutError:
            await self._stop()
            raise


def _get_stdio_runner(filepath: str) -> _PersistentStdioRunner:
    normalized_path = os.path.realpath(filepath)
    runner = _STDIO_RUNNERS.get(normalized_path)
    if runner is None:
        runner = _PersistentStdioRunner(normalized_path)
        _STDIO_RUNNERS[normalized_path] = runner
    return runner

class ExecutionService:
    """Executable file execution service class"""
    
    @staticmethod
    def _sanitize_json_for_logging(data: Any) -> Any:
        """
        Remove sensitive fields (like image_base64) from JSON data for logging
        
        Args:
            data: JSON data (dict, list, or primitive)
            
        Returns:
            Sanitized data with image_base64 fields removed
        """
        if isinstance(data, dict):
            sanitized = {}
            for key, value in data.items():
                if key == "image_base64":
                    sanitized[key] = "[REDACTED]"
                else:
                    sanitized[key] = ExecutionService._sanitize_json_for_logging(value)
            return sanitized
        elif isinstance(data, list):
            return [ExecutionService._sanitize_json_for_logging(item) for item in data]
        else:
            return data
    
    @staticmethod
    def _sanitize_json_string_for_logging(json_str: str) -> str:
        """
        Remove image_base64 from JSON string for logging
        
        Args:
            json_str: JSON string
            
        Returns:
            Sanitized JSON string
        """
        try:
            data = json.loads(json_str)
            sanitized = ExecutionService._sanitize_json_for_logging(data)
            return json.dumps(sanitized, ensure_ascii=False, separators=(',', ':'))
        except (json.JSONDecodeError, TypeError):
            # If parsing fails, return original string
            return json_str
    
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
    async def _execute_stdio_direct(
        filepath: str,
        stdin_data: str,
        timeout: int,
        environment: Optional[Dict[str, str]] = None,
    ) -> ExecutionResponse:
        """Execute one stdio request without an intermediate shell.

        Direct execution avoids quoting bugs and, importantly, lets timeout
        handling terminate the actual MCP process instead of only killing the
        shell that owns a pipe.
        """
        start_time = time.monotonic()
        env = os.environ.copy()
        if environment:
            env.update(environment)

        process = None
        try:
            process = await asyncio.create_subprocess_exec(
                filepath,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            stdout, stderr = await asyncio.wait_for(
                process.communicate((stdin_data + "\n").encode("utf-8")),
                timeout=timeout,
            )
            execution_time = time.monotonic() - start_time
            return ExecutionResponse(
                success=process.returncode == 0,
                stdout=stdout.decode("utf-8", errors="replace") if stdout else None,
                stderr=stderr.decode("utf-8", errors="replace") if stderr else None,
                exit_code=process.returncode,
                execution_time=execution_time,
                message=(
                    "Execution successful"
                    if process.returncode == 0
                    else f"Execution failed, exit code: {process.returncode}"
                ),
            )
        except asyncio.TimeoutError:
            logger.error("Direct stdio execution timed out after %ss", timeout)
            if process and process.returncode is None:
                process.kill()
                try:
                    await asyncio.wait_for(process.wait(), timeout=5)
                except asyncio.TimeoutError:
                    logger.error("Timed-out MCP did not exit within 5 seconds after kill")
            return ExecutionResponse(
                success=False,
                exit_code=process.returncode if process else None,
                execution_time=time.monotonic() - start_time,
                message=f"Execution timeout (>{timeout} seconds)",
            )
        except Exception as exc:
            logger.exception("Direct stdio execution failed")
            if process and process.returncode is None:
                process.kill()
                await process.wait()
            return ExecutionResponse(
                success=False,
                exit_code=process.returncode if process else None,
                execution_time=time.monotonic() - start_time,
                message=f"Execution failed: {exc}",
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
        
        try:
            stat = os.stat(filepath)
            cache_key = (os.path.realpath(filepath), stat.st_mtime_ns, stat.st_size)
        except OSError:
            cache_key = (os.path.realpath(filepath), 0, 0)

        if method == "help" and cache_key in _HELP_CACHE:
            cached_response = dict(_HELP_CACHE[cache_key])
            cached_response["id"] = id
            logger.info("Returning cached help response for %s", filepath)
            return cached_response

        logger.info("Executing persistent stdio JSON-RPC request: %s", method)
        # The runner serializes requests for one executable and keeps the
        # PyInstaller process warm, eliminating repeated one-file extraction.
        try:
            stdout = await _get_stdio_runner(filepath).request(stdin_data, timeout)
            result = ExecutionResponse(
                success=True,
                stdout=stdout,
                exit_code=0,
                execution_time=0,
                message="Execution successful",
            )
        except asyncio.TimeoutError:
            result = ExecutionResponse(
                success=False,
                exit_code=None,
                execution_time=timeout,
                message=f"Execution timeout (>{timeout} seconds)",
            )
        except Exception as exc:
            logger.exception("Persistent stdio JSON-RPC request failed")
            result = ExecutionResponse(
                success=False,
                stderr=str(exc),
                exit_code=None,
                execution_time=0,
                message=f"Execution failed: {exc}",
            )
        logger.info(f"Execution result - Success status: {result.success}, Exit code: {result.exit_code}")
        
        # For debugging - log response content
        if result.stdout:
            logger.info(f"Response size: {len(result.stdout)} bytes")
            # Try to log a small preview of the response (sanitized)
            sanitized_stdout = ExecutionService._sanitize_json_string_for_logging(result.stdout)
            preview_size = min(100, len(sanitized_stdout))
            logger.info(f"Response preview: {sanitized_stdout[:preview_size]}...")
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
                # Sanitize JSON before logging to remove sensitive data like image_base64
                sanitized_stdout = ExecutionService._sanitize_json_string_for_logging(result.stdout)
                logger.info(f"Parsing JSON-RPC response: {sanitized_stdout}")
                response = json.loads(result.stdout)
                if method == "help" and "result" in response:
                    cached_response = dict(response)
                    cached_response["id"] = None
                    # Remove cache entries for older versions of this file.
                    for old_key in list(_HELP_CACHE):
                        if old_key[0] == cache_key[0] and old_key != cache_key:
                            _HELP_CACHE.pop(old_key, None)
                    _HELP_CACHE[cache_key] = cached_response
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
