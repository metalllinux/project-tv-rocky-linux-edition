#!/bin/bash
# logging.sh — Timestamped logging to file and stdout
# All installer output is captured for troubleshooting.

LOG_FILE=""
LOG_DIR=""

init_log() {
    LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
    # Redirect stdout and stderr through tee to log file
    exec > >(tee -a "$LOG_FILE") 2>&1
    log_info "============================================="
    log_info "Project TV - Rocky Edition Installer Log"
    log_info "============================================="
    log_info "Date: $(date)"
    log_info "User: $(whoami)"
    log_info "Host: $(hostname)"
    if [[ -f /etc/os-release ]]; then
        log_info "OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    fi
    log_info "Kernel: $(uname -r)"
    log_info "Log file: ${LOG_FILE}"
    log_info "============================================="
}

log_info() {
    echo "[$(date +%H:%M:%S)] [INFO]  $*"
}

log_warn() {
    echo "[$(date +%H:%M:%S)] [WARN]  $*"
}

log_error() {
    echo "[$(date +%H:%M:%S)] [ERROR] $*"
}

log_success() {
    echo "[$(date +%H:%M:%S)] [OK]    $*"
}

# Run a command with logging. Logs the command, runs it, and reports success/failure.
# Usage: log_cmd "description" command arg1 arg2 ...
log_cmd() {
    local desc="$1"
    shift
    log_info "Running: $*"
    if "$@" 2>&1; then
        log_success "$desc"
        return 0
    else
        local rc=$?
        log_error "$desc failed (exit code $rc)"
        return $rc
    fi
}

# Print a section header in the log
log_section() {
    echo ""
    log_info "---------------------------------------------"
    log_info "$*"
    log_info "---------------------------------------------"
}

# Get the current log file path
get_log_file() {
    echo "$LOG_FILE"
}

# Count errors in current log
count_errors() {
    if [[ -f "$LOG_FILE" ]]; then
        grep -c '\[ERROR\]' "$LOG_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
