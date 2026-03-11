#!/usr/bin/env bash
set -euo pipefail

# clean-container-logs.sh
# 批量清理指定容器的日志

print_help() {
  cat <<EOF
批量清理 Docker 容器日志

用法:
  sudo ./clean-container-logs.sh [容器ID/名称...]
  sudo ./clean-container-logs.sh --all

选项:
  --all       清理所有容器日志
  --dry-run   预览模式
  -h, --help  显示帮助

示例:
  sudo ./clean-container-logs.sh nginx mysql
  sudo ./clean-container-logs.sh --all
EOF
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 权限运行" >&2
  exit 1
fi

DRY_RUN=0
CLEAN_ALL=0
CONTAINERS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) CLEAN_ALL=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) print_help; exit 0;;
    *) CONTAINERS+=("$1"); shift;;
  esac
done

if [[ ${CLEAN_ALL} -eq 0 ]] && [[ ${#CONTAINERS[@]} -eq 0 ]]; then
  echo "错误：请指定容器或使用 --all" >&2
  print_help
  exit 1
fi

LOG_DIR="/var/lib/docker/containers"

if [[ ${CLEAN_ALL} -eq 1 ]]; then
  echo "清理所有容器日志..."
  CONTAINERS=($(docker ps -aq))
fi

for container in "${CONTAINERS[@]}"; do
  CONTAINER_ID=$(docker inspect -f '{{.Id}}' "$container" 2>/dev/null || echo "")
  
  if [[ -z "${CONTAINER_ID}" ]]; then
    echo "⚠️  容器不存在: $container"
    continue
  fi
  
  LOG_FILE="${LOG_DIR}/${CONTAINER_ID}/${CONTAINER_ID}-json.log"
  
  if [[ ! -f "${LOG_FILE}" ]]; then
    echo "⚠️  日志文件不存在: $container"
    continue
  fi
  
  SIZE=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
  SIZE_MB=$(awk "BEGIN {printf \"%.2f\", ${SIZE}/1024/1024}")
  
  if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "[预览] 将清理: $container (${SIZE_MB} MB)"
  else
    truncate -s 0 "${LOG_FILE}"
    echo "✓ 已清理: $container (${SIZE_MB} MB)"
  fi
done

echo
echo "完成！"
