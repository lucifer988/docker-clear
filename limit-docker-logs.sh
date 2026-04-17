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

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "缺少 $1，请先安装。" >&2; exit 1; }
}

check_docker() {
    need_cmd docker
    docker info >/dev/null 2>&1 || { echo "Docker 未运行。" >&2; exit 1; }
}

# ── 主逻辑 ──────────────────────────────────────────────────────────────────

DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_DIR="/etc/docker/backup-daemon-json"

MAX_SIZE="10m"
MAX_FILE="3"
DRY_RUN=0
APPLY_TRUNCATE=0
RESTART_ALL=0

usage() {
    cat <<EOF
用法: sudo $0 [选项]

选项:
  --max-size <大小>   单个日志文件上限，默认 10m
  --max-file <数量>   保留文件数量，默认 3
  --apply-truncate    同时清空现有日志
  --restart-all       重启所有运行中的容器（使配置立即生效）
  --dry-run           仅预览，不实际修改
  -h, --help          显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-size)      MAX_SIZE="$2"; shift 2 ;;
        --max-file)      MAX_FILE="$2"; shift 2 ;;
        --apply-truncate) APPLY_TRUNCATE=1; shift ;;
        --restart-all)   RESTART_ALL=1; shift ;;
        --dry-run)       DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "未知选项: $1"; usage; exit 1 ;;
    esac
done

require_root
check_docker

# 校验参数
if [[ ! "$MAX_SIZE" =~ ^[0-9]+[kKmMgG]$ ]]; then
    echo "max-size 格式错误，示例: 10m, 200m, 1g" >&2; exit 1
fi
if [[ ! "$MAX_FILE" =~ ^[0-9]+$ ]] || [[ "$MAX_FILE" -lt 1 ]]; then
    echo "max-file 必须为 >= 1 的整数" >&2; exit 1
fi

echo "目标: max-size=$MAX_SIZE, max-file=$MAX_FILE"
[[ "$DRY_RUN" == 1 ]] && echo "[预览模式]"

# ── 备份 ────────────────────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
if [[ -f "$DAEMON_JSON" ]]; then
    TS=$(date +%Y%m%d-%H%M%S)
    if [[ "$DRY_RUN" == 0 ]]; then
        cp -a "$DAEMON_JSON" "${BACKUP_DIR}/daemon.json.${TS}.bak"
    fi
    echo "已备份到: ${BACKUP_DIR}/daemon.json.${TS}.bak"
fi

# ── 生成 JSON ───────────────────────────────────────────────────────────────
need_cmd python3

CURRENT_JSON="{}"
if [[ -f "$DAEMON_JSON" ]]; then
    if ! python3 -c "import json,sys; json.load(open('$DAEMON_JSON'))" 2>/dev/null; then
        echo "daemon.json 不是合法 JSON，请先修复。" >&2; exit 1
    fi
    CURRENT_JSON=$(cat "$DAEMON_JSON")
fi

NEW_JSON=$(python3 - <<PY
import json, sys
data = json.loads(r'''$CURRENT_JSON''' or "{}")

log_opts = data.get("log-opts", {}) if isinstance(data.get("log-opts", {}), dict) else {}
log_opts["max-size"] = "$MAX_SIZE"
log_opts["max-file"] = str("$MAX_FILE")
data["log-opts"] = log_opts

if "log-driver" not in data:
    data["log-driver"] = "json-file"

print(json.dumps(data, indent=2, sort_keys=True))
PY
)

echo "新配置:"
echo "$NEW_JSON"

if [[ "$DRY_RUN" == 0 ]]; then
    echo "$NEW_JSON" > "$DAEMON_JSON"
    echo "已写入: $DAEMON_JSON"

    echo "重载 Docker 配置..."
    systemctl daemon-reload || true
    systemctl restart docker || { echo "Docker 重启失败，请手动检查。" >&2; exit 1; }
    systemctl is-active --quiet docker && echo "Docker 运行正常。"
else
    echo "[预览] 不会写入文件或重启 Docker。"
fi

# ── 截断现有日志 ───────────────────────────────────────────────────────────
if [[ "$APPLY_TRUNCATE" == 1 ]] && [[ "$DRY_RUN" == 0 ]]; then
    LOG_DIR="/var/lib/docker/containers"
    if [[ -d "$LOG_DIR" ]]; then
        COUNT=$(find "$LOG_DIR" -type f -name "*-json.log" | wc -l)
        echo "将截断 $COUNT 个日志文件..."
        find "$LOG_DIR" -type f -name "*-json.log" -exec truncate -s 0 {} \;
        echo "完成。重启容器后新日志轮转生效: docker restart \$(docker ps -q)"
    fi
fi

# ── 重启所有容器 ───────────────────────────────────────────────────────────
if [[ "$RESTART_ALL" == 1 ]] && [[ "$DRY_RUN" == 0 ]]; then
    echo
    RUNNING=$(docker ps -q)
    COUNT=$(echo "$RUNNING" | wc -l)
    if [[ "$COUNT" -eq 0 ]] || [[ "$COUNT" =~ ^\ 0$ ]]; then
        echo "无运行中的容器，跳过重启。"
    else
        echo "重启 $COUNT 个容器..."
        docker restart $RUNNING
        echo "已完成。"
    fi
fi

echo "完毕。"
