#!/bin/bash
# Lint Worker Script - Bash Version
# ==================================
# Code linting and style enforcement agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

WORKER_NAME="lint"
WORKER_PID="$PROJECT_ROOT/worker-$WORKER_NAME.pid"
WORKER_STATUS="$LOG_DIR/worker-$WORKER_NAME-status.txt"
WORKER_LOG="$LOG_DIR/worker-$WORKER_NAME.log"

MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
ITERATION_DELAY="${ITERATION_DELAY:-20}"

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
        if [[ "$lock_pid" == "$$" ]]; then rm -f "$COMMIT_LOCK"; fi
    fi
}

get_quota_percentage() {
    if [[ ! -f "$QUOTA_STATUS" ]]; then echo 100; return; fi
    grep -oE '"Percentage": *[0-9]+' "$QUOTA_STATUS" | grep -oE '[0-9]+' || echo 100
}

# =============================================================================
# Project Detection
# =============================================================================

detect_project_type() {
    if [[ -f "package.json" ]]; then
        if grep -q "typescript" package.json 2>/dev/null; then echo "typescript"
        else echo "node"; fi
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then echo "python"
    elif [[ -f "go.mod" ]]; then echo "go"
    elif ls *.csproj 1>/dev/null 2>&1; then echo "dotnet"
    else echo "unknown"
    fi
}

# =============================================================================
# Linting Functions
# =============================================================================

run_linter() {
    local project_type="$1"
    local fix="${2:-false}"
    
    local check_cmd=""
    local fix_cmd=""
    
    case "$project_type" in
        node|typescript)
            check_cmd="npx eslint ."
            fix_cmd="npx eslint --fix ."
            ;;
        python)
            check_cmd="ruff check ."
            fix_cmd="ruff check --fix ."
            ;;
        go)
            check_cmd="golint ./..."
            fix_cmd="go fmt ./..."
            ;;
        dotnet)
            check_cmd="dotnet format --verify-no-changes"
            fix_cmd="dotnet format"
            ;;
    esac
    
    if [[ -z "$check_cmd" ]]; then
        log "No linter for project type: $project_type" "WARN"
        return 0
    fi
    
    local cmd
    if [[ "$fix" == "true" ]]; then
        cmd="$fix_cmd"
    else
        cmd="$check_cmd"
    fi
    
    log "Running: $cmd"
    local output
    output=$($cmd 2>&1 || true)
    local error_count=$(echo "$output" | grep -ciE "error|warning" || echo 0)
    
    echo "$error_count"
}

run_auto_format() {
    local project_type="$1"
    
    case "$project_type" in
        node|typescript)
            if command -v prettier &>/dev/null; then
                npx prettier --write . 2>/dev/null || true
            fi
            ;;
        python)
            if command -v black &>/dev/null; then
                black . 2>/dev/null || true
            elif command -v ruff &>/dev/null; then
                ruff format . 2>/dev/null || true
            fi
            ;;
        go)
            go fmt ./... 2>/dev/null || true
            ;;
    esac
}

# =============================================================================
# Git Operations
# =============================================================================

git_commit() {
    local message="$1"
    local quota=$(get_quota_percentage)
    if (( quota < 10 )); then return 1; fi
    
    local wait_count=0
    while check_commit_lock && (( wait_count < 30 )); do sleep 1; ((wait_count++)); done
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
    log "Starting lint worker loop..."
    update_status "running"
    
    local project_type=$(detect_project_type)
    log "Detected project type: $project_type"
    
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
        
        update_status "checking"
        local error_count=$(run_linter "$project_type" false)
        log "Linter result: $error_count issues found"
        
        if (( error_count > 0 )); then
            update_status "fixing"
            run_linter "$project_type" true
            run_auto_format "$project_type"
            
            local verify_count=$(run_linter "$project_type" false)
            log "After fix: $verify_count issues remaining"
            
            git_commit "Lint fixes from iteration $iteration"
        fi
        
        update_status "waiting"
        sleep "$ITERATION_DELAY"
    done
    
    update_status "completed"
    log "Lint worker completed"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Lint Worker Starting"
    log "============================================"
    log "PID: $$"
    
    mkdir -p "$LOG_DIR"
    save_pid
    update_status "initializing"
    
    trap 'log "Worker interrupted"; update_status "interrupted"; exit 0' INT TERM
    
    worker_loop
    
    log "Lint Worker Exiting"
}

main "$@"
