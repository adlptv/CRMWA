#!/bin/bash
# Bugfix Worker Script - Bash Version
# ====================================
# Automated bug detection and fixing agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

WORKER_NAME="bugfix"
WORKER_PID="$PROJECT_ROOT/worker-$WORKER_NAME.pid"
WORKER_STATUS="$LOG_DIR/worker-$WORKER_NAME-status.txt"
WORKER_LOG="$LOG_DIR/worker-$WORKER_NAME.log"

MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
ITERATION_DELAY="${ITERATION_DELAY:-30}"

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [$WORKER_NAME] [$level] $1"
    
    case "$level" in
        ERROR)   echo -e "\033[0;31m$message\033[0m" ;;
        WARN)    echo -e "\033[0;33m$message\033[0m" ;;
        SUCCESS) echo -e "\033[0;32m$message\033[0m" ;;
        *)       echo -e "\033[0;36m$message\033[0m" ;;
    esac
    
    echo "$message" >> "$WORKER_LOG"
}

# =============================================================================
# State Management
# =============================================================================

save_pid() { echo $$ > "$WORKER_PID"; }
update_status() { echo "$1" > "$WORKER_STATUS"; }
check_shutdown_flag() { [[ -f "$SHUTDOWN_FLAG" ]]; }
check_commit_lock() { [[ -f "$COMMIT_LOCK" ]]; }

set_commit_lock() {
    echo "PID=$$" > "$COMMIT_LOCK"
    echo "WORKER=$WORKER_NAME" >> "$COMMIT_LOCK"
    echo "TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')" >> "$COMMIT_LOCK"
}

clear_commit_lock() {
    if [[ -f "$COMMIT_LOCK" ]]; then
        local lock_pid=$(grep "PID=" "$COMMIT_LOCK" | cut -d= -f2)
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$COMMIT_LOCK"
        fi
    fi
}

get_quota_percentage() {
    if [[ ! -f "$QUOTA_STATUS" ]]; then
        echo 100
        return
    fi
    grep -oE '"Percentage': *[0-9]+' "$QUOTA_STATUS" | grep -oE '[0-9]+' || echo 100
}

# =============================================================================
# Bug Detection Functions
# =============================================================================

find_source_files() {
    find "$PROJECT_ROOT" -type f \( \
        -name "*.py" -o \
        -name "*.js" -o \
        -name "*.ts" -o \
        -name "*.jsx" -o \
        -name "*.tsx" -o \
        -name "*.go" -o \
        -name "*.java" -o \
        -name "*.cs" \
    \) ! -path "*/node_modules/*" ! -path "*/venv/*" ! -path "*/__pycache__/*" ! -path "*/.git/*"
}

search_error_patterns() {
    local file="$1"
    local patterns=(
        "try\s*\{[^}]*\}\s*catch\s*\(\s*\)"
        "except\s*:"
        "catch\s*\(\s*\.\.\.\s*\)"
        "//\s*TODO.*bug"
        "#\s*TODO.*bug"
        "FIXME"
        "HACK"
        "XXX"
    )
    
    for pattern in "${patterns[@]}"; do
        grep -nE "$pattern" "$file" 2>/dev/null || true
    done
}

run_bug_analysis() {
    log "Starting bug analysis..."
    
    local files=$(find_source_files)
    local file_count=$(echo "$files" | wc -l)
    log "Found $file_count source files to analyze"
    
    local bug_count=0
    
    while IFS= read -r file; do
        if check_shutdown_flag; then
            log "Shutdown detected, aborting analysis" "WARN"
            break
        fi
        
        local issues=$(search_error_patterns "$file")
        if [[ -n "$issues" ]]; then
            log "Issues found in: $file"
            ((bug_count++))
        fi
    done <<< "$files"
    
    log "Analysis complete. Files with potential issues: $bug_count"
}

# =============================================================================
# Git Operations
# =============================================================================

git_commit() {
    local message="$1"
    local quota=$(get_quota_percentage)
    
    if (( quota < 10 )); then
        log "Quota critical ($quota%), skipping commit" "WARN"
        return 1
    fi
    
    local wait_count=0
    while check_commit_lock && (( wait_count < 30 )); do
        sleep 1
        ((wait_count++))
    done
    
    if check_commit_lock; then
        log "Commit lock held, skipping" "WARN"
        return 1
    fi
    
    set_commit_lock
    
    git add -A
    git commit -m "[$WORKER_NAME] $message" || true
    
    clear_commit_lock
    log "Committed: $message" "SUCCESS"
}

# =============================================================================
# Main Worker Loop
# =============================================================================

worker_loop() {
    log "Starting worker loop..."
    update_status "running"
    
    local iteration=0
    
    while (( iteration < MAX_ITERATIONS )); do
        ((iteration++))
        log "=== Iteration $iteration/$MAX_ITERATIONS ==="
        
        if check_shutdown_flag; then
            log "Shutdown detected, exiting" "WARN"
            update_status "shutdown"
            save_state
            return
        fi
        
        local quota=$(get_quota_percentage)
        if (( quota < 10 )); then
            log "Quota critical ($quota%), pausing..." "WARN"
            sleep 60
            continue
        fi
        
        update_status "analyzing"
        run_bug_analysis
        
        update_status "fixing"
        # Invoke iFlow for fixes
        
        git_commit "Bug fixes from iteration $iteration"
        
        update_status "waiting"
        sleep "$ITERATION_DELAY"
    done
    
    update_status "completed"
    log "Worker loop completed"
}

save_state() {
    local state_file="$LOG_DIR/worker-$WORKER_NAME-state.json"
    cat > "$state_file" << EOF
{
    "worker": "$WORKER_NAME",
    "pid": $$,
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "status": "shutdown"
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Bugfix Worker Starting"
    log "============================================"
    log "PID: $$"
    log "Max Iterations: $MAX_ITERATIONS"
    
    mkdir -p "$LOG_DIR"
    save_pid
    update_status "initializing"
    
    trap 'log "Worker interrupted"; update_status "interrupted"; exit 0' INT TERM
    
    worker_loop
    
    log "Bugfix Worker Exiting"
}

main "$@"
