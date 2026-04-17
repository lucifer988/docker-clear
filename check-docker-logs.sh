#!/usr/bin/env bash
set -euo pipefail

stat_size() {
    local f="$1"
    stat -c%s "$f" 2>/dev/null && return
    stat -f%z "$f" 2>/dev/null && return
    echo 0
}

human_size() {
    local bytes="${1:-0}"
    local mb gb
    mb=$(awk "BEGIN {printf \"%.2f\", $bytes/1024/1024}")
    gb=$(awk "BEGIN {printf \"%.2f\", $bytes/1024/1024/1024}")
    if [[ $bytes -gt 1073741824 ]]; then
        echo "${gb} GB"
    else
        echo "${mb} MB"
    fi
}

LOG_DIR="/var/lib/docker/containers"
DAEMON_JSON="/etc/docker/daemon.json"

echo "=== Docker 日志检查 ==="
echo

if [[ ! -d "$LOG_DIR" ]]; then
    echo "未找到 Docker 日志目录: $LOG_DIR"
    exit 1
fi

TOTAL=0
declare -a FILES

while IFS= read -r -d '' f; do
    SZ=$(stat_size "$f")
    TOTAL=$((TOTAL + SZ))
    FILES+=("$f:$SZ")
done < <(find "$LOG_DIR" -type f -name "*-json.log" -print0)

echo "--- 前 10 大日志文件 ---"
printf "%-65s %10s\n" "容器 ID" "大小"
echo "---------------------------------------------------------------"

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "无日志文件。"
else
    printf '%s\n' "${FILES[@]}" \
        | sort -t: -k2 -rn \
        | head -10 \
        | while IFS=: read -r path sz; do
            CID=$(basename "$(dirname "$path")")
            printf "%-65s %10s\n" "${CID:0:12}" "$(human_size "$sz")"
          done
fi

echo "---------------------------------------------------------------"
echo "总计: $(human_size $TOTAL)"
echo

echo "--- 当前日志配置 ---"
if [[ -f "$DAEMON_JSON" ]]; then
    if command -v jq >/dev/null 2>&1; then
        jq '.["log-opts"] // empty' "$DAEMON_JSON" 2>/dev/null || echo "未配置日志轮转"
    else
        grep -A3 "log-opts" "$DAEMON_JSON" || echo "未配置日志轮转"
    fi
else
    echo "未找到 daemon.json，未配置日志轮转"
fi

echo
echo "--- 建议 ---"
if [[ $TOTAL -gt 1073741824 ]]; then
    echo "日志超过 1GB，建议运行:"
    echo "  sudo /opt/docker-clear/limit-docker-logs.sh --max-size 20m --max-file 3 --apply-truncate"
fi
