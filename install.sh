#!/usr/bin/env bash
set -euo pipefail
#
# 一键安装: curl -fsSL https://raw.githubusercontent.com/lucifer988/docker-clear/main/install.sh | sudo bash
#

INSTALL_DIR="${INSTALL_DIR:-/opt/docker-clear}"
BRANCH="${BRANCH:-main}"
GITHUB_RAW="https://raw.githubusercontent.com/lucifer988/docker-clear/${BRANCH}"

echo "=== Docker Clear 安装 ==="
echo "安装目录: $INSTALL_DIR"
echo

[[ "${EUID:-}" -ne 0 ]] && { echo "请用 root 运行: sudo $0"; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "安装依赖 $1..."; apt-get update -qq && apt-get install -y -qq "$1"; }
}

need_cmd curl; need_cmd python3

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "下载脚本..."
for script in limit-docker-logs.sh check-docker-logs.sh clean-container-logs.sh; do
    if curl -fsSL "${GITHUB_RAW}/${script}" -o "$script" 2>/dev/null; then
        chmod +x "$script"
        echo "  ✓ $script"
    else
        echo "  ✗ $script 下载失败"
    fi
done

echo
echo "安装完毕。脚本: $INSTALL_DIR"
echo
echo "使用:"
echo "  sudo $INSTALL_DIR/check-docker-logs.sh      # 检查日志占用"
echo "  sudo $INSTALL_DIR/limit-docker-logs.sh      # 限制日志大小"
echo "  sudo $INSTALL_DIR/clean-container-logs.sh --all  # 清理所有日志"
echo
echo "定时清理（可选）:"
echo "  echo '0 3 * * 0 root $INSTALL_DIR/clean-container-logs.sh --all' >> /etc/crontab"
