import os
import shutil
import uuid
import hashlib
from datetime import datetime
from typing import Dict, List, Optional, Tuple

from fastapi import UploadFile
import aiofiles

from app.models.schemas import FileType, FileInfo
from app.utils.config import get_settings

settings = get_settings()

class FileService:
    """File service class, handling file uploads, downloads and management"""
    
    @staticmethod
    async def save_file(
        file: UploadFile, 
        file_type: FileType,
        custom_filename: Optional[str] = None
    ) -> Tuple[bool, str, Optional[Dict]]:
        """
        Save uploaded file
        
        Args:
            file: Uploaded file
            file_type: File type (agent/mcp)
            custom_filename: Optional custom filename
            
        Returns:
            (success flag, message, file info)
        """
        try:
            # Determine target directory
            target_dir = settings.agent_exec_dir if file_type == FileType.AGENT else settings.mcp_exec_dir
            
            # Generate unique filename (if not provided)
            if not custom_filename:
                file_ext = os.path.splitext(file.filename)[1] if file.filename else ""
                custom_filename = f"{file_type}-{uuid.uuid4().hex}{file_ext}"
            
            # Ensure filename is safe
            safe_filename = custom_filename.replace(" ", "_")
            
            # Build complete file path
            file_path = os.path.join(target_dir, safe_filename)
            
            # Read and save file contents
            contents = await file.read()
            async with aiofiles.open(file_path, "wb") as f:
                await f.write(contents)
            
            # Set executable permissions
            os.chmod(file_path, 0o755)
            
            # Calculate file checksum
            checksum = hashlib.md5(contents).hexdigest()
            
            # Create file info
            file_info = {
                "id": uuid.uuid4().hex,
                "filename": safe_filename,
                "filepath": file_path,
                "file_type": file_type,
                "size": len(contents),
                "created_at": datetime.now(),
                "checksum": checksum
            }
            
            return True, "File uploaded successfully", file_info
            
        except Exception as e:
            return False, f"File upload failed: {str(e)}", None
    
    @staticmethod
    def get_file_path(file_type: FileType, filename: str) -> str:
        """Get complete file path"""
        # Add .bin suffix if not present
        if not filename.endswith('.bin'):
            filename = f"{filename}.bin"
        base_dir = settings.agent_exec_dir if file_type == FileType.AGENT else settings.mcp_exec_dir
        return os.path.join(base_dir, filename)
    
    @staticmethod
    def file_exists(file_path: str) -> bool:
        """Check if file exists"""
        return os.path.isfile(file_path)
    
    @staticmethod
    def get_download_url(file_path: str) -> str:
        """Get file download URL"""
        # Extract file type and filename from path
        parts = file_path.split(os.sep)
        if len(parts) >= 3 and parts[-2] in ["agent", "mcp", "img", "video"]:
            file_type = parts[-2]
            filename = parts[-1]
            return f"http://localhost:8001?type={file_type}&filename={filename}"
        return None
    
    @staticmethod
    def list_files(file_type: Optional[FileType] = None) -> List[FileInfo]:
        """
        List all files
        
        Args:
            file_type: Optional file type filter
            
        Returns:
            List of file information
        """
        files = []
        
        # Determine directories to scan
        dirs_to_scan = []
        if file_type == FileType.AGENT or file_type is None:
            dirs_to_scan.append((settings.agent_exec_dir, FileType.AGENT))
        if file_type == FileType.MCP or file_type is None:
            dirs_to_scan.append((settings.mcp_exec_dir, FileType.MCP))
        
        # Scan directories
        for dir_path, dir_type in dirs_to_scan:
            if not os.path.exists(dir_path):
                continue
                
            for filename in os.listdir(dir_path):
                file_path = os.path.join(dir_path, filename)
                if os.path.isfile(file_path):
                    # Get basic file information
                    stat_info = os.stat(file_path)
                    
                    # Create file info object
                    file_info = FileInfo(
                        id=uuid.uuid4().hex,  # Simple ID generation
                        filename=filename,
                        filepath=file_path,
                        file_type=dir_type,
                        size=stat_info.st_size,
                        created_at=datetime.fromtimestamp(stat_info.st_ctime),
                        # Don't calculate checksum to improve performance
                        checksum=None
                    )
                    files.append(file_info)
        
        return files
    
    @staticmethod
    def delete_file(file_path: str) -> Tuple[bool, str]:
        """
        Delete file
        
        Args:
            file_path: File path
            
        Returns:
            (success flag, message)
        """
        try:
            if not os.path.isfile(file_path):
                return False, "File does not exist"
                
            os.remove(file_path)
            return True, "File deleted successfully"
        except Exception as e:
            return False, f"File deletion failed: {str(e)}" 