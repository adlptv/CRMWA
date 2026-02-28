#!/bin/bash
# Spawn Workers Script - Bash Version
# =====================================
# Spawns all worker agents as background processes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"

WORKER_DELAY="${WORKER_DELAY:-2}"
DRY_RUN="${DRY_RUN:-false}"

WORKERS=(
    "bugfix:iflow-bugfix.yaml:1"
    "coverage:iflow-coverage.yaml:2"
    "refactor:iflow-refactor.yaml:3"
    "lint:iflow-lint.yaml:4"
    "doc:iflow-doc.yaml:5"
)

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$level] $1"
    
    case "$level" in
        ERROR)   echo -e "\033[0;31m$message\033[0m" ;;
        WARN)    echo -e "\033[0;33m$message\033[0m" ;;
        SUCCESS) echo -e "\033[0;32m$message\033[0m" ;;
        *)       echo -e "\033[0;36m$message\033[0m" ;;
    esac
    
    echo "$message" >> "$LOG_DIR/spawn-workers.log"
}

# =============================================================================
# Safety Checks
# =============================================================================

check_shutdown_flag() {
    [[ -f "$SHUTDOWN_FLAG" ]]
}

check_commit_lock() {
    [[ -f "$COMMIT_LOCK" ]]
}

wait_commit_lock() {
    local timeout=${1:-60}
    local start=$(date +%s)
    
    while check_commit_lock; do
        local now=$(date +%s)
        if (( now - start > timeout )); then
            return 1
        fi
        log "Waiting for commit lock to be released..."
        sleep 2
    done
    return 0
}

# =============================================================================
# Worker Functions
# =============================================================================

start_worker() {
    local name="$1"
    local config="$2"
    local priority="$3"
    
    # Check for shutdown before starting
    if check_shutdown_flag; then
        log "Shutdown flag detected, not starting worker: $name" "WARN"
        return 1
    fi
    
    local worker_script="$PROJECT_ROOT/worker-$name.sh"
    
    if [[ ! -f "$worker_script" ]]; then
        log "Worker script not found: $worker_script" "ERROR"
        return 1
    fi
    
    local config_path="$PROJECT_ROOT/$config"
    if [[ ! -f "$config_path" ]]; then
        log "Worker config not found: $config_path" "WARN"
    fi
    
    log "Starting worker: $name (Priority: $priority)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would start $name worker"
        return 0
    fi
    
    # Make script executable
    chmod +x "$worker_script"
    
    # Start worker in background
    nohup bash "$worker_script" > "$LOG_DIR/worker-$name.log" 2>&1 &
    local pid=$!
    
    # Save PID
    echo "$pid" > "$PROJECT_ROOT/worker-$name.pid"
    
    log "Worker $name started with PID $pid" "SUCCESS"
    return 0
}

start_all_workers() {
    log "Starting all workers..."
    
    local started=0
    local failed=0
    
    # Sort by priority (already sorted in array)
    for worker_info in "${WORKERS[@]}"; do
        IFS=':' read -r name config priority <<< "$worker_info"
        
        # Check for shutdown flag between workers
        if check_shutdown_flag; then
            log "Shutdown flag detected, stopping worker spawn" "WARN"
            break
        fi
        
        # Wait for commit lock if present
        wait_commit_lock 30 || log "Could not acquire lock, continuing..." "WARN"
        
        if start_worker "$name" "$config" "$priority"; then
            ((started++))
        else
            ((failed++))
        fi
        
        # Delay between worker starts
        if [[ $WORKER_DELAY -gt 0 ]]; then
            sleep "$WORKER_DELAY"
        fi
    done
    
    log "Worker spawn complete. Started: $started, Failed: $failed"
    
    echo "Started: $started"
    echo "Failed: $failed"
    echo "Total: ${#WORKERS[@]}"
}

get_worker_status() {
    echo ""
    echo "Worker Status Summary"
    echo "====================="
    echo ""
    
    for worker_info in "${WORKERS[@]}"; do
        IFS=':' read -r name config priority <<< "$worker_info"
        
        local pid_file="$PROJECT_ROOT/worker-$name.pid"
        local status_file="$LOG_DIR/worker-$name-status.txt"
        local running=false
        local pid=""
        local status="unknown"
        
        # Check PID file
        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                running=true
            fi
        fi
        
        # Check status file
        if [[ -f "$status_file" ]]; then
            status=$(cat "$status_file" 2>/dev/null | tr -d '\n')
        fi
        
        # Print status
        if [[ "$running" == "true" ]]; then
            echo -e "  $name: \033[0;32mRUNNING\033[0m (PID: $pid, Status: $status)"
        else
            echo -e "  $name: \033[0;31mSTOPPED\033[0m (Status: $status)"
        fi
    done
    
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Worker Spawn Script Starting"
    log "============================================"
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Check for existing shutdown flag
    if check_shutdown_flag; then
        log "Shutdown flag is set. Clearing before spawn..." "WARN"
        rm -f "$SHUTDOWN_FLAG"
    fi
    
    # Start all workers
    start_all_workers
    
    # Show status
    get_worker_status
    
    log "Spawn process complete"
}

main "$@"
