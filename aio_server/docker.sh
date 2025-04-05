#!/bin/bash

# 确保脚本在出错时停止执行
set -e

# 打印彩色文本
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

print_blue() {
    echo -e "\033[0;34m$1\033[0m"
}

print_yellow() {
    echo -e "\033[0;33m$1\033[0m"
}

print_red() {
    echo -e "\033[0;31m$1\033[0m"
}

# 默认设置
IMAGE_NAME="aio-mcp-server"
VERSION="latest"
DOCKER_HUB_USERNAME=""
PUSH_TO_DOCKER_HUB=false
RUN_CONTAINER=false
PORT=8000

# 显示帮助信息
show_help() {
    echo "AIO-MCP 服务器 Docker 脚本"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help                显示帮助信息"
    echo "  -n, --name NAME           设置镜像名称 (默认: $IMAGE_NAME)"
    echo "  -v, --version VERSION     设置版本标签 (默认: $VERSION)"
    echo "  -u, --username USERNAME   设置 Docker Hub 用户名 (用于推送)"
    echo "  -p, --push                构建后推送到 Docker Hub"
    echo "  -r, --run                 构建后运行容器"
    echo "  --port PORT               指定运行容器时的端口 (默认: $PORT)"
    echo ""
    echo "示例:"
    echo "  $0 --name aio-server --version 1.0"
    echo "  $0 --username myuser --push"
    echo "  $0 --run --port 9000"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -u|--username)
            DOCKER_HUB_USERNAME="$2"
            shift 2
            ;;
        -p|--push)
            PUSH_TO_DOCKER_HUB=true
            shift
            ;;
        -r|--run)
            RUN_CONTAINER=true
            shift
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        *)
            print_red "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 如果要推送但没有提供用户名
if [[ "$PUSH_TO_DOCKER_HUB" = true && -z "$DOCKER_HUB_USERNAME" ]]; then
    print_yellow "要推送到 Docker Hub，必须提供用户名 (-u, --username)"
    read -p "请输入 Docker Hub 用户名: " DOCKER_HUB_USERNAME
    
    if [[ -z "$DOCKER_HUB_USERNAME" ]]; then
        print_red "未提供用户名，无法推送到 Docker Hub"
        exit 1
    fi
fi

# 设置完整的镜像名称
if [[ -n "$DOCKER_HUB_USERNAME" ]]; then
    FULL_IMAGE_NAME="${DOCKER_HUB_USERNAME}/${IMAGE_NAME}:${VERSION}"
else
    FULL_IMAGE_NAME="${IMAGE_NAME}:${VERSION}"
fi

# 构建 Docker 镜像
print_blue "开始构建 Docker 镜像: $FULL_IMAGE_NAME"
docker build -t "$FULL_IMAGE_NAME" .

print_green "Docker 镜像构建成功: $FULL_IMAGE_NAME"

# 推送到 Docker Hub
if [[ "$PUSH_TO_DOCKER_HUB" = true ]]; then
    print_blue "登录到 Docker Hub..."
    docker login
    
    print_blue "推送镜像到 Docker Hub: $FULL_IMAGE_NAME"
    docker push "$FULL_IMAGE_NAME"
    
    print_green "成功推送到 Docker Hub: $FULL_IMAGE_NAME"
fi

# 运行容器
if [[ "$RUN_CONTAINER" = true ]]; then
    print_blue "运行 Docker 容器，端口: $PORT"
    
    # 确保上传目录存在
    mkdir -p uploads/agent uploads/mcp
    
    docker run -d --name aio-mcp-server \
        -p ${PORT}:8000 \
        -v "$(pwd)/uploads:/app/uploads" \
        "$FULL_IMAGE_NAME"
    
    print_green "Docker 容器正在运行"
    print_green "API 可在 http://localhost:${PORT} 访问"
    print_green "API 文档可在 http://localhost:${PORT}/docs 访问"
    print_green "查看日志: docker logs aio-mcp-server"
    print_green "停止容器: docker stop aio-mcp-server"
fi

# 显示使用说明
if [[ "$RUN_CONTAINER" = false ]]; then
    print_yellow "要运行此镜像，请执行:"
    echo "  docker run -d -p ${PORT}:8000 -v \$(pwd)/uploads:/app/uploads ${FULL_IMAGE_NAME}"
fi

if [[ "$PUSH_TO_DOCKER_HUB" = false && -n "$DOCKER_HUB_USERNAME" ]]; then
    print_yellow "要推送此镜像到 Docker Hub，请执行:"
    echo "  docker push ${FULL_IMAGE_NAME}"
fi 