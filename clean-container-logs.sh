#!/usr/bin/env bash
set -euo pipefail

# ── 共享函数（内嵌）─────────────────────────────────────────────────────────

require_root() {
    if [[ "${EUID:-}" -ne 0 ]]; then
        echo "请用 root 运行: sudo $0 ..." >&2
        exit 1
    fi
}

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

# ── 主逻辑 ──────────────────────────────────────────────────────────────────

LOG_DIR="/var/lib/docker/containers"
DRY_RUN=0
CLEAN_ALL=0
CONTAINERS=()

usage() {
    cat <<EOF
用法: sudo $0 [容器名... | --all] [选项]

示例:
  sudo $0 nginx mysql redis        # 清理指定容器
  sudo $0 --all                    # 清理所有容器
  sudo $0 --all --dry-run          # 预览

选项:
  --dry-run   仅预览，不实际清理
  -h, --help  帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)      CLEAN_ALL=1; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          CONTAINERS+=("$1"); shift ;;
    esac
done

require_root

if [[ $CLEAN_ALL -eq 0 ]] && [[ ${#CONTAINERS[@]} -eq 0 ]]; then
    echo "请指定容器名或使用 --all" >&2
    usage; exit 1
fi

if [[ $CLEAN_ALL -eq 1 ]]; then
    CONTAINERS=($(docker ps -aq))
fi

CLEANED=0
for name in "${CONTAINERS[@]}"; do
    CID=$(docker inspect -f '{{.Id}}' "$name" 2>/dev/null || true)
    if [[ -z "$CID" ]]; then
        echo "容器不存在: $name"; continue
    fi

    LOG_FILE="${LOG_DIR}/${CID}/${CID}-json.log"
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "无日志文件: $name"; continue
    fi

    SZ=$(stat_size "$LOG_FILE")
    [[ "$DRY_RUN" == 1 ]] && echo "[预览] 将清理: $name ($(human_size $SZ))" && continue

    truncate -s 0 "$LOG_FILE"
    echo "已清理: $name ($(human_size $SZ))"
    CLEANED=$((CLEANED + 1))
done

echo
if [[ "$DRY_RUN" == 0 ]]; then
    echo "清理了 $CLEANED 个容器日志。"
fi
