#!/bin/bash
# AI Agent Loop Controller - Bash Version
# ========================================
# Main controller for autonomous multi-agent AI development loop
# with quota monitoring and auto-recovery

set -euo pipefail

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
CONFIG_FILE="$PROJECT_ROOT/config.env"

# State files
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"
RESTART_LOG="$LOG_DIR/restart.log"
CONTROLLER_PID="$PROJECT_ROOT/controller.pid"

# Restart tracking
RESTART_TRACKER="$PROJECT_ROOT/restart.track"
MAX_RESTART_ATTEMPTS=3
RESTART_WINDOW_MINUTES=10

# Workers
WORKERS=("bugfix" "coverage" "refactor" "lint" "doc")

# =============================================================================
# Logging Functions
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
    
    echo "$message" >> "$LOG_DIR/controller.log"
}

log_restart() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$RESTART_LOG"
}

# =============================================================================
# Configuration Functions
# =============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes from value
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            
            export "$key=$value"
        done < "$CONFIG_FILE"
        log "Configuration loaded from $CONFIG_FILE"
    else
        log "Using default configuration" "WARN"
    fi
}

# =============================================================================
# Safety Functions
# =============================================================================

check_shutdown_flag() {
    [[ -f "$SHUTDOWN_FLAG" ]]
}

set_shutdown_flag() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "SHUTDOWN_REQUESTED=$timestamp" > "$SHUTDOWN_FLAG"
    log "Shutdown flag set" "WARN"
}

clear_shutdown_flag() {
    if [[ -f "$SHUTDOWN_FLAG" ]]; then
        rm -f "$SHUTDOWN_FLAG"
        log "Shutdown flag cleared"
    fi
}

check_commit_lock() {
    [[ -f "$COMMIT_LOCK" ]]
}

set_commit_lock() {
    local pid=$$
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "PID=$pid" > "$COMMIT_LOCK"
    echo "TIMESTAMP=$timestamp" >> "$COMMIT_LOCK"
    log "Commit lock acquired by PID $pid"
}

clear_commit_lock() {
    if [[ -f "$COMMIT_LOCK" ]]; then
        rm -f "$COMMIT_LOCK"
        log "Commit lock released"
    fi
}

wait_commit_lock() {
    local timeout=${1:-60}
    local start=$(date +%s)
    
    while check_commit_lock; do
        local now=$(date +%s)
        if (( now - start > timeout )); then
            log "Commit lock wait timeout exceeded" "ERROR"
            return 1
        fi
        log "Waiting for commit lock..."
        sleep 2
    done
    return 0
}

# =============================================================================
# Git Functions
# =============================================================================

init_git_repository() {
    local repo_url="$1"
    local branch_name="$2"
    
    log "Initializing Git repository..."
    
    if [[ -n "$repo_url" ]]; then
        log "Cloning repository: $repo_url"
        git clone "$repo_url" . || {
            log "Failed to clone repository" "ERROR"
            return 1
        }
    elif [[ ! -d ".git" ]]; then
        log "Initializing new Git repository"
        git init
        git config user.name "AI Agent"
        git config user.email "ai-agent@automaton.local"
    fi
    
    # Create and switch to ai-dev branch
    local current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ "$current_branch" != "$branch_name" ]]; then
        log "Creating/switching to branch: $branch_name"
        git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"
    fi
    
    log "Git repository initialized on branch: $branch_name" "SUCCESS"
    return 0
}

reset_git_state() {
    log "Resetting Git state..."
    git reset --hard HEAD
    git clean -fd
    clear_commit_lock
    log "Git state reset complete"
}

# =============================================================================
# Restart Management
# =============================================================================

get_restart_count() {
    if [[ ! -f "$RESTART_TRACKER" ]]; then
        echo 0
        return
    fi
    
    local cutoff=$(date -d "-$RESTART_WINDOW_MINUTES minutes" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-${RESTART_WINDOW_MINUTES}M '+%Y-%m-%d %H:%M:%S')
    local count=$(grep -E '^\d{4}-\d{2}-\d{2}' "$RESTART_TRACKER" | while read -r line; do
        local entry_date=$(echo "$line" | grep -oE '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
        if [[ "$entry_date" > "$cutoff" ]]; then
            echo "$line"
        fi
    done | wc -l)
    
    echo "$count"
}

register_restart() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - Restart registered" >> "$RESTART_TRACKER"
    log_restart "Restart registered at $timestamp"
}

can_restart() {
    local count=$(get_restart_count)
    if (( count >= MAX_RESTART_ATTEMPTS )); then
        log "Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached within $RESTART_WINDOW_MINUTES minutes" "ERROR"
        return 1
    fi
    return 0
}

# =============================================================================
# Quota Functions
# =============================================================================

get_quota_status() {
    if [[ ! -f "$QUOTA_STATUS" ]]; then
        echo '{"Percentage": 100, "Available": "unknown", "Used": "unknown"}'
        return
    fi
    cat "$QUOTA_STATUS"
}

is_quota_critical() {
    local status=$(get_quota_status)
    local percentage=$(echo "$status" | grep -oE '"Percentage": *[0-9]+' | grep -oE '[0-9]+')
    (( percentage < 10 ))
}

# =============================================================================
# Process Management
# =============================================================================

save_controller_pid() {
    echo $$ > "$CONTROLLER_PID"
    log "Controller PID saved: $$"
}

stop_worker_processes() {
    log "Stopping worker processes..."
    
    # Kill all iflow processes
    pkill -f "iflow" 2>/dev/null || true
    
    # Kill any node processes running worker scripts
    for worker in "${WORKERS[@]}"; do
        pkill -f "worker-$worker" 2>/dev/null || true
    done
    
    sleep 2
    log "Worker processes stopped"
}

start_quota_monitor() {
    log "Starting quota monitor..."
    
    local monitor_script="$PROJECT_ROOT/quota-monitor.sh"
    if [[ -f "$monitor_script" ]]; then
        chmod +x "$monitor_script"
        nohup bash "$monitor_script" > /dev/null 2>&1 &
        log "Quota monitor started" "SUCCESS"
    else
        log "Quota monitor script not found: $monitor_script" "WARN"
    fi
}

# =============================================================================
# Worker Spawning
# =============================================================================

start_workers() {
    log "Starting workers..."
    
    for worker in "${WORKERS[@]}"; do
        # Check for shutdown before each worker
        if check_shutdown_flag; then
            log "Shutdown detected, aborting worker start" "WARN"
            return 1
        fi
        
        local worker_script="$PROJECT_ROOT/worker-$worker.sh"
        if [[ -f "$worker_script" ]]; then
            log "Starting $worker worker..."
            chmod +x "$worker_script"
            nohup bash "$worker_script" > "$LOG_DIR/worker-$worker.log" 2>&1 &
            sleep 2
        else
            log "Worker script not found: $worker_script" "WARN"
        fi
    done
    
    log "All workers started" "SUCCESS"
    return 0
}

# =============================================================================
# Main Controller Loop
# =============================================================================

controller_loop() {
    log "Entering main controller loop..."
    
    local iteration=0
    while true; do
        ((iteration++))
        log "=== Iteration $iteration ==="
        
        # Check for shutdown flag
        if check_shutdown_flag; then
            log "Shutdown flag detected, initiating graceful shutdown..."
            
            # Check if we can restart
            if can_restart; then
                log "Initiating restart sequence..."
                register_restart
                
                # Stop all workers
                stop_worker_processes
                
                # Reset git state
                reset_git_state
                
                # Wait before restart
                sleep 5
                
                # Clear shutdown flag
                clear_shutdown_flag
                
                # Restart workers
                start_workers
            else
                log "INSUFFICIENT QUOTA - SYSTEM HALTED" "ERROR"
                log_restart "SYSTEM HALTED - Max restart attempts exceeded"
                exit 1
            fi
        fi
        
        # Check quota status
        local quota=$(get_quota_status)
        local percentage=$(echo "$quota" | grep -oE '"Percentage": *[0-9]+' | grep -oE '[0-9]+')
        log "Current quota: ${percentage}%"
        
        # Heartbeat
        local heartbeat_file="$LOG_DIR/controller.heartbeat"
        date '+%Y-%m-%d %H:%M:%S' > "$heartbeat_file"
        
        # Sleep before next iteration
        sleep 60
    done
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    local repo_url="${1:-}"
    local branch_name="${2:-ai-dev}"
    local skip_clone="${3:-false}"
    
    log "============================================"
    log "AI Agent Loop Controller Starting"
    log "============================================"
    log "Project Root: $PROJECT_ROOT"
    log "PID: $$"
    
    # Create log directory if needed
    mkdir -p "$LOG_DIR"
    
    # Save controller PID
    save_controller_pid
    
    # Load configuration
    load_config
    
    # Initialize Git repository
    if [[ "$skip_clone" != "true" ]]; then
        init_git_repository "$repo_url" "$branch_name" || {
            log "Failed to initialize Git repository" "ERROR"
            exit 1
        }
    fi
    
    # Clear any stale flags
    clear_shutdown_flag
    clear_commit_lock
    
    # Start quota monitor
    start_quota_monitor
    
    # Start workers
    start_workers || {
        log "Failed to start workers" "ERROR"
        exit 1
    }
    
    # Enter main loop
    controller_loop
}

# Run main function
main "$@"
