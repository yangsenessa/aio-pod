"""
Base Skill Class
所有技能的基类
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
import logging

logger = logging.getLogger(__name__)


class BaseSkill(ABC):
    """技能基类"""
    
    def __init__(self, name: str, description: str, version: str = "1.0.0"):
        """
        初始化技能
        
        Args:
            name: 技能名称
            description: 技能描述
            version: 技能版本
        """
        self.name = name
        self.description = description
        self.version = version
        logger.info(f"Initialized skill: {name} v{version}")
    
    @abstractmethod
    def execute(self, **kwargs) -> Any:
        """
        执行技能
        
        Args:
            **kwargs: 技能参数
            
        Returns:
            执行结果
        """
        pass
    
    def validate_params(self, params: Dict[str, Any], required: list) -> bool:
        """
        验证参数
        
        Args:
            params: 参数字典
            required: 必需参数列表
            
        Returns:
            验证是否通过
        """
        for param in required:
            if param not in params or params[param] is None:
                logger.error(f"Missing required parameter: {param}")
                return False
        return True
    
    def get_info(self) -> Dict[str, str]:
        """
        获取技能信息
        
        Returns:
            技能信息字典
        """
        return {
            "name": self.name,
            "description": self.description,
            "version": self.version
        }
    
    def __repr__(self) -> str:
        return f"<{self.__class__.__name__}: {self.name} v{self.version}>"
