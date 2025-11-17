#!/bin/bash

# ===============================================================
#   PEShell Development Build Updater and WIM Integration Script
#   Version 3.3 - Improved robustness with ShellCheck SC2181
# ===============================================================

# --- 配置 ---
# !!! 修改为你自己的 GitHub 用户名/仓库名 !!!
REPO="daiaji/peshell_minimal"
# CI 工作流的文件名 (必须与 .github/workflows/ci.yml 的文件名一致)
WORKFLOW_FILENAME="ci.yml"
# 您希望拉取哪个分支的最新构建
BRANCH_NAME="main"

# WIM 更新配置
ENABLE_WIM_UPDATE=true # 设置为 'true' 启用 WIM 更新流程, 'false' 则禁用
# !!! 修改为你的 WIM 文件路径 !!!
WIM_FILE="/home/daiaji/repo/PE/KuerPE.WIM"
WIM_IMAGE_INDEX=1
# !!! 修改为你的挂载点路径 !!!
MOUNT_POINT="/home/daiaji/repo/PE/Mount/KuerPE"
# rsync 的目标目录 (挂载点内的相对路径)，例如在PE中的 \Windows\System32\peshell
SYNC_TARGET_SUBDIR="/Windows/System32/peshell"
# ----------------

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 临时目录设置
TEMP_DIR=$(mktemp -d -t peshell_updater.XXXXXXXXXX)
if [ ! -d "$TEMP_DIR" ]; then
    echo -e "${RED}错误: 无法创建临时目录。${NC}"
    exit 1
fi

# --- 函数定义 ---

# 检查依赖工具
check_dependencies() {
    local missing=0
    for cmd in curl jq unzip rsync wimlib-imagex; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}错误: 缺少依赖工具 '$cmd'。${NC}"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo -e "请使用您的包管理器安装它 (例如: sudo apt-get install curl jq unzip rsync wimtools)"
        exit 1
    fi
}

# 清理函数
cleanup() {
    # 移除 trap 信号处理，避免在清理过程中再次触发
    trap - EXIT HUP INT QUIT TERM

    echo ""
    echo "正在执行清理..."
    if [ -n "$1" ]; then
        echo -e "${RED}错误: $1${NC}"
    fi

    # 总是尝试卸载挂载点
    if [ "$ENABLE_WIM_UPDATE" = true ] && mountpoint -q "$MOUNT_POINT"; then
        echo -e "${YELLOW}警告: 脚本异常退出，正在尝试强制卸载 WIM 挂载点...${NC}"
        wimunmount "$MOUNT_POINT" --force >/dev/null 2>&1
    fi

    # 清理临时目录
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo "临时目录 '${TEMP_DIR}' 已被删除。"
    fi

    echo ""
    [ -n "$1" ] && exit 1 || exit 0
}

# 注册 trap，确保脚本在任何地方失败都能执行清理
trap 'cleanup "脚本被中断或发生未知错误。"' EXIT HUP INT QUIT TERM

# --- 主流程开始 ---

check_dependencies

# 检查 GITHUB_TOKEN 是否设置
if [ -z "$GITHUB_TOKEN" ]; then
    cleanup "环境变量 'GITHUB_TOKEN' 未设置。请创建一个有 'repo' 权限的 GitHub PAT 并设置它。"
fi

echo -e "${GREEN}使用临时工作目录: ${YELLOW}${TEMP_DIR}${NC}"
echo -e "${GREEN}正在从 '${REPO}' 仓库查找 '${BRANCH_NAME}' 分支的最新成功构建...${NC}"

# 1. 获取最新的成功工作流运行 ID
RUNS_URL="https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW_FILENAME}/runs?branch=${BRANCH_NAME}&status=success&per_page=1"
RUN_ID=$(curl --silent -H "Authorization: Bearer $GITHUB_TOKEN" "$RUNS_URL" | jq -r '.workflow_runs[0].id')

if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
    cleanup "未能找到最新的成功工作流运行记录。请检查分支名和工作流文件名是否正确。"
fi
echo -e "${GREEN}找到最新成功运行 ID: ${YELLOW}${RUN_ID}${NC}"

# 2. 获取该运行的构建产物 (Artifact) 下载链接
ARTIFACTS_URL="https://api.github.com/repos/${REPO}/actions/runs/${RUN_ID}/artifacts"
ARTIFACT_URL=$(curl --silent -H "Authorization: Bearer $GITHUB_TOKEN" "$ARTIFACTS_URL" | jq -r '.artifacts[] | select(.name == "peshell-build-artifact") | .archive_download_url')

if [ -z "$ARTIFACT_URL" ] || [ "$ARTIFACT_URL" == "null" ]; then
    cleanup "在此次运行中未能找到名为 'peshell-build-artifact' 的构建产物。"
fi

# 3. 下载并解压构建产物
FILENAME="peshell-build-artifact.zip"
DOWNLOAD_PATH="${TEMP_DIR}/${FILENAME}"
EXTRACT_DIR="${TEMP_DIR}/peshell-release-build"

echo "准备下载构建产物..."
# [[ ShellCheck SC2181 改进 ]] 直接检查命令的退出码
if ! curl -L -o "$DOWNLOAD_PATH" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "$ARTIFACT_URL"; then
    cleanup "构建产物下载失败。"
fi
echo -e "${GREEN}下载完成。${NC}"

echo -e "正在解压到 '${EXTRACT_DIR}'...${NC}"
mkdir -p "$EXTRACT_DIR"
# [[ ShellCheck SC2181 改进 ]] 直接检查命令的退出码
if ! unzip -o "$DOWNLOAD_PATH" -d "$EXTRACT_DIR" >/dev/null; then
    cleanup "解压失败。"
fi
echo -e "${GREEN}解压完成。${NC}"

# --- WIM 更新流程 ---
if [ "$ENABLE_WIM_UPDATE" = true ]; then
    echo -e "\n${GREEN}--- 开始 WIM 镜像更新流程 ---${NC}"

    SYNC_TARGET_FULL_PATH="${MOUNT_POINT}${SYNC_TARGET_SUBDIR}"

    # 安全检查
    if [ ! -f "$WIM_FILE" ]; then
        cleanup "WIM 文件未找到: ${WIM_FILE}"
    fi
    if mountpoint -q "$MOUNT_POINT"; then
        echo -e "${YELLOW}警告: 挂载点 '${MOUNT_POINT}' 已被占用。正在尝试强制卸载...${NC}"
        # [[ ShellCheck SC2181 改进 ]] 直接检查命令的退出码
        if ! wimunmount "$MOUNT_POINT" --force; then
            cleanup "强制卸载失败，请手动处理后重试。"
        fi
        sleep 1
    fi
    mkdir -p "$MOUNT_POINT"

    # 挂载 WIM 镜像
    echo "正在以读写模式挂载 WIM 镜像..."
    echo "  源: ${WIM_FILE} (映像 #${WIM_IMAGE_INDEX})"
    echo "  目标: ${MOUNT_POINT}"
    # [[ ShellCheck SC2181 改进 ]] 直接检查命令的退出码
    if ! wimmountrw "$WIM_FILE" "$WIM_IMAGE_INDEX" "$MOUNT_POINT"; then
        cleanup "WIM 镜像挂载失败。"
    fi
    echo -e "${GREEN}WIM 挂载成功。${NC}"

    # 同步文件
    echo "正在同步文件到挂载点..."
    echo "  从: ${EXTRACT_DIR}/"
    echo "  到: ${SYNC_TARGET_FULL_PATH}/"
    mkdir -p "$SYNC_TARGET_FULL_PATH"
    # [[ ShellCheck SC2181 改进 ]] 直接检查命令的退出码
    if ! rsync -rvP --delete "${EXTRACT_DIR}/" "${SYNC_TARGET_FULL_PATH}/"; then
        cleanup "rsync 文件同步失败。"
    fi
    echo -e "${GREEN}文件同步成功。${NC}"

    # 卸载 WIM 镜像
    echo "正在卸载 WIM 镜像并提交更改（这可能需要一些时间）..."
    # [[ ShellCheck SC2181 改进 ]] 直接检查命令的退出码
    if ! wimunmount "$MOUNT_POINT" --commit --rebuild; then
        cleanup "WIM 卸载或提交失败。"
    fi
    echo -e "${GREEN}WIM 卸载并提交成功。${NC}"
fi

# --- 最终清理 ---
cleanup "" # 正常退出并清理

echo -e "\n${GREEN}🎉 所有操作成功完成！最新的开发构建已更新并集成到 WIM 镜像中。${NC}"
