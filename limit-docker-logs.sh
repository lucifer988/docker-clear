#!/usr/bin/env bash
set -euo pipefail

# limit-docker-logs.sh
# One-click script to limit Docker container log size on Debian/Ubuntu.
# It configures /etc/docker/daemon.json with json-file log rotation:
#   log-opts: max-size, max-file
#
# Usage:
#   sudo ./limit-docker-logs.sh                # defaults: 10m * 3 files
#   sudo ./limit-docker-logs.sh --max-size 20m --max-file 5
#   sudo ./limit-docker-logs.sh --apply-truncate   # optional: truncate existing huge *.log
#   sudo ./limit-docker-logs.sh --dry-run
#
# Notes:
# - Applies to docker log driver "json-file". If your daemon uses journald, see tips below.
# - Existing huge logs are not automatically reduced; use --apply-truncate carefully.

MAX_SIZE="10m"
MAX_FILE="3"
APPLY_TRUNCATE="0"
DRY_RUN="0"

print_help() {
  cat <<EOF
Docker log limiter (Debian/Ubuntu)

Options:
  --max-size <size>     e.g. 10m, 50m, 200m (default: ${MAX_SIZE})
  --max-file <num>      number of rotated files kept (default: ${MAX_FILE})
  --apply-truncate      truncate existing container json logs to 0 (optional, careful!)
  --dry-run             show what would change but do nothing
  -h, --help            show help

Examples:
  sudo ./limit-docker-logs.sh
  sudo ./limit-docker-logs.sh --max-size 20m --max-file 5
  sudo ./limit-docker-logs.sh --apply-truncate
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-size)
      MAX_SIZE="${2:-}"; shift 2;;
    --max-file)
      MAX_FILE="${2:-}"; shift 2;;
    --apply-truncate)
      APPLY_TRUNCATE="1"; shift 1;;
    --dry-run)
      DRY_RUN="1"; shift 1;;
    -h|--help)
      print_help; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      print_help
      exit 1;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0 ..." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker command not found. Install Docker first." >&2
  exit 1
fi

# Basic validation
if [[ ! "${MAX_SIZE}" =~ ^[0-9]+[kKmMgG]$ ]]; then
  echo "Invalid --max-size '${MAX_SIZE}'. Use like 10m, 200m, 1g." >&2
  exit 1
fi
if [[ ! "${MAX_FILE}" =~ ^[0-9]+$ ]] || [[ "${MAX_FILE}" -lt 1 ]]; then
  echo "Invalid --max-file '${MAX_FILE}'. Must be an integer >= 1." >&2
  exit 1
fi

DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_DIR="/etc/docker/backup-daemon-json"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_PATH="${BACKUP_DIR}/daemon.json.${TS}.bak"

echo "Target config:"
echo "  max-size = ${MAX_SIZE}"
echo "  max-file = ${MAX_FILE}"
echo "  daemon.json = ${DAEMON_JSON}"
echo

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "[DRY RUN] No changes will be made."
fi

mkdir -p "${BACKUP_DIR}"

# Backup existing daemon.json if present
if [[ -f "${DAEMON_JSON}" ]]; then
  if [[ "${DRY_RUN}" == "0" ]]; then
    cp -a "${DAEMON_JSON}" "${BACKUP_PATH}"
  fi
  echo "Backup: ${BACKUP_PATH}"
else
  echo "No existing daemon.json found; will create a new one."
fi

# Create temp file and write merged json using python (available on Debian/Ubuntu)
TMP="$(mktemp)"
cleanup() { rm -f "${TMP}"; }
trap cleanup EXIT

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Python is required to safely edit JSON. Please install python3." >&2
  exit 1
fi

CURRENT_JSON="{}"
if [[ -f "${DAEMON_JSON}" ]]; then
  # If file is empty or invalid JSON, abort safely
  if ! "${PYTHON_BIN}" -c "import json,sys; json.load(open('${DAEMON_JSON}')); print('ok')" >/dev/null 2>&1; then
    echo "ERROR: ${DAEMON_JSON} exists but is not valid JSON. Fix it first, or restore from backup." >&2
    exit 1
  fi
  CURRENT_JSON="$(cat "${DAEMON_JSON}")"
fi

NEW_JSON="$("${PYTHON_BIN}" - <<PY
import json, sys
data = json.loads(r'''$CURRENT_JSON''' or "{}")

# Ensure json-file rotation settings
# Keep existing settings, only set/override these keys.
log_opts = data.get("log-opts", {}) if isinstance(data.get("log-opts", {}), dict) else {}
log_opts["max-size"] = "$MAX_SIZE"
log_opts["max-file"] = str("$MAX_FILE")  # Docker expects string values here
data["log-opts"] = log_opts

# Ensure log-driver is json-file if not explicitly set (optional).
# If user already set something else, don't override.
if "log-driver" not in data:
    data["log-driver"] = "json-file"

print(json.dumps(data, indent=2, sort_keys=True))
PY
)"

echo "New daemon.json content:"
echo "----------------------------------------"
echo "${NEW_JSON}"
echo "----------------------------------------"
echo

if [[ "${DRY_RUN}" == "0" ]]; then
  echo "${NEW_JSON}" > "${TMP}"
  install -m 0644 "${TMP}" "${DAEMON_JSON}"
  echo "Written: ${DAEMON_JSON}"
else
  echo "[DRY RUN] Would write ${DAEMON_JSON}"
fi

# Restart docker to apply
echo
echo "Restarting Docker daemon to apply changes..."
if [[ "${DRY_RUN}" == "0" ]]; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart docker
  systemctl is-active --quiet docker && echo "Docker is active."
else
  echo "[DRY RUN] Would run: systemctl restart docker"
fi

# Optional: truncate existing huge container json logs
if [[ "${APPLY_TRUNCATE}" == "1" ]]; then
  echo
  echo "WARNING: --apply-truncate will truncate existing container JSON logs to 0 bytes."
  echo "This does NOT remove containers, but you will lose old logs."
  echo
  if [[ "${DRY_RUN}" == "0" ]]; then
    # Docker container logs are usually under /var/lib/docker/containers/<id>/<id>-json.log
    LOG_DIR="/var/lib/docker/containers"
    if [[ -d "${LOG_DIR}" ]]; then
      find "${LOG_DIR}" -type f -name "*-json.log" -print -exec truncate -s 0 {} \;
      echo "Truncated all *-json.log under ${LOG_DIR}."
    else
      echo "Directory not found: ${LOG_DIR}. Skipping truncate."
    fi
  else
    echo "[DRY RUN] Would truncate: /var/lib/docker/containers/*/*-json.log"
  fi
fi

echo
echo "Done."
echo "Tip: New containers will respect log rotation; for existing containers, restart them if needed:"
echo "  docker restart <container>"
