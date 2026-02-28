#!/bin/bash
# Quota Checker Script - Bash Version
# ====================================
# One-shot quota check utility for use by other scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

JSON_OUTPUT="${JSON_OUTPUT:-false}"
QUIET="${QUIET:-false}"

# =============================================================================
# Quota Detection Methods
# =============================================================================

get_quota_from_iflow_status() {
    local status_output
    status_output=$(iflow status 2>&1 || true)
    
    local quota
    quota=$(echo "$status_output" | grep -ioE 'quota[:\s]+[0-9]+%' | grep -oE '[0-9]+' | head -1)
    if [[ -n "$quota" ]]; then echo "$quota"; return; fi
    
    quota=$(echo "$status_output" | grep -ioE 'remaining[:\s]+[0-9]+%' | grep -oE '[0-9]+' | head -1)
    if [[ -n "$quota" ]]; then echo "$quota"; return; fi
    
    quota=$(echo "$status_output" | grep -ioE 'usage[:\s]+[0-9]+%' | grep -oE '[0-9]+' | head -1)
    if [[ -n "$quota" ]]; then
        echo $((100 - quota))
        return
    fi
    
    return 1
}

get_quota_from_environment() {
    if [[ -n "$IFLOW_QUOTA_PERCENTAGE" ]]; then
        echo "$IFLOW_QUOTA_PERCENTAGE"
        return
    fi
    return 1
}

get_quota_from_metrics_file() {
    local possible_paths=(
        "$HOME/.iflow/metrics.json"
        "$PROJECT_ROOT/.iflow/metrics.json"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            local quota
            quota=$(grep -oE '"quota"[[:space:]]*:[[:space:]]*[0-9]+' "$path" | grep -oE '[0-9]+' | head -1)
            if [[ -n "$quota" ]]; then echo "$quota"; return; fi
        fi
    done
    
    return 1
}

get_quota_from_status_file() {
    if [[ -f "$QUOTA_STATUS" ]]; then
        local quota
        quota=$(grep -oE '"Percentage"[[:space:]]*:[[:space:]]*[0-9]+' "$QUOTA_STATUS" | grep -oE '[0-9]+' | head -1)
        if [[ -n "$quota" ]]; then
            echo "$quota"
            return
        fi
    fi
    return 1
}

get_current_quota() {
    local quota
    
    quota=$(get_quota_from_iflow_status 2>/dev/null) && { echo "$quota"; return; }
    quota=$(get_quota_from_environment 2>/dev/null) && { echo "$quota"; return; }
    quota=$(get_quota_from_metrics_file 2>/dev/null) && { echo "$quota"; return; }
    quota=$(get_quota_from_status_file 2>/dev/null) && { echo "$quota"; return; }
    
    echo 100
}

# =============================================================================
# Main
# =============================================================================

main() {
    local quota
    quota=$(get_current_quota)
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local status="normal"
        if (( quota <= 10 )); then
            status="critical"
        elif (( quota <= 25 )); then
            status="warning"
        fi
        
        echo "{\"Percentage\": $quota, \"Status\": \"$status\", \"Timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"}"
    elif [[ "$QUIET" != "true" ]]; then
        echo "Quota: ${quota}%"
    fi
    
    # Exit code based on quota level
    if (( quota <= 10 )); then
        exit 2  # Critical
    elif (( quota <= 25 )); then
        exit 1  # Warning
    else
        exit 0  # Normal
    fi
}

main "$@"
