#!/bin/bash
# Process Killer Script - Bash Version
# =====================================
# Utility for forcefully terminating AI agent loop processes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"

WORKERS=("bugfix" "coverage" "refactor" "lint" "doc")
TIMEOUT="${TIMEOUT:-30}"

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [PROCESS-KILLER] [$level] $1"
    
    case "$level" in
        ERROR)   echo -e "\033[0;31m$message\033[0m" ;;
        WARN)    echo -e "\033[0;33m$message\033[0m" ;;
        SUCCESS) echo -e "\033[0;32m$message\033[0m" ;;
        *)       echo -e "\033[0;36m$message\033[0m" ;;
    esac
}

# =============================================================================
# Process Functions
# =============================================================================

stop_process_by_pidfile() {
    local pidfile="$1"
    local name="$2"
    
    if [[ ! -f "$pidfile" ]]; then
        log "PID file not found: $pidfile" "WARN"
        return 1
    fi
    
    local pid=$(cat "$pidfile" 2>/dev/null)
    if [[ -z "$pid" ]]; then
        log "No PID in file: $pidfile" "WARN"
        return 1
    fi
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log "$name process not running (PID: $pid)" "WARN"
        rm -f "$pidfile"
        return 0
    fi
    
    log "Stopping $name (PID: $pid)..."
    
    # Try graceful termination first
    kill -TERM "$pid" 2>/dev/null || true
    
    # Wait for process to exit
    local waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < TIMEOUT * 10 )); do
        sleep 0.1
        ((waited++))
    done
    
    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        log "Force killing $name (PID: $pid)" "WARN"
        kill -KILL "$pid" 2>/dev/null || true
    fi
    
    rm -f "$pidfile"
    log "$name stopped" "SUCCESS"
    return 0
}

stop_worker() {
    local worker_name="$1"
    local pidfile="$PROJECT_ROOT/worker-$worker_name.pid"
    stop_process_by_pidfile "$pidfile" "$worker_name worker"
}

stop_all_workers() {
    log "Stopping all workers..."
    for worker in "${WORKERS[@]}"; do
        stop_worker "$worker"
    done
}

stop_controller() {
    local pidfile="$PROJECT_ROOT/controller.pid"
    stop_process_by_pidfile "$pidfile" "controller"
}

stop_quota_monitor() {
    log "Stopping quota monitor..."
    pkill -f "quota-monitor" 2>/dev/null || true
    log "Quota monitor stopped" "SUCCESS"
}

stop_all_iflow() {
    log "Stopping all iFlow processes..."
    pkill -f "iflow" 2>/dev/null || true
    log "All iFlow processes stopped" "SUCCESS"
}

stop_everything() {
    log "============================================"
    log "Stopping All Processes"
    log "============================================"
    
    stop_all_workers
    stop_controller
    stop_quota_monitor
    stop_all_iflow
    
    log "All processes stopped" "SUCCESS"
}

show_status() {
    echo ""
    echo -e "\033[0;36mProcess Status\033[0m"
    echo -e "\033[0;36m==============\033[0m"
    echo ""
    
    # Check controller
    local controller_pidfile="$PROJECT_ROOT/controller.pid"
    if [[ -f "$controller_pidfile" ]]; then
        local pid=$(cat "$controller_pidfile" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "  Controller: \033[0;32mRUNNING\033[0m (PID: $pid)"
        else
            echo -e "  Controller: \033[0;31mSTOPPED (stale PID file)\033[0m"
        fi
    else
        echo -e "  Controller: \033[0;33mNOT STARTED\033[0m"
    fi
    
    # Check workers
    for worker in "${WORKERS[@]}"; do
        local pidfile="$PROJECT_ROOT/worker-$worker.pid"
        if [[ -f "$pidfile" ]]; then
            local pid=$(cat "$pidfile" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                echo -e "  $worker worker: \033[0;32mRUNNING\033[0m (PID: $pid)"
            else
                echo -e "  $worker worker: \033[0;31mSTOPPED (stale PID file)\033[0m"
            fi
        else
            echo -e "  $worker worker: \033[0;33mNOT STARTED\033[0m"
        fi
    done
    
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    local action="${1:-status}"
    
    log "Process Killer - PID: $$"
    mkdir -p "$LOG_DIR"
    
    case "$action" in
        all)      stop_everything ;;
        workers)  stop_all_workers ;;
        controller) stop_controller ;;
        quota)    stop_quota_monitor ;;
        iflow)    stop_all_iflow ;;
        status)   show_status ;;
        *)
            # Check if it's a worker name
            for worker in "${WORKERS[@]}"; do
                if [[ "$action" == "$worker" ]]; then
                    stop_worker "$action"
                    return
                fi
            done
            echo "Usage: $0 {all|workers|controller|quota|iflow|status|<worker_name>}"
            exit 1
            ;;
    esac
}

main "$@"
