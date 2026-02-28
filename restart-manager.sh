#!/bin/bash
# Restart Manager Script - Bash Version
# ======================================
# Handles controlled restart of the AI agent loop system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
RESTART_LOG="$LOG_DIR/restart.log"
RESTART_TRACKER="$PROJECT_ROOT/restart.track"

RESTART_DELAY="${RESTART_DELAY:-5}"
MAX_RESTARTS="${MAX_RESTARTS:-3}"
RESTART_WINDOW_MINUTES="${RESTART_WINDOW_MINUTES:-10}"

WORKERS=("bugfix" "coverage" "refactor" "lint" "doc")

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [RESTART-MANAGER] [$level] $1"
    
    case "$level" in
        ERROR)   echo -e "\033[0;31m$message\033[0m" ;;
        WARN)    echo -e "\033[0;33m$message\033[0m" ;;
        SUCCESS) echo -e "\033[0;32m$message\033[0m" ;;
        *)       echo -e "\033[0;36m$message\033[0m" ;;
    esac
    
    echo "$message" >> "$RESTART_LOG"
}

# =============================================================================
# Restart Tracking
# =============================================================================

get_restart_count() {
    if [[ ! -f "$RESTART_TRACKER" ]]; then
        echo 0
        return
    fi
    
    local cutoff=$(date -d "-$RESTART_WINDOW_MINUTES minutes" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                   date -v-${RESTART_WINDOW_MINUTES}M '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    
    local count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            local entry_date="${BASH_REMATCH[1]}"
            if [[ "$entry_date" > "$cutoff" ]]; then
                ((count++))
            fi
        fi
    done < "$RESTART_TRACKER"
    
    echo "$count"
}

register_restart() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - Restart initiated" >> "$RESTART_TRACKER"
    log "Restart registered at $timestamp"
}

can_restart() {
    local count=$(get_restart_count)
    if (( count >= MAX_RESTARTS )); then
        log "Maximum restart attempts ($MAX_RESTARTS) reached within $RESTART_WINDOW_MINUTES minutes" "ERROR"
        return 1
    fi
    return 0
}

# =============================================================================
# Process Management
# =============================================================================

stop_all_workers() {
    log "Stopping all worker processes..."
    
    for worker in "${WORKERS[@]}"; do
        local pid_file="$PROJECT_ROOT/worker-$worker.pid"
        
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                log "Stopping $worker worker (PID: $pid)"
                kill -TERM "$pid" 2>/dev/null || true
                sleep 1
                kill -KILL "$pid" 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    done
    
    # Kill any remaining iflow processes
    pkill -f "iflow" 2>/dev/null || true
    
    sleep 2
    log "All workers stopped" "SUCCESS"
}

stop_controller() {
    log "Stopping controller..."
    
    local pid_file="$PROJECT_ROOT/controller.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log "Stopping controller (PID: $pid)"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
}

stop_quota_monitor() {
    log "Stopping quota monitor..."
    pkill -f "quota-monitor" 2>/dev/null || true
}

# =============================================================================
# State Cleanup
# =============================================================================

clear_all_locks() {
    log "Clearing all locks..."
    
    rm -f "$COMMIT_LOCK" 2>/dev/null && log "Commit lock cleared" || true
    rm -f "$SHUTDOWN_FLAG" 2>/dev/null && log "Shutdown flag cleared" || true
}

reset_git_state() {
    log "Resetting Git state..."
    
    cd "$PROJECT_ROOT"
    git reset --hard HEAD 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    log "Git state reset" "SUCCESS"
}

# =============================================================================
# Restart Execution
# =============================================================================

start_controller() {
    log "Starting controller..."
    
    local script="$PROJECT_ROOT/controller.sh"
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        nohup bash "$script" > "$LOG_DIR/controller.log" 2>&1 &
        log "Controller started" "SUCCESS"
    else
        log "Controller script not found: $script" "ERROR"
    fi
}

do_restart() {
    log "============================================"
    log "Initiating System Restart"
    log "============================================"
    
    # Check if we can restart
    if ! can_restart; then
        log "INSUFFICIENT QUOTA - SYSTEM HALTED" "ERROR"
        log "Maximum restart attempts exceeded. Manual intervention required."
        
        # Create halt marker
        local halt_file="$LOG_DIR/system.halted"
        echo "HALTED at $(date '+%Y-%m-%d %H:%M:%S') - Max restarts exceeded" > "$halt_file"
        
        return 1
    fi
    
    # Register restart
    register_restart
    
    # Phase 1: Stop all processes
    log "Phase 1: Stopping processes..."
    stop_all_workers
    stop_controller
    stop_quota_monitor
    
    # Phase 2: Cleanup state
    log "Phase 2: Cleaning up state..."
    clear_all_locks
    reset_git_state
    
    # Phase 3: Wait
    log "Phase 3: Waiting $RESTART_DELAY seconds..."
    sleep "$RESTART_DELAY"
    
    # Phase 4: Restart
    log "Phase 4: Starting system..."
    start_controller
    
    log "Restart completed successfully" "SUCCESS"
    return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Restart Manager Starting"
    log "============================================"
    log "PID: $$"
    log "Max Restarts: $MAX_RESTARTS"
    log "Restart Window: $RESTART_WINDOW_MINUTES minutes"
    
    mkdir -p "$LOG_DIR"
    
    if do_restart; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
