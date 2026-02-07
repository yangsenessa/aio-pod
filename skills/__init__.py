"""
Skills Framework
技能框架入口
"""

from skills.skill_manager import SkillManager, get_skill_manager
from skills.base_skill import BaseSkill

__version__ = "1.0.0"
__all__ = ["SkillManager", "BaseSkill", "get_skill_manager"]
