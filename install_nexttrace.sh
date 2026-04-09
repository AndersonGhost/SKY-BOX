#!/bin/bash

# ==========================================
# nexttrace-Core 自动安装脚本（改进版）
# Original: AndersonGhost/SKY-BOX
# Improved: 版本选择、全局安装、安全增强
# Target Repo: https://github.com/nxtrace/NTrace-core
# ==========================================

set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="${INSTALL_DIR}/nexttrace"
REPO="nxtrace/NTrace-core"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# ========== 辅助函数 ==========

info()  { echo -e "${GREEN}[*] $*${NC}"; }
warn()  { echo -e "${YELLOW}[!] $*${NC}"; }
error() { echo -e "${RED}[✗] $*${NC}"; exit 1; }

cleanup() {
    [ -n "${TMP_FILE:-}" ] && rm -f "$TMP_FILE"
}
trap cleanup EXIT

usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --full      直接安装完整版（跳过交互选择）"
    echo "  --tiny      直接安装精简版（跳过交互选择）"
    echo "  -h, --help  显示帮助信息"
    exit 0
}

# ========== 参数解析 ==========

VERSION_CHOICE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --full) VERSION_CHOICE="full"; shift ;;
        --tiny) VERSION_CHOICE="tiny"; shift ;;
        -h|--help) usage ;;
        *) warn "未知参数: $1"; shift ;;
    esac
done

# ========== 1. 权限检查 ==========

if [ "$(id -u)" -ne 0 ]; then
    error "本脚本需要 root 权限，请使用: sudo bash $0"
fi

# ========== 2. 系统检测 ==========

info "开始检测系统架构..."

OS_TYPE=$(uname -s)
if [ "$OS_TYPE" != "Linux" ]; then
    error "本脚本仅支持 Linux 系统，当前系统: $OS_TYPE"
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        FILE_KEYWORD="linux_amd64"
        info "检测到架构: AMD64 (x86_64)"
        ;;
    aarch64|arm64)
        FILE_KEYWORD="linux_arm64"
        info "检测到架构: ARM64 (aarch64)"
        ;;
    armv7l|armv7)
        FILE_KEYWORD="linux_armv7"
        info "检测到架构: ARMv7 (armv7l)"
        ;;
    i686|i386)
        FILE_KEYWORD="linux_386"
        info "检测到架构: x86 (${ARCH})"
        ;;
    mips)
        FILE_KEYWORD="linux_mips"
        info "检测到架构: MIPS"
        ;;
    mipsle|mipsel)
        FILE_KEYWORD="linux_mipsle"
        info "检测到架构: MIPS LE"
        ;;
    riscv64)
        FILE_KEYWORD="linux_riscv64"
        info "检测到架构: RISC-V 64"
        ;;
    *)
        error "不支持的架构: $ARCH"
        ;;
esac

# ========== 3. 检查已安装版本 ==========

if command -v nexttrace &>/dev/null; then
    CURRENT_VER=$(nexttrace -V 2>&1 | head -n 1 | awk '{print $2}' || echo "未知")
    warn "检测到已安装的 nexttrace: ${CURRENT_VER}"
    read -r -p "$(echo -e "${YELLOW}是否覆盖安装？[y/N]: ${NC}")" CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS]) info "继续安装..." ;;
        *) echo "已取消安装。"; exit 0 ;;
    esac
fi

# ========== 4. 获取最新版本信息 ==========

info "正在从 GitHub (${REPO}) 获取最新版本信息..."

RESPONSE=$(curl -sL --fail --max-time 15 "$API_URL" 2>&1) || true

# 检查 rate limit
if echo "$RESPONSE" | grep -q "API rate limit exceeded"; then
    error "GitHub API 请求频率超限，请稍后再试，或设置 GITHUB_TOKEN 环境变量"
fi

if [ -z "$RESPONSE" ]; then
    error "无法连接到 GitHub API，请检查网络连接或 DNS"
fi

# 提取版本号
TAG_NAME=$(echo "$RESPONSE" | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4)
if [ -z "$TAG_NAME" ]; then
    error "无法解析版本信息，GitHub API 返回异常"
fi

info "最新版本: ${CYAN}${TAG_NAME}${NC}"

# ========== 5. 版本选择（完整版 / 精简版）==========

# 提取完整版和精简版的下载链接
URL_FULL=$(echo "$RESPONSE" | grep "browser_download_url" | grep "$FILE_KEYWORD" | grep -v "tiny" | head -n 1 | cut -d '"' -f 4)
URL_TINY=$(echo "$RESPONSE" | grep "browser_download_url" | grep "$FILE_KEYWORD" | grep "tiny" | head -n 1 | cut -d '"' -f 4)

# 如果命令行没有指定版本，交互让用户选择
if [ -z "$VERSION_CHOICE" ]; then
    echo ""
    echo -e "${CYAN}请选择安装版本:${NC}"
    echo ""
    if [ -n "$URL_FULL" ]; then
        echo -e "  ${GREEN}1)${NC} 完整版 (推荐) — 包含完整 IP 数据库，离线查询能力强"
    fi
    if [ -n "$URL_TINY" ]; then
        echo -e "  ${GREEN}2)${NC} 精简版 (tiny) — 体积小，依赖在线查询"
    fi
    echo ""

    if [ -n "$URL_FULL" ] && [ -n "$URL_TINY" ]; then
        read -r -p "$(echo -e "${CYAN}请输入选择 [1/2，默认1]: ${NC}")" CHOICE
        case "$CHOICE" in
            2) VERSION_CHOICE="tiny" ;;
            *) VERSION_CHOICE="full" ;;
        esac
    elif [ -n "$URL_FULL" ]; then
        VERSION_CHOICE="full"
        info "仅有完整版可用，自动选择完整版"
    elif [ -n "$URL_TINY" ]; then
        VERSION_CHOICE="tiny"
        info "仅有精简版可用，自动选择精简版"
    else
        error "未找到适配 ${ARCH} ($FILE_KEYWORD) 的下载文件"
    fi
fi

# 确定最终下载地址
if [ "$VERSION_CHOICE" = "tiny" ]; then
    DOWNLOAD_URL="$URL_TINY"
    VERSION_LABEL="精简版 (tiny)"
else
    DOWNLOAD_URL="$URL_FULL"
    VERSION_LABEL="完整版"
fi

if [ -z "$DOWNLOAD_URL" ]; then
    error "未找到所选版本 (${VERSION_LABEL}) 的下载文件，请尝试另一个版本"
fi

info "选择: ${CYAN}${VERSION_LABEL}${NC}"
info "下载地址: ${YELLOW}${DOWNLOAD_URL}${NC}"

# ========== 6. 下载到临时文件 ==========

TMP_FILE=$(mktemp /tmp/nexttrace.XXXXXX)

info "正在下载 nexttrace ${TAG_NAME} (${VERSION_LABEL})..."
if ! curl -L --fail --max-time 120 -o "$TMP_FILE" "$DOWNLOAD_URL" --progress-bar; then
    error "下载失败，请检查网络连接"
fi

# 基本完整性检查：文件大小不应小于 1MB
FILE_SIZE=$(stat -c%s "$TMP_FILE" 2>/dev/null || stat -f%z "$TMP_FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1048576 ]; then
    error "下载的文件异常 (${FILE_SIZE} 字节)，可能下载不完整或地址失效"
fi

# ========== 7. 安装 ==========

info "正在安装到 ${INSTALL_PATH}..."
chmod +x "$TMP_FILE"
mv -f "$TMP_FILE" "$INSTALL_PATH"
TMP_FILE=""  # 已移走，清空变量避免 cleanup 误删

# ========== 8. 验证 ==========

info "验证安装..."
if nexttrace -V &>/dev/null; then
    INSTALLED_VER=$(nexttrace -V 2>&1 | head -n 1)
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}    nexttrace 安装成功!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "  版本:  ${CYAN}${INSTALLED_VER}${NC}"
    echo -e "  类型:  ${CYAN}${VERSION_LABEL}${NC}"
    echo -e "  路径:  ${CYAN}${INSTALL_PATH}${NC}"
    echo -e "  架构:  ${CYAN}${ARCH}${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "使用方法:"
    echo -e "  ${YELLOW}nexttrace [IP或域名]${NC}"
    echo -e "  ${YELLOW}nexttrace -V${NC}              查看版本"
    echo -e "  ${YELLOW}nexttrace --help${NC}          查看帮助"
else
    warn "安装完成，但验证运行失败，请手动检查: ${INSTALL_PATH}"
fi
