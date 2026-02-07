"""
Skill Manager
管理和调度所有技能
"""

from typing import Dict, Optional, Type, Any
import logging

from skills.base_skill import BaseSkill

logger = logging.getLogger(__name__)


class SkillManager:
    """技能管理器"""
    
    def __init__(self):
        """初始化技能管理器"""
        self._skills: Dict[str, BaseSkill] = {}
        logger.info("Skill manager initialized")
    
    def register_skill(self, skill: BaseSkill) -> None:
        """
        注册技能
        
        Args:
            skill: 技能实例
        """
        if skill.name in self._skills:
            logger.warning(f"Skill {skill.name} already registered, overwriting")
        
        self._skills[skill.name] = skill
        logger.info(f"Registered skill: {skill.name}")
    
    def unregister_skill(self, name: str) -> bool:
        """
        取消注册技能
        
        Args:
            name: 技能名称
            
        Returns:
            是否成功取消注册
        """
        if name in self._skills:
            del self._skills[name]
            logger.info(f"Unregistered skill: {name}")
            return True
        
        logger.warning(f"Skill {name} not found")
        return False
    
    def get_skill(self, name: str) -> Optional[BaseSkill]:
        """
        获取技能
        
        Args:
            name: 技能名称
            
        Returns:
            技能实例，如果不存在则返回 None
        """
        return self._skills.get(name)
    
    def list_skills(self) -> Dict[str, Dict[str, str]]:
        """
        列出所有技能
        
        Returns:
            技能信息字典
        """
        return {
            name: skill.get_info()
            for name, skill in self._skills.items()
        }
    
    def execute_skill(self, name: str, **kwargs) -> Any:
        """
        执行技能
        
        Args:
            name: 技能名称
            **kwargs: 技能参数
            
        Returns:
            执行结果
            
        Raises:
            ValueError: 如果技能不存在
        """
        skill = self.get_skill(name)
        if not skill:
            raise ValueError(f"Skill {name} not found")
        
        logger.info(f"Executing skill: {name}")
        try:
            result = skill.execute(**kwargs)
            logger.info(f"Skill {name} executed successfully")
            return result
        except Exception as e:
            logger.error(f"Skill {name} execution failed: {str(e)}")
            raise


# 全局技能管理器实例
_global_manager: Optional[SkillManager] = None


def get_skill_manager() -> SkillManager:
    """
    获取全局技能管理器实例
    
    Returns:
        技能管理器实例
    """
    global _global_manager
    if _global_manager is None:
        _global_manager = SkillManager()
    return _global_manager
