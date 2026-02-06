#!/bin/bash

# ============================================================================
# Argosbx Intelligent Deployment Script
# Supports: Bare Metal & Docker
# ============================================================================

# Define Base Dir
BASE_DIR="$(dirname "$0")"

# Source Modules
source "$BASE_DIR/modules/utils.sh"
source "$BASE_DIR/modules/config.sh"

echo "========================================================="
echo "   Argosbx 智能部署向导"
echo "========================================================="
echo "此向导将帮助您生成最佳配置并自动部署。"
echo "推荐方案：VLESS-Reality + Hysteria2 + Tuic V5"
echo ""

# 1. Run Interactive Configuration Wizard
if [ -f "$HOME/agsbx/config.env" ] && [ -s "$HOME/agsbx/config.env" ]; then
    echo "检测到已存在配置文件: $HOME/agsbx/config.env"
    read -p "是否直接使用现有配置进行部署? (y/n, 默认: y): " use_existing
    use_existing=${use_existing:-y}
    
    if [[ "$use_existing" == "y" ]]; then
        load_config
        log_info "已加载现有配置，跳过设置向导。"
    else
        interactive_config
    fi
else
    interactive_config
fi

# 2. Deployment Method Selection
echo "---------------------------------------------------------"
echo "   部署方式选择"
echo "---------------------------------------------------------"
echo "  [1] 直接安装 (Bare Metal) - 性能最好，适合此时只需运行此脚本"
echo "  [2] Docker 部署 - 环境隔离，干净卫生，支持自动重启"
echo ""

read -p "请选择 (1/2): " deploy_method

if [[ "$deploy_method" == "2" ]]; then
    # --- Docker Deployment ---
    log_info "正在为您准备 Docker 部署..."
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "未检测到 Docker，尝试自动安装..."
        curl -fsSL https://get.docker.com | bash -s docker
        if ! command -v docker >/dev/null 2>&1; then
            log_error "Docker 安装失败，请手动安装后重试。"
            exit 1
        fi
        systemctl start docker
        systemctl enable docker
    fi
    
    # Build Image
    log_info "构建 Docker 镜像 (image: argosbx-image)..."
    docker build -t argosbx-image .
    
    # Construct Run Command
    log_info "生成并执行 Docker 命令..."
    
    # Remove old container if exists
    docker rm -f argosbx 2>/dev/null
    
    # 配置文件已由 interactive_config 生成至 $HOME/agsbx/config.env
    
    log_info "正在启动 Docker 容器..."
    DOCKER_CMD="docker run -d --name argosbx --restart=always --network=host -v $HOME/agsbx:/root/agsbx argosbx-image"
    
    echo "执行命令: $DOCKER_CMD"
    echo "执行命令: $DOCKER_CMD"
    eval "$DOCKER_CMD"
    
    if [ $? -eq 0 ]; then
        log_info "Docker 部署成功！"
        echo "查看日志请运行: docker logs -f argosbx"
        echo "配置文件已持久化至: $HOME/agsbx"
    else
        log_error "Docker 启动失败"
    fi

else
    # --- Bare Metal Deployment ---
    log_info "开始直接安装..."
    
    # The interactive_config already exported vars to current shell
    # But main.sh re-initializes/sources config.sh
    # config.sh init_config takes priority from ENV vars if set? 
    # Yes, init_config lines: [ -z "${vlpt+x}" ] || vlp=yes
    # interactive_config exports vlp=yes AND port_vl_re=...
    # main.sh logic needs vlp=yes.
    # The current shell has vlp=yes.
    # When we run bash main.sh, it runs in Subshell? No, if we source it?
    # No, usually run as `bash main.sh`.
    # Vars exported here ARE available to child `main.sh`.
    
    # We just explicitly set the env vars that main.sh expects from CLI or Env
    # main.sh calls init_config.
    # init_config checks env vars like 'vlpt'.
    # BUT interactive_config sets internal vars 'vlp', 'vmp'.
    # Does init_config overwrite them if vlpt is empty?
    # init_config: `[ -z "${vlpt+x}" ] || vlp=yes`.
    # If vlpt is unset, logic does NOTHING to vlp.
    # So vlp from parent shell persists! 
    # Correct.
    
    bash "$BASE_DIR/main.sh"
fi
