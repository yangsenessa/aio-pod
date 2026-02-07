#!/usr/bin/env python3
"""
Test Chat Router Service
测试 Chat Router 服务的连接和功能
"""

import asyncio
import httpx
import json
import sys
import os
import logging
from datetime import datetime


# 配置日志
def setup_logging():
    """配置日志输出到 ./log 目录"""
    # 创建 log 目录
    log_dir = os.path.join(os.path.dirname(__file__), "log")
    os.makedirs(log_dir, exist_ok=True)
    
    # 生成日志文件名（包含时间戳）
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = os.path.join(log_dir, f"test_chat_router_{timestamp}.log")
    
    # 配置日志格式
    log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    
    # 配置根日志记录器
    logging.basicConfig(
        level=logging.DEBUG,
        format=log_format,
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stdout)  # 同时输出到控制台
        ]
    )
    
    logger = logging.getLogger(__name__)
    logger.info(f"日志文件: {log_file}")
    
    return log_file


# 设置日志
log_file_path = setup_logging()
logger = logging.getLogger(__name__)


async def test_health_check(base_url: str):
    """测试健康检查"""
    logger.info("=" * 50)
    logger.info("开始测试健康检查")
    print("\n=== 测试健康检查 ===")
    try:
        # 使用 trust_env=False 禁用系统代理设置
        async with httpx.AsyncClient(timeout=10.0, trust_env=False) as client:
            logger.debug(f"发送请求: GET {base_url}/health")
            response = await client.get(f"{base_url}/health")
            logger.info(f"响应状态码: {response.status_code}")
            logger.debug(f"响应内容: {response.text}")
            
            print(f"状态码: {response.status_code}")
            print(f"响应: {response.json()}")
            
            success = response.status_code == 200
            logger.info(f"健康检查结果: {'成功' if success else '失败'}")
            return success
    except Exception as e:
        logger.error(f"健康检查异常: {str(e)}", exc_info=True)
        print(f"✗ 错误: {str(e)}")
        return False


async def test_list_models(base_url: str):
    """测试模型列表"""
    logger.info("=" * 50)
    logger.info("开始测试模型列表")
    print("\n=== 测试模型列表 ===")
    try:
        # 使用 trust_env=False 禁用系统代理设置
        async with httpx.AsyncClient(timeout=10.0, trust_env=False) as client:
            logger.debug(f"发送请求: GET {base_url}/v1/models")
            response = await client.get(f"{base_url}/v1/models")
            logger.info(f"响应状态码: {response.status_code}")
            logger.debug(f"响应内容: {response.text}")
            
            print(f"状态码: {response.status_code}")
            data = response.json()
            print(f"可用模型数量: {len(data.get('data', []))}")
            for model in data.get('data', []):
                print(f"  - {model['id']}")
                logger.info(f"  模型: {model['id']}")
            
            success = response.status_code == 200
            logger.info(f"模型列表测试结果: {'成功' if success else '失败'}")
            return success
    except Exception as e:
        logger.error(f"模型列表测试异常: {str(e)}", exc_info=True)
        print(f"✗ 错误: {str(e)}")
        return False


async def test_chat_completion(base_url: str, stream: bool = False):
    """测试聊天完成"""
    mode = "流式" if stream else "非流式"
    logger.info("=" * 50)
    logger.info(f"开始测试聊天完成 ({mode})")
    print(f"\n=== 测试聊天完成 ({mode}) ===")
    
    request_data = {
        "model": "openclaw:main",
        "messages": [
            {"role": "user", "content": "你能用中文跟我交流吗"}
        ],
        "stream": stream
    }
    
    logger.info(f"请求数据: {json.dumps(request_data, ensure_ascii=False, indent=2)}")
    print(f"请求: {json.dumps(request_data, ensure_ascii=False, indent=2)}")
    
    try:
        # 使用 trust_env=False 禁用系统代理设置
        async with httpx.AsyncClient(timeout=60.0, trust_env=False) as client:
            if stream:
                # 流式请求
                logger.debug("发送流式请求")
                print("\n响应 (流式):")
                async with client.stream(
                    "POST",
                    f"{base_url}/v1/chat/completions",
                    json=request_data,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    logger.info(f"响应状态码: {response.status_code}")
                    print(f"状态码: {response.status_code}")
                    if response.status_code == 200:
                        async for line in response.aiter_lines():
                            if line.startswith("data: "):
                                data = line[6:]
                                logger.debug(f"收到数据块: {data[:100]}...")
                                if data == "[DONE]":
                                    logger.info("流式响应完成")
                                    print("\n✓ 流式响应完成")
                                    break
                                try:
                                    chunk = json.loads(data)
                                    content = chunk.get("choices", [{}])[0].get("delta", {}).get("content", "")
                                    if content:
                                        print(content, end="", flush=True)
                                except json.JSONDecodeError:
                                    pass
                        return True
                    else:
                        error_text = await response.aread()
                        logger.error(f"请求失败: {error_text.decode()}")
                        print(f"✗ 请求失败: {error_text.decode()}")
                        return False
            else:
                # 非流式请求
                logger.debug(f"发送请求: POST {base_url}/v1/chat/completions")
                response = await client.post(
                    f"{base_url}/v1/chat/completions",
                    json=request_data,
                    headers={"Content-Type": "application/json"}
                )
                logger.info(f"响应状态码: {response.status_code}")
                print(f"\n状态码: {response.status_code}")
                
                if response.status_code == 200:
                    data = response.json()
                    logger.info(f"响应数据: {json.dumps(data, ensure_ascii=False, indent=2)}")
                    print(f"响应: {json.dumps(data, ensure_ascii=False, indent=2)}")
                    
                    content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
                    print(f"\nAI 回复: {content}")
                    logger.info(f"AI 回复: {content}")
                    return True
                else:
                    error_text = response.text
                    logger.error(f"请求失败: {error_text}")
                    print(f"✗ 请求失败: {error_text}")
                    return False
    
    except Exception as e:
        logger.error(f"聊天完成测试异常: {str(e)}", exc_info=True)
        print(f"✗ 错误: {str(e)}")
        import traceback
        logger.debug(traceback.format_exc())
        traceback.print_exc()
        return False


async def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Test Chat Router Service")
    parser.add_argument(
        "--url",
        default="http://localhost:8002",
        help="Chat Router service URL (default: http://localhost:8002)"
    )
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Test streaming mode"
    )
    
    args = parser.parse_args()
    base_url = args.url.rstrip("/")
    
    logger.info("=" * 70)
    logger.info("Chat Router Service Test Started")
    logger.info("=" * 70)
    logger.info(f"Service URL: {base_url}")
    logger.info(f"Log file: {log_file_path}")
    
    print("=" * 70)
    print("Chat Router Service Test")
    print("=" * 70)
    print(f"Service URL: {base_url}")
    print(f"日志文件: {log_file_path}")
    print()
    
    # 测试健康检查
    health_ok = await test_health_check(base_url)
    if not health_ok:
        logger.error("健康检查失败，服务可能未启动")
        print("\n✗ 健康检查失败，服务可能未启动")
        sys.exit(1)
    
    # 测试模型列表
    models_ok = await test_list_models(base_url)
    
    # 测试聊天完成
    chat_ok = await test_chat_completion(base_url, stream=args.stream)
    
    # 总结
    logger.info("=" * 70)
    logger.info("测试总结")
    logger.info("=" * 70)
    logger.info(f"健康检查: {'通过' if health_ok else '失败'}")
    logger.info(f"模型列表: {'通过' if models_ok else '失败'}")
    logger.info(f"聊天完成: {'通过' if chat_ok else '失败'}")
    logger.info(f"日志文件: {log_file_path}")
    
    print("\n" + "=" * 70)
    print("测试总结")
    print("=" * 70)
    print(f"健康检查: {'✓ 通过' if health_ok else '✗ 失败'}")
    print(f"模型列表: {'✓ 通过' if models_ok else '✗ 失败'}")
    print(f"聊天完成: {'✓ 通过' if chat_ok else '✗ 失败'}")
    print(f"\n详细日志: {log_file_path}")
    print()
    
    if health_ok and models_ok and chat_ok:
        logger.info("所有测试通过！")
        print("✓ 所有测试通过！")
        sys.exit(0)
    else:
        logger.warning("部分测试失败")
        print("✗ 部分测试失败")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
