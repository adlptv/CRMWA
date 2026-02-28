#!/bin/bash
# Retry Logic Script - Bash Version
# ==================================
# Retry mechanism for failed operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/logs"
RETRY_LOG="$LOG_DIR/retry.log"

# Default values
MAX_RETRIES="${MAX_RETRIES:-3}"
INITIAL_DELAY="${INITIAL_DELAY:-5}"
BACKOFF_MULTIPLIER="${BACKOFF_MULTIPLIER:-2}"
MAX_DELAY="${MAX_DELAY:-60}"
VERBOSE="${VERBOSE:-false}"

# =============================================================================
# Logging
# =============================================================================

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] [RETRY] [$level] $1"
    
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" == "ERROR" ]]; then
        case "$level" in
            ERROR)   echo -e "\033[0;31m$message\033[0m" ;;
            WARN)    echo -e "\033[0;33m$message\033[0m" ;;
            SUCCESS) echo -e "\033[0;32m$message\033[0m" ;;
            *)       echo -e "\033[0;36m$message\033[0m" ;;
        esac
    fi
    
    mkdir -p "$LOG_DIR"
    echo "$message" >> "$RETRY_LOG"
}

# =============================================================================
# Retry Functions
# =============================================================================

# Execute a command with retry logic
# Usage: with_retry <command...>
with_retry() {
    local max_retries="${MAX_RETRIES:-3}"
    local initial_delay="${INITIAL_DELAY:-5}"
    local backoff="${BACKOFF_MULTIPLIER:-2}"
    local max_delay="${MAX_DELAY:-60}"
    
    local attempt=0
    local delay="$initial_delay"
    local last_exit_code=0
    
    while (( attempt < max_retries )); do
        ((attempt++))
        
        log "Attempt $attempt of $max_retries"
        
        # Execute the command
        set +e
        "$@"
        last_exit_code=$?
        set -e
        
        if (( last_exit_code == 0 )); then
            if (( attempt > 1 )); then
                log "Operation succeeded on attempt $attempt" "SUCCESS"
            fi
            return 0
        fi
        
        log "Attempt $attempt failed with exit code $last_exit_code" "WARN"
        
        if (( attempt < max_retries )); then
            log "Waiting $delay seconds before retry..."
            sleep "$delay"
            
            # Calculate next delay with exponential backoff
            delay=$(echo "$delay * $backoff" | bc | cut -d. -f1)
            if (( delay > max_delay )); then
                delay="$max_delay"
            fi
        fi
    done
    
    log "All $max_retries attempts failed" "ERROR"
    return 1
}

# Execute a Git command with retry
# Usage: git_with_retry <git command...>
git_with_retry() {
    log "Executing Git command: git $*"
    
    local attempt=0
    local delay=2
    local max_retries=3
    
    while (( attempt < max_retries )); do
        ((attempt++))
        
        set +e
        git "$@"
        local exit_code=$?
        set -e
        
        if (( exit_code == 0 )); then
            return 0
        fi
        
        log "Git command failed (attempt $attempt)" "WARN"
        
        if (( attempt < max_retries )); then
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    
    log "Git command failed after $max_retries attempts" "ERROR"
    return 1
}

# Execute HTTP request with retry
# Usage: http_with_retry <url> [method] [timeout]
http_with_retry() {
    local url="$1"
    local method="${2:-GET}"
    local timeout="${3:-30}"
    local max_retries=3
    
    log "HTTP $method request to: $url"
    
    local attempt=0
    local delay=5
    
    while (( attempt < max_retries )); do
        ((attempt++))
        
        set +e
        local response
        response=$(curl -s -X "$method" --max-time "$timeout" "$url" 2>&1)
        local exit_code=$?
        set -e
        
        if (( exit_code == 0 )); then
            echo "$response"
            return 0
        fi
        
        log "HTTP request failed (attempt $attempt)" "WARN"
        
        if (( attempt < max_retries )); then
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    
    log "HTTP request failed after $max_retries attempts" "ERROR"
    return 1
}

# =============================================================================
# Circuit Breaker Implementation
# =============================================================================

CIRCUIT_BREAKER_STATE="closed"
CIRCUIT_BREAKER_FAILURES=0
CIRCUIT_BREAKER_LAST_FAILURE=""
CIRCUIT_BREAKER_THRESHOLD=5
CIRCUIT_BREAKER_RESET_TIMEOUT=60

circuit_breaker_can_execute() {
    if [[ "$CIRCUIT_BREAKER_STATE" == "closed" ]]; then
        return 0
    fi
    
    if [[ "$CIRCUIT_BREAKER_STATE" == "open" ]]; then
        # Check if reset timeout has passed
        if [[ -n "$CIRCUIT_BREAKER_LAST_FAILURE" ]]; then
            local last_epoch=$(date -d "$CIRCUIT_BREAKER_LAST_FAILURE" +%s 2>/dev/null || \
                               date -j -f "%Y-%m-%d %H:%M:%S" "$CIRCUIT_BREAKER_LAST_FAILURE" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local elapsed=$((now_epoch - last_epoch))
            
            if (( elapsed >= CIRCUIT_BREAKER_RESET_TIMEOUT )); then
                CIRCUIT_BREAKER_STATE="half-open"
                return 0
            fi
        fi
        return 1
    fi
    
    # half-open state
    return 0
}

circuit_breaker_record_success() {
    CIRCUIT_BREAKER_FAILURES=0
    CIRCUIT_BREAKER_STATE="closed"
}

circuit_breaker_record_failure() {
    ((CIRCUIT_BREAKER_FAILURES++))
    CIRCUIT_BREAKER_LAST_FAILURE=$(date '+%Y-%m-%d %H:%M:%S')
    
    if (( CIRCUIT_BREAKER_FAILURES >= CIRCUIT_BREAKER_THRESHOLD )); then
        CIRCUIT_BREAKER_STATE="open"
    fi
}

with_circuit_breaker() {
    if ! circuit_breaker_can_execute; then
        log "Circuit breaker is open" "ERROR"
        return 1
    fi
    
    set +e
        "$@"
    local exit_code=$?
    set -e
    
    if (( exit_code == 0 )); then
        circuit_breaker_record_success
    else
        circuit_breaker_record_failure
    fi
    
    return $exit_code
}

# =============================================================================
# Bulkhead Implementation (Concurrency Limiting)
# =============================================================================

BULKHEAD_MAX_CONCURRENT="${BULKHEAD_MAX_CONCURRENT:-5}"
BULKHEAD_SEMAPHORE="/tmp/bulkhead-$$"

bulkhead_init() {
    local max="${1:-$BULKHEAD_MAX_CONCURRENT}"
    mkdir -p /tmp
    echo "$max" > "$BULKHEAD_SEMAPHORE"
}

bulkhead_acquire() {
    local timeout="${1:-30}"
    local waited=0
    
    while (( waited < timeout )); do
        local current=$(cat "$BULKHEAD_SEMAPHORE" 2>/dev/null || echo "$BULKHEAD_MAX_CONCURRENT")
        
        if (( current > 0 )); then
            echo $((current - 1)) > "$BULKHEAD_SEMAPHORE"
            return 0
        fi
        
        sleep 1
        ((waited++))
    done
    
    log "Bulkhead full - max concurrent executions reached" "ERROR"
    return 1
}

bulkhead_release() {
    local current=$(cat "$BULKHEAD_SEMAPHORE" 2>/dev/null || echo "0")
    echo $((current + 1)) > "$BULKHEAD_SEMAPHORE"
}

with_bulkhead() {
    bulkhead_acquire || return 1
    
    set +e
        "$@"
    local exit_code=$?
    set -e
    
    bulkhead_release
    return $exit_code
}

# =============================================================================
# Utility Functions
# =============================================================================

# Retry until success or timeout
# Usage: retry_until <timeout_seconds> <command...>
retry_until() {
    local timeout="$1"
    shift
    local start=$(date +%s)
    
    while true; do
        set +e
        "$@"
        local exit_code=$?
        set -e
        
        if (( exit_code == 0 )); then
            return 0
        fi
        
        local now=$(date +%s)
        if (( now - start >= timeout )); then
            log "Timeout reached after $timeout seconds" "ERROR"
            return 1
        fi
        
        sleep 1
    done
}

# Retry with custom check function
# Usage: retry_while <max_attempts> <check_command...>
retry_while() {
    local max_attempts="$1"
    shift
    local attempt=0
    
    while (( attempt < max_attempts )); do
        ((attempt++))
        
        set +e
        "$@"
        local exit_code=$?
        set -e
        
        if (( exit_code != 0 )); then
            return 0
        fi
        
        sleep 1
    done
    
    return 1
}

# =============================================================================
# Main (for testing)
# =============================================================================

main() {
    log "Retry Logic Module Loaded"
    log "Max Retries: $MAX_RETRIES"
    log "Initial Delay: $INITIAL_DELAY"
    log "Backoff Multiplier: $BACKOFF_MULTIPLIER"
    log "Max Delay: $MAX_DELAY"
    
    # If a command is provided, execute it with retry
    if (( $# > 0 )); then
        with_retry "$@"
    fi
}

# Run main only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
