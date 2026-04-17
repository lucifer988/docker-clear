#!/usr/bin/env bash
# docker-clear/lib.sh — shared functions for all docker-clear scripts
# Source this from other scripts: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# ── Root guard ──────────────────────────────────────────────────────────────
require_root() {
    if [[ "${EUID:-}" -ne 0 ]]; then
        echo "请用 root 运行: sudo $0 ..." >&2
        exit 1
    fi
}

# ── Cross-platform stat ─────────────────────────────────────────────────────
# Prints file size in bytes; falls back to 0 on error.
stat_size() {
    local file="$1"
    if command -v stat >/dev/null 2>&1; then
        # Linux
        stat -c%s "$file" 2>/dev/null && return
        # macOS
        stat -f%z "$file" 2>/dev/null && return
    fi
    echo 0
}

# ── Human-readable size ─────────────────────────────────────────────────────
human_size() {
    local bytes="${1:-0}"
    if command -v bc >/dev/null 2>&1; then
        local mb gb
        mb=$(echo "scale=2; $bytes / 1024 / 1024" | bc 2>/dev/null || echo "0")
        if command -v bc >/dev/null 2>&1 && echo "$mb > 1024" | bc -l >/dev/null 2>&1; then
            gb=$(echo "scale=2; $mb / 1024" | bc 2>/dev/null || echo "0")
            echo "${gb} GB"
        else
            echo "${mb} MB"
        fi
    else
        # Fallback: plain arithmetic, no bc
        local mb
        mb=$(( (bytes + 524288) / 1048576 ))   # round up
        if [[ $mb -gt 1024 ]]; then
            echo "$(( mb / 1024 )) GB"
        else
            echo "${mb} MB"
        fi
    fi
}

# ── Dependency checker ──────────────────────────────────────────────────────
need_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "缺少依赖 '$cmd'，请先安装。" >&2
        exit 1
    fi
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 未安装或不在 PATH 中。" >&2
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Docker 守护进程未运行。" >&2
        exit 1
    fi
}

# ── Safe JSON write via Python ──────────────────────────────────────────────
write_daemon_json() {
    local path="$1" json="$2"
    local tmp
    tmp=$(mktemp)
    trap "rm -f '$tmp'" EXIT
    echo "$json" > "$tmp"
    install -m 0644 "$tmp" "$path"
}
