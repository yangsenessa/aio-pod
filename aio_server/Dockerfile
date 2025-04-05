FROM python:3.9-slim

WORKDIR /app

# 安装依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用程序代码
COPY . .

# 创建上传目录
RUN mkdir -p uploads/agent uploads/mcp && \
    chmod -R 755 uploads

# 暴露端口
EXPOSE 8000

# 设置环境变量
ENV HOST=0.0.0.0
ENV PORT=8000
ENV AGENT_EXEC_DIR=uploads/agent
ENV MCP_EXEC_DIR=uploads/mcp

# 启动应用
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"] 