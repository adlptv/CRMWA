#!/bin/bash
# Safety Check Script - Bash Version
# ===================================
# Performs safety checks before critical operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

ISSUES=0
WARNINGS=0

# =============================================================================
# Output Functions
# =============================================================================

add_issue() {
    echo -e "  \033[0;31m[ISSUE] $1\033[0m"
    ((ISSUES++))
}

add_warning() {
    echo -e "  \033[0;33m[WARN] $1\033[0m"
    ((WARNINGS++))
}

add_ok() {
    echo -e "  \033[0;32m[OK] $1\033[0m"
}

# =============================================================================
# Git Safety Checks
# =============================================================================

check_git_safety() {
    echo ""
    echo -e "\033[0;36mGit Safety Checks\033[0m"
    echo "================="
    
    cd "$PROJECT_ROOT"
    
    if ! git rev-parse --git-dir &>/dev/null; then
        add_warning "Not in a Git repository"
        return
    fi
    
    add_ok "In Git repository"
    
    # Check for uncommitted changes
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        add_warning "Uncommitted changes detected"
    else
        add_ok "Working directory clean"
    fi
    
    # Check current branch
    local branch=$(git branch --show-current 2>/dev/null)
    add_ok "Current branch: $branch"
    
    # Check for detached HEAD
    if ! git symbolic-ref -q HEAD &>/dev/null; then
        add_warning "Detached HEAD state"
    fi
    
    # Check for merge conflicts
    if [[ -n $(git diff --name-only --diff-filter=U 2>/dev/null) ]]; then
        add_issue "Merge conflicts detected"
    fi
}

# =============================================================================
# Lock Safety Checks
# =============================================================================

check_lock_safety() {
    echo ""
    echo -e "\033[0;36mLock Safety Checks\033[0m"
    echo "=================="
    
    # Check shutdown flag
    if [[ -f "$SHUTDOWN_FLAG" ]]; then
        add_issue "Shutdown flag is set"
        echo -e "    \033[0;90mContent: $(cat "$SHUTDOWN_FLAG")\033[0m"
        
        if [[ "${FIX:-false}" == "true" ]]; then
            rm -f "$SHUTDOWN_FLAG"
            echo -e "    \033[0;32m[FIXED] Removed shutdown flag\033[0m"
        fi
    else
        add_ok "No shutdown flag"
    fi
    
    # Check commit lock
    if [[ -f "$COMMIT_LOCK" ]]; then
        add_warning "Commit lock is set"
        echo -e "    \033[0;90mContent: $(cat "$COMMIT_LOCK")\033[0m"
        
        # Check if lock is stale
        local lock_time=$(grep "TIMESTAMP=" "$COMMIT_LOCK" 2>/dev/null | cut -d= -f2)
        if [[ -n "$lock_time" ]]; then
            local lock_epoch=$(date -d "$lock_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$lock_time" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local age=$(( (now_epoch - lock_epoch) / 60 ))
            
            if (( age > 5 )); then
                add_warning "Commit lock is stale ($age minutes old)"
                
                if [[ "${FIX:-false}" == "true" ]]; then
                    rm -f "$COMMIT_LOCK"
                    echo -e "    \033[0;32m[FIXED] Removed stale commit lock\033[0m"
                fi
            fi
        fi
    else
        add_ok "No commit lock"
    fi
}

# =============================================================================
# Process Safety Checks
# =============================================================================

check_process_safety() {
    echo ""
    echo -e "\033[0;36mProcess Safety Checks\033[0m"
    echo "====================="
    
    local workers=("bugfix" "coverage" "refactor" "lint" "doc")
    
    # Check controller
    local controller_pidfile="$PROJECT_ROOT/controller.pid"
    if [[ -f "$controller_pidfile" ]]; then
        local pid=$(cat "$controller_pidfile" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            add_ok "Controller running (PID: $pid)"
        else
            add_warning "Controller PID file exists but process not running"
        fi
    else
        add_ok "Controller not running"
    fi
    
    # Check workers
    local running=0
    for worker in "${workers[@]}"; do
        local pidfile="$PROJECT_ROOT/worker-$worker.pid"
        if [[ -f "$pidfile" ]]; then
            local pid=$(cat "$pidfile" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                ((running++))
                add_ok "$worker worker running (PID: $pid)"
            else
                add_warning "$worker worker PID file exists but process not running"
            fi
        fi
    done
    
    if (( running == 0 )); then
        add_warning "No workers running"
    fi
}

# =============================================================================
# Quota Safety Checks
# =============================================================================

check_quota_safety() {
    echo ""
    echo -e "\033[0;36mQuota Safety Checks\033[0m"
    echo "==================="
    
    if [[ -f "$QUOTA_STATUS" ]]; then
        local percentage=$(grep -oE '"Percentage"[[:space:]]*:[[:space:]]*[0-9]+' "$QUOTA_STATUS" | grep -oE '[0-9]+')
        local status=$(grep -oE '"Status"[[:space:]]*:[[:space:]]*"[^"]+"' "$QUOTA_STATUS" | grep -oE '"[^"]+"' | tr -d '"')
        
        add_ok "Quota status available"
        echo -e "    \033[0;90mPercentage: $percentage%\033[0m"
        echo -e "    \033[0;90mStatus: $status\033[0m"
        
        if (( percentage <= 10 )); then
            add_issue "Quota is critical ($percentage%)"
        elif (( percentage <= 25 )); then
            add_warning "Quota is low ($percentage%)"
        else
            add_ok "Quota is healthy"
        fi
    else
        add_warning "No quota status file"
    fi
}

# =============================================================================
# Disk Safety Checks
# =============================================================================

check_disk_safety() {
    echo ""
    echo -e "\033[0;36mDisk Safety Checks\033[0m"
    echo "=================="
    
    local disk_info=$(df -h "$PROJECT_ROOT" | tail -1)
    local free_percent=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')
    local free_space=$(echo "$disk_info" | awk '{print $4}')
    
    add_ok "Free space: $free_space ($((100 - free_percent))%)"
    
    if (( free_percent >= 95 )); then
        add_issue "Disk space critical ($(100 - free_percent)% free)"
    elif (( free_percent >= 90 )); then
        add_warning "Disk space low ($(100 - free_percent)% free)"
    fi
    
    # Check log directory size
    if [[ -d "$LOG_DIR" ]]; then
        local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
        add_ok "Log directory size: $log_size"
    fi
}

# =============================================================================
# Memory Safety Checks
# =============================================================================

check_memory_safety() {
    echo ""
    echo -e "\033[0;36mMemory Safety Checks\033[0m"
    echo "===================="
    
    if command -v free &>/dev/null; then
        local mem_info=$(free -h | grep "Mem:")
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        local free=$(echo "$mem_info" | awk '{print $4}')
        
        add_ok "Memory: $free free of $total"
    fi
}

# =============================================================================
# Summary
# =============================================================================

show_summary() {
    echo ""
    echo "============================================"
    echo -e "\033[0;36mSafety Check Summary\033[0m"
    echo "============================================"
    echo ""
    
    echo -e "Issues:    $ISSUES"
    echo -e "Warnings:  $WARNINGS"
    echo ""
    
    if (( ISSUES > 0 )); then
        echo -e "\033[0;31mSAFETY CHECK FAILED\033[0m"
        return 1
    elif (( WARNINGS > 0 )); then
        echo -e "\033[0;33mSAFETY CHECK PASSED (with warnings)\033[0m"
        return 0
    else
        echo -e "\033[0;32mSAFETY CHECK PASSED\033[0m"
        return 0
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local check="${1:-all}"
    
    echo "============================================"
    echo -e "\033[0;36mAI Agent Loop Safety Checker\033[0m"
    echo "============================================"
    echo "Project: $PROJECT_ROOT"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$check" in
        all)
            check_git_safety
            check_lock_safety
            check_process_safety
            check_quota_safety
            check_disk_safety
            check_memory_safety
            ;;
        git)     check_git_safety ;;
        locks)   check_lock_safety ;;
        processes) check_process_safety ;;
        quota)   check_quota_safety ;;
        disk)    check_disk_safety ;;
        memory)  check_memory_safety ;;
        *)
            echo "Usage: $0 {all|git|locks|processes|quota|disk|memory}"
            exit 1
            ;;
    esac
    
    show_summary
}

main "$@"
