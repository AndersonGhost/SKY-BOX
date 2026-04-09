#!/bin/bash

# ==========================================
# nexttrace-Core 管理脚本（安装 / 更新 / 卸载）
# Original: AndersonGhost/SKY-BOX
# Improved: 状态感知、版本选择、全局安装、安全增强
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
    echo "  --full        直接安装完整版（跳过所有交互）"
    echo "  --tiny        直接安装精简版（跳过所有交互）"
    echo "  --uninstall   直接卸载（跳过菜单选择）"
    echo "  -h, --help    显示帮助信息"
    echo ""
    echo "无参数运行时自动检测状态，已安装则显示操作菜单"
    exit 0
}

# ========== 卸载 ==========

do_uninstall() {
    if [ ! -f "$INSTALL_PATH" ]; then
        warn "未检测到 ${INSTALL_PATH}，无需卸载"
        return 1
    fi
    read -r -p "$(echo -e "${YELLOW}确认卸载 nexttrace？[y/N]: ${NC}")" CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS])
            rm -f "$INSTALL_PATH"
            if [ ! -f "$INSTALL_PATH" ]; then
                info "nexttrace 已成功卸载"
            else
                error "卸载失败，请手动删除: ${INSTALL_PATH}"
            fi
            ;;
        *) echo "已取消。" ;;
    esac
}

# ========== 安装流程 ==========

do_install() {
    # --- 系统检测 ---
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

    # --- 获取最新版本信息 ---
    info "正在从 GitHub (${REPO}) 获取最新版本信息..."

    RESPONSE=$(curl -sL --fail --max-time 15 "$API_URL" 2>&1) || true

    if echo "$RESPONSE" | grep -q "API rate limit exceeded"; then
        error "GitHub API 请求频率超限，请稍后再试"
    fi

    if [ -z "$RESPONSE" ]; then
        error "无法连接到 GitHub API，请检查网络连接或 DNS"
    fi

    TAG_NAME=$(echo "$RESPONSE" | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4)
    if [ -z "$TAG_NAME" ]; then
        error "无法解析版本信息，GitHub API 返回异常"
    fi

    info "最新版本: ${CYAN}${TAG_NAME}${NC}"

    # --- 版本选择 ---
    URL_FULL=$(echo "$RESPONSE" | grep "browser_download_url" | grep "$FILE_KEYWORD" | grep -v "tiny" | head -n 1 | cut -d '"' -f 4)
    URL_TINY=$(echo "$RESPONSE" | grep "browser_download_url" | grep "$FILE_KEYWORD" | grep "tiny" | head -n 1 | cut -d '"' -f 4)

    local VERSION_CHOICE="${1:-}"

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

    # --- 下载 ---
    TMP_FILE=$(mktemp /tmp/nexttrace.XXXXXX)

    info "正在下载 nexttrace ${TAG_NAME} (${VERSION_LABEL})..."
    if ! curl -L --fail --max-time 120 -o "$TMP_FILE" "$DOWNLOAD_URL" --progress-bar; then
        error "下载失败，请检查网络连接"
    fi

    FILE_SIZE=$(stat -c%s "$TMP_FILE" 2>/dev/null || stat -f%z "$TMP_FILE" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -lt 1048576 ]; then
        error "下载的文件异常 (${FILE_SIZE} 字节)，可能下载不完整或地址失效"
    fi

    # --- 安装 ---
    info "正在安装到 ${INSTALL_PATH}..."
    chmod +x "$TMP_FILE"
    mv -f "$TMP_FILE" "$INSTALL_PATH"
    TMP_FILE=""

    # --- 验证 ---
    info "验证安装..."
    FULL_OUTPUT=$(nexttrace -V 2>&1 || true)
    if [ -n "$FULL_OUTPUT" ]; then
        INSTALLED_VER=$(echo "$FULL_OUTPUT" | head -n 1)
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
}

# ========== 参数解析 ==========

VERSION_CHOICE=""
ACTION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --full) VERSION_CHOICE="full"; shift ;;
        --tiny) VERSION_CHOICE="tiny"; shift ;;
        --uninstall) ACTION="uninstall"; shift ;;
        -h|--help) usage ;;
        *) warn "未知参数: $1"; shift ;;
    esac
done

# ========== 权限检查 ==========

if [ "$(id -u)" -ne 0 ]; then
    error "本脚本需要 root 权限，请使用: sudo bash $0"
fi

# ========== 主逻辑：状态感知 ==========

# 命令行直接指定了 --uninstall
if [ "$ACTION" = "uninstall" ]; then
    do_uninstall
    exit 0
fi

# 命令行指定了 --full 或 --tiny，跳过菜单直接安装
if [ -n "$VERSION_CHOICE" ]; then
    do_install "$VERSION_CHOICE"
    exit 0
fi

# 无参数运行：检测是否已安装
if command -v nexttrace &>/dev/null; then
    CURRENT_FULL=$(nexttrace -V 2>&1 || true)
    CURRENT_VER=$(echo "$CURRENT_FULL" | head -n 1)

    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  检测到已安装的 nexttrace${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo -e "  版本: ${GREEN}${CURRENT_VER}${NC}"
    echo -e "  路径: ${GREEN}${INSTALL_PATH}${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
    echo -e "请选择操作:"
    echo -e "  ${GREEN}1)${NC} 重新安装 / 更新"
    echo -e "  ${GREEN}2)${NC} 卸载"
    echo -e "  ${GREEN}3)${NC} 退出"
    echo ""
    read -r -p "$(echo -e "${CYAN}请输入选择 [1/2/3]: ${NC}")" ACTION_CHOICE

    case "$ACTION_CHOICE" in
        1) do_install "" ;;
        2) do_uninstall ;;
        *) echo "已退出。"; exit 0 ;;
    esac
else
    # 未安装，直接进入安装流程
    do_install ""
fi
