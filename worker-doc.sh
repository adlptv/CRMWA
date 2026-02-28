#!/bin/bash
# Documentation Worker Script - Bash Version
# ===========================================
# Documentation generation and maintenance agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_ROOT"
LOG_DIR="$PROJECT_ROOT/logs"
SHUTDOWN_FLAG="$PROJECT_ROOT/shutdown.flag"
COMMIT_LOCK="$PROJECT_ROOT/commit.lock"
QUOTA_STATUS="$PROJECT_ROOT/quota.status"

WORKER_NAME="doc"
WORKER_PID="$PROJECT_ROOT/worker-$WORKER_NAME.pid"
WORKER_STATUS="$LOG_DIR/worker-$WORKER_NAME-status.txt"
WORKER_LOG="$LOG_DIR/worker-$WORKER_NAME.log"

MAX_ITERATIONS="${MAX_ITERATIONS:-100}"
ITERATION_DELAY="${ITERATION_DELAY:-45}"

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
# Documentation Analysis
# =============================================================================

find_source_files() {
    find "$PROJECT_ROOT" -type f \( \
        -name "*.py" -o -name "*.js" -o -name "*.ts" -o \
        -name "*.jsx" -o -name "*.tsx" -o -name "*.go" -o \
        -name "*.java" -o -name "*.cs" \
    \) ! -path "*/node_modules/*" ! -path "*/venv/*" ! -path "*/__pycache__/*" ! -path "*/.git/*" ! -path "*/test/*"
}

has_documentation() {
    local file="$1"
    local content=$(cat "$file" 2>/dev/null)
    
    # Check for doc patterns
    if echo "$content" | grep -qE '""".*?"""'; then return 0; fi
    if echo "$content" | grep -qE "'''.*?'''"; then return 0; fi
    if echo "$content" | grep -qE '/\*\*[\s\S]*?\*/'; then return 0; fi
    if echo "$content" | grep -qE '///'; then return 0; fi
    if echo "$content" | grep -qE '@param|@returns|@arg'; then return 0; fi
    
    return 1
}

count_functions() {
    local file="$1"
    local content=$(cat "$file" 2>/dev/null)
    
    local count=0
    count=$((count + $(echo "$content" | grep -cE 'function\s+\w+' || echo 0)))
    count=$((count + $(echo "$content" | grep -cE 'def\s+\w+' || echo 0)))
    count=$((count + $(echo "$content" | grep -cE 'func\s+\w+' || echo 0)))
    count=$((count + $(echo "$content" | grep -cE 'const\s+\w+\s*=\s*\(' || echo 0)))
    
    echo "$count"
}

run_documentation_analysis() {
    log "Running documentation analysis..."
    
    local total_files=0
    local undocumented=0
    local total_functions=0
    local documented_functions=0
    
    while IFS= read -r file; do
        if check_shutdown_flag; then break; fi
        
        ((total_files++))
        local func_count=$(count_functions "$file")
        total_functions=$((total_functions + func_count))
        
        if has_documentation "$file"; then
            documented_functions=$((documented_functions + func_count))
        elif (( func_count > 0 )); then
            ((undocumented++))
            log "Undocumented: $file ($func_count functions)"
        fi
    done < <(find_source_files)
    
    local coverage=0
    if (( total_functions > 0 )); then
        coverage=$((documented_functions * 100 / total_functions))
    fi
    
    log "Documentation coverage: ${coverage}%"
    log "Undocumented files: $undocumented"
    
    echo "$coverage:$undocumented"
}

check_readme_exists() {
    [[ -f "README.md" ]] || [[ -f "readme.md" ]] || [[ -f "README.txt" ]]
}

create_readme_template() {
    if check_readme_exists; then
        log "README already exists"
        return
    fi
    
    cat > README.md << 'EOF'
# Project Name

## Description
Brief description of the project.

## Installation

```bash
# Installation instructions
```

## Usage

```bash
# Usage examples
```

## API Reference

### Main Functions

#### `functionName(param1, param2)`
Description of the function.

**Parameters:**
- `param1` (type): Description
- `param2` (type): Description

**Returns:**
- type: Description

## Contributing

Contributions are welcome!

## License

MIT License
EOF
    
    log "Created README.md template" "SUCCESS"
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
    log "Starting doc worker loop..."
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
        
        if ! check_readme_exists; then
            log "README.md not found, creating template"
            create_readme_template
        fi
        
        run_documentation_analysis
        
        git_commit "Documentation updates from iteration $iteration"
        
        update_status "waiting"
        sleep "$ITERATION_DELAY"
    done
    
    update_status "completed"
    log "Doc worker completed"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "============================================"
    log "Documentation Worker Starting"
    log "============================================"
    log "PID: $$"
    
    mkdir -p "$LOG_DIR"
    save_pid
    update_status "initializing"
    
    trap 'log "Worker interrupted"; update_status "interrupted"; exit 0' INT TERM
    
    worker_loop
    
    log "Documentation Worker Exiting"
}

main "$@"
