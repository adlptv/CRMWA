#!/bin/bash
# Coverage Worker Script - Bash Version
# ======================================
# Test coverage analysis and improvement agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

WORKER_NAME="coverage"
WORKER_PID="$PROJECT_ROOT/worker-$WORKER_NAME.pid"
WORKER_STATUS="$LOG_DIR/worker-$WORKER_NAME-status.txt"
WORKER_LOG="$LOG_DIR/worker-$WORKER_NAME.log"

MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
ITERATION_DELAY="${ITERATION_DELAY:-30}"
TARGET_COVERAGE="${TARGET_COVERAGE:-90}"

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
    grep -oE '"Percentage": *[0-9]+' "$QUOTA_STATUS" | grep -oE '[0-9]+' || echo 100
}

# =============================================================================
# Project Detection
# =============================================================================

detect_project_type() {
    if [[ -f "package.json" ]]; then
        if grep -q "typescript" package.json 2>/dev/null; then
            echo "typescript"
        else
            echo "node"
        fi
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
        echo "python"
    elif [[ -f "go.mod" ]]; then
        echo "go"
    elif ls *.csproj 1>/dev/null 2>&1; then
        echo "dotnet"
    else
        echo "unknown"
    fi
}

# =============================================================================
# Coverage Analysis
# =============================================================================

run_coverage_analysis() {
    local project_type="$1"
    log "Running coverage analysis for $project_type project..."
    
    local coverage=0
    
    case "$project_type" in
        node)
            if [[ -f "jest.config.js" ]]; then
                npm run coverage 2>&1 | tee "$LOG_DIR/coverage-report.txt" || true
            fi
            ;;
        python)
            if command -v pytest &>/dev/null; then
                pytest --cov=. --cov-report=term 2>&1 | tee "$LOG_DIR/coverage-report.txt" || true
                coverage=$(grep "TOTAL" "$LOG_DIR/coverage-report.txt" 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%' || echo 0)
            fi
            ;;
        go)
            go test -cover ./... 2>&1 | tee "$LOG_DIR/coverage-report.txt" || true
            ;;
        dotnet)
            dotnet test --collect:"XPlat Code Coverage" 2>&1 | tee "$LOG_DIR/coverage-report.txt" || true
            ;;
    esac
    
    echo "$coverage"
}

find_uncovered_files() {
    local report_file="$LOG_DIR/coverage-report.txt"
    
    if [[ ! -f "$report_file" ]]; then
        return
    fi
    
    grep -E "^\S+\s+[0-9]+\s+[0-9]+\s+[0-9]+%" "$report_file" | \
        awk -v target="$TARGET_COVERAGE" '$4 < target { print $1, $4 }' || true
}

# =============================================================================
# Git Operations
# =============================================================================

git_commit() {
    local message="$1"
    local quota=$(get_quota_percentage)
    
    if (( quota < 10 )); then
        log "Quota critical, skipping commit" "WARN"
        return 1
    fi
    
    local wait_count=0
    while check_commit_lock && (( wait_count < 30 )); do
        sleep 1
        ((wait_count++))
    done
    
    if check_commit_lock; then
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
    log "Starting coverage worker loop..."
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
        
        update_status "analyzing"
        local coverage=$(run_coverage_analysis "$project_type")
        log "Current coverage: ${coverage}%"
        
        if (( coverage >= TARGET_COVERAGE )); then
            log "Target coverage ($TARGET_COVERAGE%) achieved!" "SUCCESS"
            update_status "target_met"
            break
        fi
        
        update_status "generating"
        local uncovered=$(find_uncovered_files)
        if [[ -n "$uncovered" ]]; then
            log "Files below target coverage:"
            echo "$uncovered" | head -5
        fi
        
        git_commit "Coverage improvements from iteration $iteration"
        
        update_status "waiting"
        sleep "$ITERATION_DELAY"
    done
    
    update_status "completed"
    log "Coverage worker completed"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Coverage Worker Starting"
    log "============================================"
    log "PID: $$"
    log "Target Coverage: $TARGET_COVERAGE%"
    
    mkdir -p "$LOG_DIR"
    save_pid
    update_status "initializing"
    
    trap 'log "Worker interrupted"; update_status "interrupted"; exit 0' INT TERM
    
    worker_loop
    
    log "Coverage Worker Exiting"
}

main "$@"
