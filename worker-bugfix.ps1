#!/usr/bin/env pwsh
# Bugfix Worker Script - PowerShell Version
# ==========================================
# Automated bug detection and fixing agent

param(
    [string]$Config = "iflow-bugfix.yaml",
    [int]$MaxIterations = 100,
    [int]$IterationDelay = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = $SCRIPT_DIR
$LOG_DIR = Join-Path $PROJECT_ROOT "logs"
$CONFIG_FILE = Join-Path $PROJECT_ROOT $Config
$SHUTDOWN_FLAG = Join-Path $PROJECT_ROOT "shutdown.flag"
$COMMIT_LOCK = Join-Path $PROJECT_ROOT "commit.lock"
$QUOTA_STATUS = Join-Path $PROJECT_ROOT "quota.status"

$WORKER_NAME = "bugfix"
$WORKER_PID = Join-Path $PROJECT_ROOT "worker-$WORKER_NAME.pid"
$WORKER_STATUS = Join-Path $LOG_DIR "worker-$WORKER_NAME-status.txt"
$WORKER_LOG = Join-Path $LOG_DIR "worker-$WORKER_NAME.log"

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$WORKER_NAME] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    Add-Content -Path $WORKER_LOG -Value $logMessage
}

# =============================================================================
# State Management
# =============================================================================

function Save-Pid {
    $PID | Out-File -FilePath $WORKER_PID
}

function Update-Status {
    param([string]$Status)
    $Status | Out-File -FilePath $WORKER_STATUS
}

function Test-ShutdownFlag {
    return Test-Path $SHUTDOWN_FLAG
}

function Test-CommitLock {
    try {
        if (-not (Test-Path $COMMIT_LOCK)) { return $false }
        
        # Try to read with file share mode
        $content = [System.IO.File]::ReadAllText($COMMIT_LOCK)
        $matches = @{}  # Initialize matches
        if ($content -match "PID=(\d+)") {
            $lockPid = $matches[1]
            $process = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if (-not $process) {
                # Lock is stale, clear it
                [System.IO.File]::Delete($COMMIT_LOCK)
                return $false
            }
        }
        return $true
    } catch {
        # File is locked by another process, wait a bit
        Start-Sleep -Milliseconds 100
        return Test-Path $COMMIT_LOCK
    }
}

function Set-CommitLock {
    $retries = 0
    while ($retries -lt 5) {
        try {
            $content = "PID=$PID`nWORKER=$WORKER_NAME`nTIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            [System.IO.File]::WriteAllText($COMMIT_LOCK, $content)
            return
        } catch {
            $retries++
            Start-Sleep -Milliseconds 200
        }
    }
}

function Clear-CommitLock {
    try {
        if (Test-Path $COMMIT_LOCK) {
            $content = [System.IO.File]::ReadAllText($COMMIT_LOCK)
            if ($content -match "PID=$PID") {
                [System.IO.File]::Delete($COMMIT_LOCK)
            }
        }
    } catch {
        # Ignore errors when clearing lock
    }
}

function Get-QuotaPercentage {
    if (-not (Test-Path $QUOTA_STATUS)) {
        return 100
    }
    try {
        $content = Get-Content $QUOTA_STATUS -Raw | ConvertFrom-Json
        return $content.Percentage
    } catch {
        return 100
    }
}

# =============================================================================
# Bug Detection Functions
# =============================================================================

function Find-SourceFiles {
    param([string]$Pattern = "*.py")
    
    $extensions = @("*.py", "*.js", "*.ts", "*.jsx", "*.tsx", "*.go", "*.java", "*.cs")
    $files = @()
    
    foreach ($ext in $extensions) {
        $found = Get-ChildItem -Path $PROJECT_ROOT -Filter $ext -Recurse -ErrorAction SilentlyContinue | 
            Where-Object { $_.FullName -notmatch "node_modules|venv|__pycache__|\.git" }
        $files += $found
    }
    
    return $files
}

function Search-ErrorPatterns {
    param([string]$FilePath)
    
    $errorPatterns = @(
        "try\s*\{[^}]*\}\s*catch\s*\(\s*\)",
        "except\s*:",
        "catch\s*\(\s*\.\.\.\s*\)",
        "//\s*TODO.*bug",
        "#\s*TODO.*bug",
        "FIXME",
        "HACK",
        "XXX"
    )
    
    $issues = @()
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    
    if ($content) {
        foreach ($pattern in $errorPatterns) {
            $matches = [regex]::Matches($content, $pattern, "IgnoreCase")
            foreach ($match in $matches) {
                $issues += @{
                    Pattern = $pattern
                    Line = $match.Index
                    Match = $match.Value
                }
            }
        }
    }
    
    return $issues
}

function Invoke-BugAnalysis {
    Write-Log "Starting bug analysis..."
    
    $files = @(Find-SourceFiles)
    Write-Log "Found $($files.Count) source files to analyze"
    
    $bugReport = @()
    
    foreach ($file in $files) {
        if (Test-ShutdownFlag) {
            Write-Log "Shutdown detected, aborting analysis" "WARN"
            break
        }
        
        $issues = @(Search-ErrorPatterns -FilePath $file.FullName)
        if ($issues.Count -gt 0) {
            $bugReport += @{
                File = $file.FullName
                Issues = $issues
            }
        }
    }
    
    return $bugReport
}

# =============================================================================
# iFlow Integration
# =============================================================================

function Invoke-iFlowAgent {
    param(
        [string]$Prompt,
        [string]$Mode = "thinking"
    )
    
    Write-Log "Invoking iFlow agent with mode: $Mode"
    
    # Build iFlow command
    $iflowArgs = @(
        "--model", "glm-5",
        "--mode", $Mode,
        "--prompt", $Prompt
    )
    
    try {
        $result = & iflow @iflowArgs 2>&1
        return $result
    } catch {
        Write-Log "iFlow invocation failed: $_" "ERROR"
        return $null
    }
}

# =============================================================================
# Git Operations
# =============================================================================

function New-GitCommit {
    param(
        [string]$Message,
        [string]$Branch = "ai-dev"
    )
    
    # Check quota before commit
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) {
        Write-Log "Quota critical ($quota%), skipping commit" "WARN"
        return $false
    }
    
    # Wait for commit lock
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) {
        Start-Sleep -Seconds 1
        $waitCount++
    }
    
    if (Test-CommitLock) {
        Write-Log "Commit lock held by another worker, skipping" "WARN"
        return $false
    }
    
    # Acquire lock
    Set-CommitLock
    
    try {
        # Stage changes
        git add -A
        
        # Commit
        git commit -m "[$WORKER_NAME] $Message"
        
        Write-Log "Committed: $Message" "SUCCESS"
        return $true
    } catch {
        Write-Log "Commit failed: $_" "ERROR"
        return $false
    } finally {
        Clear-CommitLock
    }
}

function Sync-GitPull {
    param(
        [string]$Branch = "ai-dev"
    )
    
    # Check quota
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) {
        Write-Log "Quota critical ($quota%), skipping pull" "WARN"
        return $false
    }
    
    # Wait for commit lock
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) {
        Start-Sleep -Seconds 1
        $waitCount++
    }
    
    if (Test-CommitLock) {
        Write-Log "Commit lock held, skipping pull" "WARN"
        return $false
    }
    
    Set-CommitLock
    
    try {
        # Fetch latest
        git fetch origin
        
        # Check for remote branch
        $remoteBranch = git branch -r --list "origin/$Branch"
        if (-not $remoteBranch) {
            Write-Log "Remote branch origin/$Branch not found, skipping pull" "WARN"
            return $true
        }
        
        # Clean up temporary files before pull
        git checkout --ours commit.lock *.pid logs/ 2>$null
        git reset HEAD commit.lock *.pid logs/ 2>$null
        git checkout -- commit.lock *.pid logs/ 2>$null
        
        # Pull with rebase
        git pull --rebase origin $Branch 2>$null
        
        # Clean up any merge conflict markers in commit.lock
        if (Test-Path $COMMIT_LOCK) {
            $content = [System.IO.File]::ReadAllText($COMMIT_LOCK)
            if ($content -match "<<<<<<|======|>>>>>>") {
                [System.IO.File]::Delete($COMMIT_LOCK)
            }
        }
        
        Write-Log "Pulled latest from origin/$Branch" "SUCCESS"
        return $true
    } catch {
        Write-Log "Pull failed: $_" "ERROR"
        return $false
    } finally {
        Clear-CommitLock
    }
}

function Sync-GitPush {
    param(
        [string]$Branch = "ai-dev"
    )
    
    # Check quota
    $quota = Get-QuotaPercentage
    if ($quota -lt 10) {
        Write-Log "Quota critical ($quota%), skipping push" "WARN"
        return $false
    }
    
    # Wait for commit lock
    $waitCount = 0
    while (Test-CommitLock -and $waitCount -lt 30) {
        Start-Sleep -Seconds 1
        $waitCount++
    }
    
    if (Test-CommitLock) {
        Write-Log "Commit lock held, skipping push" "WARN"
        return $false
    }
    
    Set-CommitLock
    
    try {
        # Push to remote (suppress stderr to avoid PowerShell errors)
        $output = git push origin $Branch 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Log "Pushed to origin/$Branch" "SUCCESS"
            return $true
        } else {
            # Try push with set-upstream if branch not tracked
            $output2 = git push -u origin $Branch 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Pushed and set upstream for $Branch" "SUCCESS"
                return $true
            }
            Write-Log "Push failed with exit code: $LASTEXITCODE" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Push failed: $_" "ERROR"
        return $false
    } finally {
        Clear-CommitLock
    }
}

# =============================================================================
# Main Worker Loop
# =============================================================================

function Invoke-WorkerLoop {
    Write-Log "Starting worker loop..."
    Update-Status "running"
    
    $iteration = 0
    
    while ($iteration -lt $MaxIterations) {
        $iteration++
        Write-Log "=== Iteration $iteration/$MaxIterations ==="
        
        # Check for shutdown flag
        if (Test-ShutdownFlag) {
            Write-Log "Shutdown flag detected, exiting gracefully" "WARN"
            Update-Status "shutdown"
            Save-State
            return
        }
        
        # Check quota
        $quota = Get-QuotaPercentage
        if ($quota -lt 10) {
            Write-Log "Quota critical ($quota%), pausing..." "WARN"
            Start-Sleep -Seconds 60
            continue
        }
        
        # Pull latest changes from remote
        Write-Log "Pulling latest changes from remote..."
        Sync-GitPull
        
        # Update heartbeat
        Update-Status "analyzing"
        
        # Run bug analysis
        $bugs = Invoke-BugAnalysis
        Write-Log "Found $($bugs.Count) files with potential issues"
        
        if ($bugs.Count -gt 0) {
            Update-Status "fixing"
            
            # Process each bug
            foreach ($bug in $bugs) {
                if (Test-ShutdownFlag) { break }
                
                Write-Log "Processing: $($bug.File)"
                
                # Generate fix prompt for iFlow
                $prompt = @"
Analyze and fix potential bugs in the following code:

File: $($bug.File)
Issues found: $($bug.Issues.Count)

Please provide a detailed fix for each issue.
"@
                
                $fix = Invoke-iFlowAgent -Prompt $prompt -Mode "thinking"
                
                if ($fix) {
                    Write-Log "Generated fix for $($bug.File)"
                }
            }
            
            # Commit changes
            $committed = New-GitCommit -Message "Bug fixes from analysis iteration $iteration"
            
            # Push changes to remote after commit
            if ($committed) {
                Write-Log "Pushing changes to remote..."
                Sync-GitPush
            }
        }
        
        Update-Status "waiting"
        
        # Sleep before next iteration
        Start-Sleep -Seconds $IterationDelay
    }
    
    Update-Status "completed"
    Write-Log "Worker loop completed"
}

function Save-State {
    $stateFile = Join-Path $LOG_DIR "worker-$WORKER_NAME-state.json"
    $state = @{
        Worker = $WORKER_NAME
        PID = $PID
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Status = "shutdown"
    }
    $state | ConvertTo-Json | Out-File $stateFile
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    Write-Log "============================================"
    Write-Log "Bugfix Worker Starting"
    Write-Log "============================================"
    Write-Log "PID: $PID"
    Write-Log "Config: $Config"
    Write-Log "Max Iterations: $MaxIterations"
    
    # Ensure log directory exists
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
    }
    
    # Save PID
    Save-Pid
    
    # Update status
    Update-Status "initializing"
    
    # Run worker loop
    try {
        Invoke-WorkerLoop
    } catch {
        Write-Log "Worker error: $_" "ERROR"
        Update-Status "error"
    }
    
    Write-Log "Bugfix Worker Exiting"
}

Main
