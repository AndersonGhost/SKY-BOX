#!/bin/bash

# ==========================================
# nexttrace-Core 自动安装脚本
# Author: A man
# Target Repo: https://github.com/nxtrace/NTrace-core
# ==========================================

# 定义颜色，方便查看日志
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}[*] 开始检测系统架构...${NC}"

# 1. 检测系统架构 (Architecture Detection)
ARCH=$(uname -m)
OS_TYPE=$(uname -s)

if [ "$OS_TYPE" != "Linux" ]; then
    echo -e "${RED}[!] 错误: 本脚本仅支持 Linux 系统。${NC}"
    exit 1
fi

# 根据 uname -m 的结果匹配下载文件的关键词
case $ARCH in
    x86_64)
        FILE_KEYWORD="linux_amd64"
        echo -e "${GREEN}[*] 检测到架构: AMD64 (x86_64)${NC}"
        ;;
    aarch64)
        FILE_KEYWORD="linux_arm64"
        echo -e "${GREEN}[*] 检测到架构: ARM64 (aarch64)${NC}"
        ;;
    *)
        echo -e "${RED}[!] 错误: 不支持的架构: $ARCH${NC}"
        echo "目前仅支持 x86_64 和 aarch64"
        exit 1
        ;;
esac

# 2. 获取最新版本下载链接 (Fetch Latest Release URL)
REPO="nxtrace/NTrace-core"
API_URL="https://api.github.com/repos/$REPO/releases/latest"

echo -e "${GREEN}[*] 正在从 GitHub ($REPO) 获取最新版本信息...${NC}"

# 使用 curl 获取 API 数据
RESPONSE=$(curl -sL $API_URL)

if [ -z "$RESPONSE" ]; then
    echo -e "${RED}[!] 错误: 无法连接到 GitHub API。请检查网络连接或 DNS。${NC}"
    exit 1
fi

# 解析下载链接 (不依赖 jq，使用 grep/sed 以保证兼容性)
# 逻辑：查找 browser_download_url 行，筛选包含架构关键词的行，提取 URL
DOWNLOAD_URL=$(echo "$RESPONSE" | grep "browser_download_url" | grep "$FILE_KEYWORD" | head -n 1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}[!] 错误: 未找到适配 $ARCH 的最新版本文件。${NC}"
    echo -e "${YELLOW}可能原因：该仓库发布的 Release 中没有包含 '$FILE_KEYWORD' 命名的文件。${NC}"
    exit 1
fi

echo -e "${GREEN}[*] 获取成功! 最新版本下载地址: ${YELLOW}$DOWNLOAD_URL${NC}"

# 3. 下载文件 (Download)
echo -e "${GREEN}[*] 正在下载 nexttrace...${NC}"
curl -L -o nexttrace "$DOWNLOAD_URL" --progress-bar

if [ $? -ne 0 ]; then
    echo -e "${RED}[!] 下载失败。${NC}"
    exit 1
fi

# 4. 设置权限 (Set Permissions)
echo -e "${GREEN}[*] 下载完成，正在设置执行权限...${NC}"
chmod +x nexttrace

# 5. 验证运行 (Verification)
echo -e "${GREEN}[*] 验证运行...${NC}"
if ./nexttrace --version > /dev/null 2>&1 || ./nexttrace -h > /dev/null 2>&1; then
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   nexttrace 安装成功! (针对 $ARCH)   ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "你可以通过以下命令直接运行："
    echo -e "${YELLOW}./nexttrace [IP或域名]${NC}"
else
    echo -e "${RED}[!] 警告: 安装完成，但无法直接运行，请检查文件完整性。${NC}"
fi
