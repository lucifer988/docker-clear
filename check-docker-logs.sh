#!/usr/bin/env bash
set -euo pipefail

# check-docker-logs.sh
# 检查 Docker 容器日志占用空间

echo "=== Docker 日志占用检查 ==="
echo

LOG_DIR="/var/lib/docker/containers"

if [[ ! -d "${LOG_DIR}" ]]; then
    echo "错误：找不到 Docker 日志目录: ${LOG_DIR}"
    exit 1
fi

echo "正在扫描容器日志..."
echo

TOTAL_SIZE=0
declare -a LOG_FILES

while IFS= read -r -d '' logfile; do
    SIZE=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0)
    TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
    LOG_FILES+=("$logfile:$SIZE")
done < <(find "${LOG_DIR}" -type f -name "*-json.log" -print0)

# 排序并显示前 10 大日志
echo "📊 日志文件统计："
echo "----------------------------------------"
printf "%-60s %10s\n" "容器 ID" "大小"
echo "----------------------------------------"

for entry in "${LOG_FILES[@]}"; do
    echo "$entry"
done | sort -t: -k2 -rn | head -10 | while IFS=: read -r file size; do
    CONTAINER_ID=$(basename "$(dirname "$file")")
    SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $size/1024/1024}")
    printf "%-60s %8s MB\n" "${CONTAINER_ID:0:12}" "$SIZE_MB"
done

echo "----------------------------------------"
TOTAL_MB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE/1024/1024}")
TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE/1024/1024/1024}")
echo "总计: ${TOTAL_MB} MB (${TOTAL_GB} GB)"
echo

# 检查配置
DAEMON_JSON="/etc/docker/daemon.json"
if [[ -f "${DAEMON_JSON}" ]]; then
    echo "📋 当前配置："
    if command -v jq >/dev/null 2>&1; then
        jq '.["log-opts"]' "${DAEMON_JSON}" 2>/dev/null || echo "未配置日志轮转"
    else
        grep -A 3 "log-opts" "${DAEMON_JSON}" || echo "未配置日志轮转"
    fi
else
    echo "⚠️  未找到 /etc/docker/daemon.json"
fi

echo
echo "💡 建议："
if (( $(echo "$TOTAL_GB > 1" | bc -l 2>/dev/null || echo 0) )); then
    echo "  日志占用超过 1GB，建议运行："
    echo "  sudo ./limit-docker-logs.sh --max-size 20m --max-file 3"
fi
