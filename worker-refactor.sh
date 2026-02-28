#!/bin/bash
# Refactor Worker Script - Bash Version
# ======================================
# Code refactoring and optimization agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

WORKER_NAME="refactor"
WORKER_PID="$PROJECT_ROOT/worker-$WORKER_NAME.pid"
WORKER_STATUS="$LOG_DIR/worker-$WORKER_NAME-status.txt"
WORKER_LOG="$LOG_DIR/worker-$WORKER_NAME.log"

MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
ITERATION_DELAY="${ITERATION_DELAY:-60}"

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
    if [[ ! -f "$QUOTA_STATUS" ]]; then echo 100; return; fi
    grep -oE '"Percentage": *[0-9]+' "$QUOTA_STATUS" | grep -oE '[0-9]+' || echo 100
}

# =============================================================================
# Code Analysis
# =============================================================================

find_source_files() {
    find "$PROJECT_ROOT" -type f \( \
        -name "*.py" -o -name "*.js" -o -name "*.ts" -o \
        -name "*.jsx" -o -name "*.tsx" -o -name "*.go" -o \
        -name "*.java" -o -name "*.cs" \
    \) ! -path "*/node_modules/*" ! -path "*/venv/*" ! -path "*/__pycache__/*" ! -path "*/.git/*" ! -path "*/test/*"
}

measure_complexity() {
    local file="$1"
    local content=$(cat "$file" 2>/dev/null)
    
    local complexity=0
    complexity=$((complexity + $(echo "$content" | grep -c '\bif\b' || echo 0)))
    complexity=$((complexity + $(echo "$content" | grep -c '\belse\b' || echo 0)))
    complexity=$((complexity + $(echo "$content" | grep -c '\bfor\b' || echo 0)))
    complexity=$((complexity + $(echo "$content" | grep -c '\bwhile\b' || echo 0)))
    complexity=$((complexity + $(echo "$content" | grep -c '\bswitch\b' || echo 0)))
    complexity=$((complexity + $(echo "$content" | grep -c '\bcase\b' || echo 0)))
    complexity=$((complexity + $(echo "$content" | grep -c '\bcatch\b' || echo 0)))
    
    echo "$complexity"
}

find_code_smells() {
    local file="$1"
    local smells=""
    
    # Long methods (500+ chars between braces)
    if grep -Pzo 'function\s+\w+\s*\([^)]*\)\s*\{[^\}]{500,}\}' "$file" &>/dev/null; then
        smells+="long_method,"
    fi
    
    # God class (2000+ chars)
    if grep -Pzo 'class\s+\w+\s*\{[^\}]{2000,}\}' "$file" &>/dev/null; then
        smells+="god_class,"
    fi
    
    # Magic numbers
    if grep -E '(?<!["\d])\d{2,}(?!["\d])' "$file" &>/dev/null; then
        smells+="magic_numbers,"
    fi
    
    # Deep nesting
    if grep -P '\{[^\}]*\{[^\}]*\{[^\}]*\{' "$file" &>/dev/null; then
        smells+="deep_nesting,"
    fi
    
    echo "$smells"
}

run_code_analysis() {
    log "Running code analysis..."
    
    local high_complexity=0
    local code_smells=0
    local total_files=0
    
    while IFS= read -r file; do
        if check_shutdown_flag; then break; fi
        
        ((total_files++))
        
        local complexity=$(measure_complexity "$file")
        if (( complexity > 20 )); then
            log "High complexity: $file (Complexity: $complexity)"
            ((high_complexity++))
        fi
        
        local smells=$(find_code_smells "$file")
        if [[ -n "$smells" ]]; then
            log "Code smells in $file: $smells"
            ((code_smells++))
        fi
    done < <(find_source_files)
    
    log "Analysis complete: $total_files files, $high_complexity high complexity, $code_smells with smells"
    
    echo "$high_complexity:$code_smells"
}

# =============================================================================
# Git Operations
# =============================================================================

git_commit() {
    local message="$1"
    local quota=$(get_quota_percentage)
    
    if (( quota < 10 )); then return 1; fi
    
    local wait_count=0
    while check_commit_lock && (( wait_count < 30 )); do
        sleep 1; ((wait_count++))
    done
    
    if check_commit_lock; then return 1; fi
    
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
    log "Starting refactor worker loop..."
    update_status "running"
    
    local iteration=0
    
    while (( iteration < MAX_ITERATIONS )); do
        ((iteration++))
        log "=== Iteration $iteration/$MAX_ITERATIONS ==="
        
        if check_shutdown_flag; then
            log "Shutdown detected, exiting" "WARN"
            update_status "shutdown"
            return
        fi
        
        local quota=$(get_quota_percentage)
        if (( quota < 10 )); then
            log "Quota critical, pausing..." "WARN"
            sleep 60
            continue
        fi
        
        update_status "analyzing"
        run_code_analysis
        
        update_status "refactoring"
        # Invoke refactoring logic
        
        git_commit "Refactoring from iteration $iteration"
        
        update_status "waiting"
        sleep "$ITERATION_DELAY"
    done
    
    update_status "completed"
    log "Refactor worker completed"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Refactor Worker Starting"
    log "============================================"
    log "PID: $$"
    
    mkdir -p "$LOG_DIR"
    save_pid
    update_status "initializing"
    
    trap 'log "Worker interrupted"; update_status "interrupted"; exit 0' INT TERM
    
    worker_loop
    
    log "Refactor Worker Exiting"
}

main "$@"
