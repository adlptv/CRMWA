#!/bin/bash
# Quota Monitor Script - Bash Version
# ====================================
# Background process that monitors GLM-5 agent quota
# and triggers controlled shutdown when quota is critical

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
QUOTA_LOG="$LOG_DIR/quota-monitor.log"

CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
CRITICAL_THRESHOLD="${CRITICAL_THRESHOLD:-10}"
WARNING_THRESHOLD="${WARNING_THRESHOLD:-25}"

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [QUOTA-MONITOR] [$level] $1"
    
    case "$level" in
        ERROR)   echo -e "\033[0;31m$message\033[0m" ;;
        WARN)    echo -e "\033[0;33m$message\033[0m" ;;
        SUCCESS) echo -e "\033[0;32m$message\033[0m" ;;
        *)       echo -e "\033[0;36m$message\033[0m" ;;
    esac
    
    echo "$message" >> "$QUOTA_LOG"
}

# =============================================================================
# Quota Detection Methods
# =============================================================================

get_quota_from_iflow_status() {
    # Try iFlow status command
    local status_output
    status_output=$(iflow status 2>&1 || true)
    
    # Parse various quota output formats
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
    local env_quota="$IFLOW_QUOTA_PERCENTAGE"
    if [[ -n "$env_quota" ]]; then
        echo "$env_quota"
        return
    fi
    return 1
}

get_quota_from_metrics_file() {
    local possible_paths=(
        "$HOME/.iflow/metrics.json"
        "$PROJECT_ROOT/.iflow/metrics.json"
        "/var/lib/iflow/metrics.json"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            local quota
            quota=$(grep -oE '"quota"[[:space:]]*:[[:space:]]*[0-9]+' "$path" | grep -oE '[0-9]+' | head -1)
            if [[ -n "$quota" ]]; then echo "$quota"; return; fi
            
            quota=$(grep -oE '"remaining_quota"[[:space:]]*:[[:space:]]*[0-9]+' "$path" | grep -oE '[0-9]+' | head -1)
            if [[ -n "$quota" ]]; then echo "$quota"; return; fi
        fi
    done
    
    return 1
}

get_quota_from_api() {
    local api_endpoint="$IFLOW_API_ENDPOINT"
    if [[ -z "$api_endpoint" ]]; then
        return 1
    fi
    
    local response
    response=$(curl -s --max-time 5 "$api_endpoint/quota" 2>/dev/null || true)
    
    if [[ -n "$response" ]]; then
        local quota
        quota=$(echo "$response" | grep -oE '"percentage"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
        if [[ -n "$quota" ]]; then echo "$quota"; return; fi
    fi
    
    return 1
}

get_current_quota() {
    local quota
    
    quota=$(get_quota_from_iflow_status) && { echo "$quota"; return; }
    quota=$(get_quota_from_environment) && { echo "$quota"; return; }
    quota=$(get_quota_from_metrics_file) && { echo "$quota"; return; }
    quota=$(get_quota_from_api) && { echo "$quota"; return; }
    
    # Default to 100 if no method succeeds
    echo 100
}

# =============================================================================
# Status Management
# =============================================================================

update_quota_status() {
    local percentage="$1"
    local status="${2:-normal}"
    local message="${3:-}"
    
    local available="high"
    if (( percentage < 25 )); then
        available="critical"
    elif (( percentage < 50 )); then
        available="low"
    elif (( percentage < 75 )); then
        available="medium"
    fi
    
    cat > "$QUOTA_STATUS" << EOF
{
    "Timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "Percentage": $percentage,
    "Status": "$status",
    "Message": "$message",
    "Available": "$available",
    "Used": $((100 - percentage))
}
EOF
}

set_shutdown_flag() {
    local quota="$1"
    cat > "$SHUTDOWN_FLAG" << EOF
SHUTDOWN_REQUESTED=$(date '+%Y-%m-%d %H:%M:%S')
REASON=QUOTA_CRITICAL
QUOTA_PERCENTAGE=$quota
EOF
    
    log "Shutdown flag set due to critical quota" "WARN"
}

# =============================================================================
# Notifications
# =============================================================================

send_quota_warning() {
    local percentage="$1"
    log "QUOTA WARNING: $percentage% remaining" "WARN"
}

send_quota_critical() {
    local percentage="$1"
    log "QUOTA CRITICAL: $percentage% remaining - Initiating shutdown" "ERROR"
}

# =============================================================================
# Monitor Loop
# =============================================================================

start_quota_monitor() {
    log "Starting quota monitor..."
    log "Check interval: $CHECK_INTERVAL seconds"
    log "Critical threshold: $CRITICAL_THRESHOLD%"
    log "Warning threshold: $WARNING_THRESHOLD%"
    
    local iteration=0
    local consecutive_critical=0
    local max_consecutive_critical=3
    
    while true; do
        ((iteration++))
        
        local quota
        quota=$(get_current_quota)
        
        log "Quota check #$iteration : ${quota}%"
        
        local status="normal"
        local message=""
        
        if (( quota <= CRITICAL_THRESHOLD )); then
            status="critical"
            message="Quota critical - below $CRITICAL_THRESHOLD%"
            ((consecutive_critical++))
            
            send_quota_critical "$quota"
            
            if (( consecutive_critical >= max_consecutive_critical )); then
                log "Consecutive critical readings: $consecutive_critical - Setting shutdown flag" "ERROR"
                set_shutdown_flag "$quota"
                update_quota_status "$quota" "$status" "$message"
                
                # Trigger restart manager
                local restart_manager="$PROJECT_ROOT/restart-manager.sh"
                if [[ -f "$restart_manager" ]]; then
                    chmod +x "$restart_manager"
                    nohup bash "$restart_manager" > /dev/null 2>&1 &
                fi
                
                consecutive_critical=0
            fi
        elif (( quota <= WARNING_THRESHOLD )); then
            status="warning"
            message="Quota low - below $WARNING_THRESHOLD%"
            consecutive_critical=0
            send_quota_warning "$quota"
        else
            consecutive_critical=0
        fi
        
        update_quota_status "$quota" "$status" "$message"
        
        sleep "$CHECK_INTERVAL"
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Quota Monitor Starting"
    log "============================================"
    log "PID: $$"
    
    mkdir -p "$LOG_DIR"
    update_quota_status 100 "initializing" "Monitor starting"
    
    trap 'log "Monitor interrupted"; update_quota_status 0 "interrupted" "Monitor stopped"; exit 0' INT TERM
    
    start_quota_monitor
}

main "$@"
